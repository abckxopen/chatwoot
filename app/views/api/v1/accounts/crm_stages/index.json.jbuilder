json.payload(@stages) do |stage|
  json.partial! 'crm_stage', pipeline: @pipeline, stage: stage
end
json.meta do
  json.crm_pipeline_id @pipeline.id
  json.count @stages.size
end
