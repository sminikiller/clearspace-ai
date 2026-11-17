import AVFoundation
import Observation
import SwiftUI
import UIKit

/// Riproduzione di un video dentro una carta: senza i controlli di sistema, che intercetterebbero
/// i gesti di swipe. Parte senza audio, così non interrompe la musica in ascolto.
@MainActor
@Observable
final class InlineVideoController {

    private(set) var player: AVPlayer?
    private(set) var isLoading = false
    private(set) var isUnavailable = false
    private(set) var isPlaying = false
    private(set) var isMuted = true
    private(set) var isFast = false
    /// Posizione nella riproduzione (0…1).
    private(set) var progress = 0.0
    private(set) var duration = 0.0
    /// Fotogrammi distribuiti lungo il video: danno un'idea del contenuto senza guardarlo tutto.
    private(set) var frames: [UIImage] = []

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var loadedItemID: UUID?

    func load(item: IndexedItem, provider: ThumbnailProvider, allowNetwork: Bool, autoplay: Bool) async {
        if loadedItemID == item.id && (player != nil || isLoading) { return }
        teardown()
        loadedItemID = item.id
        isLoading = true
        isUnavailable = false
        duration = item.duration

        let playerItem = await provider.playerItem(for: item, allowNetwork: allowNetwork)
        // Se nel frattempo è stato chiesto un altro video, questo non serve più.
        guard loadedItemID == item.id else { return }
        guard let playerItem else {
            isLoading = false
            isUnavailable = true
            return
        }

        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.isMuted = isMuted
        newPlayer.actionAtItemEnd = .none
        player = newPlayer
        isLoading = false

        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.update(seconds: time.seconds)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.restart()
            }
        }

        if autoplay {
            play()
        }
        await generateFrames(from: playerItem.asset, itemID: item.id)
    }

    private func update(seconds: Double) {
        guard let player else { return }
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
        if duration > 0 && seconds.isFinite {
            progress = min(1, max(0, seconds / duration))
        }
    }

    /// A fine video si ricomincia da capo: mentre si decide, il video continua a scorrere.
    private func restart() {
        guard let player else { return }
        player.seek(to: .zero)
        if isPlaying {
            player.play()
            if isFast { player.rate = 2 }
        }
    }

    func play() {
        guard let player else { return }
        configureAudioSession()
        player.play()
        if isFast { player.rate = 2 }
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        configureAudioSession()
    }

    func toggleSpeed() {
        isFast.toggle()
        if isPlaying {
            player?.rate = isFast ? 2 : 1
        }
    }

    func seek(toFraction fraction: Double) {
        guard let player, duration > 0 else { return }
        let clamped = min(1, max(0, fraction))
        progress = clamped
        let time = CMTime(seconds: clamped * duration, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func teardown() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
        loadedItemID = nil
        isLoading = false
        isPlaying = false
        progress = 0
        frames = []
    }

    /// Senza audio la riproduzione si mescola a ciò che l'utente sta ascoltando; con l'audio attivo
    /// si comporta come un normale lettore.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        if isMuted {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        } else {
            try? session.setCategory(.playback, mode: .default, options: [])
        }
    }

    private func generateFrames(from asset: AVAsset, itemID: UUID) async {
        guard duration > 3 else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        let tolerance = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let count = 6
        var collected: [UIImage] = []
        for index in 0..<count {
            let seconds = duration * (Double(index) + 0.5) / Double(count)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let frame = try? await generator.image(at: time).image else { continue }
            guard loadedItemID == itemID else { return }
            collected.append(UIImage(cgImage: frame))
            frames = collected
        }
    }
}

/// Livello video senza controlli.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // `layerClass` garantisce il tipo del livello.
        layer as! AVPlayerLayer
    }
}

/// Video riproducibile dentro una carta: un tocco avvia o mette in pausa, la barra permette di
/// spostarsi, i fotogrammi in basso mostrano i momenti principali.
struct InlineVideoView: View {
    let item: IndexedItem
    /// Avvia la riproduzione anche se quella automatica è disattivata: serve quando il video è stato
    /// scelto apposta per guardarlo.
    var forcesAutoplay = false
    /// Un'altra schermata copre il video (dettagli, confronto, schermo intero): la riproduzione si
    /// ferma e riprende quando si torna, così non suonano due video insieme.
    var isSuspended = false

    @Environment(AppEnvironment.self) private var env
    @State private var controller = InlineVideoController()
    @State private var forcesNetwork = false
    @State private var pausedBySuspension = false

