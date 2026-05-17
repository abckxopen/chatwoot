# CRM Pipeline — Onboarding Jr

> Documento pra agente Jr (humano ou IA) que vai operar / estender o módulo
> CRM no fork chatwoot. Passo-a-passo, didático, com cli copy-paste-friendly.
>
> Para CONTEXTO TEÓRICO: ver `crm-pipeline-spec.md`.
> Para O QUE LANDOU NA REALIDADE: ver `crm-implementation-notes.md`.
> Para DEPLOY / RUNBOOK: ver `crm-deploy-runbook.md`.
> Para SECURITY: ver `crm-security-review-preliminar.md`.

## TL;DR

```
1. Liga feature pra account (rails console)
2. Cria pipeline + stages (API)
3. Cria opportunity (API ou UI)
4. Cria activity dentro da opp
5. Move opp entre stages (DnD na UI)
6. Vê kanban / companies / opportunity detail / reports na UI
```

---

## Passo 1 — Ligar feature pra uma conta

Default é OFF — toda conta nasce sem CRM. Pra ativar:

```ruby
# rails console
Account.find(X).update!(holding_crm_enabled: true)
```

Sem isso, qualquer request pra `/api/v1/accounts/X/crm_*` retorna **403 Forbidden** (gate em `HoldingCrmConcern#ensure_feature_enabled`).

Pra desligar:
```ruby
Account.find(X).update!(holding_crm_enabled: false)
```

Pra desligar TUDO (emergência):
```ruby
Account.update_all(holding_crm_enabled: false)
```

---

## Passo 2 — Criar primeiro pipeline + stages

### Via API (rapidão pra dev/staging):

```bash
TOKEN="api_access_token_do_admin"  # pega no perfil do user
ACCOUNT_ID=1
HOST="http://localhost:3000"  # ou https://chat.abckx.com.br em prod

# 1. Cria pipeline
curl -X POST $HOST/api/v1/accounts/$ACCOUNT_ID/crm_pipelines \
  -H "api_access_token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"crm_pipeline": {"name": "Outbound Engine MB", "default_pipeline": true}}'
# → 201 {id: 1, name: "...", stages: []}

PIPELINE_ID=1

# 2. Cria 4 stages: Lead → Qualificado → Proposta → Ganho
curl -X POST $HOST/api/v1/accounts/$ACCOUNT_ID/crm_pipelines/$PIPELINE_ID/crm_stages \
  -H "api_access_token: $TOKEN" -H "Content-Type: application/json" \
  -d '{"crm_stage": {"name": "Lead", "position": 0, "color": "#3b82f6"}}'

curl -X POST $HOST/api/v1/accounts/$ACCOUNT_ID/crm_pipelines/$PIPELINE_ID/crm_stages \
  -H "api_access_token: $TOKEN" -H "Content-Type: application/json" \
  -d '{"crm_stage": {"name": "Qualificado", "position": 1, "color": "#f59e0b"}}'

curl -X POST $HOST/api/v1/accounts/$ACCOUNT_ID/crm_pipelines/$PIPELINE_ID/crm_stages \
  -H "api_access_token: $TOKEN" -H "Content-Type: application/json" \
  -d '{"crm_stage": {"name": "Proposta", "position": 2, "color": "#a855f7"}}'

curl -X POST $HOST/api/v1/accounts/$ACCOUNT_ID/crm_pipelines/$PIPELINE_ID/crm_stages \
  -H "api_access_token: $TOKEN" -H "Content-Type: application/json" \
  -d '{"crm_stage": {"name": "Ganho", "position": 3, "won": true, "color": "#22c55e"}}'
```

### Via UI:
1. Login no chatwoot.
2. Sidebar → CRM (só aparece se feature ligada — passo 1).
3. Botão "Novo pipeline" no `CrmHome.vue`.
4. Dentro do pipeline, sidebar de stages permite criar/reordenar.

---

## Passo 3 — Criar primeira opportunity

