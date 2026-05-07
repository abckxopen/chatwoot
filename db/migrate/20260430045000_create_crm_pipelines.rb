# [2026-04-30] Migration #1 da Phase 0 do CRM da holding.
#
# Tabela `crm_pipelines` — funil de vendas. Account possui muitos pipelines;
# ex: "Outbound Engine MB", "Vendas Holding". Cada pipeline tem N stages.
#
# Convenção do fork: TODA tabela CRM com prefixo `crm_*` (decisão durável
# em `brain/fork-policy.md` 2026-04-30) pra evitar colisão com migrations
# futuras do upstream — Chatwoot já reservou nomes genéricos como `notes`,
# `activities`, `events` que poderiam conflitar.
#
# Multi-tenancy: `account_id NOT NULL` é OBRIGATÓRIO. Chatwoot escora
# tenancy comportamentalmente via `Current.account` no controller (sem
# `default_scope` automático). Sem account_id + escoping correto na query,
# vaza dado entre contas. Validação `presence: true` no model + foreign key
# aqui amarra.
class CreateCrmPipelines < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_pipelines do |t|
      # [2026-04-30] FK pra accounts c/ delete cascade — quando account é
      # removida, pipelines vão junto. Comportamento típico do Chatwoot
      # (ver create_table :calls e create_table :teams que usam mesmo padrão).
      t.references :account, null: false, foreign_key: true, index: true

      t.string :name, null: false
      t.text :description

      # [2026-04-30] `default_pipeline` flag pra UI saber qual abrir primeiro
      # se a conta tem múltiplos. Apenas 1 por account deve ser default —
      # validação fica no model (constraint parcial em Postgres é overkill
      # pra v1).
      t.boolean :default_pipeline, default: false, null: false

      # [2026-04-30] `position` ordena pipelines na sidebar do dashboard.
      # Acts-as-list é overkill — gerenciamos via API simples (PATCH /reorder).
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    # [2026-04-30] Índice composto único (account_id, name): impede 2
    # pipelines com mesmo nome na MESMA conta — UX melhor (sem duplicata
    # confusa). Não é unique global porque accounts diferentes podem ter
    # pipelines com nome igual ("Outbound Engine") — é tenant-scoped.
    add_index :crm_pipelines, [:account_id, :name], unique: true
  end
end
