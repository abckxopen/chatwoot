# [2026-04-30] Factory pra Holding::Crm::Opportunity. Account vem do
# pipeline (consistência tenant), stage pertence ao mesmo pipeline.
FactoryBot.define do
  factory :holding_crm_opportunity, class: 'Holding::Crm::Opportunity' do
    transient do
      pipeline_account { nil }
    end

    pipeline { association :holding_crm_pipeline, account: pipeline_account }
    account { pipeline.account }
    stage { association :holding_crm_stage, pipeline: pipeline, account: pipeline.account }

    sequence(:name) { |n| "Oportunidade #{n}" }
    description { 'Descrição da oportunidade' }
    value { 10_000.00 }
    currency { 'BRL' }
    expected_close_date { 30.days.from_now.to_date }
    probability { 50 }
    status { :open }
    source { 'outbound' }
    custom_attributes { {} }

    trait :won do
      status { :won }
      probability { 100 }
      won_at { Time.zone.now }
    end

    trait :lost do
      status { :lost }
      probability { 0 }
      lost_at { Time.zone.now }
      lost_reason { 'Cliente desistiu' }
    end

    trait :discarded do
      discarded_at { Time.zone.now }
    end
  end
end
