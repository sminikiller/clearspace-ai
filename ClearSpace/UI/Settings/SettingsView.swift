import SwiftUI

/// Impostazioni: analisi, iCloud, protezioni, promemoria, piano e informazioni.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private let videoThresholds = [100, 250, 500, 1_000]
    private let sessionSizes = [25, 50, 100, 200]
    private let transcriptionLocales: [(String, String)] = [
        ("it-IT", "Italiano"), ("en-US", "Inglese"), ("es-ES", "Spagnolo"),
        ("fr-FR", "Francese"), ("de-DE", "Tedesco")
    ]

    var body: some View {
        NavigationStack {
            Form {
                analysisSection
                reviewSection
                thresholdsSection
                iCloudSection

                Section("Sicurezza") {
                    NavigationLink {
                        ProtectionSettingsView()
                    } label: {
                        Label("Elementi protetti", systemImage: "lock.shield")
                    }
                }

                Section {
                    Picker("Lingua della trascrizione", selection: env.preferences.binding(\.transcriptionLocaleIdentifier)) {
                        ForEach(transcriptionLocales, id: \.0) { locale in
                            Text(locale.1).tag(locale.0)
                        }
                    }
                } header: {
                    Text("Audio")
                } footer: {
                    Text("La trascrizione avviene solo sul dispositivo e richiede che la lingua sia disponibile offline su questo iPhone.")
                }

                Section("Piano") {
                    NavigationLink {
                        PlanView()
                    } label: {
                        HStack {
                            Label("Piano attuale", systemImage: "star.circle")
                            Spacer()
                            Text(env.plan.currentTier.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Informazioni") {
                    NavigationLink("Cosa può fare ClearSpace su iPhone") {
                        CapabilitiesInfoView()
                    }
                    DetailRow(label: "Versione", value: versionDescription)
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }

    private var analysisSection: some View {
        Section {
            Toggle("Scarica da iCloud solo con Wi‑Fi", isOn: env.preferences.binding(\.wifiOnlyDownloads))
            Toggle("Consenti il download degli originali per le verifiche", isOn: env.preferences.binding(\.allowCloudDownloadsForAnalysis))
            Toggle("Pausa con batteria scarica o dispositivo caldo", isOn: env.preferences.binding(\.pauseOnLowBattery))
            Toggle("Includi le foto nascoste nell'analisi", isOn: env.preferences.binding(\.includeHiddenAssets))
        } header: {
            Text("Analisi")
        } footer: {
            Text("Le analisi avvengono sul dispositivo. Il download degli originali da iCloud serve solo a verificare i duplicati esatti e resta disattivato finché non lo consenti. Le foto nascoste, se incluse, restano protette.")
        }
    }

    private var reviewSection: some View {
        Section {
            Toggle("Riproduci i video automaticamente", isOn: env.preferences.binding(\.autoplayVideos))
        } header: {
            Text("Revisione")
        } footer: {
            Text("Nella modalità swipe i video partono da soli, senza audio: un tocco li mette in pausa, il pulsante dell'altoparlante attiva il sonoro. Le anteprime nitide delle foto su iCloud vengono scaricate rispettando l'impostazione Wi‑Fi qui sopra.")
        }
    }

    private var thresholdsSection: some View {
        Section("Soglie") {
            Picker("Video considerati grandi", selection: env.preferences.binding(\.largeVideoThresholdMB)) {
                ForEach(videoThresholds, id: \.self) { value in
                    Text(value >= 1_000 ? "Oltre 1 GB" : "Oltre \(value) MB").tag(value)
                }
            }
            Picker("Elementi nella pulizia rapida", selection: env.preferences.binding(\.quickSessionSize)) {
                ForEach(sessionSizes, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
        }
    }

    private var iCloudSection: some View {
        Section {
            Picker("Foto di iCloud", selection: env.preferences.binding(\.iCloudPhotosState)) {
                ForEach(ICloudPhotosState.allCases, id: \.self) { state in
                    Text(state.title).tag(state)
                }
            }
            NavigationLink {
                ICloudCenterView()
            } label: {
                Label("Centro iCloud", systemImage: "icloud")
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text("Indica se usi Foto di iCloud: serve a mostrare con precisione gli effetti di un'eliminazione.")
        }
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// Regole di protezione: ciò che non deve mai essere proposto per l'eliminazione.
struct ProtectionSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var albums: [AlbumInfo] = []
    @State private var periodName = ""
    @State private var periodStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var periodEnd = Date()

    private var rules: ProtectionRules { env.preferences.values.protection }

    var body: some View {
        List {
            Section {
                Toggle("Proteggi i preferiti", isOn: env.preferences.binding(\.protection.protectFavorites))
                Toggle("Proteggi le foto nascoste", isOn: env.preferences.binding(\.protection.protectHidden))
                Toggle("Segnala i contenuti potenzialmente importanti", isOn: env.preferences.binding(\.protection.cautionForSensitive))
            } header: {
                Text("Protezioni automatiche")
            } footer: {
                Text("Documenti, ricevute, codici e testi sensibili non vengono bloccati, ma sono evidenziati nella revisione e richiedono una conferma dedicata.")
            }

            Section {
                if albums.isEmpty {
                    Text(env.photos.canRead ? "Nessun album disponibile." : "Consenti l'accesso a Foto per scegliere gli album.")
                        .foregroundStyle(.secondary)
                }
                ForEach(albums) { album in
                    Toggle(isOn: albumBinding(album.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.title)
                            Text(Format.plural(album.count, "elemento", "elementi"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Album protetti")
            } footer: {
                Text("Gli elementi contenuti in questi album non compaiono nelle sessioni di pulizia.")
            }

            if !env.folders.folders.isEmpty {
                Section("Cartelle protette") {
                    ForEach(env.folders.folders) { folder in
                        Toggle(folder.name, isOn: folderBinding(folder.id))
                    }
                }
            }

            Section {
                ForEach(rules.protectedPeriods) { period in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(period.name)
                        Text("\(Format.date(period.start)) – \(Format.date(period.end))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    env.preferences.update { $0.protection.protectedPeriods.remove(atOffsets: offsets) }
                }

                TextField("Nome del periodo (es. Viaggio di nozze)", text: $periodName)
                DatePicker("Dal", selection: $periodStart, displayedComponents: .date)
                DatePicker("Al", selection: $periodEnd, displayedComponents: .date)
                Button("Aggiungi il periodo") {
                    addPeriod()
                }
                .disabled(periodName.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Periodi protetti")
            } footer: {
                Text("Tutti i contenuti creati in un periodo protetto vengono esclusi dalle proposte. Scorri una riga verso sinistra per rimuoverla.")
            }

            Section {
                NavigationLink {
                    ItemGridScreen(query: ItemQuery(
                        title: "Protetti da te",
                        subtitle: "Elementi che hai protetto singolarmente",
                        predicate: { item, _ in item.isProtected }
                    ))
                } label: {
                    Label("Elementi protetti singolarmente", systemImage: "lock")
                }
            }
        }
        .navigationTitle("Elementi protetti")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            albums = env.photos.userAlbums()
        }
        .onChange(of: env.preferences.values.protection) { _, _ in
            Task {
                await env.protectionRulesDidChange()
            }
        }
    }

    private func albumBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { rules.protectedAlbumIDs.contains(id) },
            set: { isOn in
                env.preferences.update { preferences in
                    if isOn {
                        preferences.protection.protectedAlbumIDs.insert(id)
                    } else {
                        preferences.protection.protectedAlbumIDs.remove(id)
                    }
                }
            }
        )
    }

    private func folderBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { rules.protectedFolderIDs.contains(id) },
            set: { isOn in
                env.preferences.update { preferences in
                    if isOn {
                        preferences.protection.protectedFolderIDs.insert(id)
                    } else {
                        preferences.protection.protectedFolderIDs.remove(id)
                    }
                }
            }
        )
    }

    private func addPeriod() {
        let name = periodName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(periodStart, periodEnd))
        let end = calendar.startOfDay(for: max(periodStart, periodEnd)).addingTimeInterval(86_399)
        env.preferences.update {
            $0.protection.protectedPeriods.append(ProtectedPeriod(name: name, start: start, end: end))
        }
        periodName = ""
    }
}
