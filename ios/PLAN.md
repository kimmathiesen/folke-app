# iPhone-app: plan og specifikation

Mål: en native iPhone- og iPad-app i App Store, som andre forældre kan hente og bruge uden server, Docker
eller login. Den skal kunne alt det, webappen på branchen `standalone` kan, og mere til (Live Activity,
widgets, Siri). Kun Apple: data deles mellem forældrene via iCloud.

Webappen og serveren (`app.py`, `folke.py`, `store.py`, `index.html`) er **facit** for regler, tekster og
udseende. Er noget uklart i denne plan, så læs koden på branchen `standalone`. Serveren kører videre for
familien, indtil appen kan overtage.

## 1. Grundvalg

| Emne | Valg | Begrundelse |
|---|---|---|
| Platform | iOS/iPadOS 17+ | Interaktive widgets, App Intents, moderne SwiftUI |
| UI | SwiftUI | |
| Data | Core Data med `NSPersistentCloudKitContainer` | Understøtter deling mellem iCloud-konti (`CKShare`). Tjek ved start, om SwiftData nu understøtter delte databaser. Ellers Core Data |
| Deling | `CKShare` på én «familie»-zone, sendt via `UICloudSharingController` | Mor opretter, far accepterer. Ingen server, intet login |
| Notifikationer | Lokale (`UNUserNotificationCenter`), planlagt på telefonen | Ingen push-server nødvendig |
| Fælles kode | Swift package `FolkeCore` (model, forudsigelse, regler, WHO) | Testbar uden UI, deles med widget og App Intents via App Group |
| Tests | Swift Testing / XCTest. Python-testene i `tests/` porteres som facit | |
| Sprog | Dansk først, engelsk med det samme via String Catalog | App Store uden for Danmark |

Krav til CloudKit-modellen: alle attributter valgfri eller med standardværdi, ingen unikke constraints,
alle relationer valgfri og med inverse. Brug UUID-felter som stabile id'er.

## 2. Datamodel

| Entitet | Felter | Bemærkninger |
|---|---|---|
| `Child` | id, name, birthDate, sex (boy/girl) | Ét barn i version 1 (flere senere) |
| `Sleep` | id, start, end (nil = i gang), nap (Bool), createdBy (mor/far) | En kørende søvn erstatter serverens «timer» |
| `Feeding` | id, time, kind (left/right/both/bottle/solid), amountMl, milk (breast/formula), note | |
| `Pumping` | id, time, amountMl, side (left/right/both, valgfri), minutes (valgfri) | |
| `Growth` | id, date, weightKg, lengthCm, headCm | Mindst én af de tre |
| `Stroke` | id, color, width, points (Data: [x,y] Float32), createdAt, createdBy | Tavlen: én post pr. streg (ingen konflikter) |
| `Settings` (delt) | features (breast, solids, pump), pumpRemindHours (standard 3), suggestion-svar | Fælles for familien |

Pr. enhed (`UserDefaults`, deles ikke): rolle (mor/far), beskedtyper til/fra, sidst sete tavleversion.

## 3. Forudsigelse og dagsplan (port af `folke.plan_day` og `folke.predict`)

Input: søvn de sidste 10 dage (kun afsluttede), fødselsdato, nu, og evt. starttidspunktet for en lur, der er i gang.
`predict()` er **første punkt i dagsplanen** (uden genberegning ved misset lur, afsnit 3.4). Notifikationer og
HA-sensor bruger `predict()`, skærmen bruger `plan_day()`.

Konstanter: kort lur < 30 min, vindue efter kort lur × 0,75, afvigere uden for 60–160 % af medianen,
sengetid højst 60 min frem, lurlængde 60 min uden data, aftenlur = dagens sidste lur med start kl. 17 eller senere
(45 min uden data), «nat» under 2 t, der slutter samme dag = aftenlur, underskud = mindst 30 min mindre dagsøvn,
rykning læres efter mindst 3 dage med underskud, en «dag» over 36 t (manglende nat) springes over.

