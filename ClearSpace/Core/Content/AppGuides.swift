import Foundation

/// Procedura guidata per liberare spazio in un'altra app o in iCloud.
/// iOS non permette a un'app di leggere o cancellare i dati delle altre: ClearSpace spiega
/// dove trovare lo strumento giusto, senza dichiarare accessi che il sistema non concede.
struct AppGuide: Identifiable, Hashable, Sendable {
    enum Area: String, Sendable {
        case apps
        case iCloud
    }

    let id: String
    let area: Area
    let title: String
    let systemImage: String
    let summary: String
    let steps: [String]
    let note: String?
}

enum AppGuides {

    static let all: [AppGuide] = apps + iCloud

    static let apps: [AppGuide] = [
        AppGuide(
            id: "whatsapp",
            area: .apps,
            title: "WhatsApp",
            systemImage: "message",
            summary: "Trova ed elimina i file più grandi ricevuti nelle chat.",
            steps: [
                "Apri WhatsApp e vai in Impostazioni.",
                "Tocca «Spazio e dati», poi «Gestisci spazio».",
                "Apri «Più grandi di 5 MB» oppure una chat dell'elenco, ordinato per spazio occupato.",
                "Tocca «Seleziona», scegli gli elementi che non ti servono e conferma con il cestino.",
                "Per evitare nuovi accumuli, in «Spazio e dati» limita il download automatico dei media."
            ],
            note: "I media eliminati da WhatsApp non vengono rimossi dalla libreria Foto se li avevi già salvati lì."
        ),
        AppGuide(
            id: "telegram",
            area: .apps,
            title: "Telegram",
            systemImage: "paperplane",
            summary: "Svuota la cache: i contenuti restano nel cloud di Telegram.",
            steps: [
                "Apri Telegram e vai in Impostazioni.",
                "Tocca «Dati e archivio», poi «Utilizzo archivio».",
                "Controlla quanto spazio occupa la cache e tocca «Svuota la cache».",
                "Imposta «Conserva i media» su un periodo breve per farla svuotare da sola."
            ],
            note: "La cache contiene copie locali: foto e video delle chat cloud si possono riscaricare."
        ),
        AppGuide(
            id: "streaming",
            area: .apps,
            title: "Netflix e streaming",
            systemImage: "play.tv",
            summary: "Rimuovi film ed episodi scaricati per la visione offline.",
            steps: [
                "Apri l'app di streaming e vai nella sezione «Download».",
                "Tocca l'icona di modifica e rimuovi i titoli già visti.",
                "In Netflix: Profilo → Impostazioni app → «Elimina tutti i download».",
                "Se disponibile, attiva i download intelligenti per eliminare automaticamente gli episodi visti."
            ],
            note: nil
        ),
        AppGuide(
            id: "music",
            area: .apps,
            title: "Spotify, musica e podcast",
            systemImage: "music.note",
            summary: "Rimuovi brani e puntate scaricati che non ascolti più.",
            steps: [
                "Spotify: Impostazioni → Archiviazione → «Rimuovi tutti i download» oppure «Svuota cache».",
                "Apple Music: Impostazioni di iPhone → App → Musica → «Musica scaricata», poi «Modifica».",
                "Podcast: Impostazioni di iPhone → App → Podcast → attiva «Rimuovi download riprodotti».",
                "Controlla anche le playlist scaricate automaticamente."
            ],
            note: nil
        ),
        AppGuide(
            id: "safari",
            area: .apps,
            title: "Safari",
            systemImage: "safari",
            summary: "Gestisci download, cronologia e dati dei siti web.",
            steps: [
                "Apri Impostazioni di iPhone → App → Safari.",
                "Tocca «Cancella dati siti web e cronologia» e scegli l'intervallo di tempo.",
                "In «Avanzate» → «Dati dei siti web» puoi rimuovere i dati di singoli siti.",
                "In «Download» imposta la rimozione automatica degli elementi dell'elenco.",
                "I file scaricati si trovano nell'app File, cartella «Download»: puoi analizzarla con ClearSpace."
            ],
            note: "Cancellare i dati dei siti può disconnetterti dagli account web."
        ),
        AppGuide(
            id: "messages",
            area: .apps,
            title: "Messaggi",
            systemImage: "bubble.left.and.bubble.right",
            summary: "Rivedi conversazioni e allegati ingombranti.",
            steps: [
                "Apri Impostazioni di iPhone → Generali → Spazio su iPhone.",
                "Tocca «Messaggi»: troverai conversazioni principali, foto, video e altri allegati.",
                "Apri una categoria, tocca «Modifica» ed elimina ciò che non ti serve.",
                "In Impostazioni → App → Messaggi → «Conserva messaggi» puoi scegliere 30 giorni o 1 anno."
            ],
            note: "Con Messaggi su iCloud attivo, le eliminazioni valgono per tutti i dispositivi."
        ),
        AppGuide(
            id: "unused",
            area: .apps,
            title: "App inutilizzate",
            systemImage: "square.grid.2x2",
            summary: "Disinstalla le app che non usi conservandone documenti e dati.",
            steps: [
                "Apri Impostazioni di iPhone → Generali → Spazio su iPhone.",
                "L'elenco mostra le app ordinate per spazio occupato, con la data dell'ultimo utilizzo.",
                "Tocca un'app e scegli «Disinstalla app» per liberare spazio conservandone i dati.",
                "Attiva il consiglio «Rimuovi app che non usi» per farlo fare automaticamente a iOS."
            ],
            note: "«Elimina app» rimuove anche i dati: usalo solo se sei sicuro."
        ),
        AppGuide(
            id: "notes",
            area: .apps,
            title: "Note Apple",
            systemImage: "note.text",
            summary: "Esporta o elimina le note con allegati pesanti.",
            steps: [
                "Apri Note e usa la vista «Allegati» dal menu della cartella per trovare quelli più grandi.",
                "Per conservare un documento, apri la nota e usa «Condividi» → «Salva su File».",
                "Elimina le note che non servono e svuota la cartella «Eliminati di recente».",
                "I file esportati in una cartella autorizzata possono essere analizzati da ClearSpace."
            ],
            note: "ClearSpace non legge le tue note: lavora solo sui file che scegli di esportare."
        )
    ]

