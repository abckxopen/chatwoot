# [2026-04-30] Controller REST pra Holding::Crm::Pipeline. Padrão Chatwoot:
# herda Api::V1::Accounts::BaseController (Current.account thread-local
# injetado por before_action :current_account) + Pundit pra autorização.
#
# Defesa em camadas (regra Founder msg 308 "sem gambiarras e seguro"):
# 1. Feature flag gate (`crm_pipeline`) — 403 se conta não tem feature
# 2. Pundit policy — 403 se role não tem permissão
# 3. Scope explícito por Current.account em TODA query — defesa contra
#    bug que esqueça account_id; cross-tenant exfil é o risco principal
# 4. Strong params com permit list rígida — não confia em parâmetro
#    que vem do client
# 5. Validações de model (Pipeline) rodam de novo, gerando 422 com
#    errors granulares
class Api::V1::Accounts::CrmPipelinesController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :check_authorization
  before_action :fetch_pipeline, only: %i[show update destroy]

  def index
    pipelines = pipelines_scope.defaults_first
    @pipelines = pipelines.page(params[:page]).per(per_page)
    @total_count = pipelines.count
  end

  def show; end

  def create
    @pipeline = pipelines_scope.new(pipeline_params)
    @pipeline.save!
    render :show, status: :created
  end

  def update
    @pipeline.update!(pipeline_params)
    render :show
  end

  def destroy
    @pipeline.destroy!
    head :no_content
  end

  private

  # [2026-04-30] Ponto único de scope multi-tenant. Todas as queries do
  # controller passam por aqui. Mudar pra `Holding::Crm::Pipeline.where(...)`
  # direto é correto também, mas centralizar simplifica auditoria.
  def pipelines_scope
    @pipelines_scope ||= Holding::Crm::Pipeline.where(account_id: Current.account.id)
  end

  def fetch_pipeline
    @pipeline = pipelines_scope.find(params[:id])
    authorize(@pipeline, "#{action_name}?".to_sym)
  end

  def check_authorization
    authorize(Holding::Crm::Pipeline, "#{action_name}?".to_sym)
  end

  # [2026-04-30] Strong params: aceita só atributos editáveis. Trocar
  # ABSOLUTAMENTE EVITAR `params.require(:crm_pipeline).permit!` que
  # liberaria account_id, id, timestamps — vetor de mass-assignment.
  def pipeline_params
    params.require(:crm_pipeline).permit(:name, :description, :default_pipeline, :position)
  end

  def ensure_feature_enabled
    return if Current.account.feature_enabled?(:crm_pipeline)

    render json: { error: I18n.t('errors.crm.feature_disabled') }, status: :forbidden
  end

  # [2026-04-30] per_page com clamp 1..100 — evita client pedir page=1, per=999999
  # e sobrecarregar DB. Default 25 alinhado com convenção Chatwoot.
  def per_page
    [[(params[:per_page] || 25).to_i, 1].max, 100].min
  end
end
