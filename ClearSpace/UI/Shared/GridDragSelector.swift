import SwiftUI
import UIKit

/// Selezione con trascinamento sulle griglie, fatta con un riconoscitore di UIKit montato sullo
/// scorrimento che contiene la griglia.
///
/// Scorrimento e selezione si escludono a vicenda e la scelta va fatta prima che la griglia si muova.
/// Con un gesto di SwiftUI la griglia partiva insieme al dito e veniva fermata solo dopo, e un gesto
/// interrotto dal sistema poteva lasciarla bloccata: per questo a volte non scorreva. Qui lo
/// scorrimento aspetta soltanto la decisione, presa nei primi millimetri di movimento del dito:
/// - si seleziona solo se il dito parte su una cella, chiaramente in orizzontale, con la griglia ferma
///   (`GridDragIntent.startsSelection`);
/// - in tutti gli altri casi il riconoscitore si ritira subito e la griglia scorre come sempre.
///
/// Mentre si seleziona, vicino ai bordi la griglia scorre da sola (`GridAutoScroll`).
/// Va messo come sfondo della griglia: le coordinate passate a `onBegin` e `onMove` sono quelle della
/// griglia, con l'origine nel suo angolo in alto a sinistra.
struct GridDragSelector: UIViewRepresentable {
    /// La selezione con trascinamento è attiva (per esempio dopo «Seleziona»).
    var isEnabled: Bool
    /// Il dito ha toccato `point` e si sta spostando in orizzontale. Restituisce `false` se lì non c'è
    /// una cella: il gesto allora resta uno scorrimento.
    var onBegin: (CGPoint) -> Bool
    /// Il dito, o la griglia durante lo scorrimento automatico, si è spostato: ora il dito è su `point`.
    var onMove: (CGPoint) -> Void
    /// Fine della selezione, anche quando il sistema interrompe il gesto.
    var onEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.accessibilityElementsHidden = true
        view.coordinator = context.coordinator
        context.coordinator.configuration = self
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        context.coordinator.configuration = self
        context.coordinator.anchorDidChange(view)
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Vista invisibile grande quanto la griglia: dà le coordinate dei punti e porta allo scorrimento
    /// che la contiene.
    final class AnchorView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.anchorDidChange(self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var configuration: GridDragSelector? {
            didSet {
                pan?.isEnabled = configuration?.isEnabled ?? false
            }
        }

        private weak var anchor: UIView?
        private weak var scrollView: UIScrollView?
        private var pan: UIPanGestureRecognizer?
        private var isSelecting = false
        private var displayLink: CADisplayLink?
        /// Velocità dello scorrimento automatico, in punti al secondo (negativa verso l'alto).
        private var autoScrollSpeed: CGFloat = 0

        /// Monta il riconoscitore sullo scorrimento che contiene la griglia, oppure lo sposta se la
        /// griglia è finita in un altro scorrimento.
        func anchorDidChange(_ view: UIView) {
            anchor = view
            // Fuori dalla finestra (per esempio sotto un'altra schermata) il riconoscitore resta dov'è.
            guard view.window != nil else { return }
            let container = Self.enclosingScrollView(of: view)
            if container === scrollView && pan != nil {
                return
            }
            detach()
            guard let container else { return }
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.maximumNumberOfTouches = 1
            recognizer.delegate = self
            recognizer.isEnabled = configuration?.isEnabled ?? false
            container.addGestureRecognizer(recognizer)
            pan = recognizer
            scrollView = container
        }

        func detach() {
            finish()
            if let pan {
                pan.view?.removeGestureRecognizer(pan)
            }
            pan = nil
            scrollView = nil
        }

        private static func enclosingScrollView(of view: UIView) -> UIScrollView? {
            var current = view.superview
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView {
                    return scrollView
                }
                current = candidate.superview
            }
            return nil
        }

        // MARK: - Decisione

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let recognizer = gestureRecognizer as? UIPanGestureRecognizer, recognizer === pan,
                  let configuration, configuration.isEnabled,
                  let anchor, let scrollView else {
                return false
            }
            let translation = recognizer.translation(in: anchor)
            let isMoving = scrollView.isDecelerating || scrollView.isDragging
            guard GridDragIntent.startsSelection(
                translation: CGSize(width: translation.x, height: translation.y),
                contentIsMoving: isMoving
            ) else {
                return false
            }
            // Punto in cui il dito ha toccato: deve essere sulla griglia, non sull'intestazione.
            let location = recognizer.location(in: anchor)
            let start = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
            guard anchor.bounds.contains(start) else { return false }
            return configuration.onBegin(start)
        }

        /// Lo scorrimento aspetta la decisione, che arriva dopo pochi punti di movimento del dito.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === pan && otherGestureRecognizer === scrollView?.panGestureRecognizer
        }

        // MARK: - Selezione

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                isSelecting = true
                moveFinger()
                updateAutoScroll()
            case .ended, .cancelled, .failed:
                finish()
            default:
                break
            }
        }

        private func moveFinger() {
            guard let pan, let anchor else { return }
            configuration?.onMove(pan.location(in: anchor))
        }

        private func finish() {
            stopAutoScroll()
            guard isSelecting else { return }
            isSelecting = false
            // Più tardi e non subito: il gesto può finire mentre SwiftUI aggiorna la vista (per esempio
            // quando la selezione viene spenta), e in quel momento non si cambia lo stato.
            let end = configuration?.onEnd
            DispatchQueue.main.async {
                end?()
            }
        }

        // MARK: - Scorrimento automatico vicino ai bordi

        private func updateAutoScroll() {
            guard isSelecting, let pan, let scrollView else {
                stopAutoScroll()
                return
            }
            let finger = pan.location(in: scrollView).y - scrollView.contentOffset.y
            let insets = scrollView.adjustedContentInset
            autoScrollSpeed = GridAutoScroll.speed(
                finger: finger,
                top: insets.top,
                bottom: scrollView.bounds.height - insets.bottom
            )
            if autoScrollSpeed == 0 {
                stopAutoScroll()
            } else if displayLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(stepAutoScroll(_:)))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        }

        @objc private func stepAutoScroll(_ link: CADisplayLink) {
            guard isSelecting, autoScrollSpeed != 0, let scrollView else {
                stopAutoScroll()
                return
            }
            let interval = min(max(link.targetTimestamp - link.timestamp, 1.0 / 120.0), 1.0 / 30.0)
            let insets = scrollView.adjustedContentInset
            let lowest = -insets.top
            let highest = max(lowest, scrollView.contentSize.height - scrollView.bounds.height + insets.bottom)
            let current = scrollView.contentOffset.y
            let next = min(max(current + autoScrollSpeed * CGFloat(interval), lowest), highest)
            guard abs(next - current) > 0.01 else { return }
            scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: next)
            // Il dito è fermo ma sotto di lui ora c'è un'altra cella.
            moveFinger()
        }

        private func stopAutoScroll() {
            displayLink?.invalidate()
            displayLink = nil
            autoScrollSpeed = 0
        }
    }
}
