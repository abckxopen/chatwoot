# Política de fork — abckxopen/chatwoot

> Decisão durável Founder, 2026-04-30 03:17 UTC (Telegram msg 273):
> *"não mexe no upstream, vamos continuar conectados e pegando atualizacoes importantes tipo cherry-pick. mas não precisa mexer no core. a ideia é ser um modulo interno por isso o fork."*

## Modelo: lazy cherry-pick + módulo interno isolado

Inspirado na política do `abckxtech/matrix` (memória Denise `project_matrix_fork_policy.md`: "fork frozen sem upstream permanente; lazy cherry-pick sob demanda").

### Princípios

1. **Não rebasear regular do upstream `chatwoot/chatwoot:develop`.** Fork fica em deriva controlada.
2. **Cherry-pick sob demanda** quando uma feature/fix do upstream é importante (security patch, bug crítico, feature útil).
3. **Zero monkey-patch em código de domínio do core** (models de domínio, services, listeners, controllers existentes upstream). Usar `prepend_mod_with` em initializer isolado se inevitável.
4. **Toda funcionalidade da holding em arquivos NOVOS** sob namespaces nossos (`app/models/crm/`, `app/controllers/api/v1/accounts/crm_*_controller.rb`, `app/javascript/dashboard/store/modules/crm/`, etc.).
5. **Arquivos de configuração** são área cinzenta — discussão case-by-case (ver seção abaixo).

### O que conta como "core" / "upstream" intocável

- `app/models/<resource>.rb` (Conversation, Contact, Account, Inbox, Team, User…)
- `app/services/...` (todos os services upstream)
- `app/controllers/...` (todos exceto `crm_*` que vamos criar)
- `app/listeners/...` (não estender `WebhookListener`, `ActionCableListener`, etc. diretamente — criar `CrmListener` próprio)
- `app/jobs/...` (não estender existentes — criar `Crm*Job` próprios)
- `app/javascript/dashboard/...` (exceto `crm/` namespace nosso)
- `lib/...` (área cinzenta — ver abaixo)
- `db/migrate/...` (migrations existentes — só adicionamos novas, prefixo `crm_*`)
- `db/schema.rb` — atualizado automaticamente pelas nossas migrations, é OK.
- `Gemfile` / `Gemfile.lock` — área cinzenta (precisamos adicionar gems? minimizar).

### Arquivos de configuração — área cinzenta

A regra dura é "não mexer no core". Mas alguns arquivos de config precisam de adições pra módulo novo plugar. Política proposta:

| Arquivo | Política | Justificativa |
|---------|----------|---------------|
| `config/routes.rb` | **ADIÇÃO permitida** em bloco isolado claramente marcado (`# >>> HOLDING CRM ROUTES <<<` / `# <<< HOLDING CRM ROUTES >>>`) | Conflito de cherry-pick é raro, fácil resolver |
| `config/features.yml` | **ADIÇÃO permitida** ao final do array | YAML lista, append não conflita |
| `lib/events/types.rb` | Preferir **arquivo separado** `lib/holding/crm/events.rb` registrando consts via `Object.const_set` ou módulo concat | Adicionar constantes mid-file gera conflito |
| `config/initializers/event_handlers.rb` | Preferir **novo initializer** `config/initializers/holding_crm.rb` que carrega nosso listener | Evita patchar inicializador upstream |
| `config/initializers/devise.rb` etc | **NÃO mexer** — usar initializer próprio | Devise / Rails core, conflito alto |
| `package.json` | Área cinzenta — adicionar dep nova causa conflito em `package-lock.json`/`pnpm-lock.yaml`. Confirmar com Founder antes | Lock file diff em cherry-pick é doloroso |
| `Gemfile` | Idem — precisamos? Justificar cada dep nova | Lock file diff |

**Regra de ouro:** **se a edição de um arquivo upstream pode ser "ADIÇÃO de um bloco no final" (não edit no meio), aceitável. Senão, criar arquivo novo e registrar via mecanismo Rails (initializer, autoload).**

**Quando dúvida → criar arquivo novo > editar upstream.**

### Cherry-pick: como decidir o que trazer

Critérios pra cherry-pick um commit do upstream:
1. **Security/CVE patch** → automático, prioridade.
2. **Fix de bug que nos afeta diretamente** → cherry-pick.
3. **Feature nova grande do upstream** → analisar; pode ser que a gente queira ou não.
4. **Refactor cosmético do upstream** → ignorar.
5. **Mudança no API que quebraria nosso CRM** → cherry-pick + ajustar nosso CRM.

Cadência: revisar upstream `chatwoot/chatwoot:develop` 1× por mês (ou disparado por security advisory).

```bash
# Workflow de cherry-pick
cd ~/abckxopen/chatwoot
git remote add upstream https://github.com/chatwoot/chatwoot.git  # 1× só
git fetch upstream
git log --oneline origin/develop..upstream/develop | head -50    # ver o que tem novo
git cherry-pick <sha>                                             # selecionar
# se conflito em arquivo nosso (crm_*), resolver manualmente
# se conflito em config/routes.rb, esperado — resolver mantendo nosso bloco
git push origin develop
```

### Migrations: estratégia anti-conflito

- Toda migration nossa começa com data Brasil ANO+MES+DIA+HHMM (ex: `20260430_001_create_crm_pipelines.rb`).
- Isso garante que migrations upstream com timestamps anteriores rodam primeiro, e nossas rodam depois.
- Se upstream e a gente criar migrations no MESMO dia, manualmente garantir que timestamp da nossa é > timestamp da deles (pode editar arquivo).

### Branch strategy

- `develop` (default) — espelha upstream + nossa derivação.
- `holding/crm-phase-0` (ou similar) — branch de feature pra cada fase do CRM.
- Merge pra `develop` por PR (mesmo sem push remoto rodando localmente, abrir PR no fork).

### Anti-padrões (NÃO fazer)

1. ❌ Hard fork modificando arquivos core. Caminho do `xiribitarp/chatwoot-kanban` — dor de rebase, ninguém mantém.
2. ❌ `git rebase upstream/develop` regular (perde histórico nosso, gera conflito massivo cada vez).
3. ❌ Adicionar código da holding mid-file em arquivos upstream (`app/models/conversation.rb`, etc.) — conflito garantido.
4. ❌ Renomear arquivos upstream — conflito garantido.

## TL;DR pra implementação

- Tudo que é da holding **em arquivos novos** sob namespaces próprios (`crm/`, `holding/`).
- Mexer em arquivo upstream **só** se for **ADIÇÃO isolada e identificável** (com marcador), e justificável caso a caso.
- Atualizar do upstream é **cherry-pick lazy**, não rebase regular.
