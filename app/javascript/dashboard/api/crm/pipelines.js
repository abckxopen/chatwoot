import ApiClient from '../ApiClient';

// [2026-05-17] Holding CRM — pipelines API client. Top-level resource
// scoped to account: /api/v1/accounts/:account_id/crm_pipelines[/:id].
// Default CRUD herdado de ApiClient cobre index/show/create/update/destroy;
// não há custom actions nesse recurso ainda. Ver brain/crm-pipeline-spec.md.
class CrmPipelines extends ApiClient {
  constructor() {
    super('crm_pipelines', { accountScoped: true });
  }
}

export default new CrmPipelines();
