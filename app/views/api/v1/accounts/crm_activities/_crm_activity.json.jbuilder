json.id activity.id
json.crm_opportunity_id activity.crm_opportunity_id
json.kind activity.kind
json.subject activity.subject
json.description activity.description
json.due_at activity.due_at&.to_i
json.completed_at activity.completed_at&.to_i
json.assignee_id activity.assignee_id
json.matrix_task_id activity.matrix_task_id
json.overdue activity.overdue?

json.created_at activity.created_at&.to_i
json.updated_at activity.updated_at&.to_i
