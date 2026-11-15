import Foundation

/// Contenitore a riferimento per raccogliere un valore dentro le callback dei framework Apple.
/// Chi lo usa deve garantire che letture e scritture non avvengano in parallelo.
final class UncheckedBox<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Controlli condivisi dalle analisi in background: pausa, avanzamento e uso della rete.
struct ScanControl: Sendable {
    /// Restituisce `false` se l'analisi deve fermarsi. Resta in attesa finché l'analisi è in pausa.
    let shouldContinue: @Sendable () async -> Bool
    /// Comunica l'avanzamento: elementi completati e totale.
    let progress: @Sendable (Int, Int) async -> Void
    /// Indica se è consentito scaricare contenuti da iCloud in questo momento.
    let networkAllowed: @Sendable () async -> Bool

    /// Controlli che non interrompono mai e non usano la rete: utili per test e operazioni brevi.
    static let unrestricted = ScanControl(
        shouldContinue: { true },
        progress: { _, _ in },
        networkAllowed: { false }
    )
}
