import { frontendURL } from '../../../helper/URLHelper';
import CrmHome from './pages/CrmHome.vue';

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
];
