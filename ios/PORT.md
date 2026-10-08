# Huskeliste: rettelser fra `main` (webappen), som iPhone-appen også skal have

Arbejdsgang (også i CLAUDE.md):
- **Den, der retter på `main`**, tilføjer et punkt her i samme omgang og opdaterer `ios/PLAN.md`.
- **Mac-sessionen** starter med `git fetch && git merge origin/main`. Den laver de åbne punkter i Swift
  og sætter `[x]` med sin commit, fx `[x] … (ios: 1a2b3c4)`.
- Rene webting (CSS, iPad-layout i webappen) kommer ikke på listen.

Format: `- [ ] dato · commit på main · hvad · hvor i PLAN.md · facit`

## Åbne

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
