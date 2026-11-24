import AVKit
import QuickLook
import SwiftUI

/// Anteprima a tutto schermo: foto ingrandibile, video, documento o audio. Con più elementi si scorre
/// in orizzontale dall'uno all'altro, come nell'app Foto.
/// Le azioni disponibili cambiano soltanto lo stato di revisione: da qui non si elimina nulla.
struct ItemPreviewScreen: View {
    /// Elementi tra cui si scorre, nell'ordine in cui compaiono nella schermata di partenza.
    let itemIDs: [UUID]
    /// Mostra i pulsanti Conserva / Da eliminare. Va disattivato dove la scelta avviene altrove.
    var showsActions = true

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var currentID: UUID?
    @State private var showsDetails = false
    @State private var toast: String?

    /// - Parameters:
    ///   - itemID: elemento da mostrare per primo.
    ///   - itemIDs: elementi tra cui scorrere; se mancano (o non contengono `itemID`) si vede solo quello.
    init(itemID: UUID, itemIDs: [UUID]? = nil, showsActions: Bool = true) {
        if let itemIDs, itemIDs.contains(itemID) {
            self.itemIDs = itemIDs
        } else {
            self.itemIDs = [itemID]
        }
        self.showsActions = showsActions
        self._currentID = State(initialValue: itemID)
    }

    /// Elementi attorno a quello aperto: bastano per scorrere a lungo senza preparare migliaia di pagine.
    nonisolated static func window(_ ids: [UUID], around id: UUID, radius: Int = 150) -> [UUID] {
        guard let index = ids.firstIndex(of: id) else { return [id] }
        let low = max(0, index - radius)
        let high = min(ids.count - 1, index + radius)
        return Array(ids[low...high])
    }

    private var activeID: UUID {
        currentID ?? itemIDs[0]
    }

