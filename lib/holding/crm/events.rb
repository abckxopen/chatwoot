# [2026-04-30] Constantes de eventos do módulo CRM da holding.
#
# Por que arquivo separado e não adicionar em `lib/events/types.rb` upstream:
# - lib/events/types.rb tem ~62 linhas de constantes do core. Editar mid-file
#   gera conflito em cherry-pick do upstream (ver brain/fork-policy.md).
# - Nossas constantes ficam isoladas aqui em namespace próprio.
# - O Dispatcher do Chatwoot aceita strings arbitrárias como event name —
#   não precisa registrar no `Events::Types` central. Ele só matcha o
#   método correspondente no listener (ex: 'crm.opportunity.stage_changed'
#   → CrmListener#crm_opportunity_stage_changed via Dispatcher#method_for_event).
#
# Naming: prefixar tudo com `crm.` e usar dot.notation seguindo padrão do
# upstream (ex: 'contact.created', 'conversation.status_changed'). Isso
# também garante zero colisão com namespace de eventos upstream.

module Holding::Crm::Events
  # ======================================================================
  # PIPELINE / STAGE
  # ======================================================================
  PIPELINE_CREATED          = 'crm.pipeline.created'.freeze
  PIPELINE_UPDATED          = 'crm.pipeline.updated'.freeze
  PIPELINE_DELETED          = 'crm.pipeline.deleted'.freeze

  STAGE_CREATED             = 'crm.stage.created'.freeze
  STAGE_UPDATED             = 'crm.stage.updated'.freeze

  # ======================================================================
  # COMPANY
  # ======================================================================
  COMPANY_CREATED           = 'crm.company.created'.freeze
  COMPANY_UPDATED           = 'crm.company.updated'.freeze

  # ======================================================================
  # OPPORTUNITY
  # ======================================================================
  OPPORTUNITY_CREATED       = 'crm.opportunity.created'.freeze
  OPPORTUNITY_UPDATED       = 'crm.opportunity.updated'.freeze

  # [2026-04-30] STAGE_CHANGED é o evento mais importante do CRM — gatilha
  # integração Matrix one-way (Phase 2). Payload obrigatório:
  # `{ opportunity:, old_stage_id:, new_stage_id: }`. Mudar formato
  # quebra CrmListener#crm_opportunity_stage_changed.
  OPPORTUNITY_STAGE_CHANGED = 'crm.opportunity.stage_changed'.freeze

  OPPORTUNITY_WON           = 'crm.opportunity.won'.freeze
  OPPORTUNITY_LOST          = 'crm.opportunity.lost'.freeze

  # ======================================================================
  # ACTIVITY (prazos / tarefas por opp)
  # ======================================================================
  ACTIVITY_CREATED          = 'crm.activity.created'.freeze
  ACTIVITY_COMPLETED        = 'crm.activity.completed'.freeze

  # [2026-04-30] DUE_SOON / OVERDUE são disparados por Sidekiq cron
  # (Phase 2). Cron varre activities com `due_at` em janela e dispara
  # esses eventos. Não são disparados em mudança de campo de model.
  ACTIVITY_DUE_SOON         = 'crm.activity.due_soon'.freeze
  ACTIVITY_OVERDUE          = 'crm.activity.overdue'.freeze
end
