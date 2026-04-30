# [2026-04-30] Factory pra Holding::Crm::Pipeline. Nome do factory:
# `:holding_crm_pipeline` (não só :pipeline pra evitar colisão com qualquer
# factory upstream futura).
FactoryBot.define do
  factory :holding_crm_pipeline, class: 'Holding::Crm::Pipeline' do
    account
    sequence(:name) { |n| "Pipeline #{n}" }
    description { 'Funil padrão de teste' }
    default_pipeline { false }
    position { 0 }

    trait :default do
      default_pipeline { true }
    end
  end
end