### Via API:
```bash
curl -X POST $HOST/api/v1/accounts/$ACCOUNT_ID/crm_opportunities \
  -H "api_access_token: $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "crm_opportunity": {
      "name": "Cliente Vila Norte — proposta R$ 30k",
      "value": 30000,
      "currency": "BRL",
      "expected_close_date": "2026-06-15",
      "probability": 70,
      "source": "outbound",
      "crm_pipeline_id": 1,
      "crm_stage_id": 1,
      "assignee_id": 2
    }
  }'
# → 201
```

### Via UI:
Botão "Nova opportunity" no kanban (`PipelineKanban.vue`) — abre modal/route com `OpportunityEditForm.vue`.

---

## Passo 4 — Criar activity dentro da opp

Activities = tasks/prazos dentro da opp. Modelo: call/email/meeting/note/task.

```bash
OPP_ID=1
curl -X POST $HOST/api/v1/accounts/$ACCOUNT_ID/crm_opportunities/$OPP_ID/crm_activities \
  -H "api_access_token: $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "crm_activity": {
      "kind": "call",
      "subject": "Follow-up sobre proposta",
      "description": "Ligar pra confirmar recebimento",
      "due_at": "2026-05-20T14:00:00-03:00",
      "assignee_id": 2
    }
  }'
```

**Completar activity:**
```bash
ACTIVITY_ID=1
curl -X PATCH $HOST/api/v1/accounts/$ACCOUNT_ID/crm_opportunities/$OPP_ID/crm_activities/$ACTIVITY_ID/complete \
  -H "api_access_token: $TOKEN" -H "Content-Type: application/json" \
  -d '{}'
# (sem body = completed_at = now)
```

Activity aberta com `due_at` próximo é varrida pelo `ActivityDueSoonCronJob` (1×/h) → evento `crm.activity.due_soon`. Atualmente é stub (só loga); reminder real fica pra slice futura.

---

## Passo 5 — Mover opp entre stages

### Via API:
```bash
NEW_STAGE_ID=2
curl -X PATCH $HOST/api/v1/accounts/$ACCOUNT_ID/crm_opportunities/$OPP_ID/move_to_stage \
  -H "api_access_token: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"stage_id\": $NEW_STAGE_ID}"
```

Se stage destino tem `won: true` ou `lost: true`, dispara eventos:
- `crm.opportunity.won` ou `crm.opportunity.lost` (model lifecycle).
- `crm.opportunity.stage_changed` (sempre) → listener pode enqueue `CrmNotifyMatrixJob` se stage tem `matrix_task_template.enabled = true`.

### Via UI:
Drag entre colunas do kanban (`PipelineKanban.vue`). Optimistic commit no Vuex; rollback automático se API falhar (mostra `useAlert` toast).

---

## Passo 6 — Navegar a UI

Rotas relativas ao `/app/accounts/X`:
- `/crm` → `CrmHome.vue` (lista pipelines)
- `/crm/pipelines/<id>/kanban` → `PipelineKanban.vue`
- `/crm/companies` → `CompanyList.vue`
- `/crm/companies/<id>` → `CompanyDetail.vue`
- `/crm/opportunities/<id>` → `OpportunityDetail.vue`
- `/crm/reports?pipeline_id=<id>` → `CrmReports.vue` (3 cards: pipeline_summary, agent_performance, forecast)

---

## Onde ficam os logs

### Dev local
```bash
tail -f log/development.log | grep crm
```

### Sidekiq jobs (dev e prod)
- Sidekiq Web Dashboard em `/sidekiq` (auth admin).
- Filas usadas: `:default` (CrmNotifyMatrixJob) e `:scheduled_jobs` (cron jobs).

### Prod (k8s)
```bash
kubectl -n chatwoot logs -l app=chatwoot,role=web --tail=200 -f | grep 'event:crm'
kubectl -n chatwoot logs -l app=chatwoot,role=sidekiq --tail=200 -f | grep 'event:crm'
```

Tags de log pra grep (todos em hash JSON, `event:` key sempre presente):
```
event:crm.opportunity.stage_changed.queued_matrix_notify
event:crm.matrix.notify.success | .skip | .fatal_discarded
event:crm.activity.due_soon.received | .cron.start | .cron.complete | .dispatched
event:crm.activity.overdue.received | .cron.start | .cron.complete | .dispatched
```

---

## Debugging — "opp não aparece no kanban"

