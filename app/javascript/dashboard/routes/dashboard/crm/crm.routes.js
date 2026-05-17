import { frontendURL } from '../../../helper/URLHelper';
import CrmHome from './pages/CrmHome.vue';
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
];
