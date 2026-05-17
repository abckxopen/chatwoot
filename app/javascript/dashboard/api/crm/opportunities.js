/* global axios */

import ApiClient from '../ApiClient';

// [2026-05-17] Holding CRM — opportunities API client.
// Recurso top-level scoped por account. Custom member actions (rotas):
//   patch :move_to_stage  → move pra outra stage (registra histórico no backend)
//   patch :discard        → soft-delete (paranoia/discard gem no backend)
// NÃO existe win/lose como endpoint dedicado: status `won|lost` é setado
// via `update(id, { status })` normal. Discard é separado pra distinguir
// "removida do funil" de "perdida com motivo".
class CrmOpportunities extends ApiClient {
  constructor() {
    super('crm_opportunities', { accountScoped: true });
  }

  // [2026-05-17] Override ApiClient#get pra passar query params via axios.
  // Backend crm_opportunities_controller#index aceita filtros snake_case
  // (pipeline_id, stage_id, status, assignee_id, expected_close_date_from/to).
  // Sem esse override params eram silenciosamente droppados — Kanban
  // ficaria sempre sem filtro. Caller passa chaves em snake_case.
  get(params = {}) {
    return axios.get(this.url, { params });
  }

  moveToStage(id, stageId, reason = null) {
    return axios.patch(`${this.url}/${id}/move_to_stage`, {
      stage_id: stageId,
      reason,
    });
  }

  // [2026-05-17] Body {} explícito apesar de discard não exigir payload —
  // deixa intent claro e evita surpresa se axios mudar default no futuro.
  discard(id) {
    return axios.patch(`${this.url}/${id}/discard`, {});
  }
}

export default new CrmOpportunities();
