json.id pipeline.id
json.name pipeline.name
json.description pipeline.description
json.default_pipeline pipeline.default_pipeline
json.position pipeline.position

# [2026-04-30] Stages embeddados — payload pequeno (raramente >10 stages
# por pipeline). Evita N+1 query adicional do client. Pra payload grande
# refatorar pra include/exclude opt-in via param.
# [2026-05-01] Ordena in-memory pra reusar o preload do controller
# (`includes(:stages)`). Chamar `.ordered` aqui re-queryia, defeating
# o preload — N+1 silencioso na index. sort_by replica o ORDER do scope.
json.stages pipeline.stages.sort_by { |s| [s.position, s.id] } do |stage|
  json.id stage.id
  json.name stage.name
  json.position stage.position
  json.color stage.color
  json.won stage.won
  json.lost stage.lost
end

json.created_at pipeline.created_at&.to_i
json.updated_at pipeline.updated_at&.to_i
