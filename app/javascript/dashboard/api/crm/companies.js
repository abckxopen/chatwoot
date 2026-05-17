import ApiClient from '../ApiClient';

// [2026-05-17] Holding CRM — companies API client.
// Top-level resource (config/routes.rb):
//   resources :crm_companies, only: %i[index show create update destroy]
// URL pattern: /api/v1/accounts/:account_id/crm_companies[/:id].
// CRUD default do ApiClient cobre todos os 5 verbos — sem override.
class CrmCompanies extends ApiClient {
  constructor() {
    super('crm_companies', { accountScoped: true });
  }
}

export default new CrmCompanies();
