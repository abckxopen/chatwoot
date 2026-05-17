/* global axios */

import ApiClient from '../ApiClient';

// [2026-05-17] Holding CRM — activities API client.
// Activities são aninhadas sob opportunities no backend (config/routes.rb):
//   resources :crm_opportunities do
//     resources :crm_activities, only: %i[index create update destroy], path: 'activities' do
//       member { patch :complete }
//     end
//   end
// URL pattern: /api/v1/accounts/:account_id/crm_opportunities/:opportunity_id/activities[/:id|/:id/complete].
// Mirror do padrão de crm/stages.js — todos os métodos exigem `opportunityId` primeiro
// pq não dá pra usar o CRUD default do ApiClient (assume `${url}/:id`, não nested).
// Backend não expõe `show` (only: %i[index create update destroy]); helper omitido.
// `complete` é PATCH .../complete sem body — backend defaulta completed_at = Time.zone.now
// em `Holding::Crm::Activity#complete!`.
class CrmActivities extends ApiClient {
  constructor() {
    super('crm_opportunities', { accountScoped: true });
  }

  // eslint-disable-next-line class-methods-use-this
  activitiesUrl(opportunityId) {
    return `${this.url}/${opportunityId}/activities`;
  }

  get(opportunityId) {
    return axios.get(this.activitiesUrl(opportunityId));
  }

  create(opportunityId, data) {
    return axios.post(this.activitiesUrl(opportunityId), data);
  }

  update(opportunityId, id, data) {
    return axios.patch(`${this.activitiesUrl(opportunityId)}/${id}`, data);
  }

  delete(opportunityId, id) {
    return axios.delete(`${this.activitiesUrl(opportunityId)}/${id}`);
  }

  complete(opportunityId, id) {
    return axios.patch(`${this.activitiesUrl(opportunityId)}/${id}/complete`);
  }
}

export default new CrmActivities();
