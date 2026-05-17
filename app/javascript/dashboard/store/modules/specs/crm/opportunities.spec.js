import { describe, it, expect, vi, beforeEach } from 'vitest';
import CrmOpportunitiesAPI from 'dashboard/api/crm/opportunities';
import storeModule, {
  state as initialState,
  getters,
  actions,
  mutations,
} from '../../crm/opportunities';
import * as types from '../../../mutation-types';

vi.mock('dashboard/api/crm/opportunities', () => ({
  default: {
    get: vi.fn(),
    show: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    moveToStage: vi.fn(),
    discard: vi.fn(),
  },
}));

describe('CRM Opportunities Store', () => {
  let commit;

  beforeEach(() => {
    vi.clearAllMocks();
    commit = vi.fn();
  });

  describe('Initial State', () => {
    it('has records + uiFlags with movingToStage + discarding', () => {
      expect(initialState).toEqual({
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
      });
    });
  });

  describe('Getters', () => {
    const state = {
      records: [
        { id: 1, title: 'Deal A', crm_stage_id: 100 },
        { id: 2, title: 'Deal B', crm_stage_id: 100 },
        { id: 3, title: 'Deal C', crm_stage_id: 200 },
      ],
      uiFlags: { fetchingList: true },
    };

    it('getCrmOpportunities returns all records', () => {
      expect(getters.getCrmOpportunities(state)).toEqual(state.records);
    });

    it('getCrmOpportunitiesForStage filters by stage', () => {
      const result = getters.getCrmOpportunitiesForStage(state)(100);
      expect(result.map(o => o.id)).toEqual([1, 2]);
    });

    it('getCrmOpportunity returns by id', () => {
      expect(getters.getCrmOpportunity(state)(3)).toEqual({
        id: 3,
        title: 'Deal C',
        crm_stage_id: 200,
      });
    });

    it('getUIFlags returns uiFlags', () => {
      expect(getters.getUIFlags(state)).toEqual({ fetchingList: true });
    });
  });

  describe('Mutations', () => {
    it('SET_CRM_OPPORTUNITIES_UI_FLAG merges flags', () => {
      const state = { uiFlags: { discarding: false } };
      mutations[types.default.SET_CRM_OPPORTUNITIES_UI_FLAG](state, {
        discarding: true,
      });
      expect(state.uiFlags).toEqual({ discarding: true });
    });

    it('SET_CRM_OPPORTUNITIES replaces records', () => {
      const state = { records: [] };
      mutations[types.default.SET_CRM_OPPORTUNITIES](state, [{ id: 1 }]);
      expect(state.records).toEqual([{ id: 1 }]);
    });

    it('ADD_CRM_OPPORTUNITY pushes record', () => {
      const state = { records: [{ id: 1 }] };
      mutations[types.default.ADD_CRM_OPPORTUNITY](state, { id: 2 });
      expect(state.records).toEqual([{ id: 1 }, { id: 2 }]);
    });

    it('EDIT_CRM_OPPORTUNITY replaces matching record', () => {
      const state = { records: [{ id: 1, title: 'old' }] };
      mutations[types.default.EDIT_CRM_OPPORTUNITY](state, {
        id: 1,
        title: 'new',
      });
      expect(state.records).toEqual([{ id: 1, title: 'new' }]);
    });

    it('DELETE_CRM_OPPORTUNITY removes by id', () => {
      const state = { records: [{ id: 1 }, { id: 2 }] };
      mutations[types.default.DELETE_CRM_OPPORTUNITY](state, 1);
      expect(state.records).toEqual([{ id: 2 }]);
    });

    it('MOVE_CRM_OPPORTUNITY_TO_STAGE updates crm_stage_id', () => {
      const state = {
        records: [
          { id: 1, crm_stage_id: 100 },
          { id: 2, crm_stage_id: 100 },
        ],
      };
      mutations[types.default.MOVE_CRM_OPPORTUNITY_TO_STAGE](state, {
        id: 1,
        crm_stage_id: 200,
      });
      expect(state.records).toEqual([
        { id: 1, crm_stage_id: 200 },
        { id: 2, crm_stage_id: 100 },
      ]);
    });

    it('DISCARD_CRM_OPPORTUNITY removes by id', () => {
      const state = { records: [{ id: 1 }, { id: 2 }] };
      mutations[types.default.DISCARD_CRM_OPPORTUNITY](state, 1);
      expect(state.records).toEqual([{ id: 2 }]);
    });
  });

  describe('Actions', () => {
    describe('get', () => {
      it('passes snake_case params and commits SET', async () => {
        CrmOpportunitiesAPI.get.mockResolvedValue({ data: [{ id: 1 }] });
        await actions.get({ commit }, { pipeline_id: 10 });
        expect(CrmOpportunitiesAPI.get).toHaveBeenCalledWith({
          pipeline_id: 10,
        });
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, { fetchingList: true }],
          [types.default.SET_CRM_OPPORTUNITIES, [{ id: 1 }]],
          [
            types.default.SET_CRM_OPPORTUNITIES_UI_FLAG,
            { fetchingList: false },
          ],
        ]);
      });

      it('clears UI flag on error (silent)', async () => {
        CrmOpportunitiesAPI.get.mockRejectedValue(new Error('boom'));
        await actions.get({ commit });
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, { fetchingList: true }],
          [
            types.default.SET_CRM_OPPORTUNITIES_UI_FLAG,
            { fetchingList: false },
          ],
        ]);
      });
    });

    describe('create', () => {
      it('commits ADD on success', async () => {
        const payload = { title: 'New', crm_stage_id: 100 };
        CrmOpportunitiesAPI.create.mockResolvedValue({
          data: { id: 9, ...payload },
        });
        const result = await actions.create({ commit }, payload);
        expect(CrmOpportunitiesAPI.create).toHaveBeenCalledWith(payload);
        expect(result).toEqual({ id: 9, ...payload });
      });

      it('throws on error', async () => {
        CrmOpportunitiesAPI.create.mockRejectedValue({ message: 'fail' });
        await expect(actions.create({ commit }, {})).rejects.toThrow(Error);
      });
    });

    describe('update', () => {
      it('commits EDIT on success', async () => {
        CrmOpportunitiesAPI.update.mockResolvedValue({
          data: { id: 1, status: 'won' },
        });
        await actions.update({ commit }, { id: 1, status: 'won' });
        expect(CrmOpportunitiesAPI.update).toHaveBeenCalledWith(1, {
          status: 'won',
        });
        expect(commit).toHaveBeenCalledWith(
          types.default.EDIT_CRM_OPPORTUNITY,
          {
            id: 1,
            status: 'won',
          }
        );
      });
    });

    describe('delete', () => {
      it('commits DELETE on success', async () => {
        CrmOpportunitiesAPI.delete.mockResolvedValue({});
        await actions.delete({ commit }, 1);
        expect(commit).toHaveBeenCalledWith(
          types.default.DELETE_CRM_OPPORTUNITY,
          1
        );
      });
    });

    describe('moveToStage', () => {
      it('forwards args and commits MOVE with response data', async () => {
        CrmOpportunitiesAPI.moveToStage.mockResolvedValue({
          data: { id: 1, crm_stage_id: 200 },
        });
        await actions.moveToStage(
          { commit },
          { id: 1, stageId: 200, reason: 'qualified' }
        );
        expect(CrmOpportunitiesAPI.moveToStage).toHaveBeenCalledWith(
          1,
          200,
          'qualified'
        );
        expect(commit.mock.calls).toEqual([
          [
            types.default.SET_CRM_OPPORTUNITIES_UI_FLAG,
            { movingToStage: true },
          ],
          [
            types.default.MOVE_CRM_OPPORTUNITY_TO_STAGE,
            { id: 1, crm_stage_id: 200 },
          ],
          [
            types.default.SET_CRM_OPPORTUNITIES_UI_FLAG,
            { movingToStage: false },
          ],
        ]);
      });

      it('defaults reason to null', async () => {
        CrmOpportunitiesAPI.moveToStage.mockResolvedValue({ data: { id: 1 } });
        await actions.moveToStage({ commit }, { id: 1, stageId: 200 });
        expect(CrmOpportunitiesAPI.moveToStage).toHaveBeenCalledWith(
          1,
          200,
          null
        );
      });

      it('throws on error', async () => {
        CrmOpportunitiesAPI.moveToStage.mockRejectedValue({ message: 'fail' });
        await expect(
          actions.moveToStage({ commit }, { id: 1, stageId: 200 })
        ).rejects.toThrow(Error);
      });
    });

    describe('discard', () => {
      it('commits DISCARD on success', async () => {
        CrmOpportunitiesAPI.discard.mockResolvedValue({});
        await actions.discard({ commit }, 1);
        expect(CrmOpportunitiesAPI.discard).toHaveBeenCalledWith(1);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, { discarding: true }],
          [types.default.DISCARD_CRM_OPPORTUNITY, 1],
          [types.default.SET_CRM_OPPORTUNITIES_UI_FLAG, { discarding: false }],
        ]);
      });

      it('throws on error', async () => {
        CrmOpportunitiesAPI.discard.mockRejectedValue({ message: 'fail' });
        await expect(actions.discard({ commit }, 1)).rejects.toThrow(Error);
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
