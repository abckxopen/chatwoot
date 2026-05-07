json.payload(@activities) do |activity|
  json.partial! 'crm_activity', activity: activity
end
json.meta do
  json.crm_opportunity_id @opportunity.id
  # [2026-05-07] @activities.length em vez de .size — `length` reusa a Array
  # já carregada pelo `payload` block; `.size` em relação não-loaded dispara
  # COUNT(*) extra. Activities por opp são bounded (handful), tudo carregado
  # numa só query do index.
  json.count @activities.length
end
