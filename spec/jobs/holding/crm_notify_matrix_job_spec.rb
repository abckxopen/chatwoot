require 'rails_helper'

# [2026-05-07] Specs do job que orquestra criação de Matrix task quando
# opp entra em stage com template configurado. Foco:
# 1. Caminhos de skip (template ausente, opp/stage não existem, idempotência)
# 2. Renderização Liquid (substituição correta de variáveis)
# 3. Persistência da Activity com matrix_task_id pra audit trail
# 4. Mapeamento de erros do client → retry/discard semantics
RSpec.describe Holding::CrmNotifyMatrixJob do
  let(:account) { create(:account) }
  let(:pipeline) { create(:holding_crm_pipeline, account: account) }
  let(:stage) do
    create(:holding_crm_stage, :with_matrix_template, pipeline: pipeline, account: account, position: 1)
  end
  let(:opportunity) { create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage, name: 'ACME Corp') }
  let(:client_double) { instance_double(Holding::Crm::MatrixApiClient) }

  before do
    allow(Holding::Crm::MatrixApiClient).to receive(:new).and_return(client_double)
  end

  describe '#perform' do
    context 'when stage tem template enabled' do
      before do
        allow(client_double).to receive(:create_task)
          .and_return('id' => 'mtx-task-abc', 'title' => 'Acompanhar ACME Corp')
      end

      it 'chama Matrix API com payload renderizado e cria Activity' do
        expect do
          described_class.perform_now(opportunity_id: opportunity.id, stage_id: stage.id)
        end.to change(Holding::Crm::Activity, :count).by(1)

        expect(client_double).to have_received(:create_task).with(
          board_id: stage.matrix_task_template['board_id'],
          payload: hash_including(
            title: 'Acompanhar ACME Corp',
            priority: 'medium',
            type: 'on-demand',
            requires_review: false
          )
        )

        activity = Holding::Crm::Activity.last
        expect(activity.matrix_task_id).to eq('mtx-task-abc')
        expect(activity.crm_opportunity_id).to eq(opportunity.id)
        expect(activity.kind).to eq('task')
        expect(activity.subject).to include("[stage:#{stage.id}]")
      end
    end

    context 'when opportunity não existe' do
      it 'no-op (não cria Activity)' do
        expect do
          described_class.perform_now(opportunity_id: 999_999, stage_id: stage.id)
        end.not_to change(Holding::Crm::Activity, :count)
      end
    end

    context 'when template ausente do stage' do
      let(:stage_no_template) { create(:holding_crm_stage, pipeline: pipeline, account: account, position: 0) }

      it 'no-op' do
        described_class.perform_now(opportunity_id: opportunity.id, stage_id: stage_no_template.id)
        expect(Holding::Crm::Activity.count).to eq(0)
      end
    end

    context 'when template enabled=false' do
      let(:stage_disabled) do
        create(:holding_crm_stage, pipeline: pipeline, account: account, position: 2,
                                   matrix_task_template: { 'enabled' => false, 'board_id' => 'x' })
      end

      it 'no-op' do
        described_class.perform_now(opportunity_id: opportunity.id, stage_id: stage_disabled.id)
        expect(Holding::Crm::Activity.count).to eq(0)
      end
    end

    context 'when board_id ausente do template' do
      let(:stage_noboard) do
        create(:holding_crm_stage, pipeline: pipeline, account: account, position: 3,
                                   matrix_task_template: { 'enabled' => true, 'title_template' => 'X' })
      end

      it 'no-op (defesa contra config parcial)' do
        described_class.perform_now(opportunity_id: opportunity.id, stage_id: stage_noboard.id)
        expect(Holding::Crm::Activity.count).to eq(0)
      end
    end

    context 'when já notificou recentemente pra mesma (opp, stage)' do
      before do
        allow(client_double).to receive(:create_task)
          .and_return('id' => 'mtx-task-first')
      end

      it 'segunda invocação no-op (idempotência)' do
        described_class.perform_now(opportunity_id: opportunity.id, stage_id: stage.id)
        expect(Holding::Crm::Activity.count).to eq(1)

        described_class.perform_now(opportunity_id: opportunity.id, stage_id: stage.id)
        expect(Holding::Crm::Activity.count).to eq(1)
        expect(client_double).to have_received(:create_task).once
      end
    end

    context 'when notificação anterior foi pra outra stage da mesma opp' do
      let(:other_stage) do
        create(:holding_crm_stage, :with_matrix_template, pipeline: pipeline, account: account, position: 4)
      end

      before do
        allow(client_double).to receive(:create_task)
          .and_return({ 'id' => 'mtx-1' }, { 'id' => 'mtx-2' })
      end

      it 'notifica de novo (idempotência é por (opp, stage), não só opp)' do
        described_class.perform_now(opportunity_id: opportunity.id, stage_id: stage.id)
        described_class.perform_now(opportunity_id: opportunity.id, stage_id: other_stage.id)

        expect(Holding::Crm::Activity.count).to eq(2)
        expect(client_double).to have_received(:create_task).twice
      end
    end

    context 'when Matrix retorna ClientError (4xx)' do
      before do
        allow(client_double).to receive(:create_task)
          .and_raise(Holding::Crm::MatrixApiClient::ClientError, 'matrix 422: invalid_board')
      end

      it 'discard (não cria Activity, não enfileira retry)' do
        # discard_on swallows the error; perform_now returns normally.
        expect do
          described_class.perform_now(opportunity_id: opportunity.id, stage_id: stage.id)
        end.not_to change(Holding::Crm::Activity, :count)
      end
    end

    context 'when Matrix retorna ServerError (5xx)' do
      before do
        allow(client_double).to receive(:create_task)
          .and_raise(Holding::Crm::MatrixApiClient::ServerError, 'matrix 503')
      end

      it 're-raise (Sidekiq aplica retry com backoff)' do
        expect do
          described_class.perform_now(opportunity_id: opportunity.id, stage_id: stage.id)
        end.to raise_error(Holding::Crm::MatrixApiClient::ServerError)
        expect(Holding::Crm::Activity.count).to eq(0)
      end
    end

    context 'when template Liquid quebra' do
      let(:stage_bad_template) do
        create(:holding_crm_stage, pipeline: pipeline, account: account, position: 5,
                                   matrix_task_template: {
                                     'enabled' => true,
                                     'board_id' => 'b1',
                                     'title_template' => '{{ unclosed'
                                   })
      end

      before do
        allow(client_double).to receive(:create_task).and_return('id' => 'mtx-fallback')
      end

      it 'envia template raw (bug visível em vez de silencioso) e segue' do
        described_class.perform_now(opportunity_id: opportunity.id, stage_id: stage_bad_template.id)

        expect(client_double).to have_received(:create_task).with(
          board_id: 'b1',
          payload: hash_including(title: '{{ unclosed')
        )
        expect(Holding::Crm::Activity.last.matrix_task_id).to eq('mtx-fallback')
      end
    end
  end
end
