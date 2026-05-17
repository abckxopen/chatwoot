import ApiClient from '../../ApiClient';
import crmStages from '../../crm/stages';

describe('#CrmStagesAPI', () => {
  it('creates correct instance with required methods', () => {
    expect(crmStages).toBeInstanceOf(ApiClient);
    expect(crmStages).toHaveProperty('get');
    expect(crmStages).toHaveProperty('show');
    expect(crmStages).toHaveProperty('create');
    expect(crmStages).toHaveProperty('update');
    expect(crmStages).toHaveProperty('delete');
    expect(crmStages).toHaveProperty('reorder');
  });

  describe('inside account-scoped URL', () => {
    const originalAxios = window.axios;
    const originalPathname = window.location.pathname;
    const axiosMock = {
      get: vi.fn(() => Promise.resolve()),
      post: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
      window.history.pushState({}, '', '/app/accounts/1/settings');
    });

    afterEach(() => {
      window.axios = originalAxios;
      window.history.pushState({}, '', originalPathname);
    });

    it('lists stages under a pipeline', () => {
      crmStages.get(10);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_pipelines/10/stages'
      );
    });

    it('shows a stage', () => {
      crmStages.show(10, 5);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_pipelines/10/stages/5'
      );
    });

    it('creates a stage under a pipeline', () => {
      crmStages.create(10, { name: 'Lead' });
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_pipelines/10/stages',
        { name: 'Lead' }
      );
    });

    it('updates a stage', () => {
      crmStages.update(10, 5, { name: 'New' });
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_pipelines/10/stages/5',
        { name: 'New' }
      );
    });

    it('deletes a stage', () => {
      crmStages.delete(10, 5);
      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_pipelines/10/stages/5'
      );
    });

    it('reorders stages with stage_ids payload', () => {
      crmStages.reorder(10, [3, 1, 2]);
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_pipelines/10/stages/reorder',
        { stage_ids: [3, 1, 2] }
      );
    });
  });
});
