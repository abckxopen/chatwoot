import { throwErrorMessage } from 'dashboard/store/utils/api';
import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import * as types from '../../mutation-types';
import CrmPipelinesAPI from '../../../api/crm/pipelines';

export const state = {
  records: [],
  uiFlags: {
    fetchingList: false,
    fetchingItem: false,
    creatingItem: false,
    updatingItem: false,
    deletingItem: false,
  },
};

export const getters = {
  getCrmPipelines(_state) {
    return _state.records;
  },
  getCrmPipeline: _state => id => {
    return _state.records.find(record => record.id === Number(id));
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async function getCrmPipelines({ commit }) {
    commit(types.default.SET_CRM_PIPELINES_UI_FLAG, { fetchingList: true });
    try {
      const response = await CrmPipelinesAPI.get();
      commit(types.default.SET_CRM_PIPELINES, response.data);
    } catch (error) {
      // [2026-05-17] Não rethrow no list — UI usa uiFlags + records vazio,
      // mesmo padrão de cannedResponse (lista silenciosa em erro).
    } finally {
      commit(types.default.SET_CRM_PIPELINES_UI_FLAG, { fetchingList: false });
    }
  },

  show: async function showCrmPipeline({ commit }, id) {
    commit(types.default.SET_CRM_PIPELINES_UI_FLAG, { fetchingItem: true });
    try {
      const response = await CrmPipelinesAPI.show(id);
      commit(types.default.EDIT_CRM_PIPELINE, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_PIPELINES_UI_FLAG, { fetchingItem: false });
    }
  },

  create: async function createCrmPipeline({ commit }, pipelineObj) {
    commit(types.default.SET_CRM_PIPELINES_UI_FLAG, { creatingItem: true });
    try {
      const response = await CrmPipelinesAPI.create(pipelineObj);
      commit(types.default.ADD_CRM_PIPELINE, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_PIPELINES_UI_FLAG, { creatingItem: false });
    }
  },

  update: async function updateCrmPipeline({ commit }, { id, ...updateObj }) {
    commit(types.default.SET_CRM_PIPELINES_UI_FLAG, { updatingItem: true });
    try {
      const response = await CrmPipelinesAPI.update(id, updateObj);
      commit(types.default.EDIT_CRM_PIPELINE, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_PIPELINES_UI_FLAG, { updatingItem: false });
    }
  },

  delete: async function deleteCrmPipeline({ commit }, id) {
    commit(types.default.SET_CRM_PIPELINES_UI_FLAG, { deletingItem: true });
    try {
      await CrmPipelinesAPI.delete(id);
      commit(types.default.DELETE_CRM_PIPELINE, id);
      return id;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_PIPELINES_UI_FLAG, { deletingItem: false });
    }
  },
};

export const mutations = {
  [types.default.SET_CRM_PIPELINES_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.default.SET_CRM_PIPELINES]: MutationHelpers.set,
  [types.default.ADD_CRM_PIPELINE]: MutationHelpers.create,
  [types.default.EDIT_CRM_PIPELINE]: MutationHelpers.update,
  [types.default.DELETE_CRM_PIPELINE]: MutationHelpers.destroy,
};

// [2026-05-17] namespaced:true é obrigatório — sem isso useMapGetter('crmPipelines/x')
// e store.dispatch('crmPipelines/x') resolvem como keys flat e silenciosamente no-op
// no consumer Vue (descoberto na review do slice 2 da Phase 3, onde o landing crasha).
// Adicionado retroativamente nos 5 módulos CRM (pipelines/stages/opportunities/companies/activities).
export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
