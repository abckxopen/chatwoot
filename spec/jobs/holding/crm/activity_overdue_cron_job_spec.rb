require 'rails_helper'

# [2026-05-16] Phase 2 slice 3 — specs do cron que dispara
# Holding::Crm::Events::ACTIVITY_OVERDUE pra activities com due_at < now
# AND completed_at IS NULL. Foco análogo ao due_soon, ajustado pros filtros
# do scope `overdue` (model: open.where('due_at < ?', Time.zone.now)).
RSpec.describe Holding::Crm::ActivityOverdueCronJob do
  let(:account) { create(:account) }
  let(:pipeline) { create(:holding_crm_pipeline, account: account) }
  let(:stage) { create(:holding_crm_stage, pipeline: pipeline, account: account, position: 0) }
  let(:opportunity) { create(:holding_crm_opportunity, account: account, pipeline: pipeline, stage: stage) }
  let(:dispatcher) { Rails.configuration.dispatcher }

  before do
    Rails.cache.clear
    allow(dispatcher).to receive(:dispatch).and_call_original
  end

  describe '.perform_later' do
    it 'enfileira na fila :scheduled_jobs' do
      expect { described_class.perform_later }
        .to have_enqueued_job(described_class).on_queue('scheduled_jobs')
    end
  end

  describe '#perform' do
    context 'when activity tem due_at no passado e completed_at IS NULL' do
      let!(:overdue_activity) do
        create(:holding_crm_activity, :overdue, opportunity: opportunity, account: account)
      end

      it 'dispara ACTIVITY_OVERDUE pra activity overdue' do
        described_class.perform_now

        expect(dispatcher).to have_received(:dispatch).with(
          Holding::Crm::Events::ACTIVITY_OVERDUE,
          kind_of(Time),
          activity: overdue_activity
        )
      end
    end

    context 'when activity foi completed (mesmo que due_at no passado)' do
      let!(:completed_past_activity) do
        create(:holding_crm_activity, :completed, opportunity: opportunity, account: account, due_at: 3.days.ago)
      end

      it 'NÃO dispara evento (scope open exclui completed)' do
        described_class.perform_now

        expect(dispatcher).not_to have_received(:dispatch).with(
          Holding::Crm::Events::ACTIVITY_OVERDUE, anything, anything
        )
      end
    end

    context 'when due_at é no futuro (due_soon ou além)' do
      let!(:future_activity) do
        create(:holding_crm_activity, opportunity: opportunity, account: account, due_at: 2.hours.from_now)
      end

      it 'NÃO dispara evento (overdue scope só pega passado)' do
        described_class.perform_now

        expect(dispatcher).not_to have_received(:dispatch).with(
          Holding::Crm::Events::ACTIVITY_OVERDUE, anything, anything
        )
      end
    end

    context 'idempotency' do
      let!(:overdue_activity) do
        create(:holding_crm_activity, :overdue, opportunity: opportunity, account: account)
      end

      it 'segunda execução dentro da janela de cache não re-dispara' do
        described_class.perform_now
        described_class.perform_now

        expect(dispatcher).to have_received(:dispatch).with(
          Holding::Crm::Events::ACTIVITY_OVERDUE, anything, hash_including(activity: overdue_activity)
        ).once
      end

      it 'marca cache key com TTL ~23h após dispatch' do
        described_class.perform_now

        expect(Rails.cache.exist?("crm:activity:#{overdue_activity.id}:overdue_notified")).to be(true)
      end
    end

    context 'structured logger' do
      it 'emite eventos start e complete com contadores' do
        create(:holding_crm_activity, :overdue, opportunity: opportunity, account: account)

        expect(Rails.logger).to receive(:info).with(
          hash_including(event: 'crm.activity.overdue.cron.start')
        )
        expect(Rails.logger).to receive(:info).with(
          hash_including(event: 'crm.activity.overdue.dispatched')
        )
        expect(Rails.logger).to receive(:info).with(
          hash_including(event: 'crm.activity.overdue.cron.complete', dispatched: 1, skipped: 0)
        )

        described_class.perform_now
      end
    end
  end
end
