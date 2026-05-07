require 'rails_helper'

# [2026-05-07] Spec request pra Api::V1::Accounts::CrmActivitiesController.
# Slice 5 — última do Phase 1. Activities são nested sob crm_opportunities.
#
# Cobertura:
# - Auth/gate (401 sem header, 403 sem feature)
# - Index ordenado por due_at ASC NULLS LAST
# - Tenancy isolation (404 pra opp de outra conta)
# - CRUD: admin + agent ambos podem (policy permissivo — operacional)
# - #complete marca completed_at + dispara evento (testado via spy)
# - Strong params canary (account_id E completed_at E matrix_task_id ignorados)
RSpec.describe 'CRM Activities API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { create(:holding_crm_pipeline, account: account) }
  let(:stage) { create(:holding_crm_stage, pipeline: pipeline, account: account) }
  let(:opportunity) { create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage) }

  before { account.update!(holding_crm_enabled: true) }

  describe 'GET /api/v1/accounts/:account_id/crm_opportunities/:opp_id/activities' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when feature gate disabled' do
      before { account.update!(holding_crm_enabled: false) }

      it 'returns 403' do
        get "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities",
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when admin authenticated' do
      before do
        create(:holding_crm_activity, account: account, opportunity: opportunity, subject: 'Last', due_at: 5.days.from_now)
        create(:holding_crm_activity, account: account, opportunity: opportunity, subject: 'No deadline', due_at: nil)
        create(:holding_crm_activity, account: account, opportunity: opportunity, subject: 'First', due_at: 1.day.from_now)
      end

      it 'lista activities ordenadas due_at ASC NULLS LAST' do
        get "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['meta']['count']).to eq(3)
        subjects = body['payload'].pluck('subject')
        expect(subjects.first).to eq('First')
        expect(subjects.second).to eq('Last')
        expect(subjects.last).to eq('No deadline')
      end
    end

    it '404 pra opp de outra conta (TENANCY ISOLATION CANARY)' do
      other_pipe = create(:holding_crm_pipeline, account: other_account)
      other_stage = create(:holding_crm_stage, pipeline: other_pipe, account: other_account)
      foreign_opp = create(:holding_crm_opportunity, account: other_account, pipeline: other_pipe, stage: other_stage)

      get "/api/v1/accounts/#{account.id}/crm_opportunities/#{foreign_opp.id}/activities",
          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/crm_opportunities/:opp_id/activities' do
    let(:valid_params) do
      { crm_activity: { subject: 'Follow up call', kind: 'call', due_at: 2.days.from_now.iso8601 } }
    end

    it 'admin cria activity' do
      expect do
        post "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities",
             params: valid_params,
             headers: admin.create_new_auth_token, as: :json
      end.to change(Holding::Crm::Activity, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['subject']).to eq('Follow up call')
      expect(response.parsed_body['kind']).to eq('call')
      expect(response.parsed_body['crm_opportunity_id']).to eq(opportunity.id)
    end

    it 'agent também cria activity (policy permissivo)' do
      expect do
        post "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities",
             params: valid_params,
             headers: agent.create_new_auth_token, as: :json
      end.to change(Holding::Crm::Activity, :count).by(1)
    end

    it 'IGNORA account_id em payload (strong params)' do
      params = valid_params.deep_dup
      params[:crm_activity][:account_id] = other_account.id

      post "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities",
           params: params,
           headers: admin.create_new_auth_token, as: :json

      created = Holding::Crm::Activity.last
      expect(created.account_id).to eq(account.id)
    end

    it 'IGNORA completed_at em payload (fluxo único via #complete)' do
      params = valid_params.deep_dup
      params[:crm_activity][:completed_at] = Time.zone.now.iso8601

      post "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities",
           params: params,
           headers: admin.create_new_auth_token, as: :json

      created = Holding::Crm::Activity.last
      expect(created.completed_at).to be_nil
    end

    it 'IGNORA matrix_task_id em payload (setado por listener Phase 2)' do
      params = valid_params.deep_dup
      params[:crm_activity][:matrix_task_id] = 'tampered-id'

      post "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities",
           params: params,
           headers: admin.create_new_auth_token, as: :json

      created = Holding::Crm::Activity.last
      expect(created.matrix_task_id).to be_nil
    end

    it '422 quando subject vazio' do
      params = valid_params.deep_dup
      params[:crm_activity][:subject] = ''

      post "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities",
           params: params,
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/crm_opportunities/:opp_id/activities/:id' do
    let!(:activity) { create(:holding_crm_activity, account: account, opportunity: opportunity, subject: 'Original') }

    it 'agent atualiza' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities/#{activity.id}",
            params: { crm_activity: { subject: 'Renomeada', description: 'Detalhes' } },
            headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(activity.reload.subject).to eq('Renomeada')
      expect(activity.description).to eq('Detalhes')
    end

    it 'IGNORA completed_at em payload (fluxo único via #complete)' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities/#{activity.id}",
            params: { crm_activity: { completed_at: Time.zone.now.iso8601 } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(activity.reload.completed_at).to be_nil
    end

    it 'IGNORA matrix_task_id em payload (setado pelo listener)' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities/#{activity.id}",
            params: { crm_activity: { matrix_task_id: 'tampered' } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(activity.reload.matrix_task_id).to be_nil
    end

    it '404 pra activity de outra opp' do
      other_opp = create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage)
      other_activity = create(:holding_crm_activity, account: account, opportunity: other_opp)

      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities/#{other_activity.id}",
            params: { crm_activity: { subject: 'Hijack' } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/crm_opportunities/:opp_id/activities/:id' do
    let!(:activity) { create(:holding_crm_activity, account: account, opportunity: opportunity) }

    it 'admin destroy' do
      expect do
        delete "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities/#{activity.id}",
               headers: admin.create_new_auth_token, as: :json
      end.to change(Holding::Crm::Activity, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it 'agent NÃO destroy (parity com Opportunity — hard delete admin-only)' do
      delete "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities/#{activity.id}",
             headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/crm_opportunities/:opp_id/activities/:id/complete' do
    let!(:activity) { create(:holding_crm_activity, account: account, opportunity: opportunity, due_at: 1.day.from_now) }

    it 'marca completed_at = now' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities/#{activity.id}/complete",
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(activity.reload.completed_at).to be_present
      expect(activity.completed_at).to be_within(2.seconds).of(Time.zone.now)
    end

    it 'aceita completed_at custom (ISO8601)' do
      custom_time = 2.hours.ago.iso8601

      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities/#{activity.id}/complete",
            params: { completed_at: custom_time },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(activity.reload.completed_at).to be_within(2.seconds).of(Time.zone.parse(custom_time))
    end

    it '400 pra completed_at inválido' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities/#{activity.id}/complete",
            params: { completed_at: 'not-a-date' },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it '400 pra completed_at vazio (Time.zone.parse retorna nil silently)' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities/#{activity.id}/complete",
            params: { completed_at: '' },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(activity.reload.completed_at).to be_nil
    end

    it 'dispara evento ACTIVITY_COMPLETED' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/activities/#{activity.id}/complete",
            headers: admin.create_new_auth_token, as: :json

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Holding::Crm::Events::ACTIVITY_COMPLETED, kind_of(Time), activity: instance_of(Holding::Crm::Activity)
      )
    end
  end
end
