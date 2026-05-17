/* global axios */

import ApiClient from '../ApiClient';

// [2026-05-17] Holding CRM — stages API client.
// Stages são aninhados sob pipelines no backend (config/routes.rb):
//   resources :crm_pipelines do
//     resources :crm_stages, path: 'stages' do
//       collection { patch :reorder }
//     end
//   end
// URL pattern: /api/v1/accounts/:account_id/crm_pipelines/:pipeline_id/stages[/:id].
// Por isso TODOS os métodos exigem `pipelineId` como primeiro arg —
// não dá pra usar o CRUD default do ApiClient que assume `${url}/:id`.
class CrmStages extends ApiClient {
  constructor() {
    super('crm_pipelines', { accountScoped: true });
  }

  // eslint-disable-next-line class-methods-use-this
  stagesUrl(pipelineId) {
    return `${this.url}/${pipelineId}/stages`;
  }

  get(pipelineId) {
    return axios.get(this.stagesUrl(pipelineId));
  }

  show(pipelineId, id) {
    return axios.get(`${this.stagesUrl(pipelineId)}/${id}`);
  }

  create(pipelineId, data) {
    return axios.post(this.stagesUrl(pipelineId), data);
  }

  update(pipelineId, id, data) {
    return axios.patch(`${this.stagesUrl(pipelineId)}/${id}`, data);
  }

  delete(pipelineId, id) {
    return axios.delete(`${this.stagesUrl(pipelineId)}/${id}`);
  }

  reorder(pipelineId, stageIdsInOrder) {
    return axios.patch(`${this.stagesUrl(pipelineId)}/reorder`, {
      stage_ids: stageIdsInOrder,
    });
  }
}

export default new CrmStages();
