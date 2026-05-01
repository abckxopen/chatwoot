json.meta do
  json.count @pipelines.total_count
  json.current_page @current_page
end

json.payload @pipelines do |pipeline|
  json.partial! 'api/v1/accounts/crm_pipelines/crm_pipeline', pipeline: pipeline
end
