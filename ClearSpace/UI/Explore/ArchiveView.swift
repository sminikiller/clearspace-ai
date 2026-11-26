import SwiftUI

/// Archivio storico: esplorazione per anno e pulizia annuale.
/// I contenuti vecchi non sono considerati inutili: vengono soltanto messi in ordine per essere rivisti.
struct ArchiveView: View {
    @Environment(AppEnvironment.self) private var env

    private var summary: CatalogSummary { env.store.summary }

    var body: some View {
        ReadableList {
            Section {
                InfoBanner(text: "Scegli un anno per sfogliarne i contenuti o per rivederli tutti con gli swipe. L'età di un contenuto non è mai un motivo per eliminarlo.")
            }
            if summary.sortedYears.isEmpty {
                ContentUnavailableView(
                    "Nessun contenuto datato",
                    systemImage: "calendar",
                    description: Text("Avvia un'analisi per costruire l'archivio.")
                )
            }
            Section("Anni") {
                ForEach(summary.sortedYears, id: \.self) { year in
                    let stat = summary.years[year] ?? CollectionStat()
                    NavigationLink {
                        YearDetailView(year: year)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(year))
                                    .font(.headline)
                                Text("\(Format.plural(stat.reviewableCount, "elemento", "elementi")) da rivedere")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
            }
        }
        .navigationTitle("Archivio storico")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Riepilogo di un anno: cosa è stato conservato, proposto per l'eliminazione o lasciato da rivedere.
struct YearDetailView: View {
    let year: Int

    @Environment(AppEnvironment.self) private var env
    @State private var months: [MonthStat] = []
    @State private var counts = YearCounts()
    @State private var isStarting = false
    @State private var toast: String?

    private struct MonthStat: Identifiable {
        let month: Int
        var count = 0
        var bytes: Int64 = 0
        var id: Int { month }
    }

    private struct YearCounts {
        var kept = 0
        var marked = 0
        var pending = 0
        var protected = 0
    }

    var body: some View {
        ReadableList {
            Section("Pulizia annuale \(String(year))") {
                HStack(spacing: 8) {
                    StatTile(title: "Conservati", value: Format.count(counts.kept), systemImage: "checkmark", tint: Theme.keep)
                    StatTile(title: "Da eliminare", value: Format.count(counts.marked), systemImage: "trash", tint: Theme.remove)
                    StatTile(title: "Da rivedere", value: Format.count(counts.pending), systemImage: "clock", tint: Theme.later)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)

                Button {
                    startAnnualCleanup()
                } label: {
                    if isStarting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        ButtonTitle("Rivedi tutto il \(String(year))", systemImage: "hand.draw")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isStarting || counts.pending == 0)

                if counts.protected > 0 {
                    Text("\(Format.plural(counts.protected, "elemento protetto", "elementi protetti")) non verranno proposti.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Mesi") {
                ForEach(months) { month in
                    NavigationLink {
                        ItemGridScreen(query: .filter(monthFilter(month.month), title: monthTitle(month.month)))
                    } label: {
                        HStack {
                            Text(monthTitle(month.month))
                            Spacer()
                            Text("\(Format.count(month.count)) · \(Format.bytes(month.bytes))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                NavigationLink("Tutti i contenuti del \(String(year))") {
                    ItemGridScreen(query: .filter(yearFilter, title: String(year), mode: .annual(year: year)))
                }
            }
        }
        .navigationTitle(String(year))
        .onAppear { env.recordTutorial(.openYear) }
        .task(id: env.listRevision) {
            reload()
        }
        .toast($toast)
    }

    private var yearFilter: ItemFilter {
        var filter = ItemFilter()
        filter.year = year
        filter.sort = .oldestFirst
        return filter
    }

    private func monthFilter(_ month: Int) -> ItemFilter {
        var filter = yearFilter
        filter.month = month
        return filter
    }

    private func monthTitle(_ month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else { return "Mese \(month)" }
        return Format.monthYear(date)
    }

    private func reload() {
        let calendar = Calendar.current
        let protection = env.safety.evaluator()
        var byMonth: [Int: MonthStat] = [:]
        var result = YearCounts()
        for item in env.store.snapshot() {
            guard let date = item.createdAt, calendar.component(.year, from: date) == year else { continue }
            let month = calendar.component(.month, from: date)
            var stat = byMonth[month] ?? MonthStat(month: month)
            stat.count += 1
            stat.bytes += item.bytes
            byMonth[month] = stat

            if protection.isProtected(item) {
                result.protected += 1
            } else if item.reviewStatus == .kept {
                result.kept += 1
            } else if item.reviewStatus.isQueuedForDeletion {
                result.marked += 1
            } else {
                result.pending += 1
            }
        }
        months = byMonth.values.sorted { $0.month < $1.month }
        counts = result
    }

    private func startAnnualCleanup() {
        env.recordTutorial(.annualCleanup)
        isStarting = true
        let targetYear = year
        Task {
            let started = await env.startSession(title: "Pulizia annuale \(targetYear)", mode: .annual(year: targetYear)) { input in
                CleanupPlanner.annualQueue(year: targetYear, input)
            }
            isStarting = false
            if !started {
                toast = "Non ci sono elementi da rivedere per questo anno."
            }
        }
    }
}

/// Modalità nostalgia: i ricordi di questo giorno negli anni passati. Qui non si propone di eliminare nulla.
struct NostalgiaView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var memories: [Memory] = []
    @State private var previewItem: IndexedItem?
    @State private var isLoading = true

    private struct Memory: Identifiable {
        let year: Int
        let items: [IndexedItem]
        var id: Int { year }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("I ricordi di oggi negli anni passati. Questa sezione serve soltanto a riguardarli.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if memories.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "Nessun ricordo per oggi",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Non ci sono foto scattate in questo giorno negli anni passati.")
                    )
                    .padding(.top, 40)
                }

                ForEach(memories) { memory in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(memory.year))
                            .font(.title2.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 6) {
                                ForEach(memory.items) { item in
                                    ItemThumbnailView(item: item, pointSide: 180)
                                        .frame(width: 160, height: 160)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .onTapGesture {
                                            previewItem = item
                                        }
                                        .accessibilityLabel("\(item.kindDescription), \(Format.date(item.createdAt))")
                                        .accessibilityAddTraits(.isButton)
                                }
                            }
                        }
                        NavigationLink("Sfoglia tutto il \(String(memory.year))") {
                            YearDetailView(year: memory.year)
                        }
                        .font(.footnote)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Modalità nostalgia")
        .onAppear { env.recordTutorial(.openNostalgia) }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: env.listRevision) {
            reload()
        }
        .fullScreenCover(item: $previewItem) { item in
            ItemPreviewScreen(itemID: item.id, showsActions: false)
        }
    }

    private func reload() {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.year, .month, .day], from: Date())
        var byYear: [Int: [IndexedItem]] = [:]
        for item in env.store.snapshot() where item.source == .photoLibrary {
            guard let date = item.createdAt else { continue }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard components.month == today.month, components.day == today.day,
                  let year = components.year, year != today.year else {
                continue
            }
            byYear[year, default: []].append(item)
        }
        var result: [Memory] = []
        for year in byYear.keys.sorted(by: >) {
            let items = (byYear[year] ?? []).sorted {
                ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast)
            }
            result.append(Memory(year: year, items: items))
        }
        memories = result
        isLoading = false
    }
}
