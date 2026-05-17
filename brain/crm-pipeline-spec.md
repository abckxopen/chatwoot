# Spec — CRM Pipeline pro fork abckxopen/chatwoot

> **[2026-05-17 — Phase 5 closeout]** Spec é histórico. Implementação real
> está em [`crm-implementation-notes.md`](./crm-implementation-notes.md).
> Phase 5 (hardening + brain docs + runbook) entregue em PR de fechamento
> da CRM Pipeline initiative — referência: tag v0.4.9.
> Para deploy: [`crm-deploy-runbook.md`](./crm-deploy-runbook.md).
> Para onboarding: [`crm-jr-onboarding.md`](./crm-jr-onboarding.md).
> Para security review: [`crm-security-review-preliminar.md`](./crm-security-review-preliminar.md).

> Documento canônico que guia a implementação. Companion de `crm-research.md` (precedentes de mercado) e `crm-codebase-patterns.md` (padrões internos). Esta spec é a síntese — quando bater dúvida durante a implementação, este arquivo é a fonte.
>
> Status: **DRAFT — aguardando approval do Founder em escolha de caminho macro.**

## Objetivo

Adicionar ao Chatwoot da holding um módulo CRM/Sales Pipeline first-class:

- Pipeline (ex: "Outbound Engine", "Vendas MentoringBase")
- Stage por pipeline (Lead → Qualificado → Proposta → Ganho/Perdido — configurável)
- Company (model novo) — Chatwoot upstream só tem nome de empresa em campo solto no contact
- Contact (já existe) — adicionar relação com Company + Opportunities
- Opportunity (Deal) — pipeline+stage, contact, company, valor, deadline
- Activity / Prazo — atividades por opportunity, com due date e assignee
- Integração Matrix one-way: stage_changed → cria Matrix task

Foco: **API-first** (uso principal é via API + outros sistemas da holding consumindo). Frontend Vue serve apresentação + relatórios.

## Decisão pendente — caminho macro

| Caminho | Esforço | Trade-off |
|---------|---------|-----------|
| **A. Módulo interno** em `app/models/crm/` + `app/controllers/api/v1/accounts/crm_*` + Vue dashboard nativo | 4-6 semanas | Controle total. Eu absorvo conflito de rebase upstream. Stack único. |
| **B. Woofed CRM como base** (clonar `douglara/woofed-crm`, adaptar pra holding, plugar via API + Dashboard App) | 1-3 semanas | Economiza ~4 semanas. Maturidade pronta. Mas é um **segundo sistema** (Rails separado) pra rodar/atualizar/securizar. |
| **C. Dashboard App do zero** (UI Vue/React separada + nossa backend pequena consumindo APIs Chatwoot) | 3-5 semanas | Padrão oficialmente endossado pela Chatwoot. Mais leve que B (sem app gigante separado). Menos integrado que A. |
| **D. Híbrido A+B** | 6-8 semanas | Começa em B pra ganhar tempo, depois absorve features-chave em A em rebases. |

**Recomendação Denise: A.** Razões:
- Founder pediu API-first + frontend integrado pra reports — A entrega ambos.
- Codebase do Chatwoot já tem flag `crm` reservada e patterns prontos pra módulo novo.
- Operacionalmente mais simples (1 sistema, 1 deploy, 1 banco).
- Rebase upstream é gerenciável se a gente isolar em `app/models/crm/`, `crm_*` migrations, listener próprio (não estender `WebhookListener` core).
- Não fechamos porta pra B/C: se daqui 3 meses a gente quiser separar, é refactor (não retrabalho perdido).

**Aguardando GO em A** antes de Phase 1. Se Founder preferir B ou C, repactuar phasing.

## Arquitetura (Caminho A)

### Modelo de dados

```
Account (existing)
  └── crm_pipelines (1:N)
        ├── crm_stages (1:N) — ordered by position
        └── crm_opportunities (1:N)
              ├── crm_stage (N:1)
              ├── contact (N:1) — model existing
              ├── crm_company (N:1, nullable)
              └── crm_activities (1:N)

  └── crm_companies (1:N)
        └── contacts (1:N) — extend existing Contact
        └── crm_opportunities (1:N)
```

### Tabelas (8 migrations, prefixo `crm_*`)

