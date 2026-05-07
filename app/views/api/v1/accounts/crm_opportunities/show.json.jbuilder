json.partial! 'crm_opportunity', opportunity: @opportunity

json.activities @opportunity.activities.order(Arel.sql('due_at ASC NULLS LAST, id ASC')) do |activity|
  json.id activity.id
  json.kind activity.kind
  json.subject activity.subject
  json.description activity.description
  json.due_at activity.due_at&.to_i
  json.completed_at activity.completed_at&.to_i
  json.assignee_id activity.assignee_id
  json.matrix_task_id activity.matrix_task_id
  json.created_at activity.created_at&.to_i
end
