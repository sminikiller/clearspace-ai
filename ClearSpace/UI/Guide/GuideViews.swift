import SwiftUI

/// Apre lo strumento descritto da un capitolo o da un tutorial. Le schede principali si aprono
/// cambiando scheda (chiudendo prima i pannelli aperti, se serve); il resto si apre sopra la guida.
struct GuideDestinationLink: View {
    let destination: GuideDestination
    var openTab: ((AppTab) -> Void)?

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let tab = destination.tab {
            Button {
                if let openTab {
                    openTab(tab)
                } else {
                    env.router.selectedTab = tab
                }
            } label: {
                Label(destination.title, systemImage: "arrow.up.forward.app")
            }
        } else {
            NavigationLink {
                GuideDestinationView(destination: destination)
            } label: {
                Label(destination.title, systemImage: "arrow.up.forward.app")
            }
        }
    }
}

extension GuideDestination {
    /// La scheda corrispondente, per le destinazioni che sono schede principali.
    var tab: AppTab? {
        switch self {
        case .homeTab: return .home
        case .analyzeTab: return .analyze
        case .exploreTab: return .explore
        case .reviewTab: return .review
        case .resultsTab: return .results
        default: return nil
        }
    }
}

/// Lo strumento vero e proprio, aperto dalla guida.
struct GuideDestinationView: View {
    let destination: GuideDestination

    var body: some View {
        switch destination {
        case .allPhotos: ItemGridScreen(query: .collection(.allPhotos))
        case .allVideos: ItemGridScreen(query: .collection(.allVideos))
        case .photoCategories: CollectionListView(section: .photos)
        case .videoCategories: CollectionListView(section: .videos)
        case .similarGroups: GroupListView(collection: .similarPhotos)
        case .duplicateGroups: GroupListView(collection: .duplicatePhotos)
        case .smartSearch: SmartSearchView()
        case .guidedCleanup: GuidedCleanupView()
        case .advancedCleanup: AdvancedCleanupView()
        case .archive: ArchiveView()
        case .trips: TripsView()
        case .nostalgia: NostalgiaView()
        case .documents: DocumentsHubView()
        case .audio: AudioHubView()
        case .iCloudCenter: ICloudCenterView()
        case .appAssistant: AppAssistantView()
        case .protections: ProtectionSettingsView()
        case .homeTab, .analyzeTab, .exploreTab, .reviewTab, .resultsTab:
            ContentUnavailableView("Apri la scheda dalla barra in basso", systemImage: "rectangle.bottomthird.inset.filled")
        }
    }
}

// MARK: - Indice

/// Guida completa e tutorial: l'indice dei capitoli, cercabile, e i tutorial con i loro progressi.
struct GuideHubView: View {
    /// Come aprire una scheda principale. Senza indicazione si cambia scheda direttamente.
    var openTab: ((AppTab) -> Void)?

    @Environment(AppEnvironment.self) private var env
    @State private var query = ""

    private var matchingChapters: [GuideChapter] {
        let words = Self.normalize(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return GuideBook.chapters }
        return GuideBook.chapters.filter { chapter in
            let text = Self.normalize(chapter.searchableText)
            return words.allSatisfy { text.contains($0) }
        }
    }

    private var overall: (done: Int, total: Int) {
        var done = 0
        var total = 0
        for tutorial in TutorialCatalog.all {
            let progress = env.tutorialProgress(tutorial)
            done += progress.done
            total += progress.total
        }
        return (done: done, total: total)
    }

    var body: some View {
        let _ = env.history.checklist.count
        List {
            if query.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Impara a usare ClearSpace", systemImage: "graduationcap")
                            .font(.headline)
                        Text("La guida spiega ogni strumento, ogni gesto e ogni impostazione. I tutorial hanno esercizi veri: si spuntano da soli quando li fai nell'app.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        let progress = overall
                        ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        Text("\(progress.done) di \(progress.total) esercizi completati")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("guide.overallProgress")
                    }
                    .padding(.vertical, 4)
                }

                Section("Tutorial pratici") {
                    NavigationLink {
                        TutorialListView(openTab: openTab)
                    } label: {
                        Label("Tutti i tutorial (\(TutorialCatalog.all.count))", systemImage: "checklist.checked")
                    }
                    if let next = nextTutorial {
                        NavigationLink {
                            TutorialDetailView(tutorial: next, openTab: openTab)
                        } label: {
                            Label("Continua: \(next.title)", systemImage: "play.circle")
                        }
                    }
                }

                Section {
                    NavigationLink {
                        QuickGuideView()
                    } label: {
                        Label("Guida rapida", systemImage: "bolt")
                    }
                }
            }

