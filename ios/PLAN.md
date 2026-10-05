# iPhone-app: plan og specifikation

Mål: en native iPhone- og iPad-app i App Store, som andre forældre kan hente og bruge uden server, Docker
eller login. Den skal kunne alt det, webappen på branchen `standalone` kan, og mere til (Live Activity,
widgets, Siri). Kun Apple: data deles mellem forældrene via iCloud.

Webappen og serveren (`app.py`, `napper.py`, `store.py`, `index.html`) er **facit** for regler, tekster og
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

## 3. Forudsigelse (port af `napper.predict`)

Input: søvn de sidste 10 dage (kun afsluttede), fødselsdato, nu.

1. Sortér efter start. Ingen søvn betyder ingen forudsigelse.
2. **Vågenvinduer pr. position:** gå gennem par (forrige, næste). `pos = 0` hvis forrige er nat, ellers `pos + 1`.
   `gap` = næste.start − forrige.end i minutter. Kun `20 < gap < 480` tæller. Gem pr. position og i en samlet liste.
3. **Næste position:** gå gennem alle søvn: `pos = 0` ved nat, ellers `pos + 1`.
4. **Vindue:**
   - mindst 3 prøver for positionen: median af de sidste 7, kilde «eget mønster (position N)»
   - ellers mindst 5 vinduer i alt: median af de sidste 15, kilde «gennemsnit af alle vinduer»
   - ellers aldersstandard, kilde «aldersbaseret standard»

   Medianen er som Pythons `statistics.median`: ved et lige antal bruges gennemsnittet af de to midterste.
5. **Aldersstandard** (måneder = dage / 30,4):

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
6. `nextStart` = sidste søvns slut + vindue.
7. **Sengetid:** median af starttidspunkt (minutter efter midnat) for nattesøvn med start kl. 17 eller senere.
   Kræver mindst 3, ellers 19:30. Sengetiden lægges på `nextStart`s dato.
8. Er `nextStart` ≥ sengetid − 60 min, er resultatet **sengetid** på sengetidspunktet. Ellers er det **lur** på `nextStart`.
9. Resultat: kind (lur/sengetid), tid, vindue i minutter (afrundet), kilde, id på sidste søvn.

Facit: `tests/test_predict.py` (10 syntetiske dage med 3 lure og faste vinduer).

**Gæt på lur eller nat**, når en søvn startes: nat, hvis klokken er 18:00 eller senere, eller før 05:00. Ellers lur.

## 4. Notifikationer (lokale)

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
  - Forventet næste søvn vises som stiplet cirkel. Hvid prik markerer nu.
  - I midten: klokkeslæt og tæller (vågen siden / sover siden).
- **Start/Stop søvn** og Lur/Nat-valg, mens søvnen kører.
- **«Glemte du at trykke?»:** «Faldt i søvn kl.» og «Vågnede kl.».
  - Ligger tidspunktet i fremtiden, betyder det i går.
  - En start før forrige søvns slut afvises.
  - En opvågning før start afvises.
- **Forudsigelseskort:** «Næste lur ca. kl. 13:40», vindue og kilde.
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
- Forudsigelsen er vores egen (vågenvinduer pr. position fra `napper.py`, som er skrevet fra bunden til Baby Buddy).
  Navnet `napper.py` er internt og skal ikke bruges udadtil.
- Udseendet (døgnringen med himmel efter tid på dagen, månen, tavlen) kommer fra vores egen webapp.
- Appnavn, ikon og App Store-tekster skal være vores egne. Tjek varemærker og eksisterende appnavne, før navnet låses.

**Før lancering:** TestFlight til 20-30 forældre uden for familien (mødregrupper). Spørg, om de ville betale, og hvad de savner.
Afgør derefter prisen. Indtægter er skattepligtige: tjek CVR og moms (Apple afregner moms i EU, men indkomsten skal opgives).

## 10. Rækkefølge (milepæle)

1. **FolkeCore:** model, forudsigelse, notifikationsregler og WHO, med porterede tests. Ingen UI. *(færdig)*
2. **App-skelet:** Core Data og CloudKit, første opstart, forside med ring og start/stop. Kør i simulatoren. *(færdig)*
3. Resten af forsiden: glemte tryk, ret/slet, mad, udpumpning, forslag. *(færdig)*
4. Lokale notifikationer og indstillinger. *(færdig)*
5. Vækst og udpumpningshistorik. *(færdig)*
6. iCloud-deling mellem to konti og tavlen. Kræver betalt udviklerkonto, Team ID og endeligt bundle id.
7. Live Activity, widgets og App Intents.
8. Import fra serveren. TestFlight til familien.
9. **Folke Plus** (afsnit 9): StoreKit 2-engangskøb med familiedeling, 14 dages prøve, låste funktioner, «Gendan køb».
   Test med StoreKit-konfigurationsfil i simulatoren. TestFlight til forældre uden for familien.
10. Engelsk, privatlivspolitik, App Store.

Hver milepæl afsluttes med grønne tests, et skærmbillede fra simulatoren og en commit.
