import { describe, it, expect, vi, beforeEach } from 'vitest';
import CrmStagesAPI from 'dashboard/api/crm/stages';
import storeModule, {
  state as initialState,
  getters,
  actions,
  mutations,
} from '../../crm/stages';
import * as types from '../../../mutation-types';

vi.mock('dashboard/api/crm/stages', () => ({
  default: {
    get: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    reorder: vi.fn(),
  },
}));

describe('CRM Stages Store', () => {
  let commit;

  beforeEach(() => {
    vi.clearAllMocks();
    commit = vi.fn();
  });

  describe('Initial State', () => {
    it('has records + uiFlags shape with reordering flag', () => {
      expect(initialState).toEqual({
        records: [],
        uiFlags: {
          fetchingList: false,
          fetchingItem: false,
          creatingItem: false,
          updatingItem: false,
          deletingItem: false,
          reordering: false,
        },
      });
    });
  });

  describe('Getters', () => {
    const state = {
      records: [
        { id: 1, name: 'Lead', crm_pipeline_id: 10, position: 2 },
        { id: 2, name: 'Qualified', crm_pipeline_id: 10, position: 1 },
        { id: 3, name: 'Onboard A', crm_pipeline_id: 20, position: 1 },
      ],
      uiFlags: { fetchingList: true },
    };

    it('getCrmStages returns all records', () => {
      expect(getters.getCrmStages(state)).toEqual(state.records);
    });

    it('getCrmStagesForPipeline filters + sorts by position', () => {
      const result = getters.getCrmStagesForPipeline(state)(10);
      expect(result.map(s => s.id)).toEqual([2, 1]);
    });

    it('getUIFlags returns uiFlags', () => {
      expect(getters.getUIFlags(state)).toEqual({ fetchingList: true });
    });
  });

  describe('Mutations', () => {
    it('SET_CRM_STAGES_UI_FLAG merges flags', () => {
      const state = { uiFlags: { reordering: false } };
      mutations[types.default.SET_CRM_STAGES_UI_FLAG](state, {
        reordering: true,
      });
      expect(state.uiFlags).toEqual({ reordering: true });
    });

    it('SET_CRM_STAGES replaces records', () => {
      const state = { records: [] };
      mutations[types.default.SET_CRM_STAGES](state, [{ id: 1 }]);
      expect(state.records).toEqual([{ id: 1 }]);
    });

    it('ADD_CRM_STAGE pushes record', () => {
      const state = { records: [{ id: 1 }] };
      mutations[types.default.ADD_CRM_STAGE](state, { id: 2 });
      expect(state.records).toEqual([{ id: 1 }, { id: 2 }]);
    });

    it('EDIT_CRM_STAGE replaces matching record', () => {
      const state = { records: [{ id: 1, name: 'old' }] };
      mutations[types.default.EDIT_CRM_STAGE](state, { id: 1, name: 'new' });
      expect(state.records).toEqual([{ id: 1, name: 'new' }]);
    });

    it('DELETE_CRM_STAGE removes by id', () => {
      const state = { records: [{ id: 1 }, { id: 2 }] };
      mutations[types.default.DELETE_CRM_STAGE](state, 1);
      expect(state.records).toEqual([{ id: 2 }]);
    });

    it('REORDER_CRM_STAGES replaces stages of target pipeline only', () => {
      const state = {
        records: [
          { id: 1, crm_pipeline_id: 10, position: 1 },
          { id: 2, crm_pipeline_id: 10, position: 2 },
          { id: 3, crm_pipeline_id: 20, position: 1 },
        ],
      };
      mutations[types.default.REORDER_CRM_STAGES](state, {
        pipelineId: 10,
        stages: [
          { id: 2, crm_pipeline_id: 10, position: 1 },
          { id: 1, crm_pipeline_id: 10, position: 2 },
        ],
      });
      expect(state.records).toEqual([
        { id: 3, crm_pipeline_id: 20, position: 1 },
        { id: 2, crm_pipeline_id: 10, position: 1 },
        { id: 1, crm_pipeline_id: 10, position: 2 },
      ]);
    });
  });

  describe('Actions', () => {
    describe('get', () => {
      it('passes pipelineId to API and commits SET', async () => {
        CrmStagesAPI.get.mockResolvedValue({ data: [{ id: 1 }] });
        await actions.get({ commit }, 10);
        expect(CrmStagesAPI.get).toHaveBeenCalledWith(10);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_STAGES_UI_FLAG, { fetchingList: true }],
          [types.default.SET_CRM_STAGES, [{ id: 1 }]],
          [types.default.SET_CRM_STAGES_UI_FLAG, { fetchingList: false }],
        ]);
      });

      it('clears UI flag on error (silent)', async () => {
        CrmStagesAPI.get.mockRejectedValue(new Error('boom'));
        await actions.get({ commit }, 10);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_STAGES_UI_FLAG, { fetchingList: true }],
          [types.default.SET_CRM_STAGES_UI_FLAG, { fetchingList: false }],
        ]);
      });
    });

    describe('create', () => {
      it('forwards pipelineId + data and commits ADD', async () => {
        CrmStagesAPI.create.mockResolvedValue({
          data: { id: 3, name: 'New' },
        });
        await actions.create(
          { commit },
          { pipelineId: 10, name: 'New', position: 1 }
        );
        expect(CrmStagesAPI.create).toHaveBeenCalledWith(10, {
          name: 'New',
          position: 1,
        });
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_STAGES_UI_FLAG, { creatingItem: true }],
          [types.default.ADD_CRM_STAGE, { id: 3, name: 'New' }],
          [types.default.SET_CRM_STAGES_UI_FLAG, { creatingItem: false }],
        ]);
      });

      it('throws on error', async () => {
        CrmStagesAPI.create.mockRejectedValue({ message: 'fail' });
        await expect(
          actions.create({ commit }, { pipelineId: 10 })
        ).rejects.toThrow(Error);
      });
    });

    describe('update', () => {
      it('forwards pipelineId, id, data and commits EDIT', async () => {
        CrmStagesAPI.update.mockResolvedValue({
          data: { id: 1, name: 'Updated' },
        });
        await actions.update(
          { commit },
          { pipelineId: 10, id: 1, name: 'Updated' }
        );
        expect(CrmStagesAPI.update).toHaveBeenCalledWith(10, 1, {
          name: 'Updated',
        });
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_STAGES_UI_FLAG, { updatingItem: true }],
          [types.default.EDIT_CRM_STAGE, { id: 1, name: 'Updated' }],
          [types.default.SET_CRM_STAGES_UI_FLAG, { updatingItem: false }],
        ]);
      });
    });

    describe('delete', () => {
      it('forwards pipelineId + id and commits DELETE', async () => {
        CrmStagesAPI.delete.mockResolvedValue({});
        await actions.delete({ commit }, { pipelineId: 10, id: 1 });
        expect(CrmStagesAPI.delete).toHaveBeenCalledWith(10, 1);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_STAGES_UI_FLAG, { deletingItem: true }],
          [types.default.DELETE_CRM_STAGE, 1],
          [types.default.SET_CRM_STAGES_UI_FLAG, { deletingItem: false }],
        ]);
      });
    });

    describe('reorder', () => {
      it('forwards ids and commits REORDER with pipelineId', async () => {
        CrmStagesAPI.reorder.mockResolvedValue({
          data: [{ id: 2 }, { id: 1 }],
        });
        await actions.reorder({ commit }, { pipelineId: 10, stageIds: [2, 1] });
        expect(CrmStagesAPI.reorder).toHaveBeenCalledWith(10, [2, 1]);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_STAGES_UI_FLAG, { reordering: true }],
          [
            types.default.REORDER_CRM_STAGES,
            { pipelineId: 10, stages: [{ id: 2 }, { id: 1 }] },
          ],
          [types.default.SET_CRM_STAGES_UI_FLAG, { reordering: false }],
        ]);
      });

      it('throws on error', async () => {
        CrmStagesAPI.reorder.mockRejectedValue({ message: 'fail' });
        await expect(
          actions.reorder({ commit }, { pipelineId: 10, stageIds: [] })
        ).rejects.toThrow(Error);
      });
    });
  });

  describe('Default export', () => {
    it('exposes state/getters/actions/mutations', () => {
      expect(storeModule).toHaveProperty('state');
      expect(storeModule).toHaveProperty('getters');
      expect(storeModule).toHaveProperty('actions');
      expect(storeModule).toHaveProperty('mutations');
    });
  });
});
