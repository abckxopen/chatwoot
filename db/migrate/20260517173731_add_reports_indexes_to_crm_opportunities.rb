# [2026-05-17 Phase 5] Audit do CRM (Phase 5 hardening) detectou que
# CrmReportsController#agent_performance queryia por:
#   .where(status: :won, won_at: range).group(:assignee_id)
#   .where(status: :lost, lost_at: range).group(:assignee_id)
# em cima de `opportunities_scope` (account_id pré-filtrado). Os índices
# existentes `idx_crm_opportunities_account_status` + per-coluna FK cobriam
# o `account_id`+`status` mas deixavam o range em `won_at`/`lost_at` pra
# heap scan dentro da partição. Hoje (volume baixo) é OK; com 50k+ opps
# por conta o relatório vira full scan filtrado.
#
# Solução: índices PARCIAIS por status (Postgres-only — chatwoot já assume
# Postgres em outros migrations, ver idx_crm_opportunities_account_active).
# Partial mantém índice pequeno (apenas opps em won/lost, minoria do volume)
# e bate exatamente o predicado das duas queries de agent_performance.
#
# `if_not_exists: true` em ambos pra migration ser idempotente — segura
# pra rodar em ambientes onde alguém pré-criou manualmente durante triagem.
class AddReportsIndexesToCrmOpportunities < ActiveRecord::Migration[7.1]
  def change
    add_index :crm_opportunities, %i[account_id won_at],
              where: 'status = 1',
              name: 'idx_crm_opportunities_account_won_at',
              if_not_exists: true

    add_index :crm_opportunities, %i[account_id lost_at],
              where: 'status = 2',
              name: 'idx_crm_opportunities_account_lost_at',
              if_not_exists: true
  end
end
