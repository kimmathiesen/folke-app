import FolkeCore
import Foundation

/// Midlertidig synkronisering med familiens egen Folke-server, indtil iCloud er slået til (milepæl 6).
/// Kun i egne builds. Serveren er facit: handlinger sendes til dens API, og bagefter hentes `GET /api/export`
/// og spejles ind i databasen (`mirrorServerExport`). Uden forbindelse til serveren gemmes intet.
@MainActor final class ServerSync {
    /// Adressen gemmes kun på enheden, fx «https://folke.mathiesen.pro» eller «http://192.168.1.10:6661». Tom = slået fra.
    static var url: String {
        get { FolkeShared.defaults.string(forKey: "folke.serverURL") ?? "" }
        set { FolkeShared.defaults.set(newValue, forKey: "folke.serverURL") }
    }

    let base: URL
    private(set) var lastExport: Data?
    private(set) var lastPull: Date?
    /// Serverens fingeraftryk af seneste eksport (svar 304 = intet nyt)
    private var etag: String?

    init?(_ text: String = ServerSync.url) {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix("/") { t.removeLast() }
        // Uden «http(s)://»: et domæne (fx folke.mathiesen.pro) får https, en IP-adresse eller et lokalt navn
        // på hjemmenetværket (fx 192.168.1.10:6661, tower.local) får http
        if !t.isEmpty && !t.contains("://") {
            let host = t.split(separator: ":").first.map(String.init) ?? t
            let local = host.allSatisfy { $0.isNumber || $0 == "." } || host.hasSuffix(".local") || !host.contains(".")
            t = (local ? "http://" : "https://") + t
        }
        guard !t.isEmpty, let u = URL(string: t), u.host != nil else { return nil }
        base = u
    }

    enum Failure: LocalizedError {
        case server(String)
        case unsupported
        case offline(String)

        var errorDescription: String? {
            switch self {
            case .server(let m): m
            case .unsupported: "Serveren kan ikke det her endnu. Opdatér Folke-serveren."
            case .offline(let m): "Ingen forbindelse til Folke-serveren (\(m))"
            }
        }
    }

    /// Hent serverens data og spejl dem ind. Giver true, hvis noget var ændret.
    /// Et mislykket forsøg (fx et kort hak i forbindelsen) prøves igen én gang efter 2 sek.
    func pull(into store: FolkeStore) async throws -> Bool {
        let (data, status, tag): (Data, Int, String?)
        do {
            (data, status, tag) = try await fetchExport()
        } catch Failure.offline {
            try await Task.sleep(for: .seconds(2))
            (data, status, tag) = try await fetchExport()
        }
        lastPull = .now
        if status == 304 || data == lastExport { return false }
        try store.mirrorServerExport(data)
        lastExport = data
        etag = tag
        return true
    }

    private func fetchExport() async throws -> (Data, Int, String?) {
        var r = URLRequest(url: base.appending(path: "/api/export"), cachePolicy: .reloadIgnoringLocalCacheData,
                           timeoutInterval: 10)
        if let etag, lastExport != nil { r.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await load(r)
        if response.statusCode == 304 { return (Data(), 304, etag) }
        try check(data, response)
        return (data, response.statusCode, response.value(forHTTPHeaderField: "ETag"))
    }

    /// Send en handling. `body` bliver til JSON.
    func send(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws {
        _ = try await request(method, path, body)
    }

    private func request(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> Data {
        var r = URLRequest(url: base.appending(path: path), timeoutInterval: 10)
        r.httpMethod = method
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await load(r)
        try check(data, response)
        return data
    }

    private func load(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: r)
            guard let http = response as? HTTPURLResponse else { throw Failure.offline("intet svar") }
            return (data, http)
        } catch let f as Failure {
            throw f
        } catch {
            throw Failure.offline(error.localizedDescription)
        }
    }

    private func check(_ data: Data, _ response: HTTPURLResponse) throws {
        let status = response.statusCode
        if status == 404 || status == 405 { throw Failure.unsupported }
        if !(200..<300).contains(status) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw Failure.server(msg ?? "Serveren svarede \(status)")
        }
    }

    // MARK: Tidspunkter i serverens format (serveren regner i dansk tid)

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Copenhagen") ?? .current
        return c
    }()

    /// «HH:MM» (serveren lægger det i dag, eller i går, hvis det ligger i fremtiden)
    static func clock(_ d: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// «YYYY-MM-DDTHH:MM» i dansk tid
    static func local(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        return String(format: "%04d-%02d-%02dT%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// «YYYY-MM-DD»
    static func day(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
