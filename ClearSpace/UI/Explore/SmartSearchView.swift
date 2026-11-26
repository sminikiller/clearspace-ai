import SwiftUI

/// Ricerca in linguaggio naturale: la richiesta viene tradotta in filtri direttamente sul dispositivo.
struct SmartSearchView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var query = ""
    @State private var parsed: ParsedQuery?
    @State private var resultCount = 0
    @FocusState private var isFocused: Bool

    private let examples = [
        "Screenshot più vecchi di un anno che contengono testo",
        "I 20 video più pesanti girati nel 2024",
        "Foto sfocate degli ultimi 6 mesi",
        "PDF oltre 10 MB",
        "Registrazioni audio di gennaio"
    ]

    var body: some View {
        Group {
            if env.plan.isUnlocked(.smartSearch) {
                content
            } else {
                LockedFeatureView(feature: .smartSearch)
            }
        }
        .navigationTitle("Ricerca intelligente")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var content: some View {
        ReadableList {
            Section {
                HStack {
                    Image(systemName: "sparkle.magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Cosa vuoi trovare?", text: $query)
                        .focused($isFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            runSearch()
                        }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            parsed = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Cancella")
                    }
                }
                Button("Cerca") {
                    runSearch()
                }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("La richiesta viene interpretata sul dispositivo e cerca solo tra i contenuti che hai autorizzato.")
            }

            if let parsed {
                resultsSection(parsed)
            } else {
                suggestionsSections
            }
        }
    }

    @ViewBuilder
    private func resultsSection(_ parsed: ParsedQuery) -> some View {
        Section("Come ho interpretato la richiesta") {
            if parsed.understoodSomething {
                FlowLayout(spacing: 6) {
                    ForEach(Array(parsed.interpretations.enumerated()), id: \.offset) { _, note in
                        TagChip(text: note, tint: .accentColor)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Non ho riconosciuto filtri: prova a indicare un tipo di contenuto, un periodo o una dimensione.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        Section {
            NavigationLink {
                ItemGridScreen(
                    query: .filter(parsed.filter, title: "Risultati", mode: .search(query: query)),
                    limit: parsed.filter.limit
                )
                .onAppear { env.recordTutorial(.searchResults) }
            } label: {
                HStack {
                    Label("Mostra i risultati", systemImage: "square.grid.2x2")
                    Spacer()
                    Text(Format.count(resultCount))
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(resultCount == 0)
        } footer: {
            if resultCount == 0 {
                Text("Nessun elemento corrisponde alla richiesta.")
            }
        }
    }

    @ViewBuilder
    private var suggestionsSections: some View {
        Section("Esempi") {
            ForEach(examples, id: \.self) { example in
                Button(example) {
                    query = example
                    runSearch()
                }
                .foregroundStyle(.primary)
            }
        }
        if !env.history.recentSearches.isEmpty {
            Section("Ricerche recenti") {
                ForEach(env.history.recentSearches, id: \.self) { recent in
                    Button {
                        query = recent
                        runSearch()
                    } label: {
                        Label(recent, systemImage: "clock")
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private func runSearch() {
        env.recordTutorial(.search)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isFocused = false
        let result = NaturalLanguageQueryParser().parse(trimmed)
        parsed = result
        env.history.rememberSearch(trimmed)

        let snapshot = env.store.snapshot()
        let filter = result.filter
        Task {
            let count = await Task.detached(priority: .userInitiated) {
                filter.apply(to: snapshot).count
            }.value
            resultCount = count
        }
    }
}
