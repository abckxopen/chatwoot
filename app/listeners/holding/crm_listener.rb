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
end
