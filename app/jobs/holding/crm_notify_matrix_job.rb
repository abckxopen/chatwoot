# [2026-05-07 abckxopen-fork] Slice 2.2 — integração CRM → Matrix one-way.
#
# Erro semântica (importa pra Sidekiq retries):
# - ClientError (4xx) + ArgumentError (config faltando): fatal, discard.
#   Retry não resolve — alguém precisa investigar.
# - ServerError (5xx + transport): transitório. retry com backoff exp.
#
# Idempotência: marker `[stage:N]` no subject da Activity, query LIKE
# em janela 1h. Inline em vez de coluna FK pra evitar migration nessa
# slice; trade-off é query LIKE em vez de index, aceitável dado que
# crm_activities filtra primeiro por crm_opportunity_id (FK index hits)
# e o slice de rows por opp é pequeno (~tens). Se opps virarem log de
# centenas+ activities, follow-up adiciona crm_stage_id+index.
#
# Liquid render é fatal-on-error: template malformado é config bug,
# enviar `{{ unclosed }}` literal pro Matrix corrompe a task. Raise
# como ClientError → discard.
class Holding::CrmNotifyMatrixJob < ApplicationJob
  queue_as :default

  IDEMPOTENCY_WINDOW = 1.hour

  FATAL_ERRORS = [
    Holding::Crm::MatrixApiClient::ClientError,
    ArgumentError
  ].freeze

  discard_on(*FATAL_ERRORS) do |job, error|
    Rails.logger.error(
      job: 'Holding::CrmNotifyMatrixJob',
      event: 'crm.matrix.notify.fatal_discarded',
      error_class: error.class.name,
      error: error.message,
      args: job.arguments
    )
  end

  retry_on Holding::Crm::MatrixApiClient::ServerError, attempts: 5, wait: :polynomially_longer

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
    log_success(opportunity, stage, matrix_task_id)
  end

  private

  def template_enabled?(template)
    template.present? && template['enabled'] && template['board_id'].present?
  end

  def subject_marker(stage)
    "[stage:#{stage.id}]"
  end

  def recently_notified?(opportunity, stage)
    Holding::Crm::Activity
      .where(crm_opportunity_id: opportunity.id)
      .where('subject LIKE ?', "%#{subject_marker(stage)}%")
      .exists?(created_at: IDEMPOTENCY_WINDOW.ago..)
  end

  def build_payload(opportunity, stage, template)
    context = liquid_context(opportunity, stage)
    title_tpl = template['title_template'].presence || 'CRM: acompanhar {{opportunity.name}}'
    {
      title: render_template(title_tpl, context),
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
    # Config bug — não enviar literal `{{...}}` pro Matrix. Raise como
    # ClientError pra ser tratado fatal-discard junto com 4xx.
    raise Holding::Crm::MatrixApiClient::ClientError, "liquid render failed: #{e.message}"
  end

  def persist_activity!(opportunity, stage, matrix_task_id)
    Holding::Crm::Activity.create!(
      account_id: opportunity.account_id,
      crm_opportunity_id: opportunity.id,
      kind: :task,
      subject: "Matrix task #{subject_marker(stage)} — Stage: #{stage.name}",
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

  def log_success(opportunity, stage, matrix_task_id)
    Rails.logger.info(
      job: 'Holding::CrmNotifyMatrixJob',
      event: 'crm.matrix.notify.success',
      opportunity_id: opportunity.id,
      stage_id: stage.id,
      matrix_task_id: matrix_task_id
    )
  end

  def api_client
    @api_client ||= Holding::Crm::MatrixApiClient.new
  end
end
