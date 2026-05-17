import { describe, it, expect, vi, beforeEach } from 'vitest';
import CrmCompaniesAPI from 'dashboard/api/crm/companies';
import storeModule, {
  state as initialState,
  getters,
  actions,
  mutations,
} from '../../crm/companies';
import * as types from '../../../mutation-types';

vi.mock('dashboard/api/crm/companies', () => ({
  default: {
    get: vi.fn(),
    show: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
  },
}));

describe('CRM Companies Store', () => {
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
        { id: 1, name: 'Acme' },
        { id: 2, name: 'Globex' },
      ],
      uiFlags: { fetchingList: true },
    };

    it('getCrmCompanies returns records', () => {
      expect(getters.getCrmCompanies(state)).toEqual(state.records);
    });

    it('getCrmCompany returns company by id', () => {
      expect(getters.getCrmCompany(state)(1)).toEqual({ id: 1, name: 'Acme' });
    });

    it('getCrmCompany coerces string id to number', () => {
      expect(getters.getCrmCompany(state)('2')).toEqual({
        id: 2,
        name: 'Globex',
      });
    });

    it('getUIFlags returns uiFlags', () => {
      expect(getters.getUIFlags(state)).toEqual({ fetchingList: true });
    });
  });

  describe('Mutations', () => {
    it('SET_CRM_COMPANIES_UI_FLAG merges flags', () => {
      const state = { uiFlags: { fetchingList: false, creatingItem: false } };
      mutations[types.default.SET_CRM_COMPANIES_UI_FLAG](state, {
        fetchingList: true,
      });
      expect(state.uiFlags).toEqual({
        fetchingList: true,
        creatingItem: false,
      });
    });

    it('SET_CRM_COMPANIES replaces records', () => {
      const state = { records: [] };
      mutations[types.default.SET_CRM_COMPANIES](state, [{ id: 1 }]);
      expect(state.records).toEqual([{ id: 1 }]);
    });

    it('ADD_CRM_COMPANY pushes to records', () => {
      const state = { records: [{ id: 1 }] };
      mutations[types.default.ADD_CRM_COMPANY](state, { id: 2 });
      expect(state.records).toEqual([{ id: 1 }, { id: 2 }]);
    });

    it('EDIT_CRM_COMPANY replaces matching record', () => {
      const state = { records: [{ id: 1, name: 'old' }] };
      mutations[types.default.EDIT_CRM_COMPANY](state, {
        id: 1,
        name: 'new',
      });
      expect(state.records).toEqual([{ id: 1, name: 'new' }]);
    });

    it('DELETE_CRM_COMPANY removes by id', () => {
      const state = { records: [{ id: 1 }, { id: 2 }] };
      mutations[types.default.DELETE_CRM_COMPANY](state, 1);
      expect(state.records).toEqual([{ id: 2 }]);
    });
  });

  describe('Actions', () => {
    describe('get', () => {
      it('commits SET + UI flag on success', async () => {
        CrmCompaniesAPI.get.mockResolvedValue({ data: [{ id: 1 }] });
        await actions.get({ commit });
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_COMPANIES_UI_FLAG, { fetchingList: true }],
          [types.default.SET_CRM_COMPANIES, [{ id: 1 }]],
          [types.default.SET_CRM_COMPANIES_UI_FLAG, { fetchingList: false }],
        ]);
      });

      it('clears UI flag on error (silent)', async () => {
        CrmCompaniesAPI.get.mockRejectedValue(new Error('boom'));
        await actions.get({ commit });
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_COMPANIES_UI_FLAG, { fetchingList: true }],
          [types.default.SET_CRM_COMPANIES_UI_FLAG, { fetchingList: false }],
        ]);
      });
    });

    describe('show', () => {
      it('commits ADD on success when record absent (deep-link cold cache)', async () => {
        CrmCompaniesAPI.show.mockResolvedValue({ data: { id: 1, name: 'A' } });
        const state = { records: [] };
        const result = await actions.show({ commit, state }, 1);
        expect(CrmCompaniesAPI.show).toHaveBeenCalledWith(1);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_COMPANIES_UI_FLAG, { fetchingItem: true }],
          [types.default.ADD_CRM_COMPANY, { id: 1, name: 'A' }],
          [types.default.SET_CRM_COMPANIES_UI_FLAG, { fetchingItem: false }],
        ]);
        expect(result).toEqual({ id: 1, name: 'A' });
      });

      it('commits EDIT on success when record already exists', async () => {
        CrmCompaniesAPI.show.mockResolvedValue({
          data: { id: 1, name: 'Updated' },
        });
        const state = { records: [{ id: 1, name: 'Old' }] };
        await actions.show({ commit, state }, 1);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_COMPANIES_UI_FLAG, { fetchingItem: true }],
          [types.default.EDIT_CRM_COMPANY, { id: 1, name: 'Updated' }],
          [types.default.SET_CRM_COMPANIES_UI_FLAG, { fetchingItem: false }],
        ]);
      });

      it('throws on error', async () => {
        CrmCompaniesAPI.show.mockRejectedValue({ message: 'fail' });
        await expect(actions.show({ commit }, 1)).rejects.toThrow(Error);
        expect(commit).toHaveBeenLastCalledWith(
          types.default.SET_CRM_COMPANIES_UI_FLAG,
          { fetchingItem: false }
        );
      });
    });

    describe('create', () => {
      it('commits ADD on success', async () => {
        const payload = { name: 'New' };
        CrmCompaniesAPI.create.mockResolvedValue({
          data: { id: 3, ...payload },
        });
        const result = await actions.create({ commit }, payload);
        expect(CrmCompaniesAPI.create).toHaveBeenCalledWith(payload);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_COMPANIES_UI_FLAG, { creatingItem: true }],
          [types.default.ADD_CRM_COMPANY, { id: 3, name: 'New' }],
          [types.default.SET_CRM_COMPANIES_UI_FLAG, { creatingItem: false }],
        ]);
        expect(result).toEqual({ id: 3, name: 'New' });
      });

      it('throws on error', async () => {
        CrmCompaniesAPI.create.mockRejectedValue({ message: 'fail' });
        await expect(actions.create({ commit }, {})).rejects.toThrow(Error);
        expect(commit).toHaveBeenLastCalledWith(
          types.default.SET_CRM_COMPANIES_UI_FLAG,
          { creatingItem: false }
        );
      });
    });

    describe('update', () => {
      it('commits EDIT on success', async () => {
        CrmCompaniesAPI.update.mockResolvedValue({
          data: { id: 1, name: 'Updated' },
        });
        await actions.update({ commit }, { id: 1, name: 'Updated' });
        expect(CrmCompaniesAPI.update).toHaveBeenCalledWith(1, {
          name: 'Updated',
        });
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_COMPANIES_UI_FLAG, { updatingItem: true }],
          [types.default.EDIT_CRM_COMPANY, { id: 1, name: 'Updated' }],
          [types.default.SET_CRM_COMPANIES_UI_FLAG, { updatingItem: false }],
        ]);
      });

      it('throws on error', async () => {
        CrmCompaniesAPI.update.mockRejectedValue({ message: 'fail' });
        await expect(
          actions.update({ commit }, { id: 1, name: 'x' })
        ).rejects.toThrow(Error);
        expect(commit).toHaveBeenLastCalledWith(
          types.default.SET_CRM_COMPANIES_UI_FLAG,
          { updatingItem: false }
        );
      });
    });

    describe('delete', () => {
      it('commits DELETE on success', async () => {
        CrmCompaniesAPI.delete.mockResolvedValue({});
        await actions.delete({ commit }, 1);
        expect(CrmCompaniesAPI.delete).toHaveBeenCalledWith(1);
        expect(commit.mock.calls).toEqual([
          [types.default.SET_CRM_COMPANIES_UI_FLAG, { deletingItem: true }],
          [types.default.DELETE_CRM_COMPANY, 1],
          [types.default.SET_CRM_COMPANIES_UI_FLAG, { deletingItem: false }],
        ]);
      });

      it('throws on error', async () => {
        CrmCompaniesAPI.delete.mockRejectedValue({ message: 'fail' });
        await expect(actions.delete({ commit }, 1)).rejects.toThrow(Error);
        expect(commit).toHaveBeenLastCalledWith(
          types.default.SET_CRM_COMPANIES_UI_FLAG,
          { deletingItem: false }
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
