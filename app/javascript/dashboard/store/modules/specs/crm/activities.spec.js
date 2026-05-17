import { describe, it, expect, vi, beforeEach } from 'vitest';
import CrmActivitiesAPI from 'dashboard/api/crm/activities';
import storeModule, {
  state as initialState,
  getters,
  actions,
  mutations,
} from '../../crm/activities';
import * as types from '../../../mutation-types';

vi.mock('dashboard/api/crm/activities', () => ({
  default: {
    get: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    complete: vi.fn(),
  },
}));

describe('CRM Activities Store', () => {
  let commit;

  beforeEach(() => {
    vi.clearAllMocks();
    commit = vi.fn();
  });

  describe('Initial State', () => {
    it('has records + uiFlags shape with completing flag', () => {
      expect(initialState).toEqual({
        records: [],
        uiFlags: {
          fetchingList: false,
          fetchingItem: false,
          creatingItem: false,
          updatingItem: false,
          deletingItem: false,
          completing: false,
        },
      });
    });
  });

  describe('Getters', () => {
    const state = {
      records: [
        { id: 1, title: 'Call', crm_opportunity_id: 10 },
        { id: 2, title: 'Email', crm_opportunity_id: 10 },
        { id: 3, title: 'Demo', crm_opportunity_id: 20 },
      ],
      uiFlags: { fetchingList: true },
    };

    it('getCrmActivities returns all records', () => {
      expect(getters.getCrmActivities(state)).toEqual(state.records);
    });

    it('getCrmActivitiesForOpportunity filters by opportunity_id', () => {
      const result = getters.getCrmActivitiesForOpportunity(state)(10);
      expect(result.map(a => a.id)).toEqual([1, 2]);
    });

    it('getCrmActivitiesForOpportunity coerces string id to number', () => {
      const result = getters.getCrmActivitiesForOpportunity(state)('20');
      expect(result.map(a => a.id)).toEqual([3]);
    });

    it('getUIFlags returns uiFlags', () => {
      expect(getters.getUIFlags(state)).toEqual({ fetchingList: true });
    });
  });

  describe('Mutations', () => {
    it('SET_CRM_ACTIVITIES_UI_FLAG merges flags', () => {
      const state = { uiFlags: { completing: false } };
      mutations[types.default.SET_CRM_ACTIVITIES_UI_FLAG](state, {
        completing: true,
      });
      expect(state.uiFlags).toEqual({ completing: true });
    });

    it('SET_CRM_ACTIVITIES replaces records', () => {
      const state = { records: [] };
      mutations[types.default.SET_CRM_ACTIVITIES](state, [{ id: 1 }]);
      expect(state.records).toEqual([{ id: 1 }]);
    });

    it('ADD_CRM_ACTIVITY pushes to records', () => {
      const state = { records: [{ id: 1 }] };
      mutations[types.default.ADD_CRM_ACTIVITY](state, { id: 2 });
      expect(state.records).toEqual([{ id: 1 }, { id: 2 }]);
    });

    it('EDIT_CRM_ACTIVITY replaces matching record', () => {
      const state = { records: [{ id: 1, title: 'old' }] };
      mutations[types.default.EDIT_CRM_ACTIVITY](state, {
        id: 1,
        title: 'new',
      });
      expect(state.records).toEqual([{ id: 1, title: 'new' }]);
    });

    it('DELETE_CRM_ACTIVITY removes by id', () => {
      const state = { records: [{ id: 1 }, { id: 2 }] };
      mutations[types.default.DELETE_CRM_ACTIVITY](state, 1);
      expect(state.records).toEqual([{ id: 2 }]);
    });

    it('COMPLETE_CRM_ACTIVITY updates completed_at in-place', () => {
      const state = {
        records: [
          { id: 1, title: 'Call', completed_at: null },
          { id: 2, title: 'Email', completed_at: null },
        ],
      };
      const completedAt = '2026-05-17T12:00:00Z';
      mutations[types.default.COMPLETE_CRM_ACTIVITY](state, {
        id: 1,
        title: 'Call',
        completed_at: completedAt,
      });
      expect(state.records).toEqual([
        { id: 1, title: 'Call', completed_at: completedAt },
        { id: 2, title: 'Email', completed_at: null },
      ]);
    });
  });

  describe('Actions', () => {
    describe('get', () => {
      it('commits SET + UI flag on success', async () => {
        CrmActivitiesAPI.get.mockResolvedValue({ data: [{ id: 1 }] });
        await actions.get({ commit }, 10);
        expect(CrmActivitiesAPI.get).toHaveBeenCalledWith(10);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_ACTIVITIES_UI_FLAG, { fetchingList: true }],
          [types.default.SET_CRM_ACTIVITIES, [{ id: 1 }]],
          [types.default.SET_CRM_ACTIVITIES_UI_FLAG, { fetchingList: false }],
        ]);
      });

      it('clears UI flag on error (silent)', async () => {
        CrmActivitiesAPI.get.mockRejectedValue(new Error('boom'));
        await actions.get({ commit }, 10);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_ACTIVITIES_UI_FLAG, { fetchingList: true }],
          [types.default.SET_CRM_ACTIVITIES_UI_FLAG, { fetchingList: false }],
        ]);
      });
    });

    describe('create', () => {
      it('commits ADD on success and strips opportunityId from payload', async () => {
        CrmActivitiesAPI.create.mockResolvedValue({
          data: { id: 3, title: 'New', crm_opportunity_id: 10 },
        });
        const result = await actions.create(
          { commit },
          { opportunityId: 10, title: 'New' }
        );
        expect(CrmActivitiesAPI.create).toHaveBeenCalledWith(10, {
          title: 'New',
        });
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_ACTIVITIES_UI_FLAG, { creatingItem: true }],
          [
            types.default.ADD_CRM_ACTIVITY,
            { id: 3, title: 'New', crm_opportunity_id: 10 },
          ],
          [types.default.SET_CRM_ACTIVITIES_UI_FLAG, { creatingItem: false }],
        ]);
        expect(result).toEqual({ id: 3, title: 'New', crm_opportunity_id: 10 });
      });

      it('throws on error', async () => {
        CrmActivitiesAPI.create.mockRejectedValue({ message: 'fail' });
        await expect(
          actions.create({ commit }, { opportunityId: 10 })
        ).rejects.toThrow(Error);
        expect(commit).toHaveBeenLastCalledWith(
          types.default.SET_CRM_ACTIVITIES_UI_FLAG,
          { creatingItem: false }
        );
      });
    });

    describe('update', () => {
      it('commits EDIT on success and strips opportunityId/id from payload', async () => {
        CrmActivitiesAPI.update.mockResolvedValue({
          data: { id: 1, title: 'Updated' },
        });
        await actions.update(
          { commit },
          { opportunityId: 10, id: 1, title: 'Updated' }
        );
        expect(CrmActivitiesAPI.update).toHaveBeenCalledWith(10, 1, {
          title: 'Updated',
        });
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_ACTIVITIES_UI_FLAG, { updatingItem: true }],
          [types.default.EDIT_CRM_ACTIVITY, { id: 1, title: 'Updated' }],
          [types.default.SET_CRM_ACTIVITIES_UI_FLAG, { updatingItem: false }],
        ]);
      });

      it('throws on error', async () => {
        CrmActivitiesAPI.update.mockRejectedValue({ message: 'fail' });
        await expect(
          actions.update({ commit }, { opportunityId: 10, id: 1, title: 'x' })
        ).rejects.toThrow(Error);
      });
    });

    describe('delete', () => {
      it('commits DELETE on success', async () => {
        CrmActivitiesAPI.delete.mockResolvedValue({});
        await actions.delete({ commit }, { opportunityId: 10, id: 1 });
        expect(CrmActivitiesAPI.delete).toHaveBeenCalledWith(10, 1);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_ACTIVITIES_UI_FLAG, { deletingItem: true }],
          [types.default.DELETE_CRM_ACTIVITY, 1],
          [types.default.SET_CRM_ACTIVITIES_UI_FLAG, { deletingItem: false }],
        ]);
      });

      it('throws on error', async () => {
        CrmActivitiesAPI.delete.mockRejectedValue({ message: 'fail' });
        await expect(
          actions.delete({ commit }, { opportunityId: 10, id: 1 })
        ).rejects.toThrow(Error);
      });
    });

    describe('complete', () => {
      it('commits COMPLETE on success', async () => {
        const completedAt = '2026-05-17T12:00:00Z';
        CrmActivitiesAPI.complete.mockResolvedValue({
          data: { id: 1, title: 'Call', completed_at: completedAt },
        });
        const result = await actions.complete(
          { commit },
          { opportunityId: 10, id: 1 }
        );
        expect(CrmActivitiesAPI.complete).toHaveBeenCalledWith(10, 1);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_ACTIVITIES_UI_FLAG, { completing: true }],
          [
            types.default.COMPLETE_CRM_ACTIVITY,
            { id: 1, title: 'Call', completed_at: completedAt },
          ],
          [types.default.SET_CRM_ACTIVITIES_UI_FLAG, { completing: false }],
        ]);
        expect(result).toEqual({
          id: 1,
          title: 'Call',
          completed_at: completedAt,
        });
      });

      it('throws on error and clears completing flag', async () => {
        CrmActivitiesAPI.complete.mockRejectedValue({ message: 'fail' });
        await expect(
          actions.complete({ commit }, { opportunityId: 10, id: 1 })
        ).rejects.toThrow(Error);
        expect(commit).toHaveBeenLastCalledWith(
          types.default.SET_CRM_ACTIVITIES_UI_FLAG,
          { completing: false }
        );
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
