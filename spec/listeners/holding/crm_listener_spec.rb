require 'rails_helper'

# [2026-05-07] Slice 2.1 — testa que o handler #crm_opportunity_stage_changed:
# 1. Enfileira CrmNotifyMatrixJob quando stage tem template enabled
# 2. NÃO enfileira quando template ausente / disabled
# 3. NÃO enfileira quando opportunity ou new_stage_id ausentes (defesa)
# 4. NÃO enfileira quando new_stage_id aponta pra stage inexistente
RSpec.describe Holding::CrmListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:pipeline) { create(:holding_crm_pipeline, account: account) }
  let(:stage_with_template) do
    create(:holding_crm_stage, :with_matrix_template, pipeline: pipeline, account: account, position: 1)
  end
  let(:stage_no_template) { create(:holding_crm_stage, pipeline: pipeline, account: account, position: 0) }
  let(:opportunity) { create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage_no_template) }

  describe '#crm_opportunity_stage_changed' do
    let(:event) do
      build_event(opportunity: opportunity, old_stage_id: stage_no_template.id, new_stage_id: new_stage_id)
    end

    context 'when stage destino tem matrix_task_template enabled' do
      let(:new_stage_id) { stage_with_template.id }

      it 'enfileira CrmNotifyMatrixJob com opportunity + stage' do
        expect { listener.crm_opportunity_stage_changed(event) }
          .to have_enqueued_job(Holding::CrmNotifyMatrixJob)
          .with(opportunity_id: opportunity.id, stage_id: stage_with_template.id)
      end
    end

    context 'when stage destino NÃO tem template' do
      let(:new_stage_id) { stage_no_template.id }

      it 'NÃO enfileira job' do
        expect { listener.crm_opportunity_stage_changed(event) }
          .not_to have_enqueued_job(Holding::CrmNotifyMatrixJob)
      end
    end

    context 'when template existe mas enabled=false' do
      let(:disabled_stage) do
        create(:holding_crm_stage, pipeline: pipeline, account: account, position: 2,
                                   matrix_task_template: { 'enabled' => false, 'board_id' => 'x' })
      end
      let(:new_stage_id) { disabled_stage.id }

      it 'NÃO enfileira job' do
        expect { listener.crm_opportunity_stage_changed(event) }
          .not_to have_enqueued_job(Holding::CrmNotifyMatrixJob)
      end
    end

    context 'when new_stage_id aponta pra stage inexistente' do
      let(:new_stage_id) { 999_999 }

      it 'NÃO enfileira job (sem raise)' do
        expect { listener.crm_opportunity_stage_changed(event) }
          .not_to have_enqueued_job(Holding::CrmNotifyMatrixJob)
      end
    end

    context 'when opportunity ausente do payload' do
      it 'NÃO enfileira job (defesa contra payload malformado)' do
        ev = build_event(opportunity: nil, old_stage_id: nil, new_stage_id: stage_with_template.id)
        expect { listener.crm_opportunity_stage_changed(ev) }
          .not_to have_enqueued_job(Holding::CrmNotifyMatrixJob)
      end
    end
  end

  def build_event(payload)
    Events::Base.new(Holding::Crm::Events::OPPORTUNITY_STAGE_CHANGED, Time.zone.now, payload)
  end
end
