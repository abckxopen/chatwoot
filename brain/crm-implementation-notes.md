# CRM Pipeline — Implementation notes (REAL vs spec)

> Documento companion de [`crm-pipeline-spec.md`](./crm-pipeline-spec.md). Spec
> era teórica (pre-implementação). Este arquivo registra o que de fato landou
> em código, decisões duráveis durante a build, e o que ficou pra follow-up.
>
> Autor: Denise (2026-05-17, fechamento Phase 5).
> Janela de implementação: 2026-04-30 → 2026-05-17.

## Caminho macro escolhido

**A — Módulo interno** em `app/models/holding/crm/` + `app/controllers/api/v1/accounts/crm_*` + Vue dashboard nativo. Confirmado e implementado.

Razão: stack único, controle total da rebase, sem segundo Rails rodando em paralelo. Foi 2-3x mais tempo que opção B (Woofed), mas a manutenção ficou a 1 sistema só.

## Backend stack (Phases 0-2)

### Controllers (6)
- `Api::V1::Accounts::CrmPipelinesController`
- `Api::V1::Accounts::CrmStagesController` (nested sob pipeline)
- `Api::V1::Accounts::CrmCompaniesController`
- `Api::V1::Accounts::CrmOpportunitiesController`
- `Api::V1::Accounts::CrmActivitiesController` (nested sob opportunity)
- `Api::V1::Accounts::CrmReportsController` (read-only, 3 endpoints)

### Concern
- `HoldingCrmConcern` — `ensure_feature_enabled` + `per_page` (clamp 1..100) + `page_param`.

### Models (5)
`Holding::Crm::Pipeline`, `::Stage`, `::Company`, `::Opportunity`, `::Activity`.

### Listener
- `Holding::CrmListener` — 3 handlers: `crm.opportunity.stage_changed`, `crm.activity.due_soon`, `crm.activity.overdue`. Registrado via `config/initializers/holding_crm.rb`.

### Jobs (3)
- `Holding::CrmNotifyMatrixJob` — egress pra Matrix API (one-way).
- `Holding::Crm::ActivityDueSoonCronJob` (1×/h) + `Holding::Crm::ActivityOverdueCronJob` (1×/d) herdando de `Holding::Crm::ActivityCronJobBase`.

### Migrations (7)
- `20260430045000_create_crm_pipelines.rb`
- `20260430045001_create_crm_stages.rb`
- `20260430045002_create_crm_companies.rb`
- `20260430045003_create_crm_opportunities.rb`
- `20260430045004_create_crm_activities.rb`
- `20260501154529_add_holding_crm_enabled_to_accounts.rb`
- `20260517173731_add_reports_indexes_to_crm_opportunities.rb` (Phase 5 audit — partial indexes `(account_id, won_at) WHERE status=1` e `(account_id, lost_at) WHERE status=2`)

### Configs
- `config/initializers/holding_crm.rb` — registra listener no AsyncDispatcher.
- `config/schedule.yml` — cron entries pros 2 ActivityCronJob.

## Frontend stack (Phases 3-4)

### Vuex modules (5)
`crmPipelines`, `crmStages`, `crmOpportunities`, `crmCompanies`, `crmActivities` — todos com `namespaced: true` (regressão fixada em Phase 3 slice 2).

### API clients (5)
1:1 com Vuex modules. Em `app/javascript/dashboard/api/`.

### Pages / routes (6)
- `CrmHome.vue` — landing (lista pipelines).
- `PipelineKanban.vue` — board DnD.
- `CompanyList.vue` — listagem paginada.
- `CompanyDetail.vue` — detalhe + opps vinculadas.
- `OpportunityDetail.vue` — detalhe + activities + edit form.
- `CrmReports.vue` — 3 reports (pipeline_summary, agent_performance, forecast).

### Sub-componentes (3)
- `ActivityList.vue`
- `OpportunityEditForm.vue`
- `ReportSection.vue`

### Helpers
- `helpers/formatters.js` — currency/date/percent formatters compartilhados.

## Decisões duráveis (anchor)

> Cada item aqui é decisão que sobreviveu code review + simplify e está
> cravada no código. Mudar = quebra. Anchor para futuro Jr não desfazer.

