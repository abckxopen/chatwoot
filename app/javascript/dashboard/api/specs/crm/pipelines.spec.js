import ApiClient from '../../ApiClient';
import crmPipelines from '../../crm/pipelines';

describe('#CrmPipelinesAPI', () => {
  it('creates correct instance with account-scoped resource', () => {
    expect(crmPipelines).toBeInstanceOf(ApiClient);
    expect(crmPipelines).toHaveProperty('get');
    expect(crmPipelines).toHaveProperty('show');
    expect(crmPipelines).toHaveProperty('create');
    expect(crmPipelines).toHaveProperty('update');
    expect(crmPipelines).toHaveProperty('delete');
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

    it('lists pipelines at the right endpoint', () => {
      crmPipelines.get();
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_pipelines'
      );
    });

    it('shows by id', () => {
      crmPipelines.show(42);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_pipelines/42'
      );
    });

    it('creates with payload', () => {
      crmPipelines.create({ name: 'Sales' });
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_pipelines',
        { name: 'Sales' }
      );
    });

    it('updates by id', () => {
      crmPipelines.update(7, { name: 'Updated' });
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_pipelines/7',
        { name: 'Updated' }
      );
    });

    it('deletes by id', () => {
      crmPipelines.delete(7);
      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_pipelines/7'
      );
    });
  });
});
