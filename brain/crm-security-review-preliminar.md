# CRM Pipeline — Security review preliminar (Phase 5)

> Preparado por Denise (2026-05-17) pra revisão formal do Sergio.
> Cobre superficie de ataque introduzida pelos Phases 0-4 do módulo CRM
> (commits 2026-04-30 → 2026-05-16 / tags v0.3.1 → v0.4.8).
>
> Este é o BASELINE — não substitui o pen-test/threat-model do Sergio.

## Surface de ataque

### Controllers REST (6 — todos sob `/api/v1/accounts/:account_id/`)

| Controller | Endpoints | Pundit? | Concern gate |
|---|---|---|---|
| `CrmPipelinesController` | index/show/create/update/destroy | sim | HoldingCrmConcern |
| `CrmStagesController` | index/create/update/destroy + #reorder | sim | HoldingCrmConcern |
| `CrmCompaniesController` | index/show/create/update/destroy | sim | HoldingCrmConcern |
| `CrmOpportunitiesController` | index/show/create/update/destroy + #move_to_stage + #discard | sim | HoldingCrmConcern |
| `CrmActivitiesController` | index/create/update/destroy + #complete (nested sob opportunity) | sim | HoldingCrmConcern |
| `CrmReportsController` | pipeline_summary / agent_performance / forecast | **NÃO** (read-only) | HoldingCrmConcern |

### Listener

- `Holding::CrmListener` — handler pra 3 eventos:
  - `crm.opportunity.stage_changed` → enqueue `Holding::CrmNotifyMatrixJob`
  - `crm.activity.due_soon` → stub (só log estruturado)
  - `crm.activity.overdue` → stub (só log estruturado)

### Jobs

- `Holding::CrmNotifyMatrixJob` — HTTP POST pra Matrix API (egress externo).
- `Holding::Crm::ActivityDueSoonCronJob` — Sidekiq cron 1×/h (vê activities open com due_at ≤ now+24h).
- `Holding::Crm::ActivityOverdueCronJob` — Sidekiq cron 1×/d (vê activities open com due_at < now).
- Ambos crons herdam de `Holding::Crm::ActivityCronJobBase`.

### Models (5)

`Holding::Crm::Pipeline`, `Holding::Crm::Stage`, `Holding::Crm::Company`, `Holding::Crm::Opportunity`, `Holding::Crm::Activity` — todos com `account_id` NOT NULL + FK + validations.

### Concern

- `HoldingCrmConcern` — `before_action :ensure_feature_enabled` em todos os 6 controllers.

## Auth + autorização

- **Concern gate (feature flag por conta):** `HoldingCrmConcern#ensure_feature_enabled` retorna 403 com `errors.crm.feature_disabled` se `Current.account.holding_crm_enabled?` for `false`. Roda ANTES de qualquer ação. Default `false` — accounts precisam ser ativadas explicitamente (`Account#update!(holding_crm_enabled: true)`).
- **Pundit:** 5 controllers usam `authorize` (Pipelines/Stages/Companies/Opportunities/Activities). CrmReportsController NÃO usa Pundit (read-only, qualquer membro do account pode ver). Avaliar se quer Pundit também ali pra granularidade (ex: esconder agent_performance de outros agents).
- **Tenancy scope:** TODA query passa por `account_id: Current.account.id` explícito. Pontos verificados:
  - `CrmPipelinesController#pipelines_scope` — `Holding::Crm::Pipeline.where(account_id: Current.account.id)`
  - `CrmStagesController#fetch_pipeline` — `Holding::Crm::Pipeline.where(account_id: Current.account.id).find(...)` (stages nested via @pipeline.stages)
  - `CrmCompaniesController#companies_scope` — `Holding::Crm::Company.where(account_id: Current.account.id)`
  - `CrmOpportunitiesController#opportunities_scope` — `Holding::Crm::Opportunity.where(account_id: Current.account.id)`
  - `CrmActivitiesController#fetch_opportunity` — `Holding::Crm::Opportunity.where(account_id: Current.account.id).find(...)`
  - `CrmReportsController#opportunities_scope` + `#find_pipeline` — ambos usam `where(account_id: Current.account.id)`
  - Move-to-stage destination: `CrmOpportunitiesController#move_to_stage` filtra `Holding::Crm::Stage.where(account_id: Current.account.id).find_by(id: params[:stage_id])` — bloqueia mover opp pra stage de outra conta.
