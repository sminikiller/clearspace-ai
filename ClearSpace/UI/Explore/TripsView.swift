import CoreLocation
import SwiftUI

/// Modalità viaggio: periodi trascorsi lontano dal luogo abituale, ricostruiti da date e posizioni.
/// Il calcolo avviene sul dispositivo; il nome del luogo viene richiesto ad Apple solo su tua richiesta.
struct TripsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var trips: [Trip] = []
    @State private var placeNames: [UUID: String] = [:]
    @State private var isLoading = true

    var body: some View {
        ReadableList {
            Section {
                InfoBanner(text: "I viaggi sono riconosciuti dalle posizioni salvate nelle foto. Servono a rivedere insieme i contenuti di uno stesso periodo.")
            }
            if isLoading {
                ProgressView("Ricerca dei viaggi…")
            } else if trips.isEmpty {
                ContentUnavailableView(
                    "Nessun viaggio",
                    systemImage: "airplane",
                    description: Text("Non sono stati riconosciuti viaggi: servono foto con la posizione, scattate lontano dal luogo abituale.")
                )
            }
            ForEach(trips) { trip in
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink {
                        ItemGridScreen(query: .ids(trip.itemIDs, title: title(for: trip), subtitle: dateRange(for: trip)))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title(for: trip))
                                .font(.headline)
                            Text(dateRange(for: trip))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(Format.plural(trip.itemIDs.count, "elemento", "elementi")) · \(Format.bytes(trip.bytes)) · circa \(Int(trip.distanceFromHomeKm)) km da casa")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if placeNames[trip.id] == nil {
                        Button("Mostra il luogo") {
                            lookUpPlace(for: trip)
                        }
                        .font(.footnote)
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Modalità viaggio")
        .onAppear { env.recordTutorial(.openTrips) }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await reload()
        }
    }

    private func title(for trip: Trip) -> String {
        placeNames[trip.id] ?? "Viaggio di \(Format.plural(trip.dayCount, "giorno", "giorni"))"
    }

    private func dateRange(for trip: Trip) -> String {
        "\(Format.date(trip.start)) – \(Format.date(trip.end))"
    }

    private func reload() async {
        let libraryItems = env.store.snapshot().filter { $0.source == .photoLibrary }
        let detected = await Task.detached(priority: .userInitiated) {
            TripDetector.detect(items: libraryItems)
        }.value
        trips = detected
        isLoading = false
    }

    /// Chiede al servizio di geocodifica di Apple il nome del luogo: è l'unico dato che esce dal dispositivo,
    /// e solo quando l'utente tocca il pulsante.
    private func lookUpPlace(for trip: Trip) {
        env.recordTutorial(.tripPlace)
        let location = CLLocation(latitude: trip.latitude, longitude: trip.longitude)
        Task {
            let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
            let placemark = placemarks?.first
            let name = [placemark?.locality, placemark?.country]
                .compactMap { $0 }
                .joined(separator: ", ")
            placeNames[trip.id] = name.isEmpty ? "Luogo non disponibile" : name
        }
    }
}
