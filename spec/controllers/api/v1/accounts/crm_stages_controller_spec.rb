require 'rails_helper'

# [2026-05-07] Spec request pra Api::V1::Accounts::CrmStagesController.
# Cobertura mínima (mesma barra do slice 1 Pipelines):
# - auth: 401 sem headers
# - feature gate: 403 quando holding_crm_enabled = false
# - autorização: matriz role × action
# - tenancy isolation: pipeline + stage só acessíveis na conta certa
# - strong params: account_id em payload é ignorado
# - validations: 422 com errors granulares
# - reorder: bulk update preserva constraint UNIQUE (pipeline, position)
RSpec.describe 'CRM Stages API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { create(:holding_crm_pipeline, account: account) }
  let(:other_pipeline) { create(:holding_crm_pipeline, account: other_account) }

  before { account.update!(holding_crm_enabled: true) }

  describe 'GET /api/v1/accounts/:account_id/crm_pipelines/:pipeline_id/stages' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when holding_crm_enabled is false' do
      before { account.update!(holding_crm_enabled: false) }

      it 'returns 403' do
        get "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages",
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when authenticated as admin' do
      before do
        create(:holding_crm_stage, pipeline: pipeline, account: account, name: 'Lead', position: 0)
        create(:holding_crm_stage, pipeline: pipeline, account: account, name: 'Ganho', position: 2, won: true)
        create(:holding_crm_stage, pipeline: pipeline, account: account, name: 'Qualificado', position: 1)
      end

      it 'lists stages do pipeline ordenadas por position' do
        get "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['meta']['count']).to eq(3)
        expect(body['meta']['crm_pipeline_id']).to eq(pipeline.id)
        names = body['payload'].pluck('name')
        expect(names).to eq(%w[Lead Qualificado Ganho])
      end
    end

    context 'when authenticated as agent (read access)' do
      before { create(:holding_crm_stage, pipeline: pipeline, account: account) }

      it 'permite read' do
        get "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages",
            headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    it '404 pra pipeline de outra conta (TENANCY ISOLATION CANARY)' do
      get "/api/v1/accounts/#{account.id}/crm_pipelines/#{other_pipeline.id}/stages",
          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/crm_pipelines/:pipeline_id/stages' do
    let(:valid_params) { { crm_stage: { name: 'Proposta', position: 5, color: '#aabbcc' } } }

    context 'when admin' do
      it 'cria stage' do
        expect do
          post "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages",
               params: valid_params,
               headers: admin.create_new_auth_token,
               as: :json
        end.to change(Holding::Crm::Stage, :count).by(1)

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body['name']).to eq('Proposta')
        expect(body['crm_pipeline_id']).to eq(pipeline.id)

        created = Holding::Crm::Stage.last
        expect(created.account_id).to eq(account.id)
      end

      it 'IGNORA account_id em payload (strong params defense)' do
        post "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages",
             params: { crm_stage: { name: 'Hijack', account_id: other_account.id } },
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:created)
        created = Holding::Crm::Stage.last
        expect(created.account_id).to eq(account.id)
      end

      it '422 quando name vazio' do
        post "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages",
             params: { crm_stage: { name: '' } },
             headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it '422 quando won AND lost (xor)' do
        post "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages",
             params: { crm_stage: { name: 'Inválido', won: true, lost: true } },
             headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it '422 quando 2 stages com mesma name+pipeline' do
        create(:holding_crm_stage, pipeline: pipeline, account: account, name: 'Dup')
        post "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages",
             params: { crm_stage: { name: 'Dup' } },
             headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it '404 pra pipeline de outra conta' do
        post "/api/v1/accounts/#{account.id}/crm_pipelines/#{other_pipeline.id}/stages",
             params: valid_params,
             headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end

      it 'aceita matrix_task_template com chaves do schema permitido' do
        template = {
          enabled: true,
          board_id: 'a46a66a2-e393-405c-94e1-0d73cda3a11f',
          title_template: 'Acompanhar {{opportunity.name}}',
          description_template: 'Opp na stage {{stage.name}}',
          priority: 'medium'
        }
        post "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages",
             params: { crm_stage: { name: 'WithTemplate', matrix_task_template: template } },
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:created)
        expect(response.parsed_body['matrix_task_template']['title_template']).to eq('Acompanhar {{opportunity.name}}')
      end

      it 'IGNORA chaves estranhas em matrix_task_template (permit list defense)' do
        post "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages",
             params: { crm_stage: { name: 'NoExtra', matrix_task_template: { enabled: true, evil_key: 'pwn' } } },
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:created)
        template = response.parsed_body['matrix_task_template']
        expect(template).to include('enabled' => true)
        expect(template).not_to have_key('evil_key')
      end
    end

    context 'when agent' do
      it 'retorna 403 (só admin cria)' do
        post "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages",
             params: valid_params,
             headers: agent.create_new_auth_token, as: :json
        # [2026-05-07] Chatwoot mapeia Pundit::NotAuthorizedError → 401
        # via RequestExceptionHandler#render_unauthorized (não 403 padrão Rails).
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/crm_pipelines/:pipeline_id/stages/:id' do
    let!(:stage) { create(:holding_crm_stage, pipeline: pipeline, account: account, name: 'Original') }

    it 'atualiza stage (admin)' do
      patch "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages/#{stage.id}",
            params: { crm_stage: { name: 'Renomeado' } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(stage.reload.name).to eq('Renomeado')
    end

    it '403 pra agent' do
      patch "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages/#{stage.id}",
            params: { crm_stage: { name: 'Hack' } },
            headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it '404 pra stage de outro pipeline' do
      foreign_stage = create(:holding_crm_stage, pipeline: other_pipeline, account: other_account)
      patch "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages/#{foreign_stage.id}",
            params: { crm_stage: { name: 'Hijack' } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/crm_pipelines/:pipeline_id/stages/:id' do
    let!(:stage) { create(:holding_crm_stage, pipeline: pipeline, account: account) }

    it 'deleta (admin)' do
      expect do
        delete "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages/#{stage.id}",
               headers: admin.create_new_auth_token, as: :json
      end.to change(Holding::Crm::Stage, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it '422 quando stage tem opportunities (restrict_with_error)' do
      create(:holding_crm_opportunity, pipeline: pipeline, stage: stage, account: account)
      delete "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages/#{stage.id}",
             headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it '403 pra agent' do
      delete "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages/#{stage.id}",
             headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/crm_pipelines/:pipeline_id/stages/reorder' do
    let!(:s1) { create(:holding_crm_stage, pipeline: pipeline, account: account, name: 'A', position: 0) }
    let!(:s2) { create(:holding_crm_stage, pipeline: pipeline, account: account, name: 'B', position: 1) }
    let!(:s3) { create(:holding_crm_stage, pipeline: pipeline, account: account, name: 'C', position: 2) }

    it 'reordena (admin)' do
      patch "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages/reorder",
            params: { stage_ids: [s3.id, s1.id, s2.id] },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(s1.reload.position).to eq(1)
      expect(s2.reload.position).to eq(2)
      expect(s3.reload.position).to eq(0)
    end

    it '400 sem stage_ids' do
      patch "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages/reorder",
            params: {},
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it '400 quando stage_ids parcial (sem cobrir todas as stages)' do
      patch "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages/reorder",
            params: { stage_ids: [s1.id, s2.id] },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it '400 quando stage_ids inclui stage de outro pipeline' do
      foreign_stage = create(:holding_crm_stage, pipeline: other_pipeline, account: other_account)
      patch "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages/reorder",
            params: { stage_ids: [s1.id, s2.id, foreign_stage.id] },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it '403 pra agent' do
      patch "/api/v1/accounts/#{account.id}/crm_pipelines/#{pipeline.id}/stages/reorder",
            params: { stage_ids: [s1.id, s2.id, s3.id] },
            headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it '404 pipeline de outra conta' do
      patch "/api/v1/accounts/#{account.id}/crm_pipelines/#{other_pipeline.id}/stages/reorder",
            params: { stage_ids: [s1.id] },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
