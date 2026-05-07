json.payload(@companies) do |company|
  json.partial! 'crm_company', company: company
end
json.meta do
  json.count @companies.total_count
  json.current_page @current_page
  json.total_pages @companies.total_pages
end
