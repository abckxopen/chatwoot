# [2026-05-07] Controller REST pra Holding::Crm::Opportunity — coração do CRM.
# Adiciona às actions REST padrão: #move_to_stage e #discard (member actions).
#
# Defesa em camadas mesma das slices 1-3 — ver header de CrmPipelinesController.
# Diferenças importantes desta slice:
# - Policy DIVERGE de Pipeline/Stage/Company: agentes podem criar opps e
#   atualizar/mover SUAS opps (assignee_id == current user). Admin tem tudo.
#   Esse é o ponto que a Pipeline header anchora ("opportunities individuais
#   terão filtro por assignee mais granular").
# - Filtros básicos no index (status, pipeline_id, stage_id, assignee_id).
#   Não usei gem `sift` ainda porque MVP — fica pra Phase 4 se UI exigir.
# - move_to_stage delega pro model (#move_to_stage!) que valida pipeline
#   match + auto-aplica won/lost se a stage destino é marker.
class Api::V1::Accounts::CrmOpportunitiesController < Api::V1::Accounts::BaseController
  include HoldingCrmConcern

  before_action :check_authorization, only: %i[index create]
  before_action :fetch_opportunity, only: %i[show update destroy move_to_stage discard]

  def index
    @current_page = page_param
    @opportunities = filtered_scope.page(@current_page).per(per_page)
  end

  def show; end

  def create
    @opportunity = opportunities_scope.new(opportunity_params)
    @opportunity.save!
    render :show, status: :created
  end

  def update
    @opportunity.update!(opportunity_params)
    render :show
  end

  # [2026-05-07] destroy! (bang) em vez do `if @opp.destroy / else render`
  # de slice 1-3. Pipeline/Stage têm `dependent: :restrict_with_error`
  # (falha amigável se há filhos). Opportunity tem `dependent: :destroy_async`
  # nas activities — não pode falhar ao nível AR síncrono. Inconsistência
  # no shape entre slices é justificada pela semântica do dependent.
  def destroy
    @opportunity.destroy!
    head :no_content
  end

  # PATCH /crm_opportunities/:id/move_to_stage
  # Body: { stage_id: N, reason: '...' (optional) }
  def move_to_stage
    new_stage = Holding::Crm::Stage.where(account_id: Current.account.id).find_by(id: params[:stage_id])
    return render(json: { error: 'stage_id required and must belong to the same account' }, status: :bad_request) if new_stage.nil?

    @opportunity.move_to_stage!(new_stage)
    @opportunity.update!(lost_reason: params[:reason]) if params[:reason].present? && @opportunity.lost?
    render :show
  rescue ArgumentError => e
    render json: { error: e.message }, status: :bad_request
  end

  # PATCH /crm_opportunities/:id/discard — soft-delete via discarded_at
  def discard
    @opportunity.discard!
    render :show
  end

  private

  def opportunities_scope
    @opportunities_scope ||= Holding::Crm::Opportunity.where(account_id: Current.account.id)
  end

  # [2026-05-07] Filtros básicos. status (open/won/lost), pipeline_id,
  # stage_id, assignee_id, plus active_only flag (default true) pra esconder
  # discarded. Eager loading apenas das relações que o jbuilder embeda
  # (stage/pipeline/company); assignee_id e contact_id saem como scalar
  # FK no payload — sem dereferência, sem includes.
  #
  # Filter map: param name → coluna AR. Cada chave aplicada via where se
  # presente. Mapping explícito porque pipeline_id/stage_id no client viram
  # crm_pipeline_id/crm_stage_id no schema.
  FILTER_PARAM_TO_COLUMN = {
    status: :status,
    pipeline_id: :crm_pipeline_id,
    stage_id: :crm_stage_id,
    assignee_id: :assignee_id
  }.freeze

  def filtered_scope
    scope = opportunities_scope.includes(:stage, :pipeline, :company)
    scope = scope.active unless params[:include_discarded].to_s == 'true'
    FILTER_PARAM_TO_COLUMN.each do |param_key, column|
      scope = scope.where(column => params[param_key]) if params[param_key].present?
    end
    scope.order(created_at: :desc)
  end

  def fetch_opportunity
    @opportunity = opportunities_scope.find(params[:id])
    authorize(@opportunity, "#{action_name}?".to_sym)
  end

  def check_authorization
    authorize(Holding::Crm::Opportunity, "#{action_name}?".to_sym)
  end

  # [2026-05-07] Strong params:
  # - Tenant-tied keys (account_id, id) e timestamps gerenciados (won_at,
  #   lost_at, discarded_at) ficam fora — auto-aplicados via callbacks/
  #   lifecycle do model.
  # - `:status` removido da permit list intencionalmente. Mudança de status
  #   ÚNICA via move_to_stage (que valida que stage destino é won/lost
  #   marker). Sem isso, agente PATCHa status=won sem mover stage e gera
  #   inconsistência (opp.status=won, stage.won=false → kanban quebra,
  #   reports filtram errado).
  def opportunity_params
    params.require(:crm_opportunity).permit(
      :name, :description, :value, :currency, :expected_close_date, :probability,
      :source, :lost_reason,
      :crm_pipeline_id, :crm_stage_id, :crm_company_id, :contact_id, :assignee_id,
      custom_attributes: {}
    )
  end
end
