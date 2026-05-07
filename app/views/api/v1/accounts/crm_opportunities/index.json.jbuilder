json.payload(@opportunities) do |opportunity|
  json.partial! 'crm_opportunity', opportunity: opportunity
end
json.meta do
  json.count @opportunities.total_count
  json.current_page @current_page
  json.total_pages @opportunities.total_pages
end
