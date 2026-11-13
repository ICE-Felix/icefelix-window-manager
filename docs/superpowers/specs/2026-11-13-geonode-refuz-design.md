# Geonode: respingere + protecție contact — design

Task: Google Tasks, lista „ICE-Felix Flutter Packages”, „Geonode: respingere SDK + protecție contact + ADR anti-SDK terț”.

## Locul intervenției
Nu e UI. Se schimbă: Gmail (filtru), repo `icefelix-window-manager` (ADR, `CLAUDE.md`), configurarea git a autorului. Cod de pachet: neatins.

## Delta
| Cerință | Stare | Dovadă |
|---|---|---|
| Integrare SDK Geonode | nu există și nu se face | `packages/icefelix_window_manager/pubspec.yaml`: doar `flutter`, `meta`, `plugin_platform_interface` |
| Sursa adresei `alex.bordei@whiz.ro` | neverificat; ipoteză: emailul din commit-urile publice | `git log --all`: 34 de commituri cu `alex.bordei@whiz.ro`; în fișiere apare doar `@icefelix.com` |
| Filtru Gmail | făcut 2026-11-13 | filtru `{geonodeservices.com geonode.com}`, scos din INBOX și marcat citit |

## Decizii (runda 1, toate confirmate „da”)
1. Refuzăm integrarea; taskul = protecție contact + politică.
2. Nu răspundem, nu apăsăm unsubscribe; filtru Gmail.
3. ADR 0001: fără SDK terț de monetizare/telemetrie.
4. Contact: pubspec nu conține email, deci nu e nimic de mutat acolo. Sursa probabilă e emailul din commituri; recomandare: `git config` pe email noreply GitHub pentru commiturile viitoare. Istoricul nu se rescrie (repo publicat, tag-uri, pub.dev).
5. Tracker: Google Tasks; `CLAUDE.md` cu „Configurare metodologie” pe același branch.

## Puncte de testare
Niciunul: nu se schimbă comportament de cod.

## În afara scopului
- Rescrierea istoricului git.
- Evaluarea ofertei Geonode (condiții, preț).
- Răspuns către Geonode sau raportare ca spam.
- Schimbări în pachet.
