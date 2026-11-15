import SwiftUI

/// Centro iCloud: Foto di iCloud, iCloud Drive e percorsi guidati per gli altri dati.
/// Mostra solo ciò che l'app può davvero rilevare: il totale del piano iCloud non è leggibile
/// da un'app e, se lo vuoi vedere nella dashboard, va inserito a mano.
struct ICloudCenterView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var totalText = ""
    @State private var usedText = ""
    @State private var toast: String?

    private var summary: CatalogSummary { env.store.summary }

    var body: some View {
        List {
            photosSection
            driveSection
            otherDataSection
            quotaSection
        }
        .navigationTitle("Centro iCloud")
        .onAppear {
            if let quota = env.preferences.values.manualICloudQuota {
                totalText = String(format: "%.0f", quota.totalGB)
                usedText = String(format: "%.0f", quota.usedGB)
            }
        }
        .toast($toast)
    }

    // MARK: - Foto di iCloud

    private var photosSection: some View {
        Section {
            Picker("Foto di iCloud", selection: env.preferences.binding(\.iCloudPhotosState)) {
                ForEach(ICloudPhotosState.allCases, id: \.self) { state in
                    Text(state.title).tag(state)
                }
            }
            DetailRow(label: "Foto e video analizzati", value: Format.bytes(summary.libraryBytes))
            DetailRow(label: "Originali presenti solo su iCloud", value: Format.bytes(summary.cloudOnlyLibraryBytes))

            VStack(alignment: .leading, spacing: 8) {
                Label("Eliminare una foto", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                Text("Con Foto di iCloud attivo, la foto viene rimossa anche da iCloud e dagli altri dispositivi. Resta recuperabile per 30 giorni in Eliminati di recente.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Label("Liberare solo spazio sull'iPhone", systemImage: "iphone")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                Text("Per le foto già sincronizzate si usa «Ottimizza spazio iPhone»: gli originali restano su iCloud e iOS gestisce le copie locali. Nessuna app può rimuovere soltanto la copia locale di una singola foto.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            if let guide = AppGuides.guide(withID: "icloud-optimize") {
                NavigationLink {
                    GuideDetailView(guide: guide)
                } label: {
                    Label(guide.title, systemImage: guide.systemImage)
                }
            }
            if let guide = AppGuides.guide(withID: "icloud-recently-deleted") {
                NavigationLink {
                    GuideDetailView(guide: guide)
                } label: {
                    Label(guide.title, systemImage: guide.systemImage)
                }
            }
        } header: {
            Text("Foto di iCloud")
        } footer: {
            Text("iOS non comunica alle app se Foto di iCloud è attivo: indicalo tu. Se viene trovato un originale presente solo online, lo stato passa da solo ad «Attivo».")
        }
    }

    // MARK: - iCloud Drive

    private var driveSection: some View {
        Section {
            let stat = summary.stat(StorageSource.iCloudDrive)
            DetailRow(label: "File analizzati", value: "\(Format.count(stat.count)) · \(Format.bytes(stat.bytes))")
            CollectionLink(collection: .cloudOnlyFiles)
            CollectionLink(collection: .downloadedCloudFiles)
            NavigationLink {
                EvictLocalCopiesView()
            } label: {
                Label("Libera spazio sul dispositivo", systemImage: "icloud.and.arrow.down")
            }
            NavigationLink {
                DocumentsHubView()
            } label: {
                Label("Cartelle e duplicati", systemImage: "folder")
            }
        } header: {
            Text("iCloud Drive")
        } footer: {
            Text("Per i documenti di iCloud Drive è possibile rimuovere la sola copia scaricata, lasciando il file disponibile nel cloud.")
        }
    }

    // MARK: - Altri dati

    private var otherDataSection: some View {
        Section {
            ForEach(AppGuides.iCloud.filter { $0.id != "icloud-optimize" && $0.id != "icloud-recently-deleted" }) { guide in
                NavigationLink {
                    GuideDetailView(guide: guide)
                } label: {
                    GuideRow(guide: guide, isDone: env.history.isChecked(guide.id))
                }
            }
        } header: {
            Text("Altri dati iCloud")
        } footer: {
            Text("Backup e dati delle altre app non sono accessibili a ClearSpace: questi percorsi ti guidano nelle Impostazioni di Apple.")
        }
    }

    // MARK: - Piano

    private var quotaSection: some View {
        Section {
            HStack {
                Text("Spazio totale del piano (GB)")
                Spacer()
                TextField("200", text: $totalText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
            }
            HStack {
                Text("Spazio usato (GB)")
                Spacer()
                TextField("0", text: $usedText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
            }
            Button("Salva") {
                saveQuota()
            }
            if env.preferences.values.manualICloudQuota != nil {
                Button("Rimuovi questi dati", role: .destructive) {
                    env.preferences.update { $0.manualICloudQuota = nil }
                    totalText = ""
                    usedText = ""
                }
            }
        } header: {
            Text("Il tuo piano iCloud")
        } footer: {
            Text("Dati inseriti da te, mostrati nella Home con la dicitura «inserito da te». Li trovi in Impostazioni → [il tuo nome] → iCloud.")
        }
    }

    private func saveQuota() {
        let total = Double(totalText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let used = Double(usedText.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard total > 0, used >= 0, used <= total else {
            toast = "Controlla i valori: lo spazio usato non può superare il totale."
            return
        }
        env.preferences.update {
            $0.manualICloudQuota = ManualICloudQuota(totalGB: total, usedGB: used, updatedAt: Date())
        }
        toast = "Dati del piano salvati."
    }
}
