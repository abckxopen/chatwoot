# Padrões internos do Chatwoot — pra novo módulo CRM (2026-04-30)

> Mapa concreto da codebase: onde existe o quê, qual base classe extender, qual convenção seguir. Companion do `crm-research.md` (precedentes externos).

## Multi-tenancy é COMPORTAMENTAL, não automático

- Não há `default_scope` em models — Chatwoot escora tenancy via `Current.account` (thread-local) injetado por `Api::V1::Accounts::BaseController#current_account`.
- Toda tabela de domínio: `account_id NOT NULL`, índice composto, validação `validates :account_id, presence: true`, `belongs_to :account`.
- **Implicação:** todo model `crm_*` TEM que ter `account_id` + `belongs_to :account`. Toda query de controller TEM que partir de `Current.account.crm_xxx` ou `.where(account_id: Current.account.id)`. Se faltar, vaza dado entre contas. Sem rede de proteção automática.

## Concerns reusáveis úteis

| Concern | Onde | Pra que |
|---------|------|---------|
| `Avatarable` | `app/models/concerns/` | Avatar/blob attach (útil pra Company logo) |
| `Labelable` | `app/models/concerns/` | acts-as-taggable-on (útil pra Opportunity tags) |
| `LlmFormattable` | `app/models/concerns/` | Serialização pra Captain LLM (skip for now) |

## Custom Attributes vs models próprios

- `CustomAttributeDefinition` (`app/models/custom_attribute_definition.rb`) limita a `Contact` e `Conversation`. Storage via JSONB columns (`custom_attributes`, `additional_attributes`).
- Pra **MVP** rápido sem migration: usar `Contact.custom_attributes` (`crm_deal_id`, `pipeline_stage`).
- Pra **CRM sério** (validações de transição de stage, audit trail, reports agregados sem JSONB-parse): models próprios `crm_pipelines`, `crm_stages`, `crm_opportunities`. Recomendação: models próprios.

## Feature Flags via FlagShihTzu

- `Account` inclui `Featurable` concern. `config/features.yml` tem 240+ features.
- **Já existem flags reservadas:** `crm`, `crm_v2`, `crm_integration`. Podemos adicionar `crm_pipeline` (ou reutilizar `crm` como pai e colocar nosso CRM atrás dele).
- **Uso:** `account.feature_enabled?(:crm_pipeline)`, `account.enable_features!(:crm_pipeline)`, dynamic method `account.feature_crm?`.

## Event Dispatcher (pub/sub interno)

- `Rails.configuration.dispatcher.dispatch(EVENT_NAME, Time.zone.now, key: value)` — pattern oficial.
- Tipos em `lib/events/types.rb` (constantes string `'contact.created'`, `'conversation.status_changed'`, etc.).
- Listeners em `app/listeners/`, herdam `BaseListener`. Métodos por evento (`def contact_created(event); end`).
- Inscrição automática: `config/initializers/event_handlers.rb` chama `Rails.configuration.dispatcher.load_listeners`.
- **Listeners são síncronos** — pra async, dentro do listener fazer `MeuJob.perform_later(...)`.

**Pra CRM, adicionar:**
```ruby
# lib/events/types.rb (append)
OPPORTUNITY_CREATED        = 'opportunity.created'
OPPORTUNITY_STAGE_CHANGED  = 'opportunity.stage_changed'
OPPORTUNITY_UPDATED        = 'opportunity.updated'
OPPORTUNITY_CLOSED         = 'opportunity.closed'
PIPELINE_UPDATED           = 'pipeline.updated'
```

```ruby
# app/listeners/crm_listener.rb (criar)
class CrmListener < BaseListener
  def opportunity_stage_changed(event)
    CrmNotifyMatrixJob.perform_later(event.data[:opportunity].id)
  end
end
```

## Sidekiq Jobs

- Base: `ApplicationJob < ActiveJob::Base; discard_on ActiveJob::DeserializationError`.
- Pattern simples: `MyJob.perform_later(model_or_id)`.

## API Controllers

- Base: `Api::V1::Accounts::BaseController < Api::BaseController` (inclui `EnsureCurrentAccountHelper`, antes-action `current_account`).
- Patterns:
  - `include Sift` pra sort/filter (ex: `sort_on :name, type: :string`)
  - `before_action :check_authorization` (Pundit)
  - `before_action :fetch_<resource>, only: [:show, :update]`
  - Pagination via Kaminari (page = `params[:page]`)
- Routes em `config/routes.rb` `namespace :api do; namespace :v1 do; resources :accounts do; scope module: :accounts do; resources :crm_pipelines; ...`

