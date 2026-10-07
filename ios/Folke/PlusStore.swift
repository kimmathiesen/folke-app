import FolkeCore
import Observation
import StoreKit

/// Køb af Folke Plus med StoreKit 2 (PLAN.md afsnit 9). Status læses fra `Transaction.currentEntitlements`
/// og gemmes kun i App Group (`FolkeShared.plusPurchased`), så widgets og intents kan se den. Ingen server.
@MainActor @Observable
final class PlusStore {
    private(set) var product: Product?
    private(set) var busy = false
    var message: String?
    /// Kaldes, når købet ændrer sig (køb, gendannet, refunderet, familiedeling)
    var onChange: () -> Void = {}
    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refreshEntitlement()
            }
        }
        Task { await load() }
    }

    func load() async {
        product = try? await Product.products(for: [Plus.productID]).first
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Plus.productID, t.revocationDate == nil { owned = true }
        }
        if FolkeShared.plusPurchased != owned {
            FolkeShared.plusPurchased = owned
            onChange()
        }
    }

    func buy() async {
        guard let product, !busy else { return }
        busy = true
        defer { busy = false }
        message = nil
        do {
            switch try await product.purchase() {
            case .success(let v):
                if case .verified(let t) = v { await t.finish() }
                await refreshEntitlement()
            case .pending:
                message = "Købet venter på godkendelse (fx «Spørg før køb»)."
            default:
                break
            }
        } catch {
            message = "Købet kunne ikke gennemføres. Prøv igen."
        }
    }

    /// «Gendan køb»: henter køb fra App Store (fx på en ny telefon eller via familiedeling).
    func restore() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refreshEntitlement()
        message = FolkeShared.plusPurchased ? nil : "Der blev ikke fundet et køb af Folke Plus på denne Apple-konto."
    }
}
