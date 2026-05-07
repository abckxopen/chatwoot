require 'rails_helper'

# [2026-05-07] Spec request pra Api::V1::Accounts::CrmCompaniesController.
# Cobertura mesma barra das slices 1+2:
# - auth 401 sem headers
# - feature gate 403 quando holding_crm_enabled = false (via HoldingCrmConcern)
# - role matrix admin/agent
# - tenancy isolation (cross-account 404)
# - strong params canary (account_id ignorado, additional_attributes permit aberto)
# - validations (name presence, name uniqueness scoped to account, domain format)
# - opportunities_count no payload
RSpec.describe 'CRM Companies API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before { account.update!(holding_crm_enabled: true) }

  describe 'GET /api/v1/accounts/:account_id/crm_companies' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get "/api/v1/accounts/#{account.id}/crm_companies"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when holding_crm_enabled is false' do
      before { account.update!(holding_crm_enabled: false) }

      it 'returns 403' do
        get "/api/v1/accounts/#{account.id}/crm_companies",
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when authenticated as admin' do
      before do
        create(:holding_crm_company, account: account, name: 'Bravo Inc')
        create(:holding_crm_company, account: account, name: 'Alpha Co')
        create(:holding_crm_company, account: other_account, name: 'NotMine Ltd')
      end

      it 'lista companies da conta ordenadas por name' do
        get "/api/v1/accounts/#{account.id}/crm_companies",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['meta']['count']).to eq(2)
        names = body['payload'].pluck('name')
        expect(names).to eq(['Alpha Co', 'Bravo Inc'])
        expect(names).not_to include('NotMine Ltd')
      end
    end

    context 'when authenticated as agent (read access)' do
      before { create(:holding_crm_company, account: account) }

      it 'permite read' do
        get "/api/v1/accounts/#{account.id}/crm_companies",
            headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/crm_companies/:id' do
    let!(:company) { create(:holding_crm_company, account: account, name: 'Acme') }

    it 'retorna company com opportunities_count' do
      pipeline = create(:holding_crm_pipeline, account: account)
      stage = create(:holding_crm_stage, pipeline: pipeline, account: account)
      create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage, company: company)
      create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage, company: company)

      get "/api/v1/accounts/#{account.id}/crm_companies/#{company.id}",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['id']).to eq(company.id)
      expect(body['name']).to eq('Acme')
      expect(body['opportunities_count']).to eq(2)
    end

    it '404 pra company de outra conta (TENANCY ISOLATION CANARY)' do
      foreign = create(:holding_crm_company, account: other_account)

      get "/api/v1/accounts/#{account.id}/crm_companies/#{foreign.id}",
          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/crm_companies' do
    let(:valid_params) do
      { crm_company: { name: 'Holding Tech', domain: 'holding.tech', industry: 'SaaS', size: '11-50' } }
    end

    context 'when admin' do
      it 'cria company' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm_companies",
               params: valid_params,
               headers: admin.create_new_auth_token, as: :json
        end.to change(Holding::Crm::Company, :count).by(1)

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body['name']).to eq('Holding Tech')
        expect(body['domain']).to eq('holding.tech')

        created = Holding::Crm::Company.last
        expect(created.account_id).to eq(account.id)
      end

      it 'IGNORA account_id em payload (strong params defense)' do
        post "/api/v1/accounts/#{account.id}/crm_companies",
             params: { crm_company: { name: 'Hijack', account_id: other_account.id } },
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:created)
        created = Holding::Crm::Company.last
        expect(created.account_id).to eq(account.id)
      end

      it 'aceita additional_attributes (jsonb permit aberto por design)' do
        post "/api/v1/accounts/#{account.id}/crm_companies",
             params: { crm_company: { name: 'Custom', additional_attributes: { region: 'BR-RS', tier: 'gold' } } },
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body['additional_attributes']).to include('region' => 'BR-RS', 'tier' => 'gold')
      end

      it '422 quando name vazio' do
        post "/api/v1/accounts/#{account.id}/crm_companies",
             params: { crm_company: { name: '' } },
             headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it '422 quando 2 companies com mesma name na conta' do
        create(:holding_crm_company, account: account, name: 'Duplicada')
        post "/api/v1/accounts/#{account.id}/crm_companies",
             params: { crm_company: { name: 'Duplicada' } },
             headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it '422 quando domain inválido' do
        post "/api/v1/accounts/#{account.id}/crm_companies",
             params: { crm_company: { name: 'Bad', domain: 'not a domain' } },
             headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when agent' do
      it 'retorna 401 (só admin cria)' do
        post "/api/v1/accounts/#{account.id}/crm_companies",
             params: valid_params,
             headers: agent.create_new_auth_token, as: :json
        # [2026-05-07] Pundit::NotAuthorizedError → 401 via RequestExceptionHandler.
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/crm_companies/:id' do
    let!(:company) { create(:holding_crm_company, account: account, name: 'Original') }

    it 'atualiza (admin)' do
      patch "/api/v1/accounts/#{account.id}/crm_companies/#{company.id}",
            params: { crm_company: { name: 'Renomeada' } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(company.reload.name).to eq('Renomeada')
    end

    it '401 pra agent' do
      patch "/api/v1/accounts/#{account.id}/crm_companies/#{company.id}",
            params: { crm_company: { name: 'Hack' } },
            headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it '404 pra company de outra conta' do
      foreign = create(:holding_crm_company, account: other_account)
      patch "/api/v1/accounts/#{account.id}/crm_companies/#{foreign.id}",
            params: { crm_company: { name: 'Hijack' } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/crm_companies/:id' do
    let!(:company) { create(:holding_crm_company, account: account) }

    it 'deleta (admin)' do
      expect do
        delete "/api/v1/accounts/#{account.id}/crm_companies/#{company.id}",
               headers: admin.create_new_auth_token, as: :json
      end.to change(Holding::Crm::Company, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it 'destroy preserva opportunities (nullify)' do
      pipeline = create(:holding_crm_pipeline, account: account)
      stage = create(:holding_crm_stage, pipeline: pipeline, account: account)
      opp = create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage, company: company)

      delete "/api/v1/accounts/#{account.id}/crm_companies/#{company.id}",
             headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(opp.reload.crm_company_id).to be_nil
    end

    it '401 pra agent' do
      delete "/api/v1/accounts/#{account.id}/crm_companies/#{company.id}",
             headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