1. `create_crm_pipelines` — `id, account_id, name, description, default_pipeline:bool, position:int, created_at, updated_at` + index `(account_id, name)` unique.
2. `create_crm_stages` — `id, account_id, crm_pipeline_id, name, position:int, color:string, won:bool default false, lost:bool default false, created_at, updated_at` + index `(crm_pipeline_id, position)`.
3. `create_crm_companies` — `id, account_id, name, domain:string, industry, size, additional_attributes:jsonb default {}, created_at, updated_at` + index `(account_id, domain)` unique-when-not-null.
4. `create_crm_opportunities` — `id, account_id, crm_pipeline_id, crm_stage_id, contact_id, crm_company_id (nullable), assignee_id (User, nullable), name:string, description:text, value:decimal(15,2), currency:string default 'BRL', expected_close_date:date, probability:int 0-100, status:int (open/won/lost), source:string, custom_attributes:jsonb default {}, created_at, updated_at, won_at, lost_at, lost_reason:text` + indexes `(account_id, status)`, `(crm_pipeline_id, crm_stage_id)`, `(contact_id)`, `(assignee_id)`.
5. `create_crm_activities` — `id, account_id, crm_opportunity_id, kind:int (call/email/meeting/note/task), subject:string, description:text, due_at:datetime, completed_at:datetime, assignee_id (User, nullable), matrix_task_id:string (link bidirectional later), created_at, updated_at` + indexes `(crm_opportunity_id, due_at)`, `(assignee_id, completed_at)`.
6. `add_crm_company_id_to_contacts` — `ALTER TABLE contacts ADD COLUMN crm_company_id BIGINT NULL REFERENCES crm_companies(id)` + index. Não-destrutivo, opcional. NB: editar tabela upstream `contacts` é o único ponto de fricção c/ rebase. Alternativa: armazenar em `Contact#additional_attributes` JSONB e servir relação via método. **Decisão recomendada: JSONB pra evitar conflito.**
7. `create_crm_pipeline_views` — view materializada ou simples view SQL pra summary do kanban (count opportunities por stage, sum value por stage). Se for view materializada, agendar refresh por Sidekiq.
8. `add_crm_feature_flag_to_features_yml` — não é migration, é edit em `config/features.yml` adicionando `crm_pipeline` flag (`enabled: false`, ativa por conta).

### API REST

Endpoint base: `/api/v1/accounts/:account_id/crm_*`

**Pipelines:**
- `GET    /crm_pipelines` — list (com count opportunities + total value por pipeline)
- `POST   /crm_pipelines` — create (admin only)
- `GET    /crm_pipelines/:id` — show (with stages embedded)
- `PATCH  /crm_pipelines/:id` — update (admin only)
- `DELETE /crm_pipelines/:id` — delete (admin only, blocked if has open opps)

**Stages (nested):**
- `GET    /crm_pipelines/:pipeline_id/crm_stages`
- `POST   /crm_pipelines/:pipeline_id/crm_stages`
- `PATCH  /crm_pipelines/:pipeline_id/crm_stages/:id`
- `DELETE /crm_pipelines/:pipeline_id/crm_stages/:id`
- `PATCH  /crm_pipelines/:pipeline_id/crm_stages/reorder` — bulk reorder via array de ids

**Companies:**
- `GET    /crm_companies` — list with sift filters (name, domain, industry)
- `POST   /crm_companies`
- `GET    /crm_companies/:id` — show with contacts list + opportunities count
- `PATCH  /crm_companies/:id`
- `DELETE /crm_companies/:id`

**Opportunities:**
- `GET    /crm_opportunities` — list with sift filters (status, pipeline_id, stage_id, assignee_id, expected_close_date_range)
- `POST   /crm_opportunities`
- `GET    /crm_opportunities/:id` — show with activities + contact + company embedded
- `PATCH  /crm_opportunities/:id`
- `PATCH  /crm_opportunities/:id/move_to_stage` — body `{stage_id, reason?}`
- `PATCH  /crm_opportunities/:id/win` — body `{won_value?, won_at?}`
- `PATCH  /crm_opportunities/:id/lose` — body `{lost_reason}`
- `DELETE /crm_opportunities/:id` — soft-delete via `discarded_at` (gem `discard`?)

**Activities:**
- `GET    /crm_opportunities/:opp_id/crm_activities`
- `POST   /crm_opportunities/:opp_id/crm_activities`
- `PATCH  /crm_opportunities/:opp_id/crm_activities/:id`
- `PATCH  /crm_opportunities/:opp_id/crm_activities/:id/complete`
- `DELETE /crm_opportunities/:opp_id/crm_activities/:id`

**Reports:**
- `GET /crm_reports/pipeline_summary?pipeline_id=...` — count + value por stage, conversion rate stage-to-stage, average time per stage.
- `GET /crm_reports/agent_performance?from=&to=` — opps fechadas por agent, value, win-rate.
- `GET /crm_reports/forecast?pipeline_id=&until=` — sum(value × probability) projetado.

