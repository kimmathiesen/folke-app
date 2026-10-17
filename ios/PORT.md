# Huskeliste: rettelser fra `main` (webappen), som iPhone-appen også skal have

Arbejdsgang (også i CLAUDE.md):
- **Den, der retter på `main`**, tilføjer et punkt her i samme omgang og opdaterer `ios/PLAN.md`.
- **Mac-sessionen** starter med `git fetch && git merge origin/main`. Den laver de åbne punkter i Swift
  og sætter `[x]` med sin commit, fx `[x] … (ios: 1a2b3c4)`.
- Rene webting (CSS, iPad-layout i webappen) kommer ikke på listen.

Format: `- [ ] dato · commit på main · hvad · hvor i PLAN.md · facit`

## Åbne

- [x] 2026-10-17 · `5fd7869` (forbedring-web) · **Søvn i tal:** 14 dages søjler (nat/dag), gennemsnit for de seneste 7 dage mod
      ugen før (søvn i døgnet, nat, dag, lure, lurenes længde, sengetid, opvågning, opvågninger). Dage uden nat tæller ikke med.
      PLAN.md afsnit 5. Facit: `stats.py`, `tests/test_stats.py`, `tests/fixtures/stats/`. Lavet samtidig i Swift
      (`SleepStats.swift`, `StatsView.swift`, `FixtureTests.soevnITal`).

- [x] 2026-10-17 · `0463244` (forbedring-web) · **Glemt søvn og glemt nat:** «Tilføj glemt søvn» (start og slut med dato,
      lur/nat; ikke i fremtiden, højst 16 t, ikke overlappende) og kortet «Mangler natten?» med hans typiske tider.
      PLAN.md afsnit 3.10. Facit: `folke.missing_night`, `tests/test_missing.py`, `tests/fixtures/missing/`. Lavet samtidig
      i Swift (`MissingNight.swift`, `store.addSleep`, `FixtureTests.glemtNat`, `RecordsTests.tilfoejGlemtSoevn`).

- [x] 2026-10-17 · `a390da1` (forbedring-web) · **Mildere notifikationer:** 10 støttende varianter pr. slags (snart lur,
      snart sengetid, lurtiden/sengetiden er gået, udpumpning), valgt ud fra tidspunktet (minutter siden 1970 modulo 10).
      Uden navn: «den lille». PLAN.md afsnit 4. Facit: `messages.py`, `tests/test_messages.py`, `tests/fixtures/messages.json`.
      Lavet samtidig i Swift (`Messages.swift`, `FixtureTests.beskeder`).

- [x] 2026-10-11 · `a40f2c0` (forbedring-web) · **Urolig søvn:** de seneste 4 hele dage mod de 14 før; mindst 2 ting
      tydeligt dårligere giver et kort på Søvn-siden med en blid tekst (søvnregression ved 4 mdr., 8–10 mdr., 1 år,
      1½ år, 2 år, ellers en generel tekst). «Tak» skjuler det pr. enhed; kan slås fra under Indstillinger. Gratis.
      PLAN.md afsnit 3.9. Facit: `rough.py`, `tests/test_rough.py`, `tests/fixtures/rough/`. Lavet samtidig i Swift
      (`RoughPatch.swift`, `FixtureTests.uroligSoevn`).

- [x] 2026-10-08 · (se main, «Dagsplan: en kort lur efter kl. 17 er aftenluren») · En lur efter kl. 17 er altid aftenluren,
      også under 30 min. Når den er sovet, kommer kun sengetid: slutningen + `evening_gap` (75 % efter en kort aftenlur),
      uden at vente på hans normale sengetid. PLAN.md afsnit 3. Facit: `tests/test_dayplan.py`
      (`test_kort_aftenlur_er_aftenluren_og_sengetid_foelger`, `test_tidlig_aftenlur_giver_tidligere_sengetid`).
      Lavet samtidig i Swift (`DayPlanTests`).

- [x] 2026-10-06 · `08a003d` · Ringens midte viser næste lur/sengetid i stedet for klokkeslættet
      («Næste lur kl. 13.40», «Sengetid kl. 19.30»), og «Faldt i søvn kl. 09.25», mens han sover.
      PLAN.md afsnit 5, Forside → Ringen. Facit: `index.html`, `render()`. (ios: 81b26f3)
- [x] 2026-10-06 · `07bfd30` · Forklaringen under «Næste lur» på almindeligt dansk i stedet for «eget mønster
      (position N)». `predict()` giver også `basis`, `pos` og `bed_basis`. Varighed «1 t» i stedet for «1 t 0 min»
      (også i dagens søvnliste). PLAN.md afsnit 3.5 og 5, Forudsigelseskort. Facit: `index.html` (`why`, `dur`)
      og `tests/test_predict.py`. (ios: 81b26f3)
- [x] 2026-10-06 · `eeaa016` · **Dagsplan med genberegning:** resten af dagen (lure og sengetid). Kort lur (under 30 min)
      tæller ikke og giver et vindue på 75 %. For lidt dagsøvn eller en lur, der ikke kan nås, giver tidligere sengetid
      (højst 60 min). Misset lur giver «nu» på skærmen (kun der). Hans tal beskyttes mod korte lure og afvigere.
      UI: «Resten af dagen» på kortet, «Forventet vågen» under en lur, stiplede buer i ringen. Notifikationerne følger
      `predict()` = planens første punkt. PLAN.md afsnit 3 (helt omskrevet), 4 og 5. Facit: `folke.py` (`plan_day`,
      `_Model`) og `tests/test_dayplan.py`. (ios: 87857dc)
- [x] 2026-10-06 · `cfaa3f0` (lavet på ios) · **Sengetid ud fra data i stedet for faste regler:**
      aftenlur læres og planlægges (ingen fast rykning på 60 min, når en lur ikke kan nås), rykning efter mindre dagsøvn
      kun når hans egne dage viser det (`learned_shift`), korte «nætter» samme aften læses som aftenlure (`_normalize`),
      dage med manglende nat springes over, og gæt på lur/nat ved stop ud fra længden (`nap_at_stop`).
      Lavet i `folke.py` på `ios` (standalone styres af en anden session). Port til Swift sammen med dagsplanen ovenfor.
      PLAN.md afsnit 3. Facit: `tests/test_dayplan.py` (aftenlur-testene), `tests/test_app.py` (stop uden valg). (ios: 87857dc)

## Lavet

(ingen endnu)
