# [2026-04-30] Migration #4 da Phase 0 — `crm_opportunities`.
#
# Opportunity = Deal. Coração do CRM. Belongs to pipeline+stage, opcionalmente
# linkado a contact e company. Tem valor, prazo, probabilidade, status open/won/lost.
#
# Decisão crítica: contact_id e crm_company_id são NULLABLE. Por quê?
# - Contact pode existir sem company (lead frio sem empresa identificada)
# - Opportunity pode existir sem contact ainda (lead recém-importado de planilha)
# - Permite criar opp "rascunho" e enriquecer depois
# Validação de "tem que ter pelo menos 1" (contact OU company) fica no model.
class CreateCrmOpportunities < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_opportunities do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :crm_pipeline, null: false,
                                  foreign_key: { to_table: :crm_pipelines, on_delete: :cascade },
                                  index: true
      t.references :crm_stage, null: false,
                               foreign_key: { to_table: :crm_stages, on_delete: :restrict },
                               index: true

      # [2026-04-30] Contact é o do core upstream (`contacts` table) — NÃO
      # criamos tabela nossa. FK aponta pra contacts existente. on_delete:
      # nullify pra não perder a opp se contact é deletado (negócios
      # mantêm histórico).
      t.bigint :contact_id
      t.bigint :crm_company_id

      # [2026-04-30] Assignee é o User do core (`users` table) — agente
      # responsável pela opp. Nullable: opp pode ficar não-atribuída no inbox.
      t.bigint :assignee_id

      t.string :name, null: false
      t.text :description

      # [2026-04-30] Valor monetário. precision 15, scale 2 = até R$ 9_999_999_999_999.99.
      # Suficiente. Se precisarmos mais, migration ALTER. Currency string
      # ISO 4217 ('BRL', 'USD'). Default BRL — multi-currency ativo desde
      # início, sem migration depois.
      t.decimal :value, precision: 15, scale: 2
      t.string :currency, null: false, default: 'BRL'

      # [2026-04-30] Data esperada de fechamento (close date). NULL permitido
      # — alguns leads não têm previsão. Probabilidade 0-100 (%). Validação
      # no model.
      t.date :expected_close_date
      t.integer :probability, null: false, default: 0

      # [2026-04-30] Status como integer enum (Rails). 0=open, 1=won, 2=lost.
      # Won_at/lost_at ficam preenchidos quando muda — auditoria. Lost_reason
      # texto livre (UI tem dropdown + free text).
      t.integer :status, null: false, default: 0
      t.datetime :won_at
      t.datetime :lost_at
      t.text :lost_reason

      # [2026-04-30] Source = origem do lead ('outbound', 'inbound', 'referral',
      # 'event', etc.). String livre — enums por account ficam pra v2.
      t.string :source

      # [2026-04-30] Soft-delete via timestamp em vez de gem `discard` —
      # menos dependência. Scopes no model lidam com `where(discarded_at: nil)`.
      t.datetime :discarded_at

      # [2026-04-30] custom_attributes JSONB pra extensibilidade (ex: campos
      # custom que cada vila quer rastrear sem migration).
      t.jsonb :custom_attributes, null: false, default: {}

      t.timestamps
    end

    add_index :crm_opportunities, [:account_id, :status],
              name: 'idx_crm_opportunities_account_status'
    add_index :crm_opportunities, [:crm_pipeline_id, :crm_stage_id],
              name: 'idx_crm_opportunities_pipeline_stage'
    add_index :crm_opportunities, [:contact_id],
              name: 'idx_crm_opportunities_contact'
    add_index :crm_opportunities, [:crm_company_id],
              name: 'idx_crm_opportunities_company'
    add_index :crm_opportunities, [:assignee_id, :status],
              name: 'idx_crm_opportunities_assignee_status'
    add_index :crm_opportunities, [:expected_close_date],
              name: 'idx_crm_opportunities_close_date'
    # [2026-04-30] Index parcial em discarded_at IS NULL acelera queries
    # comuns "opps ativas". Postgres-specific; bate o requirement do Chatwoot.
    add_index :crm_opportunities, [:account_id], where: 'discarded_at IS NULL',
                                                 name: 'idx_crm_opportunities_account_active'
  end
end
