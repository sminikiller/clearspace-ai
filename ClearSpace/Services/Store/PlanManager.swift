import Foundation
import Observation
import StoreKit

/// Gestione dei piani (Gratuito, Pro, Pro Plus) con StoreKit 2.
/// Finché `AppConfiguration.monetizationEnabled` è `false` tutte le funzioni sono sbloccate
/// e lo Store non viene interrogato. Le funzioni di sicurezza non dipendono mai dal piano.
@MainActor
@Observable
final class PlanManager {

    private(set) var purchasedTier: PlanTier = .free
    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var message: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    /// Piano forzato dalle preferenze di sviluppo, se presente.
    @ObservationIgnored var developerTierProvider: @MainActor () -> PlanTier? = { nil }

    var monetizationEnabled: Bool { AppConfiguration.monetizationEnabled }

    var currentTier: PlanTier {
        guard monetizationEnabled else { return .proPlus }
        if let forced = developerTierProvider() { return forced }
        return purchasedTier
    }

    /// Le categorie senza requisito (`nil`) fanno parte del piano gratuito.
    func isUnlocked(_ feature: Feature?) -> Bool {
        guard let feature else { return true }
        return currentTier >= feature.requiredTier
    }

    func tier(forProductID productID: String) -> PlanTier {
        switch productID {
        case AppConfiguration.proPlusProductID: return .proPlus
        case AppConfiguration.proProductID: return .pro
        default: return .free
        }
    }

    func start() {
        guard monetizationEnabled, updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        guard monetizationEnabled else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let identifiers = [AppConfiguration.proProductID, AppConfiguration.proPlusProductID]
            let loaded = try await Product.products(for: identifiers)
            products = loaded.sorted { $0.price < $1.price }
            message = loaded.isEmpty ? "I piani non sono ancora disponibili sullo Store." : nil
        } catch {
            message = "Impossibile caricare i piani: \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var best = PlanTier.free
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement, transaction.revocationDate == nil else { continue }
            best = max(best, tier(forProductID: transaction.productID))
        }
        purchasedTier = best
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                    message = nil
                } else {
                    message = "L'acquisto non ha superato la verifica."
                }
            case .userCancelled:
                break
            case .pending:
                message = "Acquisto in attesa di approvazione."
            @unknown default:
                break
            }
        } catch {
            message = "Acquisto non riuscito: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = purchasedTier == .free ? "Nessun acquisto da ripristinare." : nil
        } catch {
            message = "Ripristino non riuscito: \(error.localizedDescription)"
        }
    }
}
