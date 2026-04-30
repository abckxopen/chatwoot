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

    trait :linked_to_matrix do
      matrix_task_id { 'matrix-task-uuid-fake' }
    end
  end
end
