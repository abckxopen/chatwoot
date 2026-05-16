# [2026-04-30] Factory pra Holding::Crm::Activity.
FactoryBot.define do
  factory :holding_crm_activity, class: 'Holding::Crm::Activity' do
    opportunity { association :holding_crm_opportunity }
    account { opportunity.account }
    sequence(:subject) { |n| "Atividade #{n}" }
    description { 'Detalhes da atividade' }
    kind { :task }
    due_at { 1.day.from_now }
    completed_at { nil }
    matrix_task_id { nil }

    trait :completed do
      completed_at { Time.zone.now }
    end

    trait :overdue do
      due_at { 2.days.ago }
      completed_at { nil }
    end

    # [2026-05-16] Phase 2 slice 3 — activity dentro da janela do
    # ActivityDueSoonCronJob (now..now+24h). 1h pra ficar bem no meio
    # da janela e não esbarrar em race com Time.zone.now sliding.
    trait :due_soon do
      due_at { 1.hour.from_now }
      completed_at { nil }
    end

    trait :linked_to_matrix do
      matrix_task_id { 'matrix-task-uuid-fake' }
    end
  end
end