**Hvorfor sengetiden ikke rykkes efter en fast regel** (analyse af Folkes data 29/9–6/10 2026): mindre dagsøvn gav
ikke tidligere sengetid. Dagen med mindst dagsøvn (3,3 t) gav sengetid 21:34, den tidligste (19:53) kom efter en dag
med masser af dagsøvn uden aftenlur. Han tager næsten hver dag en aftenlur 17:45–21:00, og natten starter 1–2 t efter.
Derfor: aftenluren planlægges, og sengetiden rykkes kun, hvis barnets egne data viser det.

### 3.1 Hans tal (`_Model`)

Gå gennem søvn sorteret efter start. Ingen søvn betyder ingen plan. Først læses en «nat» under 2 t, der sluttede samme
dag, som en lur (`_normalize`): ældre registreringer af aftenlure efter kl. 18 blev gemt som nat.

- **Kort lur:** en lur under 30 min, fx i barnevognen. Den tæller ikke som en af dagens lure og flytter ikke positionen.
  Vinduerne lige før og lige efter en kort lur bruges ikke i hans tal.
- **Position:** 0 efter natten, og +1 efter hver lur, der ikke er kort.
- **Vinduer:** `gap` = næste.start − forrige.end i minutter for hvert par, hvor ingen af dem er en kort lur.
  Kun `20 < gap < 480` gemmes, pr. position og i en samlet liste.
- **Lurlængder:** pr. lurnummer (1., 2., 3. lur på dagen, kun lure, der ikke er korte) og i en samlet liste.
- **Lure pr. dag:** antal lure, der ikke er korte, for hver hel dag mellem to nætter.
- **Aftener:** starttid i minutter for nattesøvn med start kl. 17 eller senere.
- **Hele dage** (mellem to nætter, under 36 t): dagsøvn (alle lure, også korte), natten starter, sidste søvns slut,
  og dagens aftenlur (sidste lur, der ikke er kort, med start kl. 17 eller senere), hvis der er en.

`robust(prøver, n)`: hvis der er mindst 4 prøver, fjernes dem uden for 0,6–1,6 × medianen. Derefter bruges de sidste `n`.
Medianen er som Pythons `statistics.median`: ved et lige antal bruges gennemsnittet af de to midterste.

| Tal | Regel |
|---|---|
| `window(pos)` | `robust(pos-prøver, 7)` har mindst 3: median, basis `own`, kilde «eget mønster (position N)». Ellers `robust(alle, 15)` har mindst 5: median, `all`, «gennemsnit af alle vinduer». Ellers aldersstandard, `age`, «aldersbaseret standard» |
| `nap_length(k)` | `robust(lurnummer k, 7)` har mindst 3: median. Ellers `robust(alle længder, 15)` har mindst 3: median. Ellers 60 |
| `naps()` | Median af de sidste 7 hele dage (afrundet), hvis der er mindst 3 dage. Ellers efter alder: under 4 mdr. 4, under 7 mdr. 3, under 15 mdr. 2, ellers 1 |
| `bed_min()` | Median af aftenerne, hvis der er mindst 3. Ellers 19:30 |
| `catnap_habit()` | Aftenlur på mindst 3 af de seneste 7 hele dage og på mindst halvdelen af dem |
| `catnap_length()` | `robust(aftenlurenes længder, 7)`: median. Ellers 45 |
| `evening_gap()` | `robust(natten starter − sidste søvns slut på dage med aftenlur, 7)`: median, hvis mindst 3. Ellers ingen |
| `normal_day_sleep()` | Median af dagsøvnen de seneste 7 hele dage, hvis mindst 3. Ellers summen af `nap_length(i)` for `i = 1 … naps()` |
| `learned_shift()` | Dage med dagsøvn ≤ median − 30 min og nat efter kl. 17: mindst 3 af dem, og medianen af (`bed_min` − nattens start) er mindst 15 min. Så den, højst 60. Ellers 0 |

**Aldersstandard for vinduet** (måneder = dage / 30,4):

| Alder | Vindue |
|---|---|
| under 2 mdr. | 60 min |
| under 3 mdr. | 75 min |
| under 4 mdr. | 90 min |
| under 6 mdr. | 120 min |
| under 9 mdr. | 150 min |
| under 12 mdr. | 180 min |
| under 18 mdr. | 210 min |
| ellers | 270 min |

### 3.2 Dagen indtil nu

