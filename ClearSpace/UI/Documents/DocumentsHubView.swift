import SwiftUI
import UniformTypeIdentifiers

/// Documenti e file: cartelle autorizzate, categorie e strumenti di organizzazione.
struct DocumentsHubView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showsFolderPicker = false
    @State private var folderToRemove: AuthorizedFolder?
    @State private var toast: String?

    var body: some View {
        Group {
            if env.plan.isUnlocked(.documents) {
                content
            } else {
                LockedFeatureView(feature: .documents)
            }
        }
        .navigationTitle("Documenti e file")
    }

    private var content: some View {
        List {
            Section {
                ForEach(env.folders.folders) { folder in
                    folderRow(folder)
                }
                Button {
                    showsFolderPicker = true
                } label: {
                    Label("Aggiungi una cartella", systemImage: "folder.badge.plus")
                }
            } header: {
                Text("Cartelle autorizzate")
            } footer: {
                Text("ClearSpace analizza soltanto le cartelle che scegli qui, comprese quelle di iCloud Drive e la cartella Download. Puoi revocare l'accesso in qualsiasi momento: i file non vengono toccati.")
            }

            Section("Categorie") {
                ForEach(SmartCollection.collections(in: .documents)) { collection in
                    CollectionLink(collection: collection)
                }
            }

            Section {
                NavigationLink {
                    EvictLocalCopiesView()
                } label: {
                    Label("Libera spazio sul dispositivo", systemImage: "icloud.and.arrow.down")
                }
                NavigationLink {
                    OrganizeView()
                } label: {
                    Label("Organizza per tipo o per anno", systemImage: "folder.badge.gearshape")
                }
            } header: {
                Text("Operazioni sui file")
            } footer: {
                Text("Tre operazioni distinte: liberare la sola copia locale di un file di iCloud Drive, eliminare un file (dalla Revisione, con conferma) oppure organizzare i file in cartelle.")
            }
        }
        .fileImporter(isPresented: $showsFolderPicker, allowedContentTypes: [.folder]) { result in
            handlePickedFolder(result)
        }
        .confirmationDialog(
            "Rimuovere la cartella dall'elenco?",
            isPresented: Binding(
                get: { folderToRemove != nil },
                set: { if !$0 { folderToRemove = nil } }
            ),
            titleVisibility: .visible,
            presenting: folderToRemove
        ) { folder in
            Button("Revoca l'accesso a «\(folder.name)»", role: .destructive) {
                env.removeFolder(folder.id)
            }
            Button("Annulla", role: .cancel) {}
        } message: { _ in
            Text("ClearSpace non potrà più leggere questa cartella. I file restano dove sono.")
        }
        .toast($toast)
    }

    private func folderRow(_ folder: AuthorizedFolder) -> some View {
        let isProtected = env.preferences.values.protection.protectedFolderIDs.contains(folder.id)
        return HStack(spacing: 12) {
            Image(systemName: folder.isICloud ? "icloud" : "folder")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                Text(folderDetail(folder))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isProtected {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Cartella protetta")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                folderToRemove = folder
            } label: {
                Label("Rimuovi", systemImage: "minus.circle")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                toggleProtection(folder.id)
            } label: {
                Label(isProtected ? "Sblocca" : "Proteggi", systemImage: isProtected ? "lock.open" : "lock")
            }
            .tint(.gray)
        }
    }

    private func folderDetail(_ folder: AuthorizedFolder) -> String {
        guard folder.lastScanAt != nil else {
            return "In attesa di analisi"
        }
        return "\(Format.plural(folder.itemCount, "file", "file")) · \(Format.bytes(folder.totalBytes))"
    }

    private func toggleProtection(_ id: UUID) {
        env.preferences.update { preferences in
            if preferences.protection.protectedFolderIDs.contains(id) {
                preferences.protection.protectedFolderIDs.remove(id)
            } else {
                preferences.protection.protectedFolderIDs.insert(id)
            }
        }
        Task {
            await env.protectionRulesDidChange()
        }
    }

    private func handlePickedFolder(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        do {
            try env.folders.addFolder(at: url)
            toast = "Cartella aggiunta: l'analisi è stata avviata."
            if !env.scan.isRunning {
                env.scan.start(deep: true)
            }
        } catch let error as FolderAccessError {
            toast = error.message
        } catch {
            toast = "Non è stato possibile aggiungere la cartella."
        }
    }
}

/// Libera la sola copia locale dei file di iCloud Drive: il documento resta disponibile online.
struct EvictLocalCopiesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var items: [IndexedItem] = []
    @State private var selection = Set<UUID>()
    @State private var confirmsEviction = false
    @State private var isWorking = false
    @State private var toast: String?

    private var selectedBytes: Int64 {
        items.reduce(0) { $0 + (selection.contains($1.id) ? $1.deviceBytes : 0) }
    }

    var body: some View {
        List {
            Section {
                InfoBanner(text: "Questa operazione rimuove dall'iPhone solo la copia scaricata. Il file resta in iCloud Drive e si riscarica quando lo apri. Non è un'eliminazione.")
            }
            if items.isEmpty {
                ContentUnavailableView(
                    "Nessuna copia locale da liberare",
                    systemImage: "icloud",
                    description: Text("Aggiungi una cartella di iCloud Drive e completa l'analisi.")
                )
            }
            Section {
                ForEach(items) { item in
                    Button {
                        toggle(item.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection.contains(item.id) ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayTitle)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Text("\(item.category.title) · \(Format.bytes(item.deviceBytes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Copie locali")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !items.isEmpty {
                Button {
                    confirmsEviction = true
                } label: {
                    if isWorking {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Libera \(Format.bytes(selectedBytes)) sul dispositivo")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selection.isEmpty || isWorking)
                .padding(12)
                .background(.bar)
            }
        }
        .confirmationDialog(
            "Liberare le copie locali selezionate?",
            isPresented: $confirmsEviction,
            titleVisibility: .visible
        ) {
            Button("Libera spazio sul dispositivo") {
                evictSelection()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("I file resteranno in iCloud Drive. I file non ancora caricati online non verranno toccati.")
        }
        .task(id: env.listRevision) {
            reload()
        }
        .toast($toast)
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func reload() {
        let context = CollectionContext(now: Date(), largeVideoBytes: env.preferences.values.largeVideoBytes)
        items = env.store.snapshot()
            .filter { SmartCollection.downloadedCloudFiles.contains($0, context: context) && $0.deviceBytes > 0 }
            .sorted { $0.deviceBytes > $1.deviceBytes }
        selection.formIntersection(Set(items.map { $0.id }))
    }

    private func evictSelection() {
        isWorking = true
        let targets = items.filter { selection.contains($0.id) }
        Task {
            var freed: [UUID] = []
            var firstError: String?
            for item in targets {
                guard let url = env.folders.url(for: item) else { continue }
                do {
                    try await env.fileOperations.evictLocalCopy(at: url)
                    freed.append(item.id)
                } catch let error as FileOperationError {
                    firstError = firstError ?? error.message
                } catch {
                    firstError = firstError ?? error.localizedDescription
                }
            }
            // L'indice viene aggiornato solo per i file realmente liberati.
            env.store.mutateEach(freed) { item in
                item.traits.insert(.cloudOnly)
                item.localBytes = 0
            }
            selection.removeAll()
            isWorking = false
            if let firstError, freed.count < targets.count {
                toast = "\(freed.count) di \(targets.count) liberati. \(firstError)"
            } else {
                toast = "\(Format.plural(freed.count, "copia locale liberata", "copie locali liberate"))."
            }
        }
    }
}
