# [2026-05-16 abckxopen-fork] Phase 2 slice 3 — Sidekiq cron 1×/h que
# varre Holding::Crm::Activity com due_at em [now, now+24h] e dispara
# Holding::Crm::Events::ACTIVITY_DUE_SOON por activity. O listener
# (Holding::CrmListener#crm_activity_due_soon) é stub nessa slice — só
# observa o fluxo. Reminder real (Matrix/email) fica pra slice futura,
# quando produto definir o canal de entrega.
#
# Loop, idempotência via cache e log estruturado: Holding::Crm::ActivityCronJobBase.
class Holding::Crm::ActivityDueSoonCronJob < Holding::Crm::ActivityCronJobBase
  WINDOW = 24.hours

  private

  def activity_scope
    Holding::Crm::Activity.due_within(WINDOW)
  end

  def event_constant
    Holding::Crm::Events::ACTIVITY_DUE_SOON
  end

  def log_event_prefix
    'crm.activity.due_soon'
  end

  def cache_suffix
    'due_soon_notified'
  end

  def extra_start_log_fields
    { window_hours: WINDOW.in_hours.to_i }
  end
end