- **I dag:** lure siden sidste nattesøvn.
- `k` = antal lure i dag, der ikke er korte. `pos = k`.
- `slept` = summen af alle lure i dag, også de korte.
- `win = window(pos)`. Var den sidste søvn en kort lur, ganges `win` med 0,75. Resultatet `short` er dens længde i minutter.
- Var den sidste søvn en aftenlur (start kl. 17 eller senere), han har `catnap_habit()`, og `evening_gap()` findes,
  er `win = evening_gap()`.
- `wake` = sidste søvns slut, og `t = wake + win`.
- **Lur i gang** (starttid `r`):
  - `wake = max(r + nap_length(k+1), nu)`. Den returneres som `wake`.
  - `k += 1`, `pos += 1`, og `slept` får `wake − r` lagt til.
  - Derefter `win = window(pos)` og `t = wake + win`.
  - Nattesøvn i gang giver ingen plan.
- `bed(t)` = `bed_min()` på `t`s dato.

### 3.3 Planen

Gentag højst 6 gange:
1. Er `t ≥ bed(t) − 60 min`, stop: så er det sengetid.
2. `L = nap_length(k+1)` og `end = t + L`.
3. Er `end + window(pos+1) > bed(t) + 30 min`, er der ikke plads til en hel lur og hans normale vindue bagefter. Stop:
   - har han `catnap_habit()`: tilføj en **aftenlur** `t … t + catnap_length()` (`catnap: true`), `slept += længden`,
     `wake` = dens slut, og husk `catnap_end`
   - ellers **droppes** luren (`dropped`)
4. Tilføj lur `t … end`. `k += 1`, `pos += 1`, `slept += L`, `wake = end`, `win = window(pos)` og `t = end + win`.

**Sengetid:**
- `shift` = `learned_shift()`, hvis den er over 0 og `slept ≤ normal_day_sleep() − 30`. Ellers 0.
- `floor` = `t`, hvis `shift = 0`. Ellers `wake + win × 0,75`.
- Er en aftenlur planlagt: `shift = 0` og `floor = catnap_end + (evening_gap() eller window(pos+1))`.
- Ellers, er en lur droppet (barn uden aftenlur): `shift = 60` og `floor = t` (nødløsning, ingen data siger andet).
- Ved misset lur (3.4) bruges `floor = max(floor, nu)`.
- **Sengetid** = `max(bed(t) − shift, floor)`.
- Det rapporterede `bed_shift` er minutter før `bed(t)`, mindst 0.

Uden afvigelser og uden lært rykning: sengetid = `max(bed, t)`. Er sengetiden allerede gået sent på aftenen, er det sengetid, når vinduet er gået.

### 3.4 Misset lur (kun til skærmen)

Gælder, når `replan = true`, der ikke er nogen lur i gang, nu > `t` + 15 min, og `t < bed(t) − 60` (det var en lur, ikke sengetid).
- `missed_at = t` og `t = nu`. Planen regnes derefter som i 3.3, så første lur er «nu».
- `predict()` bruger `replan = false`, så beskeden «… virker meget frisk» stadig kommer 15 min efter det oprindelige tidspunkt.

### 3.5 Resultat

`plan_day` returnerer:
- `items`: lure `{kind: "lur", start, end}` og til sidst `{kind: "sengetid", start}`
- `wake`, `missed_at`, `short`, `bed_shift`, `naps`, `catnap` (han plejer at tage en aftenlur), `last_id`
- en aftenlur i `items` har `catnap: true`
- for første punkt: `first_window`, `source`, `basis`, `pos` og `bed_basis` (`own`, hvis der er mindst 3 aftener, ellers `default`)

`predict` returnerer første punkt som `{kind, time, window_min, source, basis, pos, bed_basis, short, bed_shift, last_id}`.

Facit: `tests/test_predict.py` (uændret adfærd på normale dage) og `tests/test_dayplan.py` (hele dagen, faktisk opvågning, kort lur, misset lur, misset sidste lur, for lidt dagsøvn uden og med lært rykning, lur i gang, korte lure påvirker ikke hans tal, afvigere, aftenlur, kort første lur giver ikke tidlig sengetid, gæt ved stop, manglende nat). Samme syntetiske historik: 10 dage med nat 19:30–06:30 og lure 08:30–09:30, 12:00–13:30 og 16:30–17:00.

