import { throwErrorMessage } from 'dashboard/store/utils/api';
import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import * as types from '../../mutation-types';
import CrmOpportunitiesAPI from '../../../api/crm/opportunities';

export const state = {
  records: [],
  uiFlags: {
    fetchingList: false,
    fetchingItem: false,
    creatingItem: false,
    updatingItem: false,
    deletingItem: false,
    movingToStage: false,
    discarding: false,
  },
};

export const getters = {
  getCrmOpportunities(_state) {
    return _state.records;
  },
  getCrmOpportunitiesForStage: _state => stageId => {
    const sid = Number(stageId);
    return _state.records.filter(record => record.crm_stage_id === sid);
  },
  getCrmOpportunity: _state => id => {
    return _state.records.find(record => record.id === Number(id));
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async function getCrmOpportunities({ commit }, params = {}) {
    commit(types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, { fetchingList: true });
    try {
      const response = await CrmOpportunitiesAPI.get(params);
      commit(types.default.SET_CRM_OPPORTUNITIES, response.data);
    } catch (error) {
      // [2026-05-17] Silencioso no list — mesmo padrão de pipelines/stages.
    } finally {
      commit(types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, {
        fetchingList: false,
      });
    }
  },

  // [2026-05-17] show usa ADD ou EDIT dependendo se record já existe em
  // records — MutationHelpers.update no-opa em record ausente (bug pego em
  // reviewer da Phase 4 slice 2). Deep-link cold cache disparava show, EDIT
  // não populava records, e CrmOpportunityDetail mostrava "não encontrado".
  show: async function showCrmOpportunity({ commit, state }, id) {
    commit(types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, { fetchingItem: true });
    try {
      const response = await CrmOpportunitiesAPI.show(id);
      const exists = state.records.some(r => r.id === response.data.id);
      commit(
        exists
          ? types.default.EDIT_CRM_OPPORTUNITY
          : types.default.ADD_CRM_OPPORTUNITY,
        response.data
      );
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, {
        fetchingItem: false,
      });
    }
  },

  create: async function createCrmOpportunity({ commit }, opportunityObj) {
    commit(types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, { creatingItem: true });
    try {
      const response = await CrmOpportunitiesAPI.create(opportunityObj);
      commit(types.default.ADD_CRM_OPPORTUNITY, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, {
        creatingItem: false,
      });
    }
  },

  update: async function updateCrmOpportunity(
    { commit },
    { id, ...updateObj }
  ) {
    commit(types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, { updatingItem: true });
    try {
      const response = await CrmOpportunitiesAPI.update(id, updateObj);
      commit(types.default.EDIT_CRM_OPPORTUNITY, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, {
        updatingItem: false,
      });
    }
  },

  delete: async function deleteCrmOpportunity({ commit }, id) {
    commit(types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, { deletingItem: true });
    try {
      await CrmOpportunitiesAPI.delete(id);
      commit(types.default.DELETE_CRM_OPPORTUNITY, id);
      return id;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, {
        deletingItem: false,
      });
    }
  },

  moveToStage: async function moveCrmOpportunityToStage(
    { commit },
    { id, stageId, reason = null }
  ) {
    commit(types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, {
      movingToStage: true,
    });
    try {
      const response = await CrmOpportunitiesAPI.moveToStage(
        id,
        stageId,
        reason
      );
      // Backend retorna a opportunity atualizada (com novo crm_stage_id).
      commit(types.default.MOVE_CRM_OPPORTUNITY_TO_STAGE, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, {
        movingToStage: false,
      });
    }
  },

  discard: async function discardCrmOpportunity({ commit }, id) {
    commit(types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, { discarding: true });
    try {
      await CrmOpportunitiesAPI.discard(id);
      // [2026-05-17] Discard é soft-delete: remove dos records locais.
      // Caller que queira mostrar discardadas usa endpoint separado (Phase 4).
      commit(types.default.DISCARD_CRM_OPPORTUNITY, id);
      return id;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, {
        discarding: false,
      });
    }
  },
};

export const mutations = {
  [types.default.SET_CRM_OPPORTUNITIES_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.default.SET_CRM_OPPORTUNITIES]: MutationHelpers.set,
  [types.default.ADD_CRM_OPPORTUNITY]: MutationHelpers.create,
  [types.default.EDIT_CRM_OPPORTUNITY]: MutationHelpers.update,
  [types.default.DELETE_CRM_OPPORTUNITY]: MutationHelpers.destroy,

  // Move: backend devolve o registro com `crm_stage_id` novo → update normal.
  [types.default.MOVE_CRM_OPPORTUNITY_TO_STAGE]: MutationHelpers.update,

  // Discard: remove do array local (mesma semântica de destroy).
  [types.default.DISCARD_CRM_OPPORTUNITY]: MutationHelpers.destroy,
};

// [2026-05-17] namespaced:true — ver razão completa em crm/pipelines.js.
export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
