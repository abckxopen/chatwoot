import { throwErrorMessage } from 'dashboard/store/utils/api';
import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import * as types from '../../mutation-types';
import CrmActivitiesAPI from '../../../api/crm/activities';

// [2026-05-17] Activities são aninhadas sob opportunities no backend
// (rotas /crm_opportunities/:opportunity_id/activities). Aqui o state.records
// é um array FLAT — cada activity carrega `crm_opportunity_id` no payload do
// backend, então componentes Vue filtram via getter (`getCrmActivitiesForOpportunity`).
// Mirror direto do shape de crm/stages.js (mesmo problema de nested resource).
export const state = {
  records: [],
  uiFlags: {
    fetchingList: false,
    fetchingItem: false,
    creatingItem: false,
    updatingItem: false,
    deletingItem: false,
    completing: false,
  },
};

export const getters = {
  getCrmActivities(_state) {
    return _state.records;
  },
  getCrmActivitiesForOpportunity: _state => opportunityId => {
    const oid = Number(opportunityId);
    return _state.records.filter(record => record.crm_opportunity_id === oid);
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async function getCrmActivities({ commit }, opportunityId) {
    commit(types.default.SET_CRM_ACTIVITIES_UI_FLAG, { fetchingList: true });
    try {
      const response = await CrmActivitiesAPI.get(opportunityId);
      commit(types.default.SET_CRM_ACTIVITIES, response.data);
    } catch (error) {
      // [2026-05-17] Silencioso no list — mesmo padrão de pipelines/stages.
    } finally {
      commit(types.default.SET_CRM_ACTIVITIES_UI_FLAG, { fetchingList: false });
    }
  },

  create: async function createCrmActivity(
    { commit },
    { opportunityId, ...data }
  ) {
    commit(types.default.SET_CRM_ACTIVITIES_UI_FLAG, { creatingItem: true });
    try {
      const response = await CrmActivitiesAPI.create(opportunityId, data);
      commit(types.default.ADD_CRM_ACTIVITY, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_ACTIVITIES_UI_FLAG, { creatingItem: false });
    }
  },

  update: async function updateCrmActivity(
    { commit },
    { opportunityId, id, ...updateObj }
  ) {
    commit(types.default.SET_CRM_ACTIVITIES_UI_FLAG, { updatingItem: true });
    try {
      const response = await CrmActivitiesAPI.update(
        opportunityId,
        id,
        updateObj
      );
      commit(types.default.EDIT_CRM_ACTIVITY, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_ACTIVITIES_UI_FLAG, { updatingItem: false });
    }
  },

  delete: async function deleteCrmActivity({ commit }, { opportunityId, id }) {
    commit(types.default.SET_CRM_ACTIVITIES_UI_FLAG, { deletingItem: true });
    try {
      await CrmActivitiesAPI.delete(opportunityId, id);
      commit(types.default.DELETE_CRM_ACTIVITY, id);
      return id;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_ACTIVITIES_UI_FLAG, { deletingItem: false });
    }
  },

  // [2026-05-17] complete é PATCH .../complete sem body — backend
  // (Holding::Crm::Activity#complete!) defaulta completed_at = Time.zone.now.
  // Response carrega o activity atualizado, então EDIT in-place via MutationHelpers.update.
  complete: async function completeCrmActivity(
    { commit },
    { opportunityId, id }
  ) {
    commit(types.default.SET_CRM_ACTIVITIES_UI_FLAG, { completing: true });
    try {
      const response = await CrmActivitiesAPI.complete(opportunityId, id);
      commit(types.default.COMPLETE_CRM_ACTIVITY, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_ACTIVITIES_UI_FLAG, { completing: false });
    }
  },
};

export const mutations = {
  [types.default.SET_CRM_ACTIVITIES_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.default.SET_CRM_ACTIVITIES]: MutationHelpers.set,
  [types.default.ADD_CRM_ACTIVITY]: MutationHelpers.create,
  [types.default.EDIT_CRM_ACTIVITY]: MutationHelpers.update,
  [types.default.DELETE_CRM_ACTIVITY]: MutationHelpers.destroy,
  [types.default.COMPLETE_CRM_ACTIVITY]: MutationHelpers.update,
};

export default {
  state,
  getters,
  actions,
  mutations,
};