**Gæt på lur eller nat**, når en søvn startes: nat, hvis klokken er 18:00 eller senere, eller før 05:00. Ellers lur.
**Når den stoppes** uden at brugeren har valgt Lur/Nat (`nap_at_stop`): som ved start, men en «nat» under 2 t, der slutter
samme dag, er en lur (aftenlur). Webappen sender kun `nap`, hvis brugeren har trykket Lur eller Nat.

## 4. Notifikationer (lokale)

Tidspunktet er `predict()` (afsnit 3): første punkt i dagsplanen uden genberegning ved misset lur.
En kort lur eller en rykket sengetid flytter altså også beskeden.

Planlæg forfra, hver gang data ændres lokalt eller fra iCloud (`NSPersistentStoreRemoteChange`) og når appen
åbnes. Fjern ventende notifikationer, når en søvn startes.

| Type (id) | Hvornår | Titel og tekst | Standard pr. enhed |
|---|---|---|---|
| `sleep_soon` | 30 min før forudsagt tid | «Søvn»: «Tid til at slappe af. Næste lur ca. kl. 13:40» (sengetid: «Sengetid ca. kl. 19:30») | Til |
| `overdue` | 15 min efter forudsagt tid, hvis ingen søvn er startet | «Søvn»: «Folke virker meget frisk. Prøv alligevel en lur» (sengetid: «… at putte til natten») | Til |
| `pump` | X timer efter sidste udpumpning (fælles indstilling, standard 3) | «Udpumpning»: «Det er 3 timer siden sidste udpumpning (kl. 09:15)» | Fra |

- Hver notifikation planlægges højst én gang pr. forudsigelse eller udpumpning. Fast id pr. type, så en ny planlægning erstatter den gamle.
- `overdue` sendes ikke mere end 2 timer for sent.
- `pump` sendes ikke mellem 22 og 7. Falder tidspunktet om natten, flyttes det til kl. 7.
- Barnets navn indsættes. Uden navn bruges «Babyen».
- Kendt begrænsning: når den anden forælder starter en søvn, ryddes notifikationen på denne telefon først, når ændringen er synkroniseret fra iCloud.

## 5. Skærme og funktioner (som webappen)

**Første opstart:** velkomst med barnets navn, fødselsdato og «Jeg er mor/far» (gemmes på enheden).
Tilbyd «Inviter din partner» (iCloud-deling) og «Importér fra Folke-server» (afsnit 8).

