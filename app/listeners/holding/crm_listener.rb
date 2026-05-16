# [2026-05-07] Listener pra eventos do módulo CRM da holding.
# Singleton instanciado uma vez e registrado no AsyncDispatcher via
# config/initializers/holding_crm.rb.
#
# Method names mapeiam o `name.to_s.tr('.', '_')` de Events::Base — então
# 'crm.opportunity.stage_changed' → #crm_opportunity_stage_changed.
# Constants vêm de Holding::Crm::Events.
#
# Padrão: cada handler é magro — só decide o `if` (gate por configuração
# do stage etc) e enfileira um job. Nada de I/O ou lógica complexa aqui.
class Holding::CrmListener < BaseListener
  # crm.opportunity.stage_changed
  # Payload: { opportunity:, old_stage_id:, new_stage_id: }
  #
  # [2026-05-07] Gate por matrix_task_template.enabled — só dispara o job
  # quando a stage destino tem template Matrix configurado E ativado.
  # Sem o gate, qualquer mudança de stage tentaria criar Matrix task
  # mesmo sem configuração, gerando erros e ruído nos logs.
  def crm_opportunity_stage_changed(event)
    opportunity = event.data[:opportunity]
    new_stage_id = event.data[:new_stage_id]
    return if opportunity.blank? || new_stage_id.blank?

    new_stage = Holding::Crm::Stage.find_by(id: new_stage_id)
    return if new_stage.blank?

    template = new_stage.matrix_task_template
    return if template.blank? || !template['enabled']

    Rails.logger.info(
      event: 'crm.opportunity.stage_changed.queued_matrix_notify',
      opportunity_id: opportunity.id,
      account_id: opportunity.account_id,
      old_stage_id: event.data[:old_stage_id],
      new_stage_id: new_stage_id
    )

    Holding::CrmNotifyMatrixJob.perform_later(opportunity_id: opportunity.id, stage_id: new_stage_id)
  end

  # crm.activity.due_soon
  # Payload: { activity: }
  # Disparado por Holding::Crm::ActivityDueSoonCronJob (1×/h).
  #
  # [2026-05-16] Stub handler pra slice 3. Por ora só observa o evento
  # via log estruturado pra termos visibilidade end-to-end (cron → dispatch
  # → listener) sem precisar definir um reminder job sem requisitos de
  # produto. Reminder real (Matrix task pro assignee, email, etc.) vai
  # entrar em slice futura (4 ou pós-Phase-4) quando o canal de entrega
  # estiver decidido. Mantém o pipe de eventos plumbed pra não precisar
  # mexer no listener / dispatcher de novo quando o reminder chegar.
  def crm_activity_due_soon(event)
    activity = event.data[:activity]
    return if activity.blank?

    Rails.logger.info(
      event: 'crm.activity.due_soon.received',
      activity_id: activity.id,
      account_id: activity.account_id,
      assignee_id: activity.assignee_id,
      due_at: activity.due_at
    )
  end

  # crm.activity.overdue
  # Payload: { activity: }
  # Disparado por Holding::Crm::ActivityOverdueCronJob (1×/d).
  #
  # [2026-05-16] Stub handler pra slice 3 — mesmo racional do due_soon
  # acima. Reminder/escalation real fica pra slice futura.
  def crm_activity_overdue(event)
    activity = event.data[:activity]
    return if activity.blank?

    Rails.logger.info(
      event: 'crm.activity.overdue.received',
      activity_id: activity.id,
      account_id: activity.account_id,
      assignee_id: activity.assignee_id,
      due_at: activity.due_at
    )
  end
end
