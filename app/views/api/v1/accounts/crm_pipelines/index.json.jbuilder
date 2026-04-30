json.meta do
  json.count @total_count
  json.current_page params[:page].to_i.positive? ? params[:page].to_i : 1
end

json.payload @pipelines do |pipeline|
  json.partial! 'api/v1/accounts/crm_pipelines/crm_pipeline', pipeline: pipeline
end
