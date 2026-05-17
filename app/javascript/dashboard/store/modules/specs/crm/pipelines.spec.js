import { describe, it, expect, vi, beforeEach } from 'vitest';
import CrmPipelinesAPI from 'dashboard/api/crm/pipelines';
import storeModule, {
  state as initialState,
  getters,
  actions,
  mutations,
} from '../../crm/pipelines';
import * as types from '../../../mutation-types';

vi.mock('dashboard/api/crm/pipelines', () => ({
  default: {
    get: vi.fn(),
    show: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
  },
}));

describe('CRM Pipelines Store', () => {
  let commit;

  beforeEach(() => {
    vi.clearAllMocks();
    commit = vi.fn();
  });

  describe('Initial State', () => {
    it('has records + uiFlags shape', () => {
      expect(initialState).toEqual({
        records: [],
        uiFlags: {
          fetchingList: false,
          fetchingItem: false,
          creatingItem: false,
          updatingItem: false,
          deletingItem: false,
        },
      });
    });
  });

  describe('Getters', () => {
    const state = {
      records: [
        { id: 1, name: 'Sales' },
        { id: 2, name: 'Onboarding' },
      ],
      uiFlags: { fetchingList: true },
    };

    it('getCrmPipelines returns records', () => {
      expect(getters.getCrmPipelines(state)).toEqual(state.records);
    });

    it('getCrmPipeline returns pipeline by id', () => {
      expect(getters.getCrmPipeline(state)(1)).toEqual({
        id: 1,
        name: 'Sales',
      });
    });

    it('getUIFlags returns uiFlags', () => {
      expect(getters.getUIFlags(state)).toEqual({ fetchingList: true });
    });
  });

  describe('Mutations', () => {
    it('SET_CRM_PIPELINES_UI_FLAG merges flags', () => {
      const state = { uiFlags: { fetchingList: false, creatingItem: false } };
      mutations[types.default.SET_CRM_PIPELINES_UI_FLAG](state, {
        fetchingList: true,
      });
      expect(state.uiFlags).toEqual({
        fetchingList: true,
        creatingItem: false,
      });
    });

    it('SET_CRM_PIPELINES replaces records', () => {
      const state = { records: [] };
      mutations[types.default.SET_CRM_PIPELINES](state, [{ id: 1 }]);
      expect(state.records).toEqual([{ id: 1 }]);
    });

    it('ADD_CRM_PIPELINE pushes to records', () => {
      const state = { records: [{ id: 1 }] };
      mutations[types.default.ADD_CRM_PIPELINE](state, { id: 2 });
      expect(state.records).toEqual([{ id: 1 }, { id: 2 }]);
    });

    it('EDIT_CRM_PIPELINE replaces matching record', () => {
      const state = { records: [{ id: 1, name: 'old' }] };
      mutations[types.default.EDIT_CRM_PIPELINE](state, {
        id: 1,
        name: 'new',
      });
      expect(state.records).toEqual([{ id: 1, name: 'new' }]);
    });

    it('DELETE_CRM_PIPELINE removes by id', () => {
      const state = { records: [{ id: 1 }, { id: 2 }] };
      mutations[types.default.DELETE_CRM_PIPELINE](state, 1);
      expect(state.records).toEqual([{ id: 2 }]);
    });
  });

  describe('Actions', () => {
    describe('get', () => {
      it('commits SET + UI flag on success', async () => {
        CrmPipelinesAPI.get.mockResolvedValue({ data: [{ id: 1 }] });
        await actions.get({ commit });
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_PIPELINES_UI_FLAG, { fetchingList: true }],
          [types.default.SET_CRM_PIPELINES, [{ id: 1 }]],
          [types.default.SET_CRM_PIPELINES_UI_FLAG, { fetchingList: false }],
        ]);
      });

      it('clears UI flag on error (silent)', async () => {
        CrmPipelinesAPI.get.mockRejectedValue(new Error('boom'));
        await actions.get({ commit });
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_PIPELINES_UI_FLAG, { fetchingList: true }],
          [types.default.SET_CRM_PIPELINES_UI_FLAG, { fetchingList: false }],
        ]);
      });
    });

    describe('create', () => {
      it('commits ADD on success', async () => {
        const payload = { name: 'New' };
        CrmPipelinesAPI.create.mockResolvedValue({
          data: { id: 3, ...payload },
        });
        const result = await actions.create({ commit }, payload);
        expect(CrmPipelinesAPI.create).toHaveBeenCalledWith(payload);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_PIPELINES_UI_FLAG, { creatingItem: true }],
          [types.default.ADD_CRM_PIPELINE, { id: 3, name: 'New' }],
          [types.default.SET_CRM_PIPELINES_UI_FLAG, { creatingItem: false }],
        ]);
        expect(result).toEqual({ id: 3, name: 'New' });
      });

      it('throws on error', async () => {
        CrmPipelinesAPI.create.mockRejectedValue({ message: 'fail' });
        await expect(actions.create({ commit }, {})).rejects.toThrow(Error);
        expect(commit).toHaveBeenLastCalledWith(
          types.default.SET_CRM_PIPELINES_UI_FLAG,
          { creatingItem: false }
        );
      });
    });

    describe('update', () => {
      it('commits EDIT on success', async () => {
        CrmPipelinesAPI.update.mockResolvedValue({
          data: { id: 1, name: 'Updated' },
        });
        await actions.update({ commit }, { id: 1, name: 'Updated' });
        expect(CrmPipelinesAPI.update).toHaveBeenCalledWith(1, {
          name: 'Updated',
        });
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_PIPELINES_UI_FLAG, { updatingItem: true }],
          [types.default.EDIT_CRM_PIPELINE, { id: 1, name: 'Updated' }],
          [types.default.SET_CRM_PIPELINES_UI_FLAG, { updatingItem: false }],
        ]);
      });

      it('throws on error', async () => {
        CrmPipelinesAPI.update.mockRejectedValue({ message: 'fail' });
        await expect(
          actions.update({ commit }, { id: 1, name: 'x' })
        ).rejects.toThrow(Error);
      });
    });

    describe('delete', () => {
      it('commits DELETE on success', async () => {
        CrmPipelinesAPI.delete.mockResolvedValue({});
        await actions.delete({ commit }, 1);
        expect(CrmPipelinesAPI.delete).toHaveBeenCalledWith(1);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_PIPELINES_UI_FLAG, { deletingItem: true }],
          [types.default.DELETE_CRM_PIPELINE, 1],
          [types.default.SET_CRM_PIPELINES_UI_FLAG, { deletingItem: false }],
        ]);
      });

      it('throws on error', async () => {
        CrmPipelinesAPI.delete.mockRejectedValue({ message: 'fail' });
        await expect(actions.delete({ commit }, 1)).rejects.toThrow(Error);
      });
    });

    describe('show', () => {
      it('commits EDIT on success', async () => {
        CrmPipelinesAPI.show.mockResolvedValue({ data: { id: 1, name: 'A' } });
        const result = await actions.show({ commit }, 1);
        expect(CrmPipelinesAPI.show).toHaveBeenCalledWith(1);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_PIPELINES_UI_FLAG, { fetchingItem: true }],
          [types.default.EDIT_CRM_PIPELINE, { id: 1, name: 'A' }],
          [types.default.SET_CRM_PIPELINES_UI_FLAG, { fetchingItem: false }],
        ]);
        expect(result).toEqual({ id: 1, name: 'A' });
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