- **Tabelas com prefixo `crm_*`** — evita colisão com migrations upstream que poderiam reservar `notes`, `activities`, `events` (ver `brain/fork-policy.md`).
- **Tenancy via `account_id` + `Current.account.id` explícito** em TODA query — `default_scope` automático foi rejeitado (gera surprise em rake tasks / dev console).
- **Contact ↔ Company via JSONB `additional_attributes['crm_company_id']`** — NÃO criamos FK em `contacts` (zero monkey patch do core). Trade-off: perde integridade referencial mas ganha zero conflito de rebase.
- **Feature flag `accounts.holding_crm_enabled`** (coluna boolean dedicada) — NÃO em `features.yml` por causa do limite 63-bit do upstream e pra não vazar config em `custom_attributes`.
- **Matrix integration one-way only v1** — `Holding::CrmNotifyMatrixJob` cria task na Matrix quando opp entra em stage com template enabled. Bidi (Matrix → CRM) fica pra v2.
- **Reports 3 essenciais** (pipeline_summary, agent_performance, forecast) — backend agrega via `group(:column).count|.sum`, NÃO via materialized view (até crescer ~100k opps).
- **5 módulos Vuex CRM com `namespaced: true`** — bug-fix retroativo em Phase 3 slice 2 (era flat antes, getters falhavam silenciosamente).
- **`show` actions de `crmOpportunities` e `crmCompanies` fazem UPSERT** (state.records.some + ADD ou EDIT) — bug-fix retroativo em Phase 4 slice 2 (era só EDIT antes, deep-link em URL fresh não carregava o record no state).
- **Pundit em 5 controllers + skip em CrmReportsController** (read-only, concern gate basta).
- **DnD via `vuedraggable`** — optimistic commit + manual rollback em caso de API error (useAlert toast).
- **`Stage#matrix_task_template` é JSONB com permit-list EXPLÍCITA de chaves** — bloqueia client jogar 10MB jsonb arbitrário.
- **`Company#additional_attributes` é JSONB hash ABERTO** — by-design (saco de atributos custom por vila). Cap 16KB via model validation `ADDITIONAL_ATTRIBUTES_MAX_BYTES`.
- **`status` REMOVIDO da permit list de Opportunity#update** — mudança única via `#move_to_stage` pra evitar inconsistência `opp.status=won` mas `stage.won=false`.
- **`probability nil → 50`** no forecast — fallback neutro, default neutro do schema antigo era 0 (default mantido pra valores legados).
- **`value` formatado como string `"%.2f"`** em reports — payload JSON com BigDecimal vira `"0.45e3"` em alguns serializers (Oj), Float perde precisão. Sprintf garante shape estável pro frontend parsear.
- **`opportunities_count_aggr`** alias em CompaniesController#index — left_join + group em vez de N+1 por `company.opportunities.size` na jbuilder. Evita counter_cache (overkill). **Inclui discarded by-design** — UI mostra contagem total da company (incluindo soft-deleted), filtragem por status é responsabilidade do caller via list endpoint dedicado.
- **Partial indexes `(account_id, won_at) WHERE status=1` e `(account_id, lost_at) WHERE status=2`** (migration 173731) — bate exato o predicado de `agent_performance`.
- **`due_at` ordering com `Arel.sql('due_at ASC NULLS LAST, id ASC')`** em activities — activities sem due_at vão pro fim, ordenação determinística com `id ASC` como tie-break.

## Tags pushed durante implementação

| Tag | PR | Descrição |
|---|---|---|
| v0.3.1 | #15 | Phase 0 — migrations + models |
| v0.4.1 | #16 | Phase 1 slice 1 — Pipelines/Stages REST |
| v0.4.2 | #17 | Phase 1 slice 2 — Companies REST |
| v0.4.3 | #18 | Phase 2 slice 1 — listener + Matrix one-way |
| v0.4.4 | #19 | Phase 2 slice 2 — Opportunities REST + activities |
| v0.4.5 | #20 | Phase 2 slice 3 — cron jobs |
| v0.4.6 | #21 | Phase 3 — frontend Vuex + landing + Kanban DnD |
| v0.4.7 | #22 | Phase 4 slice 1-2 — Companies + OpportunityDetail UI |
| v0.4.8 | #23 | Phase 4 slice 3 — Reports backend + frontend |

Phase 5 (hardening + brain docs + runbook) fecha em PR posterior — tag conforme padrão Founder.

## Follow-ups (out of scope Phase 0-5)

Backlog pra eventual Phase 6+ ou ad-hoc fix:

- **Backend filter `crm_company_id` em `CrmOpportunities#index`** — UI hoje filtra client-side em CompanyDetail; backend ignora o param. Server-side filter é trivial (uma linha no `filtered_scope`).
- **Embedding `assignee_name` em `_crm_opportunity.json.jbuilder`** — UI mostra placeholder `"U<id>"` por enquanto. Adicionar serializer embed + `.includes(:assignee)` no controller. Triagem mostrou que o eager loading já está parcial em comentário desatualizado (fixado neste PR).
- **Materialized view + refresh job** para reports — atual ad-hoc query rodando. Migrar pra `crm_pipeline_summary_mv` + `REFRESH MATERIALIZED VIEW CONCURRENTLY` 5min quando passar de ~100k opps.
- **History/audit trail** (papertrail) em Opportunity + Activity — out of scope Phase 0-5. Flagged em `crm-security-review-preliminar.md` ponto 2.
- **Reminder real pros eventos `activity.due_soon` / `activity.overdue`** — listener atual é stub (só log). Implementar quando canal de entrega (Matrix task pro assignee? email?) for decidido pelo produto.
- **Modal de confirmação polished** pra discard/destroy — atual usa `window.confirm`.
- **Validação cross-account de `assignee_id` / `crm_stage_id`** — flagada em security review pra Sergio decidir.
- **Rate limiting dedicado** nos endpoints CRM — herda do `Rack::Attack` global se configurado, sem throttle próprio.

## Métricas finais (Phase 5 closeout)

- 6 controllers + 5 models + 1 listener + 3 jobs + 1 concern
- 5 Vuex modules + 5 API clients + 6 pages + 3 sub-componentes + 1 helper
- 7 migrations (6 originais + 1 audit Phase 5)
- 4 brain docs (este + security + runbook + onboarding) — Phase 5
- 9 tags pushed (v0.3.1 → v0.4.8) — Phase 5 entrega a 10ª
