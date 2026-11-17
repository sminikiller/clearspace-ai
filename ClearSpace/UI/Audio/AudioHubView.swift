import SwiftUI
import UniformTypeIdentifiers

/// Audio e registrazioni: file audio delle cartelle autorizzate e registrazioni importate in ClearSpace.
struct AudioHubView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var recordings: [IndexedItem] = []
    @State private var showsImporter = false
    @State private var searchText = ""
    @State private var toast: String?

    var body: some View {
        Group {
            if env.plan.isUnlocked(.audioTools) {
                content
            } else {
                LockedFeatureView(feature: .audioTools)
            }
        }
        .navigationTitle("Audio e registrazioni")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var content: some View {
        List {
            Section {
                Button {
                    showsImporter = true
                } label: {
                    Label("Importa file audio", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Importazione")
            } footer: {
                Text("L'app Memo Vocali non mette il proprio archivio a disposizione di altre app. Per analizzare un memo aprilo in Memo Vocali, tocca Condividi e scegli ClearSpace, oppure salvalo in File. Viene importata una copia: eliminarla qui non elimina l'originale in Memo Vocali.")
            }

            Section("Cerca nelle registrazioni") {
                TextField("Nome o parole della trascrizione", text: $searchText)
                    .submitLabel(.search)
                if !searchTokens.isEmpty {
                    NavigationLink {
                        ItemGridScreen(query: .filter(searchFilter, title: "Risultati", mode: .search(query: searchText)))
                    } label: {
                        Label("Cerca «\(searchText)»", systemImage: "magnifyingglass")
                    }
                }
            }

            Section("Categorie") {
                ForEach(SmartCollection.collections(in: .audio)) { collection in
                    CollectionLink(collection: collection)
                }
            }

            Section("Registrazioni") {
                if recordings.isEmpty {
                    Text("Nessuna registrazione trovata. Importa un file o aggiungi una cartella dalla sezione Documenti.")
                        .foregroundStyle(.secondary)
                }
                ForEach(recordings.prefix(100)) { item in
                    NavigationLink {
                        AudioDetailView(itemID: item.id)
                    } label: {
                        recordingRow(item)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            importFiles(result)
        }
        .task(id: env.listRevision) {
            let context = CollectionContext(now: Date(), largeVideoBytes: env.preferences.values.largeVideoBytes)
            recordings = env.store.snapshot()
                .filter { SmartCollection.allAudio.contains($0, context: context) }
                .sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
        }
        .toast($toast)
    }

    private var searchTokens: [String] {
        TextSimilarity.tokens(searchText).filter { $0.count >= 2 }
    }

    private var searchFilter: ItemFilter {
        var filter = ItemFilter()
        filter.categories = [.audio]
        filter.textTokens = searchTokens
        filter.sort = .newestFirst
        return filter
    }

    private func recordingRow(_ item: IndexedItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .lineLimit(1)
                Text("\(Format.duration(item.duration)) · \(Format.bytesOrUnknown(item.estimatedBytes)) · \(Format.date(item.createdAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if item.traits.contains(.transcribed) {
                Image(systemName: "text.quote")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Trascritta")
            }
            if item.isProtected {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Protetta")
            }
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        var imported = 0
        for url in urls {
            if (try? env.folders.importFile(from: url)) != nil {
                imported += 1
            }
        }
        toast = "\(Format.plural(imported, "file importato", "file importati")) su \(urls.count)."
        if imported > 0 && !env.scan.isRunning {
            env.scan.start(deep: true)
        }
    }
}

/// Dettaglio di una registrazione: ascolto, silenzi rilevati e trascrizione sul dispositivo.
struct AudioDetailView: View {
    let itemID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var silences: [ClosedRange<Double>] = []
    @State private var isTranscribing = false
    @State private var toast: String?

    var body: some View {
        let _ = env.store.revision
        List {
            if let item = env.store.item(itemID) {
                Section {
                    AudioPlaybackView(item: item)
                        .listRowInsets(EdgeInsets())
                }

                Section("Informazioni") {
                    DetailRow(label: "Durata", value: Format.duration(item.duration))
                    DetailRow(label: "Dimensione", value: Format.bytesOrUnknown(item.estimatedBytes))
                    DetailRow(label: "Data", value: Format.dateTime(item.createdAt))
                    DetailRow(label: "Origine", value: item.source.title)
                }

                if !silences.isEmpty {
                    Section("Silenzi lunghi") {
                        ForEach(Array(silences.enumerated()), id: \.offset) { _, range in
                            DetailRow(
                                label: "Da \(Format.duration(range.lowerBound)) a \(Format.duration(range.upperBound))",
                                value: Format.duration(range.upperBound - range.lowerBound)
                            )
                        }
                    }
                }

                transcriptSection(for: item)
                actionsSection(for: item)
            } else {
                ContentUnavailableView("Registrazione non più disponibile", systemImage: "waveform.slash")
            }
        }
        .navigationTitle("Registrazione")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: itemID) {
            await loadSilences()
        }
        .toast($toast)
    }

    @ViewBuilder
    private func transcriptSection(for item: IndexedItem) -> some View {
        Section {
            if let text = item.textContent, !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
            Button {
                transcribe(item)
            } label: {
                if isTranscribing {
                    HStack {
                        ProgressView()
                        Text("Trascrizione in corso…")
                    }
                } else {
                    Label(
                        item.traits.contains(.transcribed) ? "Trascrivi di nuovo" : "Trascrivi sul dispositivo",
                        systemImage: "text.quote"
                    )
                }
            }
            .disabled(isTranscribing)
        } header: {
            Text("Trascrizione")
        } footer: {
            Text("La trascrizione avviene sul dispositivo: l'audio non viene inviato a nessun server. Il testo rende la registrazione ricercabile.")
        }
    }

    private func actionsSection(for item: IndexedItem) -> some View {
        Section {
            if item.isProtected {
                Button("Rimuovi la protezione") {
                    env.safety.removeProtection([item.id])
                }
            } else {
                Button("Proteggi questa registrazione") {
                    env.safety.protect([item.id])
                }
            }
            Button("Conserva") {
                env.safety.apply(.keep, to: item.id)
                toast = "Registrazione conservata."
            }
            Button("Aggiungi alla lista da eliminare", role: .destructive) {
                let result = env.safety.apply(.delete, to: item.id)
                if case .blocked(let reason) = result {
                    toast = reason.message
                } else {
                    toast = "Aggiunta alla revisione: nulla viene eliminato finché non confermi."
                }
            }
        } footer: {
            if item.source == .appImports {
                Text("È una copia importata in ClearSpace: eliminarla non tocca l'originale nell'app di origine.")
            }
        }
    }

    private func loadSilences() async {
        guard let item = env.store.item(itemID), let url = env.folders.url(for: item) else { return }
        let analysis = await Task.detached(priority: .utility) {
            try? AudioAnalyzer.analyze(url: url)
        }.value
        silences = analysis?.silences ?? []
    }

    private func transcribe(_ item: IndexedItem) {
        guard let url = env.folders.url(for: item) else { return }
        isTranscribing = true
        let locale = env.preferences.values.transcriptionLocaleIdentifier
        Task {
            do {
                let text = try await TranscriptionService.transcribe(url: url, localeIdentifier: locale)
                env.store.mutate(item.id) { current in
                    current.textContent = String(text.prefix(20_000))
                    current.traits.insert(.transcribed)
                    if !text.isEmpty {
                        current.traits.insert(.hasText)
                    }
                }
                toast = text.isEmpty ? "Nessun parlato riconosciuto." : "Trascrizione completata."
            } catch let error as TranscriptionError {
                toast = error.message
            } catch {
                toast = "Trascrizione non riuscita."
            }
            isTranscribing = false
        }
    }
}
