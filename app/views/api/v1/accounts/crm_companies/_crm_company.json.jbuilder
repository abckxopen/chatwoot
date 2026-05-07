json.id company.id
json.name company.name
json.domain company.domain
json.industry company.industry
json.size company.size
json.additional_attributes company.additional_attributes
json.opportunities_count company.try(:opportunities_count_aggr) || company.opportunities.size

json.created_at company.created_at&.to_i
json.updated_at company.updated_at&.to_i