Checklist linear (eliminar de cima pra baixo):

1. **account_id correto?** Logado na conta certa? URL bate?
2. **Feature flag ligada?** `Account.find(X).holding_crm_enabled?` retorna `true`?
3. **pipeline_id correto?** Opp tem `crm_pipeline_id = <id>` do pipeline aberto?
4. **status open?** Kanban só mostra opps com `status: :open`. Won/lost vão pra reports, não pro board.
5. **discarded_at NULL?** Soft-deleted opps não aparecem. Re-ativar com `opp.undiscard!`.
6. **Vuex carregou?** Devtools → Vuex tab → módulo `crmOpportunities/records` deve ter o registro.

---

## Debugging — "filtro não funciona em opportunities"

Backend aceita só **snake_case** nos filters do `CrmOpportunities#index`:
- `pipeline_id`
- `stage_id`
- `status`
- `assignee_id`
- `include_discarded=true|false` (default false)

**NÃO** aceita `pipelineId` (camelCase) — passa silenciosamente sem filtrar.

Filtro `crm_company_id` ainda NÃO existe no backend (out of scope Phase 5). UI filtra client-side em `CompanyDetail.vue`. Follow-up flagged em `crm-implementation-notes.md`.

---

## Common gotchas

> Cada item aqui custou tempo durante a build. Memorize ou perde 30min reproduzindo.

- **Vuex namespace `crmPipelines/` (etc) — sem `namespaced: true` getters resolvem flat e falham silenciosamente.** Foi bug-fix retroativo Phase 3 slice 2. Se você adicionar novo módulo Vuex CRM, copia da `crmOpportunities` e mantém `namespaced: true`.
- **`show` actions de `crmOpportunities` e `crmCompanies` fazem UPSERT** (state.records.some + ADD ou EDIT). Foi bug-fix Phase 4 slice 2 — deep-link em URL fresh não carregava o record. Se você adicionar novo crm_* model com show action, mirror o pattern.
- **Backend filters em opportunities aceitam só snake_case** — ver seção acima.
- **`PATCH /opportunities/:id` NÃO aceita `status`.** Mudança via `#move_to_stage` apenas. Se mexer no permit list e adicionar `:status`, vai criar inconsistência `opp.status=won` mas `stage.won=false` → kanban quebra, reports filtram errado.
- **Drag entre stages dispatcha optimistic update.** Se API falhar, rollback dispara `useAlert` toast — usuário vê erro mas o card já voltou pro stage original.
- **`opportunity.value` é Decimal — formate antes de mostrar no frontend.** Use `helpers/formatters.js` (currency formatter). `Number(value)` direto perde precisão pra valores grandes.
- **`window.confirm`** ainda é usado pra discard/destroy — substituir por modal polished é follow-up.
- **`opportunity.probability nil` é tratado como 50** no forecast report (default neutro). Default do schema é 0 (mantido pra valores legados).
- **Liquid templates em `Stage#matrix_task_template`** são sandbox-safe (sem acesso a Ruby), mas template malformado vira fatal-discard do CrmNotifyMatrixJob — vai pro dead set, não retry. Testar template em staging antes de salvar em prod.
- **`additional_attributes` (companies) e `custom_attributes` (opportunities) são JSONB ABERTOS** — sem schema enforcement, só cap de 16KB. Não armazene PII bruta aí.

---

## Próximos passos sugeridos pra um Jr

Tasks de baixo risco pra ramp-up:

1. **Implementar backend filter `crm_company_id` em `CrmOpportunities#index`** — uma linha no `filtered_scope`. Tem teste existente que pode ser estendido.
2. **Embeddar `assignee_name` em `_crm_opportunity.json.jbuilder`** — adicionar `.includes(:assignee)` no controller, embed scalar `assignee_name: opp.assignee&.name`.
3. **Substituir `window.confirm` por modal polished** em destroy/discard — usa o padrão de modal já existente no chatwoot.
4. **Implementar reminder real pros eventos `activity.due_soon` / `activity.overdue`** — listener atual é stub. Decidir canal de entrega antes (Matrix task? email? notification?).

Todos têm impacto pequeno e podem ser shipados como slices independentes.
