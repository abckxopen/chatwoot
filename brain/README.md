# brain/ — fonte única de verdade técnica do fork abckxopen/chatwoot

Esta pasta carrega tudo que é específico desta codebase e é durável: stack, decisões de arquitetura, runbooks, integração com a holding. Scoped ao **fork** (não vai pro upstream chatwoot/chatwoot — fica isolado em path próprio justamente pra evitar conflito em rebase do upstream).

Ao trabalhar nesse repo, sempre ler `context.md` aqui ANTES de mexer em código.

## Índice

- `context.md` — overview do projeto: stack, environments, dev workflow, integração com os 7 sistemas da holding.
- `fork-policy.md` — _(a criar quando primeira decisão durável for tomada)_: como rebasear do upstream, onde isolar customizações, quais paths evitar.

## Convenção

- Tudo aqui é **técnico e durável**. Não é diário de sessão.
- Se uma decisão é "sempre faremos assim nesse projeto", entra aqui.
- Se é "quem é a Denise nesse projeto / status no radar dela", vai pro `denise/projects/abckxopen/chatwoot/`.
