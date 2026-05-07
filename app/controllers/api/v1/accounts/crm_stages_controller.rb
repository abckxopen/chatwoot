# [2026-05-07] REST controller for Holding::Crm::Stage, nested under crm_pipelines.
# Defesa em camadas é a mesma do CrmPipelinesController (gate por conta + Pundit
# + tenancy scope + strong params + model validations) — ver header lá pro racional.
# Slice-2 specifics: action #reorder + tenant fetch nested via @pipeline.
#
# TODO(slice-3): extrair ensure_feature_enabled + tenant scope pra
# `Holding::Crm::ControllerConcern` quando 3º controller (Companies/Opportunities)
# replicar o padrão. Não fizemos agora pra evitar abstração com 1 caller.
class Api::V1::Accounts::CrmStagesController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :fetch_pipeline
  before_action :check_authorization, only: %i[index create reorder]
  before_action :fetch_stage, only: %i[update destroy]

  def index
    @stages = @pipeline.stages.ordered
  end

  def create
    @stage = @pipeline.stages.new(stage_params.merge(account_id: Current.account.id))
    @stage.save!
    render :show, status: :created
  end

  def update
    @stage.update!(stage_params)
    render :show
  end

  def destroy
    if @stage.destroy
      head :no_content
    else
      render json: { errors: @stage.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /crm_pipelines/:pipeline_id/stages/reorder
  # Body: { stage_ids: [42, 17, 8, ...] } — nova ordem (index 0 = top)
  def reorder
    ids = Array(params[:stage_ids]).map(&:to_i).reject(&:zero?)
    return render(json: { error: 'stage_ids required' }, status: :bad_request) if ids.empty?

    Holding::Crm::Stage.update_positions_for_pipeline!(pipeline: @pipeline, ordered_ids: ids)
    @stages = @pipeline.stages.ordered
    render :index
  rescue ArgumentError => e
    render json: { error: e.message }, status: :bad_request
  end

  private

  def fetch_pipeline
    # [2026-05-07] Scope explícito por Current.account — defesa contra vazar
    # pipeline de outra conta. find raise RecordNotFound → 404.
    @pipeline = Holding::Crm::Pipeline.where(account_id: Current.account.id).find(params[:crm_pipeline_id])
  end

  def fetch_stage
    @stage = @pipeline.stages.find(params[:id])
    authorize(@stage, "#{action_name}?".to_sym)
  end

  def check_authorization
    authorize(Holding::Crm::Stage, "#{action_name}?".to_sym)
  end

  # [2026-05-07] matrix_task_template permit list explícita (em vez de hash
  # aberto `{}`). Schema documentado em migration 045001 + factory trait
  # `:with_matrix_template`. Restringir aqui evita client jogar 10MB jsonb
  # arbitrário no DB e bloqueia typos silenciosos em chaves não-suportadas.
  # Adicionar chave nova aqui quando adicionar no listener (Phase 2).
  def stage_params
    params.require(:crm_stage).permit(
      :name, :position, :color, :won, :lost,
      matrix_task_template: %i[enabled board_id title_template description_template priority]
    )
  end

  def ensure_feature_enabled
    return if Current.account.holding_crm_enabled?

    render json: { error: I18n.t('errors.crm.feature_disabled') }, status: :forbidden
  end
end
