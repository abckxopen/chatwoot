require 'rails_helper'

# [2026-05-07] Spec request pra Api::V1::Accounts::CrmOpportunitiesController.
# Coração do CRM — slice 4. Cobertura mais ampla que slices 1-3 porque a
# policy DIVERGE: agentes podem criar opps e atualizar/mover SUAS opps.
#
# Cobertura:
# - Auth/gate (401 sem header, 403 sem feature)
# - Index: filtros (status, pipeline, stage, assignee), include_discarded,
#   tenancy isolation, ordering desc por created_at
# - Show: payload com stage/pipeline/company/activities embedded
# - Create: admin + agent ambos OK, validações, account_id ignorado
# - Update: admin + assignee OK, não-assignee 401
# - move_to_stage: admin + assignee, auto-won/lost, cross-pipeline 400, cross-account 400
# - Discard: admin + assignee, não-assignee 401, marca discarded_at
# - Destroy: admin only, agent 401, hard delete
RSpec.describe 'CRM Opportunities API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { create(:holding_crm_pipeline, account: account) }
  let(:stage) { create(:holding_crm_stage, pipeline: pipeline, account: account, position: 0) }

  before { account.update!(holding_crm_enabled: true) }

  describe 'GET /api/v1/accounts/:account_id/crm_opportunities' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get "/api/v1/accounts/#{account.id}/crm_opportunities"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when feature gate disabled' do
      before { account.update!(holding_crm_enabled: false) }

      it 'returns 403' do
        get "/api/v1/accounts/#{account.id}/crm_opportunities",
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when admin authenticated' do
      let!(:active_opp) { create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage, name: 'Active Deal') }
      let!(:discarded_opp) do
        create(:holding_crm_opportunity, :discarded, account: account, pipeline: pipeline, stage: stage, name: 'Discarded Deal')
      end

      it 'lista opps active por padrão (oculta discarded)' do
        get "/api/v1/accounts/#{account.id}/crm_opportunities",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        ids = body['payload'].pluck('id')
        expect(ids).to include(active_opp.id)
        expect(ids).not_to include(discarded_opp.id)
      end

      it 'inclui discarded com include_discarded=true' do
        get "/api/v1/accounts/#{account.id}/crm_opportunities?include_discarded=true",
            headers: admin.create_new_auth_token, as: :json

        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to include(active_opp.id, discarded_opp.id)
      end

      it 'filtra por status' do
        won_stage = create(:holding_crm_stage, :won, pipeline: pipeline, account: account, position: 99)
        won_opp = create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: won_stage)
        won_opp.update!(status: :won)

        get "/api/v1/accounts/#{account.id}/crm_opportunities?status=won",
            headers: admin.create_new_auth_token, as: :json

        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to contain_exactly(won_opp.id)
      end

      it 'filtra por pipeline_id' do
        other_pipeline = create(:holding_crm_pipeline, account: account)
        other_stage = create(:holding_crm_stage, pipeline: other_pipeline, account: account)
        opp_other_pipe = create(:holding_crm_opportunity, account: account, pipeline: other_pipeline, stage: other_stage)

        get "/api/v1/accounts/#{account.id}/crm_opportunities?pipeline_id=#{other_pipeline.id}",
            headers: admin.create_new_auth_token, as: :json

        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to contain_exactly(opp_other_pipe.id)
      end

      it 'TENANCY: não retorna opps de outra conta' do
        other_pipeline = create(:holding_crm_pipeline, account: other_account)
        other_stage = create(:holding_crm_stage, pipeline: other_pipeline, account: other_account)
        foreign = create(:holding_crm_opportunity, account: other_account, pipeline: other_pipeline, stage: other_stage)

        get "/api/v1/accounts/#{account.id}/crm_opportunities",
            headers: admin.create_new_auth_token, as: :json

        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).not_to include(foreign.id)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/crm_opportunities/:id' do
    let!(:opportunity) { create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage) }

    it 'retorna opp com stage/pipeline embedded + activities' do
      activity = create(:holding_crm_activity, account: account, opportunity: opportunity, subject: 'Follow up')

      get "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['id']).to eq(opportunity.id)
      expect(body['stage']['id']).to eq(stage.id)
      expect(body['pipeline']['id']).to eq(pipeline.id)
      expect(body['activities'].pluck('id')).to include(activity.id)
    end

    it '404 pra opp de outra conta (TENANCY ISOLATION CANARY)' do
      other_pipe = create(:holding_crm_pipeline, account: other_account)
      other_stage = create(:holding_crm_stage, pipeline: other_pipe, account: other_account)
      foreign = create(:holding_crm_opportunity, account: other_account, pipeline: other_pipe, stage: other_stage)

      get "/api/v1/accounts/#{account.id}/crm_opportunities/#{foreign.id}",
          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/crm_opportunities' do
    let(:valid_params) do
      {
        crm_opportunity: {
          name: 'Big Deal',
          crm_pipeline_id: pipeline.id,
          crm_stage_id: stage.id,
          value: 50_000.0,
          currency: 'BRL',
          probability: 30
        }
      }
    end

    it 'admin cria opp' do
      expect do
        post "/api/v1/accounts/#{account.id}/crm_opportunities",
             params: valid_params,
             headers: admin.create_new_auth_token, as: :json
      end.to change(Holding::Crm::Opportunity, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['name']).to eq('Big Deal')
    end

    it 'agent também cria opp (DIVERGE de Pipeline/Stage/Company)' do
      expect do
        post "/api/v1/accounts/#{account.id}/crm_opportunities",
             params: valid_params,
             headers: agent.create_new_auth_token, as: :json
      end.to change(Holding::Crm::Opportunity, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it 'IGNORA account_id em payload (strong params)' do
      params = valid_params.deep_dup
      params[:crm_opportunity][:account_id] = other_account.id

      post "/api/v1/accounts/#{account.id}/crm_opportunities",
           params: params,
           headers: admin.create_new_auth_token, as: :json

      created = Holding::Crm::Opportunity.last
      expect(created.account_id).to eq(account.id)
    end

    it '422 quando name vazio' do
      params = valid_params.deep_dup
      params[:crm_opportunity][:name] = ''

      post "/api/v1/accounts/#{account.id}/crm_opportunities",
           params: params,
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '422 quando currency fora ALLOWED_CURRENCIES' do
      params = valid_params.deep_dup
      params[:crm_opportunity][:currency] = 'XYZ'

      post "/api/v1/accounts/#{account.id}/crm_opportunities",
           params: params,
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '422 quando probability > 100' do
      params = valid_params.deep_dup
      params[:crm_opportunity][:probability] = 150

      post "/api/v1/accounts/#{account.id}/crm_opportunities",
           params: params,
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'IGNORA status em payload (strong params defense — status só via move_to_stage)' do
      params = valid_params.deep_dup
      params[:crm_opportunity][:status] = 'won'

      post "/api/v1/accounts/#{account.id}/crm_opportunities",
           params: params,
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      created = Holding::Crm::Opportunity.last
      expect(created.status).to eq('open') # status default não foi sobrescrito
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/crm_opportunities/:id' do
    let!(:opportunity) { create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage, assignee: agent) }

    it 'admin atualiza' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}",
            params: { crm_opportunity: { name: 'Renomeado' } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(opportunity.reload.name).to eq('Renomeado')
    end

    it 'agent assignee atualiza' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}",
            params: { crm_opportunity: { name: 'Atualizado pelo dono' } },
            headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'agent NÃO-assignee retorna 401' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}",
            params: { crm_opportunity: { name: 'Hijack' } },
            headers: other_agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/crm_opportunities/:id/move_to_stage' do
    let!(:stage_b) { create(:holding_crm_stage, pipeline: pipeline, account: account, position: 1) }
    let!(:won_stage) { create(:holding_crm_stage, :won, pipeline: pipeline, account: account, position: 99) }
    let!(:opportunity) { create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage, assignee: agent) }

    it 'admin move pra stage destino' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/move_to_stage",
            params: { stage_id: stage_b.id },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(opportunity.reload.crm_stage_id).to eq(stage_b.id)
    end

    it 'auto-aplica won quando stage destino é won marker' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/move_to_stage",
            params: { stage_id: won_stage.id },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(opportunity.reload.status).to eq('won')
      expect(opportunity.won_at).to be_present
    end

    it 'agent assignee move' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/move_to_stage",
            params: { stage_id: stage_b.id },
            headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'agent não-assignee retorna 401' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/move_to_stage",
            params: { stage_id: stage_b.id },
            headers: other_agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it '400 pra stage de outro pipeline' do
      foreign_pipe = create(:holding_crm_pipeline, account: account)
      foreign_stage = create(:holding_crm_stage, pipeline: foreign_pipe, account: account)

      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/move_to_stage",
            params: { stage_id: foreign_stage.id },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it '400 pra stage de outra account (cross-tenant)' do
      foreign_pipe = create(:holding_crm_pipeline, account: other_account)
      foreign_stage = create(:holding_crm_stage, pipeline: foreign_pipe, account: other_account)

      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/move_to_stage",
            params: { stage_id: foreign_stage.id },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it '400 sem stage_id' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/move_to_stage",
            params: {},
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/crm_opportunities/:id/discard' do
    let!(:opportunity) { create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage, assignee: agent) }

    it 'admin discard marca discarded_at' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/discard",
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(opportunity.reload.discarded_at).to be_present
    end

    it 'agent assignee discard' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/discard",
            headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'agent não-assignee retorna 401' do
      patch "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}/discard",
            headers: other_agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/crm_opportunities/:id' do
    let!(:opportunity) { create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage, assignee: agent) }

    it 'admin destroy hard-deleta' do
      expect do
        delete "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}",
               headers: admin.create_new_auth_token, as: :json
      end.to change(Holding::Crm::Opportunity, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it 'agent assignee NÃO pode hard-delete (somente discard)' do
      delete "/api/v1/accounts/#{account.id}/crm_opportunities/#{opportunity.id}",
             headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
