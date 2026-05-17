import { frontendURL } from '../../../helper/URLHelper';
import CompanyDetail from './pages/CompanyDetail.vue';
import CompanyList from './pages/CompanyList.vue';
import CrmHome from './pages/CrmHome.vue';
import CrmReports from './pages/CrmReports.vue';
import OpportunityDetail from './pages/OpportunityDetail.vue';
import PipelineKanban from './pages/PipelineKanban.vue';

// [2026-05-17] `holdingCrm: true` é o meta-flag do guard custom
// (validateHoldingCrmRoute em helper/routeHelpers.js). Não confundir
// com `featureFlag` do core (esse só gateia sidebar visibility, não
// redireciona route).
const commonMeta = {
  holdingCrm: true,
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/crm'),
    name: 'crm_home',
    component: CrmHome,
    meta: commonMeta,
  },
  {
    path: frontendURL('accounts/:accountId/crm/pipelines/:pipelineId/kanban'),
    name: 'crm_pipeline_kanban',
    component: PipelineKanban,
    meta: commonMeta,
    // [2026-05-17] props:true expõe pipelineId (route param) como prop
    // do PipelineKanban — evita acoplar componente ao useRoute() pra
    // ler params (accountId continua via useAccount()).
    props: true,
  },
  {
    path: frontendURL('accounts/:accountId/crm/companies'),
    name: 'crm_companies',
    component: CompanyList,
    meta: commonMeta,
  },
  {
    path: frontendURL('accounts/:accountId/crm/companies/:companyId'),
    name: 'crm_company_detail',
    component: CompanyDetail,
    meta: commonMeta,
    // [2026-05-17] props:true expõe companyId (route param) como prop
    // do CompanyDetail — mesmo padrão de PipelineKanban acima.
    props: true,
  },
  {
    path: frontendURL('accounts/:accountId/crm/opportunities/:opportunityId'),
    name: 'crm_opportunity_detail',
    component: OpportunityDetail,
    meta: commonMeta,
    // [2026-05-17] props:true expõe opportunityId (route param) como prop
    // do OpportunityDetail — mesmo padrão das rotas acima.
    props: true,
  },
  {
    // [2026-05-17] Phase 4 slice 3 — relatórios CRM. Sem id na URL: página
    // tem seletor próprio de pipeline + range de datas. Aggregations
    // read-only, mesmo gate (holdingCrm + admin/agent) das outras rotas.
    path: frontendURL('accounts/:accountId/crm/reports'),
    name: 'crm_reports',
    component: CrmReports,
    meta: commonMeta,
  },
];