### Eventos (`lib/events/types.rb` adicionar)

```ruby
PIPELINE_CREATED          = 'pipeline.created'
PIPELINE_UPDATED          = 'pipeline.updated'
OPPORTUNITY_CREATED       = 'opportunity.created'
OPPORTUNITY_UPDATED       = 'opportunity.updated'
OPPORTUNITY_STAGE_CHANGED = 'opportunity.stage_changed'
OPPORTUNITY_WON           = 'opportunity.won'
OPPORTUNITY_LOST          = 'opportunity.lost'
ACTIVITY_CREATED          = 'activity.created'
ACTIVITY_DUE_SOON         = 'activity.due_soon'  # disparado por Sidekiq cron
ACTIVITY_OVERDUE          = 'activity.overdue'   # disparado por Sidekiq cron
```

### Listener (`app/listeners/crm_listener.rb`)

Subscriber dos eventos acima. Responsabilidades:
- `opportunity_stage_changed` → enfileirar `CrmNotifyMatrixJob` se stage tiver `matrix_template` configurado
- `opportunity_won` / `opportunity_lost` → enfileirar `CrmNotifyMatrixJob` + dispatch interno pra dashboard ActionCable
- `activity_due_soon` (cron 1× hora) → enfileirar `CrmRemindAssigneeJob`

### Jobs

- `CrmNotifyMatrixJob(opportunity_id, event_type)` — chama Matrix API criando task. Idempotente (checa `matrix_task_id` no opp/activity antes de criar).
- `CrmActivityCronJob` — Sidekiq scheduler 1× hora; varre `crm_activities` com `due_at` em [now, now+24h] e dispara `activity.due_soon` event.
- `CrmActivityOverdueCronJob` — 1× dia; varre `due_at < now AND completed_at IS NULL` dispara `activity.overdue`.

### Integração Matrix

**One-way (v1):** Chatwoot → Matrix.

Trigger:
- Configuração por **stage**: campo `matrix_task_template:jsonb` em `crm_stages` com schema:
  ```json
  {
    "enabled": true,
    "board_id": "uuid-board",
    "title_template": "Acompanhar {{opportunity.name}}",
    "description_template": "Opp na stage {{stage.name}}, contato {{contact.name}}",
    "priority": "medium",
    "depends_on_template": null
  }
  ```
- Quando opp entra na stage, `CrmListener#opportunity_stage_changed` enfileira `CrmNotifyMatrixJob`.
- Job renderiza template (Liquid? Mustache? — Chatwoot já usa Liquid em outros lugares; reusar) e chama Matrix `mcp__matrix__matrix_create_task`.
- Salva o `task_id` retornado em `crm_opportunities.custom_attributes['matrix_task_ids']` (array, append).

**Bidirecional (v2 futuro):** quando Matrix task vira `done`, webhook → API Chatwoot move opp pra próxima stage. Out of scope da v1.

### Frontend

- **Vuex store:** `app/javascript/dashboard/store/modules/crm/` (pipelines, stages, opportunities, companies, activities, reports — sub-modules ou um módulo grande).
- **API clients:** `app/javascript/dashboard/api/crm/{pipelines,stages,opportunities,companies,activities,reports}.js`.
- **Routes:** `app/javascript/dashboard/routes/dashboard/crm/crm.routes.js`.
- **Páginas:**
  - `CrmHome.vue` — landing com lista de pipelines + métricas-resumo
  - `PipelineKanban.vue` — board kanban drag-and-drop (lib `vuedraggable` ou `@vueuse/core` + manual)
  - `OpportunityDetail.vue` — detalhe da opp + atividades + histórico de stages
  - `CompanyDetail.vue` — detalhe da empresa + contatos + opps
  - `CompanyList.vue` / `OpportunityList.vue` — listas com filtros (sift)
  - `CrmReports.vue` — relatórios (recharts ou Chart.js — verificar lib upstream)
- **i18n:** strings em `config/locales/{pt,en}.yml` namespace `crm:`.
- **Feature flag gate:** rotas com `meta: { featureFlag: FEATURE_FLAGS.CRM_PIPELINE }`.

### Policies (Pundit)

- `CrmPipelinePolicy`, `CrmStagePolicy`, `CrmCompanyPolicy`, `CrmOpportunityPolicy`, `CrmActivityPolicy`.
- `index?`, `show?`: agent + administrator.
- `create?`, `update?`: agent (suas opps) + administrator (todas).
- `destroy?`: administrator only.
- Se `account.feature_enabled?(:custom_roles)` (enterprise feature já existente): granular via roles custom.

