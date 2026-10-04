# Napper (selfhostet)
Baby-søvntracker oven på Baby Buddy (REST API). Mål: start/stop søvn fra telefonen (PWA),
forudsigelse af næste lur/sengetid, notifikation via Home Assistant.

## Arkitektur
- `napper.py`: motor. `predict()` (vågenvinduer pr. position på dagen, median, aldersbaseret fallback),
  HA-sensor `sensor.baby_next_sleep`, notifikation LEAD_MIN min før. Kan køre alene (cron) eller importeres.
- `app.py`: Flask. `/api/status`, `/api/start`, `/api/stop`, `/api/pump` (JSON {amount} -> Baby Buddy /api/pumping/, kaldes fra HA). Start = Baby Buddy-timer "Søvn";
  stop = POST /api/sleep/ + DELETE timeren. Baggrundstråd kalder `napper.main()` hvert 60. sek.
- `index.html`: enkeltfil-UI (ingen build). Kør gunicorn med 1 worker (tråden).
- Konfiguration via env (se `.env.example`). Alle tider håndteres i TZ (Europe/Copenhagen).

## Uverificeret mod rigtig Baby Buddy (test først!)
- Felter ved POST /api/timers/ og /api/sleep/, og at DELETE timer virker.
- `start_min`-filter på /api/sleep/, og `active`-felt på timere.

## Idéer / TODO
- Ret/slet seneste registrering i UI, tilføj glemt søvn bagud
- Ikon + splash til hjemmeskærm, evt. HTTPS via Tailscale/NPM
- Tests: `tests/` (pytest, falsk Baby Buddy i `test_app.py`). CI kører dem før build.
- Flere børn, vækstvindue-justering (fx efter dårlig nat), enkelt login

## Udrulning
- GitHub Actions bygger `ghcr.io/kimmathiesen/folke-app:latest` ved push til main.
- Unraid-skabelon: `unraid/my-napper.xml` (hemmeligheder ligger kun i Unraid, aldrig i repoet).
- Lokal variant uden GitHub: `unraid/update-local.sh` (Gitea + cron).

## Forslag og tilpasning
- `prefs.json` (ved siden af state.json) gemmer funktionsvalg og svar på forslag. `suggestions()` i app.py beregnes højst hvert 10. min.
- Forslag: «Fast føde» ved 6 mdr., «skjul Amning» efter 21 dage uden amning. Intet ændres uden svar (Ja / Ikke nu = 30 dage / Aldrig). «Tilpas» nederst gør alt reversibelt.

## Vækst
- Egen side i index.html (`#vaekst`). Målinger i `growth.json` (ikke Baby Buddy). `who.py` har WHO LMS-tabeller 0-24 mdr. (fra pygrowup) og beregner kurver/percentiler. Køn vælges under Tilpas (`prefs.json`).
