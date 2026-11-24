import Foundation

/// Azioni che i tutorial riconoscono: quando l'utente le compie davvero nell'app, l'esercizio
/// corrispondente si spunta da solo. Sono registrate nella checklist dello storico, sul dispositivo.
enum TutorialEvent: String, CaseIterable, Sendable {
    // Swipe
    case swipeRight, swipeLeft, swipeDown, swipeUp
    case actionButton, undo, undoGroup, fullScreen, cardZoom
    // Video nella carta
    case videoPause, videoAudio, videoSpeed, videoSeek
    // Simili: striscia, galleria, stelle
    case stripSelect, stripMenu, keepBest, keepOnlyCurrent
    case openGallery, galleryToggle, dragSelect, quickSelect, galleryOrder, galleryMenu, starBest, removeStar, groupSequence
    case groupBatch
    // Confronto
    case openCompare, compareZoom, compareStep, compareDecision
    // Esplora e griglie
    case openCategory, openGroups, sortGrid, preview, selectMode, gridAction, protectItem
    // Ricerca
    case search, searchResults
    // Modalità di pulizia
    case quickCleanup, guidedStep, guidedCheck, advancedCleanup, goalCleanup, resumeSession
    // Archivio, viaggi, nostalgia
    case openYear, annualCleanup, openTrips, tripPlace, openNostalgia
    // Revisione ed eliminazione
    case restoreItem, restoreGroup, openConfirmation, archiveWizard
    // Risultati
    case remeasure, reportDetail, reminder
    // Analisi
    case startScan, pauseScan
    // Dettagli e protezioni
    case details, unlockItem, protectionRules
    // Documenti, audio, compressione
    case addFolder, freeLocalCopy, organize, importAudio, audioSearch, transcribe, compressVideo
    // iCloud e altre app
    case iCloudState, iCloudQuota, appGuide, appChecklist
    // Guida
    case readGuide

    /// Chiave nella checklist dello storico.
    var storageID: String { "tutorial.event." + rawValue }
}

/// Dove porta il pulsante «Apri lo strumento» di un tutorial o di un capitolo della guida.
enum GuideDestination: String, Sendable {
    case homeTab, analyzeTab, exploreTab, reviewTab, resultsTab
    case allPhotos, allVideos, photoCategories, videoCategories
    case similarGroups, duplicateGroups
    case smartSearch, guidedCleanup, advancedCleanup
    case archive, trips, nostalgia
    case documents, audio, iCloudCenter, appAssistant, protections

    /// Le schede principali si aprono cambiando scheda; tutto il resto si apre sopra la guida.
    var isTab: Bool {
        switch self {
        case .homeTab, .analyzeTab, .exploreTab, .reviewTab, .resultsTab: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .homeTab: return "Apri la Home"
        case .analyzeTab: return "Apri la scheda Analizza"
        case .exploreTab: return "Apri la scheda Esplora"
        case .reviewTab: return "Apri la scheda Revisione"
        case .resultsTab: return "Apri la scheda Risultati"
        case .allPhotos: return "Apri Tutte le foto"
        case .allVideos: return "Apri Tutti i video"
        case .photoCategories: return "Apri le categorie delle foto"
        case .videoCategories: return "Apri le categorie dei video"
        case .similarGroups: return "Apri le foto simili"
        case .duplicateGroups: return "Apri le foto duplicate"
        case .smartSearch: return "Apri la ricerca intelligente"
        case .guidedCleanup: return "Apri la pulizia guidata"
        case .advancedCleanup: return "Apri la pulizia avanzata"
        case .archive: return "Apri l'archivio storico"
        case .trips: return "Apri la modalità viaggio"
        case .nostalgia: return "Apri la modalità nostalgia"
        case .documents: return "Apri Documenti e file"
        case .audio: return "Apri Audio e registrazioni"
        case .iCloudCenter: return "Apri il Centro iCloud"
        case .appAssistant: return "Apri l'assistente app"
        case .protections: return "Apri le protezioni"
        }
    }
}

/// Un esercizio di un tutorial. Se ha un evento si spunta da solo quando l'utente compie l'azione;
/// altrimenti l'utente lo segna come fatto.
struct TutorialTask: Identifiable, Sendable {
    let id: String
    let title: String
    /// Come si fa, passo per passo.
    let howTo: String
    /// Cosa si deve vedere se è andato tutto bene.
    let check: String
    let event: TutorialEvent?

    /// Chiave della spunta manuale nella checklist dello storico.
    var manualStorageID: String { "tutorial.task." + id }
}

