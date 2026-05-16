# [2026-05-16 abckxopen-fork] Phase 2 slice 3 — Sidekiq cron 1×/d que
# varre Holding::Crm::Activity overdue (due_at < now AND completed_at IS NULL)
# e dispara Holding::Crm::Events::ACTIVITY_OVERDUE. Listener stub nessa
# slice; reminder real (Matrix/email + escalation) fica pra slice futura.
#
# Loop, idempotência via cache e log estruturado: Holding::Crm::ActivityCronJobBase.
#
# [2026-05-16] TTL 23h (na base) vs cron 1×/dia: o tick teoricamente
# permitiria ~25h, mas alinhamos com DueSoon (uma notificação por dia
# por activity) e garantimos que mudanças de schedule (e.g. 2×/dia) não
# causem suppression silenciosa. Trade-off: job que atrasar >23h re-dispara.
class Holding::Crm::ActivityOverdueCronJob < Holding::Crm::ActivityCronJobBase
  private

  def activity_scope
    Holding::Crm::Activity.overdue
  end

  def event_constant
    Holding::Crm::Events::ACTIVITY_OVERDUE
  end

  def log_event_prefix
    'crm.activity.overdue'
  end

  def cache_suffix
    'overdue_notified'
  end
end
