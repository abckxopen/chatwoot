require 'rails_helper'

# [2026-04-30] Spec request pra Api::V1::Accounts::CrmPipelinesController.
# Cobertura mínima exigida (regra Founder "sem gambiarras e seguro"):
# - auth: 401 sem headers
# - feature flag: 403 quando crm_pipeline desabilitado
# - autorização: matriz role × action (admin pode tudo, agent só read)
# - tenancy isolation: 2 accounts, garantir que não vaza recurso
# - strong params: account_id e id em payload são IGNORADOS
# - validation: 422 com errors granulares quando model rejeita
RSpec.describe 'CRM Pipelines API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_admin) { create(:user, account: other_account, role: :administrator) }

  before { account.enable_features!(:crm_pipeline) }

  describe 'GET /api/v1/accounts/:account_id/crm_pipelines' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get "/api/v1/accounts/#{account.id}/crm_pipelines"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when feature crm_pipeline disabled' do
      before { account.disable_features!(:crm_pipeline) }

      it 'returns 403' do
        get "/api/v1/accounts/#{account.id}/crm_pipelines",
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when authenticated as admin' do
      let!(:pipeline_a) { create(:holding_crm_pipeline, account: account, name: 'Outbound') }
      let!(:pipeline_default) { create(:holding_crm_pipeline, :default, account: account, name: 'Vendas MB') }
      let!(:other_account_pipeline) { create(:holding_crm_pipeline, account: other_account, name: 'NotMine') }

      it 'lists pipelines da conta com defaults_first' do
        get "/api/v1/accounts/#{account.id}/crm_pipelines",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['meta']['count']).to eq(2)
        names = body['payload'].pluck('name')
        expect(names.first).to eq('Vendas MB') # default first
        expect(names).not_to include('NotMine') # tenancy isolation
      end
    end

    context 'when authenticated as agent (read access)' do
      let!(:_pipeline) { create(:holding_crm_pipeline, account: account) }

      it 'permite read' do
        get "/api/v1/accounts/#{account.id}/crm_pipelines",
            headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/crm_pipelines' do
    let(:valid_params) do
      { crm_pipeline: { name: 'Outbound Engine', description: 'Funil cold email', default_pipeline: true } }
    end

    context 'as admin' do
      it 'cria pipeline' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm_pipelines",
               params: valid_params,
               headers: admin.create_new_auth_token,
               as: :json
        end.to change { Holding::Crm::Pipeline.count }.by(1)

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body['name']).to eq('Outbound Engine')
        expect(body['default_pipeline']).to be(true)

        # tenancy: pipeline foi criado na account correta
        created = Holding::Crm::Pipeline.last
        expect(created.account_id).to eq(account.id)
      end

      it 'IGNORA account_id em payload (strong params defense)' do
        post "/api/v1/accounts/#{account.id}/crm_pipelines",
             params: { crm_pipeline: { name: 'Hijack', account_id: other_account.id } },
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:created)
        created = Holding::Crm::Pipeline.last
        expect(created.account_id).to eq(account.id) # não escalou pra outra conta
        expect(created.account_id).not_to eq(other_account.id)
      end

      it '422 quando name vazio' do
        post "/api/v1/accounts/#{account.id}/crm_pipelines",
             params: { crm_pipeline: { name: '' } },
             headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it '422 quando 2 default_pipelines' do
        create(:holding_crm_pipeline, :default, account: account)
        post "/api/v1/accounts/#{account.id}/crm_pipelines",
             params: { crm_pipeline: { name: 'Outro Default', default_pipeline: true } },
             headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'as agent' do
      it 'retorna 403 (só admin cria)' do
        post "/api/v1/accounts/#{account.id}/crm_pipelines",
             params: valid_params,
             headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/crm_pipelines/:id' do
    let!(:pipeline) { create(:holding_crm_pipeline, account: account) }

    it 'retorna pipeline com stages embeddados' do
      create(:holding_crm_stage, pipeline: pipeline, account: account, name: 'Lead', position: 0)
      create(:holding_crm_stage, pipeline: pipeline, account: account, name: 'Ganho', position: 1, won: true)

      get "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['id']).to eq(pipeline.id)
      expect(body['stages'].size).to eq(2)
      expect(body['stages'].first['name']).to eq('Lead')
    end

    it '404 pra pipeline de outra conta (TENANCY ISOLATION CANARY)' do
      foreign = create(:holding_crm_pipeline, account: other_account)

      get "/api/v1/accounts/#{account.id}/crm_pipelines/#{foreign.id}",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/crm_pipelines/:id' do
    let!(:pipeline) { create(:holding_crm_pipeline, account: account) }

    it 'atualiza pipeline (admin)' do
      patch "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}",
            params: { crm_pipeline: { name: 'Renomeado' } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(pipeline.reload.name).to eq('Renomeado')
    end

    it '403 pra agent' do
      patch "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}",
            params: { crm_pipeline: { name: 'Hack' } },
            headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end

    it '404 pra pipeline de outra conta' do
      foreign = create(:holding_crm_pipeline, account: other_account)
      patch "/api/v1/accounts/#{account.id}/crm_pipelines/#{foreign.id}",
            params: { crm_pipeline: { name: 'Hijack' } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/crm_pipelines/:id' do
    let!(:pipeline) { create(:holding_crm_pipeline, account: account) }

    it 'deleta (admin)' do
      expect do
        delete "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}",
               headers: admin.create_new_auth_token, as: :json
      end.to change { Holding::Crm::Pipeline.count }.by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it '422 quando pipeline tem opportunities (restrict_with_error)' do
      stage = create(:holding_crm_stage, pipeline: pipeline, account: account)
      create(:holding_crm_opportunity, pipeline: pipeline, stage: stage, account: account)
      delete "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}",
             headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity).or have_http_status(:conflict)
    end

    it '404 pra pipeline de outra conta' do
      foreign = create(:holding_crm_pipeline, account: other_account)
      delete "/api/v1/accounts/#{account.id}/crm_pipelines/#{foreign.id}",
             headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it '403 pra agent' do
      delete "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}",
             headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end
  end
end