### Tests

- Models: validations, associations, scopes, dispatch de eventos.
- Policies: matriz roles × actions.
- Requests (RSpec): happy path + 401/403/404 + tenancy isolation (criar 2 accounts e garantir que GET /crm_opportunities da account A não retorna opps da B).
- Listeners: mock dispatcher, asserir job enqueued.
- Jobs: stub Matrix API client, asserir chamada com payload correto.
- Frontend: vitest pra components + Vuex.

## Phasing (proposta — sujeito a Founder GO)

### Fase 0 — Base de domínio (1 semana)
- Migrations 1-5 + 8 (sem alterar Contact, sem feature `crm_company_id` em contacts ainda — usar JSONB).
- Models `Crm::Pipeline`, `Crm::Stage`, `Crm::Company`, `Crm::Opportunity`, `Crm::Activity`.
- Validations, associations, dispatch de eventos.
- Tests model 100%.
- Feature flag `crm_pipeline` em `config/features.yml`.

### Fase 1 — API REST + Policies (1-2 semanas)
- Controllers `Api::V1::Accounts::Crm*Controller`.
- JBuilder serializers.
- Policies Pundit.
- Routes em `config/routes.rb`.
- Tests request 100% (incluindo tenancy isolation).
- **Já dá pra usar via API** — primeiro milestone "API-first" cumprido.

### Fase 2 — Listener + Sidekiq + Matrix one-way (1 semana)
- `CrmListener`.
- `CrmNotifyMatrixJob`.
- `CrmActivityCronJob`, `CrmActivityOverdueCronJob`.
- Configuração de `matrix_task_template` em stage.
- Tests integration end-to-end com Matrix mockado.

### Fase 3 — Frontend Kanban + Detalhes (1-2 semanas)
- Vuex store + API clients.
- Routes + páginas core (Home, Kanban, OpportunityDetail).
- Drag-and-drop entre stages com optimistic update + rollback on error.
- Feature flag gating no router.
- Tests vitest.

### Fase 4 — Companies, Activities UI, Reports (1 semana)
- CompanyList, CompanyDetail, OpportunityList.
- Activity timeline na OpportunityDetail.
- CrmReports com 3 relatórios da spec.
- Polish + i18n completo.

### Fase 5 — Hardening + Docs (3-5 dias)
- Performance: índices revisados, N+1 audit, eager loading.
- Security review (Sergio).
- Brain docs atualizadas com decisões tomadas.
- Runbook deploy / migration / rollback.

**Total:** 5-8 semanas de trabalho focado pra prod-pronto. Phase 1 já entrega valor (API funcional) em 2-3 semanas.

## Decisões duráveis tomadas (anchor pra implementação)

- **Caminho macro:** A (módulo interno) — pendente confirmação Founder.
- **Tabelas:** prefixo `crm_*` obrigatório.
- **Tenancy:** `account_id` em tudo + scoping via `Current.account`.
- **Contact ↔ Company:** via JSONB `additional_attributes['crm_company_id']` (não FK direto, evita conflito rebase em `contacts`).
- **Feature flag:** `crm_pipeline` (não reusar `crm` por respeito a possível roadmap upstream).
- **Matrix integration:** one-way only v1; bidirecional v2.
- **Soft-delete:** opportunities suportam (gem `discard` ou similar — confirmar se já tem no Gemfile, senão usar timestamp `discarded_at` manual).
- **Reports:** 3 essenciais (pipeline_summary, agent_performance, forecast). Mais sob demanda.
- **Push em fork:** bloqueado por permissão GitHub no momento — branches locais, push quando acesso resolvido.

## Open questions / risks

1. **Branding x CRM:** Founder mencionou rebrand depois. Confirmar que branding do dashboard pode ser feito post-CRM sem retrabalho.
2. **Multi-currency:** suportamos só BRL ou desde início multi-currency? Default BRL é OK.
3. **Imports:** vai precisar importar leads existentes (CSV, planilhas)? Não está em escopo v1; agendar Phase 5+.
4. **Webhooks externos:** clientes externos (Mautic, sistemas da holding) precisam consumir eventos CRM via webhook? Adicionar suporte nativo Webhook do Chatwoot pra eventos `opportunity.*` é trivial — vale incluir em Fase 2.
5. **Rebase cadence:** Chatwoot release ~mensal. Definir cadência de rebase (semanal sugerido) e CI que detecta conflito cedo.

---

**Autor:** Denise (curinga dev abckxopen).  
**Última atualização:** 2026-04-30 03:30 UTC.  
**Próxima revisão:** após GO do Founder em escolha de caminho.
