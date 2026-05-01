# [2026-04-30] Factory pra Holding::Crm::Stage. Note `account` derivado do
# pipeline pra manter consistência multi-tenant — testes que passam account
# explicitamente devem passar pra ambos pipeline e stage com mesma account.
FactoryBot.define do
  factory :holding_crm_stage, class: 'Holding::Crm::Stage' do
    account { pipeline.account }
    pipeline { association :holding_crm_pipeline }
    sequence(:name) { |n| "Stage #{n}" }
    sequence(:position) { |n| n }
    color { '#3B82F6' }
    won { false }
    lost { false }

    trait :won do
      won { true }
      lost { false }
      name { 'Ganho' }
    end

    trait :lost do
      lost { true }
      won { false }
      name { 'Perdido' }
    end

    trait :with_matrix_template do
      matrix_task_template do
        {
          enabled: true,
          board_id: 'a46a66a2-e393-405c-94e1-0d73cda3a11f',
          title_template: 'Acompanhar {{opportunity.name}}',
          priority: 'medium'
        }
      end
    end
  end
end
