import { throwErrorMessage } from 'dashboard/store/utils/api';
import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import * as types from '../../mutation-types';
import CrmStagesAPI from '../../../api/crm/stages';

// [2026-05-17] Stages são aninhados sob pipelines no backend (rotas
// /crm_pipelines/:pipeline_id/stages). Aqui o state.records é um array
// FLAT — cada stage carrega `crm_pipeline_id` no payload do backend, então
// componentes Vue filtram via getter (`getStagesForPipeline`). Mais simples
// que manter object keyed por pipelineId; serializa direto pra Kanban.
export const state = {
  records: [],
  uiFlags: {
    fetchingList: false,
    fetchingItem: false,
    creatingItem: false,
    updatingItem: false,
    deletingItem: false,
    reordering: false,
  },
};

export const getters = {
  getCrmStages(_state) {
    return _state.records;
  },
  getCrmStagesForPipeline: _state => pipelineId => {
    const pid = Number(pipelineId);
    return _state.records
      .filter(record => record.crm_pipeline_id === pid)
      .sort((a, b) => (a.position || 0) - (b.position || 0));
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async function getCrmStages({ commit }, pipelineId) {
    commit(types.default.SET_CRM_STAGES_UI_FLAG, { fetchingList: true });
    try {
      const response = await CrmStagesAPI.get(pipelineId);
      commit(types.default.SET_CRM_STAGES, response.data);
    } catch (error) {
      // [2026-05-17] Silencioso no list — mesmo padrão de pipelines.
    } finally {
      commit(types.default.SET_CRM_STAGES_UI_FLAG, { fetchingList: false });
    }
  },

  create: async function createCrmStage({ commit }, { pipelineId, ...data }) {
    commit(types.default.SET_CRM_STAGES_UI_FLAG, { creatingItem: true });
    try {
      const response = await CrmStagesAPI.create(pipelineId, data);
      commit(types.default.ADD_CRM_STAGE, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_STAGES_UI_FLAG, { creatingItem: false });
    }
  },

  update: async function updateCrmStage(
    { commit },
    { pipelineId, id, ...updateObj }
  ) {
    commit(types.default.SET_CRM_STAGES_UI_FLAG, { updatingItem: true });
    try {
      const response = await CrmStagesAPI.update(pipelineId, id, updateObj);
      commit(types.default.EDIT_CRM_STAGE, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_STAGES_UI_FLAG, { updatingItem: false });
    }
  },

  delete: async function deleteCrmStage({ commit }, { pipelineId, id }) {
    commit(types.default.SET_CRM_STAGES_UI_FLAG, { deletingItem: true });
    try {
      await CrmStagesAPI.delete(pipelineId, id);
      commit(types.default.DELETE_CRM_STAGE, id);
      return id;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_STAGES_UI_FLAG, { deletingItem: false });
    }
  },

  reorder: async function reorderCrmStages(
    { commit },
    { pipelineId, stageIds }
  ) {
    commit(types.default.SET_CRM_STAGES_UI_FLAG, { reordering: true });
    try {
      const response = await CrmStagesAPI.reorder(pipelineId, stageIds);
      // Backend retorna a lista de stages na nova ordem com `position` atualizado.
      commit(types.default.REORDER_CRM_STAGES, {
        pipelineId: Number(pipelineId),
        stages: response.data,
      });
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.default.SET_CRM_STAGES_UI_FLAG, { reordering: false });
    }
  },
};

export const mutations = {
  [types.default.SET_CRM_STAGES_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.default.SET_CRM_STAGES]: MutationHelpers.set,
  [types.default.ADD_CRM_STAGE]: MutationHelpers.create,
  [types.default.EDIT_CRM_STAGE]: MutationHelpers.update,
  [types.default.DELETE_CRM_STAGE]: MutationHelpers.destroy,

  // [2026-05-17] Reorder substitui in-place os stages do pipeline alvo
  // mantendo records de OUTROS pipelines intactos.
  [types.default.REORDER_CRM_STAGES](_state, { pipelineId, stages }) {
    const others = _state.records.filter(
      record => record.crm_pipeline_id !== pipelineId
    );
    _state.records = [...others, ...stages];
  },
};

// [2026-05-17] namespaced:true — ver razão completa em crm/pipelines.js.
export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
