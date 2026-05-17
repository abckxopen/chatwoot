require 'rails_helper'

# [2026-05-17] Spec request pra Api::V1::Accounts::CrmReportsController.
# Phase 4 slice 3. Cobertura mínima alinhada com slices 1-3:
# - auth: 401 sem headers
# - gate por conta: 403 quando accounts.holding_crm_enabled = false
# - tenancy isolation: opportunities/pipelines de outra conta não vazam
# - shape: cada endpoint retorna chaves esperadas
# - happy path por endpoint + edge case (404 pipeline missing, empty range)
RSpec.describe 'CRM Reports API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before { account.update!(holding_crm_enabled: true) }

  describe 'GET /api/v1/accounts/:account_id/crm_reports/pipeline_summary' do
    let(:pipeline) { create(:holding_crm_pipeline, account: account) }
    let(:stage_lead) { create(:holding_crm_stage, pipeline: pipeline, account: account, name: 'Lead', position: 0) }
    let(:stage_negotiation) { create(:holding_crm_stage, pipeline: pipeline, account: account, name: 'Negociação', position: 1) }

    context 'when unauthenticated' do
      it 'returns 401' do
        get "/api/v1/accounts/#{account.id}/crm_reports/pipeline_summary",
            params: { pipeline_id: pipeline.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when holding_crm_enabled is false' do
      before { account.update!(holding_crm_enabled: false) }

      it 'returns 403' do
        get "/api/v1/accounts/#{account.id}/crm_reports/pipeline_summary",
            params: { pipeline_id: pipeline.id },
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when pipeline is missing' do
      it 'returns 404' do
        get "/api/v1/accounts/#{account.id}/crm_reports/pipeline_summary",
            params: { pipeline_id: 999_999 },
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error']).to eq('pipeline_not_found')
      end
    end

    context 'when pipeline belongs to other account (TENANCY CANARY)' do
      it 'returns 404' do
        foreign = create(:holding_crm_pipeline, account: other_account)
        get "/api/v1/accounts/#{account.id}/crm_reports/pipeline_summary",
            params: { pipeline_id: foreign.id },
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'happy path' do
      before do
        create(:holding_crm_opportunity, pipeline: pipeline, stage: stage_lead, account: account, value: 1_000)
        create(:holding_crm_opportunity, pipeline: pipeline, stage: stage_lead, account: account, value: 2_500)
        create(:holding_crm_opportunity, pipeline: pipeline, stage: stage_negotiation, account: account, value: 10_000)
        # opp won/lost não conta no aggregate de open
        create(:holding_crm_opportunity, :won, pipeline: pipeline, stage: stage_lead, account: account, value: 99_999)
        # opp em pipeline de outra conta não vaza
        other_pipeline = create(:holding_crm_pipeline, account: other_account)
        other_stage = create(:holding_crm_stage, pipeline: other_pipeline, account: other_account)
        create(:holding_crm_opportunity, pipeline: other_pipeline, stage: other_stage, account: other_account, value: 50_000)
      end

      it 'retorna count + total por stage (apenas open)' do
        get "/api/v1/accounts/#{account.id}/crm_reports/pipeline_summary",
            params: { pipeline_id: pipeline.id },
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['pipeline_id']).to eq(pipeline.id)
        expect(body['pipeline_name']).to eq(pipeline.name)
        expect(body['stages'].size).to eq(2)

        lead_row = body['stages'].find { |s| s['stage_id'] == stage_lead.id }
        expect(lead_row['opportunities_count']).to eq(2)
        expect(lead_row['total_value']).to eq('3500.00')

        neg_row = body['stages'].find { |s| s['stage_id'] == stage_negotiation.id }
        expect(neg_row['opportunities_count']).to eq(1)
        expect(neg_row['total_value']).to eq('10000.00')
      end

      it 'permite agent (read access)' do
        get "/api/v1/accounts/#{account.id}/crm_reports/pipeline_summary",
            params: { pipeline_id: pipeline.id },
            headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    context 'pipeline com stages mas sem opps' do
      before do
        stage_lead
        stage_negotiation
      end

      it 'retorna stages com counts/totais zerados' do
        get "/api/v1/accounts/#{account.id}/crm_reports/pipeline_summary",
            params: { pipeline_id: pipeline.id },
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        body['stages'].each do |stage|
          expect(stage['opportunities_count']).to eq(0)
          expect(stage['total_value']).to eq('0.00')
        end
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/crm_reports/agent_performance' do
    let(:pipeline) { create(:holding_crm_pipeline, account: account) }
    let(:stage) { create(:holding_crm_stage, pipeline: pipeline, account: account) }

    context 'when unauthenticated' do
      it 'returns 401' do
        get "/api/v1/accounts/#{account.id}/crm_reports/agent_performance"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when holding_crm_enabled is false' do
      before { account.update!(holding_crm_enabled: false) }

      it 'returns 403' do
        get "/api/v1/accounts/#{account.id}/crm_reports/agent_performance",
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'sem opps no período' do
      it 'retorna linhas zeradas pra cada user da conta' do
        admin
        agent
        get "/api/v1/accounts/#{account.id}/crm_reports/agent_performance",
            params: { from: '2020-01-01', to: '2020-12-31' },
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        # default 30 days range substituído pelo from/to acima
        expect(body['from']).to eq('2020-01-01')
        expect(body['to']).to eq('2020-12-31')
        expect(body['agents'].size).to eq(2)
        body['agents'].each do |row|
          expect(row['opportunities_assigned']).to eq(0)
          expect(row['opportunities_won']).to eq(0)
          expect(row['opportunities_lost']).to eq(0)
          expect(row['win_rate']).to eq(0.0)
        end
      end
    end

    context 'happy path com 2 agentes + tenancy canary' do
      let(:other_user) { create(:user, account: other_account, role: :agent) }

      before do
        # admin: 2 assigned, 1 won, 0 lost
        create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage,
                                         assignee: admin, created_at: 10.days.ago)
        create(:holding_crm_opportunity, :won, account: account, pipeline: pipeline, stage: stage,
                                               assignee: admin, created_at: 5.days.ago,
                                               value: 50_000, won_at: 2.days.ago)
        # agent: 1 assigned, 0 won, 1 lost
        create(:holding_crm_opportunity, :lost, account: account, pipeline: pipeline, stage: stage,
                                                assignee: agent, created_at: 7.days.ago,
                                                value: 30_000, lost_at: 1.day.ago)
        # opp em outra conta não conta
        other_pipeline = create(:holding_crm_pipeline, account: other_account)
        other_stage = create(:holding_crm_stage, pipeline: other_pipeline, account: other_account)
        create(:holding_crm_opportunity, :won, account: other_account, pipeline: other_pipeline,
                                               stage: other_stage, assignee: other_user,
                                               value: 99_999, won_at: 1.day.ago)
      end

      it 'aggrega corretamente por agente (tenancy isolada)' do
        get "/api/v1/accounts/#{account.id}/crm_reports/agent_performance",
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        agent_ids = body['agents'].pluck('user_id')
        expect(agent_ids).to contain_exactly(admin.id, agent.id)
        expect(agent_ids).not_to include(other_user.id)

        admin_row = body['agents'].find { |r| r['user_id'] == admin.id }
        expect(admin_row['opportunities_assigned']).to eq(2)
        expect(admin_row['opportunities_won']).to eq(1)
        expect(admin_row['won_value']).to eq('50000.00')
        expect(admin_row['opportunities_lost']).to eq(0)
        expect(admin_row['win_rate']).to eq(1.0)

        agent_row = body['agents'].find { |r| r['user_id'] == agent.id }
        expect(agent_row['opportunities_assigned']).to eq(1)
        expect(agent_row['opportunities_won']).to eq(0)
        expect(agent_row['opportunities_lost']).to eq(1)
        expect(agent_row['win_rate']).to eq(0.0)
      end

      it 'respeita filtros from/to (won fora do range não conta)' do
        get "/api/v1/accounts/#{account.id}/crm_reports/agent_performance",
            params: { from: 90.days.ago.to_date.to_s, to: 60.days.ago.to_date.to_s },
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
        admin_row = response.parsed_body['agents'].find { |r| r['user_id'] == admin.id }
        expect(admin_row['opportunities_won']).to eq(0)
        expect(admin_row['opportunities_lost']).to eq(0)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/crm_reports/forecast' do
    let(:pipeline) { create(:holding_crm_pipeline, account: account) }
    let(:stage) { create(:holding_crm_stage, pipeline: pipeline, account: account) }

    context 'when unauthenticated' do
      it 'returns 401' do
        get "/api/v1/accounts/#{account.id}/crm_reports/forecast",
            params: { pipeline_id: pipeline.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when pipeline is missing' do
      it 'returns 404' do
        get "/api/v1/accounts/#{account.id}/crm_reports/forecast",
            params: { pipeline_id: 999_999 },
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when pipeline belongs to other account (TENANCY CANARY)' do
      it 'returns 404' do
        foreign = create(:holding_crm_pipeline, account: other_account)
        get "/api/v1/accounts/#{account.id}/crm_reports/forecast",
            params: { pipeline_id: foreign.id },
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'happy path com agrupamento mensal' do
      before do
        # Mar 2025: 2 opps × value × probability
        create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage,
                                         expected_close_date: Date.new(2025, 3, 10), value: 10_000, probability: 80)
        create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage,
                                         expected_close_date: Date.new(2025, 3, 25), value: 20_000, probability: 50)
        # Apr 2025: 1 opp probability nil → tratada como 50
        create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage,
                                         expected_close_date: Date.new(2025, 4, 15), value: 40_000, probability: 0)
        # Fora do until: ignorada
        create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage,
                                         expected_close_date: Date.new(2026, 1, 1), value: 999_999, probability: 100)
        # Won não entra (status != open)
        create(:holding_crm_opportunity, :won, account: account, pipeline: pipeline, stage: stage,
                                               expected_close_date: Date.new(2025, 3, 1), value: 99_999, probability: 100)
        # Outra conta: tenancy
        other_pipeline = create(:holding_crm_pipeline, account: other_account)
        other_stage = create(:holding_crm_stage, pipeline: other_pipeline, account: other_account)
        create(:holding_crm_opportunity, account: other_account, pipeline: other_pipeline, stage: other_stage,
                                         expected_close_date: Date.new(2025, 3, 5), value: 99_999, probability: 100)
      end

      it 'agrupa por mês até `until` e soma value × probability' do
        get "/api/v1/accounts/#{account.id}/crm_reports/forecast",
            params: { pipeline_id: pipeline.id, until: '2025-12-31' },
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['pipeline_id']).to eq(pipeline.id)
        expect(body['until']).to eq('2025-12-31')

        months = body['monthly_projection']
        expect(months.size).to eq(2)
        mar = months.find { |m| m['month'] == '2025-03' }
        # 10000 * 0.8 + 20000 * 0.5 = 8000 + 10000 = 18000
        expect(mar['projected_value']).to eq('18000.00')
        expect(mar['opportunities_count']).to eq(2)

        apr = months.find { |m| m['month'] == '2025-04' }
        # 40000 * 0.5 (default) = 20000
        expect(apr['projected_value']).to eq('20000.00')
        expect(apr['opportunities_count']).to eq(1)

        # total = 18000 + 20000 = 38000
        expect(body['total_projected']).to eq('38000.00')
      end

      it 'respeita filtro until (opps depois do until são ignoradas)' do
        get "/api/v1/accounts/#{account.id}/crm_reports/forecast",
            params: { pipeline_id: pipeline.id, until: '2025-03-31' },
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['monthly_projection'].size).to eq(1)
        expect(body['monthly_projection'].first['month']).to eq('2025-03')
      end
    end

    context 'sem opps abertas' do
      it 'retorna projeção vazia + total zero' do
        get "/api/v1/accounts/#{account.id}/crm_reports/forecast",
            params: { pipeline_id: pipeline.id },
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['monthly_projection']).to eq([])
        expect(body['total_projected']).to eq('0.00')
      end
    end
  end
end
