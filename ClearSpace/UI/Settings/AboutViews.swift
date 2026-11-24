import SwiftUI

/// Dati dell'app mostrati nelle informazioni.
enum AppInfo {
    static let name = "ClearSpace AI"
    static let tagline = "Meno spazio occupato. Più controllo sui tuoi ricordi."
    static let author = "Lorenzo Minichilli"
    static let copyright = "© 2026 Lorenzo Minichilli. Tutti i diritti riservati."

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// "1.0 (8)".
    static var versionDescription: String {
        "\(version) (\(build))"
    }

    /// App di TestFlight, da cui i tester inviano commenti e schermate allo sviluppatore.
    static let testFlightURL = URL(string: "itms-beta://")

    /// Le novità si mostrano una volta dopo un aggiornamento: non al primo avvio (c'è già
    /// l'introduzione), non due volte per la stessa build e mai sopra una sessione di pulizia.
    static func shouldShowWhatsNew(
        hasCompletedOnboarding: Bool,
        lastSeenBuild: String?,
        currentBuild: String,
        isBusy: Bool
    ) -> Bool {
        hasCompletedOnboarding && lastSeenBuild != currentBuild && !isBusy
    }
}

/// Una novità della versione corrente.
struct ReleaseNote: Identifiable {
    let systemImage: String
    let title: String
    let text: String

    var id: String { title }

    static let current: [ReleaseNote] = [
        ReleaseNote(
            systemImage: "hand.draw",
            title: "Scorrere non seleziona più",
            text: "Nelle gallerie e nelle griglie uno scorrimento, anche storto o con la lista ancora in movimento, fa sempre scorrere: la selezione parte solo trascinando il dito chiaramente di lato."
        ),
        ReleaseNote(
            systemImage: "square.grid.3x3",
            title: "Gruppi decisi in un tocco",
            text: "Aprendo un gruppo la migliore ha già il segno verde e le altre il cestino: un tocco cambia la scelta di una foto, «Elimina» elimina subito le altre (con la conferma di iOS) e «Tieni tutte» le conserva."
        ),
        ReleaseNote(
            systemImage: "arrow.left.and.right",
            title: "Scorri tra le foto",
            text: "A tutto schermo passi alla foto vicina scorrendo di lato, come in Foto. Nel confronto la foto segue il dito, anche con lo zoom attivo."
        ),
        ReleaseNote(
            systemImage: "infinity",
            title: "Griglie senza fine",
            text: "Le griglie lunghe caricano da sole le foto successive mentre scorri, senza il pulsante «Mostra altri»."
        ),
        ReleaseNote(
            systemImage: "rectangle.compress.vertical",
            title: "Schermate più ordinate",
            text: "Meno testo e barre più basse nella galleria e nella Revisione, un solo segno per foto, pulsanti spenti ben riconoscibili in tema scuro e niente bande nere sulle carte dello swipe."
        )
    ]
}

/// Icona dell'app in formato grande, con gli angoli arrotondati come sulla schermata Home.
struct AppLogoView: View {
    var side: CGFloat = 96

    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            .accessibilityHidden(true)
    }
}

// MARK: - Informazioni e crediti

/// Chi ha creato l'app, crediti, tecnologie, privacy e versione.
struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    AppLogoView()
                    Text(AppInfo.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(AppInfo.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        TagChip(text: "Versione \(AppInfo.versionDescription)", systemImage: "number", tint: Theme.info)
                        TagChip(text: "Anteprima TestFlight", systemImage: "airplane", tint: Theme.later)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }

            Section("Autore") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ideata e sviluppata da")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(AppInfo.author)
                        .font(.title3.weight(.semibold))
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section("Crediti") {
                creditRow("Idea e progetto", AppInfo.author, systemImage: "lightbulb")
                creditRow("Design dell'interfaccia", AppInfo.author, systemImage: "paintbrush")
                creditRow("Sviluppo", AppInfo.author, systemImage: "chevron.left.forwardslash.chevron.right")
                creditRow("Prove sul campo", "I tester di TestFlight", systemImage: "person.2")
            }

            Section {
                Text("SwiftUI, PhotoKit, Vision, Core Image, AVFoundation, Speech, Swift Charts e CryptoKit.")
                    .font(.subheadline)
            } header: {
                Text("Realizzata con")
            } footer: {
                Text("Solo tecnologie di Apple: nessuna libreria di terze parti, nessuna pubblicità, nessun tracciamento.")
            }

            Section("La tua privacy") {
                privacyRow("iphone", "Le analisi avvengono sul dispositivo: foto, video e documenti non lasciano l'iPhone.")
                privacyRow("lock.shield", "L'indice dei contenuti è cifrato e contiene solo riferimenti, mai copie dei file.")
                privacyRow("hand.raised", "Nulla viene eliminato senza la tua conferma: ClearSpace chiede sempre prima, e per foto e video chiede anche iOS.")
                privacyRow("eye.slash", "Nessun account, nessuna pubblicità, nessun dato inviato a server.")
                NavigationLink("Cosa può fare ClearSpace su iPhone") {
                    CapabilitiesInfoView()
                }
            }

            Section {
                NavigationLink {
                    WhatsNewView()
                } label: {
                    Label("Novità di questa versione", systemImage: "sparkles")
                }
                NavigationLink {
                    GuideHubView()
                } label: {
                    Label("Guida completa e tutorial", systemImage: "graduationcap")
                }
                NavigationLink {
                    QuickGuideView()
                } label: {
                    Label("Guida rapida", systemImage: "questionmark.circle")
                }
                FeedbackLink()
            }

            Section {
                EmptyView()
            } footer: {
                Text(AppInfo.copyright)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationTitle("Informazioni")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func creditRow(_ role: String, _ name: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(name)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
        }
        .accessibilityElement(children: .combine)
    }

    private func privacyRow(_ systemImage: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.keep)
        }
    }
}

