# [2026-05-07] Controller REST pra Holding::Crm::Activity. Nested sob
# crm_opportunities — activity só faz sentido dentro de uma opp.
# Padrão consistente com slices anteriores (gate por conta + Pundit +
# tenant scope + strong params + validações model).
#
# Action especial #complete: marca completed_at = now, model dispara
# evento ACTIVITY_COMPLETED.
class Api::V1::Accounts::CrmActivitiesController < Api::V1::Accounts::BaseController
  include HoldingCrmConcern

  before_action :fetch_opportunity
  before_action :check_authorization, only: %i[index create]
  before_action :fetch_activity, only: %i[update destroy complete]

  def index
    @activities = @opportunity.activities.order(Arel.sql('due_at ASC NULLS LAST, id ASC'))
  end

  def create
    @activity = @opportunity.activities.new(activity_params.merge(account_id: Current.account.id))
    @activity.save!
    render :show, status: :created
  end

  def update
    @activity.update!(activity_params)
    render :show
  end

  def destroy
    @activity.destroy!
    head :no_content
  end

  # PATCH /crm_opportunities/:opp_id/activities/:id/complete
  # Body opcional: { completed_at: ISO8601 } — default Time.zone.now
  #
  # [2026-05-07] Time.zone.parse('') retorna nil em vez de raise — então
  # `present?` E o resultado-não-nil precisam ser checados pra evitar
  # `complete!` ser chamado com `at: nil`, que marcaria a activity como
  # ABERTA (silently un-completing) em vez de gerar erro.
  def complete
    completed_at = parse_completed_at(params[:completed_at])
    return render(json: { error: 'completed_at must be a valid ISO8601 timestamp' }, status: :bad_request) if completed_at.nil?

    @activity.complete!(at: completed_at)
    render :show
  end

  private

  def fetch_opportunity
    # [2026-05-07] Tenant scope explícito — find raise 404 pra opp de
    # outra conta (RecordNotFound → render_not_found via RequestExceptionHandler).
    @opportunity = Holding::Crm::Opportunity.where(account_id: Current.account.id).find(params[:crm_opportunity_id])
  end

  def fetch_activity
    @activity = @opportunity.activities.find(params[:id])
    authorize(@activity, "#{action_name}?".to_sym)
  end

  def check_authorization
    authorize(Holding::Crm::Activity, "#{action_name}?".to_sym)
  end

  # [2026-05-07] Strong params permit list:
  # - account_id e crm_opportunity_id ficam fora — derivados do scope.
  # - completed_at fica fora — fluxo único é via #complete (controle de
  #   evento ACTIVITY_COMPLETED). Permite ao agent edit subject/due_at/etc
  #   sem reabrir uma activity completada acidentalmente.
  # - matrix_task_id fica fora — setado pelo listener Matrix one-way (Phase 2).
  def activity_params
    params.require(:crm_activity).permit(:subject, :description, :kind, :due_at, :assignee_id)
  end

  # [2026-05-07] Distingue param missing (key ausente do hash → default Time.zone.now)
  # de param-blank (`''` ou whitespace → 400). Empty string como input
  # provavelmente é bug do client — preferível 400 explícito a silently
  # usar timestamp atual e mascarar o bug.
  def parse_completed_at(raw)
    return Time.zone.now if raw.nil?
    return nil if raw.blank?

    Time.zone.parse(raw)
  rescue ArgumentError
    nil
  end
end
