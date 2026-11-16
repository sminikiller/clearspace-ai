import Foundation

/// Tipo di raggruppamento individuato dalle analisi.
enum GroupKind: String, Codable, CaseIterable, Sendable {
    /// Contenuto binariamente identico, verificato con SHA-256.
    case exactDuplicate
    /// Anteprime visivamente identiche: probabile duplicato, non verificato sul contenuto.
    case visualDuplicate
    /// Scatti dello stesso soggetto.
    case similar
    case burst
    /// Possibili versioni dello stesso documento.
    case documentVersion
    case similarAudio
    case similarVideo

    /// I duplicati usano `duplicateGroupID`, gli altri gruppi `similarityGroupID`.
    var isDuplicateKind: Bool {
        self == .exactDuplicate || self == .visualDuplicate
    }

    var title: String {
        switch self {
        case .exactDuplicate: return "Duplicati esatti"
        case .visualDuplicate: return "Probabili duplicati"
        case .similar: return "Foto simili"
        case .burst: return "Raffica"
        case .documentVersion: return "Versioni dello stesso documento"
        case .similarAudio: return "Registrazioni simili"
        case .similarVideo: return "Video simili"
        }
    }
}

enum GroupScope: String, Codable, Sendable {
    case photoLibrary
    case files
    case crossSource
}

/// Grado di certezza con cui due elementi sono stati associati.
enum MatchCertainty: String, Codable, Sendable {
    case verifiedHash
    case previewComparison
    case similarity

    var explanation: String {
        switch self {
        case .verifiedHash:
            return "Contenuto identico, verificato sull'originale (SHA-256)."
        case .previewComparison:
            return "Confronto eseguito sulle sole anteprime: probabile duplicato, non verificato sull'originale."
        case .similarity:
            return "Contenuti simili, non identici: la scelta spetta a te."
        }
    }
}

/// Gruppo di elementi duplicati o simili, con il candidato suggerito da conservare.
struct ItemGroup: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: GroupKind
    var scope: GroupScope
    var memberIDs: [UUID]
    var suggestedKeepID: UUID?
    /// Motivo del suggerimento, es. "è più nitida e ha una risoluzione superiore".
    var suggestionReason: String?
    /// Nota aggiuntiva, es. "uno ha una pagina in più".
    var note: String?

    init(
        id: UUID = UUID(),
        kind: GroupKind,
        scope: GroupScope,
        memberIDs: [UUID],
        suggestedKeepID: UUID? = nil,
        suggestionReason: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.memberIDs = memberIDs
        self.suggestedKeepID = suggestedKeepID
        self.suggestionReason = suggestionReason
        self.note = note
    }

    var certainty: MatchCertainty {
        switch kind {
        case .exactDuplicate: return .verifiedHash
        case .visualDuplicate: return .previewComparison
        case .similar, .burst, .documentVersion, .similarAudio, .similarVideo: return .similarity
        }
    }

    /// Membri diversi da quello suggerito: i candidati alla revisione.
    var extraIDs: [UUID] {
        guard let suggestedKeepID else { return Array(memberIDs.dropFirst()) }
        return memberIDs.filter { $0 != suggestedKeepID }
    }

    /// Gruppo da mostrare per un elemento che appartiene sia a un gruppo di duplicati sia a uno di simili.
    ///
    /// Due scatti quasi identici di una stessa serie risultano spesso "probabili duplicati" tra loro e,
    /// insieme agli altri, "foto simili": mostrando i due gruppi separatamente si dovrebbe decidere due
    /// volte sulle stesse foto. Quando le copie sono tutte comprese tra gli scatti simili si mostra
    /// quindi l'insieme più ampio; altrimenti prevale il legame più stretto, quello tra copie.
    static func preferred(duplicate: ItemGroup?, similar: ItemGroup?) -> ItemGroup? {
        guard let duplicate else { return similar }
        guard let similar else { return duplicate }
        return Set(duplicate.memberIDs).isSubset(of: Set(similar.memberIDs)) ? similar : duplicate
    }
}