    var body: some View {
        let _ = env.store.revision
        NavigationStack {
            Group {
                if let item = env.store.item(activeID) {
                    VStack(spacing: 0) {
                        pages
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if showsActions {
                            actionBar(for: item)
                        }
                    }
                    .navigationTitle(title(for: item))
                } else {
                    ContentUnavailableView(
                        "Elemento non più disponibile",
                        systemImage: "questionmark.circle",
                        description: Text("Potrebbe essere stato eliminato o spostato.")
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsDetails = true
                    } label: {
                        Label("Dettagli", systemImage: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showsDetails) {
                ItemDetailView(itemID: activeID)
            }
            .toast($toast)
        }
    }

    /// "3 di 12" quando si può scorrere, altrimenti il nome dell'elemento.
    private func title(for item: IndexedItem) -> String {
        guard itemIDs.count > 1, let index = itemIDs.firstIndex(of: item.id) else { return item.displayTitle }
        return "\(index + 1) di \(itemIDs.count)"
    }

    @ViewBuilder
    private var pages: some View {
        if itemIDs.count < 2 {
            if let item = env.store.item(activeID) {
                media(for: item, isActive: true)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(itemIDs, id: \.self) { id in
                            page(for: id)
                                .containerRelativeFrame([.horizontal, .vertical])
                                .clipped()
                                .id(id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentID)
                .scrollIndicators(.hidden)
                .background(Color.black)
                .onAppear {
                    proxy.scrollTo(activeID)
                }
            }
        }
    }

    @ViewBuilder
    private func page(for id: UUID) -> some View {
        if let item = env.store.item(id) {
            media(for: item, isActive: id == activeID)
        } else {
            ZStack {
                Color.black
                Text("Elemento non più disponibile")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private func media(for item: IndexedItem, isActive: Bool) -> some View {
        switch item.category {
        case .photo:
            ZoomablePhotoView(item: item, isActive: isActive)
        case .video:
            VideoPlaybackView(item: item, isActive: isActive)
        case .audio:
            AudioPlaybackView(item: item)
        case .pdf, .office, .archive, .otherDocument, .unknown:
            DocumentPreviewView(item: item)
        }
    }

    private func actionBar(for item: IndexedItem) -> some View {
        AdaptiveStack(spacing: 12) {
            Button {
                let result = env.safety.apply(.delete, to: item.id)
                handle(result)
            } label: {
                Label("Da eliminare", systemImage: "trash")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.remove)

            Button {
                env.safety.apply(.keep, to: item.id)
                advanceOrDismiss()
            } label: {
                Label("Conserva", systemImage: "checkmark")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.keep)
        }
        .controlSize(.large)
        .padding()
        .background(.bar)
        // La foto resta grande anche con il testo molto ingrandito.
        .compactControlText()
    }

    private func handle(_ result: MarkResult?) {
        switch result {
        case .blocked(let reason):
            toast = reason.message
        case .appliedWithCaution:
            toast = "Aggiunto alla revisione. Contenuto potenzialmente importante: verrà evidenziato."
        case .applied:
            advanceOrDismiss()
        case nil:
            toast = "Elemento non più disponibile."
        }
    }

    /// Dopo una scelta si passa all'elemento successivo; con un solo elemento si chiude.
    private func advanceOrDismiss() {
        guard itemIDs.count > 1, let index = itemIDs.firstIndex(of: activeID), index + 1 < itemIDs.count else {
            dismiss()
            return
        }
        withAnimation {
            currentID = itemIDs[index + 1]
        }
    }
}

/// Foto a piena risoluzione, ingrandibile. Se sul dispositivo c'è solo l'anteprima a bassa qualità
/// lo dice e permette di scaricare quella nitida: è qui che si controlla se uno scatto è riuscito.
struct ZoomablePhotoView: View {
    let item: IndexedItem
    /// La pagina in vista. Le pagine accanto si preparano con una versione più leggera e senza rete.
    var isActive = true

    @Environment(AppEnvironment.self) private var env
    @State private var loader = DisplayImageLoader()

    private struct LoadKey: Equatable {
        let id: UUID
        let attempt: Int
        let isActive: Bool
    }

    var body: some View {
        ZStack {
            Color.black
            if let image = loader.image {
                ZoomableImageView(image: image)
            } else if loader.phase == .failed || loader.phase == .needsNetwork {
                ContentUnavailableView(
                    "Immagine non disponibile",
                    systemImage: "icloud.slash",
                    description: Text("L'originale è solo su iCloud e non è stato scaricato.")
                )
                .foregroundStyle(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .overlay(alignment: .bottom) {
            ImageLoadStatusView(loader: loader)
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
        }
        .task(id: LoadKey(id: item.id, attempt: loader.attempt, isActive: isActive)) {
            // A tutto schermo si sta esaminando proprio questa foto: va mostrata nitida.
            await loader.load(item: item, pixelSide: isActive ? 3_000 : 1_600, env: env, inspecting: isActive)
        }
    }
}

/// Riproduzione di un video, con velocità doppia per scorrerlo rapidamente.
struct VideoPlaybackView: View {
    let item: IndexedItem
    /// La pagina in vista: scorrendo via, il video si ferma.
    var isActive = true

    @Environment(AppEnvironment.self) private var env
    @State private var player: AVPlayer?
    @State private var isUnavailable = false
    @State private var isFast = false
    /// L'utente ha chiesto di riprodurre comunque, anche con la rete a consumo.
    @State private var forcesNetwork = false

    private struct LoadKey: Equatable {
        let id: UUID
        let forcesNetwork: Bool
    }

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else if isUnavailable {
                ContentUnavailableView {
                    Label("Video non disponibile", systemImage: "icloud.slash")
                } description: {
                    Text(env.conditions.isOnline
                         ? "Il video è solo su iCloud e non è stato scaricato."
                         : "Il video è solo su iCloud: serve una connessione.")
                } actions: {
                    if env.conditions.isOnline {
                        Button("Riproduci comunque") {
                            forcesNetwork = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .foregroundStyle(.white)
            } else {
                ProgressView("Caricamento…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            if player != nil {
                Button(isFast ? "Velocità 2×" : "Velocità 1×") {
                    isFast.toggle()
                    player?.rate = isFast ? 2 : 1
                }
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.6))
                .padding()
                .accessibilityHint("Cambia la velocità di riproduzione")
            }
        }
        .task(id: LoadKey(id: item.id, forcesNetwork: forcesNetwork)) {
            player = nil
            isUnavailable = false
            let allowNetwork = env.canDownloadForViewing || (forcesNetwork && env.conditions.isOnline)
            if let playerItem = await env.thumbnails.playerItem(for: item, allowNetwork: allowNetwork) {
                player = AVPlayer(playerItem: playerItem)
            } else {
                isUnavailable = true
            }
        }
        .onChange(of: isActive) { _, active in
            if !active {
                player?.pause()
            }
        }
        .onDisappear {
            player?.pause()
        }
    }
}

/// Anteprima di un documento con Quick Look.
struct DocumentPreviewView: View {
    let item: IndexedItem

    @Environment(AppEnvironment.self) private var env
    @State private var previewURL: URL?

    var body: some View {
        // Scorre se non ci sta (testo molto grande), altrimenti resta centrato.
        CenteredScrollView {
            documentContent
        }
        .quickLookPreview($previewURL)
    }

    private var documentContent: some View {
        VStack(spacing: 16) {
            ItemThumbnailView(item: item, pointSide: 320, fill: false)
                .frame(maxWidth: 320, maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(item.displayTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("\(item.category.title) · \(Format.bytesOrUnknown(item.estimatedBytes))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if item.traits.contains(.cloudOnly) {
                TagChip(text: "Solo su iCloud Drive", systemImage: "icloud", tint: Theme.info)
            }
            Button {
                previewURL = env.folders.url(for: item)
            } label: {
                Label("Apri anteprima", systemImage: "eye")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

/// Riproduzione di una registrazione con forma d'onda.
struct AudioPlaybackView: View {
    let item: IndexedItem

    @Environment(AppEnvironment.self) private var env
    @State private var controller = AudioPlayerController()
    @State private var bars: [Float] = []

    var body: some View {
        // Scorre se non ci sta (testo molto grande), altrimenti resta centrato.
        CenteredScrollView {
            playerContent
        }
        .task(id: item.id) {
            guard let url = env.folders.url(for: item) else { return }
            controller.load(url: url)
            let analysis = await Task.detached(priority: .userInitiated) {
                try? AudioAnalyzer.analyze(url: url)
            }.value
            if let analysis {
                bars = AudioAnalyzer.waveform(from: analysis.envelope, bars: 90)
            }
        }
        .onDisappear {
            controller.stop()
        }
    }

    private var playerContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text(item.displayTitle)
                .font(.headline)
                .multilineTextAlignment(.center)

            GeometryReader { geometry in
                WaveformView(bars: bars, progress: controller.progress)
                    .contentShape(Rectangle())
                    // Un tocco sulla forma d'onda sposta la riproduzione in quel punto. È un tocco e non
                    // un trascinamento, così non blocca lo scorrimento della schermata.
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let width = max(1, geometry.size.width)
                                controller.seek(toFraction: Double(value.location.x / width))
                            }
                    )
            }
            .frame(height: 90)
            .accessibilityLabel("Forma d'onda")

            HStack {
                Text(Format.duration(controller.currentTime))
                Spacer()
                Text(Format.duration(controller.duration > 0 ? controller.duration : item.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Button {
                controller.togglePlayback()
            } label: {
                Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            .accessibilityLabel(controller.isPlaying ? "Pausa" : "Riproduci")

            if let message = controller.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }
}

/// Disegno della forma d'onda: la parte già riprodotta è colorata.
struct WaveformView: View {
    let bars: [Float]
    var progress: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let count = max(bars.count, 1)
            let spacing: CGFloat = 2
            let barWidth = max(1, (geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, value in
                    Capsule()
                        .fill(Double(index) / Double(count) < progress ? Color.accentColor : Theme.placeholder)
                        .frame(width: barWidth, height: max(3, geometry.size.height * CGFloat(value)))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .overlay {
            if bars.isEmpty {
                ProgressView()
            }
        }
    }
}
