import SwiftUI

/// Scheda dei dettagli: dimensioni, data, origine, stato delle analisi e protezione.
struct ItemDetailView: View {
    let itemID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsUnlock = false

    var body: some View {
        let _ = env.store.revision
        NavigationStack {
            Group {
                if let item = env.store.item(itemID) {
                    details(for: item)
                } else {
                    ContentUnavailableView("Elemento non più disponibile", systemImage: "questionmark.circle")
                }
            }
            .navigationTitle("Dettagli")
            .onAppear { env.recordTutorial(.details) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }

    private func details(for item: IndexedItem) -> some View {
        List {
            Section {
                ItemThumbnailView(item: item, pointSide: 300, fill: false)
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
            }

            Section("Informazioni") {
                DetailRow(label: "Tipo", value: item.kindDescription)
                if let filename = item.filename {
                    DetailRow(label: "Nome", value: filename)
                }
                DetailRow(label: "Data", value: Format.dateTime(item.createdAt))
                if item.pixelWidth > 0 {
                    DetailRow(label: "Risoluzione", value: Format.megapixels(width: item.pixelWidth, height: item.pixelHeight))
                }
                if item.duration > 0 {
                    DetailRow(label: "Durata", value: Format.duration(item.duration))
                }
                if let pages = item.pageCount {
                    DetailRow(label: "Pagine", value: String(pages))
                }
                DetailRow(label: "Origine", value: originDescription(for: item))
                if item.latitude != nil {
                    DetailRow(label: "Posizione", value: "Presente nei metadati")
                }
            }

            Section {
                DetailRow(
                    label: item.bytesAreEstimated ? "Dimensione (stima)" : "Dimensione",
                    value: Format.bytesOrUnknown(item.estimatedBytes)
                )
                DetailRow(label: "Spazio sull'iPhone", value: Format.bytes(item.deviceBytes))
                if item.traits.contains(.cloudOnly) {
                    Label("L'originale è solo su iCloud: eliminarlo libera spazio soprattutto nel cloud.", systemImage: "icloud")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Spazio")
            } footer: {
                if item.bytesAreEstimated {
                    Text("iOS non ha fornito la dimensione esatta: il valore è una stima.")
                }
            }

            Section("Analisi") {
                DetailRow(label: "Stato", value: item.analysisStatus.title)
                if let sharpness = item.sharpness, item.isImage {
                    DetailRow(label: "Nitidezza", value: Format.percent(sharpness))
                }
                if let shot = item.shot, item.isImage {
                    // Misure del confronto tra scatti simili: sono quelle che decidono quale viene consigliato.
                    DetailRow(label: "Voto dello scatto", value: "\(QualityRanker.breakdown(item).grade)/100")
                    DetailRow(label: "Nitidezza nel dettaglio", value: Format.percent(shot.detailSharpness))
                    if let subject = shot.subjectSharpness {
                        DetailRow(label: "Nitidezza del soggetto", value: Format.percent(subject))
                    }
                    if shot.faceCount > 0 {
                        DetailRow(label: "Volti", value: faceDescription(shot))
                    }
                    if let aesthetics = shot.aesthetics {
                        DetailRow(label: "Giudizio estetico", value: Format.percent((aesthetics + 1) / 2))
                    }
                }
                if item.contentHash != nil {
                    DetailRow(label: "Contenuto", value: "Verificato con SHA-256")
                }
                if let groupID = item.duplicateGroupID, let group = env.store.group(groupID) {
                    DetailRow(label: "Duplicati", value: "\(group.kind.title) (\(group.memberIDs.count))")
                }
                if let groupID = item.similarityGroupID, let group = env.store.group(groupID) {
                    DetailRow(label: "Simili", value: "\(group.kind.title) (\(group.memberIDs.count))")
                }
                let labels = traitLabels(for: item)
                if !labels.isEmpty {
                    Text(labels.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let text = item.textContent, !text.isEmpty {
                    DisclosureGroup("Testo riconosciuto") {
                        Text(text)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }
            }

            if item.isVideo && item.source == .photoLibrary {
                Section {
                    NavigationLink {
                        VideoCompressionView(itemID: item.id)
                    } label: {
                        Label("Comprimi questo video", systemImage: "rectangle.compress.vertical")
                    }
                } header: {
                    Text("Strumenti")
                } footer: {
                    Text("Operazione facoltativa: crea una copia più leggera e ti permette di confrontarla con l'originale.")
                }
            }

            protectionSection(for: item)
        }
    }

    @ViewBuilder
    private func protectionSection(for item: IndexedItem) -> some View {
        let reason = env.safety.blockReason(for: item)
        Section {
            DetailRow(label: "Decisione", value: item.reviewStatus.title)
            if let reason {
                Label(reason.message, systemImage: "lock.fill")
                    .font(.subheadline)
            }
            if item.isSensitive {
                Label("Contenuto potenzialmente importante: controllalo con attenzione.", systemImage: "exclamationmark.shield")
                    .font(.subheadline)
                    .foregroundStyle(Theme.later)
            }

            if item.isProtected {
                Button("Rimuovi la protezione") {
                    env.safety.removeProtection([item.id])
                }
            } else {
                Button("Proteggi questo elemento") {
                    env.recordTutorial(.protectItem)
                    env.safety.protect([item.id])
                }
            }
            if let reason, reason.canBeOverridden {
                Button("Sblocca solo questo elemento") {
                    confirmsUnlock = true
                }
            }
            if item.protectionOverride {
                Button("Ripristina la protezione automatica") {
                    env.safety.removeProtection([item.id])
                }
            }
        } header: {
            Text("Protezione")
        } footer: {
            Text("Gli elementi protetti non possono essere proposti per l'eliminazione.")
        }
        .confirmationDialog(
            "Sbloccare questo elemento?",
            isPresented: $confirmsUnlock,
            titleVisibility: .visible
        ) {
            Button("Sblocca") {
                env.recordTutorial(.unlockItem)
                env.safety.unlock(item.id)
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Potrà essere proposto per l'eliminazione, sempre con revisione e conferma finale.")
        }
    }

    private func originDescription(for item: IndexedItem) -> String {
        switch item.source {
        case .photoLibrary:
            return item.traits.contains(.fromOtherApp) ? "Libreria Foto (probabilmente salvata da un'altra app)" : "Libreria Foto"
        case .localFiles, .iCloudDrive:
            let folder = item.folderID.flatMap { env.folders.folder($0)?.name } ?? item.source.title
            return "\(item.source.title) · \(folder)"
        case .appImports:
            return "Copia importata in ClearSpace"
        }
    }

    /// "2 · qualità 74% · occhi aperti".
    private func faceDescription(_ shot: ShotMetrics) -> String {
        var parts = [String(shot.faceCount)]
        if let quality = shot.faceQuality {
            parts.append("qualità \(Format.percent(quality))")
        }
        if shot.hasClosedEyes {
            parts.append("occhi chiusi")
        } else if shot.openEyes != nil {
            parts.append("occhi aperti")
        }
        if let smiles = shot.smiles, smiles >= 0.5 {
            parts.append("sorriso")
        }
        return parts.joined(separator: " · ")
    }

    private func traitLabels(for item: IndexedItem) -> [String] {
        let table: [(ItemTraits, String)] = [
            (.screenshot, "Screenshot"), (.livePhoto, "Live Photo"), (.burst, "Raffica"),
            (.panorama, "Panoramica"), (.selfie, "Selfie"), (.portrait, "Ritratto"), (.hdr, "HDR"),
            (.raw, "RAW"), (.edited, "Modificata"), (.favorite, "Preferita"), (.hidden, "Nascosta"),
            (.screenRecording, "Registrazione schermo"), (.slowMotion, "Slow motion"),
            (.timelapse, "Time-lapse"), (.cinematic, "Cinema"), (.video4K, "4K"),
            (.download, "Download"), (.lowResolution, "Bassa risoluzione"),
            (.heavyForResolution, "Pesante per la risoluzione"), (.hasText, "Contiene testo"),
            (.conversation, "Conversazione"), (.receipt, "Ricevuta"), (.qrCode, "Codice QR"),
            (.documentLike, "Documento"), (.ticket, "Biglietto"), (.sensitiveText, "Dati sensibili"),
            (.blurry, "Probabilmente sfocata"), (.dark, "Scura"), (.blank, "Apparentemente vuota"),
            (.longSilence, "Silenzi lunghi"), (.transcribed, "Trascritta")
        ]
        return table.filter { item.traits.contains($0.0) }.map { $0.1 }
    }
}
