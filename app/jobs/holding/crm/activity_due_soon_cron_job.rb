# [2026-05-16 abckxopen-fork] Phase 2 slice 3 — Sidekiq cron 1×/h que
# varre Holding::Crm::Activity com due_at em [now, now+24h] e dispara
# o evento Holding::Crm::Events::ACTIVITY_DUE_SOON por activity. O
# listener (Holding::CrmListener#crm_activity_due_soon) é stub nessa
# slice — só observa o fluxo. Reminder real (Matrix/email) fica pra
# slice futura, quando produto definir o canal de entrega.
#
# [2026-05-16] Queue :scheduled_jobs — alinhado com pattern do upstream
# (Account::ConversationsResolutionSchedulerJob, TriggerScheduledItemsJob).
# Cron jobs vão pra fila dedicada que tem prioridade abaixo de critical/
# high/medium/default mas acima de purgable/housekeeping — não compete
# com tráfego interativo do usuário.
#
# [2026-05-16] Idempotência via Rails.cache. Cron roda 1×/h e a janela
# due_within(24.hours) inclui a mesma activity em até 24 ticks; sem
# guarda, seria 24 dispatches da mesma activity. Cache key marca
# "já notificado nessa janela" com TTL de 23h (curto o suficiente pra
# permitir re-notificação no próximo ciclo de 24h, longo o suficiente
# pra cobrir as ~24 execuções da janela atual). Se Redis cair entre
# execuções, no pior caso re-dispatch — handler é stub, side-effect é
# log; quando virar reminder real (slice futura), o handler precisa ter
# sua própria idempotência (e.g. coluna last_due_soon_notified_at).
class Holding::Crm::ActivityDueSoonCronJob < ApplicationJob
  queue_as :scheduled_jobs

  WINDOW = 24.hours
  CACHE_TTL = 23.hours
  CACHE_KEY = 'crm:activity:%<id>d:due_soon_notified'.freeze

  def perform
    Rails.logger.info(
      job: self.class.name,
      event: 'crm.activity.due_soon.cron.start',
      window_hours: WINDOW.in_hours.to_i
    )

    dispatched = 0
    skipped = 0

    Holding::Crm::Activity.due_within(WINDOW).find_each(batch_size: 100) do |activity|
      if recently_notified?(activity)
        skipped += 1
        next
      end

      dispatch_event(activity)
      mark_notified(activity)
      dispatched += 1
    end

    Rails.logger.info(
      job: self.class.name,
      event: 'crm.activity.due_soon.cron.complete',
      dispatched: dispatched,
      skipped: skipped
    )
  end

  private

  def cache_key(activity)
    format(CACHE_KEY, id: activity.id)
  end

  def recently_notified?(activity)
    Rails.cache.exist?(cache_key(activity))
  end

  def mark_notified(activity)
    Rails.cache.write(cache_key(activity), Time.zone.now.to_i, expires_in: CACHE_TTL)
  end

  def dispatch_event(activity)
    Rails.configuration.dispatcher.dispatch(
      Holding::Crm::Events::ACTIVITY_DUE_SOON,
      Time.zone.now,
      activity: activity
    )

    Rails.logger.info(
      job: self.class.name,
      event: 'crm.activity.due_soon.dispatched',
      activity_id: activity.id,
      account_id: activity.account_id
    )
  end
end
