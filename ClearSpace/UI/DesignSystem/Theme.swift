import SwiftUI

/// Colori e misure condivisi dall'interfaccia. Si usano i colori di sistema, così tema scuro,
/// contrasto elevato e testo ingrandito funzionano senza interventi.
enum Theme {
    static let cornerRadius: CGFloat = 18
    static let spacing: CGFloat = 16

    static let keep = Color.green
    static let remove = Color.red
    static let later = Color.orange
    static let info = Color.blue

    static let background = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let placeholder = Color(uiColor: .tertiarySystemFill)

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentColor, Color.indigo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct CardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: message)
            .task(id: message) {
                guard message != nil else { return }
                try? await Task.sleep(for: .seconds(3))
                // Se nel frattempo è arrivato un altro messaggio, questo compito è stato annullato.
                if !Task.isCancelled {
                    message = nil
                }
            }
    }
}

extension View {
    /// Riquadro arrotondato usato per le schede della dashboard.
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Messaggio temporaneo in alto, che scompare da solo.
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
