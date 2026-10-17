import Foundation

/// Teksterne i notifikationerne: 10 milde varianter pr. slags, så det ikke er den samme hver gang (port af `messages.py`).
/// Varianten vælges ud fra tidspunktet (minutter siden 1970 modulo antallet), så den samme begivenhed altid giver den samme
/// tekst. Listerne tjekkes mod tests/fixtures/messages.json. {name} = barnets navn, {t} = klokkeslæt, {h} = timer.
public enum Messages {
    public enum Kind: String, CaseIterable, Sendable {
        case soonNap = "soon_nap", soonBed = "soon_bed", lateNap = "late_nap", lateBed = "late_bed", pump
    }

    static let soonNap: [String] = [
        "Snart lurtid, ca. kl. {t}. Måske en stille stund sammen først?",
        "Næste lur ca. kl. {t}. Et godt tidspunkt at skrue lidt ned for tempoet.",
        "Lurtiden nærmer sig (ca. kl. {t}). Dæmp lyset, og tag den med ro.",
        "{name} bliver nok træt snart. Næste lur ca. kl. {t}.",
        "Om lidt er det lurtid, ca. kl. {t}. Lidt nus og ro kan gøre det lettere.",
        "Næste lur ca. kl. {t}. Kig efter gaben og gnubbede øjne.",
        "Snart tid til en lur, ca. kl. {t}. I gør det godt.",
        "Lurtid ca. kl. {t}. Måske en sang eller en stille leg først?",
        "Næste lur ca. kl. {t}. Et lille pusterum til jer begge.",
        "Snart lurtid, ca. kl. {t}. Tag det i jeres eget tempo.",
    ]

    static let soonBed: [String] = [
        "Sengetid ca. kl. {t}. Tid til at finde aftenroen sammen.",
        "Aftenen nærmer sig, sengetid ca. kl. {t}. Dæmp lyset, og tag den med ro.",
        "{name} bliver nok træt snart. Sengetid ca. kl. {t}.",
        "Sengetid ca. kl. {t}. Måske bad, nattøj og en stille sang?",
        "Snart sengetid, ca. kl. {t}. I har klaret en hel dag. Godt gået.",
        "Sengetid ca. kl. {t}. Lidt ro og nærvær gør det lettere at falde i søvn.",
        "Dagen er ved at runde af. Sengetid ca. kl. {t}.",
        "Snart tid til natten, ca. kl. {t}. Tag den stille og roligt.",
        "Sengetid ca. kl. {t}. Kig efter gaben og gnubbede øjne.",
        "Aftenroen kan begynde nu. Sengetid ca. kl. {t}.",
    ]

    static let lateNap: [String] = [
        "{name} virker frisk endnu, og det er helt okay. Prøv stille og roligt en lur, når I er klar.",
        "Lurtiden er gået, men der er ingen grund til stress. Et roligt forsøg på en lur kan være godt nu.",
        "{name} er stadig vågen. Måske en lille pause, nye omgivelser eller en tur i barnevognen?",
        "Nogle dage vil søvnen bare ikke. Prøv blidt med en lur igen, og husk at trække vejret.",
        "{name} har været vågen lidt længe. Et stille hjørne og lidt nus kan hjælpe.",
        "Det er okay, at luren ikke er kommet endnu. Prøv igen i jeres eget tempo.",
        "Måske er {name} lige lidt for nysgerrig til at sove. Dæmp lyset, og prøv blidt igen.",
        "Lurtiden er gået. Du gør det godt, også når det driller. Prøv roligt en lur igen.",
        "{name} virker frisk. En stille stund kan måske hjælpe søvnen på vej.",
        "Ingen lur endnu? Det sker. Prøv igen, når I begge er klar.",
    ]

    static let lateBed: [String] = [
        "{name} virker frisk endnu, og det er helt okay. Prøv stille og roligt at putte til natten.",
        "Sengetiden er gået, men der er ingen grund til stress. Dæmp lyset, og find roen sammen.",
        "Nogle aftener tager det lidt længere. Prøv blidt at putte igen, og husk at trække vejret.",
        "{name} er stadig vågen. Lidt nus og en stille sang kan hjælpe natten på vej.",
        "Det er okay, at natten ikke er kommet endnu. Prøv igen i jeres eget tempo.",
        "Sengetiden er gået. Du gør det godt, også de aftener, hvor det driller.",
        "{name} har været vågen lidt længe. Et mørkt og stille rum kan gøre det lettere.",
        "Ingen søvn endnu? Det sker. Tag den med ro, og prøv igen om lidt.",
        "Måske er {name} lige lidt for nysgerrig til at sove. Prøv blidt at putte igen.",
        "Aftenen trækker ud, og det er helt okay. Snart er det nat for jer begge.",
    ]

    static let pump: [String] = [
        "Det er {h} timer siden sidste udpumpning (kl. {t}). Måske tid til en ny, når det passer dig.",
        "En venlig påmindelse: sidste udpumpning var kl. {t}. Husk også et glas vand til dig selv.",
        "{h} timer siden sidst (kl. {t}). Find et roligt øjeblik til udpumpning, når du kan.",
        "Tid til udpumpning? Sidste gang var kl. {t}. Du gør det godt.",
        "Det er {h} timer siden kl. {t}. Sæt dig godt til rette, og tag den med ro.",
        "En lille påmindelse om udpumpning (sidst kl. {t}). Husk at passe på dig selv også.",
        "Sidste udpumpning var for {h} timer siden (kl. {t}). Et godt tidspunkt til en ny?",
        "Udpumpning, når du er klar. Sidst kl. {t}. Måske lidt at spise og drikke imens?",
        "{h} timer siden sidste udpumpning (kl. {t}). Hvert lille skridt tæller.",
        "Tid til en pause med udpumpning? Sidst kl. {t}. Du klarer det flot.",
    ]

    public static func list(_ kind: Kind) -> [String] {
        switch kind {
        case .soonNap: soonNap
        case .soonBed: soonBed
        case .lateNap: lateNap
        case .lateBed: lateBed
        case .pump: pump
        }
    }

    /// Teksten til en besked. `when` vælger varianten. Uden navn: «den lille».
    public static func pick(_ kind: Kind, when: Date, name: String = "", t: String = "", h: String = "") -> String {
        let l = list(kind)
        let minutes = Int((when.timeIntervalSince1970 / 60).rounded(.down))
        let s = l[((minutes % l.count) + l.count) % l.count]
            .replacingOccurrences(of: "{name}", with: name.isEmpty ? "den lille" : name)
            .replacingOccurrences(of: "{t}", with: t)
            .replacingOccurrences(of: "{h}", with: h)
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
