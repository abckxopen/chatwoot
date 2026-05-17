# CRM Pipeline — Deploy runbook

> Procedimento operacional pra subir / atualizar / rollback do módulo CRM
> em prod (chat.abckx.com.br). Companion de `brain/cluster-deploy.md`
> (runbook genérico de cluster). Específico do módulo CRM.
>
> Atualizado: 2026-05-17 (fechamento Phase 5).

## Pré-deploy checks

1. **Migrations pendentes?** No servidor alvo:
   ```bash
   bundle exec rake db:migrate:status | grep -i crm
   ```
   Confirma que todas as 7 migrations da Phase 0/5 estão `up`:
   - `20260430045000_create_crm_pipelines`
   - `20260430045001_create_crm_stages`
   - `20260430045002_create_crm_companies`
   - `20260430045003_create_crm_opportunities`
   - `20260430045004_create_crm_activities`
   - `20260501154529_add_holding_crm_enabled_to_accounts`
   - `20260517173731_add_reports_indexes_to_crm_opportunities`

2. **Feature flag default OFF.** Accounts precisam ser ativadas explicitamente:
   ```ruby
   # rails console em prod
   Account.where(holding_crm_enabled: true).count
   Account.where(holding_crm_enabled: true).pluck(:id, :name)
   ```

3. **Sidekiq cron entries presentes?** Conferir `config/schedule.yml` em produção (deve ter `crm_activity_due_soon_cron_job` e `crm_activity_overdue_cron_job`). Em runtime:
   ```bash
   # Se usando sidekiq-cron, no console:
   Sidekiq::Cron::Job.all.map(&:name).grep(/crm/)
   ```

4. **ENV vars necessárias** (todos via Vaultwarden ou Secrets do k8s):
   - `MATRIX_API_TOKEN` — token de API da Matrix. **Obrigatório** pro CrmNotifyMatrixJob funcionar. Sem ele, jobs caem em discard fatal silencioso (após log).
   - `MATRIX_API_URL` — opcional, default no client (`Holding::Crm::MatrixApiClient`).
   - `MATRIX_AGENT_NAME` — opcional, identifica o agent na Matrix.

5. **PVC / storage** — sem mudança de schema de storage. CRM não adiciona arquivos.

## Sequência de deploy (tag push)

Padrão atual (validado em chatwoot v0.2.1 deploy em 2026-04-30):

1. Criar a tag em branch isolado (pre-push hook bloqueia push direto em develop):
   ```bash
   # detach pra evitar pre-push hook em develop
   git checkout --detach
   git tag -a vX.Y.Z -m "chore(crm): phase 5 — hardening"
   git push origin refs/tags/vX.Y.Z
   git checkout develop
   ```

2. CI/CD do chatwoot fork detecta tag → workflow `holding-build-and-publish.yml`:
   - Build Docker image (CE)
   - Push pra `ghcr.io/abckxopen/chatwoot:vX.Y.Z`
   - SSH no manager-01 → `kubectl set image` + rollout no namespace `chatwoot`

3. **Migration roda automaticamente no rollout** (chatwoot init pattern). Acompanhar logs:
   ```bash
   kubectl -n chatwoot logs -l app=chatwoot,role=migrate --tail=100 -f
   ```

4. Verificar Sidekiq pra confirmar cron jobs re-registrados:
   ```bash
   kubectl -n chatwoot exec deploy/chatwoot-sidekiq -- bundle exec rails runner \
     'puts Sidekiq::Cron::Job.all.map(&:name).grep(/crm/)'
   ```
   Esperado: `crm_activity_due_soon_cron_job`, `crm_activity_overdue_cron_job`.

## Smoke test pós-deploy

Account de teste com `holding_crm_enabled: true` (ID conhecido — staging account ou conta interna).

1. **Login** como admin numa conta com `holding_crm_enabled=true`.
2. **Navegar** `/app/accounts/X/crm` — deve renderizar `CrmHome` com lista de pipelines (mesmo vazia, sem erro).
3. **Criar pipeline + stages + opportunity via API**:
   ```bash
   # auth_token = api_access_token do user admin
   curl -X POST https://chat.abckx.com.br/api/v1/accounts/X/crm_pipelines \
     -H "api_access_token: $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"crm_pipeline": {"name": "Smoke Pipeline"}}'
   # → 201 com {id, name, stages:[]}
   ```