- **Sem cross-tenancy leak** — cada controller tem spec request que confirma 404 quando record pertence a outro account (`spec/controllers/api/v1/accounts/crm_*_controller_spec.rb`).

## Inputs sanitizados / strong params

| Controller | Permit list | Notas de segurança |
|---|---|---|
| Pipelines | `:name, :description, :default_pipeline, :position` | `account_id`/`id`/timestamps dropped — bloqueado mass-assignment cross-tenant. |
| Stages | `:name, :position, :color, :won, :lost, matrix_task_template: %i[enabled board_id title_template description_template priority]` | `matrix_task_template` é hash com whitelist EXPLÍCITA de chaves (não hash aberto) — bloqueia 10MB jsonb arbitrário e typos em chave inválida. |
| Companies | `:name, :domain, :industry, :size, additional_attributes: {}` | `additional_attributes` é hash ABERTO (by-design — saco de atributos custom por vila). Bloat mitigado por validação de model `ADDITIONAL_ATTRIBUTES_MAX_BYTES` (16KB cap). |
| Opportunities | `:name, :description, :value, :currency, :expected_close_date, :probability, :source, :lost_reason, :crm_pipeline_id, :crm_stage_id, :crm_company_id, :contact_id, :assignee_id, custom_attributes: {}` | `:status` REMOVIDO intencionalmente — mudança via `#move_to_stage` apenas (evita inconsistência opp.status=won / stage.won=false). `account_id`/`id`/timestamps/won_at/lost_at/discarded_at dropped. |
| Activities | `:subject, :description, :kind, :due_at, :assignee_id` | `account_id`/`crm_opportunity_id` derivados do scope. `completed_at` e `matrix_task_id` ficam fora (fluxo via `#complete` action / listener Matrix). |

- **Value** é `Decimal` (precision 15, scale 2) — Rails type-coerciona, bloqueia injection via string esquisita.
- **Description / subject / notes** são text livre — RENDERIZADOS via `{{ }}` (Vue auto-escapes HTML) ou `v-text` no frontend, NUNCA `v-html`. Verificar (Sergio): grep `v-html` em `app/javascript/dashboard/routes/dashboard/crm/`.
- **`assignee_id` / `contact_id`** são scalar FKs sem validação de "user pertence ao account" no nível do model — vetor: client pode setar `assignee_id` pra User de outro account. Mitigação implícita: Pundit + UI só lista members próprios. Sergio decidir se vale validar explicitamente.
- **`crm_stage_id` em opportunity_params** poderia receber stage de outra account no `create` — mitigado pela FK `on_delete: restrict` + tenancy do model? Verificar. (Anchor: opp pertence a account X mas client manda stage_id de account Y → pode passar a validação básica. Adicionar `validates :crm_stage_id, presence: true, in_account: true` seria explícito.)

## Logs sensíveis

Auditados em `app/listeners/holding/crm_listener.rb` + `app/jobs/holding/crm_notify_matrix_job.rb` + `app/jobs/holding/crm/*.rb`:

- **Todos os logs em forma HASH (key-value)**, NUNCA string interpolada. `event:` key sempre presente pra grep.
- **PII confirmada FORA dos logs:** nenhum log inclui `value`, `description`, `email`, `phone`, `full_name`, ou attributos JSONB raw.
- **IDs em log (não-PII):** `opportunity_id`, `account_id`, `user_id`/`assignee_id`, `stage_id`, `matrix_task_id`, `due_at` (timestamp). Todos internos, sem PII direta.
- **Erros (discard_on FATAL_ERRORS):** logam `error_class` + `error.message` + `args: job.arguments` — args inclui `opportunity_id` e `stage_id`, ambos IDs. Não vaza payload.

