# [2026-05-16 abckxopen-fork] Phase 2 slice 3 — base compartilhada pelos
# crons de Holding::Crm::Activity (DueSoon 1×/h, Overdue 1×/d). Cada
# subclasse define: o scope (.activity_scope), o event constant
# (.event_constant), o prefixo de log (.log_event_prefix) e o sufixo do
# cache key (.cache_suffix). Loop, contadores, dedup via Rails.cache e
# emissão de log estruturado vivem aqui.
#
# [2026-05-16] Queue :scheduled_jobs — alinhado com pattern do upstream
# (Account::ConversationsResolutionSchedulerJob, TriggerScheduledItemsJob).
# Cron jobs vão pra fila dedicada que tem prioridade abaixo de critical/
# high/medium/default mas acima de purgable/housekeeping — não compete
# com tráfego interativo do usuário.
#
# [2026-05-16] Idempotência via Rails.cache + TTL 23h. As janelas dos crons
# overlap (DueSoon roda 24× em 24h, Overdue 1×/d cobre o mesmo registro
# indefinidamente até completar), então sem guarda re-dispatchávamos a
# mesma activity dezenas de vezes. TTL 23h é curto o suficiente pra
# permitir re-notificação no próximo ciclo de 24h e longo o suficiente
# pra cobrir as execuções da janela atual. Se Redis cair entre execuções,
# pior caso é re-dispatch — handler é stub e o side-effect é log. Quando
# virar reminder real (slice futura), o handler precisa ter sua própria
# idempotência (e.g. coluna last_*_notified_at).
class Holding::Crm::ActivityCronJobBase < ApplicationJob
  queue_as :scheduled_jobs

  CACHE_TTL = 23.hours

  def perform
    Rails.logger.info({ job: self.class.name, event: "#{log_event_prefix}.cron.start" }.merge(extra_start_log_fields))

    dispatched = 0
    skipped = 0

    activity_scope.find_each(batch_size: 100) do |activity|
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
      event: "#{log_event_prefix}.cron.complete",
      dispatched: dispatched,
      skipped: skipped
    )
  end

  private

  # Template methods — subclasses devem sobrescrever.
  def activity_scope
    raise NotImplementedError
  end

  def event_constant
    raise NotImplementedError
  end

  def log_event_prefix
    raise NotImplementedError
  end

  def cache_suffix
    raise NotImplementedError
  end

  # Override opcional pra metadados extras no log de start (e.g. window_hours).
  def extra_start_log_fields
    {}
  end

  def cache_key(activity)
    "crm:activity:#{activity.id}:#{cache_suffix}"
  end

  def recently_notified?(activity)
    Rails.cache.exist?(cache_key(activity))
  end

  def mark_notified(activity)
    Rails.cache.write(cache_key(activity), Time.zone.now.to_i, expires_in: CACHE_TTL)
  end

  def dispatch_event(activity)
    Rails.configuration.dispatcher.dispatch(event_constant, Time.zone.now, activity: activity)

    Rails.logger.info(
      job: self.class.name,
      event: "#{log_event_prefix}.dispatched",
      activity_id: activity.id,
      account_id: activity.account_id
    )
  end
end
