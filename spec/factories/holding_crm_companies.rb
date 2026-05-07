# [2026-04-30] Factory pra Holding::Crm::Company.
FactoryBot.define do
  factory :holding_crm_company, class: 'Holding::Crm::Company' do
    account
    sequence(:name) { |n| "Empresa #{n}" }
    sequence(:domain) { |n| "empresa#{n}.com.br" }
    industry { 'tech' }
    size { '11-50' }
    additional_attributes { {} }
  end
end
