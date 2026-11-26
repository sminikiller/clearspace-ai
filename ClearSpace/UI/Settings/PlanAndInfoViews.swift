import StoreKit
import SwiftUI

/// Piani disponibili. Le funzioni di sicurezza non sono mai a pagamento.
struct PlanView: View {
    @Environment(AppEnvironment.self) private var env

    private var plan: PlanManager { env.plan }

    var body: some View {
        ReadableList {
            Section {
                if plan.monetizationEnabled {
                    DetailRow(label: "Piano attuale", value: plan.currentTier.title)
                } else {
                    InfoBanner(
                        text: "In questa versione tutte le funzioni sono sbloccate: gli acquisti non sono ancora attivi.",
                        systemImage: "gift.fill",
                        tint: Theme.keep
                    )
                }
            }

            tierSection(.free, features: [
                "Scansione di foto e video",
                "Categorie principali",
                "Modalità swipe",
                "Revisione ed eliminazione confermata",
                "Protezioni, annullamento e sessioni salvate"
            ])
            tierSection(.pro, features: Feature.allCases.filter { $0.requiredTier == .pro }.map { $0.title })
            tierSection(.proPlus, features: Feature.allCases.filter { $0.requiredTier == .proPlus }.map { $0.title })

            if plan.monetizationEnabled {
                purchaseSection
            }

            Section {
                Label("Revisione, conferma finale, protezioni e annullamento sono incluse in ogni piano.", systemImage: "checkmark.shield")
                    .font(.subheadline)
            }
        }
        .navigationTitle("Piani")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tierSection(_ tier: PlanTier, features: [String]) -> some View {
        Section(tier.title) {
            ForEach(features, id: \.self) { feature in
                Label(feature, systemImage: "checkmark")
                    .font(.subheadline)
            }
        }
    }

    private var purchaseSection: some View {
        Section {
            if plan.isLoading {
                ProgressView()
            }
            ForEach(plan.products, id: \.id) { product in
                Button {
                    Task {
                        await plan.purchase(product)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName)
                            Text(product.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(product.displayPrice)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            Button("Ripristina gli acquisti") {
                Task {
                    await plan.restorePurchases()
                }
            }
            if let message = plan.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Acquisti")
        }
    }
}

/// Spiega con trasparenza cosa iOS permette a un'app come ClearSpace e cosa riserva al sistema.
struct CapabilitiesInfoView: View {

    private struct Capability: Identifiable {
        let id: String
        let content: String
        let possibility: String
        let solution: String
        let systemImage: String
    }

    private let capabilities: [Capability] = [
        Capability(id: "photos", content: "Foto e video dell'iPhone", possibility: "Completa, con permesso",
                   solution: "Analisi, anteprima, selezione ed eliminazione", systemImage: "photo.on.rectangle"),
        Capability(id: "icloud-photos", content: "Foto e video di iCloud", possibility: "Tramite la libreria Foto sincronizzata",
                   solution: "Gestione con PhotoKit, con avviso sugli effetti della sincronizzazione", systemImage: "icloud"),
        Capability(id: "drive", content: "Documenti di iCloud Drive", possibility: "Con accesso autorizzato",
                   solution: "Analisi delle cartelle che scegli", systemImage: "folder"),
        Capability(id: "local", content: "Documenti locali", possibility: "Con accesso autorizzato",
                   solution: "Duplicati, analisi e pulizia", systemImage: "doc"),
        Capability(id: "audio", content: "Registrazioni audio", possibility: "Parziale",
                   solution: "File audio accessibili o importati in ClearSpace", systemImage: "waveform"),
        Capability(id: "apps", content: "App installate e loro dati", possibility: "Limitata",
                   solution: "Procedure guidate con gli strumenti di iOS", systemImage: "square.grid.2x2"),
        Capability(id: "caches", content: "WhatsApp, Messaggi, cache di altre app", possibility: "Nessun accesso diretto",
                   solution: "Guide agli strumenti offerti da ciascuna app", systemImage: "message"),
        Capability(id: "backup", content: "Backup iCloud e dati privati di altre app", possibility: "Non accessibili",
                   solution: "Istruzioni per gestirli nelle Impostazioni", systemImage: "arrow.clockwise.icloud")
    ]

    private let privacyPoints = [
        "Le analisi di immagini, documenti e audio avvengono sul dispositivo.",
        "Foto e documenti non vengono caricati su server esterni.",
        "L'indice locale contiene solo riferimenti e metadati, è cifrato ed è escluso dai backup.",
        "I permessi vengono chiesti solo quando servono e possono essere revocati in qualsiasi momento.",
        "Nessuna pubblicità e nessun tracciamento.",
        "Il nome del luogo di un viaggio viene richiesto ad Apple solo se tocchi «Mostra il luogo»."
    ]

    private let safetyPoints = [
        "Uno swipe non elimina mai nulla: aggiunge soltanto alla lista di revisione.",
        "Prima della conferma vedi l'elenco completo e gli effetti su iPhone e iCloud.",
        "Preferiti, album, cartelle e periodi che scegli restano protetti.",
        "Nessuna eliminazione parte dal solo giudizio di un'analisi automatica.",
        "Dopo ogni operazione l'esito viene verificato: eliminato, non riuscito o in attesa."
    ]

    var body: some View {
        ReadableList {
            Section {
                ForEach(capabilities) { capability in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: capability.systemImage)
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(capability.content)
                                .font(.subheadline.weight(.semibold))
                            Text(capability.possibility)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                            Text(capability.solution)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Cosa permette iOS")
            } footer: {
                Text("ClearSpace non dichiara accessi che il sistema non concede: dove non può agire direttamente ti guida allo strumento giusto.")
            }

            Section("Liberare spazio: iPhone e iCloud") {
                Text("Eliminare una foto con Foto di iCloud attivo la rimuove anche da iCloud e dagli altri dispositivi; resta recuperabile per 30 giorni.")
                    .font(.subheadline)
                Text("Per liberare solo spazio sull'iPhone, Apple prevede «Ottimizza spazio iPhone»: nessuna app può rimuovere la sola copia locale di una singola foto.")
                    .font(.subheadline)
                Text("Per i documenti di iCloud Drive, invece, è possibile rimuovere la copia scaricata lasciando il file nel cloud.")
                    .font(.subheadline)
            }

            Section("Sicurezza") {
                ForEach(safetyPoints, id: \.self) { point in
                    Label(point, systemImage: "checkmark.shield")
                        .font(.subheadline)
                }
            }

            Section("Privacy") {
                ForEach(privacyPoints, id: \.self) { point in
                    Label(point, systemImage: "hand.raised")
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Cosa può fare ClearSpace")
        .navigationBarTitleDisplayMode(.inline)
    }
}
