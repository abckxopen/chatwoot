# [2026-05-07] Controller REST pra Holding::Crm::Company. Padrão consistente
# com Pipelines/Stages: HoldingCrmConcern faz o gate por conta, Pundit autoriza,
# tenancy scope explícito por Current.account em toda query.
#
# Show retorna company com `opportunities_count` (count das opps que apontam
# pra essa company via crm_company_id). Listagem de contacts vinculados (via
# Contact#additional_attributes['crm_company_id']) fica pra v2 — exige scan
# de jsonb que não vale o esforço sem index. Phase 4 UI puxa contacts por
# query separada quando precisar.
class Api::V1::Accounts::CrmCompaniesController < Api::V1::Accounts::BaseController
  include HoldingCrmConcern

  before_action :check_authorization, only: %i[index create]
  before_action :fetch_company, only: %i[show update destroy]

  def index
    # [2026-05-07] Eager count opportunities via left_join + group em vez
    # de `company.opportunities.size` na jbuilder (que dispara N+1: 1 query
    # extra por company). Postgres usa idx_crm_opportunities_company pra
    # group rapidamente. counter_cache seria overkill (migration + writer
    # hooks). Resultado vem em company.opportunities_count_aggr (alias evita
    # colisão com any future column real).
    @current_page = page_param
    @companies = companies_scope
                 .left_joins(:opportunities)
                 .group('crm_companies.id')
                 .select('crm_companies.*, COUNT(crm_opportunities.id) AS opportunities_count_aggr')
                 .order('crm_companies.name ASC')
                 .page(@current_page).per(per_page)
  end

  def show; end

  def create
    @company = companies_scope.new(company_params)
    @company.save!
    render :show, status: :created
  end

  def update
    @company.update!(company_params)
    render :show
  end

  def destroy
    if @company.destroy
      head :no_content
    else
      # has_many :opportunities, dependent: :nullify — destroy NÃO deve falhar
      # por isso. Errors aqui só vêm de validações futuras (ex: hook que rejeita).
      render json: { errors: @company.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def companies_scope
    @companies_scope ||= Holding::Crm::Company.where(account_id: Current.account.id)
  end

  def fetch_company
    @company = companies_scope.find(params[:id])
    authorize(@company, "#{action_name}?".to_sym)
  end

  def check_authorization
    authorize(Holding::Crm::Company, "#{action_name}?".to_sym)
  end

  # [2026-05-07] additional_attributes permit list aberta `{}` (não restritiva
  # como Stage.matrix_task_template) porque é por-design o "saco de atributos
  # custom" da company — cada vila adiciona campos sem migration. Cap de
  # tamanho (16KB) é validação de model em Holding::Crm::Company —
  # ADDITIONAL_ATTRIBUTES_MAX_BYTES — pra bloquear bloat malicioso.
  def company_params
    params.require(:crm_company).permit(:name, :domain, :industry, :size, additional_attributes: {})
  end

end
