import Observation
import SwiftUI
import UIKit

/// Carica l'immagine di un elemento per mostrarla in grande e ne segue lo stato.
///
/// Con Foto di iCloud e «Ottimizza spazio iPhone» sul dispositivo resta spesso solo un'anteprima
/// a bassa qualità. Qui arriva prima quella, poi la versione nitida: scaricata da iCloud quando la
/// rete lo consente, con l'avanzamento visibile. Se il download non è permesso lo stato lo dice,
/// così l'interfaccia può offrire di scaricarla comunque invece di lasciare una foto sfocata.
@MainActor
@Observable
final class DisplayImageLoader {

    enum Phase: Equatable {
        case loading
        /// È visibile la versione provvisoria; quella nitida sta arrivando.
        case provisional
        case downloading
        case final
        /// La versione nitida è su iCloud e non è stata scaricata.
        case needsNetwork
        case failed
    }

    private(set) var image: UIImage?
    private(set) var phase: Phase = .loading
    /// Avanzamento del download da iCloud (0…1).
    private(set) var progress = 0.0
    /// La versione nitida tarda ad arrivare: conviene dirlo.
    private(set) var isSlow = false
    /// Cambia a ogni nuovo tentativo chiesto dall'utente: le viste lo usano per ricaricare.
    private(set) var attempt = 0

    /// L'utente ha chiesto di scaricare comunque, anche con la rete a consumo.
    @ObservationIgnored private var forcesNetwork = false
    @ObservationIgnored private var slowTask: Task<Void, Never>?

    /// Scarica la versione nitida anche se le impostazioni di rete non lo farebbero da sole.
    func requestDownload() {
        forcesNetwork = true
        attempt += 1
    }

    func load(item: IndexedItem, pixelSide: CGFloat, env: AppEnvironment) async {
        let allowNetwork = env.canDownloadForViewing || (forcesNetwork && env.conditions.isOnline)
        // L'immagine precedente resta visibile finché non arriva la nuova: nel confronto tra foto simili
        // il passaggio da una all'altra deve essere immediato, senza schermate vuote.
        setPhase(.loading)
        progress = 0
        var receivedAny = false
        var receivedFinal = false
        let stream = env.thumbnails.displayEvents(for: item, pixelSide: pixelSide, allowNetwork: allowNetwork)
        for await event in stream {
            switch event {
            case .image(let next, let isFinal):
                image = next
                receivedAny = true
                if isFinal {
                    receivedFinal = true
                    setPhase(.final)
                } else if !receivedFinal {
                    setPhase(.provisional)
                }
            case .downloading(let value):
                progress = value
                if !receivedFinal {
                    setPhase(.downloading)
                }
            case .needsNetwork:
                // Nessuna immagine per questo elemento: quella mostrata apparteneva al precedente.
                if !receivedAny { image = nil }
                if !receivedFinal {
                    setPhase(.needsNetwork)
                }
            case .failed:
                if !receivedAny { image = nil }
                if !receivedFinal {
                    setPhase(.failed)
                }
            }
        }
    }

    private func setPhase(_ newPhase: Phase) {
        guard newPhase != phase || newPhase == .loading else { return }
        phase = newPhase
        isSlow = false
        slowTask?.cancel()
        slowTask = nil
        guard newPhase == .provisional else { return }
        // Una versione provvisoria che resta a lungo sullo schermo va segnalata.
        slowTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_200))
            guard !Task.isCancelled, let self, self.phase == .provisional else { return }
            self.isSlow = true
        }
    }
}

/// Avviso sullo stato di un'immagine in caricamento: download in corso, versione nitida non
/// disponibile, pulsante per scaricarla.
struct ImageLoadStatusView: View {
    let loader: DisplayImageLoader

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        switch loader.phase {
        case .downloading:
            pill {
                ProgressView(value: min(max(loader.progress, 0), 1))
                    .progressViewStyle(.circular)
                    .tint(.white)
                Text("Scarico la versione nitida da iCloud…")
            }
        case .provisional:
            if loader.isSlow {
                pill {
                    ProgressView()
                        .tint(.white)
                    Text("Carico la versione nitida…")
                }
            }
        case .needsNetwork:
            if env.conditions.isOnline {
                Button {
                    loader.requestDownload()
                } label: {
                    pill {
                        Image(systemName: "icloud.and.arrow.down")
                        Text(loader.image == nil
                             ? "Scarica l'immagine da iCloud"
                             : "Anteprima a bassa qualità · Scarica quella nitida")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Scarica da iCloud la versione nitida di questa immagine")
            } else {
                pill {
                    Image(systemName: "wifi.slash")
                    Text("Versione nitida solo su iCloud: serve una connessione")
                }
            }
        case .failed:
            if loader.image != nil {
                Button {
                    loader.requestDownload()
                } label: {
                    pill {
                        Image(systemName: "arrow.clockwise")
                        Text("Versione nitida non caricata · Riprova")
                    }
                }
                .buttonStyle(.plain)
            }
        case .loading, .final:
            EmptyView()
        }
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.65), in: Capsule())
    }
}

/// Immagine di un elemento mostrata in grande, con ingrandimento e spostamento decisi da chi la usa.
struct ItemImageView: View {
    let item: IndexedItem
    /// Lato lungo richiesto, in pixel.
    var pixelSide: CGFloat = 2_048
    var zoom: CGFloat = 1
    var zoomAnchor: UnitPoint = .center
    var pan: CGSize = .zero
    /// Mostra gli avvisi sullo stato del caricamento.
    var showsStatus = true

    @Environment(AppEnvironment.self) private var env
    @State private var loader = DisplayImageLoader()

    private struct LoadKey: Equatable {
        let id: UUID
        let attempt: Int
    }

    var body: some View {
        ZStack {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(zoom, anchor: zoomAnchor)
                    .offset(pan)
                    .accessibilityHidden(true)
            } else if loader.phase == .failed || loader.phase == .needsNetwork {
                Image(systemName: item.category.systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .bottom) {
            if showsStatus {
                ImageLoadStatusView(loader: loader)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .task(id: LoadKey(id: item.id, attempt: loader.attempt)) {
            await loader.load(item: item, pixelSide: pixelSide, env: env)
        }
    }
}
