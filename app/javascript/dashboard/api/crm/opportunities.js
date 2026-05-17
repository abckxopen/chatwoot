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

  moveToStage(id, stageId, reason = null) {
    return axios.patch(`${this.url}/${id}/move_to_stage`, {
      stage_id: stageId,
      reason,
    });
  }

  discard(id) {
    return axios.patch(`${this.url}/${id}/discard`);
  }
}

export default new CrmOpportunities();
