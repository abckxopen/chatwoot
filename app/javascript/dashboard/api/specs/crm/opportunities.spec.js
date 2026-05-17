import ApiClient from '../../ApiClient';
import crmOpportunities from '../../crm/opportunities';

describe('#CrmOpportunitiesAPI', () => {
  it('creates correct instance with custom + default methods', () => {
    expect(crmOpportunities).toBeInstanceOf(ApiClient);
    expect(crmOpportunities).toHaveProperty('get');
    expect(crmOpportunities).toHaveProperty('show');
    expect(crmOpportunities).toHaveProperty('create');
    expect(crmOpportunities).toHaveProperty('update');
    expect(crmOpportunities).toHaveProperty('delete');
    expect(crmOpportunities).toHaveProperty('moveToStage');
    expect(crmOpportunities).toHaveProperty('discard');
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

    it('lists opportunities', () => {
      crmOpportunities.get();
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_opportunities'
      );
    });

    it('shows by id', () => {
      crmOpportunities.show(7);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_opportunities/7'
      );
    });

    it('creates with payload', () => {
      crmOpportunities.create({ title: 'Deal' });
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_opportunities',
        { title: 'Deal' }
      );
    });

    it('updates by id', () => {
      crmOpportunities.update(7, { status: 'won' });
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_opportunities/7',
        { status: 'won' }
      );
    });

    it('deletes by id', () => {
      crmOpportunities.delete(7);
      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_opportunities/7'
      );
    });

    it('moves to stage with reason', () => {
      crmOpportunities.moveToStage(7, 200, 'qualified');
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_opportunities/7/move_to_stage',
        { stage_id: 200, reason: 'qualified' }
      );
    });

    it('moves to stage with null reason by default', () => {
      crmOpportunities.moveToStage(7, 200);
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_opportunities/7/move_to_stage',
        { stage_id: 200, reason: null }
      );
    });

    it('discards by id', () => {
      crmOpportunities.discard(7);
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_opportunities/7/discard'
      );
    });
  });
});