**Forside:**
- Overskrift «Hej Folkes mor». Genitiv: navne på s, x eller z får apostrof (Mads').
- **Ringen:** 24 timer, midnat i bunden og middag i toppen.
  - Yderste ring i døgnets farver.
  - Indre ring med dagens søvn: lur `#a9c2ff`, nat `#8b7cf6`. En kørende søvn pulserer.
  - Forventet næste søvn (første punkt i dagsplanen) vises som stiplet cirkel. Planlagte lure resten af dagen
    vises som stiplede buer i `rgba(169,194,255,.45)`, streg 2 / mellemrum 6. Hvid prik markerer nu.
  - I midten: «Næste lur kl. 13.40» / «Sengetid kl. 19.30» / «Næste lur: nu» (misset lur), mens han sover
    «Faldt i søvn kl. 09.25», og tæller (vågen siden / sover siden).
- **Start/Stop søvn** og Lur/Nat-valg, mens søvnen kører.
- **«Glemte du at trykke?»:** «Faldt i søvn kl.» og «Vågnede kl.».
  - Ligger tidspunktet i fremtiden, betyder det i går.
  - En start før forrige søvns slut afvises.
  - En opvågning før start afvises.
- **Forudsigelseskort** (bygger på dagsplanen, afsnit 3):
  - Normalt: «Næste lur» / «Sengetid», «ca. kl. 13.40» og en forklaring på almindeligt dansk (aldrig «position N»):
    - lur, `basis own`: «Vågen ca. 2 t 30 min efter 1. lur · ud fra de seneste dage» (pos 0: «efter natten»)
    - lur, `basis all`: «Vågen ca. 2 t 15 min · ud fra de seneste dage»
    - lur, `basis age`: «Vågen ca. 1 t 30 min · typisk for alderen (for lidt data endnu)»
    - efter kort lur: «Vågen ca. 1 t 52 min efter en kort lur på 12 min (kortere end normalt)»
    - sengetid: «Sengetid ud fra de seneste aftener» / «Typisk sengetid (for lidt data endnu)», eller ved
      `bed_shift`: «Rykket 25 min frem efter en dag med mindre søvn end normalt»
  - Misset lur: «Næste lur» / «Nu» / «Luren kl. 10.00 blev ikke til noget. Prøv at putte nu, så er resten af dagen flyttet.»
    Er næste punkt sengetid: «Luren kl. 16.30 blev ikke til noget, så sengetid er rykket 60 min frem.»
  - Lur i gang: «Forventet vågen» / «ca. kl. 11.47» / «Ud fra hvor længe hans lure plejer at vare».
  - Under en streg: «Resten af dagen» med «Lur ca. 14.47–15.17» og «Sengetid ca. 18.30 (60 min tidligere)».
  - Varighed: «45 min», «1 t», «2 t 30 min» (aldrig «0 min»).
- **Mad:**
  - Amning venstre/højre/begge.
  - Flaske: ml (0 < ml ≤ 500), modermælk eller erstatning.
  - Fast føde med note (kun når slået til).
  - Linje med sidste måltid.
- **Udpumpning:**
  - ml (0 < ml ≤ 1000), side, minutter (1–180) og tidspunkt.
  - «I dag: 3 gange · 340 ml · sidst kl. 14.20».
- **Dagens søvn:** liste med varighed og samlet søvn. Tryk for at rette eller slette.
  - Slut skal være efter start og må ikke ligge i fremtiden.
  - Sletning kræver to tryk.

**Udpumpning (historik):**
- Søjlegraf over 14 dage med i dag i gul og en stiplet linje for gennemsnit. Gennemsnittet regnes kun af hele dage med udpumpning.
- Liste over de seneste 7 dage. Tryk for at rette eller slette.

**Vækst:**
- Vægt (0,5–30 kg), længde (30–120 cm) og hovedomfang (25–60 cm). Datoen må ikke ligge i fremtiden.
- WHO-kurver (2006) med P3/P15/P50/P85/P97, 0–24 mdr. og percentil pr. måling.
- Kurverne vises op til 12 mdr., til barnet er 9 mdr., derefter op til 24.
- Køn vælges i indstillinger.
- Data og formler: `who.py`. Facit: `tests/test_who.py`.
- **Tøjstørrelse (for begge forældre):** sidste længdemåling fremskrives langs sin egen percentil
  (samme z-værdi på WHO-kurven) til i dag. Størrelsen er den mindste danske babystørrelse (44, 50, 56, 62, 68, 74, 80, 86,
  92, 98), der er mindst lige så lang som barnet. Desuden hvornår næste størrelse passer: «Str. 74 om ca. 5 uger».
  Kun 0-24 mdr. og kun med en længdemåling. Skrives tydeligt som et skøn (størrelser varierer mellem mærker).
  Linjen med næste størrelse kan slås fra under Indstillinger («Vis næste tøjstørrelse», pr. enhed, standard til).

**Tavlen** (tryk på månen):
- Delt kridttavle med fast format 3:4, så tegningen ser ens ud på alle enheder.
- Fire farver: `#f4f1ea`, `#ff8fa3`, `#ffd27a`, `#8fb0ff`. Stregtykkelse 0,012 × bredden. Punkter gemmes i 0..1.
- Fortryd sidste streg og «Visk ud» (to tryk). Begge gælder for begge forældre.
- «Sidst ændret af far kl. 21.14».
- Stjernerne ved månen blinker, når der er nyt, man ikke har set.

**Indstillinger:**
- Barnets navn og «Jeg er mor/far».
- Amning, fast føde og udpumpning til/fra.
- Påmindelse om udpumpning efter 2–6 timer.
- Beskedtyper på denne enhed.
- Vækstkurver: dreng/pige.
- Deling med partner.
- Import og eksport.

**Forslag:** de vises på forsiden. Intet ændres uden svar.
- Svarmuligheder: Ja / Ikke nu (30 dage) / Aldrig.
- «Fast føde» ved 6 mdr., hvis det ikke allerede er slået til.
- «Skjul Amning», hvis der ikke er registreret amning i 21 dage.

**Udseende:**
- Kopiér farvetabellerne `ST` (ringen) og `SKY` (baggrunden) fra `index.html` på branchen `standalone`.
- Baggrunden følger tiden på dagen, med et skær øverst i ringens farve.
- iPad: to kolonner fra 900 pt bredde.

## 6. Ekstra i appen

- **Live Activity:** kørende søvn på låseskærm og Dynamic Island.
  - Brug `Text(timerInterval:)`, så den kan opdateres uden server.
  - Startes på den telefon, der starter søvnen. Den anden telefon starter sin egen, når ændringen kommer fra iCloud, mens appen er åben. Push-to-start kræver server og bruges ikke.
- **Widgets:** «Næste lur ca. 13:40» og «Vågen i 1 t 20 min» på hjemmeskærm og låseskærm, plus en knap til at starte og stoppe søvn (interaktiv widget).
- **Siri og Genveje (App Intents):** start søvn, stop søvn, log udpumpning (ml), log flaske (ml).

## 7. App Store

- Betalingsmodel: se afsnit 9.
- Betalt Apple Developer-konto. Bundle id og appnavn besluttes. Navnet «Folke» er familiens barns navn, så overvej et neutralt navn.
- Privatlivspolitik på en webadresse. Data forlader kun telefonen via brugerens egen iCloud, så «Data Not Collected» bør kunne vælges. Tjek det.
- Tekst om, at forudsigelser og vækstkurver er vejledende og ikke medicinsk rådgivning.
- Tjek licensen for WHO's vækstdata, før de distribueres.
- TestFlight til familien først.

## 8. Import fra den nuværende server

`GET /api/export` på stand-alone-serveren giver en JSON-fil:

- `child`, `sleep`, `timer`, `feeding` og `pumping`: rækker med kolonnerne fra `MIGRATIONS` i `store.py`.
  Tider er ISO-tekst i UTC.
- Feeding:
  - `method` er «left breast», «right breast», «both breasts», «bottle» eller «parent fed».
  - `type` er «breast milk», «formula» eller «solid food».
- `growth`: `[{id, date, w, l, h}]`.
- `prefs`: features, `sex`, `child_name`, `pump_remind`.

Appen importerer filen via filvælgeren (eller via Del → Folke). En kørende `timer` bliver til `Sleep` uden slut.
Gentaget import må ikke give dubletter: brug serverens id som nøgle.

## 9. Betalingsmodel

Mål: en lille, ærlig indtægt uden at gå på kompromis med privatlivet. Ingen server betyder næsten ingen driftsudgifter,
så prisen kan holdes lav.

**Model: gratis app med «Folke Plus» som engangskøb** (StoreKit 2, non-consumable).

| Gratis | Folke Plus |
|---|---|
| Start/stop søvn, ringen, dagens søvn, glemte tryk, ret/slet | Forudsigelse af næste lur og sengetid (kortet og den stiplede cirkel) |
| Mad og udpumpning, udpumpningshistorik | Notifikationer: `sleep_soon`, `overdue` og `pump` |
| **Deling med partner** (iCloud) og tavlen | Widgets, Live Activity og Siri/Genveje |
| Import fra Folke-server | Vækstkurver med percentiler (målinger kan altid indtastes og ses som liste) |

- **Pris:** 149 kr. som engangskøb (prøv evt. 199 kr.). Bevidst langt under konkurrenter, fx Napper (ca. 500 kr. engangs) og
  abonnementsapps som Huckleberry. «Intet abonnement» er et salgsargument.
- **Prøveperiode:** alt i Plus er åbent de første 14 dage fra første opstart. Forudsigelserne bliver først gode efter en uges data,
  så brugeren skal nå at opleve dem. Efter prøven vises Plus-funktionerne låst med en kort forklaring, aldrig som pop-op midt i brugen.
- **Familiedeling slået til** på købet, så partneren også får Plus. Deling mellem forældrene må aldrig kræve betaling: invitationen
  er appens vigtigste vej til nye brugere.
- **Ingen reklamer, intet salg af data, ingen analyse-SDK'er.** Så kan «Data Not Collected» vælges i App Store.
- Køb gendannes via «Gendan køb» under Indstillinger. Status læses med `Transaction.currentEntitlements` og gemmes ikke på en server.
- Data forsvinder aldrig, hvis Plus udløber eller ikke købes: alt registreret kan stadig ses og eksporteres.

**Ikke en kopi af Napper eller andre apps.** Vi har ikke kigget i deres kode, tekster eller design og skal heller ikke:
- Forudsigelsen er vores egen (vågenvinduer pr. position fra `folke.py`, som er skrevet fra bunden til Baby Buddy).
- Alt i projektet er navngivet efter Folke. Motoren hed tidligere `napper.py` og er omdøbt for at undgå enhver forveksling.
- Udseendet (døgnringen med himmel efter tid på dagen, månen, tavlen) kommer fra vores egen webapp.
- Appnavn, ikon og App Store-tekster skal være vores egne. Tjek varemærker og eksisterende appnavne, før navnet låses.
- **Måske et redesign før lancering.** Nuværende udseende er porteret 1:1 fra familiens webapp og er godt til os selv.
  Før App Store bør vi vurdere, om det skal have et mere gennemarbejdet og genkendeligt udtryk: eget ikon og logo,
  farver og typografi, illustrationer, tilgængelighed (Dynamic Type, VoiceOver, kontrast) og et lyst tema. Tag stilling
  efter TestFlight med forældre uden for familien (milepæl 9), så redesignet bygger på deres feedback og ikke på gæt.

**Før lancering:** TestFlight til 20-30 forældre uden for familien (mødregrupper). Spørg, om de ville betale, og hvad de savner.
Afgør derefter prisen. Indtægter er skattepligtige: tjek CVR og moms (Apple afregner moms i EU, men indkomsten skal opgives).

## 10. Rækkefølge (milepæle)

1. **FolkeCore:** model, forudsigelse, notifikationsregler og WHO, med porterede tests. Ingen UI. *(færdig)*
2. **App-skelet:** Core Data og CloudKit, første opstart, forside med ring og start/stop. Kør i simulatoren. *(færdig)*
3. Resten af forsiden: glemte tryk, ret/slet, mad, udpumpning, forslag. *(færdig)*
4. Lokale notifikationer og indstillinger. *(færdig)*
5. Vækst og udpumpningshistorik. *(færdig)*
6. iCloud-deling mellem to konti og tavlen (tavlen lokalt er færdig; deling mangler). Kræver betalt udviklerkonto, Team ID og endeligt bundle id. App Group `group.dk.folkeapp.folke` skal også oprettes på kontoen.
7. Live Activity, widgets og App Intents. *(færdig, testet i simulatoren; Siri-sætninger og låseskærm-widgets er ikke afprøvet)*
8. **Skjult** import fra Folke-serveren (kun i egne builds: debug og TestFlight, aldrig i App Store-versionen, da andre
   brugere ikke har en server). TestFlight til familien.
9. **Folke Plus** (afsnit 9): StoreKit 2-engangskøb med familiedeling, 14 dages prøve, låste funktioner, «Gendan køb».
   Test med StoreKit-konfigurationsfil i simulatoren. TestFlight til forældre uden for familien.
10. Evt. redesign (afsnit 9), engelsk, privatlivspolitik, privacy manifest, eksport som CSV (dine data er dine, fx til
    sundhedsplejersken), App Store.

Ud over milepælene (lavet uden udviklerkonto): app-ikon, baggrundsopdatering af notifikationer (`BGAppRefreshTask`,
skal afprøves på telefon), tavlen lokalt (deling kommer med milepæl 6) og tøjstørrelse (afsnit 5, Vækst).
Tavlen i appen viser «Sidst ændret» ud fra seneste streg (fortryd og «Visk ud» registreres ikke som ændring).

Hver milepæl afsluttes med grønne tests, et skærmbillede fra simulatoren og en commit.
