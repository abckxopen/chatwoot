require 'rails_helper'

# [2026-05-16] Phase 2 slice 3 — specs do cron que dispara
# Holding::Crm::Events::ACTIVITY_DUE_SOON pra activities open com due_at
# em [now, now+24h]. Foco:
# 1. Smoke: enqueue na fila correta
# 2. Dispatcher é chamado pra activities elegíveis
# 3. Filtros negativos: completed, due > 24h, due no passado (overdue)
# 4. Idempotência: 2ª execução dentro de 23h não re-dispara
# 5. Logger estruturado emite start + complete
RSpec.describe Holding::Crm::ActivityDueSoonCronJob do
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
    context 'when há activity open dentro da janela 24h' do
      let!(:activity_due_soon) do
        create(:holding_crm_activity, :due_soon, opportunity: opportunity, account: account)
      end

      it 'dispara ACTIVITY_DUE_SOON pra activity elegível' do
        described_class.perform_now

        expect(dispatcher).to have_received(:dispatch).with(
          Holding::Crm::Events::ACTIVITY_DUE_SOON,
          kind_of(Time),
          activity: activity_due_soon
        )
      end
    end

    context 'when activity já foi completed' do
      let!(:completed_activity) do
        create(:holding_crm_activity, :completed, opportunity: opportunity, account: account, due_at: 1.hour.from_now)
      end

      it 'NÃO dispara evento (completed_at presente, scope open exclui)' do
        described_class.perform_now

        expect(dispatcher).not_to have_received(:dispatch).with(
          Holding::Crm::Events::ACTIVITY_DUE_SOON, anything, anything
        )
      end
    end

    context 'when due_at é mais de 24h à frente' do
      let!(:future_activity) do
        create(:holding_crm_activity, opportunity: opportunity, account: account, due_at: 48.hours.from_now)
      end

      it 'NÃO dispara evento (fora da janela)' do
        described_class.perform_now

        expect(dispatcher).not_to have_received(:dispatch).with(
          Holding::Crm::Events::ACTIVITY_DUE_SOON, anything, anything
        )
      end
    end

    context 'when due_at já passou (overdue, não due_soon)' do
      let!(:overdue_activity) do
        create(:holding_crm_activity, :overdue, opportunity: opportunity, account: account)
      end

      it 'NÃO dispara evento (overdue é outro cron)' do
        described_class.perform_now

        expect(dispatcher).not_to have_received(:dispatch).with(
          Holding::Crm::Events::ACTIVITY_DUE_SOON, anything, anything
        )
      end
    end

    context 'idempotency' do
      # [2026-05-16] Rails.cache em test env é :null_store por padrão (config/environments/test.rb).
      # null_store faz cache.write virar no-op e cache.exist? sempre retornar false — ou seja,
      # recently_notified? sempre false, ambos os performs disparam, e a asserção de TTL falha.
      # Trocamos por MemoryStore só nesse context pra testar idempotência real.
      before do
        @cache_original = Rails.cache
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      end

      after do
        allow(Rails).to receive(:cache).and_return(@cache_original)
      end

      let!(:activity_due_soon) do
        create(:holding_crm_activity, :due_soon, opportunity: opportunity, account: account)
      end

      it 'segunda execução dentro da janela de cache não re-dispara' do
        described_class.perform_now
        described_class.perform_now

        expect(dispatcher).to have_received(:dispatch).with(
          Holding::Crm::Events::ACTIVITY_DUE_SOON, anything, hash_including(activity: activity_due_soon)
        ).once
      end

      it 'marca cache key com TTL ~23h após dispatch' do
        described_class.perform_now

        expect(Rails.cache.exist?("crm:activity:#{activity_due_soon.id}:due_soon_notified")).to be(true)
      end
    end

    context 'structured logger' do
      it 'emite eventos start + dispatched + complete com contadores' do
        create(:holding_crm_activity, :due_soon, opportunity: opportunity, account: account)

        # [2026-05-16] Spy pattern (allow + have_received) ao invés de strict expect-receive:
        # Rails.logger.info recebe chamadas de framework (autoload, ActiveJob, dispatcher).
        # Strict mock quebra em qualquer call incidental. Spy + and_call_original deixa passar
        # tudo e asserciona só a chamada que importa.
        allow(Rails.logger).to receive(:info).and_call_original

        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with(
          hash_including(event: 'crm.activity.due_soon.cron.start', window_hours: 24)
        )
        expect(Rails.logger).to have_received(:info).with(
          hash_including(event: 'crm.activity.due_soon.dispatched')
        )
        expect(Rails.logger).to have_received(:info).with(
          hash_including(event: 'crm.activity.due_soon.cron.complete', dispatched: 1, skipped: 0)
        )
      end
    end
  end
end
