import SwiftUI

/// Catalogo dei contenuti: categorie, archivio storico, ricerca e strumenti dedicati.
struct ExploreView: View {
    @Environment(AppEnvironment.self) private var env

    private var summary: CatalogSummary { env.store.summary }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SmartSearchView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ricerca intelligente")
                                Text("«Screenshot più vecchi di un anno con testo»")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "sparkle.magnifyingglass")
                        }
                    }
                }

                Section("Categorie") {
                    sectionLink(.photos, stat: summary.stat(.allPhotos)) {
                        CollectionListView(section: .photos)
                    }
                    sectionLink(.videos, stat: summary.stat(.allVideos)) {
                        CollectionListView(section: .videos)
                    }
                    sectionLink(.documents, stat: summary.stat(.allFiles)) {
                        DocumentsHubView()
                    }
                    sectionLink(.audio, stat: summary.stat(.allAudio)) {
                        AudioHubView()
                    }
                }

                Section("Archivio") {
                    NavigationLink {
                        ArchiveView()
                    } label: {
                        Label("Archivio storico e pulizia annuale", systemImage: "calendar")
                    }
                    NavigationLink {
                        TripsView()
                    } label: {
                        Label("Modalità viaggio", systemImage: "airplane")
                    }
                    NavigationLink {
                        NostalgiaView()
                    } label: {
                        Label("Modalità nostalgia", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section("iCloud e altre app") {
                    NavigationLink {
                        ICloudCenterView()
                    } label: {
                        Label("Centro iCloud", systemImage: "icloud")
                    }
                    NavigationLink {
                        AppAssistantView()
                    } label: {
                        Label("Assistente app", systemImage: "square.grid.2x2")
                    }
                }

                Section("Stato") {
                    NavigationLink {
                        ItemGridScreen(query: ItemQuery(
                            title: "Già conservati",
                            subtitle: "Elementi che hai deciso di tenere",
                            predicate: { item, _ in item.reviewStatus == .kept }
                        ))
                    } label: {
                        statusRow("Già conservati", "checkmark.seal", summary.review[.kept] ?? 0)
                    }
                    NavigationLink {
                        ItemGridScreen(query: ItemQuery(
                            title: "Rimandati",
                            subtitle: "Elementi su cui hai rinviato la decisione",
                            predicate: { item, _ in item.reviewStatus == .postponed }
                        ))
                    } label: {
                        statusRow("Rimandati", "clock", summary.review[.postponed] ?? 0)
                    }
                    NavigationLink {
                        ProtectionSettingsView()
                    } label: {
                        statusRow("Elementi protetti", "lock", summary.protectedCount)
                    }
                }
            }
            .navigationTitle("Esplora")
        }
    }

    private func sectionLink<Destination: View>(
        _ section: CollectionSection,
        stat: CollectionStat,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label(section.title, systemImage: section.systemImage)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.count(stat.count))
                        .font(.subheadline.weight(.semibold))
                    Text(Format.bytes(stat.bytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statusRow(_ title: String, _ systemImage: String, _ count: Int) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(Format.count(count))
                .foregroundStyle(.secondary)
        }
    }
}

/// Elenco delle categorie di una sezione, con conteggi e spazio occupato.
struct CollectionListView: View {
    let section: CollectionSection

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        List {
            Section {
                ForEach(SmartCollection.collections(in: section)) { collection in
                    CollectionLink(collection: collection)
                }
            } footer: {
                Text("Appartenere a una categoria non significa che un elemento sia da eliminare: sono soltanto modi per ritrovare i contenuti.")
            }
        }
        .navigationTitle(section.title)
    }
}

/// Riga di una categoria che apre la griglia, il confronto a gruppi o l'avviso del piano.
struct CollectionLink: View {
    let collection: SmartCollection

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let isLocked = !env.plan.isUnlocked(collection.requiredFeature)
        NavigationLink {
            CollectionDestination(collection: collection)
        } label: {
            CollectionRow(
                collection: collection,
                stat: env.store.summary.stat(collection),
                isLocked: isLocked
            )
        }
    }
}

/// Schermata di una categoria: l'elenco dei gruppi, la griglia oppure l'avviso del piano.
struct CollectionDestination: View {
    let collection: SmartCollection

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if !env.plan.isUnlocked(collection.requiredFeature), let feature = collection.requiredFeature {
            LockedFeatureView(feature: feature)
        } else if collection.isGroupBased {
            GroupListView(collection: collection)
        } else {
            ItemGridScreen(query: .collection(collection))
        }
    }
}
