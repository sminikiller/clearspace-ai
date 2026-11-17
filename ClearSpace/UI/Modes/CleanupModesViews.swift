import SwiftUI

/// Opzioni della pulizia rapida: quanti elementi rivedere in una sessione.
struct QuickCleanupSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private let sizes = [25, 50, 100, 200]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Elementi per sessione", selection: env.preferences.binding(\.quickSessionSize)) {
                        ForEach(sizes, id: \.self) { size in
                            Text("\(size)").tag(size)
                        }
                    }
                    .adaptiveSegmentedStyle()
                } header: {
                    Text("Elementi per sessione")
                } footer: {
                    Text("La pulizia rapida propone per primi duplicati certi, video grandi e screenshot vecchi. Puoi interrompere quando vuoi: le scelte restano salvate.")
                }

                Section {
                    Button("Avvia la pulizia rapida") {
                        start()
                    }
                }
            }
            .navigationTitle("Pulizia rapida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
    }

    private func start() {
        let limit = env.preferences.values.quickSessionSize
        let environment = env
        dismiss()
        // La sessione parte dopo la chiusura di questo pannello, così le due presentazioni non si sovrappongono.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            await environment.startSession(title: "Pulizia rapida", mode: .quick) { input in
                CleanupPlanner.quickQueue(input, limit: limit)
            }
        }
    }
}

/// Pulizia per obiettivo: si sceglie quanto spazio potenziale raggiungere.
struct GoalCleanupSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var targetGB = 5

    private let options = [1, 2, 5, 10, 20]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Obiettivo", selection: $targetGB) {
                        ForEach(options, id: \.self) { value in
                            Text("\(value) GB").tag(value)
                        }
                    }
                    .adaptiveSegmentedStyle()
                } header: {
                    Text("Spazio potenziale da raggiungere")
                } footer: {
                    Text("ClearSpace propone gli elementi più promettenti e mostra l'avanzamento verso l'obiettivo. È spazio potenziale: quello effettivo dipende dalla conferma finale e dalla sincronizzazione.")
                }

                Section {
                    Button("Avvia") {
                        start()
                    }
                }
            }
            .navigationTitle("Pulizia per obiettivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
    }

    private func start() {
        let target = Int64(targetGB) * AppConfiguration.Thresholds.gigabyte
        let title = "Obiettivo \(targetGB) GB"
        let environment = env
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            await environment.startSession(title: title, mode: .goal(targetBytes: target), goalBytes: target) { input in
                CleanupPlanner.goalQueue(targetBytes: target, input)
            }
        }
    }
}

