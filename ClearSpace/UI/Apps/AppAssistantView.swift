import SwiftUI

/// Assistente app: procedure guidate per liberare spazio nelle altre applicazioni.
/// iOS isola i dati di ogni app: ClearSpace non può leggerli né cancellarli, ma può indicare
/// lo strumento giusto dentro ciascuna app e tenere traccia di ciò che è già stato fatto.
struct AppAssistantView: View {
    @Environment(AppEnvironment.self) private var env

    private var completedCount: Int {
        AppGuides.apps.filter { env.history.isChecked($0.id) }.count
    }

    var body: some View {
        List {
            Section {
                InfoBanner(text: "iOS non permette a un'app di leggere o cancellare i dati delle altre. Qui trovi, passo per passo, dove liberare spazio dentro ciascuna app.")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Checklist di pulizia: \(completedCount) di \(AppGuides.apps.count) completate")
                        .font(.subheadline.weight(.medium))
                    ProgressView(value: Double(completedCount), total: Double(AppGuides.apps.count))
                }
                .padding(.vertical, 4)
            }

            Section("Da fare") {
                let pending = AppGuides.apps.filter { !env.history.isChecked($0.id) }
                if pending.isEmpty {
                    Text("Hai completato tutte le procedure.")
                        .foregroundStyle(.secondary)
                }
                ForEach(pending) { guide in
                    link(for: guide)
                }
            }

            let done = AppGuides.apps.filter { env.history.isChecked($0.id) }
            if !done.isEmpty {
                Section("Completate") {
                    ForEach(done) { guide in
                        link(for: guide)
                    }
                }
            }
        }
        .navigationTitle("Assistente app")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func link(for guide: AppGuide) -> some View {
        NavigationLink {
            GuideDetailView(guide: guide)
        } label: {
            GuideRow(guide: guide, isDone: env.history.isChecked(guide.id))
        }
    }
}

struct GuideRow: View {
    let guide: AppGuide
    let isDone: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: guide.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(guide.title)
                Text(guide.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.keep)
                    .accessibilityLabel("Completata")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Procedura passo per passo, con la possibilità di segnarla come completata.
struct GuideDetailView: View {
    let guide: AppGuide

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        List {
            Section {
                Text(guide.summary)
                    .font(.subheadline)
            }

            Section("Passaggi") {
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.accentColor, in: Circle())
                        Text(step)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }

            if let note = guide.note {
                Section("Da sapere") {
                    Label(note, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                }
            }

            Section {
                Toggle("Procedura completata", isOn: Binding(
                    get: { env.history.isChecked(guide.id) },
                    set: { env.history.setChecked($0, id: guide.id) }
                ))
                Button("Apri l'app Impostazioni") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } footer: {
                Text("Il pulsante apre le impostazioni di ClearSpace: da lì puoi tornare all'elenco principale delle Impostazioni di iPhone.")
            }
        }
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
