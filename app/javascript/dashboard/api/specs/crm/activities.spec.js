import ApiClient from '../../ApiClient';
import crmActivities from '../../crm/activities';

describe('#CrmActivitiesAPI', () => {
  it('creates correct instance with required methods', () => {
    expect(crmActivities).toBeInstanceOf(ApiClient);
    expect(crmActivities).toHaveProperty('get');
    expect(crmActivities).toHaveProperty('create');
    expect(crmActivities).toHaveProperty('update');
    expect(crmActivities).toHaveProperty('delete');
    expect(crmActivities).toHaveProperty('complete');
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

    it('lists activities under an opportunity', () => {
      crmActivities.get(10);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_opportunities/10/activities'
      );
    });

    it('creates an activity under an opportunity', () => {
      crmActivities.create(10, { title: 'Call' });
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_opportunities/10/activities',
        { title: 'Call' }
      );
    });

    it('updates an activity', () => {
      crmActivities.update(10, 5, { title: 'New' });
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_opportunities/10/activities/5',
        { title: 'New' }
      );
    });

    it('deletes an activity', () => {
      crmActivities.delete(10, 5);
      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_opportunities/10/activities/5'
      );
    });

    it('completes an activity via PATCH with no body', () => {
      crmActivities.complete(10, 5);
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_opportunities/10/activities/5/complete'
      );
    });
  });
});
