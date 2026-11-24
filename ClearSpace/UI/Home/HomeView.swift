import SwiftUI

/// Dashboard: quanto spazio è occupato, quanto è potenzialmente recuperabile
/// e quale operazione conviene fare per prima.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var device: StorageSnapshot?
    @State private var isStarting = false
    @State private var showsSettings = false
    @State private var showsQuickOptions = false
    @State private var showsGoalOptions = false
    @State private var toast: String?

    private var summary: CatalogSummary { env.store.summary }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Prima ciò che si può fare subito: quello che aspetta la conferma, quanto si può liberare e
                // da dove iniziare. Poi lo spazio del telefono, gli altri modi di pulire e la guida.
                VStack(spacing: Theme.spacing) {
                    accessBanner
                    pendingDeletionCard
                    potentialCard
                    startSection
                    resumeCard
                    quickCleanupCard
                    storageCards
                    categoriesSection
                    modesSection
                    guideCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("ClearSpace")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Impostazioni", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showsQuickOptions) {
                QuickCleanupSheet()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showsGoalOptions) {
                GoalCleanupSheet()
                    .presentationDetents([.medium, .large])
            }
            .task(id: env.store.revision) {
                device = DeviceStorage.snapshot()
            }
            .toast($toast)
        }
    }

    // MARK: - Permessi

    @ViewBuilder
    private var accessBanner: some View {
        if env.photos.authorization == .notDetermined {
            VStack(alignment: .leading, spacing: 10) {
                InfoBanner(text: "Per iniziare, consenti a ClearSpace di analizzare foto e video. Nulla viene eliminato senza la tua conferma.")
                Button("Consenti l'accesso a Foto") {
                    Task {
                        await env.photos.requestAccess()
                        if env.photos.canRead {
                            env.scan.start(deep: true)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .card()
        } else if env.photos.isDenied {
            VStack(alignment: .leading, spacing: 10) {
                InfoBanner(
                    text: "L'accesso a Foto non è autorizzato: foto e video non possono essere analizzati.",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: Theme.later
                )
                Button("Apri Impostazioni") {
                    openSettings()
                }
                .buttonStyle(.bordered)
            }
            .card()
        } else if env.photos.isLimited {
            InfoBanner(text: "Accesso limitato: ClearSpace vede soltanto le foto che hai selezionato. Puoi estendere l'accesso dalle Impostazioni.")
        }
    }

    // MARK: - Spazio

    private var storageCards: some View {
        // Affiancate se ci stanno, una sotto l'altra con il testo grande.
        AdaptiveStack(verticalAlignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label("iPhone", systemImage: "iphone")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let device {
                    Text(Format.gigabytes(device.usedBytes))
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("di \(Format.gigabytes(device.totalBytes)) utilizzati")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    StorageBar(fraction: Double(device.usedBytes) / Double(max(device.totalBytes, 1)))
                } else {
                    Text("—")
                        .font(.title.bold())
                }
            }
            .card()
            .accessibilityElement(children: .combine)

            iCloudCard
        }
    }

    private var iCloudCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("iCloud", systemImage: "icloud")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let quota = env.preferences.values.manualICloudQuota, quota.totalGB > 0 {
                Text(String(format: "%.0f GB", quota.usedGB))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(String(format: "di %.0f GB · inserito da te", quota.totalGB))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StorageBar(fraction: quota.usedGB / quota.totalGB, tint: Theme.info)
            } else {
                // iOS non permette alle app di leggere il totale del piano iCloud:
                // si mostra soltanto ciò che l'app ha effettivamente rilevato.
                Text(Format.gigabytes(summary.libraryBytes))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("foto e video analizzati")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NavigationLink("Centro iCloud") {
                    ICloudCenterView()
                }
                .font(.caption.weight(.semibold))
            }
        }
        .card()
    }

    // MARK: - Potenziale

    private var potentialCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spazio potenzialmente recuperabile")
                .font(.subheadline.weight(.semibold))
            Text(Format.gigabytes(summary.potential.total))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("Stima sui contenuti analizzati, non spazio già liberato")
                .font(.caption)
                .opacity(0.85)

            if summary.totalCount == 0 && !env.scan.isRunning && env.photos.canRead {
                // Al primo avvio, o se l'analisi non è mai partita: il primo passo è uno solo.
                Button {
                    env.recordTutorial(.startScan)
                    env.scan.start(deep: true)
                } label: {
                    Label("Analizza la libreria", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.large)
                .accessibilityIdentifier("home.startScan")
            }

            if env.scan.isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Analisi in corso: la stima può crescere.")
                        .font(.caption)
                }
            } else if summary.totalCount > 0 && summary.analysisProgress < 1 {
                Text("Analisi completata al \(Format.percent(summary.analysisProgress)).")
                    .font(.caption)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        // Con VoiceOver il pulsante «Analizza la libreria» resta un pulsante a sé, non una parte del testo.
        .accessibilityElement(children: .contain)
    }

    // MARK: - In attesa di conferma

    /// Ciò che è già stato proposto per l'eliminazione libera spazio solo dopo la conferma: la scheda
    /// lo ricorda, così la pulizia non resta a metà.
    @ViewBuilder
    private var pendingDeletionCard: some View {
        let count = env.store.markedCount
        if count > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("Pronto da liberare")
                        .font(.headline)
                } icon: {
                    Image(systemName: "trash.circle.fill")
                        .foregroundStyle(Theme.remove)
                }
                Text("\(Format.plural(count, "elemento proposto", "elementi proposti")) per l'eliminazione · \(Format.bytes(summary.markedBytes))")
                    .font(.subheadline.weight(.medium))
                Text("Sono nella scheda Revisione: nulla viene eliminato finché non confermi. Lì puoi ancora ripristinare ciò che vuoi tenere.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    env.router.selectedTab = .review
                } label: {
                    Label("Apri la Revisione", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("home.pendingReview")
            }
            .card()
        }
    }

    // MARK: - Pulizia rapida

    private var quickCleanupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pulizia rapida con gli swipe", systemImage: "bolt.fill")
                .font(.headline)
            Text("Ti mostro per primi gli elementi che liberano più spazio: verso sinistra li scarti, verso destra li tieni. Nulla si elimina senza la tua conferma.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                startQuickCleanup()
            } label: {
                if isStarting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Avvia pulizia intelligente")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isStarting)

            Button("Scegli quanti elementi rivedere") {
                showsQuickOptions = true
            }
            .font(.footnote)
        }
        .card()
    }

    // MARK: - Da dove iniziare

    /// Un posto da cui liberare spazio: una categoria con ciò che resta da decidere.
    private struct StartPoint: Identifiable {
        let collection: SmartCollection
        let title: String
        let detail: String
        let systemImage: String
        let tint: Color
        let stat: CollectionStat

        var id: String { collection.rawValue }
    }

    /// Le categorie che di solito liberano più spazio, con qualcosa ancora da decidere, dalla più
    /// ingombrante. Ogni riga porta direttamente al lavoro: i gruppi o la griglia.
    private var startPoints: [StartPoint] {
        let candidates: [(SmartCollection, String, String, String, Color)] = [
            (.similarPhotos, "Foto simili", "Tieni il migliore di ogni scatto", "square.stack.3d.down.right.fill", Theme.keep),
            (.duplicatePhotos, "Foto duplicate", "Copie della stessa foto", "square.on.square", Theme.info),
            (.largeVideos, "Video grandi", "I video che occupano più spazio", "video.fill", Theme.later),
            (.oldScreenshots, "Screenshot vecchi", "Schermate di più di un anno fa", "camera.viewfinder", Color.accentColor),
            (.blurryPhotos, "Foto sfocate", "Mosse o fuori fuoco", "camera.metering.unknown", Theme.remove),
            (.screenRecordings, "Registrazioni dello schermo", "Riprese dello schermo dell'iPhone", "record.circle", Theme.remove)
        ]
        return candidates
            .map { collection, title, detail, image, tint in
                StartPoint(collection: collection, title: title, detail: detail, systemImage: image, tint: tint, stat: summary.stat(collection))
            }
            .filter { $0.stat.reviewableCount > 0 }
            .sorted { $0.stat.reviewableBytes > $1.stat.reviewableBytes }
            .prefix(5)
            .map { $0 }
    }

    @ViewBuilder
    private var startSection: some View {
        let points = startPoints
        if !points.isEmpty {
            VStack(spacing: 10) {
                SectionHeader(title: "Da dove iniziare", subtitle: "Dove c'è più spazio da liberare")
                ForEach(points) { point in
                    NavigationLink {
                        CollectionDestination(collection: point.collection)
                    } label: {
                        startRow(point)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.start.\(point.collection.rawValue)")
                }
            }
        }
    }

    private func startRow(_ point: StartPoint) -> some View {
        HStack(spacing: 12) {
            Image(systemName: point.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(point.tint.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(point.title)
                    .font(.headline)
                Text(point.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Format.plural(point.stat.reviewableCount, "da decidere", "da decidere")) · \(Format.bytes(point.stat.reviewableBytes))")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .card(padding: 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var resumeCard: some View {
        if let session = env.sessions.resumableSessions.first {
            VStack(alignment: .leading, spacing: 10) {
                Label("Riprendi da dove eri rimasto", systemImage: "arrow.clockwise")
                    .font(.headline)
                Text("\(session.title) · \(Format.plural(session.remainingCount, "elemento", "elementi")) da rivedere")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: session.progress)
                AdaptiveStack {
                    Button("Riprendi") {
                        env.recordTutorial(.resumeSession)
                        env.sessions.resume(session.id)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Scarta sessione", role: .destructive) {
                        env.sessions.discard(session.id)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .card()
        }
    }

    // MARK: - Modalità e categorie

    private var modesSection: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "Modalità di pulizia")
            NavigationLink {
                GuidedCleanupView()
            } label: {
                modeRow("Pulizia guidata", "Un percorso passo dopo passo: consigliata", "list.number")
            }
            NavigationLink {
                AdvancedCleanupView()
            } label: {
                modeRow("Pulizia avanzata", "Filtri combinati, cartelle e regole", "slider.horizontal.3")
            }
            Button {
                showsGoalOptions = true
            } label: {
                modeRow("Pulizia per obiettivo", "Scegli quanto spazio vuoi recuperare", "target")
            }
            NavigationLink {
                ArchiveView()
            } label: {
                modeRow("Pulizia annuale", "Rivedi un anno alla volta", "calendar")
            }
        }
        .buttonStyle(.plain)
    }

    /// Guida completa e tutorial con esercizi, con l'avanzamento.
    private var guideCard: some View {
        var done = 0
        var total = 0
        for tutorial in TutorialCatalog.all {
            let progress = env.tutorialProgress(tutorial)
            done += progress.done
            total += progress.total
        }
        return NavigationLink {
            GuideHubView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Guida e tutorial")
                        .font(.headline)
                    Text("Ogni strumento spiegato, con esercizi da provare: \(done) di \(total) completati.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .card(padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.guide")
    }

    private func modeRow(_ title: String, _ subtitle: String, _ systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 14)
        .contentShape(Rectangle())
    }

    private var categoriesSection: some View {
        // Con il testo molto grande una sola colonna: in due le scritte non ci starebbero.
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(spacing: 10) {
            SectionHeader(title: "Categorie")
            LazyVGrid(columns: columns, spacing: 12) {
                NavigationLink {
                    CollectionListView(section: .photos)
                } label: {
                    categoryTile("Foto", "Duplicati, screenshot, simili", "photo.on.rectangle.angled", summary.stat(.allPhotos))
                }
                NavigationLink {
                    CollectionListView(section: .videos)
                } label: {
                    categoryTile("Video", "Grandi, vecchi, registrazioni", "video", summary.stat(.allVideos))
                }
                NavigationLink {
                    DocumentsHubView()
                } label: {
                    categoryTile("Documenti", "PDF, download e file", "doc.on.doc", summary.stat(.allFiles))
                }
                NavigationLink {
                    ICloudCenterView()
                } label: {
                    categoryTile("iCloud Drive", "File online e locali", "icloud", summary.stat(StorageSource.iCloudDrive))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func categoryTile(_ title: String, _ subtitle: String, _ systemImage: String, _ stat: CollectionStat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("\(Format.count(stat.count)) · \(Format.bytes(stat.bytes))")
                .font(.caption.weight(.semibold))
        }
        .card(padding: 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Azioni

    private func startQuickCleanup() {
        env.recordTutorial(.quickCleanup)
        isStarting = true
        let limit = env.preferences.values.quickSessionSize
        Task {
            let started = await env.startSession(title: "Pulizia rapida", mode: .quick) { input in
                CleanupPlanner.quickQueue(input, limit: limit)
            }
            isStarting = false
            if !started {
                toast = summary.totalCount == 0
                    ? "Avvia prima un'analisi dalla scheda Analizza."
                    : "Per ora non ci sono elementi da proporre."
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
