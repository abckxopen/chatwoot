import ApiClient from '../../ApiClient';
import crmReports from '../../crm/reports';

describe('#CrmReportsAPI', () => {
  it('creates correct instance with account-scoped resource', () => {
    expect(crmReports).toBeInstanceOf(ApiClient);
    expect(crmReports).toHaveProperty('pipelineSummary');
    expect(crmReports).toHaveProperty('agentPerformance');
    expect(crmReports).toHaveProperty('forecast');
  });

  describe('inside account-scoped URL', () => {
    const originalAxios = window.axios;
    const originalPathname = window.location.pathname;
    const axiosMock = {
      get: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
      window.history.pushState({}, '', '/app/accounts/1/settings');
    });

    afterEach(() => {
      window.axios = originalAxios;
      window.history.pushState({}, '', originalPathname);
    });

    it('hits pipeline_summary with pipeline_id', () => {
      crmReports.pipelineSummary(42);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_reports/pipeline_summary',
        { params: { pipeline_id: 42 } }
      );
    });

    it('hits agent_performance with from + to', () => {
      crmReports.agentPerformance({ from: '2025-01-01', to: '2025-12-31' });
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_reports/agent_performance',
        { params: { from: '2025-01-01', to: '2025-12-31' } }
      );
    });

    it('agent_performance suporta chamada sem args (defaults backend)', () => {
      crmReports.agentPerformance();
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_reports/agent_performance',
        { params: { from: undefined, to: undefined } }
      );
    });

    it('hits forecast with pipeline_id + until', () => {
      crmReports.forecast(7, '2025-12-31');
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/crm_reports/forecast',
        { params: { pipeline_id: 7, until: '2025-12-31' } }
      );
    });
  });
});