4. **Navegar** `/app/accounts/X/crm/pipelines/<id>/kanban` — board deve renderizar (mesmo sem stages, sem erro de Vuex).
5. **Drag opp** entre stages — persistência via `PATCH /move_to_stage`. Conferir no devtools: optimistic commit primeiro, depois 200 do server.
6. **Navegar** `/app/accounts/X/crm/companies` — deve listar (mesmo vazio).
7. **Navegar** `/app/accounts/X/crm/reports?pipeline_id=<id>` — 3 cards (pipeline_summary, agent_performance, forecast) devem carregar sem erro.
8. **Conferir Sidekiq** — sem ERROR levels nos crons:
   ```bash
   kubectl -n chatwoot logs -l app=chatwoot,role=sidekiq --tail=200 | grep -i 'crm\|error'
   ```

## Rollback path

### Cenário 1: bug em frontend Vue (backend / DB intactos)
Tag anterior continua em GHCR. Rollback rápido:
```bash
kubectl -n chatwoot rollout undo deployment/chatwoot-web
kubectl -n chatwoot rollout undo deployment/chatwoot-sidekiq  # se sidekiq pacote junto
```
Migrations CRM permanecem (não-destrutivas). Frontend volta pra última imagem boa.

### Cenário 2: bug em backend (controller / job / listener)
1. `kubectl rollout undo` (mesmo do Cenário 1) reverte image.
2. **Se migration recém-rodada quebrou algo:**
   ```bash
   kubectl -n chatwoot exec deploy/chatwoot-web -- bundle exec rake db:rollback STEP=N
   ```
   onde `N = número de migrations da release`. **CUIDADO:** reversal é destrutivo se a migration removeu coluna NOT NULL — abrir o `def change` antes de rodar.
   - Migrations CRM 0-4 (create_table) → drop_table reversal OK em ambiente sem dados, perde dados em prod. Evitar rollback de create_table em prod com dados.
   - Migration 5 (add_holding_crm_enabled) → remove coluna boolean, perde estado de quem tinha CRM ativo.
   - Migration 6 (Phase 5 indexes) → reversal segura (drop_index), sem perda de dado.

### Cenário 3: feature flag escape (usuários vendo CRM por engano)
Desligar global imediato sem deploy:
```ruby
# rails console
Account.update_all(holding_crm_enabled: false)
```
Re-ativar caso por caso depois (`Account.find(X).update!(holding_crm_enabled: true)`).

### Cenário 4: CrmNotifyMatrixJob entopindo dead set
Matrix API down ou token expirado → jobs vão pra retry, eventualmente dead.
```bash
# console
Sidekiq::DeadSet.new.scan('CrmNotifyMatrixJob').size
# investigar
Sidekiq::DeadSet.new.scan('CrmNotifyMatrixJob').first.args
# após fix do token, requeue:
Sidekiq::DeadSet.new.scan('CrmNotifyMatrixJob').each(&:retry)
```

## Conhecidos pré-existentes (não bloqueia)

- **`lint-staged@17.0.5` package missing** em dev environments sem `pnpm install` completo — husky hook falha silenciosamente, commits passam mesmo assim. **Não afeta CI** (que instala deps). Ver `brain/known-issues/`.
- **Mautic + Chatwoot HTTP integration NÃO foi testada com CRM ativo.** Smoke test não cobre interação entre módulos. Out of scope Phase 5.
- **Rebase upstream pendente** — fork está N commits atrás de `develop` do upstream. Rebase periódico é responsabilidade separada (ver `brain/fork-policy.md`).

## Observabilidade

Tags de log pra grep rápido:
```
event:crm.opportunity.stage_changed.queued_matrix_notify
event:crm.matrix.notify.success
event:crm.matrix.notify.skip                # reason: idempotent | template_disabled | not_found
event:crm.matrix.notify.fatal_discarded     # token problem
event:crm.activity.due_soon.cron.start
event:crm.activity.due_soon.cron.complete
event:crm.activity.due_soon.dispatched
event:crm.activity.overdue.cron.start
event:crm.activity.overdue.cron.complete
event:crm.activity.overdue.dispatched
```

Querying típico (Loki/grafana ou kubectl logs com jq):
```bash
kubectl -n chatwoot logs -l app=chatwoot --tail=10000 | grep 'event:crm.matrix.notify'
```