            Section(query.isEmpty ? "Guida completa · \(GuideBook.chapters.count) capitoli" : "Capitoli trovati") {
                if matchingChapters.isEmpty {
                    Text("Nessun capitolo contiene «\(query)».")
                        .foregroundStyle(.secondary)
                }
                ForEach(matchingChapters) { chapter in
                    NavigationLink {
                        GuideChapterView(chapter: chapter, openTab: openTab)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chapter.title)
                                Text(chapter.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: chapter.systemImage)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Cerca nella guida")
        .navigationTitle("Guida e tutorial")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Il primo tutorial non ancora completato.
    private var nextTutorial: Tutorial? {
        TutorialCatalog.all.first { tutorial in
            let progress = env.tutorialProgress(tutorial)
            return progress.done < progress.total
        }
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
    }
}

// MARK: - Capitolo

/// Un capitolo della guida, con il tutorial collegato e lo strumento da aprire.
struct GuideChapterView: View {
    let chapter: GuideChapter
    var openTab: ((AppTab) -> Void)?

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        List {
            Section {
                Label {
                    Text(chapter.summary)
                        .font(.subheadline)
                } icon: {
                    Image(systemName: chapter.systemImage)
                        .foregroundStyle(Color.accentColor)
                }
            }

            ForEach(chapter.sections) { section in
                Section(section.title) {
                    ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(section.points.enumerated()), id: \.offset) { _, point in
                        Label {
                            Text(point)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    if let tip = section.tip {
                        InfoBanner(text: tip, systemImage: "lightbulb.fill", tint: Theme.later)
                    }
                }
            }

            if chapter.tutorialID != nil || chapter.destination != nil {
                Section("Mettiti alla prova") {
                    if let tutorialID = chapter.tutorialID, let tutorial = TutorialCatalog.tutorial(tutorialID) {
                        NavigationLink {
                            TutorialDetailView(tutorial: tutorial, openTab: openTab)
                        } label: {
                            Label("Tutorial: \(tutorial.title)", systemImage: "checklist.checked")
                        }
                    }
                    if let destination = chapter.destination {
                        GuideDestinationLink(destination: destination, openTab: openTab)
                    }
                }
            }
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            env.recordTutorial(.readGuide)
        }
    }
}

// MARK: - Tutorial

/// Elenco dei tutorial con i progressi di ciascuno.
struct TutorialListView: View {
    var openTab: ((AppTab) -> Void)?

    @Environment(AppEnvironment.self) private var env
    @State private var confirmsReset = false

    var body: some View {
        let _ = env.history.checklist.count
        List {
            Section {
                Text("Ogni tutorial ha esercizi da fare davvero nell'app. Quelli con l'icona della bacchetta si spuntano da soli appena compi l'azione; gli altri li segni tu quando li hai provati.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(TutorialCatalog.all) { tutorial in
                    let progress = env.tutorialProgress(tutorial)
                    NavigationLink {
                        TutorialDetailView(tutorial: tutorial, openTab: openTab)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: progress.done == progress.total ? "checkmark.seal.fill" : tutorial.systemImage)
                                .font(.title3)
                                .foregroundStyle(progress.done == progress.total ? Theme.keep : Color.accentColor)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tutorial.title)
                                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                                    .tint(progress.done == progress.total ? Theme.keep : Color.accentColor)
                                Text("\(progress.done) di \(progress.total) esercizi")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Section {
                Button("Azzera i progressi", role: .destructive) {
                    confirmsReset = true
                }
            } footer: {
                Text("Toglie tutte le spunte dei tutorial per rifarli da capo. Non cambia nulla dei tuoi contenuti.")
            }
        }
        .navigationTitle("Tutorial")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Azzerare i progressi dei tutorial?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Azzera", role: .destructive) {
                env.resetTutorials()
            }
            Button("Annulla", role: .cancel) {}
        }
    }
}

/// Un tutorial: obiettivo, preparazione, strumento da aprire ed esercizi con la loro spunta.
struct TutorialDetailView: View {
    let tutorial: Tutorial
    var openTab: ((AppTab) -> Void)?

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let _ = env.history.checklist.count
        let progress = env.tutorialProgress(tutorial)
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tutorial.goal)
                        .font(.subheadline)
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .tint(progress.done == progress.total ? Theme.keep : Color.accentColor)
                    Text(progress.done == progress.total
                         ? "Tutorial completato: \(progress.total) esercizi su \(progress.total)."
                         : "\(progress.done) di \(progress.total) esercizi completati")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Prima di cominciare") {
                Text(tutorial.preparation)
                    .font(.subheadline)
                GuideDestinationLink(destination: tutorial.destination, openTab: openTab)
                if let chapter = GuideBook.chapter(tutorial.chapterID) {
                    NavigationLink {
                        GuideChapterView(chapter: chapter, openTab: openTab)
                    } label: {
                        Label("Leggi il capitolo «\(chapter.title)»", systemImage: "book")
                    }
                }
            }

            Section("Esercizi") {
                ForEach(Array(tutorial.tasks.enumerated()), id: \.element.id) { index, task in
                    TutorialTaskRow(task: task, number: index + 1)
                }
            }
        }
        .navigationTitle(tutorial.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Un esercizio: cosa fare, cosa si deve vedere e la spunta (automatica o manuale).
private struct TutorialTaskRow: View {
    let task: TutorialTask
    let number: Int

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let isDone = env.isTutorialTaskDone(task)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? Theme.keep : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(number). \(task.title)")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(isDone ? "Completato" : (task.event != nil ? "Si spunta da solo quando lo fai" : "Segnalo tu quando l'hai provato"))
                        .font(.caption)
                        .foregroundStyle(isDone ? Theme.keep : Color.secondary)
                }
                Spacer(minLength: 0)
                if task.event != nil {
                    Image(systemName: "wand.and.stars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            Label {
                Text(task.howTo)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "hand.point.right")
                    .foregroundStyle(Color.accentColor)
            }
            Label {
                Text(task.check)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "eye")
                    .foregroundStyle(.secondary)
            }
            if task.event == nil {
                Toggle("Fatto", isOn: Binding(
                    get: { env.history.isChecked(task.manualStorageID) },
                    set: { env.history.setChecked($0, id: task.manualStorageID) }
                ))
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Esercizio \(number): \(task.title), \(isDone ? "completato" : "da fare")")
        .accessibilityIdentifier("tutorial.task.\(task.id)")
    }
}
