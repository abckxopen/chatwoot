json.id opportunity.id
json.name opportunity.name
json.description opportunity.description
json.status opportunity.status
json.value opportunity.value
json.currency opportunity.currency
json.expected_close_date opportunity.expected_close_date&.iso8601
json.probability opportunity.probability
json.source opportunity.source
json.lost_reason opportunity.lost_reason
json.discarded_at opportunity.discarded_at&.to_i
json.won_at opportunity.won_at&.to_i
json.lost_at opportunity.lost_at&.to_i

json.crm_pipeline_id opportunity.crm_pipeline_id
json.crm_stage_id opportunity.crm_stage_id
json.crm_company_id opportunity.crm_company_id
json.contact_id opportunity.contact_id
json.assignee_id opportunity.assignee_id

json.custom_attributes opportunity.custom_attributes

# [2026-05-07] Embeds compactos com `.try` em vez de `&.` direto pra
# robustez quando a relação não foi eager-loaded (try retorna nil em vez
# de disparar autoload). Index eager-loads via includes(:stage, :pipeline,
# :company, :assignee, :contact); show single-record carrega sob demanda.
json.stage do
  if (stage = opportunity.try(:stage))
    json.id stage.id
    json.name stage.name
    json.won stage.won
    json.lost stage.lost
  end
end

json.pipeline do
  if (pipeline = opportunity.try(:pipeline))
    json.id pipeline.id
    json.name pipeline.name
  end
end

json.company do
  if (company = opportunity.try(:company))
    json.id company.id
    json.name company.name
    json.domain company.domain
  end
end

json.created_at opportunity.created_at&.to_i
json.updated_at opportunity.updated_at&.to_i
