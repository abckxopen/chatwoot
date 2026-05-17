/* global axios */
import ApiClient from '../ApiClient';

// [2026-05-17] Holding CRM — reports API client. Phase 4 slice 3.
// Endpoints read-only (não tem CRUD), custom collection actions:
//   /api/v1/accounts/:account_id/crm_reports/pipeline_summary
//   /api/v1/accounts/:account_id/crm_reports/agent_performance
//   /api/v1/accounts/:account_id/crm_reports/forecast
//
// Override em axios.get direto (não via this.show/get herdados) porque
// não há recurso REST id-based — cada método mapeia 1:1 com collection
// action do controller. Snake_case nos params bate com permit do backend.
class CrmReports extends ApiClient {
  constructor() {
    super('crm_reports', { accountScoped: true });
  }

  pipelineSummary(pipelineId) {
    return axios.get(`${this.url}/pipeline_summary`, {
      params: { pipeline_id: pipelineId },
    });
  }

  agentPerformance({ from, to } = {}) {
    return axios.get(`${this.url}/agent_performance`, {
      params: { from, to },
    });
  }

  forecast(pipelineId, untilDate) {
    return axios.get(`${this.url}/forecast`, {
      params: { pipeline_id: pipelineId, until: untilDate },
    });
  }
}

export default new CrmReports();
