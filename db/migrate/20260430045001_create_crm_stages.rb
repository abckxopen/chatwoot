# [2026-04-30] Migration #2 da Phase 0 — `crm_stages`.
#
# Estágios dentro de um pipeline (ex: Lead → Qualificado → Proposta → Ganho/Perdido).
# Cada stage pertence a 1 pipeline e tem position pra ordenação no kanban.
#
# Stages "won" e "lost" são marcadores especiais — quando opportunity entra
# em stage com `won: true`, dispara evento OPPORTUNITY_WON; mesmo pra `lost`.
# Tipicamente cada pipeline tem 1 stage com won=true e 1 com lost=true (mas
# nada impede múltiplos — ex: "Ganho-Express" e "Ganho-Padrão").
class CreateCrmStages < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_stages do |t|
      t.references :crm_pipeline, null: false,
                                  foreign_key: { to_table: :crm_pipelines, on_delete: :cascade },
                                  index: true

      # [2026-04-30] account_id duplicado em stage (já existe via pipeline) é
      # PROPOSITAL — evita JOIN em queries multi-tenant comuns ("listar stages
      # da minha conta"). Custo: 8 bytes por linha + sync nas mudanças
      # (nenhuma na prática porque stages não migram entre pipelines/contas).
      t.references :account, null: false,
                             foreign_key: true,
                             index: true

      t.string :name, null: false
      t.integer :position, null: false, default: 0

      # [2026-04-30] Cor hexa (#RRGGBB) pro chip da coluna no kanban. Validação
      # de formato no model. NULL permite — UI usa fallback.
      t.string :color

      # [2026-04-30] Marcadores semânticos. Won/lost dispatcham eventos
      # adicionais (OPPORTUNITY_WON / OPPORTUNITY_LOST) quando opp entra
      # numa stage com essa flag. Trocar pra enum exigiria migration —
      # boolean é mais flexível pra extensões futuras (ex: `qualifying`).
      t.boolean :won, null: false, default: false
      t.boolean :lost, null: false, default: false

      # [2026-04-30] JSONB pra config Matrix-task-template (Phase 2). Schema:
      # { enabled, board_id, title_template, description_template, priority }.
      # Usar JSONB em vez de tabela separada porque (a) é config por stage,
      # (b) flexível sem migration cada vez que adicionar campo, (c) pequeno
      # volume — overhead JSONB não importa.
      t.jsonb :matrix_task_template, null: false, default: {}

      t.timestamps
    end

    # [2026-04-30] (pipeline_id, position) único: 2 stages do mesmo pipeline
    # não podem ter mesma position. UI faz reordenação atômica via PATCH /reorder.
    add_index :crm_stages, [:crm_pipeline_id, :position], unique: true,
                                                          name: 'idx_crm_stages_pipeline_position'

    # [2026-04-30] (account_id, crm_pipeline_id, name) único: 2 stages do mesmo
    # pipeline não podem ter mesmo nome. Account incluso pra reforçar tenancy
    # isolation no índice (e permite usar índice em queries por account).
    add_index :crm_stages, [:account_id, :crm_pipeline_id, :name], unique: true,
                                                                   name: 'idx_crm_stages_account_pipeline_name'
  end
end
