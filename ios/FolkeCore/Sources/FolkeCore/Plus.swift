import Foundation

/// Folke Plus (PLAN.md afsnit 9): engangskøb med familiedeling og 14 dages prøve fra første opstart.
/// Gratis: søvn, mad, udpumpning, deling, tavlen, næste lur/sengetid (`Predictor.basic`) og notifikationer.
/// Plus: dagsplanen med løbende tilpasning, widgets/Live Activity/Siri og vækstkurver.
public enum Plus {
    public static let productID = "dk.folkeapp.folke.plus"
    public static let trialDays = 14

    public enum Status: Equatable, Sendable {
        case purchased
        case trial(daysLeft: Int)
        case locked

        public var unlocked: Bool { self != .locked }

        /// Kort tekst til Indstillinger
        public var text: String {
            switch self {
            case .purchased: "Folke Plus er købt. Tak for støtten!"
            case .trial(let d): d == 1 ? "Prøveperiode: 1 dag tilbage" : "Prøveperiode: \(d) dage tilbage"
            case .locked: "Prøveperioden er slut"
            }
        }
    }

    /// Status ud fra køb og første opstart. Prøven gælder til og med dag 14 (hele kalenderdage).
    public static func status(purchased: Bool, trialStart: Date?, now: Date = .now, calendar: Calendar = .current) -> Status {
        if purchased { return .purchased }
        guard let trialStart else { return .trial(daysLeft: trialDays) }
        let used = calendar.dateComponents([.day], from: calendar.startOfDay(for: trialStart),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        let left = trialDays - max(0, used)
        return left > 0 ? .trial(daysLeft: left) : .locked
    }

    /// Hvad der er låst, og hvorfor (vises på kortet i stedet for funktionen, aldrig som pop-op)
    public enum Feature: Sendable {
        case extensions, growthCurves

        public var lockedText: String {
            switch self {
            case .extensions: "Widgets, Live Activity og Siri er med i Folke Plus."
            case .growthCurves: "Vækstkurver og percentiler er med i Folke Plus. Målingerne kan stadig skrives ind og ses herunder."
            }
        }
    }
}
