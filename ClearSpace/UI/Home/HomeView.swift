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
                VStack(spacing: Theme.spacing) {
                    accessBanner
                    storageCards
                    potentialCard
                    quickCleanupCard
                    similarShortcutCard
                    resumeCard
                    modesSection
                    categoriesSection
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

            Divider().overlay(.white.opacity(0.4))

            potentialRow("Foto duplicate e simili", summary.potential.photoDuplicatesAndSimilar)
            potentialRow("Video ingombranti", summary.potential.bulkyVideos)
            potentialRow("Screenshot e documenti", summary.potential.screenshotsAndDocuments)

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
        .accessibilityElement(children: .combine)
    }

    private func potentialRow(_ title: String, _ bytes: Int64) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(Format.bytes(bytes))
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Pulizia rapida

    private var quickCleanupCard: some View {
        let recommendations = RecommendationEngine.recommendations(summary: summary, learner: env.history.learner)
        return VStack(alignment: .leading, spacing: 12) {
            Label("Pulizia rapida", systemImage: "bolt.fill")
                .font(.headline)
            Text(RecommendationEngine.headline(for: recommendations, hasIndexedContent: summary.totalCount > 0))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Rivedi per primi gli elementi con maggiore potenziale di recupero, senza cancellazioni automatiche.")
                .font(.footnote)
                .foregroundStyle(.secondary)

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

    /// Scorciatoia verso i gruppi di foto simili ancora da decidere: è lì che si recupera spazio
    /// tenendo solo lo scatto migliore.
    @ViewBuilder
    private var similarShortcutCard: some View {
        let stat = summary.stat(.similarPhotos)
        if stat.reviewableCount > 0 {
            NavigationLink {
                GroupListView(collection: .similarPhotos)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.down.right.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scegli le foto migliori")
                            .font(.headline)
                        Text("\(Format.plural(stat.reviewableCount, "scatto simile", "scatti simili")) da decidere: tieni il migliore di ogni gruppo.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
        }
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
