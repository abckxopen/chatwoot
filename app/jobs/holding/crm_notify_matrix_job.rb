# [2026-05-07 abckxopen-fork] Slice 2.2 — implementação real da integração
# CRM → Matrix. Substitui stub do slice 2.1.
#
# Fluxo:
#   1. Carrega opp + stage. Sai cedo se template ausente/disabled (defesa
#      a mais; listener já gateava — segurança extra contra mudança de
#      ordem ou re-enfileiramento manual).
#   2. Idempotência (ver "Idempotência" abaixo): no-op se já criamos
#      task pra esse (opp, stage) em janela recente.
#   3. Renderiza title/description via Liquid com contexto (opp + stage).
#   4. POST Matrix /boards/{board_id}/tasks via MatrixApiClient.
#   5. Persiste Holding::Crm::Activity (kind: :task, matrix_task_id) — é
#      a representação visível no CRM da holding ("Auto-criada quando
#      opp entrou na stage X").
#
# Erro semântica (importa pra Sidekiq retries):
# - ClientError (4xx Matrix API): fatal. discard_on. Indica config errada
#   (board_id inexistente, token revogado, payload inválido). Retry não
#   vai resolver — alguém precisa olhar.
# - ServerError (5xx + transport): transitório. retry_on com backoff
#   exponencial. Matrix indisponível volta sozinho.
# - StandardError genérico: re-raise (Sidekiq aplica retry padrão).
#
# Idempotência:
# Pesquisa Holding::Crm::Activity onde subject contém marcador
# "[stage:<stage_id>]" pra mesma opp em janela IDEMPOTENCY_WINDOW.
# Marcador inline em vez de coluna FK (crm_stage_id) pra evitar migration
# nessa slice; trade-off: query LIKE em vez de index — aceitável dado
# que crm_activities é particionada por opp_id (idx_crm_activities_opp_due
# já filtra). Se virar gargalo, follow-up adiciona crm_stage_id+index.
#
# Por que rendering com Liquid (e não Mustache/gsub manual):
# - Chatwoot já usa Liquid (canned responses, automation rules).
# - Liquid sandboxa execução, não permite eval/code injection.
# - Sintaxe `{{opportunity.name}}` familiar pra agentes.
class Holding::CrmNotifyMatrixJob < ApplicationJob
  queue_as :default

  IDEMPOTENCY_WINDOW = 1.hour
  IDEMPOTENCY_MARKER = '[stage:%<stage_id>d]'.freeze

  # 4xx fatal — não tenta de novo. Alguém precisa investigar.
  discard_on Holding::Crm::MatrixApiClient::ClientError do |job, error|
    Rails.logger.error(
      job: 'Holding::CrmNotifyMatrixJob',
      event: 'crm.matrix.notify.client_error_discarded',
      error: error.message,
      args: job.arguments
    )
  end

  # ConfigError = MATRIX_API_TOKEN ausente ou board_id vazio na config
  # do stage. Fatal. Alguém precisa setar a env var ou consertar config.
  discard_on Holding::Crm::MatrixApiClient::ConfigError do |job, error|
    Rails.logger.error(
      job: 'Holding::CrmNotifyMatrixJob',
      event: 'crm.matrix.notify.config_error_discarded',
      error: error.message,
      args: job.arguments
    )
  end

  # 5xx + transport: backoff exponencial, 5 tentativas (Sidekiq default
  # ~3min/15min/.../21h). Após 5x, dead set — alerta humano.
  retry_on Holding::Crm::MatrixApiClient::ServerError, attempts: 5, wait: :exponentially_longer

  def perform(opportunity_id:, stage_id:)
    opportunity = Holding::Crm::Opportunity.find_by(id: opportunity_id)
    stage = Holding::Crm::Stage.find_by(id: stage_id)
    return log_skip(:not_found, opportunity_id, stage_id) unless opportunity && stage

    template = stage.matrix_task_template
    return log_skip(:template_disabled, opportunity_id, stage_id) unless template_enabled?(template)

    if recently_notified?(opportunity, stage)
      log_skip(:idempotent, opportunity_id, stage_id)
      return
    end

    payload = build_payload(opportunity, stage, template)
    result = api_client.create_task(board_id: template['board_id'], payload: payload)
    matrix_task_id = result['id']

    persist_activity!(opportunity, stage, matrix_task_id)

    Rails.logger.info(
      job: 'Holding::CrmNotifyMatrixJob',
      event: 'crm.matrix.notify.success',
      opportunity_id: opportunity.id,
      stage_id: stage.id,
      matrix_task_id: matrix_task_id
    )
  end

  private

  def template_enabled?(template)
    template.present? && template['enabled'] && template['board_id'].present?
  end

  def recently_notified?(opportunity, stage)
    marker = format(IDEMPOTENCY_MARKER, stage_id: stage.id)
    Holding::Crm::Activity
      .where(crm_opportunity_id: opportunity.id)
      .where('subject LIKE ?', "%#{marker}%")
      .where(created_at: IDEMPOTENCY_WINDOW.ago..)
      .exists?
  end

  def build_payload(opportunity, stage, template)
    context = liquid_context(opportunity, stage)
    {
      title: render_template(template['title_template'].presence || default_title, context),
      description: render_template(template['description_template'], context),
      priority: template['priority'].presence || 'medium',
      type: 'on-demand',
      requires_review: false
    }.compact
  end

  def liquid_context(opportunity, stage)
    {
      'opportunity' => {
        'id' => opportunity.id,
        'name' => opportunity.name,
        'value' => opportunity.value.to_s,
        'currency' => opportunity.currency
      },
      'stage' => {
        'id' => stage.id,
        'name' => stage.name
      }
    }
  end

  def render_template(template_str, context)
    return nil if template_str.blank?

    Liquid::Template.parse(template_str).render(context)
  rescue Liquid::Error => e
    # Template malformado não deve abortar notificação inteira; logamos
    # e usamos o template raw (vai aparecer com {{...}} literais — bug
    # visível em vez de silencioso).
    Rails.logger.warn(
      job: 'Holding::CrmNotifyMatrixJob',
      event: 'crm.matrix.notify.template_render_failed',
      error: e.message
    )
    template_str
  end

  def default_title
    'CRM: acompanhar {{opportunity.name}}'
  end

  def persist_activity!(opportunity, stage, matrix_task_id)
    marker = format(IDEMPOTENCY_MARKER, stage_id: stage.id)
    Holding::Crm::Activity.create!(
      account_id: opportunity.account_id,
      crm_opportunity_id: opportunity.id,
      kind: :task,
      subject: "Matrix task #{marker} — Stage: #{stage.name}",
      description: "Auto-criada por CrmNotifyMatrixJob quando opp entrou na stage #{stage.name}.",
      matrix_task_id: matrix_task_id
    )
  end

  def log_skip(reason, opportunity_id, stage_id)
    Rails.logger.info(
      job: 'Holding::CrmNotifyMatrixJob',
      event: 'crm.matrix.notify.skip',
      reason: reason,
      opportunity_id: opportunity_id,
      stage_id: stage_id
    )
  end

  def api_client
    @api_client ||= Holding::Crm::MatrixApiClient.new
  end
end
