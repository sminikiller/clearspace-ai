import SwiftUI

/// Introduzione al primo avvio: spiega cosa verrà analizzato e che nulla viene eliminato automaticamente,
/// poi chiede il permesso di accedere a Foto.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var page = 0
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                safetyPage.tag(1)
                accessPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(Theme.background)
        .interactiveDismissDisabled()
    }

    private var welcomePage: some View {
        OnboardingPage(
            systemImage: "sparkles.rectangle.stack",
            title: "Benvenuto in ClearSpace",
            message: "Meno spazio occupato, più controllo sui tuoi ricordi. ClearSpace trova duplicati, contenuti simili e file ingombranti e ti accompagna nella pulizia con pochi gesti.",
            points: [
                ("hand.draw", "Scorri: a destra conservi, a sinistra proponi l'eliminazione."),
                ("square.on.square", "I duplicati esatti sono distinti dalle semplici somiglianze."),
                ("externaldrive", "Vedi sempre quanto spazio recuperi su iPhone e quanto su iCloud.")
            ]
        )
    }

    private var safetyPage: some View {
        OnboardingPage(
            systemImage: "checkmark.shield",
            title: "Decidi sempre tu",
            message: "Nessun contenuto viene eliminato automaticamente, nemmeno su suggerimento dell'intelligenza artificiale.",
            points: [
                ("list.bullet.rectangle", "Uno swipe non cancella nulla: aggiunge soltanto alla lista di revisione."),
                ("arrow.uturn.backward", "Puoi annullare ogni scelta prima della conferma finale."),
                ("lock", "Preferiti e contenuti che scegli tu restano protetti."),
                ("iphone", "Le analisi avvengono sul dispositivo: foto e documenti non lasciano l'iPhone.")
            ]
        )
    }

    private var accessPage: some View {
        OnboardingPage(
            systemImage: "photo.on.rectangle.angled",
            title: "Accesso a Foto",
            message: "Per analizzare foto e video ClearSpace ha bisogno del tuo permesso. Verranno letti date, dimensioni e anteprime; gli originali su iCloud non vengono scaricati senza il tuo consenso.",
            points: [
                ("icloud", "Con Foto di iCloud attivo, eliminare una foto la rimuove anche da iCloud e dagli altri dispositivi."),
                ("clock.arrow.circlepath", "Le foto eliminate restano recuperabili per 30 giorni in Eliminati di recente.")
            ]
        )
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if page < 2 {
                Button {
                    withAnimation { page += 1 }
                } label: {
                    Text("Continua")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button {
                    requestAccess()
                } label: {
                    if isRequesting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(env.photos.canRead ? "Inizia l'analisi" : "Consenti l'accesso a Foto")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRequesting)

                Button("Non ora") {
                    finish(startScan: false)
                }
                .font(.subheadline)
            }
        }
    }

    private func requestAccess() {
        isRequesting = true
        Task {
            if !env.photos.canRead {
                await env.photos.requestAccess()
            }
            isRequesting = false
            finish(startScan: env.photos.canRead)
        }
    }

    private func finish(startScan: Bool) {
        env.preferences.update { $0.hasCompletedOnboarding = true }
        if startScan && !env.scan.isRunning {
            env.scan.start(deep: true)
        }
    }
}

private struct OnboardingPage: View {
    let systemImage: String
    let title: String
    let message: String
    let points: [(String, String)]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: systemImage)
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.heroGradient)
                    .padding(.top, 48)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: point.0)
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 30)
                                .accessibilityHidden(true)
                            Text(point.1)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .card()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 60)
        }
    }
}