    private struct LoadKey: Equatable {
        let id: UUID
        let forcesNetwork: Bool
    }

    var body: some View {
        ZStack {
            // Finché il video non è pronto resta visibile la copertina.
            ItemThumbnailView(item: item, pointSide: 430, fill: false, allowsNetwork: true)
            if let player = controller.player {
                PlayerLayerView(player: player)
            }
            centerIndicator
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            controller.togglePlayback()
        }
        .overlay(alignment: .topTrailing) {
            if controller.player != nil {
                sideButtons
                    .padding(10)
            }
        }
        .overlay(alignment: .bottom) {
            if controller.player != nil {
                bottomControls
            }
        }
        .task(id: LoadKey(id: item.id, forcesNetwork: forcesNetwork)) {
            let allowNetwork = env.canDownloadForViewing || (forcesNetwork && env.conditions.isOnline)
            await controller.load(
                item: item,
                provider: env.thumbnails,
                allowNetwork: allowNetwork,
                autoplay: env.preferences.values.autoplayVideos || forcesNetwork || forcesAutoplay
            )
        }
        .onChange(of: isSuspended) { _, suspended in
            if suspended {
                pausedBySuspension = controller.isPlaying
                controller.pause()
            } else if pausedBySuspension {
                pausedBySuspension = false
                controller.play()
            }
        }
        .onDisappear {
            controller.teardown()
        }
    }

    // MARK: - Indicatori

    @ViewBuilder
    private var centerIndicator: some View {
        if controller.isLoading {
            ProgressView()
                .tint(.white)
                .padding(18)
                .background(.black.opacity(0.45), in: Circle())
        } else if controller.isUnavailable {
            VStack(spacing: 10) {
                Image(systemName: "icloud.slash")
                    .font(.title)
                Text(env.conditions.isOnline
                     ? "Il video è solo su iCloud"
                     : "Il video è solo su iCloud: serve una connessione")
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                if env.conditions.isOnline {
                    Button("Riproduci comunque") {
                        forcesNetwork = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(24)
        } else if controller.player != nil && !controller.isPlaying {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 62))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.45))
                .accessibilityHidden(true)
        }
    }

    private var sideButtons: some View {
        VStack(spacing: 8) {
            roundButton(
                systemImage: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: controller.isMuted ? "Attiva l'audio" : "Disattiva l'audio"
            ) {
                controller.toggleMute()
            }
            Button {
                controller.toggleSpeed()
            } label: {
                Text(controller.isFast ? "2×" : "1×")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.isFast ? "Velocità normale" : "Velocità doppia")
        }
    }

    private func roundButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Barra in basso

    private var bottomControls: some View {
        VStack(spacing: 6) {
            if !controller.frames.isEmpty {
                frameStrip
            }
            HStack(spacing: 8) {
                Text(Format.duration(controller.progress * controller.duration))
                scrubber
                Text(Format.duration(controller.duration))
            }
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        // Spazio per il pulsante "a tutto schermo" della carta, in basso a destra.
        .padding(.trailing, 44)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        )
    }

    /// Barra di avanzamento: toccandola o trascinandola ci si sposta nel video.
    private var scrubber: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(height: 4)
                Capsule()
                    .fill(.white)
                    .frame(width: max(4, geometry.size.width * controller.progress), height: 4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let width = max(1, geometry.size.width)
                        controller.seek(toFraction: Double(value.location.x / width))
                    }
            )
        }
        .frame(height: 26)
        .accessibilityElement()
        .accessibilityLabel("Posizione nel video")
        .accessibilityValue(Format.percent(controller.progress))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: controller.seek(toFraction: controller.progress + 0.1)
            case .decrement: controller.seek(toFraction: controller.progress - 0.1)
            @unknown default: break
            }
        }
    }

    /// Momenti del video: un tocco porta a quel punto.
    private var frameStrip: some View {
        HStack(spacing: 3) {
            ForEach(Array(controller.frames.enumerated()), id: \.offset) { index, frame in
                // La larghezza la decide il riquadro, non il fotogramma: un'immagine che "riempie"
                // chiederebbe più spazio di quello disponibile e spingerebbe la barra fuori dalla carta.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .overlay {
                        Image(uiImage: frame)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let count = Double(max(controller.frames.count, 1))
                        controller.seek(toFraction: (Double(index) + 0.5) / count)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}
