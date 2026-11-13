# icefelix-window-manager

Federated Flutter plugin (desktop), publisher pub.dev `icefelix.com`. Reguli de cod: `ICE-Felix/coding_rules`, skill `reguli-de-cod`.

## Configurare metodologie
- tracker: Google Tasks, lista „ICE-Felix Flutter Packages”
- convenția titlurilor de task: „[Fază] pachet — ce se face”
- remote + unealtă MR: GitHub (`ICE-Felix/icefelix-window-manager`) + `gh`
- test țintit: `melos run test` din rădăcină (de confirmat comanda exactă)
- e2e: `integration_test` din `packages/icefelix_window_manager/example`
- mediu dev/prod: nu există (pachet, nu serviciu); „deploy” = publicare pub.dev prin OIDC
- poarta: `.poarta.conf` încă lipsă
- glosar și ADR-uri: `GLOSSARY.md` (lipsă), `docs/adr/`
- standarde de cod pentru review: niciunul încă
- interdicții locale: fără SDK terț de monetizare/telemetrie (vezi ADR 0001); fără rescriere de istoric pe branch-uri publicate
