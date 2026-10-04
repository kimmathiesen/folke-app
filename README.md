# Folke-App

Selfhostet baby-tracker oven på [Baby Buddy](https://github.com/babybuddy/babybuddy). Start/stop søvn med ét tryk, få en forudsigelse af næste lur eller sengetid, og log mad og pumpning. Designet som en mobil-app (PWA) til iPhonens hjemmeskærm. Al data ligger i Baby Buddy.

## Funktioner

- **Søvn:** start/stop med tæller, lur/nat, og mulighed for at taste "faldt i søvn kl." / "vågnede kl." bagud
- **Dagsring:** 24-timers ring med dagens søvn som buer, klokkeslæt og forventet næste søvn
- **Forudsigelse:** næste lur/sengetid ud fra barnets egne vågenvinduer (median af de sidste 10 dage, pr. position på dagen). Aldersbaseret standard bruges, indtil der er data nok
- **Rediger søvn:** tryk på en søvn i listen for at rette tider, skifte lur/nat eller slette
- **Mad:** amning (venstre/højre/begge), flaske (ml, modermælk/erstatning) og fastføde
- **Vækst:** egen side (knap øverst til højre) med vægt, længde og hovedomfang på WHO's kurver (2006), 3.-97. percentil. Gemmes i `growth.json`, kurvedata ligger i `who.py`
- **Pumpning:** `POST /api/pump`, beregnet til Home Assistant
- **Forslag:** appen foreslår at tilføje eller skjule funktioner efter alder og brug (fast føde ved 6 mdr., skjul amning efter 3 uger uden). Intet ændres uden svar. Alt kan ændres under *Indstillinger* (knap øverst til venstre)
- **Home Assistant:** opdaterer `sensor.baby_next_sleep` og sender notifikation før næste søvn

## Opbygning

| Fil | Rolle |
|---|---|
| `napper.py` | Forudsigelsesmotor, HA-sensor og notifikationer (kan også køre alene via cron) |
| `app.py` | Flask-API og baggrundstråd (kalder `napper.main()` hvert minut) |
| `who.py` | WHO's vækststandarder (LMS-tabeller) og percentilberegning |
| `index.html` | Hele brugerfladen, ingen build |
| `Dockerfile` | Python 3.12 slim + gunicorn (1 worker, så baggrundstråden kun kører ét sted) |
| `.github/workflows/docker.yml` | Bygger og pusher image til `ghcr.io/kimmathiesen/folke-app:latest` |
| `unraid/my-napper.xml` | Unraid-skabelon (`unraid/update-local.sh`: lokal variant uden GitHub) |
| `tests/` | pytest: `predict()`, WHO-kurver og API mod en falsk Baby Buddy |

## Konfiguration (miljøvariabler)

| Variabel | Beskrivelse | Standard |
|---|---|---|
| `BB_URL` | Baby Buddy-adresse | `http://localhost:8000` |
| `BB_TOKEN` | Baby Buddy API-nøgle | |
| `HA_URL` | Home Assistant-adresse (valgfri) | |
| `HA_TOKEN` | HA long-lived access token | |
| `HA_NOTIFY` | Notify-tjeneste, fx `notify.mobile_app_din_telefon` | |
| `TZ` | Tidszone | `Europe/Copenhagen` |
| `CHILD_ID` | Barnets id, hvis der er flere | første barn |
| `LEAD_MIN` | Minutter før næste søvn, notifikationen sendes | `10` |
| `HISTORY_DAYS` | Dage søvnhistorik til forudsigelsen | `10` |
| `STATE_FILE` | Stien til tilstandsfil (`prefs.json` ligger ved siden af) | `/data/state.json` |

Gem aldrig nøgler i repoet. Brug `.env` (ignoreret af git) eller felterne i Unraid-skabelonen.

## Kør

```bash
docker run -d --name folke-app --restart unless-stopped \
  -e BB_URL=http://BABYBUDDY:8000 -e BB_TOKEN=... \
  -e HA_URL=http://HA:8123 -e HA_TOKEN=... -e HA_NOTIFY=notify.mobile_app_... \
  -e TZ=Europe/Copenhagen -e STATE_FILE=/data/state.json \
  -v /sti/til/data:/data -p 6660:8080 \
  ghcr.io/kimmathiesen/folke-app:latest
```

Åbn `http://SERVER:6660` og vælg *Føj til hjemmeskærm* i Safari.

## Unraid

Læg `unraid/my-napper.xml` i `/boot/config/plugins/dockerMan/templates-user/`, og opret containeren via *Docker → Add Container*. Slå automatisk opdatering til med pluginet *CA Auto Update Applications*. Et push til `main` bygger så et nyt image, som Unraid henter selv.

## API

| Endpoint | Formål |
|---|---|
| `GET /api/status` | Tilstand, forudsigelse, dagens søvn, sidste måltid, forslag |
| `POST /api/start` | Start søvn. Valgfrit `{"since": "HH:MM"}` |
| `POST /api/stop` | Stop søvn. Valgfrit `{"nap": true, "wake": "HH:MM"}` |
| `POST /api/sleep/<id>` / `DELETE` | Ret eller slet en søvn |
| `POST /api/feed` | `{"kind": "left\|right\|both\|bottle\|solid", "amount": ml, "milk": "formula", "at": "HH:MM"}` |
| `POST /api/pump` | `{"amount": ml}` |
| `GET/POST /api/growth`, `POST/DELETE /api/growth/<id>` | Vækstmålinger og kurver |
| `POST /api/suggestion`, `POST /api/feature` | Svar på forslag, slå funktioner til/fra |

## Home Assistant

Appen sætter `sensor.baby_next_sleep` (tidsstempel). Pumpning og start/stop kan styres med `rest_command` mod endpoints ovenfor og en `rest`-sensor mod `/api/status`.

## Sikkerhed

Der er intet login. Hold appen på LAN eller bag Tailscale, og udstil den ikke på internettet.

## Udvikling

Se `CLAUDE.md` for arkitektur og kendte antagelser mod Baby Buddys API.

Tests (kører også i GitHub Actions før hvert image-build):

```bash
pip install -r requirements-dev.txt
pytest -q
```
