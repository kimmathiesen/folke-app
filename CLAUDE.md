# Folke (selfhostet)
Baby-søvntracker oven på Baby Buddy (REST API). Mål: start/stop søvn fra telefonen (PWA),
forudsigelse af næste lur/sengetid, notifikation via Home Assistant.

## Arkitektur
- `folke.py`: motor. `plan_day()` laver dagsplanen (lure og sengetid resten af dagen), og `predict()` er dens første punkt (vågenvinduer pr. position på dagen, median, aldersbaseret fallback),
  HA-sensor `sensor.baby_next_sleep`, besked LEAD_MIN (30) min før og OVERDUE_MIN (15) min efter, hvis ingen søvn er startet. Kan køre alene (cron) eller importeres.
- `app.py`: Flask. `/api/status`, `/api/start`, `/api/stop`, `/api/pump` (JSON {amount} -> Baby Buddy /api/pumping/, kaldes fra HA). Start = Baby Buddy-timer "Søvn";
  stop = POST /api/sleep/ + DELETE timeren. Baggrundstråd kalder `folke.main()` hvert 60. sek.
- `store.py`: datalag. `store.get()` giver `BabyBuddy` eller `Sqlite` (env `BACKEND`). app.py og `folke.main()` går altid gennem det, aldrig direkte til Baby Buddy. Tider gemmes i SQLite som UTC-tekst (`iso()`), så de kan sammenlignes som tekst. Skemaændringer: tilføj et trin til `MIGRATIONS` (PRAGMA user_version).
- Stand-alone: envejs-import (`Sqlite.import_bb`, upsert på `bb_id`, spejler Baby Buddy-rækker, lokale rækker har `bb_id` NULL). `tick()` i app.py importerer automatisk ved tom database og tager daglig backup. Branch `standalone` -> image `:standalone`, skabelon `unraid/my-folke-standalone.xml` (port 6661, HA slået fra).
- `index.html`: enkeltfil-UI (ingen build). Kør gunicorn med 1 worker (tråden).
- Konfiguration via env (se `.env.example`). Alle tider håndteres i TZ (Europe/Copenhagen).

## Uverificeret mod rigtig Baby Buddy (test først!)
- Felter ved POST /api/timers/ og /api/sleep/, og at DELETE timer virker.
- `start_min`-filter på /api/sleep/, og `active`-felt på timere.

## Idéer / TODO
- Ret/slet seneste registrering i UI, tilføj glemt søvn bagud
- Ikon + splash til hjemmeskærm, evt. HTTPS via Tailscale/NPM
- Tests: `tests/` (pytest). `fakebb.py` er en falsk Baby Buddy. `world`-fixturen i conftest kører API-testene mod både Baby Buddy og SQLite. Kør: `.venv/Scripts/python -m pytest -q`. CI kører dem før build.
- Flere børn, vækstvindue-justering (fx efter dårlig nat), enkelt login

## Udrulning
- GitHub Actions bygger `ghcr.io/kimmathiesen/folke-app:latest` ved push til main.
- Unraid-skabelon: `unraid/my-folke.xml` (hemmeligheder ligger kun i Unraid, aldrig i repoet).
- Lokal variant uden GitHub: `unraid/update-local.sh` (Gitea + cron).

## Forslag og tilpasning
- `prefs.json` (ved siden af state.json) gemmer funktionsvalg og svar på forslag. `suggestions()` i app.py beregnes højst hvert 10. min.
- Forslag: «Fast føde» ved 6 mdr., «skjul Amning» efter 21 dage uden amning. Intet ændres uden svar (Ja / Ikke nu = 30 dage / Aldrig). Siden «Indstillinger» (`#indstillinger`, knap øverst til venstre) gør alt reversibelt.

## Udpumpning (kun branch standalone)
- Kort på forsiden, side `#pumpning` (graf 14 dage, liste 7 dage, ret/slet). Side og minutter gemmes kun i SQLite (migration 2). Baby Buddy-backenden ignorerer dem.
- Påmindelse: `pump_reminder()` i app.py, kaldt fra `tick()`. `prefs.pump_remind` timer (0 = fra), én gang pr. udpumpning (`pump_notified` i state.json), ikke mellem 22 og 7.