    static let iCloud: [AppGuide] = [
        AppGuide(
            id: "icloud-backup",
            area: .iCloud,
            title: "Backup iCloud",
            systemImage: "arrow.clockwise.icloud",
            summary: "Elimina i backup di vecchi dispositivi e riduci quelli attuali.",
            steps: [
                "Apri Impostazioni di iPhone e tocca il tuo nome in alto.",
                "Tocca «iCloud», poi «Spazio» (o «Gestisci spazio») e infine «Backup».",
                "Elimina i backup dei dispositivi che non possiedi più.",
                "Tocca il backup di questo iPhone e disattiva le app i cui dati non ti serve salvare."
            ],
            note: "Eliminare un backup non cancella i dati presenti sul dispositivo."
        ),
        AppGuide(
            id: "icloud-optimize",
            area: .iCloud,
            title: "Ottimizza spazio iPhone",
            systemImage: "icloud.and.arrow.down",
            summary: "Mantieni gli originali su iCloud e versioni leggere sull'iPhone.",
            steps: [
                "Apri Impostazioni di iPhone e tocca il tuo nome in alto.",
                "Tocca «iCloud», poi «Foto».",
                "Attiva «Ottimizza spazio iPhone».",
                "iOS sostituirà gradualmente gli originali locali con versioni ridotte, quando serve spazio."
            ],
            note: "È il modo previsto da Apple per liberare spazio sul telefono senza eliminare foto da iCloud."
        ),
        AppGuide(
            id: "icloud-recently-deleted",
            area: .iCloud,
            title: "Eliminati di recente",
            systemImage: "trash",
            summary: "Lo spazio delle foto eliminate si libera davvero solo svuotando questo album.",
            steps: [
                "Apri l'app Foto e vai su «Album» → «Utility» → «Eliminati di recente».",
                "Controlla il contenuto: da qui puoi ancora recuperare tutto per 30 giorni.",
                "Tocca «Seleziona», poi «Elimina tutto» per liberare subito lo spazio."
            ],
            note: "Questa eliminazione è definitiva e vale anche per iCloud e gli altri dispositivi."
        ),
        AppGuide(
            id: "icloud-app-data",
            area: .iCloud,
            title: "Dati delle app in iCloud",
            systemImage: "square.stack.3d.up",
            summary: "Controlla quali app occupano spazio nel tuo piano iCloud.",
            steps: [
                "Apri Impostazioni di iPhone e tocca il tuo nome in alto.",
                "Tocca «iCloud», poi «Spazio» (o «Gestisci spazio»).",
                "L'elenco mostra le app ordinate per spazio occupato su iCloud.",
                "Tocca un'app e scegli «Elimina dati da iCloud» se non ti servono più."
            ],
            note: "L'eliminazione dei dati di un'app da iCloud è definitiva."
        ),
        AppGuide(
            id: "icloud-mail",
            area: .iCloud,
            title: "Mail di iCloud",
            systemImage: "envelope",
            summary: "Gli allegati della posta iCloud contano nel tuo piano.",
            steps: [
                "Apri Mail e seleziona la casella iCloud.",
                "Ordina o cerca i messaggi con allegati di grandi dimensioni.",
                "Elimina i messaggi che non servono e svuota il Cestino della casella."
            ],
            note: nil
        )
    ]

    static func guide(withID id: String) -> AppGuide? {
        all.first { $0.id == id }
    }
}