## Policies (Pundit)

- `app/policies/<resource>_policy.rb < ApplicationPolicy`.
- Métodos: `index?`, `show?`, `create?`, `update?`, `destroy?`.
- Acesso a `@account_user.administrator?`, `@account_user.agent?`.
- `enable_features!(:custom_roles)` = enterprise feature pra roles além de admin/agent.

## Serializers — JBuilder, não AMS

- View partials em `app/views/api/v1/accounts/<resource>/`:
  - `index.json.jbuilder` (`json.array!`)
  - `show.json.jbuilder`
  - `_<resource>.json.jbuilder` (partial)
- Convenção: `json.id`, `json.<attr>`, `json.created_at obj.created_at&.to_i` (epoch).

## Frontend Vuex Pattern

- `app/javascript/dashboard/store/modules/<module>/`:
  - `index.js` exporta `{ namespaced: true, state, actions, mutations, getters }`
  - `state` tem `meta`, `records: {}`, `uiFlags: { isFetching, isUpdating }`
  - `actions.js` async com `commit('SET_UI_FLAG', ...)` antes/depois
  - `mutations.js` constants em `types.js`

## Frontend API Client

- `app/javascript/dashboard/api/<resource>.js`:
  - `class <Resource>API extends ApiClient { constructor() { super('crm_pipelines', { accountScoped: true }); } }`
  - `accountScoped: true` injeta `/api/v1/accounts/:account_id/` automaticamente.

## Frontend Routes

- `app/javascript/dashboard/routes/dashboard/<module>/<module>.routes.js`:
```js
{
  path: frontendURL('accounts/:accountId/crm'),
  component: CrmDashboard,
  meta: { featureFlag: FEATURE_FLAGS.CRM_PIPELINE, permissions: ['agent', 'administrator'] },
  children: [...]
}
```
- Importar em `app/javascript/dashboard/routes/index.js`.

## Customizations / Fork-isolation paths já existentes

Segundo o agent que estudou a codebase:
- `app/javascript/dashboard/customizations/` — pasta upstream pra customs frontend
- ~~`app/services/holding/`~~ — não confirmado existir; criar se preciso
- ~~`config/initializers/holding_overrides.rb`~~ — não confirmado; criar se monkey-patch necessário
- `enterprise/` — caminho oficial Chatwoot pra módulos premium (ver handbook EE upstream)

## Tests

- Models: `spec/models/<resource>_spec.rb` — `it { is_expected.to validate_presence_of(:account_id) }`, `it { is_expected.to belong_to(:account) }`.
- Policies: `spec/policies/<resource>_policy_spec.rb`.
- Requests: `spec/requests/api/v1/accounts/<resource>_controller_spec.rb`.
- Frontend: `vitest`, specs em `*.spec.js` ao lado dos componentes.

## Convenção crítica de migration

- Prefixo `crm_*` em tabelas pra não colidir com upstream futuro (`notes`, `activities`, `events`, `leads` já existem ou foram usados).
- `t.references :account, null: false, foreign_key: true` em tudo.
- Índice composto `[:account_id, :name]`, `[:account_id, :status]`.
- `t.jsonb :custom_attributes, default: {}` pra extensibilidade.

## Anti-padrões a evitar

1. Editar `app/models/conversation.rb`, `app/listeners/webhook_listener.rb`, `app/services/llm/...` direto. Em vez disso: `prepend_mod_with('CrmConversationExtensions')` em initializer.
2. Reutilizar nomes genéricos de migration (`notes`, `activities`).
3. Esquecer `account_id` em qualquer tabela CRM.
4. Disparar updates em massa pelo `webhook_listener.rb` — vai serializar com tudo. Listener próprio.
5. Usar custom_attributes JSONB pra Pipeline/Stage como entidades. JSONB serve dado flexível por opp, não estrutura.

## Conclusão pra spec

Codebase é amigável a módulo novo de domínio — patterns claros, feature flags prontas (`crm` reservado), event dispatcher pronto, JBuilder pronto, Vuex pronto. **Encaixa naturalmente em `app/models/crm/` + `app/controllers/api/v1/accounts/crm_*` + `app/javascript/dashboard/store/modules/crm/`** sem precisar do `enterprise/` namespace ainda — desde que a gente assuma que o módulo é MIT-livre e não fechado da holding.

Se a decisão for "fechar" o CRM (não compartilhar com upstream nem com forks da comunidade), aí entra `enterprise/` como wrapper.
