# [2026-05-07] Controller REST pra Holding::Crm::Opportunity — coração do CRM.
# Defesa em camadas mesma das slices 1-3 (ver CrmPipelinesController header).
# Específico desta slice: policy DIVERGE com gate por assignee, member actions
# #move_to_stage (delega pro model) e #discard (soft-delete).
# Filtros do index são manuais — sift gem fica pra Phase 4 se UI exigir.
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

  # [2026-05-07] Filtros básicos. status, pipeline_id, stage_id, assignee_id,
  # plus include_discarded flag. Eager loading apenas das relações embeddadas
  # (stage/pipeline/company); assignee_id e contact_id saem scalar FK.
  #
  # AbcSize 32/26 desligado: filtros são lineares e auto-explicativos inline.
  # Convenção do chatwoot upstream usa essa shape (live_reports_controller etc).
  # Map-de-filtros foi tentado mas atrapalha grep da coluna AR (cherry-pick hygiene).
  def filtered_scope # rubocop:disable Metrics/AbcSize
    scope = opportunities_scope.includes(:stage, :pipeline, :company)
    scope = scope.active unless params[:include_discarded].to_s == 'true'
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(crm_pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?
    scope = scope.where(crm_stage_id: params[:stage_id]) if params[:stage_id].present?
    scope = scope.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
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
