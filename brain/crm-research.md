# CRM em Chatwoot — pesquisa de precedentes (2026-04-30)

> Captura da pesquisa antes de spec. Não é spec — é o que **outros tentaram** e como o ecossistema reage.

## TL;DR

- **Ninguém implementou pipeline/deals first-class dentro do core Chatwoot e sobreviveu sem fork doloroso.** Todo projeto vivo virou sidecar (Woofed) ou Dashboard App (Tegrus).
- Padrão upstream **preferido**, em ordem decrescente de aceitação:
  1. **Dashboard App** (iframe externo) — endossado em blog oficial Chatwoot.
  2. **Hook listener + Sidekiq job + processor** (PR #11284 LeadSquared, mergeado por scmmishra/CTO Chatwoot).
  3. **Sidecar separado consumindo API + webhooks** (Woofed, KanbanWoot).
  4. **Módulo `enterprise/` com `prepend_mod_with`** — caminho oficial pra feature grande sem quebrar merge upstream.
  5. **Hard fork modificando core** — caminho do `xiribitarp/chatwoot-kanban`. Ninguém recomenda. Dor de rebase.

## Issues / discussões upstream

- [#2271 events to contacts (CRM)](https://github.com/chatwoot/chatwoot/issues/2271) — fechada sem implementação. Time empurra pra `custom_attributes` + dashboard apps.
- [#7528 Kanban-style Conversation Manager](https://github.com/chatwoot/chatwoot/issues/7528) — open desde 2023-07. Sem resposta de mantenedor.
- [discussion #12784 Kanban view 2025-11](https://github.com/orgs/chatwoot/discussions/12784) — open, 7 reações, zero resposta core. Confirma: não está no roadmap.
- [#1197 HubSpot integration 2020-09](https://github.com/chatwoot/chatwoot/issues/1197) — open há 4+ anos. Label "needs clear product spec". Time prefere PRs externos a roadmap interno de CRM.

**Sinal claro:** o time core não pretende absorver "CRM" como módulo nativo.

## PR de referência: LeadSquared (mergeado)

[PR #11284 — feat: integrate LeadSquared CRM](https://github.com/chatwoot/chatwoot/pull/11284), por scmmishra (CTO Chatwoot), mergeado 2025-04-29.

Padrão usado no PR (= template aceito pelo upstream pra lógica de CRM):
- `app/listeners/hook_listener.rb` captura eventos do domínio
- `HookJob` (Sidekiq) processa async
- Processor service + API client + mappers
- Sync **one-way Chatwoot → CRM externo**
- Autor declara: *"meant to serve as a base for adding other CRM platforms (HubSpot, Zoho, Attio)"*
- Reviewer flagou que `HookJob` está virando god-class — débito que escalaria com mais integrações.

## Precedentes externos relevantes

### Woofed CRM (mais maduro)

[douglara/woofed-crm](https://github.com/douglara/woofed-crm)
- Rails standalone (não fork), ~140 stars, 766 commits, ativo.
- Tem deals, pipelines, stages, automation.
- **Pluga no Chatwoot via API**, não embute.
- **Mesmo stack** (Rails + Postgres + Redis), MIT.
- Maior precedente da ideia "CRM open-source que conversa com Chatwoot".

### KanbanWoot (prova de conceito kanban-via-attrs)

[pucabala/kanbanwoot](https://github.com/pucabala/kanbanwoot)
- React + Tailwind sidecar, dormente (4 commits, beta v0.1.0 2025-05).
- Lê `custom_attributes` do tipo dropdown como colunas.
- Útil como prova-de-conceito do padrão "kanban via custom_attributes".

### Hard forks (anti-padrão)

[xiribitarp/chatwoot-kanban](https://github.com/xiribitarp/chatwoot-kanban) — fork de fork, 416 commits no develop. Modificações Kanban embutidas. Caminho doloroso de manter sincronizado com upstream. **Não seguir.**

## Endorsement oficial: Dashboard Apps

[Tegrus case — How Tegrus uses Dashboard Apps to triple sales](https://www.chatwoot.com/blog/sales-processes-with-dashboard-apps/)

Tegrus **não forka**, construiu *Tfy* (CRM próprio) como Dashboard App: iframe embutido em URL externa, postMessage pra receber contexto (contact/conversation/agent atual).

Chatwoot afirma na peça: *"Dashboard Apps is one of our most versatile features... common ways customers use them include CRMs, orders library, payment history."*

**É o endorsement oficial do padrão sidecar/iframe pra CRM.**

Limitação: Dashboard App tem postMessage one-way (recebe contexto), não permite mutação direta da UI Chatwoot. Se quisermos drag-and-drop entre kanban-de-deals e conversation-list nativa, Dashboard App não basta — aí precisa de Vue components no `enterprise/`.

## Docs upstream sobre extensibilidade

- [developers.chatwoot.com/introduction](https://developers.chatwoot.com/introduction) — APIs (Application/Platform/Client) + webhooks. **Não fala em "módulos novos de domínio".**
- [Developing Enterprise Edition Features handbook](https://www.chatwoot.com/hc/handbook/articles/developing-enterprise-edition-features-38) — caminho oficial pra adicionar funcionalidade "fechada":
  - Pasta top-level `enterprise/` espelhando estrutura CE
  - Namespace `Enterprise::` com `prepend_mod_with` injetando overrides em classes Community
  - CI strip-da-pasta-enterprise + teste em CE garante que upstream não quebra
  - Specs em `spec/enterprise/`
  - Helpers `ChatwootApp.enterprise?` / `isEnterprise()` pra render condicional

## Armadilhas confirmadas (= regras pro nosso CRM)

1. **Rebase upstream:** Chatwoot release ~mensal, mexe em `app/listeners`, `app/models/conversation.rb`, `app/javascript/dashboard`. Hard fork acumula conflito rápido. **→ Usar namespace `enterprise/` ou sidecar.**
2. **Schema migrations conflict:** Chatwoot reusa nomes genéricos (`notes`, `events`, `activities`, `leads` apareceu em LeadSquared PR). **→ Tabelas novas com prefixo `crm_*`** (ex: `crm_deals`, `crm_pipelines`).
3. **Multi-tenant `Account`:** todo Chatwoot é multi-tenant por `account_id`. **→ Toda tabela CRM TEM que ter `account_id` + scope `Current.account`,** senão vaza entre contas.
4. **ActionCable / `HookJob` god-class:** flagged no review do #11284. **→ Se disparar updates de pipeline pelo mesmo bus de mensagens vai serializar lento.** Considerar channel separado pra eventos CRM.
5. **Billing/license CE/EE fronteira:** JS é MIT, Ruby tem cinta CE/EE. **→ Decidir cedo:** módulo CRM é "premium" da holding (vai em `enterprise/`) ou MIT-livre (em `app/models/crm/` + decidir se a gente publica)?

## Decisões a tomar antes de spec

- [ ] **Caminho macro:** Dashboard App + módulo Rails interno (sob `enterprise/`) OU sidecar standalone (a la Woofed) consumindo API Chatwoot?
- [ ] **Avaliar Woofed como base:** clonar e adaptar pode poupar 4-6 semanas. Vale 1h de investigação técnica antes de escrever modelo do zero.
- [ ] **CE vs EE:** módulo entra em `enterprise/` (não conflita upstream) ou em `app/` core (mais simples, menos isolado)?
- [ ] **Schema prefix:** confirmar `crm_*` como convenção (recomendado).

## Fontes

- https://github.com/chatwoot/chatwoot/issues/2271
- https://github.com/chatwoot/chatwoot/issues/7528
- https://github.com/chatwoot/chatwoot/issues/1197
- https://github.com/orgs/chatwoot/discussions/12784
- https://github.com/chatwoot/chatwoot/pull/11284
- https://www.chatwoot.com/blog/sales-processes-with-dashboard-apps/
- https://www.chatwoot.com/hc/handbook/articles/developing-enterprise-edition-features-38
- https://developers.chatwoot.com/introduction
- https://github.com/douglara/woofed-crm
- https://github.com/pucabala/kanbanwoot
- https://github.com/xiribitarp/chatwoot-kanban
- https://blog.elest.io/chatwoot-webhooks-build-custom-chatbots-and-integrate-with-your-crm/
- https://www.chatwoot.com/features/integrations/