## Push (kun branch standalone)
- `push.py`: web push med pywebpush. VAPID-nøgle i `vapid.pem` (laves første gang), abonnementer i `push.json`, begge ved STATE_FILE. 404/410 fra push-tjenesten fjerner abonnementet.
- Beskedtyper (`folke.KINDS`): `sleep_soon`, `overdue`, `pump`. Hver enhed har til/fra i `push.json` (`kinds`, `push.DEFAULT_KINDS`: søvn til, udpumpning fra), sat via `POST /api/push/kinds`. HA får typerne i env `HA_KINDS` (standard kun søvn). Udpumpningens «efter X timer» er fælles (`prefs.pump_remind`, standard 3).
- `folke.notify(title, msg, kind)` sender via HA (hvis sat op) og push (`folke.push`, sat af app.py). `folke.can_notify()` styrer, om der overhovedet notificeres. `sw.js` (route `/sw.js`) viser notifikationen.

## Navn og forælder (kun branch standalone)
- Barnets navn er fælles: `prefs.child_name` (sat ved første opstart eller under Indstillinger), ellers `first_name` fra databasen. `folke.display_name` bruges i beskeden «… virker meget frisk».
- Mor/far gemmes kun på enheden (`localStorage` `folke.role`) og giver overskriften «Hej Folkes mor» og push-navnet «Mors iPhone».
- Første opstart: UI'et viser `#onb`, hvis navn eller rolle mangler. Uden barn i SQLite svarer `/api/status` `{setup: true}`, og `POST /api/child` opretter barnet.

## Tavlen (easter egg, kun branch standalone)
- Tryk på månen i toppen -> `#tavle`. Fælles tegning i `board.json` (ved STATE_FILE): streger som punkter i 0..1 på en tavle med fast format 3:4, så den ser ens ud overalt. Ingen push.
- `/api/board` (`?v=` giver `{same: true}`, hvis intet er nyt), `/stroke`, `/undo`, `/clear`. Klienten spørger hvert 2,5 sek., mens tavlen er åben.
- Stjernerne ved månen blinker, når `status.board` (version, 0 hvis tom) er nyere end `localStorage` `folke.boardSeen`.

## Vækst
- Egen side i index.html (`#vaekst`). Målinger i `growth.json` (ikke Baby Buddy). `who.py` har WHO LMS-tabeller 0-24 mdr. (fra pygrowup) og beregner kurver/percentiler. Køn vælges under Indstillinger (`prefs.json`).

## Dagsplan og genberegning
- `plan_day()` i folke.py: lure med hans typiske længde pr. lurnummer, indtil sengetid. Genberegnes ved hver status.
- **Kort lur:** under 30 min (`SHORT_NAP`), fx i barnevognen. Den tæller ikke som en af dagens lure, og næste vindue er 75 % (`SHORT_FACTOR`).
- **For lidt dagsøvn:** sengetiden rykkes halvdelen af underskuddet frem. Kan en lur ikke nås med hans normale vindue bagefter (+30 min), droppes den, og sengetiden rykkes. Begge dele højst 60 min (`MAX_BED_SHIFT`).
- **Misset lur:** vågen 15 min efter planlagt lur. Kun skærmen viser «nu» og flytter resten. `predict()` (`replan=False`) holder fast i det oprindelige tidspunkt, så «virker meget frisk» kommer til tiden.
- **Hans tal beskyttes:** vinduer lige før og efter korte lure bruges ikke, og afvigere uden for 60–160 % af medianen sorteres fra (`_robust`).
- Facit: `tests/test_dayplan.py`. Specifikationen til iOS står i `ios/PLAN.md` afsnit 3.

## Arbejdsgang: standalone og ios (to sessioner)
- **`standalone`** er den app, familien bruger, og facit for server, webapp og regler. Rettelser til webappen og serveren laves her (Windows-sessionen). `main` ligger stille.
- **`ios`** er iPhone-appen (Mac-sessionen). **Start altid med `git fetch && git merge origin/standalone`**, og arbejd derefter `ios/PORT.md` igennem.
- **`ios/PORT.md`** er huskelisten over rettelser på `standalone`, som appen også skal have. Den, der retter på `standalone`, tilføjer et punkt (dato, commit, hvad, hvor i PLAN.md, facit-test) i samme omgang og opdaterer `ios/PLAN.md`. Mac-sessionen sætter `[x]` og skriver sin commit ved siden af, når punktet er lavet i Swift. Rene webting (CSS, iPad-layout) kommer ikke på listen.
- Serverkode (`*.py`, `index.html`) rettes helst kun på `standalone`. Skal det ske på `ios`, så hold det lille og nævn det, så det flettes tilbage til `standalone`.

