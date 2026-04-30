# brain/ — fonte única de verdade técnica do fork abckxopen/chatwoot

Esta pasta carrega tudo que é específico desta codebase e é durável: stack, decisões de arquitetura, runbooks, integração com a holding. Scoped ao **fork** (não vai pro upstream chatwoot/chatwoot — fica isolado em path próprio justamente pra evitar conflito em rebase do upstream).

Ao trabalhar nesse repo, sempre ler `context.md` aqui ANTES de mexer em código.

## Índice

- `context.md` — overview do projeto: stack, environments, dev workflow, integração com os 7 sistemas da holding.
- `fork-policy.md` — política de fork: lazy cherry-pick (não rebase), zero monkey-patch em código de domínio, módulo interno em arquivos novos. Decisão Founder 2026-04-30.
- `crm-research.md` — pesquisa de precedentes externos: Woofed CRM, KanbanWoot, LeadSquared PR #11284, Tegrus blog Dashboard App.
- `crm-codebase-patterns.md` — padrões internos do Chatwoot pra módulo novo: multi-tenancy comportamental, FlagShihTzu, event dispatcher, JBuilder, Vuex pattern.
- `crm-pipeline-spec.md` — spec consolidada do CRM (caminho A interno): modelo de dados, ~30 endpoints REST, fasing 5-8 semanas, integração Matrix one-way v1.

## Convenção

- Tudo aqui é **técnico e durável**. Não é diário de sessão.
- Se uma decisão é "sempre faremos assim nesse projeto", entra aqui.
- Se é "quem é a Denise nesse projeto / status no radar dela", vai pro `denise/projects/abckxopen/chatwoot/`.
