# Folke-App

Selfhostet baby-tracker. Start/stop søvn med ét tryk, få en forudsigelse af næste lur eller sengetid, og log mad, udpumpning og vækst. Designet som en mobil-app (PWA) til iPhonens hjemmeskærm. Data ligger i en SQLite-fil på serveren. (Appen startede oven på [Baby Buddy](https://github.com/babybuddy/babybuddy), men kører nu helt uden.)

## Funktioner

- **Første opstart:** barnets navn og fødselsdato og «Jeg er mor/far» på hver enhed. Forsiden siger «Hej Folkes mor»

- **Søvn:** start/stop med tæller, lur/nat, og mulighed for at taste "faldt i søvn kl." / "vågnede kl." bagud
- **Dagsring:** 24-timers ring med dagens søvn som buer, klokkeslæt og forventet næste søvn
- **Forudsigelse og dagsplan:** næste lur/sengetid og en plan for resten af dagen ud fra barnets egne vågenvinduer og lurlængder (median af de sidste 10 dage, pr. position på dagen). Planen genberegnes i realtid: misset lur giver «lur nu» og en flyttet dag, en kort lur (under 30 min) giver et kortere vindue, og en dag med for lidt søvn giver tidligere sengetid (højst 60 min). Afvigelser påvirker ikke barnets normale tal. Aldersbaseret standard bruges, indtil der er data nok
- **Rediger søvn:** tryk på en søvn i listen for at rette tider, skifte lur/nat eller slette
- **Sider:** forsiden er sider, man stryger mellem som på iPhonens hjemmeskærm: Søvn (standard), Mad, Udpumpning og Vækst
- **Mad:** amning (venstre/højre/begge), flaske (ml, modermælk/erstatning) og fastføde, og en liste over dagens måltider
- **Vækst:** egen side med vægt, længde og hovedomfang på WHO's kurver (2006), 3.-97. percentil. Gemmes i `growth.json`, kurvedata ligger i `who.py`
- **Udpumpning:** egen side med registrering (ml, side, minutter og tidspunkt), dagens total, graf over 14 dage og en liste, hvor man kan rette og slette. Påmindelse via Home Assistant efter et valgfrit antal timer (ikke mellem 22 og 7). Kan slås fra under Indstillinger. `POST /api/pump` virker stadig fra Home Assistant
- **Forslag:** appen foreslår at tilføje eller skjule funktioner efter alder og brug (fast føde ved 6 mdr., skjul amning efter 3 uger uden). Intet ændres uden svar. Alt kan ændres under *Indstillinger* (knap øverst til venstre)
- **Notifikationer:** «Tid til at slappe af. Næste lur ca. kl. 13:40» 30 min før, «Folke virker meget frisk. Prøv alligevel en lur» hvis tiden er gået med 15 min uden søvn, og påmindelse om udpumpning. Hver enhed (fx mors og fars telefon) vælger selv, hvilke den vil have. Søvnbeskederne er slået til, udpumpning fra. Via web push direkte til telefonen (Indstillinger → *Notifikationer på denne enhed*) og/eller via Home Assistant
- **Tavlen:** et lille easter egg. Tryk på månen øverst for at tegne eller skrive til din partner med fingeren. Tavlen er fælles: det, den ene tegner eller visker ud, ser den anden også. Ingen notifikation, men stjernerne ved månen blinker, når der er noget nyt
- **Home Assistant:** opdaterer `sensor.baby_next_sleep` og kan sende notifikationer

## Opbygning

| Fil | Rolle |
|---|---|
| `folke.py` | Forudsigelsesmotor, HA-sensor og notifikationer (kan også køre alene via cron) |
| `app.py` | Flask-API og baggrundstråd (kalder `folke.main()` hvert minut) |
| `store.py` | Datalag: SQLite-filen, migreringer, eksport og backup |
| `who.py` | WHO's vækststandarder (LMS-tabeller) og percentilberegning |
| `index.html` | Hele brugerfladen, ingen build |
| `Dockerfile` | Python 3.12 slim + gunicorn (1 worker, så baggrundstråden kun kører ét sted) |
| `.github/workflows/docker.yml` | Bygger og pusher image til `ghcr.io/kimmathiesen/folke-app:latest` |
| `unraid/my-folke.xml` | Unraid-skabelon (`unraid/update-local.sh`: lokal variant uden GitHub) |
| `tests/` | pytest: forudsigelse, dagsplan, WHO-kurver og API'erne mod en frisk SQLite-fil |

## Konfiguration (miljøvariabler)

| Variabel | Beskrivelse | Standard |
|---|---|---|
| `HA_URL` | Home Assistant-adresse (valgfri) | |
| `HA_TOKEN` | HA long-lived access token | |
| `HA_NOTIFY` | Notify-tjeneste, fx `notify.mobile_app_din_telefon` | |
| `TZ` | Tidszone | `Europe/Copenhagen` |
| `CHILD_ID` | Barnets id, hvis der er flere | første barn |
| `LEAD_MIN` | Minutter før næste søvn, beskeden «Tid til at slappe af» sendes (standard; hver enhed med web push kan vælge sit eget under Indstillinger) | `30` |
| `OVERDUE_MIN` | Minutter efter forventet søvn, beskeden «… virker meget frisk» sendes (standard, kan vælges pr. enhed) | `15` |
| `HA_KINDS` | Beskedtyper, Home Assistant får (`sleep_soon`, `overdue`, `pump`) | `sleep_soon,overdue` |
| `HISTORY_DAYS` | Dage søvnhistorik til forudsigelsen | `10` |
| `STATE_FILE` | Stien til tilstandsfil (`prefs.json` ligger ved siden af) | `/data/state.json` |
| `DB_FILE` | SQLite-fil | `folke.db` ved siden af `STATE_FILE` |
| `HA_SENSOR` | Sensoren, forudsigelsen skrives til | `sensor.baby_next_sleep` |
| `CHILD_BIRTH`, `CHILD_NAME` | Valgfrit: barnets fødselsdato (ÅÅÅÅ-MM-DD) og navn. Ellers spørger appen ved første opstart | |

Gem aldrig nøgler i repoet. Brug `.env` (ignoreret af git) eller felterne i Unraid-skabelonen.

## Kør

```bash
docker run -d --name folke-app --restart unless-stopped \
  -e HA_URL=http://HA:8123 -e HA_TOKEN=... -e HA_NOTIFY=notify.mobile_app_... \
  -e TZ=Europe/Copenhagen -e STATE_FILE=/data/state.json \
  -v /sti/til/data:/data -p 6660:8080 \
  ghcr.io/kimmathiesen/folke-app:latest
```

Åbn `http://SERVER:6660` og vælg *Føj til hjemmeskærm* i Safari.

## Unraid

Læg `unraid/my-folke.xml` i `/boot/config/plugins/dockerMan/templates-user/`, og opret containeren via *Docker → Add Container*. Slå automatisk opdatering til med pluginet *CA Auto Update Applications*. Et push til `main` bygger så et nyt image, som Unraid henter selv.

## API

| Endpoint | Formål |
|---|---|
| `GET /api/status` | Tilstand, forudsigelse, dagsplan, dagens søvn og måltider, forslag |
| `POST /api/start` | Start søvn. Valgfrit `{"since": "HH:MM"}` |
| `POST /api/stop` | Stop søvn. Valgfrit `{"nap": true, "wake": "HH:MM"}` |
| `POST /api/sleep/<id>` / `DELETE` | Ret eller slet en søvn |
| `POST /api/feed` | `{"kind": "left\|right\|both\|bottle\|solid", "amount": ml, "milk": "formula", "at": "HH:MM"}` |
| `POST /api/pump` | `{"amount": ml}`, valgfrit `"at": "HH:MM"`, `"side": "left\|right\|both"`, `"minutes"` |
| `POST /api/pump/<id>` / `DELETE` | Ret eller slet en udpumpning |
| `GET /api/pump/history?days=14` | Ml pr. dag og de enkelte udpumpninger |
| `POST /api/pump/remind` | `{"hours": 3}` (0 = fra) |
| `GET /api/push/key`, `POST /api/push/subscribe`, `/unsubscribe`, `/test` | Web push pr. enhed |
| `GET/POST /api/growth`, `POST/DELETE /api/growth/<id>` | Vækstmålinger og kurver |
| `POST /api/suggestion`, `POST /api/feature` | Svar på forslag, slå funktioner til/fra |
| `POST /api/child` | Første opstart: `{"name", "birth_date"}` |
| `GET /api/export` | Alle data som JSON |

## Data

Alt ligger i `/data`: `folke.db` (SQLite), `growth.json`, `prefs.json`, `board.json`, `push.json` og `vapid.pem`.

- **Backup:** dagligt øjebliksbillede af databasen i `/data/backup/` (de seneste 14 dage).
- **Eksport:** *Eksportér* under Indstillinger giver alle data som JSON. Filen kan også importeres i iPhone-appen (branch `ios`).
- Kolonnen `bb_id` i databasen er en rest fra importen fra Baby Buddy og bruges ikke længere.

## Push-notifikationer

Virker uden Home Assistant. Kræver https, fx via cloudflared eller Tailscale.

1. Åbn appen i Safari på https-adressen, og vælg *Del → Føj til hjemmeskærm*. På iPhone virker push kun fra hjemmeskærmen (iOS 16.4+).
2. Åbn appen fra hjemmeskærmen, gå til *Indstillinger → Notifikationer på denne enhed*, og tryk *Slå til*.
3. Tryk *Send test*.

Gentag på hver enhed. Nøglen (`vapid.pem`) og enhederne (`push.json`) ligger i `/data`. Mistes `vapid.pem`, skal hver enhed slå notifikationer til igen.

## Home Assistant

Appen sætter `sensor.baby_next_sleep` (tidsstempel). Pumpning og start/stop kan styres med `rest_command` mod endpoints ovenfor og en `rest`-sensor mod `/api/status`.

## Sikkerhed

Der er intet login. Hold appen på LAN eller bag Tailscale, og udstil den ikke på internettet.

## Udvikling

Se `CLAUDE.md` for arkitektur og arbejdsgang.

Tests (kører også i GitHub Actions før hvert image-build):

```bash
pip install -r requirements-dev.txt
pytest -q
```