/// Pulizia guidata: un percorso passo dopo passo, consigliato alla maggior parte delle persone.
struct GuidedCleanupView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var counts: [GuidedStepKind: Int] = [:]
    @State private var startingStep: GuidedStepKind?
    @State private var toast: String?

    var body: some View {
        List {
            Section {
                InfoBanner(text: "Segui i passi nell'ordine che preferisci. In ogni passo decidi tu cosa tenere: l'eliminazione avviene solo dalla scheda Revisione.")
            }
            ForEach(Array(GuidedStepKind.allCases.enumerated()), id: \.element) { index, step in
                Section {
                    stepRow(step, number: index + 1)
                }
            }
        }
        .navigationTitle("Pulizia guidata")
        .task(id: env.listRevision) {
            await reloadCounts()
        }
        .toast($toast)
    }

    private func checklistID(_ step: GuidedStepKind) -> String {
        "guided." + step.rawValue
    }

    @ViewBuilder
    private func stepRow(_ step: GuidedStepKind, number: Int) -> some View {
        let isDone = env.history.isChecked(checklistID(step))
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(isDone ? Theme.keep : Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Label(step.title, systemImage: step.systemImage)
                    .font(.headline)
                Text(step.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if step.usesSwipe {
                    Text("\(Format.plural(counts[step] ?? 0, "elemento", "elementi")) da rivedere")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)

        if step.usesSwipe {
            Button {
                start(step)
            } label: {
                if startingStep == step {
                    ProgressView()
                } else {
                    Text("Rivedi con gli swipe")
                }
            }
            .disabled((counts[step] ?? 0) == 0 || startingStep != nil)
        } else if step == .otherApps {
            NavigationLink("Apri l'assistente app") {
                AppAssistantView()
            }
        } else {
            NavigationLink("Apri il centro iCloud") {
                ICloudCenterView()
            }
        }

        Toggle("Passo completato", isOn: Binding(
            get: { env.history.isChecked(checklistID(step)) },
            set: { env.history.setChecked($0, id: checklistID(step)) }
        ))
        .font(.subheadline)
    }

    private func reloadCounts() async {
        let input = env.plannerInput()
        let computed = await Task.detached(priority: .userInitiated) { () -> [GuidedStepKind: Int] in
            var result: [GuidedStepKind: Int] = [:]
            for step in GuidedStepKind.allCases where step.usesSwipe {
                result[step] = CleanupPlanner.guidedQueue(step, input).count
            }
            return result
        }.value
        guard !Task.isCancelled else { return }
        counts = computed
    }

    private func start(_ step: GuidedStepKind) {
        startingStep = step
        Task {
            let started = await env.startSession(title: step.title, mode: .guided(step: step)) { input in
                CleanupPlanner.guidedQueue(step, input)
            }
            startingStep = nil
            if !started {
                toast = "Non ci sono elementi da rivedere in questo passo."
            }
        }
    }
}

/// Pulizia avanzata: filtri combinati su tipo, origine, periodo, dimensione e caratteristiche.
struct AdvancedCleanupView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var filter = ItemFilter()
    @State private var usesDateRange = false
    @State private var fromDate = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    @State private var toDate = Date()
    @State private var minimumSizeMB = 0.0
    @State private var minimumMinutes = 0.0
    @State private var reviewScope = ReviewScope.pending
    @State private var matchCount = 0
    @State private var matchBytes: Int64 = 0
    @State private var isStarting = false
    @State private var toast: String?

    private enum ReviewScope: String, CaseIterable, Identifiable {
        case pending
        case all
        case kept
        case postponed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pending: return "Da rivedere"
            case .all: return "Tutti"
            case .kept: return "Già conservati"
            case .postponed: return "Rimandati"
            }
        }
    }

    private struct MatchKey: Equatable {
        let filter: ItemFilter
        let revision: Int
    }

    private let categoryOptions: [(ContentCategory, String)] = [
        (.photo, "Foto e immagini"), (.video, "Video"), (.pdf, "PDF"), (.office, "Documenti Office"),
        (.archive, "Archivi compressi"), (.audio, "Audio"), (.otherDocument, "Altri documenti"),
        (.unknown, "File sconosciuti")
    ]

    private let traitOptions: [(ItemTraits, String)] = [
        (.screenshot, "Screenshot"), (.livePhoto, "Live Photo"), (.burst, "Raffiche"), (.selfie, "Selfie"),
        (.hasText, "Con testo"), (.screenRecording, "Registrazioni schermo"), (.video4K, "Video 4K"),
        (.cloudOnly, "Solo su iCloud"), (.download, "Download")
    ]

    var body: some View {
        Group {
            if env.plan.isUnlocked(.advancedFilters) {
                form
            } else {
                LockedFeatureView(feature: .advancedFilters)
            }
        }
        .navigationTitle("Pulizia avanzata")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var form: some View {
        Form {
            Section("Tipo di contenuto") {
                ForEach(categoryOptions, id: \.0) { option in
                    Toggle(option.1, isOn: categoryBinding(option.0))
                }
            }

            Section("Origine") {
                ForEach(StorageSource.allCases, id: \.self) { source in
                    Toggle(source.title, isOn: sourceBinding(source))
                }
            }

            Section {
                ForEach(traitOptions, id: \.1) { option in
                    Toggle(option.1, isOn: requiredTraitBinding(option.0))
                }
                Toggle("Sfocate, scure o vuote", isOn: lowQualityBinding)
                Toggle("Solo elementi con duplicati", isOn: $filter.onlyDuplicates)
                Toggle("Solo elementi con simili", isOn: $filter.onlySimilar)
            } header: {
                Text("Caratteristiche")
            } footer: {
                Text("Le caratteristiche selezionate devono essere tutte presenti.")
            }

            Section("Periodo") {
                Toggle("Limita a un intervallo di date", isOn: $usesDateRange)
                if usesDateRange {
                    DatePicker("Dal", selection: $fromDate, displayedComponents: .date)
                    DatePicker("Al", selection: $toDate, displayedComponents: .date)
                }
            }

            Section("Dimensione e durata") {
                VStack(alignment: .leading) {
                    Text(minimumSizeMB > 0 ? "Almeno \(Int(minimumSizeMB)) MB" : "Qualsiasi dimensione")
                    Slider(value: $minimumSizeMB, in: 0...2_000, step: 10)
                        .accessibilityLabel("Dimensione minima")
                }
                VStack(alignment: .leading) {
                    Text(minimumMinutes > 0 ? "Almeno \(Int(minimumMinutes)) min" : "Qualsiasi durata")
                    Slider(value: $minimumMinutes, in: 0...60, step: 1)
                        .accessibilityLabel("Durata minima")
                }
            }

            if !env.folders.folders.isEmpty {
                Section("Cartelle") {
                    ForEach(env.folders.folders) { folder in
                        Toggle(folder.name, isOn: folderBinding(folder.id))
                    }
                }
            }

            Section("Stato e ordinamento") {
                Picker("Stato", selection: $reviewScope) {
                    ForEach(ReviewScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                Toggle("Includi gli elementi protetti", isOn: $filter.includeProtected)
                Picker("Ordina per", selection: $filter.sort) {
                    ForEach(ItemSort.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
            }

            Section {
                NavigationLink {
                    ItemGridScreen(query: .filter(effectiveFilter, title: "Risultati"))
                } label: {
                    HStack {
                        Text("Mostra i risultati")
                        Spacer()
                        Text("\(Format.count(matchCount)) · \(Format.bytes(matchBytes))")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(matchCount == 0)

                Button {
                    startSwipe()
                } label: {
                    if isStarting {
                        ProgressView()
                    } else {
                        Text("Rivedi con gli swipe")
                    }
                }
                .disabled(matchCount == 0 || isStarting)

                Button("Azzera i filtri", role: .destructive) {
                    reset()
                }
            }
        }
        .task(id: MatchKey(filter: effectiveFilter, revision: env.listRevision)) {
            await countMatches()
        }
        .toast($toast)
    }

    // MARK: - Filtro

    /// Il filtro completo, che unisce le scelte fatte con i controlli della schermata.
    private var effectiveFilter: ItemFilter {
        var result = filter
        result.createdAfter = usesDateRange ? Calendar.current.startOfDay(for: fromDate) : nil
        // L'intervallo comprende l'intera giornata finale.
        result.createdBefore = usesDateRange
            ? Calendar.current.startOfDay(for: toDate).addingTimeInterval(86_399)
            : nil
        result.minBytes = minimumSizeMB > 0 ? Int64(minimumSizeMB) * AppConfiguration.Thresholds.megabyte : nil
        result.minDuration = minimumMinutes > 0 ? minimumMinutes * 60 : nil
        switch reviewScope {
        case .pending: result.reviewStatuses = [.unreviewed, .postponed]
        case .all: result.reviewStatuses = []
        case .kept: result.reviewStatuses = [.kept]
        case .postponed: result.reviewStatuses = [.postponed]
        }
        return result
    }

    private func categoryBinding(_ category: ContentCategory) -> Binding<Bool> {
        Binding(
            get: { filter.categories.contains(category) },
            set: { isOn in
                if isOn {
                    filter.categories.insert(category)
                } else {
                    filter.categories.remove(category)
                }
            }
        )
    }

    private func sourceBinding(_ source: StorageSource) -> Binding<Bool> {
        Binding(
            get: { filter.sources.contains(source) },
            set: { isOn in
                if isOn {
                    filter.sources.insert(source)
                } else {
                    filter.sources.remove(source)
                }
            }
        )
    }

    private func requiredTraitBinding(_ trait: ItemTraits) -> Binding<Bool> {
        Binding(
            get: { filter.requiredTraits.contains(trait) },
            set: { isOn in
                if isOn {
                    filter.requiredTraits.insert(trait)
                } else {
                    filter.requiredTraits.remove(trait)
                }
            }
        )
    }

    private var lowQualityBinding: Binding<Bool> {
        Binding(
            get: { !filter.anyTraits.isDisjoint(with: .lowQualityMask) },
            set: { isOn in
                if isOn {
                    filter.anyTraits.formUnion(.lowQualityMask)
                } else {
                    filter.anyTraits.subtract(.lowQualityMask)
                }
            }
        )
    }

    private func folderBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { filter.folderIDs.contains(id) },
            set: { isOn in
                if isOn {
                    filter.folderIDs.insert(id)
                } else {
                    filter.folderIDs.remove(id)
                }
            }
        )
    }

    private func reset() {
        filter = ItemFilter()
        usesDateRange = false
        minimumSizeMB = 0
        minimumMinutes = 0
        reviewScope = .pending
    }

    private func countMatches() async {
        let input = env.plannerInput()
        let active = effectiveFilter
        let result = await Task.detached(priority: .userInitiated) { () -> (count: Int, bytes: Int64) in
            var count = 0
            var bytes: Int64 = 0
            for item in input.items where active.matches(item, evaluator: input.evaluator) {
                count += 1
                bytes += item.bytes
            }
            return (count, bytes)
        }.value
        guard !Task.isCancelled else { return }
        matchCount = result.count
        matchBytes = result.bytes
    }

    private func startSwipe() {
        isStarting = true
        let active = effectiveFilter
        Task {
            let started = await env.startSession(title: "Pulizia avanzata", mode: .advanced) { input in
                CleanupPlanner.queue(for: active, input)
            }
            isStarting = false
            if !started {
                toast = "Gli elementi trovati sono già stati decisi o sono protetti."
            }
        }
    }
}
