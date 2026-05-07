# [2026-05-07 — STUB slice 2.1] Cria Matrix task pra opportunity baseado
# no matrix_task_template do stage. Implementação real (HTTP API client)
# vem em slice 2.2.
#
# Por que stub agora: slice 2.1 entrega o wiring (listener registrado +
# handler enfileira job). Slice 2.2 entrega a integração Matrix de fato
# (API client, idempotência via matrix_task_id, error handling, retries).
#
# Idempotência planejada (slice 2.2):
# - Antes de criar task, checa se já existe um Holding::Crm::Activity
#   recente (mesma opp + matrix_task_id presente em janela de N min).
# - Se sim, no-op + log.
class Holding::CrmNotifyMatrixJob < ApplicationJob
  queue_as :default

  def perform(opportunity_id:, stage_id:)
    Rails.logger.info(
      job: 'Holding::CrmNotifyMatrixJob',
      event: 'crm.matrix.notify.stub_invoked',
      opportunity_id: opportunity_id,
      stage_id: stage_id,
      note: 'STUB — real Matrix API call lands in slice 2.2'
    )
  end
end
