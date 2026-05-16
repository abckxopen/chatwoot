# [2026-05-16 abckxopen-fork] Phase 2 slice 3 — Sidekiq cron 1×/d que
# varre Holding::Crm::Activity overdue (due_at < now AND completed_at IS NULL)
# e dispara Holding::Crm::Events::ACTIVITY_OVERDUE. Listener stub nessa
# slice; reminder real (Matrix/email + escalation) fica pra slice futura.
#
# [2026-05-16] Queue :scheduled_jobs — mesmo motivo do DueSoon cron.
#
# [2026-05-16] Idempotência via Rails.cache, TTL 23h. Cron roda 1×/dia
# (09 UTC), então o TTL teoricamente daria pra ser ~25h pra cobrir o
# próximo tick. Usamos 23h pra alinhar com DueSoon (mesma janela mental
# = uma notificação por dia por activity) e pra garantir que mudanças
# de cron schedule (ex: rodar 2×/dia) não causem suppression silenciosa.
# Trade-off: se job atrasar >23h, re-dispatch — aceitável (listener
# stub agora, slice futura com reminder real precisa de dedup por DB
# coluna como last_overdue_notified_at pra ser bulletproof).
class Holding::Crm::ActivityOverdueCronJob < ApplicationJob
  queue_as :scheduled_jobs

  CACHE_TTL = 23.hours
  CACHE_KEY = 'crm:activity:%<id>d:overdue_notified'.freeze

  def perform
    Rails.logger.info(
      job: self.class.name,
      event: 'crm.activity.overdue.cron.start'
    )

    dispatched = 0
    skipped = 0

    Holding::Crm::Activity.overdue.find_each(batch_size: 100) do |activity|
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
      event: 'crm.activity.overdue.cron.complete',
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
      Holding::Crm::Events::ACTIVITY_OVERDUE,
      Time.zone.now,
      activity: activity
    )

    Rails.logger.info(
      job: self.class.name,
      event: 'crm.activity.overdue.dispatched',
      activity_id: activity.id,
      account_id: activity.account_id
    )
  end
end
