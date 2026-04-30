# Cluster deploy — Chatwoot fork em prod

## Setup atual

- Cluster: k3s self-hosted, manager-01 + workers (worker-03 hospeda chatwoot)
- Registry: `ghcr.io/abckxopen/chatwoot` — **PRIVADO** (auth obrigatória)
- Namespace: `chatwoot`
- Domínio: https://chat.abckx.com.br
- PVC: `chatwoot-storage` (RWO, pinado em worker-03 via nodeSelector)

## Workflows

| Arquivo | Trigger | O que faz |
|---|---|---|
| `holding-build-and-publish.yml` | push em tag `v*` ou `develop` | build imagem CE + push ghcr + (em tag) deploy automático |
| `holding-fix-imagepull.yml` | manual (workflow_dispatch) | patcha SA + deploys com `ghcr-secret`. **Idempotente** — re-rodar não estraga |
| `holding-fix-progress-deadline.yml` | manual (workflow_dispatch) | sobe `progressDeadlineSeconds` dos deploys pra 1800s. Idempotente |
| `holding-cluster-diagnose.yml` | manual (workflow_dispatch) | read-only: pods/events/logs/imagePullSecrets/pull policy. Usar quando deploy falhar |

Secrets GH usados (já configurados): `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY` (chave SSH pro manager-01 do k3s).

## Bug histórico — imagePullSecrets faltando (2026-04-30)

### Sintoma
`v0.2.1` falhou: `error: deployment "chatwoot-web" exceeded its progress deadline` exatamente 10min depois de `kubectl set image`. Auto-rollback funcionou, prod voltou pra `v0.1.0`.

### Causa raíz
Cluster foi montado SEM `imagePullSecrets` wired no SA `default` nem nos Deployments do ns `chatwoot`. `ghcr-secret` (do tipo `dockerconfigjson`) existia no namespace mas não era referenciada por nada.

`v0.1.0` sobrevivia porque `imagePullPolicy: IfNotPresent` + imagem cacheada no worker-03 desde o deploy original. Kubelet nunca tentava puxar, usava cache.

`v0.2.1` (tag nova) → kubelet OBRIGADO a puxar do ghcr → `401 Unauthorized` → `ImagePullBackOff` → `progressDeadlineSeconds` (default 600s) estoura.

### Fix permanente (commit registrado em git)
Workflow `holding-fix-imagepull.yml` patcha 2 camadas:
1. `kubectl patch sa default -n chatwoot -p '{"imagePullSecrets":[{"name":"ghcr-secret"}]}'` — todo pod novo do namespace herda
2. `kubectl patch deploy chatwoot-{web,worker} ... -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ghcr-secret"}]}}}}'` — defesa explícita no spec

Verifica no final que ambas camadas pegaram, fail-fast se não.

### Prevenção
Se aparecer namespace novo (staging, hml, etc), aplicar mesmo padrão. Considerar criar secret + patch como parte do bootstrap do namespace na infra-as-code (não tem hoje).

## Runbook — deploy de tag nova

### Caminho feliz
1. Merge PR em `develop` → CI builda imagem `develop` + `latest` no ghcr
2. Tag manualmente: `git tag v0.X.Y && git push origin v0.X.Y`
3. CI builda imagem `v0.X.Y` + roda `deploy-core`:
   - `kubectl set image` → web + worker + initContainer db-migrate
   - `kubectl rollout status` (timeout 15m web, 10m worker)
   - Health check `https://chat.abckx.com.br/auth/sign_in` (12 tentativas/2min)
4. Se algum passo acima falhar, step `Auto-rollback on failure` roda `kubectl rollout undo` → prod volta pra anterior

### Se falhar
1. **Não entre em pânico** — o auto-rollback já trouxe prod de volta
2. Rode `holding-cluster-diagnose.yml` manualmente (workflow_dispatch) → captura pods/events/logs do estado atual
3. Pra capturar estado **durante** a falha, rode no GitHub UI: re-trigger do deploy (gh run rerun --failed) e enquanto rola, em outra janela trigger o diagnose
4. Se for `imagePullBackOff` de novo → `holding-fix-imagepull.yml` (idempotente, sempre seguro rodar)

### Limites conhecidos
- `progressDeadlineSeconds` = **1800s (30min)** após PR #6. Buffer confortável pra migrations grandes.
- `command_timeout: 20m` no `appleboy/ssh-action` (PR #2). Cobre rollout + 5min de buffer.

## Tech debt conhecido (decidido não-arrumar agora)

Triagem do Founder 2026-04-30:

| # | Item | Decisão | Owner |
|---|---|---|---|
| 1 | Manifest source-of-truth desconhecido (patches drift se infra reaplicar) | Infra | Sergio |
| 2 | Pod pinado em worker-03 via nodeSelector + PVC RWO local-path (SPOF) | Infra (longo prazo: RWX) | Sergio |
| 3 | `imagePullPolicy: IfNotPresent` mascara retag de mesma versão | Não fixar — caso raro, conserta se ocorrer | — |
| 4 | Token do `ghcr-secret` sem rotação documentada | Não-meu | Sergio |
| 5 | `progressDeadlineSeconds=600s` apertado | **FIXADO** PR #6 → 1800s | Denise |
| 6 | Probe bate em `/auth/sign_in` (não `/healthz`) | Over — não fazer | — |

## Tags emitidas até agora

| Tag | Data | Status | Notas |
|---|---|---|---|
| v0.1.0 | 2026-04-30 04:19 | ✅ deploy original | imagem cacheada no worker-03 |
| v0.2.0 | 2026-04-30 20:04 | ❌ SSH timeout | command_timeout (10m default) < rollout timeout (15m). Fix em PR #2 |
| v0.2.1 | 2026-04-30 20:31 (1ª) | ❌ progress deadline | imagePullSecrets faltando. Fix em PR #5 |
| v0.2.1 | 2026-04-30 22:27 (rerun) | ✅ live | redeploy via `gh run rerun --failed` após fix do imagePullSecrets |
