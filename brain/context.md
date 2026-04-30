# Chatwoot fork (abckxopen/chatwoot) — contexto técnico

## Origem

Fork de `chatwoot/chatwoot` (default branch upstream e local: `develop`). Fork ainda **sincronizado** com upstream — sem patches locais ainda no momento desse documento (commit base: `cd9c8e3 fix: skip self-mention notification in private notes`).

## Stack

| Camada | Tech | Versão |
|--------|------|--------|
| Runtime | Ruby | 3.4.4 (`.ruby-version`) |
| Web framework | Rails | ~> 7.1 |
| Frontend | Vue 3 + Vite | (ver package.json) |
| Storefront SDK | `vite build --mode library` | `npm run build:sdk` |
| DB | PostgreSQL | (configurado em docker-compose) |
| Cache/Queue | Redis | (Sidekiq pra background jobs) |
| Node | | 24.13.0 (`.nvmrc`) |
| App version | | 4.13.0 (package.json) |
| Process manager dev | foreman ou overmind | `Procfile.dev` |
| Linting Ruby | rubocop | `.rubocop.yml` |
| Linting JS | eslint | `.eslintrc.js` |
| Test framework JS | vitest | `npm test` |
| Test framework Ruby | RSpec | `.rspec` |
| Container build | Docker | `docker/Dockerfile` |
| Component story | histoire | `npm run story:dev` |

## Layout (paths que importam)

```
app/
  javascript/        ← Vue 3 frontend (dashboard, widget, SDK)
  controllers/       ← Rails controllers (REST API + ActionCable)
  models/
  services/          ← onde mora a lógica de domínio
  jobs/              ← Sidekiq jobs
  channels/          ← canais (WhatsApp, FB, Email, Web Widget...)
  listeners/         ← event listeners (pub/sub interno)
config/
docker/
docker-compose.yaml          ← dev local
docker-compose.production.yaml ← produção
.env.example                  ← 10KB de env vars (ler com calma antes de subir)
AGENTS.md (= CLAUDE.md)       ← convenções do upstream pra agentes — LER PRIMEIRO
brain/                        ← este diretório
```

## Onde isolar customizações da holding

Para minimizar conflito em rebase do upstream, **preferir** estes paths quando criar custom:

- **Frontend customizations:** `app/javascript/dashboard/customizations/` (já existe upstream pra esse fim — confirmar antes de criar) ou criar plugin Vue isolado.
- **Backend services novos:** `app/services/holding/` (criar namespace nosso) — isola de upstream `app/services/`.
- **Novos canais/integrações:** `app/services/<channel>/` em namespace específico.
- **Migrations da holding:** `db/migrate/` numbered com data Brasil (não conflita por nome porque schema_migrations é numérico).
- **Branding (logo, cores):** override via assets em `public/brand/` + ENV (verificar se Chatwoot já suporta — `BRAND_NAME`, `BRAND_URL`, `LOGO_THUMBNAIL` existem no `.env.example`).

**Evitar editar:** controllers/models/services upstream sem necessidade real. Se precisar, fazer monkey-patch em `config/initializers/holding_overrides.rb` ao invés de editar o arquivo upstream.

## Comandos dev essenciais

```bash
# install
bundle install
pnpm install   # ou npm install

# dev (escolhe um)
npm run start:dev   # foreman -f Procfile.dev
npm run dev         # overmind -f Procfile.dev (preferido se tiver overmind)

# tests
npm test                           # JS (vitest)
bundle exec rspec                  # Ruby
bundle exec rspec spec/<path>      # arquivo específico

# lint/format
npm run eslint:fix
bundle exec rubocop -a             # auto-fix Ruby

# build produção
npm run build       # frontend
npm run build:sdk   # widget SDK pra embutir em sites externos

# story
npm run story:dev
```

## Integração com os 7 sistemas da holding

| Sistema | Como Chatwoot conecta |
|---------|------------------------|
| **Vaultwarden** | Credenciais (DB url, secret_key_base, smtp creds, redis, channel API tokens) — não commitar em `.env`. Bootstrap `source ~/.env.vault && bw unlock`. |
| **Stalwart** | SMTP server pra outbound de notificações Chatwoot. Configurar `SMTP_*` env vars apontando pra Stalwart self-hosted. |
| **Mautic** | _(a integrar)_: webhook Chatwoot → Mautic pra sync de contatos/conversas em campanhas. |
| **Chatwoot ele mesmo** | É este sistema. Atendimento + WhatsApp + canais. |
| **Zulip** | Notificações de eventos Chatwoot (nova conversa, SLA breach) via webhook → bot Zulip em `#DESENV TEAM` ou canal dedicado. |
| **Matrix** | _(a definir)_: tasks operacionais (ex: "dev de plantão revisa fila") podem ser criadas via webhook Chatwoot → Matrix API. |
| **GitHub** | Repo `abckxopen/chatwoot` (este). Tickets de bug do Chatwoot da holding em `abckxtech/tickets` com label `kingdom:development` se afetar dev. |

## Política de fork (a expandir em `fork-policy.md` na primeira decisão durável)

- Rebasear do upstream `chatwoot/chatwoot:develop` regularmente (cadência a definir — semanal sugerido).
- Patches da holding ficam em commits identificados (`feat(holding): ...`, `fix(holding): ...`).
- Mudanças que sirvam pro upstream → considerar PR pro chatwoot/chatwoot ao invés de manter no fork.
- `brain/` neste fork **não** vai pro upstream (path único nosso).

## Padrões não-negociáveis (denise standards POLICY)

- Zero hardcode de credentials.
- Zero `console.log` em produção.
- TypeScript tipado (zero `any`) — Chatwoot frontend é JS+Vue, não TS, então essa regra se aplica a código novo se introduzirmos TS.
- Code review por Sergio (security) antes de qualquer deploy de patch novo.
- Anchor comments em decisões críticas (ex: por que monkey-patchamos um controller upstream).

## Acessos a confirmar (antes de mexer em ambiente real)

- [ ] Token GitHub com permissão de push em `abckxopen/chatwoot`.
- [ ] Credenciais Postgres/Redis do Chatwoot da holding (Vaultwarden coleção `Infra`).
- [ ] Acesso ao painel Cloudflare/DNS se for tocar domínio do Chatwoot (`chat.<algo>.abckx.com.br`?).
- [ ] Acesso SSH ao servidor onde Chatwoot roda (se for hot-fix em produção).

Se faltar qualquer um → Matrix task pro CTO antes de bloquear.