## Matrix integration (egress externo)

- Cliente em `Holding::Crm::MatrixApiClient` (lib externa do fork).
- Payload enviado pra Matrix API:
  ```
  { title, description, priority, type: 'on-demand', requires_review: false }
  ```
  onde `title`/`description` vêm de Liquid render com contexto:
  ```
  { opportunity: { id, name, value, currency }, stage: { id, name } }
  ```
  → **`opportunity.name` e `opportunity.value` SÃO enviados pro Matrix** via template render. Avaliar com Sergio: Matrix conta como "exterior" do ponto de vista de PII? (`name` pode conter nome de pessoa ou empresa — borderline PII.)
- ENV vars: `MATRIX_API_TOKEN` (Vaultwarden), `MATRIX_API_URL` (opcional), `MATRIX_AGENT_NAME` (opcional). Sem token → ClientError → discard fatal (não vaza por timeout silencioso).
- Token rotacionável via Vaultwarden — sem fluxo automatizado documentado; Sergio confirmar política.

## Audit trail

- `crm_opportunities` tem `created_at`, `updated_at`, `won_at`, `lost_at` — sem history table de mudanças de stage ou edits de valor/probabilidade.
- **Sugestão pro Sergio:** adicionar `papertrail` em `Holding::Crm::Opportunity` (mín.) + `Holding::Crm::Activity#completed_at`. Out of scope Phase 0-5; flagged como follow-up.

## Pontos pra Sergio decidir

1. **CrmReportsController sem Pundit** — OK (read-only dentro do account) ou adicionar policy?
2. **Activity / Opportunity history tracking** (mudanças de stage, edits) — fora de escopo Phase 0-5, mas Sergio pode flagar como pré-requisito de compliance.
3. **Rate limiting** nos endpoints CRM — existe globalmente no chatwoot via `Rack::Attack`? Verificar `config/initializers/rack_attack.rb`. Endpoints CRM não adicionaram throttling próprio.
4. **Matrix integration**: política de rotação do `MATRIX_API_TOKEN`. Quando expirar, jobs entram em ClientError discard-loop — alguém precisa monitorar Sidekiq dead set.
5. **Backup das tabelas crm_***: confirmado coberto pelo backup global do Postgres do chatwoot? `crm_opportunities` pode crescer rápido — verificar retention.
6. **Validação de `assignee_id` / `crm_stage_id` cross-account** — adicionar custom validator `:in_account` em Opportunity e Activity?
7. **`opportunity.name` enviado pra Matrix API** — borderline PII se cliente colocar nome de pessoa. Aceitar ou redact?
8. **`additional_attributes` (companies) e `custom_attributes` (opportunities)** — JSONB aberto, only validation é cap 16KB. Sem schema enforcement. Vetor pra storing PII oculta. Recomendação: log de auditoria periódico das keys em uso.

## Riscos não-mitigados (conscientes)

- **DoS via opportunity flood** (POST sem rate limit) — herda do chatwoot global rack_attack se configurado.
- **Vazamento de stage_changed via Matrix** se config token errar — `discard_on FATAL_ERRORS` cobre 4xx (não retry), 5xx retry com backoff exponencial (5 attempts). Após 5 retries, dead set.
- **`include_discarded=true`** em opportunities#index é aceito pra qualquer caller autorizado — soft-deleted opps ficam visíveis. Sem audit log de quem leu discarded. Aceitável (UI restringe acesso) mas Sergio pode flagar.
- **Liquid template** em `Stage#matrix_task_template['title_template']` é Liquid::Template.parse → render — Liquid é sandbox-safe by design (sem acesso a Ruby), risco é template malformado → ClientError → discard. OK.