/// Un tutorial pratico su uno strumento: obiettivo, preparazione ed esercizi.
struct Tutorial: Identifiable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let goal: String
    /// Cosa serve prima di cominciare (contenuti analizzati, una cartella, una registrazione…).
    let preparation: String
    let destination: GuideDestination
    /// Capitolo della guida che spiega lo strumento.
    let chapterID: String
    let tasks: [TutorialTask]
}

/// Tutti i tutorial, uno per strumento.
enum TutorialCatalog {

    private static func task(
        _ id: String,
        _ title: String,
        howTo: String,
        check: String,
        event: TutorialEvent?
    ) -> TutorialTask {
        TutorialTask(id: id, title: title, howTo: howTo, check: check, event: event)
    }

    static let all: [Tutorial] = [
        Tutorial(
            id: "swipe",
            title: "Lo swipe",
            systemImage: "hand.draw",
            goal: "Imparare tutti i gesti delle carte e i pulsanti equivalenti, e capire che nessun gesto elimina davvero qualcosa.",
            preparation: "Serve almeno un'analisi completata. Apri Tutte le foto e tocca «Rivedi con gli swipe»: le scelte che fai sono vere, ma si annullano in un attimo e nulla viene eliminato senza la Revisione.",
            destination: .allPhotos,
            chapterID: "swipe",
            tasks: [
                task("swipe.right", "Conserva con uno swipe a destra",
                     howTo: "Appoggia il dito sulla carta e trascinala verso destra finché compare la scritta verde CONSERVA, poi lascia.",
                     check: "La carta vola via a destra e in alto il contatore «Conservati» aumenta di uno.",
                     event: .swipeRight),
                task("swipe.left", "Proponi con uno swipe a sinistra",
                     howTo: "Trascina la carta verso sinistra finché compare la scritta rossa DA ELIMINARE.",
                     check: "Il contatore «Da eliminare» aumenta e l'elemento compare nella scheda Revisione. Non è stato eliminato nulla.",
                     event: .swipeLeft),
                task("swipe.down", "Rimanda con uno swipe verso il basso",
                     howTo: "Trascina la carta verso il basso finché compare PIÙ TARDI.",
                     check: "La carta passa alla successiva; a fine sessione puoi rivedere i rimandati.",
                     event: .swipeDown),
                task("swipe.up", "Apri i dettagli con uno swipe verso l'alto",
                     howTo: "Trascina la carta verso l'alto finché compare DETTAGLI.",
                     check: "Si apre la scheda Dettagli con tipo, data, dimensione, analisi e protezione. Chiudila con Fine.",
                     event: .swipeUp),
                task("swipe.undo", "Annulla l'ultima scelta",
                     howTo: "Tocca il pulsante Annulla (la freccia che torna indietro) nella barra in basso.",
                     check: "L'ultima carta decisa torna davanti e i contatori tornano indietro.",
                     event: .undo),
                task("swipe.buttons", "Usa i pulsanti al posto dei gesti",
                     howTo: "Tocca uno dei pulsanti in basso: Elimina, Più tardi, Dettagli o Conserva. Fanno esattamente ciò che fanno i gesti.",
                     check: "La carta si comporta come con il gesto corrispondente.",
                     event: .actionButton),
                task("swipe.fullscreen", "Guarda una foto a tutto schermo",
                     howTo: "Tocca due volte la foto sulla carta, oppure il pulsante con le due frecce in basso a destra.",
                     check: "La foto si apre a tutto schermo: puoi ingrandirla con due dita. Chiudi con Chiudi.",
                     event: .fullScreen),
                task("swipe.zoom", "Ingrandisci la carta con due dita",
                     howTo: "Allarga due dita sulla foto della carta per controllare un dettaglio, poi lascia: torna da sola alla dimensione normale.",
                     check: "La foto si ingrandisce nel punto che hai scelto mentre tieni le dita appoggiate.",
                     event: .cardZoom)
            ]
        ),
        Tutorial(
            id: "video",
            title: "I video nella carta",
            systemImage: "play.rectangle",
            goal: "Guardare un video prima di deciderlo, con tutti i comandi: pausa, audio, velocità, barra e fotogrammi.",
            preparation: "Apri Tutti i video e tocca «Rivedi con gli swipe». Se il video è solo su iCloud usa «Riproduci comunque».",
            destination: .allVideos,
            chapterID: "video",
            tasks: [
                task("video.pause", "Metti in pausa e riprendi",
                     howTo: "Tocca una volta il video nella carta. Toccalo di nuovo per farlo ripartire.",
                     check: "Al centro compare il simbolo di riproduzione mentre è in pausa.",
                     event: .videoPause),
                task("video.audio", "Attiva l'audio",
                     howTo: "Tocca il pulsante con l'altoparlante a destra del video.",
                     check: "L'icona cambia e senti il sonoro. I video partono sempre senza audio.",
                     event: .videoAudio),
                task("video.speed", "Guarda a velocità doppia",
                     howTo: "Tocca il pulsante «1×» sotto l'altoparlante: diventa «2×».",
                     check: "Il video scorre al doppio della velocità: utile per i video lunghi.",
                     event: .videoSpeed),
                task("video.seek", "Salta a un momento preciso",
                     howTo: "Trascina il dito sulla barra bianca in basso, oppure tocca uno dei fotogrammi sopra la barra.",
                     check: "Il video riparte dal punto scelto e il tempo a sinistra si aggiorna.",
                     event: .videoSeek)
            ]
        ),
        Tutorial(
            id: "similar",
            title: "Foto simili nello swipe",
            systemImage: "square.stack.3d.down.right",
            goal: "Vedere tutto il gruppo di scatti simili sotto la carta, guardarli uno per uno e tenere il migliore con un tocco.",
            preparation: "Apri la Pulizia guidata e avvia il passo «Foto simili e duplicate»: sotto la carta compare la striscia con tutte le foto del gruppo.",
            destination: .guidedCleanup,
            chapterID: "strip",
            tasks: [
                task("similar.select", "Porta un'altra foto sulla carta",
                     howTo: "Nella striscia sotto la carta tocca un'anteprima diversa da quella evidenziata.",
                     check: "Quella foto sale sulla carta (un video parte subito) e nella striscia diventa quella evidenziata.",
                     event: .stripSelect),
                task("similar.menu", "Decidi una foto senza portarla sulla carta",
                     howTo: "Tieni premuta un'anteprima della striscia e scegli Conserva, Proponi per l'eliminazione o Segna come migliore.",
                     check: "Sull'anteprima compare il simbolo della decisione: segno verde, cestino rosso o stella.",
                     event: .stripMenu),
                task("similar.best", "Tieni la migliore in un tocco",
                     howTo: "Tocca «Tieni la migliore» (o «Tieni la tua migliore» se hai messo delle stelle).",
                     check: "La foto consigliata resta conservata, le altre passano alla Revisione e la sessione va avanti.",
                     event: .keepBest),
                task("similar.only", "Tieni solo quella sulla carta",
                     howTo: "Tocca «Tieni solo questa» con sulla carta la foto che preferisci.",
                     check: "Resta solo quella; le altre del gruppo vanno in Revisione.",
                     event: .keepOnlyCurrent),
                task("similar.undo", "Annulla una scelta su tutto il gruppo",
                     howTo: "Subito dopo «Tieni la migliore» tocca Annulla.",
                     check: "Tutte le foto del gruppo tornano da decidere con un solo tocco.",
                     event: .undoGroup)
            ]
        ),
        Tutorial(
            id: "gallery",
            title: "Galleria e stelle",
            systemImage: "square.grid.3x3",
            goal: "Decidere un gruppo in pochi tocchi: la migliore resta, le altre si eliminano subito. Tocchi, trascinamento e stelle come nell'app Foto.",
            preparation: "Apri le Foto simili e tocca un gruppo: si apre la galleria «Scegli le migliori».",
            destination: .similarGroups,
            chapterID: "gallery",
            tasks: [
                task("gallery.open", "Apri la galleria di un gruppo",
                     howTo: "In Esplora → Foto → Foto simili tocca un gruppo, oppure tocca «Griglia» nella striscia dello swipe.",
                     check: "Vedi tutte le foto del gruppo: la consigliata ha il segno verde, le altre il cestino rosso.",
                     event: .openGallery),
                task("gallery.toggle", "Cambia la scelta con un tocco",
                     howTo: "Tocca una foto con il cestino: diventa verde e resta. Toccala di nuovo per rimetterla tra quelle da eliminare.",
                     check: "In basso il conteggio cambia: «N da eliminare · M da tenere».",
                     event: .galleryToggle),
                task("gallery.drag", "Cambia tante foto trascinando il dito",
                     howTo: "Appoggia il dito su una foto e trascinalo di lato, ben in orizzontale, sulle altre; poi, senza staccare, scendi alla riga sotto. Un gesto verticale o in diagonale fa invece scorrere la griglia, e non cambia nessuna scelta.",
                     check: "Tutte le foto toccate prendono la stessa scelta: se la prima era da tenere diventano da eliminare, e viceversa.",
                     event: .dragSelect),
                task("gallery.quick", "Usa una scelta rapida",
                     howTo: "Nel menu «…» in alto tocca «Segna tutte da eliminare», poi «Ripristina la proposta».",
                     check: "La scelta cambia per tutto il gruppo e poi torna com'era all'apertura.",
                     event: .quickSelect),
                task("gallery.star", "Segna la tua migliore con la stella",
                     howTo: "Tieni premuta una foto e scegli «Segna come migliore».",
                     check: "Sulla foto compare una stella gialla e il segno verde: resta conservata.",
                     event: .starBest),
                task("gallery.unstar", "Togli una stella",
                     howTo: "Tieni premuta una foto con la stella e scegli «Togli la stella» (oppure usa il menu «…» → Togli tutte le stelle).",
                     check: "La stella sparisce; la foto resta conservata.",
                     event: .removeStar),
                task("gallery.order", "Metti prima le migliori",
                     howTo: "Nel menu «…» in alto scegli «Prima le migliori».",
                     check: "Le foto con la stella vengono per prime, poi quelle con il voto più alto.",
                     event: .galleryOrder),
                task("gallery.menu", "Usa il menu di una foto",
                     howTo: "Tieni premuta una foto: vedi l'anteprima grande e un menu (Vedi a tutto schermo, Confronta da qui, Segna come migliore, Tieni o Elimina). Scegli una voce.",
                     check: "L'azione scelta vale per quella sola foto.",
                     event: .galleryMenu),
                task("gallery.delete", "Elimina le foto scartate",
                     howTo: "Con le foto da eliminare segnate dal cestino tocca «Elimina N» in basso e conferma l'avviso di iOS. Per file e contenuti importanti ClearSpace chiede prima anche la sua conferma.",
                     check: "Le foto spariscono dal gruppo e restano 30 giorni in «Eliminati di recente» dell'app Foto.",
                     event: nil),
                task("gallery.sequence", "Decidi un gruppo dopo l'altro",
                     howTo: "Nell'elenco delle Foto simili (dalla Home: «Foto simili» in «Da dove iniziare») tocca «Decidi un gruppo dopo l'altro». In ogni gruppo tocca «Elimina» o «Tieni tutte», oppure «Salta» in alto per lasciarlo da decidere.",
                     check: "In alto leggi «Gruppo 1 di N»; dopo la scelta compare da solo il gruppo successivo e alla fine il riepilogo.",
                     event: .groupSequence),
                task("gallery.batch", "Decidi tutti i gruppi in una volta",
                     howTo: "Nell'elenco delle Foto simili tocca «Tieni la migliore in tutti i gruppi». Controlla le foto con il cestino, escludi con il cerchio i gruppi da lasciare stare, poi tocca «Elimina» e conferma l'avviso di iOS.",
                     check: "Vedi tutti i gruppi in una schermata; dopo la conferma resta la migliore di ognuno e le altre vanno in «Eliminati di recente».",
                     event: .groupBatch)
            ]
        ),
        Tutorial(
            id: "compare",
            title: "Il confronto",
            systemImage: "rectangle.split.2x1",
            goal: "Guardare le foto simili in grande, una dopo l'altra, con lo zoom che resta sullo stesso punto.",
            preparation: "Apri un gruppo di foto simili e tocca «Confronta».",
            destination: .similarGroups,
            chapterID: "compare",
            tasks: [
                task("compare.open", "Apri il confronto",
                     howTo: "Nella galleria di un gruppo tocca «Confronta», oppure nello swipe tocca «Confronta» sopra la striscia.",
                     check: "In alto vedi la foto grande con «1 di N»; sotto la striscia con i voti e il motivo del consiglio.",
                     event: .openCompare),
                task("compare.zoom", "Ingrandisci un dettaglio",
                     howTo: "Tocca due volte la foto grande, oppure allarga due dita.",
                     check: "La foto si ingrandisce e compare il pulsante «Riduci».",
                     event: .compareZoom),
                task("compare.step", "Passa alla foto vicina",
                     howTo: "Trascina la foto grande in orizzontale: segue il dito e passa a quella vicina. Con lo zoom attivo continua oltre il bordo della foto ingrandita. Oppure tocca un'anteprima della striscia.",
                     check: "Il contatore passa a «2 di N» e la striscia evidenzia la nuova foto.",
                     event: .compareStep),
                task("compare.decide", "Decidi la foto selezionata",
                     howTo: "Usa il selettore Tieni / Elimina sotto le etichette, oppure tocca la stella accanto.",
                     check: "Sull'anteprima della striscia compare il segno della decisione.",
                     event: .compareDecision)
            ]
        ),
        Tutorial(
            id: "explore",
            title: "Esplora, categorie e griglie",
            systemImage: "square.grid.2x2",
            goal: "Trovare i contenuti per tipo, ordinarli, guardarli e decidere più elementi insieme.",
            preparation: "Apri Esplora → Foto. Ogni categoria è solo un filtro: appartenervi non significa che un elemento vada eliminato.",
            destination: .photoCategories,
            chapterID: "grids",
            tasks: [
                task("explore.category", "Apri una categoria",
                     howTo: "Tocca ad esempio «Screenshot» o «Tutte le foto».",
                     check: "Si apre la griglia con il numero di elementi e lo spazio occupato.",
                     event: .openCategory),
                task("explore.sort", "Cambia l'ordine",
                     howTo: "Tocca le due frecce in alto e scegli «Più pesanti», «Più vecchi», «Consigliati»…",
                     check: "La griglia si riordina subito.",
                     event: .sortGrid),
                task("explore.preview", "Guarda un elemento a tutto schermo",
                     howTo: "Tocca un'anteprima della griglia (fuori dalla selezione).",
                     check: "Si apre l'anteprima con i pulsanti Da eliminare e Conserva; scorrendo di lato passi all'elemento vicino.",
                     event: .preview),
                task("explore.select", "Entra in selezione",
                     howTo: "Tocca «Seleziona» in alto, poi tocca o trascina il dito sulle anteprime.",
                     check: "Sulle anteprime compare il cerchio di selezione e in basso la barra delle azioni.",
                     event: .selectMode),
                task("explore.action", "Applica un'azione a più elementi",
                     howTo: "Con qualche elemento selezionato tocca Da eliminare, Conserva o Proteggi.",
                     check: "Un messaggio conferma l'operazione e le anteprime mostrano il nuovo stato.",
                     event: .gridAction),
                task("explore.groups", "Apri i gruppi di duplicati o di simili",
                     howTo: "In Esplora → Foto tocca «Foto duplicate» o «Foto simili».",
                     check: "Vedi l'elenco dei gruppi con le anteprime e lo spazio potenziale.",
                     event: .openGroups)
            ]
        ),
        Tutorial(
            id: "search",
            title: "La ricerca intelligente",
            systemImage: "sparkle.magnifyingglass",
            goal: "Trovare contenuti scrivendo come parleresti, combinando tipo, periodo, dimensione e caratteristiche.",
            preparation: "Apri Esplora → Ricerca intelligente.",
            destination: .smartSearch,
            chapterID: "search",
            tasks: [
                task("search.run", "Fai una ricerca",
                     howTo: "Scrivi «screenshot più vecchi di un anno con testo» e tocca Cerca.",
                     check: "Sotto compare «Come ho interpretato la richiesta» con le etichette Screenshot, Con testo, età.",
                     event: .search),
                task("search.results", "Apri i risultati",
                     howTo: "Tocca «Mostra i risultati».",
                     check: "Si apre una griglia con gli elementi trovati, da cui puoi anche avviare lo swipe.",
                     event: .searchResults),
                task("search.size", "Cerca per dimensione e quantità",
                     howTo: "Prova «i 20 video più pesanti» oppure «video più grandi di 500 MB».",
                     check: "Le etichette mostrano Video, Dal più pesante e il limite di risultati o la soglia.",
                     event: nil),
                task("search.period", "Cerca per periodo",
                     howTo: "Prova «foto di agosto 2024», «video dell'anno scorso» o «registrazioni più lunghe di 10 minuti».",
                     check: "Le etichette mostrano il mese, l'anno o la durata riconosciuti.",
                     event: nil),
                task("search.text", "Cerca una parola esatta",
                     howTo: "Scrivi una parola tra virgolette, per esempio «\"fattura\"»: viene cercata nei nomi dei file, nel testo riconosciuto e nelle trascrizioni.",
                     check: "Tra le etichette compare il testo cercato.",
                     event: nil)
            ]
        ),
        Tutorial(
            id: "modes",
            title: "Le modalità di pulizia",
            systemImage: "list.number",
            goal: "Provare i cinque modi di affrontare la pulizia: rapida, guidata, avanzata, per obiettivo e annuale.",
            preparation: "Parti dalla Home: le modalità sono nella sezione «Modalità di pulizia».",
            destination: .guidedCleanup,
            chapterID: "modes",
            tasks: [
                task("modes.quick", "Avvia una pulizia rapida",
                     howTo: "Nella Home tocca «Avvia pulizia intelligente» (oppure «Scegli quanti elementi rivedere» → Avvia la pulizia rapida).",
                     check: "Parte lo swipe con gli elementi che conviene rivedere per primi.",
                     event: .quickCleanup),
                task("modes.guided", "Avvia un passo della pulizia guidata",
                     howTo: "Apri Pulizia guidata e tocca «Rivedi con gli swipe» in un passo che ha elementi.",
                     check: "Parte lo swipe con solo gli elementi di quel passo.",
                     event: .guidedStep),
                task("modes.check", "Segna un passo come completato",
                     howTo: "In Pulizia guidata attiva l'interruttore «Passo completato».",
                     check: "Il numero del passo diventa verde: ti ricorda dove sei arrivato.",
                     event: .guidedCheck),
                task("modes.advanced", "Usa i filtri della pulizia avanzata",
                     howTo: "Apri Pulizia avanzata, scegli almeno un tipo (ad esempio Video) e una dimensione minima, poi avvia lo swipe.",
                     check: "Lo swipe contiene solo gli elementi che rispettano tutti i filtri.",
                     event: .advancedCleanup),
                task("modes.goal", "Avvia una pulizia per obiettivo",
                     howTo: "Nella Home tocca «Pulizia per obiettivo», scegli quanti GB e tocca Avvia.",
                     check: "Nello swipe compare la barra verde dell'obiettivo che si riempie man mano.",
                     event: .goalCleanup),
                task("modes.resume", "Riprendi una sessione interrotta",
                     howTo: "Chiudi uno swipe a metà con Chiudi, poi nella Home tocca «Riprendi».",
                     check: "La sessione riparte dall'elemento in cui l'avevi lasciata.",
                     event: .resumeSession)
            ]
        ),
        Tutorial(
            id: "archive",
            title: "Archivio, viaggi e nostalgia",
            systemImage: "calendar",
            goal: "Rivedere la libreria per anno e per mese, per viaggio e per ricorrenza.",
            preparation: "Apri Esplora → Archivio storico e pulizia annuale.",
            destination: .archive,
            chapterID: "archive",
            tasks: [
                task("archive.year", "Apri un anno",
                     howTo: "Tocca un anno nell'elenco.",
                     check: "Vedi i mesi con quanti elementi e quanto spazio occupano.",
                     event: .openYear),
                task("archive.annual", "Avvia la pulizia di un anno",
                     howTo: "Dentro un anno tocca «Pulizia annuale» seguito dall'anno.",
                     check: "Parte lo swipe con i contenuti di quell'anno ancora da decidere.",
                     event: .annualCleanup),
                task("archive.trips", "Apri la modalità viaggio",
                     howTo: "In Esplora tocca «Modalità viaggio».",
                     check: "Vedi i viaggi riconosciuti dalle posizioni delle foto (servono foto con la posizione).",
                     event: .openTrips),
                task("archive.place", "Mostra il nome di un luogo",
                     howTo: "In un viaggio tocca «Mostra il luogo»: è l'unico caso in cui una posizione viene inviata ad Apple, e solo su tua richiesta.",
                     check: "Al posto di «Viaggio di N giorni» compare la città e il paese.",
                     event: .tripPlace),
                task("archive.nostalgia", "Apri la modalità nostalgia",
                     howTo: "In Esplora tocca «Modalità nostalgia».",
                     check: "Vedi le foto scattate oggi negli anni passati, se ce ne sono.",
                     event: .openNostalgia)
            ]
        ),
        Tutorial(
            id: "review",
            title: "Revisione ed eliminazione",
            systemImage: "checklist",
            goal: "Controllare la lista, ripristinare ciò che vuoi tenere e capire la conferma finale senza eliminare per errore.",
            preparation: "Proponi prima qualche elemento per l'eliminazione (ad esempio con uno swipe a sinistra), poi apri la scheda Revisione.",
            destination: .reviewTab,
            chapterID: "review",
            tasks: [
                task("review.item", "Ripristina un singolo elemento",
                     howTo: "Tocca la freccia blu nell'angolo in alto a destra di un'anteprima.",
                     check: "L'elemento sparisce dalla lista e torna tra quelli da rivedere.",
                     event: .restoreItem),
                task("review.group", "Ripristina un'intera sezione",
                     howTo: "Tocca «Ripristina gruppo» accanto al titolo di una sezione (Foto, Video, File…).",
                     check: "Tutta la sezione torna tra gli elementi da rivedere.",
                     event: .restoreGroup),
                task("review.confirm", "Apri la conferma senza eliminare",
                     howTo: "Tocca «Controlla ed elimina»: leggi cosa verrebbe eliminato e lo spazio su iPhone e su iCloud, poi tocca Annulla.",
                     check: "Hai visto la conferma; senza toccare «Elimina» non succede nulla.",
                     event: .openConfirmation),
                task("review.archive", "Scopri l'archiviazione guidata",
                     howTo: "Tocca «Archivia prima»: serve a copiare i contenuti in un'altra posizione, con verifica, prima di eliminarli. Chiudi con Fine.",
                     check: "Si apre l'Archiviazione guidata con «Cosa archiviare» e «Destinazione».",
                     event: .archiveWizard)
            ]
        ),
        Tutorial(
            id: "results",
            title: "Risultati e promemoria",
            systemImage: "chart.bar",
            goal: "Leggere cosa è stato davvero fatto e programmare un promemoria per la prossima pulizia.",
            preparation: "Apri la scheda Risultati. Il confronto prima/dopo compare dopo la prima eliminazione confermata.",
            destination: .resultsTab,
            chapterID: "results",
            tasks: [
                task("results.reminder", "Imposta un promemoria",
                     howTo: "In fondo a Risultati scegli una frequenza in «Promemoria», ad esempio Ogni mese.",
                     check: "iOS chiede il permesso per le notifiche la prima volta; il promemoria non elimina mai nulla.",
                     event: .reminder),
                task("results.measure", "Aggiorna la misura dello spazio",
                     howTo: "Dopo un'eliminazione tocca «Aggiorna la misura» nel confronto prima/dopo.",
                     check: "Compare «Misura aggiornata» e lo spazio libero attuale.",
                     event: .remeasure),
                task("results.report", "Apri il dettaglio di un'operazione",
                     howTo: "Nella cronologia tocca un'operazione.",
                     check: "Vedi l'esito di ogni elemento: eliminato, non riuscito, escluso.",
                     event: .reportDetail)
            ]
        ),
        Tutorial(
            id: "analyze",
            title: "L'analisi",
            systemImage: "waveform.and.magnifyingglass",
            goal: "Avviare, mettere in pausa e capire le fasi dell'analisi.",
            preparation: "Apri la scheda Analizza.",
            destination: .analyzeTab,
            chapterID: "analysis",
            tasks: [
                task("analyze.start", "Avvia un'analisi",
                     howTo: "Tocca «Analisi completa» (tutte le fasi) oppure «Rapida» (solo ciò che è nuovo o cambiato).",
                     check: "Lo stato diventa «Fase A · Metadati» e le percentuali avanzano.",
                     event: .startScan),
                task("analyze.pause", "Metti in pausa l'analisi",
                     howTo: "Mentre è in corso tocca «Pausa», poi «Riprendi».",
                     check: "Lo stato mostra «Analisi in pausa» e poi riparte da dove era.",
                     event: .pauseScan)
            ]
        ),
        Tutorial(
            id: "details",
            title: "Dettagli e protezioni",
            systemImage: "lock.shield",
            goal: "Proteggere ciò che non deve mai essere proposto e capire le protezioni automatiche.",
            preparation: "Apri un elemento qualsiasi a tutto schermo e tocca il pulsante «i» (Dettagli).",
            destination: .protections,
            chapterID: "protections",
            tasks: [
                task("details.open", "Apri i dettagli di un elemento",
                     howTo: "Dallo swipe tocca Dettagli, oppure dall'anteprima a tutto schermo tocca «i».",
                     check: "Vedi informazioni, spazio, analisi e la sezione Protezione.",
                     event: .details),
                task("details.protect", "Proteggi un elemento",
                     howTo: "Nei Dettagli tocca «Proteggi questo elemento», oppure in una griglia seleziona e tocca Proteggi.",
                     check: "Compare il lucchetto: l'elemento esce da ogni sessione di pulizia.",
                     event: .protectItem),
                task("details.unlock", "Sblocca un preferito per un solo elemento",
                     howTo: "Nei Dettagli di un preferito tocca «Sblocca solo questo elemento».",
                     check: "Solo quell'elemento può essere proposto; gli altri preferiti restano protetti.",
                     event: .unlockItem),
                task("details.rules", "Imposta una protezione automatica",
                     howTo: "In Impostazioni → Elementi protetti scegli un album protetto o aggiungi un periodo (ad esempio un viaggio importante).",
                     check: "Gli elementi di quell'album o periodo non compaiono più nelle sessioni.",
                     event: .protectionRules)
            ]
        ),
        Tutorial(
            id: "documents",
            title: "Documenti e file",
            systemImage: "doc.on.doc",
            goal: "Autorizzare una cartella, trovare file pesanti e duplicati, liberare copie locali e riordinare.",
            preparation: "Apri Esplora → Documenti e file. Serve una cartella con qualche file (anche iCloud Drive o Download).",
            destination: .documents,
            chapterID: "documents",
            tasks: [
                task("documents.folder", "Aggiungi una cartella",
                     howTo: "Tocca «Aggiungi una cartella» e scegli una cartella nel selettore di iOS.",
                     check: "La cartella compare tra le Cartelle autorizzate e l'analisi la legge.",
                     event: .addFolder),
                task("documents.local", "Libera la copia locale di un file di iCloud Drive",
                     howTo: "Apri «Copie locali di iCloud Drive», seleziona dei file e tocca «Libera … sul dispositivo».",
                     check: "I file restano in iCloud Drive ma non occupano più spazio sull'iPhone.",
                     event: .freeLocalCopy),
                task("documents.organize", "Riordina i file",
                     howTo: "Tocca «Organizza per tipo o per anno», scegli il criterio e guarda l'anteprima prima di spostare.",
                     check: "L'anteprima mostra in quali sottocartelle finirebbero i file. Nessun file viene eliminato.",
                     event: .organize)
            ]
        ),
        Tutorial(
            id: "audio",
            title: "Audio e registrazioni",
            systemImage: "waveform",
            goal: "Importare memo vocali, trascriverli e ritrovarli cercando una parola.",
            preparation: "Da Memo Vocali: apri una registrazione → Condividi → ClearSpace. Oppure aggiungi una cartella con file audio.",
            destination: .audio,
            chapterID: "audio",
            tasks: [
                task("audio.import", "Importa una registrazione",
                     howTo: "Tocca «Importa file audio» e scegli un file, oppure condividilo da Memo Vocali verso ClearSpace.",
                     check: "La registrazione compare in Tutti gli audio.",
                     event: .importAudio),
                task("audio.transcribe", "Trascrivi una registrazione",
                     howTo: "Apri una registrazione e tocca «Trascrivi sul dispositivo»: l'audio non lascia il telefono.",
                     check: "Compare il testo e il segno «Trascritta».",
                     event: .transcribe),
                task("audio.search", "Cerca nelle registrazioni",
                     howTo: "Scrivi una parola nel campo «Cerca nelle registrazioni» e conferma.",
                     check: "Vedi le registrazioni il cui nome o la cui trascrizione contengono la parola.",
                     event: .audioSearch)
            ]
        ),
        Tutorial(
            id: "compression",
            title: "Comprimere un video",
            systemImage: "film",
            goal: "Creare una copia più leggera di un video, confrontarla con l'originale e decidere.",
            preparation: "Apri Tutti i video, tocca un video, poi «i» (Dettagli) → «Comprimi questo video».",
            destination: .allVideos,
            chapterID: "compression",
            tasks: [
                task("compression.create", "Crea una versione compressa",
                     howTo: "Scegli un profilo (1080p HEVC, 720p o Qualità media) e tocca «Crea la versione compressa».",
                     check: "Vedi l'anteprima della copia accanto all'originale. Se non ti convince, tocca Scarta: l'originale resta com'era.",
                     event: .compressVideo)
            ]
        ),
        Tutorial(
            id: "icloud",
            title: "iCloud e altre app",
            systemImage: "icloud",
            goal: "Dire all'app come usi Foto di iCloud e seguire le guide per le altre app.",
            preparation: "Apri il Centro iCloud dalla Home o da Esplora.",
            destination: .iCloudCenter,
            chapterID: "icloud",
            tasks: [
                task("icloud.state", "Indica se usi Foto di iCloud",
                     howTo: "In Centro iCloud (o Impostazioni → iCloud) scegli Attivo o Disattivato in «Foto di iCloud».",
                     check: "La conferma di eliminazione mostra con precisione gli effetti su iCloud.",
                     event: .iCloudState),
                task("icloud.quota", "Inserisci il tuo piano iCloud",
                     howTo: "In «Il tuo piano iCloud» scrivi lo spazio totale e quello usato (li trovi in Impostazioni di iOS → il tuo nome → iCloud) e tocca Salva.",
                     check: "Nella Home il riquadro iCloud mostra i tuoi valori con la dicitura «inserito da te».",
                     event: .iCloudQuota),
                task("icloud.guide", "Apri la guida di un'altra app",
                     howTo: "In Esplora → Assistente app tocca ad esempio WhatsApp.",
                     check: "Vedi i passi da seguire in quell'app, perché iOS non permette a ClearSpace di entrarci.",
                     event: .appGuide),
                task("icloud.check", "Segna una procedura come completata",
                     howTo: "Nella guida di un'app, dopo averla seguita, attiva «Procedura completata».",
                     check: "In cima all'Assistente app il conteggio «Checklist di pulizia» aumenta.",
                     event: .appChecklist)
            ]
        )
    ]

    static func tutorial(_ id: String) -> Tutorial? {
        all.first { $0.id == id }
    }

    /// Esercizi completati: quelli con un evento registrato o segnati a mano.
    static func completedCount(_ tutorial: Tutorial, isDone: (TutorialTask) -> Bool) -> Int {
        tutorial.tasks.filter(isDone).count
    }
}