## iPhone-app (branch `ios`, mappen `ios/`)
- Plan: `ios/PLAN.md`. Webappen/serveren er facit for regler, tekster og udseende.
- `ios/FolkeCore`: Swift package uden UI (forudsigelse, notifikationsregler, WHO, forslag, farver, Core Data-model i kode, `FolkeStore`). Python-testene er porteret til Swift Testing.
  Test: `cd ios/FolkeCore && xcodebuild test -scheme FolkeCore -destination 'platform=iOS Simulator,name=iPhone 17'`
- `ios/Folke.xcodeproj` + `ios/Folke/`: SwiftUI-appen (mappen synkroniseres automatisk, nye filer kræver ingen ændring i projektet).
  Build: `cd ios && xcodebuild build -project Folke.xcodeproj -scheme Folke -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGN_IDENTITY=-` (lokal signering, så App Group-tilladelsen kommer med)
- `ios/Shared/` er med i både appen og widget-udvidelsen (`ios/FolkeWidgets/`): `FolkeShared` (App Group `group.dk.folkeapp.folke`, fælles `store`, rolle), Live Activity (`SleepActivity.swift`), App Intents (`Intents.swift`: start/stop søvn, log udpumpning/flaske; start/stop er `LiveActivityIntent` og kører i appens proces) og `Notifier` (indstillinger i gruppens UserDefaults, så intents kan planlægge). Siri-sætninger: `Folke/Shortcuts.swift`.
- Widgets: `FolkeWidgets/SleepWidget.swift` (lille/mellem + låseskærm, knap start/stop) og `SleepLiveActivityWidget.swift` (låseskærm og Dynamic Island). Appen genindlæser widgets, når det, de viser, ændrer sig.
- Core Data, ikke SwiftData: SwiftData understøtter ikke delte CloudKit-databaser (tjekket i iOS 27-SDK'et).
- iCloud er slået fra (`AppModel.cloudKitContainer = nil`), indtil appen signeres med udviklerkontoen (milepæl 6). Bundle id `dk.folkeapp.folke` er et arbejdsnavn.
- Debug: start med `-demoData YES` (evt. `-demoMonths 7` for forslaget om fast føde) for et barn med 10 dages søvn, måltider, 14 dages udpumpning og vækstmålinger, eller `-demoExport <sti>` for en eksport fra serveren (samme import som «Importér fra Folke-server» under Indstillinger, der kun vises uden for App Store-builds). NB: tømmer databasen i App Group først (så widgets ser de samme data).
- Sider: `AppModel.page` (home, settings, growth, pump) svarer til hash-ruterne i webappen. Vækst og udpumpningshistorik ligger i `FolkeCore/History.swift`.
- Klokkeslæt i UI'et vises med punktum («kl. 14.05», `Format.time`) som i webappen. Notifikationer og fejl bruger kolon (`Format.clock`) som serveren.
- Folke Plus: gratis er den oprindelige forudsigelse (`Predictor.basic`, `store.basicPrediction`); dagsplanen kræver Plus. Regler i `FolkeCore/Plus.swift`, køb i `Folke/PlusStore.swift` (StoreKit 2). Status i App Group (`FolkeShared.plus()`), så widgets, Live Activity, intents og notifikationer låses ens. Testkøb: `ios/Folke.storekit` via den delte scheme (kun ved ⌘R i Xcode). Debug: `-plus locked|trial|purchased`.
- Eksport som CSV: `FolkeCore/Export.swift` (semikolon, decimalkomma, BOM), zippes i `AppModel.exportCSV()`. Privacy manifest: `PrivacyInfo.xcprivacy` i app og widgets. Privatlivspolitik og App Store-tekster: `ios/AppStore/`.
- Notifikationer: `Folke/Notifier.swift` planlægger lokale notifikationer ud fra `NotificationPlanner` ved hver `refresh()` (fast id pr. type). Beskedtyper pr. enhed og log over sendte i `UserDefaults` (`folke.kinds`, `folke.notificationLog`). Se planen: `xcrun simctl spawn "iPhone 17" log show --last 5m --predicate 'subsystem == "dk.folkeapp.folke"' --info`
