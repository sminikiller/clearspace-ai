import SwiftUI
import UniformTypeIdentifiers

/// Organizza i file di una cartella autorizzata in sottocartelle per tipo o per anno.
/// Mostra sempre l'anteprima degli spostamenti prima di applicarli; nessun file viene eliminato.
struct OrganizeView: View {

    enum Scheme: String, CaseIterable, Identifiable {
        case byType
        case byYear

        var id: String { rawValue }

        var title: String {
            switch self {
            case .byType: return "Per tipo"
            case .byYear: return "Per anno"
            }
        }
    }

    private struct PlannedMove: Identifiable {
        let item: IndexedItem
        let destinationFolder: String

        var id: UUID { item.id }
    }

    private struct PlanKey: Equatable {
        let folderID: UUID?
        let scheme: Scheme
        let revision: Int
    }

    @Environment(AppEnvironment.self) private var env
    @State private var folderID: UUID?
    @State private var scheme: Scheme = .byType
    @State private var moves: [PlannedMove] = []
    @State private var confirmsApply = false
    @State private var isApplying = false
    @State private var completed = 0
    @State private var toast: String?

    var body: some View {
        Group {
            if env.plan.isUnlocked(.organization) {
                content
            } else {
                LockedFeatureView(feature: .organization)
            }
        }
        .navigationTitle("Organizza")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var content: some View {
        List {
            Section("Cartella") {
                if env.folders.folders.isEmpty {
                    Text("Aggiungi prima una cartella dalla sezione Documenti.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Cartella", selection: $folderID) {
                        Text("Scegli…").tag(UUID?.none)
                        ForEach(env.folders.folders) { folder in
                            Text(folder.name).tag(UUID?.some(folder.id))
                        }
                    }
                }
            }

            Section("Criterio") {
                Picker("Criterio", selection: $scheme) {
                    ForEach(Scheme.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .adaptiveSegmentedStyle()
            }

            if folderID != nil {
                Section {
                    if moves.isEmpty {
                        Text("I file sono già organizzati secondo questo criterio.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(destinationSummary) { destination in
                            HStack {
                                Label(destination.name, systemImage: "folder")
                                Spacer()
                                Text(Format.plural(destination.count, "file", "file"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Anteprima")
                } footer: {
                    Text("I file vengono soltanto spostati in sottocartelle della cartella scelta. Le decisioni prese su quei file andranno ripetute dopo lo spostamento.")
                }

                Section {
                    Button {
                        confirmsApply = true
                    } label: {
                        if isApplying {
                            HStack {
                                ProgressView()
                                Text("Spostamento \(completed) di \(moves.count)")
                            }
                        } else {
                            Text("Sposta \(Format.plural(moves.count, "file", "file"))")
                        }
                    }
                    .disabled(moves.isEmpty || isApplying)
                }
            }
        }
        .confirmationDialog(
            "Spostare i file nelle sottocartelle?",
            isPresented: $confirmsApply,
            titleVisibility: .visible
        ) {
            Button("Sposta") {
                applyMoves()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Nessun file viene eliminato. Se la cartella è in iCloud Drive, lo spostamento vale anche per gli altri dispositivi.")
        }
        .task(id: PlanKey(folderID: folderID, scheme: scheme, revision: env.listRevision)) {
            computeMoves()
        }
        .toast($toast)
    }

    private struct DestinationCount: Identifiable {
        let name: String
        let count: Int

        var id: String { name }
    }

    private var destinationSummary: [DestinationCount] {
        var counts: [String: Int] = [:]
        for move in moves {
            counts[move.destinationFolder, default: 0] += 1
        }
        return counts.keys.sorted().map { DestinationCount(name: $0, count: counts[$0] ?? 0) }
    }

    private func destinationName(for item: IndexedItem) -> String {
        switch scheme {
        case .byType:
            switch item.category {
            case .photo: return "Immagini"
            case .video: return "Video"
            case .pdf: return "PDF"
            case .office: return "Documenti"
            case .archive: return "Archivi"
            case .audio: return "Audio"
            case .otherDocument: return "Altri documenti"
            case .unknown: return "Altro"
            }
        case .byYear:
            guard let date = item.modifiedAt ?? item.createdAt else { return "Senza data" }
            return String(Calendar.current.component(.year, from: date))
        }
    }

    private func computeMoves() {
        guard let folderID, !isApplying else {
            if folderID == nil { moves = [] }
            return
        }
        var planned: [PlannedMove] = []
        for item in env.store.existingItems(inFolder: folderID).values {
            guard let path = item.relativePath else { continue }
            let destination = destinationName(for: item)
            let firstComponent = path.split(separator: "/").first.map(String.init)
            // I file che si trovano già nella sottocartella giusta restano dove sono.
            if firstComponent == destination && path.contains("/") { continue }
            planned.append(PlannedMove(item: item, destinationFolder: destination))
        }
        moves = planned.sorted { $0.item.displayTitle < $1.item.displayTitle }
    }

    private func applyMoves() {
        guard let folderID, let root = env.folders.resolvedURL(for: folderID) else { return }
        isApplying = true
        completed = 0
        let planned = moves
        Task {
            var moved = 0
            var failed = 0
            for move in planned {
                completed += 1
                guard let source = env.folders.url(for: move.item) else {
                    failed += 1
                    continue
                }
                let directory = root.appendingPathComponent(move.destinationFolder, isDirectory: true)
                let destination = uniqueDestination(in: directory, filename: source.lastPathComponent)
                do {
                    try await env.fileOperations.move(from: source, to: destination)
                    moved += 1
                } catch {
                    failed += 1
                }
            }
            isApplying = false
            toast = failed == 0
                ? "\(Format.plural(moved, "file spostato", "file spostati"))."
                : "\(moved) spostati, \(failed) non riusciti."
            // L'indice viene riallineato alla nuova posizione dei file.
            if !env.scan.isRunning {
                env.scan.start(deep: false)
            }
        }
    }

    private func uniqueDestination(in directory: URL, filename: String) -> URL {
        let name = (filename as NSString).deletingPathExtension
        let fileExtension = (filename as NSString).pathExtension
        var destination = directory.appendingPathComponent(filename)
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            counter += 1
            let candidate = fileExtension.isEmpty ? "\(name) \(counter)" : "\(name) \(counter).\(fileExtension)"
            destination = directory.appendingPathComponent(candidate)
        }
        return destination
    }
}

/// Archiviazione guidata: prima di eliminare contenuti importanti, ne crea una copia verificata
/// in una destinazione scelta dall'utente.
struct ArchiveWizardView: View {
    let itemIDs: [UUID]

    private struct ArchiveResult: Identifiable {
        let id: UUID
        let title: String
        let succeeded: Bool
        let message: String
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var onlySensitive = true
    @State private var destination: URL?
    @State private var showsPicker = false
    @State private var isRunning = false
    @State private var completed = 0
    @State private var results: [ArchiveResult] = []

    private var candidates: [IndexedItem] {
        let items = env.store.items(itemIDs)
        return onlySensitive ? items.filter { $0.isSensitive } : items
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    InfoBanner(text: "Crea una copia dei contenuti prima di eliminarli. Ogni copia viene confrontata con l'originale (SHA-256): solo quelle identiche sono considerate riuscite.")
                }

                Section("Cosa archiviare") {
                    Toggle("Solo i contenuti potenzialmente importanti", isOn: $onlySensitive)
                    let selected = candidates
                    Text("\(Format.plural(selected.count, "elemento", "elementi")) · \(Format.bytes(selected.reduce(0) { $0 + $1.bytes }))")
                        .foregroundStyle(.secondary)
                }

                Section {
                    if let destination {
                        Label(destination.lastPathComponent, systemImage: "folder")
                    }
                    Button(destination == nil ? "Scegli la cartella di destinazione" : "Cambia cartella") {
                        showsPicker = true
                    }
                } header: {
                    Text("Destinazione")
                } footer: {
                    Text("Scegli una posizione diversa da quelle che stai per ripulire, ad esempio un'unità esterna o un altro servizio cloud.")
                }

                Section {
                    Button {
                        run()
                    } label: {
                        if isRunning {
                            HStack {
                                ProgressView()
                                Text("Copia \(completed) di \(candidates.count)")
                            }
                        } else {
                            Text("Copia e verifica")
                        }
                    }
                    .disabled(destination == nil || isRunning || candidates.isEmpty)
                }

                if !results.isEmpty {
                    Section("Esito") {
                        ForEach(results) { result in
                            HStack(alignment: .top) {
                                Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.succeeded ? Theme.keep : Theme.remove)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .lineLimit(1)
                                    Text(result.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Archiviazione guidata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                        .disabled(isRunning)
                }
            }
            .fileImporter(isPresented: $showsPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    destination = url
                }
            }
            .interactiveDismissDisabled(isRunning)
        }
    }

    private func run() {
        guard let destination else { return }
        let targets = candidates
        isRunning = true
        completed = 0
        results = []
        Task {
            for item in targets {
                completed += 1
                results.append(await archive(item, to: destination))
            }
            isRunning = false
        }
    }

    private func archive(_ item: IndexedItem, to directory: URL) async -> ArchiveResult {
        do {
            if item.source == .photoLibrary {
                let written = try await env.fileOperations.exportLibraryAsset(
                    identifier: item.sourceIdentifier,
                    to: directory,
                    allowNetwork: env.canDownloadForViewing
                )
                return ArchiveResult(
                    id: item.id,
                    title: item.displayTitle,
                    succeeded: true,
                    message: "Copia verificata (\(Format.plural(written.count, "file", "file")))."
                )
            }
            guard let source = env.folders.url(for: item) else {
                return ArchiveResult(id: item.id, title: item.displayTitle, succeeded: false, message: "File non accessibile.")
            }
            _ = try await env.fileOperations.copyVerified(from: source, to: directory)
            return ArchiveResult(id: item.id, title: item.displayTitle, succeeded: true, message: "Copia verificata.")
        } catch let error as FileOperationError {
            return ArchiveResult(id: item.id, title: item.displayTitle, succeeded: false, message: error.message)
        } catch {
            return ArchiveResult(id: item.id, title: item.displayTitle, succeeded: false, message: error.localizedDescription)
        }
    }
}
