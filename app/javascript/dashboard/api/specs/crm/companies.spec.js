import ApiClient from '../../ApiClient';
import crmCompanies from '../../crm/companies';

describe('#CrmCompaniesAPI', () => {
  it('creates correct instance with account-scoped resource', () => {
    expect(crmCompanies).toBeInstanceOf(ApiClient);
    expect(crmCompanies).toHaveProperty('get');
    expect(crmCompanies).toHaveProperty('show');
    expect(crmCompanies).toHaveProperty('create');
    expect(crmCompanies).toHaveProperty('update');
    expect(crmCompanies).toHaveProperty('delete');
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

    it('lists companies at the right endpoint', () => {
      crmCompanies.get();
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_companies'
      );
    });

    it('shows by id', () => {
      crmCompanies.show(42);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_companies/42'
      );
    });

    it('creates with payload', () => {
      crmCompanies.create({ name: 'Acme' });
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_companies',
        { name: 'Acme' }
      );
    });

    it('updates by id', () => {
      crmCompanies.update(7, { name: 'Updated' });
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_companies/7',
        { name: 'Updated' }
      );
    });

    it('deletes by id', () => {
      crmCompanies.delete(7);
      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_companies/7'
      );
    });
  });
});