/// Apre TestFlight, da cui si inviano commenti e schermate allo sviluppatore.
struct FeedbackLink: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = AppInfo.testFlightURL {
                openURL(url)
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invia un commento")
                    Text("Si apre TestFlight. Puoi anche fare uno screenshot: TestFlight propone di inviarlo con una nota.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "bubble.left.and.text.bubble.right")
            }
        }
    }
}

// MARK: - Novità

/// Le novità di questa versione. Compare da sola una volta dopo ogni aggiornamento.
struct WhatsNewView: View {
    /// Mostra il pulsante per chiudere (quando compare da sola, in un foglio).
    var showsCloseButton = false
    var onClose: () -> Void = {}

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    AppLogoView(side: 72)
                    Text("Novità della versione \(AppInfo.versionDescription)")
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
            Section {
                ForEach(ReleaseNote.current) { note in
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.title)
                                .font(.headline)
                            Text(note.text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: note.systemImage)
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                }
            }
            if showsCloseButton {
                Section {
                    Button {
                        onClose()
                    } label: {
                        Text("Continua")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .accessibilityIdentifier("whatsnew.continue")
                }
            }
        }
        .navigationTitle("Novità")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        onClose()
                    }
                }
            }
        }
    }
}

// MARK: - Guida rapida

/// Come si usa l'app, in breve: gesti, foto simili, selezione rapida, revisione, foto sfocate.
struct QuickGuideView: View {
    var body: some View {
        List {
            Section("Swipe") {
                guideRow("hand.point.right", "Verso destra", "Conservi l'elemento.")
                guideRow("hand.point.left", "Verso sinistra", "Lo proponi per l'eliminazione: va nella lista di Revisione, non viene cancellato.")
                guideRow("hand.point.up", "Verso l'alto", "Apri i dettagli.")
                guideRow("hand.point.down", "Verso il basso", "Decidi più tardi.")
                guideRow("arrow.uturn.backward", "Annulla", "Ripristina l'ultima scelta, anche quella su un intero gruppo.")
            }

            Section("Foto e video simili") {
                guideRow("square.stack.3d.down.right", "Striscia sotto la carta", "Mostra tutto il gruppo: tocca un'anteprima per portarla sulla carta (un video parte subito).")
                guideRow("square.grid.3x3", "Galleria del gruppo", "La migliore ha il segno verde, le altre il cestino: un tocco cambia la scelta, «Elimina» elimina subito le altre (iOS chiede conferma). Le frecce su un'anteprima la aprono a tutto schermo.")
                guideRow("rectangle.stack.badge.play", "Un gruppo dopo l'altro", "Dalla Home «Scegli le foto migliori», oppure in cima all'elenco dei gruppi: dopo «Elimina» o «Tieni tutte» compare da solo il gruppo successivo. «Salta» lo lascia da decidere.")
                guideRow("star.fill", "Stella", "Segna le tue migliori: restano sempre e nella galleria hanno già il segno verde.")
                guideRow("sparkles", "Consiglio", "Le scintille indicano lo scatto che l'app ritiene migliore, con il motivo: nitidezza, volti, occhi aperti, esposizione.")
                guideRow("rectangle.split.2x1", "Confronta", "Guarda le foto in grande una dopo l'altra, con lo zoom che resta sullo stesso punto.")
            }

            Section("Revisione e sicurezza") {
                guideRow("checklist", "Revisione", "Ciò che proponi con gli swipe e nelle griglie resta qui finché non confermi. Dalla galleria di un gruppo puoi invece eliminare subito.")
                guideRow("trash", "Eliminati di recente", "Le foto eliminate restano recuperabili per 30 giorni nell'app Foto: lo spazio si libera quando svuoti quell'album. Dopo un'eliminazione «Apri l'app Foto» ti ci porta.")
                guideRow("lock", "Protezioni", "Preferiti, foto nascoste, album e periodi scelti da te non vengono mai proposti.")
            }

            Section("Foto sfocate") {
                guideRow("icloud.and.arrow.down", "Versione nitida", "Con «Ottimizza spazio iPhone» sul telefono c'è spesso solo un'anteprima: tocca «Scarica quella nitida» oppure apri il confronto o la foto a tutto schermo.")
            }

            Section("Vuoi saperne di più?") {
                NavigationLink {
                    GuideHubView()
                } label: {
                    Label("Guida completa e tutorial", systemImage: "graduationcap")
                }
            }

            Section("Un problema o un'idea?") {
                FeedbackLink()
            }
        }
        .navigationTitle("Guida rapida")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func guideRow(_ systemImage: String, _ title: String, _ text: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
