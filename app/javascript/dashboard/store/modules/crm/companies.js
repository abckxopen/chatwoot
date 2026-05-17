import { throwErrorMessage } from 'dashboard/store/utils/api';
import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import * as types from '../../mutation-types';
import CrmCompaniesAPI from '../../../api/crm/companies';

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
  getCrmCompanies(_state) {
    return _state.records;
  },
  getCrmCompany: _state => id => {
    return _state.records.find(record => record.id === Number(id));
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async function getCrmCompanies({ commit }) {
    commit(types.default.SET_CRM_COMPANIES_UI_FLAG, { fetchingList: true });
    try {
      const response = await CrmCompaniesAPI.get();
      commit(types.default.SET_CRM_COMPANIES, response.data);
    } catch (error) {
      // [2026-05-17] Silencioso no list — mesmo padrão de cannedResponse +
      // crm/pipelines (UI usa uiFlags + records vazio pra render fallback).
    } finally {
      commit(types.default.SET_CRM_COMPANIES_UI_FLAG, { fetchingList: false });
    }
  },

  // [2026-05-17] show usa ADD ou EDIT — ver razão em crm/opportunities.js
  // (MutationHelpers.update no-opa em record ausente; deep-link cold cache
  // ficava silenciosamente quebrado).
  show: async function showCrmCompany({ commit, state }, id) {
    commit(types.default.SET_CRM_COMPANIES_UI_FLAG, { fetchingItem: true });
    try {
      const response = await CrmCompaniesAPI.show(id);
      const exists = state.records.some(r => r.id === response.data.id);
      commit(
        exists ? types.default.EDIT_CRM_COMPANY : types.default.ADD_CRM_COMPANY,
        response.data
      );
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_COMPANIES_UI_FLAG, { fetchingItem: false });
    }
  },

  create: async function createCrmCompany({ commit }, companyObj) {
    commit(types.default.SET_CRM_COMPANIES_UI_FLAG, { creatingItem: true });
    try {
      const response = await CrmCompaniesAPI.create(companyObj);
      commit(types.default.ADD_CRM_COMPANY, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_COMPANIES_UI_FLAG, { creatingItem: false });
    }
  },

  update: async function updateCrmCompany({ commit }, { id, ...updateObj }) {
    commit(types.default.SET_CRM_COMPANIES_UI_FLAG, { updatingItem: true });
    try {
      const response = await CrmCompaniesAPI.update(id, updateObj);
      commit(types.default.EDIT_CRM_COMPANY, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_COMPANIES_UI_FLAG, { updatingItem: false });
    }
  },

  delete: async function deleteCrmCompany({ commit }, id) {
    commit(types.default.SET_CRM_COMPANIES_UI_FLAG, { deletingItem: true });
    try {
      await CrmCompaniesAPI.delete(id);
      commit(types.default.DELETE_CRM_COMPANY, id);
      return id;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_COMPANIES_UI_FLAG, { deletingItem: false });
    }
  },
};

export const mutations = {
  [types.default.SET_CRM_COMPANIES_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.default.SET_CRM_COMPANIES]: MutationHelpers.set,
  [types.default.ADD_CRM_COMPANY]: MutationHelpers.create,
  [types.default.EDIT_CRM_COMPANY]: MutationHelpers.update,
  [types.default.DELETE_CRM_COMPANY]: MutationHelpers.destroy,
};

// [2026-05-17] namespaced:true — ver razão completa em crm/pipelines.js.
export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
