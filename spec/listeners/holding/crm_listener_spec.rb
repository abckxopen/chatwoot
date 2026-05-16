require 'rails_helper'

# [2026-05-07] Slice 2.1 — testa que o handler #crm_opportunity_stage_changed:
# 1. Enfileira CrmNotifyMatrixJob quando stage tem template enabled
# 2. NÃO enfileira quando template ausente / disabled
# 3. NÃO enfileira quando opportunity ou new_stage_id ausentes (defesa)
# 4. NÃO enfileira quando new_stage_id aponta pra stage inexistente
#
# [2026-05-16] Slice 3 — adicionados describes pros handlers stub
# #crm_activity_due_soon e #crm_activity_overdue. Refactor: build_event
# agora aceita event constant pra reuso entre describes.
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
      build_event(
        Holding::Crm::Events::OPPORTUNITY_STAGE_CHANGED,
        opportunity: opportunity, old_stage_id: stage_no_template.id, new_stage_id: new_stage_id
      )
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
        ev = build_event(
          Holding::Crm::Events::OPPORTUNITY_STAGE_CHANGED,
          opportunity: nil, old_stage_id: nil, new_stage_id: stage_with_template.id
        )
        expect { listener.crm_opportunity_stage_changed(ev) }
          .not_to have_enqueued_job(Holding::CrmNotifyMatrixJob)
      end
    end
  end

  # [2026-05-16] Slice 3 — handler stub. Asserts log estruturado + tolerância
  # a payload sem activity. Quando reminder real for adicionado em slice
  # futura, estes specs precisam expandir pra cobrir o side-effect.
  describe '#crm_activity_due_soon' do
    let(:assignee) { create(:user, account: account) }
    let(:activity) do
      create(:holding_crm_activity, :due_soon, opportunity: opportunity, account: account, assignee: assignee)
    end
    let(:event) { build_event(Holding::Crm::Events::ACTIVITY_DUE_SOON, activity: activity) }

    it 'loga evento estruturado com dados da activity' do
      expect(Rails.logger).to receive(:info).with(
        hash_including(
          event: 'crm.activity.due_soon.received',
          activity_id: activity.id,
          account_id: activity.account_id,
          assignee_id: assignee.id
        )
      )

      listener.crm_activity_due_soon(event)
    end

    it 'não raise quando activity ausente do payload' do
      ev = build_event(Holding::Crm::Events::ACTIVITY_DUE_SOON, activity: nil)
      expect { listener.crm_activity_due_soon(ev) }.not_to raise_error
    end
  end

  describe '#crm_activity_overdue' do
    let(:assignee) { create(:user, account: account) }
    let(:activity) do
      create(:holding_crm_activity, :overdue, opportunity: opportunity, account: account, assignee: assignee)
    end
    let(:event) { build_event(Holding::Crm::Events::ACTIVITY_OVERDUE, activity: activity) }

    it 'loga evento estruturado com dados da activity' do
      expect(Rails.logger).to receive(:info).with(
        hash_including(
          event: 'crm.activity.overdue.received',
          activity_id: activity.id,
          account_id: activity.account_id,
          assignee_id: assignee.id
        )
      )

      listener.crm_activity_overdue(event)
    end

    it 'não raise quando activity ausente do payload' do
      ev = build_event(Holding::Crm::Events::ACTIVITY_OVERDUE, activity: nil)
      expect { listener.crm_activity_overdue(ev) }.not_to raise_error
    end
  end

  # [2026-05-16] Refactor pra aceitar event constant — antes era hardcoded em
  # OPPORTUNITY_STAGE_CHANGED. Slice 3 precisa disparar ACTIVITY_DUE_SOON e
  # ACTIVITY_OVERDUE também.
  def build_event(event_name, payload)
    Events::Base.new(event_name, Time.zone.now, payload)
  end
end
