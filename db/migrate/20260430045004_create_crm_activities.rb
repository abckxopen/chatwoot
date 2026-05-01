# [2026-04-30] Migration #5 da Phase 0 — `crm_activities`.
#
# Activity = atividade/prazo dentro de uma opportunity. Modela "tarefas
# por opp" (Founder msg 270): chamadas, emails, reuniões, follow-ups,
# notas. Cada activity tem due_at, assignee, kind.
#
# Founder pediu (msg 270): "podemos ter o basico agora, mas ja pensando que
# podemos colocar mais tasks ali por fase". Esse model permite 1 activity
# de "follow-up" por opp inicial (basico) e expansão pra múltiplas
# atividades por fase quando o time precisar.
class CreateCrmActivities < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    create_table :crm_activities do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :crm_opportunity, null: false,
                                     foreign_key: { to_table: :crm_opportunities, on_delete: :cascade },
                                     index: true

      # [2026-04-30] Kind como integer enum: 0=call, 1=email, 2=meeting,
      # 3=note, 4=task. Trocar nomes/ordem QUEBRA dados existentes.
      t.integer :kind, null: false, default: 4

      t.string :subject, null: false
      t.text :description

      # [2026-04-30] due_at + completed_at. Activity OPEN se completed_at IS NULL.
      # Cron job (Phase 2) varre due_at em janelas pra disparar
      # ACTIVITY_DUE_SOON e ACTIVITY_OVERDUE.
      t.datetime :due_at
      t.datetime :completed_at

      # [2026-04-30] User do core upstream. Nullable: activity pode ser
      # geral, sem assignee.
      t.bigint :assignee_id

      # [2026-04-30] matrix_task_id armazena id da task espelho na Matrix
      # quando integração one-way criar (Phase 2). Bidi (Matrix → CRM)
      # fica pra v2. Permitir NULL: nem toda activity vira task Matrix.
      t.string :matrix_task_id

      t.timestamps
    end

    add_index :crm_activities, [:crm_opportunity_id, :due_at],
              name: 'idx_crm_activities_opp_due'
    add_index :crm_activities, [:assignee_id, :completed_at],
              name: 'idx_crm_activities_assignee_completed'
    # [2026-04-30] Index parcial pra cron varrer activities open com due_at
    # próximo — query quente do scheduler.
    add_index :crm_activities, [:account_id, :due_at],
              where: 'completed_at IS NULL',
              name: 'idx_crm_activities_open_due'
  end
end
