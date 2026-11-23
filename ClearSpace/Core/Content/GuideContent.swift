import Foundation

/// Una sezione di un capitolo della guida: paragrafi, punti elenco e un consiglio facoltativo.
struct GuideSection: Identifiable, Sendable {
    let title: String
    let paragraphs: [String]
    let points: [String]
    let tip: String?

    var id: String { title }

    /// Tutto il testo della sezione, per la ricerca nella guida.
    var searchableText: String {
        ([title] + paragraphs + points + [tip ?? ""]).joined(separator: " ")
    }
}

/// Un capitolo della guida completa: uno per strumento o argomento.
struct GuideChapter: Identifiable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let summary: String
    let sections: [GuideSection]
    /// Tutorial pratico collegato, se esiste.
    let tutorialID: String?
    /// Strumento che il capitolo descrive, da aprire con un tocco.
    let destination: GuideDestination?

    var searchableText: String {
        ([title, summary] + sections.map { $0.searchableText }).joined(separator: " ")
    }
}

/// La guida completa di ClearSpace: ogni strumento, ogni gesto, ogni categoria e ogni impostazione.
enum GuideBook {

    private static func section(
        _ title: String,
        _ paragraphs: [String] = [],
        points: [String] = [],
        tip: String? = nil
    ) -> GuideSection {
        GuideSection(title: title, paragraphs: paragraphs, points: points, tip: tip)
    }

    static func chapter(_ id: String) -> GuideChapter? {
        chapters.first { $0.id == id }
    }

    // MARK: - Categorie

    /// Spiegazione di ogni categoria: cosa contiene e come viene riconosciuta.
    static func explanation(of collection: SmartCollection) -> String {
        switch collection {
        case .allPhotos: return "Tutte le foto della libreria a cui hai dato accesso, senza filtri."
        case .screenshots: return "Le schermate catturate con l'iPhone, riconosciute dai metadati di iOS."
        case .oldScreenshots: return "Screenshot di più di un anno fa: spesso servivano solo sul momento."
        case .recentScreenshots: return "Screenshot dell'ultimo anno, da rivedere con più attenzione."
        case .textScreenshots: return "Screenshot in cui il riconoscimento del testo (OCR, sul dispositivo) ha trovato delle scritte."
        case .conversationScreenshots: return "Screenshot che sembrano chat o messaggi, riconosciuti dalla disposizione del testo."
        case .receiptScreenshots: return "Screenshot di ricevute, scontrini, biglietti e conferme: possono essere importanti, quindi sono segnalati in revisione."
        case .qrCodes: return "Immagini che contengono un codice QR (biglietti, pagamenti, accessi): da controllare prima di eliminarle."
        case .duplicatePhotos: return "Gruppi di foto uguali: «Duplicati esatti» se il contenuto è identico, verificato sull'originale con l'impronta SHA-256; «Probabili duplicati» se uguali solo nelle anteprime."
        case .similarPhotos: return "Gruppi di scatti dello stesso soggetto, fatti a pochi minuti di distanza o in raffica: l'app consiglia quale tenere."
        case .blurryPhotos: return "Foto con pochi dettagli nitidi: probabile mosso o messa a fuoco sbagliata. È una stima: controllala ingrandendo."
        case .darkPhotos: return "Foto quasi nere o senza contenuto (ad esempio scattate in tasca)."
        case .lowResolutionPhotos: return "Immagini sotto mezzo megapixel: miniature salvate o foto molto vecchie."
        case .heavyPhotos: return "Foto che pesano molto rispetto ai pixel che hanno (formati poco compressi o file anomali)."
        case .selfies: return "Scatti fatti con la fotocamera frontale."
        case .portraits: return "Foto in modalità Ritratto, con l'effetto profondità."
        case .panoramas: return "Foto panoramiche, spesso molto pesanti."
        case .livePhotos: return "Foto che contengono anche un breve video: occupano più spazio di una foto normale."
        case .bursts: return "Sequenze di scatti rapidi riconosciute da iOS: di solito basta tenerne uno."
        case .savedFromApps: return "Immagini probabilmente salvate da altre app (WhatsApp, Telegram, browser), stimate dal nome del file."
        case .photosWithText: return "Foto (non screenshot) in cui è stato riconosciuto del testo: cartelli, appunti, lavagne."
        case .photographedDocuments: return "Foto di pagine, ricevute e biglietti riconosciute dal riconoscimento dei documenti di Vision."
        case .alreadyKept: return "Foto e video che hai già deciso di conservare: escono dalle sessioni di pulizia."
        case .allVideos: return "Tutti i video della libreria."
        case .largeVideos: return "Video più grandi della soglia scelta in Impostazioni → Soglie (100 MB se non la cambi)."
        case .veryLargeVideos: return "Video di oltre 500 MB ciascuno."
        case .hugeVideos: return "Video di oltre 1 GB ciascuno: i primi da controllare quando serve spazio."
        case .longVideos: return "Video di più di tre minuti."
        case .screenRecordings: return "Registrazioni dello schermo dell'iPhone."
        case .video4K: return "Video registrati in 4K: belli ma molto pesanti; si possono comprimere."
        case .highFrameRateVideos: return "Slow motion e video a 60 fotogrammi al secondo o più."
        case .duplicateVideos: return "Copie identiche dello stesso video."
        case .similarVideos: return "Video quasi uguali, girati a poca distanza di tempo: puoi guardarli uno per uno e tenerne uno."
        case .oldVideos: return "Video registrati più di due anni fa: l'età da sola non è un motivo per eliminarli."
        case .allFiles: return "Tutti i file delle cartelle che hai autorizzato (iCloud Drive, Download, cartelle locali)."
        case .pdfs: return "Documenti PDF."
        case .officeDocuments: return "Documenti Word, fogli Excel e presentazioni PowerPoint (anche Pages, Numbers, Keynote)."
        case .archives: return "Archivi ZIP, RAR, 7Z e simili."
        case .downloads: return "File nelle cartelle Download."
        case .mediaFiles: return "Foto e video salvati come file: spesso sono copie di contenuti già presenti in Foto."
        case .unknownFiles: return "File di un formato che l'app non riconosce."
        case .largeFiles: return "File di oltre 50 MB."
        case .oldFiles: return "File non modificati da più di due anni."
        case .duplicateFiles: return "File identici, verificati sul contenuto con l'impronta SHA-256."
        case .documentVersions: return "Versioni dello stesso documento: testo quasi identico o nomi molto simili (ad esempio «finale», «finale2»)."
        case .cloudOnlyFiles: return "File di iCloud Drive presenti solo online: non occupano spazio sull'iPhone."
        case .downloadedCloudFiles: return "File di iCloud Drive scaricati sull'iPhone: puoi liberare la copia locale senza eliminarli."
        case .allAudio: return "Tutti i file audio accessibili o importati in ClearSpace."
        case .longAudio: return "Registrazioni di oltre dieci minuti."
        case .silentAudio: return "Registrazioni con pause di almeno cinque secondi (registrazioni partite per sbaglio, tasche, riunioni finite)."
        case .duplicateAudio: return "Registrazioni identiche, verificate sul contenuto."
        case .similarAudio: return "Registrazioni con durata e andamento sonoro molto simili."
        }
    }

    private static func categorySection(_ section: CollectionSection) -> GuideSection {
        let points = SmartCollection.collections(in: section).map { collection in
            "\(collection.title): \(explanation(of: collection))"
        }
        return GuideSection(
            title: "Categorie di «\(section.title)»",
            paragraphs: [],
            points: points,
            tip: nil
        )
    }

    // MARK: - Capitoli

    static let chapters: [GuideChapter] = [
        GuideChapter(
            id: "start",
            title: "Primi passi",
            systemImage: "flag.checkered",
            summary: "Cos'è ClearSpace, la regola d'oro della sicurezza e come iniziare.",
            sections: [
                section("Cos'è ClearSpace", [
                    "ClearSpace ti aiuta a liberare spazio sull'iPhone e su iCloud: trova duplicati, foto simili, video ingombranti, screenshot, documenti e registrazioni, e ti accompagna nella scelta con pochi gesti.",
                    "Tutte le analisi avvengono sul dispositivo: foto, video e documenti non vengono mai inviati a un server."
                ]),
                section("La regola d'oro: decidi sempre tu", [
                    "Nessun gesto e nessun pulsante elimina davvero qualcosa. Proporre un elemento significa solo metterlo nella lista della scheda Revisione.",
                    "Si elimina solo dalla Revisione, dopo una schermata di conferma che mostra esattamente cosa succede su iPhone e su iCloud, e dopo l'ulteriore conferma di iOS per foto e video."
                ], points: [
                    "Puoi annullare ogni scelta prima della conferma finale.",
                    "Le foto eliminate restano per 30 giorni in Eliminati di recente dell'app Foto.",
                    "Preferiti, foto nascoste e ciò che proteggi non vengono mai proposti."
                ]),
                section("Il primo avvio", [
                    "L'introduzione ha tre pagine: benvenuto, sicurezza e accesso a Foto. Sull'ultima tocca «Consenti l'accesso a Foto».",
                    "Scegli l'accesso completo: con l'accesso limitato ClearSpace vede solo le foto che hai selezionato e la Home lo segnala. Puoi cambiarlo in qualsiasi momento da Impostazioni di iOS → ClearSpace → Foto.",
                    "Subito dopo parte l'analisi: puoi usare l'app mentre lavora, i risultati compaiono man mano."
                ], tip: "Puoi rivedere l'introduzione da Impostazioni → Rivedi l'introduzione: l'analisi non riparte."),
                section("Le cinque schede", points: [
                    "Home: spazio occupato, spazio recuperabile, pulizia rapida, modalità di pulizia e categorie.",
                    "Analizza: stato e fasi dell'analisi, opzioni di download e batteria.",
                    "Esplora: tutte le categorie, la ricerca, l'archivio per anno, i viaggi, i ricordi, iCloud e l'assistente per le altre app.",
                    "Revisione: la lista di ciò che hai proposto, con il numero di elementi in attesa sull'icona.",
                    "Risultati: cosa è stato davvero eliminato, lo spazio recuperato, la cronologia e i promemoria."
                ]),
                section("Impostazioni, guida e tutorial", [
                    "Le Impostazioni si aprono dall'ingranaggio in alto a destra nella Home. Da lì trovi anche questa guida, i tutorial, le novità e le informazioni sull'app.",
                    "I tutorial hanno esercizi veri: si spuntano da soli quando compi l'azione nell'app."
                ]),
                section("Testo grande e tema scuro", [
                    "L'app segue la dimensione del testo e il tema scelti in iOS. Le schermate che scorrono ingrandiscono tutto; quelle che non possono scorrere (swipe, confronto, barre di pulsanti) limitano il testo dei comandi a una dimensione che entra sempre nello schermo."
                ])
            ],
            tutorialID: nil,
            destination: .homeTab
        ),
        GuideChapter(
            id: "home",
            title: "La Home",
            systemImage: "house",
            summary: "Spazio occupato, spazio recuperabile e da dove partire.",
            sections: [
                section("iPhone e iCloud", [
                    "Il riquadro iPhone mostra lo spazio usato e il totale del telefono, con una barra.",
                    "Il riquadro iCloud mostra quanto pesano le foto e i video analizzati. iOS non permette alle app di leggere il totale del tuo piano iCloud: se vuoi vederlo qui, inseriscilo nel Centro iCloud e comparirà con la dicitura «inserito da te»."
                ]),
                section("Spazio potenzialmente recuperabile", [
                    "È una stima sui contenuti analizzati, non spazio già liberato. È divisa in tre voci: foto duplicate e simili, video ingombranti, screenshot e documenti.",
                    "Per i gruppi di duplicati e simili conta solo le copie in più, mai l'elemento che conviene tenere. Mentre l'analisi è in corso la stima può crescere."
                ]),
                section("Pulizia rapida", [
                    "«Avvia pulizia intelligente» apre lo swipe con gli elementi che conviene rivedere per primi: duplicati certi, video grandi, screenshot vecchi e così via, nell'ordine «Consigliati».",
                    "«Scegli quanti elementi rivedere» decide la lunghezza della sessione: 25, 50, 100 o 200 elementi."
                ]),
                section("Pronto da liberare", [
                    "Se hai proposto qualcosa per l'eliminazione ma non hai ancora confermato, sotto lo spazio recuperabile compare questa scheda: quanti elementi e quanto spazio aspettano nella Revisione. «Apri la Revisione» ti porta lì. Finché non confermi non viene eliminato nulla."
                ]),
                section("Scegli le foto migliori", [
                    "Se ci sono gruppi di foto simili ancora da decidere compare questa scheda: apre subito i gruppi uno dopo l'altro, a partire da quello che libera più spazio. In ogni gruppo tieni la migliore e compare da solo il gruppo successivo (vedi il capitolo sulla galleria)."
                ]),
                section("Riprendi da dove eri rimasto", [
                    "Se chiudi uno swipe a metà, la sessione viene salvata. «Riprendi» la riapre dall'elemento in cui eri; «Scarta sessione» la cancella (le scelte già fatte restano)."
                ]),
                section("Modalità e categorie", [
                    "In basso trovi le modalità di pulizia (guidata, avanzata, per obiettivo, annuale) e le scorciatoie alle categorie Foto, Video, Documenti e iCloud Drive, con quanti elementi e quanto spazio contengono."
                ])
            ],
            tutorialID: "modes",
            destination: .homeTab
        ),
        GuideChapter(
            id: "analysis",
            title: "L'analisi e il riconoscimento",
            systemImage: "waveform.and.magnifyingglass",
            summary: "Le fasi dell'analisi, cosa viene riconosciuto e come controllarla.",
            sections: [
                section("Le fasi", points: [
                    "A · Metadati: date, tipi, dimensioni. Non scarica nulla ed è incrementale: riusa i dati degli elementi che non sono cambiati.",
                    "B · Anteprime: nitidezza, luminosità, impronta percettiva, testo degli screenshot (OCR), foto simili, probabili duplicati e scelta dello scatto migliore. Più foto vengono esaminate insieme, su più processori.",
                    "C · Analisi approfondita: impronta SHA-256 degli originali, solo per i possibili duplicati, versioni dei documenti e analisi degli audio.",
                    "D · Raccomandazioni: riepilogo, priorità di revisione, spazio potenziale.",
                    "E · Esecuzione: avviene solo dalla Revisione, dopo la tua conferma."
                ]),
                section("Analisi completa e rapida", [
                    "«Analisi completa» esegue tutte le fasi. «Rapida» rilegge solo ciò che è nuovo o cambiato: è quella che parte da sola quando la libreria cambia.",
                    "Mentre lavora puoi metterla in «Pausa», farla ripartire con «Riprendi» o fermarla con «Interrompi»."
                ]),
                section("Pause automatiche", [
                    "Se l'opzione è attiva, l'analisi si mette in pausa da sola con batteria sotto il 20%, con il risparmio energetico o se il telefono si scalda, e riparte quando le condizioni tornano normali. Le condizioni attuali (rete, batteria, temperatura) sono indicate in fondo alla scheda Analizza."
                ]),
                section("Cosa viene riconosciuto", points: [
                    "Tipi di foto: screenshot, selfie, ritratti, panoramiche, Live Photo, raffiche, foto modificate, preferite, nascoste.",
                    "Contenuto: testo (OCR), chat, ricevute e scontrini, biglietti, codici QR, documenti fotografati.",
                    "Qualità: foto sfocate, scure, vuote, a bassa risoluzione, pesanti per la risoluzione.",
                    "Volti: quanti, qualità secondo Vision, occhi aperti o chiusi, sorrisi (servono per scegliere lo scatto migliore).",
                    "Video: 4K, alto frame rate, slow motion, registrazioni dello schermo, durata, peso.",
                    "File: tipo, cartelle Download, versioni dello stesso documento, file solo su iCloud Drive.",
                    "Audio: durata, silenzi lunghi, registrazioni identiche o simili, trascrizione."
                ], tip: "Il riconoscimento è una stima: nelle categorie come «Foto sfocate» controlla sempre ingrandendo prima di decidere."),
                section("Opzioni", points: [
                    "Scarica da iCloud solo con Wi‑Fi: le anteprime nitide e i video solo su iCloud si scaricano automaticamente solo in Wi‑Fi.",
                    "Consenti il download degli originali per verificare i duplicati: senza questo consenso i contenuti solo su iCloud sono confrontati sulle anteprime e non diventano mai «duplicati esatti».",
                    "Pausa con batteria scarica o dispositivo caldo.",
                    "Includi le foto nascoste nell'analisi (in Impostazioni): se le includi restano comunque protette."
                ])
            ],
            tutorialID: "analyze",
            destination: .analyzeTab
        ),
        GuideChapter(
            id: "swipe",
            title: "Lo swipe",
            systemImage: "hand.draw",
            summary: "Tutti i gesti, i pulsanti, la carta e la fine della sessione.",
            sections: [
                section("I quattro gesti", points: [
                    "Verso destra: conservi l'elemento (scritta verde CONSERVA).",
                    "Verso sinistra: lo proponi per l'eliminazione (scritta rossa DA ELIMINARE). Va nella Revisione, non viene eliminato.",
                    "Verso l'alto: apri i Dettagli (scritta DETTAGLI).",
                    "Verso il basso: decidi più tardi (scritta PIÙ TARDI)."
                ], tip: "Se lasci la carta prima che compaia la scritta piena, torna al suo posto e non succede nulla."),
                section("I pulsanti equivalenti", [
                    "Ogni gesto ha un pulsante nella barra in basso: Elimina (rosso), Più tardi, Annulla, Dettagli, Conserva (verde). Funzionano anche con VoiceOver."
                ]),
                section("Annulla", [
                    "Annulla ripristina l'ultima mossa. Se l'ultima mossa era una scelta su un intero gruppo (ad esempio «Tieni la migliore»), annulla tutto il gruppo in un colpo. Puoi annullare più volte di seguito."
                ]),
                section("L'intestazione", points: [
                    "«Elemento X di Y» e «Da rivedere»: dove sei nella sessione.",
                    "Conservati e Da eliminare, con lo spazio potenziale degli elementi proposti.",
                    "Nelle pulizie per obiettivo: la barra verde dell'obiettivo."
                ]),
                section("La carta", points: [
                    "Foto: si carica nitida (scaricandola da iCloud se serve). Allarga due dita per ingrandire un punto: lasciando torna normale.",
                    "Tocca due volte la foto o il pulsante con le frecce per vederla a tutto schermo.",
                    "Didascalia: titolo, dimensione, durata, data e, per le foto, il voto di qualità da 0 a 100.",
                    "Etichette: «La tua migliore» (stella), «La consigliata del gruppo» (scintille), «Ha N copie», «N scatti simili», Live, Solo su iCloud, Da controllare, Occhi chiusi, Forse sfocata, Molto scura, Apparentemente vuota."
                ]),
                section("Elementi protetti e importanti", [
                    "Un elemento protetto non può essere proposto: con lo swipe a sinistra la carta torna indietro e un messaggio spiega il motivo. Puoi sbloccarlo dai Dettagli.",
                    "I contenuti potenzialmente importanti (ricevute, documenti, codici) si possono proporre, ma vengono evidenziati nella Revisione e richiedono una conferma in più."
                ]),
                section("Fine della sessione", [
                    "Quando hai deciso tutto compare il riepilogo: conservati, da eliminare, rimandati e lo spazio potenziale. Da qui: «Vai alla revisione», «Rivedi i N rimandati», «Annulla l'ultima scelta» e «Chiudi»."
                ]),
                section("Dall'alto della schermata", [
                    "«Chiudi» salva la sessione per riprenderla dalla Home. «Revisione» chiude lo swipe e apre la scheda Revisione."
                ])
            ],
            tutorialID: "swipe",
            destination: .allPhotos
        ),
        GuideChapter(
            id: "video",
            title: "I video nella carta",
            systemImage: "play.rectangle",
            summary: "Guardare un video prima di deciderlo.",
            sections: [
                section("Riproduzione", [
                    "Nello swipe i video partono da soli, senza audio (puoi spegnere l'avvio automatico in Impostazioni → Revisione). Ripartono dall'inizio quando finiscono."
                ], points: [
                    "Tocco sul video: pausa e ripresa.",
                    "Altoparlante: attiva o disattiva l'audio.",
                    "1× / 2×: velocità normale o doppia.",
                    "Barra in basso: trascina o tocca per spostarti.",
                    "Fotogrammi sopra la barra: tocca un momento per saltarci."
                ]),
                section("Video solo su iCloud", [
                    "Se il video non è sul telefono e la rete non permette di scaricarlo automaticamente, compare «Riproduci comunque»: toccalo per scaricarlo e guardarlo."
                ]),
                section("Video simili e compressione", [
                    "Se un video ha delle riprese quasi uguali, sotto la carta compare la striscia dei video simili: tocca un altro video per guardarlo subito sulla carta.",
                    "Per alleggerire un video senza perderlo: Dettagli → «Comprimi questo video» (vedi il capitolo sulla compressione)."
                ])
            ],
            tutorialID: "video",
            destination: .allVideos
        ),
        GuideChapter(
            id: "strip",
            title: "Foto e video simili nello swipe",
            systemImage: "square.stack.3d.down.right",
            summary: "La striscia del gruppo sotto la carta e le scelte su tutto il gruppo.",
            sections: [
                section("La striscia", [
                    "Quando l'elemento sulla carta fa parte di un gruppo di simili o di duplicati, sotto la carta compaiono tutti i membri del gruppo. Le foto di un gruppo vengono proposte una dopo l'altra, con prima quella consigliata."
                ], points: [
                    "Scintille: lo scatto consigliato dall'app.",
                    "Stella gialla: le tue migliori.",
                    "Segno verde, cestino rosso, orologio: conservato, proposto, rimandato.",
                    "▶︎ e durata: è un video."
                ]),
                section("Gesti sulla striscia", points: [
                    "Tocca un'anteprima: quell'elemento sale sulla carta (anche se lo avevi già deciso, per cambiare idea). Un video parte subito.",
                    "Tieni premuta un'anteprima: Mostra sulla carta (o Guarda), Segna come migliore / Togli la stella, Conserva, Proponi per l'eliminazione.",
                    "«Griglia»: tutte le anteprime del gruppo in una galleria con selezione multipla.",
                    "«Confronta»: le foto in grande una dopo l'altra."
                ]),
                section("Scelte su tutto il gruppo", points: [
                    "«Tieni la migliore»: conserva lo scatto consigliato e propone gli altri.",
                    "«Tieni la tua migliore» / «Tieni le tue migliori»: se hai messo delle stelle, conserva quelle e propone il resto.",
                    "«Tieni solo questa»: conserva l'elemento sulla carta e propone gli altri."
                ], tip: "Una scelta sul gruppo si annulla con un solo tocco su Annulla. Gli elementi protetti del gruppo vengono saltati.")
            ],
            tutorialID: "similar",
            destination: .guidedCleanup
        ),
        GuideChapter(
            id: "ranking",
            title: "Come l'app sceglie la migliore",
            systemImage: "sparkles",
            summary: "Come si formano i gruppi, i criteri del voto e il perché di ogni consiglio.",
            sections: [
                section("Come nascono i gruppi", points: [
                    "Raffiche: le sequenze riconosciute da iOS.",
                    "Foto simili: scatti fatti entro pochi minuti l'uno dall'altro e confrontati con le impronte visive di Vision; se manca l'impronta si usa l'impronta percettiva delle anteprime. Quanto devono somigliarsi lo decidi in Impostazioni → Foto simili (Rigorosa, Normale, Ampia).",
                    "Duplicati esatti: stesso contenuto, verificato sull'originale con l'impronta SHA-256.",
                    "Probabili duplicati: anteprime identiche, ma originale non verificato (ad esempio perché è solo su iCloud).",
                    "Video simili, versioni dello stesso documento e registrazioni simili funzionano allo stesso modo con criteri adatti."
                ]),
                section("I criteri del voto", points: [
                    "Nitidezza dell'intera immagine.",
                    "Nitidezza del soggetto: il volto più grande o, senza volti, la zona centrale.",
                    "Qualità dei volti, secondo Vision.",
                    "Occhi aperti e sorrisi.",
                    "Esposizione: né troppo scura né bruciata.",
                    "Giudizio estetico di iOS, dove disponibile.",
                    "Risoluzione."
                ]),
                section("Quanto pesa ogni criterio", [
                    "Nei ritratti contano di più i volti (26%), il soggetto a fuoco (20%), gli occhi aperti (14%) e la nitidezza (14%); poi esposizione e risoluzione (8% ciascuna) e il giudizio estetico.",
                    "Senza volti contano nitidezza (34%), soggetto (20%), risoluzione (18%), esposizione (16%) e giudizio estetico.",
                    "Se mancano le misure approfondite si usano nitidezza, risoluzione ed esposizione.",
                    "Un criterio viene usato solo se è disponibile per tutte le foto del gruppo: non si confrontano numeri calcolati in modo diverso."
                ]),
                section("Le tue scelte contano", points: [
                    "Preferita: +30 punti, perché l'hai già scelta tu.",
                    "Modificata da te: +10 punti.",
                    "Sfocata, scura o vuota: −20 punti.",
                    "Le tue stelle prevalgono sempre sul consiglio."
                ]),
                section("Il voto e il motivo", [
                    "Ogni foto ha un voto da 0 a 100, visibile nella galleria, nel confronto e sulla carta. Il consiglio arriva con il motivo, ad esempio «Conserva la foto 2: ha gli occhi aperti e il soggetto più a fuoco».",
                    "Motivi possibili: è tra i preferiti, ha gli occhi aperti, i volti sono venuti meglio, ha il soggetto più a fuoco, è più nitida, ha una risoluzione superiore, ha un'esposizione migliore, è più riuscita nel complesso, è stata modificata da te; per i video, dura di più.",
                    "Tra duplicati identici si tiene la preferita oppure la copia meno recente, probabilmente l'originale. Se le foto sono equivalenti il consiglio lo dice."
                ], tip: "Quando apri un gruppo che l'analisi non ha ancora misurato, l'app calcola subito le misure mancanti e aggiorna il consiglio.")
            ],
            tutorialID: "gallery",
            destination: .similarGroups
        ),
        GuideChapter(
            id: "gallery",
            title: "La galleria «Scegli le migliori»",
            systemImage: "square.grid.3x3",
            summary: "Tutte le foto di un gruppo in griglia, selezione rapida come in Foto e stelle.",
            sections: [
                section("Come si apre", points: [
                    "Esplora → Foto → Foto simili (o Foto duplicate) → tocca un gruppo.",
                    "Dalla Home: «Scegli le foto migliori» apre i gruppi uno dopo l'altro.",
                    "Nello swipe: «Griglia» sopra la striscia.",
                    "Nel confronto: il pulsante con i quadratini in alto."
                ]),
                section("L'elenco dei gruppi", points: [
                    "Prima vengono i gruppi ancora da decidere, da quello che libera più spazio; quelli in cui ogni foto è già conservata, proposta o protetta finiscono in fondo con l'etichetta «Deciso».",
                    "In cima, «Decidi un gruppo dopo l'altro» dice quanti gruppi restano e quanto spazio potresti liberare. Se sono tutti decisi diventa «Rivedi i gruppi uno dopo l'altro», per ricontrollarli."
                ]),
                section("Un gruppo dopo l'altro", [
                    "Si apre la galleria del primo gruppo da decidere, con «Gruppo 1 di N» in alto e una barra di avanzamento. Dopo «Tieni solo la migliore» (o «Tieni solo le tue migliori», «Tieni tutte») compare da solo il gruppo successivo.",
                    "«Salta», in alto a destra, lascia il gruppo da decidere e passa al prossimo. Se hai già deciso tutte le foto una per una, il pulsante diventa «Avanti».",
                    "Alla fine un riepilogo dice quanti gruppi hai deciso e quanti saltato, con «Vai alla revisione» per controllare ciò che hai scartato. Funziona anche per i video simili e per i duplicati."
                ], tip: "È il modo più veloce per sistemare tante foto simili: in ogni gruppo bastano uno sguardo al consiglio e un tocco."),
                section("In alto", points: [
                    "Il riquadro del consiglio, con le tue stelle e il motivo.",
                    "L'ordine: «Ordine di scatto» oppure «Prima le migliori» (prima le stelle, poi il voto più alto).",
                    "Scelte rapide: Seleziona tutte, Tutte tranne la consigliata (o tranne le tue migliori), Deseleziona."
                ]),
                section("Selezionare", points: [
                    "Tocca una foto per selezionarla o deselezionarla.",
                    "Trascina il dito in orizzontale: selezioni tutte le foto tra la prima e quella sotto il dito, anche scendendo su più righe. Vicino ai bordi la griglia scorre da sola.",
                    "Se cominci da una foto già selezionata, il trascinamento deseleziona.",
                    "Un gesto verticale o in diagonale fa scorrere la griglia."
                ]),
                section("Le anteprime", points: [
                    "Voto da 0 a 100 (o durata per i video) in basso a sinistra.",
                    "Stella gialla o scintille in alto a destra.",
                    "Stato in alto a sinistra; le foto proposte appaiono più scure.",
                    "Tieni premuto: anteprima grande e menu (Vedi a tutto schermo, Confronta da qui, Segna come migliore, Conserva, Proponi per l'eliminazione)."
                ]),
                section("La barra in basso", points: [
                    "«N selezionate» e «Confronta».",
                    "Migliore: mette la stella alle selezionate e le conserva (diventa «Togli stella» se sono già tutte stellate).",
                    "Tieni: conserva le selezionate. Elimina: le propone per l'eliminazione.",
                    "Pulsante verde: «Tieni solo la migliore», «Tieni solo la tua migliore» o «Tieni solo le tue N migliori».",
                    "Menu «…» in alto: Tieni tutte, Togli tutte le stelle."
                ], tip: "Aperta dallo swipe, la galleria si chiude da sola dopo una scelta su tutto il gruppo e la sessione prosegue.")
            ],
            tutorialID: "gallery",
            destination: .similarGroups
        ),
        GuideChapter(
            id: "compare",
            title: "Il confronto",
            systemImage: "rectangle.split.2x1",
            summary: "Le foto simili in grande, con lo zoom condiviso.",
            sections: [
                section("La foto grande", points: [
                    "In alto: «N di M», «La tua migliore» e «Consigliata».",
                    "Doppio tocco: ingrandisce tre volte; di nuovo per tornare normale. Due dita: ingrandimento libero fino a otto volte.",
                    "Con lo zoom attivo trascini per spostarti; «Riduci» torna all'intera foto.",
                    "Senza zoom, scorri in orizzontale per passare alla foto vicina.",
                    "Zoom condiviso: passando a un'altra foto l'ingrandimento resta sullo stesso punto, così vedi subito quale è più nitida.",
                    "I video si riproducono con gli stessi comandi della carta."
                ]),
                section("Sotto la foto", points: [
                    "La striscia del gruppo con il voto di ogni foto: tocca per cambiarla.",
                    "Il consiglio con il motivo, il tipo di gruppo e quanto è certo.",
                    "Le etichette: Voto, Occhi aperti o chiusi, Volti, Sorriso, Forse sfocata, Nitidezza, Molto scura, Modificata, Preferita, megapixel, durata, dimensione e data.",
                    "Tieni / Elimina per la foto selezionata e la stella per segnarla come migliore. Gli elementi protetti mostrano il lucchetto."
                ]),
                section("I pulsanti in basso", points: [
                    "Tieni solo la migliore (o la tua migliore).",
                    "Tieni solo questa: resta la foto selezionata.",
                    "Tieni tutte: conserva tutto il gruppo."
                ])
            ],
            tutorialID: "compare",
            destination: .similarGroups
        ),
        GuideChapter(
            id: "stars",
            title: "Stelle, preferiti e consigliate",
            systemImage: "star",
            summary: "Tre segni diversi e cosa significano.",
            sections: [
                section("La stella di ClearSpace", [
                    "La stella gialla segna le tue migliori di un gruppo. Una foto con la stella è sempre conservata e si riconosce ovunque: striscia, carta, galleria, confronto, griglie ed elenco dei gruppi.",
                    "Le stelle prevalgono sul consiglio: il pulsante verde diventa «Tieni solo la tua migliore» o «Tieni solo le tue N migliori»."
                ], points: [
                    "Mettere la stella: galleria → seleziona → Migliore; menu di una foto → Segna come migliore; confronto → stella; striscia → tieni premuto → Segna come migliore.",
                    "Togliere la stella: gli stessi comandi, oppure il menu «…» → Togli tutte le stelle.",
                    "La stella sparisce da sola se proponi quella foto per l'eliminazione, la rimandi o annulli la decisione."
                ]),
                section("I preferiti di iOS", [
                    "Il cuore dell'app Foto. Se in Impostazioni → Elementi protetti è attivo «Proteggi i preferiti», i preferiti non vengono mai proposti. Nel consiglio valgono +30 punti."
                ]),
                section("Le scintille", [
                    "Indicano lo scatto che l'app ritiene migliore, con il motivo. È solo un consiglio: la scelta è tua."
                ]),
                section("Già conservate", [
                    "Tutto ciò che conservi esce dalle sessioni di pulizia. Lo ritrovi in Esplora → Stato → Già conservati (e in Foto → Già conservate)."
                ])
            ],
            tutorialID: "gallery",
            destination: .similarGroups
        ),
        GuideChapter(
            id: "categories",
            title: "Tutte le categorie",
            systemImage: "square.grid.2x2",
            summary: "Ogni categoria di foto, video, documenti e audio, e come viene riconosciuta.",
            sections: [
                section("Come funzionano", [
                    "Le categorie sono filtri: appartenere a una categoria non significa che un elemento sia da eliminare. Un elemento può stare in più categorie.",
                    "Le categorie a gruppi (duplicati e simili) aprono l'elenco dei gruppi; tutte le altre aprono una griglia."
                ]),
                categorySection(.photos),
                categorySection(.videos),
                categorySection(.documents),
                categorySection(.audio),
                section("Le altre voci di Esplora", points: [
                    "Ricerca intelligente: trovi i contenuti scrivendo una frase.",
                    "Archivio storico e pulizia annuale, Modalità viaggio, Modalità nostalgia.",
                    "Centro iCloud e Assistente app.",
                    "Stato: Già conservati, Rimandati, Elementi protetti."
                ]),
                section("Gruppi di duplicati", [
                    "Nell'elenco dei duplicati «Proponi le copie in più» propone in un colpo tutte le copie dei soli duplicati esatti verificati, lasciando l'elemento suggerito di ogni gruppo. Le somiglianze richiedono sempre una scelta tua."
                ])
            ],
            tutorialID: "explore",
            destination: .photoCategories
        ),
        GuideChapter(
            id: "grids",
            title: "Le griglie",
            systemImage: "square.grid.3x3.square",
            summary: "Ordinare, guardare, selezionare e decidere più elementi insieme.",
            sections: [
                section("In alto", points: [
                    "Descrizione della categoria, numero di elementi e spazio totale.",
                    "«Rivedi con gli swipe»: avvia lo swipe con gli elementi della griglia ancora da decidere.",
                    "Le frecce: l'ordine. «Seleziona»: entra in selezione."
                ]),
                section("Gli ordini", points: [
                    "Consigliati: prima ciò che conviene rivedere (vedi sotto).",
                    "Più pesanti, Più vecchi, Più recenti, Più lunghi (per i video e gli audio), Nome."
                ]),
                section("Come funziona «Consigliati»", [
                    "Ogni elemento ha un punteggio di recuperabilità da 0 a 100 che decide cosa rivedere per primo. Non autorizza mai un'eliminazione."
                ], points: [
                    "Spazio (30%): più pesa, più conta, su una scala da 100 KB a 2 GB.",
                    "Certezza (30%): copie di duplicati esatti più dei probabili duplicati, più delle somiglianze; l'elemento da tenere non è penalizzato.",
                    "Abitudini (18%): l'app impara quali categorie tendi a eliminare e quali a tenere.",
                    "Qualità (14%): vuote, sfocate, scure, a bassa risoluzione vengono prima.",
                    "Età (8%): pesa poco, perché la data non prova che qualcosa sia inutile.",
                    "Rischio (−35%): preferiti, contenuti importanti, foto nascoste e modificate scendono in fondo."
                ]),
                section("Le anteprime", points: [
                    "Dimensione in basso a sinistra, durata in basso a destra.",
                    "In alto a sinistra: stella, lucchetto (protetto), nuvola (solo su iCloud), stato della decisione.",
                    "Tocca un'anteprima per aprirla a tutto schermo."
                ]),
                section("La selezione", points: [
                    "Tocca o trascina il dito in orizzontale per selezionare più elementi, come nella galleria.",
                    "Seleziona tutto / Deseleziona tutto.",
                    "Da eliminare: propone le selezionate (le protette vengono saltate e il messaggio lo dice).",
                    "Conserva e Proteggi.",
                    "«Fine» esce dalla selezione."
                ], tip: "Le griglie molto lunghe mostrano 300 elementi alla volta: «Mostra altri» carica i successivi.")
            ],
            tutorialID: "explore",
            destination: .allPhotos
        ),
        GuideChapter(
            id: "preview",
            title: "Anteprima a tutto schermo e Dettagli",
            systemImage: "arrow.up.left.and.arrow.down.right",
            summary: "Guardare bene un elemento e conoscere tutto di lui.",
            sections: [
                section("Anteprima a tutto schermo", points: [
                    "Foto: ingrandisci con due dita o con il doppio tocco. Arriva prima un'anteprima e poi la versione nitida.",
                    "Video: lettore completo, con il pulsante della velocità.",
                    "Documenti: «Apri anteprima» con Quick Look.",
                    "Audio: forma d'onda (tocca un punto per spostarti) e riproduzione.",
                    "In basso, quando previsti: Da eliminare e Conserva. In alto: Chiudi e «i» per i Dettagli."
                ]),
                section("Foto sfocate e iCloud", [
                    "Con «Ottimizza spazio iPhone» sul telefono resta spesso solo un'anteprima. L'app scarica la versione nitida quando la rete lo permette e lo dice con un avviso: «Scarico la versione nitida», «Anteprima a bassa qualità · Scarica quella nitida» (tocca per scaricarla), «serve una connessione», «Riprova».",
                    "Nel confronto, a tutto schermo e nell'anteprima tenendo premuto, la foto che guardi arriva nitida anche con la rete cellulare, una alla volta e mai con Dati ridotti attivo."
                ]),
                section("I Dettagli", points: [
                    "Informazioni: tipo, nome, data, risoluzione, durata, pagine, origine e posizione.",
                    "Spazio: dimensione e spazio sull'iPhone; se l'originale è solo su iCloud lo dice; se iOS non fornisce la dimensione esatta il valore è una stima.",
                    "Analisi: stato dell'analisi, contenuto riconosciuto, nitidezza (anche nel dettaglio e del soggetto), volti, giudizio estetico, voto dello scatto, appartenenza a gruppi di duplicati o di simili, decisione presa.",
                    "Protezione: Proteggi questo elemento, Rimuovi la protezione, Sblocca solo questo elemento (per le protezioni automatiche), Ripristina la protezione automatica.",
                    "Strumenti: Comprimi questo video."
                ])
            ],
            tutorialID: "details",
            destination: .allPhotos
        ),
        GuideChapter(
            id: "search",
            title: "La ricerca intelligente",
            systemImage: "sparkle.magnifyingglass",
            summary: "Scrivi come parleresti: tutte le parole e le frasi che l'app capisce.",
            sections: [
                section("Come funziona", [
                    "Scrivi una richiesta e tocca Cerca. L'app la interpreta sul dispositivo e mostra «Come ho interpretato la richiesta» con un'etichetta per ogni filtro riconosciuto; poi «Mostra i risultati» apre la griglia. Capisce l'italiano e l'inglese.",
                    "Le ultime ricerche restano in «Ricerche recenti»; gli esempi sono un buon punto di partenza."
                ]),
                section("Tipi di contenuto", points: [
                    "foto, immagini, scatti · video, filmati · screenshot, schermate · registrazioni dello schermo",
                    "audio, registrazioni, memo vocali, note vocali · selfie · live photo · raffiche · panoramiche · ritratti · 4K · slow motion, rallentatore",
                    "PDF · Word, Excel, PowerPoint, Office · ZIP, RAR, archivi · documenti · file · iCloud Drive · download, scaricati · solo su iCloud, solo online"
                ]),
                section("Caratteristiche", points: [
                    "duplicati, doppioni, copie identiche · simili · sfocate, mosse · scure, buie",
                    "ricevute, scontrini, fatture · codici QR · biglietti · chat, conversazioni, messaggi · con testo",
                    "preferiti · già conservati · rimandati"
                ]),
                section("Dimensione, durata ed età", points: [
                    "più grandi di 100 MB, oltre 1 GB, più piccoli di 2 MB (KB, MB, GB, TB).",
                    "più lunghi di 10 minuti, meno di 30 secondi (secondi, minuti, ore).",
                    "più vecchi di un anno, da più di sei mesi (giorni, settimane, mesi, anni, anche in lettere fino a dieci)."
                ]),
                section("Periodi", points: [
                    "l'anno scorso, quest'anno, il mese scorso, questo mese.",
                    "recenti, ultimi 30 giorni, ultime due settimane.",
                    "un mese con l'anno facoltativo: «agosto 2024», «di gennaio»; un anno: «del 2023»."
                ]),
                section("Quantità, ordine e testo", points: [
                    "Numero di risultati: «i 20 video più pesanti», «le prime 50 foto».",
                    "Ordine: più pesanti, grandi, ingombranti · più vecchi · più recenti, ultimi · più lunghi.",
                    "Testo esatto tra virgolette: viene cercato nei nomi dei file, nel testo riconosciuto e nelle trascrizioni. Le parole non riconosciute diventano anch'esse ricerca testuale."
                ], tip: "Esempi: «screenshot più vecchi di un anno con testo», «i 20 video più pesanti girati nel 2024», «foto sfocate degli ultimi 6 mesi», «PDF oltre 10 MB», «registrazioni audio di gennaio».")
            ],
            tutorialID: "search",
            destination: .smartSearch
        ),
        GuideChapter(
            id: "modes",
            title: "Le modalità di pulizia",
            systemImage: "list.number",
            summary: "Rapida, guidata, avanzata, per obiettivo e annuale.",
            sections: [
                section("Pulizia rapida", [
                    "Dalla Home: lo swipe con un numero scelto di elementi (25, 50, 100 o 200), nell'ordine che fa recuperare più spazio con meno rischi."
                ]),
                section("Pulizia guidata", [
                    "Un percorso in sette passi, nell'ordine che preferisci. Ogni passo mostra quanti elementi ha da rivedere e un interruttore «Passo completato»."
                ], points: [
                    "1 · Screenshot: schermate vecchie, ricevute e conversazioni.",
                    "2 · Foto simili e duplicate: raffiche, scatti consecutivi e copie (solo le copie in più).",
                    "3 · Video: video grandi, registrazioni dello schermo e video duplicati.",
                    "4 · Documenti e download: file duplicati, pesanti e scaricati.",
                    "5 · Audio e registrazioni: registrazioni lunghe o ripetute.",
                    "6 · Altre app: apre l'Assistente app.",
                    "7 · iCloud: apre il Centro iCloud."
                ]),
                section("Pulizia avanzata", [
                    "Filtri combinati: tipo di contenuto (foto, video, PDF, Office, archivi, audio, altri documenti, file sconosciuti), origine (Libreria Foto, File locali, iCloud Drive, importati), periodo dal… al…, dimensione minima, durata minima, caratteristiche (screenshot, Live Photo, raffiche, selfie, con testo, registrazioni schermo, 4K, solo su iCloud, download) e stato (da rivedere, tutti, già conservati, rimandati). Il conteggio dei risultati si aggiorna mentre scegli."
                ]),
                section("Pulizia per obiettivo", [
                    "Scegli quanto spazio potenziale vuoi raggiungere (1, 2, 5, 10 o 20 GB): l'app propone gli elementi più promettenti e nello swipe mostra la barra di avanzamento verso l'obiettivo."
                ]),
                section("Pulizia annuale", [
                    "Dall'archivio storico: un anno alla volta, con «Pulizia annuale» seguito dall'anno."
                ]),
                section("Sessioni", [
                    "Ogni pulizia è una sessione salvata a ogni scelta: puoi chiuderla e riprenderla dalla Home. A fine sessione puoi rivedere subito i rimandati."
                ])
            ],
            tutorialID: "modes",
            destination: .guidedCleanup
        ),
        GuideChapter(
            id: "archive",
            title: "Archivio, viaggi e nostalgia",
            systemImage: "calendar",
            summary: "La libreria per anno, per viaggio e per ricorrenza.",
            sections: [
                section("Archivio storico", [
                    "Un elenco di anni con quanti elementi contengono, quanto spazio occupano e quanti sono ancora da rivedere. Dentro un anno trovi i mesi, «Tutti i contenuti» dell'anno e «Pulizia annuale» per rivederli con gli swipe.",
                    "L'età di un contenuto non è mai un motivo per eliminarlo: l'archivio serve a rivedere con calma."
                ]),
                section("Modalità viaggio", [
                    "Riconosce i periodi passati lontano dal luogo abituale, dalle posizioni salvate nelle foto: giorni, numero di elementi, spazio e distanza da casa. Tocca un viaggio per vederne i contenuti.",
                    "«Mostra il luogo» chiede il nome della città ad Apple: è l'unico caso in cui una posizione esce dal telefono, e solo su tua richiesta."
                ]),
                section("Modalità nostalgia", [
                    "Le foto scattate oggi negli anni passati. Serve soltanto a riguardarle: «Sfoglia tutto il …» apre l'intero anno."
                ])
            ],
            tutorialID: "archive",
            destination: .archive
        ),
        GuideChapter(
            id: "review",
            title: "Revisione ed eliminazione",
            systemImage: "checklist",
            summary: "La lista, la conferma, l'esito: l'unico punto da cui si elimina.",
            sections: [
                section("La lista", points: [
                    "Sezioni per tipo: Foto, Video, File e documenti, Audio, Copie importate in ClearSpace, con numero e spazio.",
                    "Freccia blu su un'anteprima: ripristina quell'elemento. «Ripristina gruppo»: tutta la sezione. «Annulla tutto» in alto: tutta la lista.",
                    "Tocca un'anteprima per guardarla. Lo scudo arancione segnala i contenuti potenzialmente importanti.",
                    "In alto l'esito dell'ultima operazione, con «Vedi il resoconto»."
                ]),
                section("Archivia prima", [
                    "Prima di eliminare puoi copiare i contenuti in un'altra posizione (un'unità esterna o un altro servizio cloud). Ogni copia viene confrontata con l'originale con l'impronta SHA-256: sono considerate riuscite solo quelle identiche. Puoi archiviare solo i contenuti potenzialmente importanti."
                ]),
                section("La conferma", points: [
                    "Cosa verrà eliminato: quante foto e video (andranno in Eliminati di recente per 30 giorni), quanti file (nel cestino dell'app File, se la posizione lo supporta), quante copie importate.",
                    "Spazio che si libererà: sull'iPhone e su iCloud, che non vanno sommati perché sono gli stessi contenuti visti da due posizioni.",
                    "Effetti su iCloud: con Foto di iCloud o iCloud Drive l'eliminazione vale anche su iCloud e sugli altri dispositivi; serve l'interruttore «Ho capito gli effetti su iCloud».",
                    "Contenuti importanti: serve «Li ho controllati».",
                    "File senza cestino: «Elimina definitivamente se il cestino non è disponibile», altrimenti restano in elenco.",
                    "Esclusi dall'operazione e Elenco completo.",
                    "«Elimina N elementi»: per foto e video iOS chiede un'ulteriore conferma."
                ]),
                section("L'esito", [
                    "Eliminati correttamente, operazioni non riuscite, in attesa ed esclusi, lo spazio recuperato e, se misurato, l'aumento dello spazio libero. Gli elementi non riusciti restano in lista per riprovare.",
                    "Lo spazio delle foto si libera davvero quando svuoti Eliminati di recente nell'app Foto: la sezione «Libera davvero lo spazio» spiega come e con «Apri l'app Foto» la apre. iOS non permette alle app di svuotare quell'album da sole."
                ], tip: "Prima di confermare, l'app ricontrolla ogni elemento: se nel frattempo è stato protetto o non è più nella lista, viene escluso.")
            ],
            tutorialID: "review",
            destination: .reviewTab
        ),
        GuideChapter(
            id: "results",
            title: "Risultati e promemoria",
            systemImage: "chart.bar",
            summary: "Cosa è stato davvero fatto e quanto spazio hai recuperato.",
            sections: [
                section("Attività e spazio", points: [
                    "Elementi esaminati, conservati, proposti, rimandati, eliminati e operazioni non riuscite.",
                    "Spazio effettivamente recuperato sull'iPhone e su iCloud: conta solo ciò che è stato davvero eliminato."
                ]),
                section("Libera davvero lo spazio", [
                    "Per 30 giorni dopo un'eliminazione di foto e video compare questo promemoria: gli elementi sono in Eliminati di recente e occupano ancora spazio. «Apri l'app Foto» la apre; lì scegli Eliminati di recente, Seleziona ed Elimina tutto. Quando l'hai fatto tocca «L'ho già svuotato» e poi «Aggiorna la misura»."
                ]),
                section("Confronto prima/dopo", [
                    "Spazio libero prima e dopo l'ultima operazione e adesso. Dopo la sincronizzazione con iCloud e lo svuotamento di Eliminati di recente il valore può cambiare: «Aggiorna la misura» lo rilegge."
                ]),
                section("Andamento e cronologia", [
                    "Il grafico mostra lo spazio liberato sull'iPhone mese per mese, quando ci sono operazioni in almeno due mesi. La cronologia elenca ogni operazione: tocca per vedere l'esito di ciascun elemento."
                ]),
                section("Promemoria", [
                    "Mai, ogni settimana, ogni mese o ogni tre mesi: una notifica ti invita a una nuova pulizia. Non avvia mai eliminazioni automatiche."
                ])
            ],
            tutorialID: "results",
            destination: .resultsTab
        ),
        GuideChapter(
            id: "documents",
            title: "Documenti e file",
            systemImage: "doc.on.doc",
            summary: "Cartelle autorizzate, categorie dei file e le tre operazioni.",
            sections: [
                section("Cartelle autorizzate", [
                    "ClearSpace analizza solo le cartelle che scegli con «Aggiungi una cartella»: iCloud Drive, Download, cartelle locali. Puoi revocare l'accesso in qualsiasi momento: i file non vengono toccati. Una cartella può essere protetta."
                ]),
                section("Le tre operazioni", points: [
                    "Liberare spazio sul dispositivo: per i file di iCloud Drive scaricati, rimuove solo la copia locale. Il file resta in iCloud Drive; quelli non ancora caricati online non vengono toccati.",
                    "Eliminare: come per le foto, solo dalla Revisione e con conferma.",
                    "Organizzare: sposta i file in sottocartelle per tipo o per anno, con anteprima prima di confermare. Nessun file viene eliminato."
                ]),
                section("Duplicati e versioni", [
                    "I file duplicati sono verificati sul contenuto (SHA-256). Le versioni dello stesso documento sono riconosciute dal testo quasi identico o da nomi simili: si confrontano come le foto simili."
                ])
            ],
            tutorialID: "documents",
            destination: .documents
        ),
        GuideChapter(
            id: "audio",
            title: "Audio e registrazioni",
            systemImage: "waveform",
            summary: "Importare, trascrivere e ritrovare le registrazioni.",
            sections: [
                section("Importare", [
                    "L'archivio di Memo Vocali non è accessibile alle altre app. Apri la registrazione in Memo Vocali, tocca Condividi e scegli ClearSpace, oppure salvala in File e usa «Importa file audio». Viene importata una copia: eliminarla non tocca l'originale."
                ]),
                section("Categorie", points: [
                    "Tutti gli audio, Registrazioni lunghe (oltre 10 minuti), Con silenzi lunghi (pause di almeno 5 secondi), Audio identici, Registrazioni simili."
                ]),
                section("Trascrizione e ricerca", [
                    "La trascrizione avviene solo sul dispositivo e rende la registrazione ricercabile. La lingua si sceglie in Impostazioni → Audio e deve essere disponibile offline. «Cerca nelle registrazioni» trova le parole nei nomi e nelle trascrizioni."
                ]),
                section("Una registrazione", [
                    "Forma d'onda e riproduzione, «Trascrivi sul dispositivo» (o «Trascrivi di nuovo»), «Proteggi questa registrazione», «Conserva» e «Aggiungi alla lista da eliminare»."
                ])
            ],
            tutorialID: "audio",
            destination: .audio
        ),
        GuideChapter(
            id: "compression",
            title: "Comprimere un video",
            systemImage: "film",
            summary: "Una copia più leggera, da confrontare con l'originale.",
            sections: [
                section("Come si fa", [
                    "Apri un video → «i» (Dettagli) → «Comprimi questo video». Scegli il profilo e tocca «Crea la versione compressa»: viene creata una copia temporanea, l'originale resta al suo posto."
                ], points: [
                    "1080p HEVC: buona qualità, adatta ai video 4K.",
                    "720p: più leggero, dettaglio ridotto.",
                    "Qualità media: massimo risparmio, qualità sensibilmente inferiore."
                ]),
                section("Dopo la compressione", [
                    "Guarda l'anteprima della copia e confrontala con l'originale. «Salva la versione compressa nella libreria» la salva e la verifica; poi puoi proporre l'originale per l'eliminazione (va in Revisione). «Scarta» la elimina senza toccare l'originale.",
                    "Se la copia non è più leggera viene scartata da sola; se è solo su iCloud, serve il download."
                ])
            ],
            tutorialID: "compression",
            destination: .allVideos
        ),
        GuideChapter(
            id: "icloud",
            title: "Centro iCloud e altre app",
            systemImage: "icloud",
            summary: "Cosa succede su iCloud e come liberare spazio nelle altre app.",
            sections: [
                section("Foto di iCloud", [
                    "iOS non dice alle app se Foto di iCloud è attivo: indicalo tu (Attivo, Disattivato o Non so). Serve a mostrare con precisione gli effetti di un'eliminazione; finché è sconosciuto lo spazio su iCloud è indicato come «fino a…»."
                ]),
                section("Quanto occupa", [
                    "Foto e video analizzati e originali presenti solo su iCloud. Il tuo piano iCloud (totale e usato) puoi inserirlo a mano: compare nella Home."
                ]),
                section("Le guide", points: [
                    "Eliminare una foto: con Foto di iCloud sparisce anche da iCloud e dagli altri dispositivi.",
                    "Liberare solo spazio sull'iPhone: «Ottimizza spazio iPhone» tiene gli originali su iCloud.",
                    "Eliminati di recente, Backup iCloud, Dati delle app in iCloud, Mail di iCloud."
                ]),
                section("Assistente app", [
                    "iOS isola i dati di ogni app: ClearSpace non può entrare in WhatsApp o in Netflix. Per ogni app trovi i passi da seguire e una checklist con le spunte: WhatsApp, Telegram, Netflix e streaming, Spotify (musica e podcast), Safari, Messaggi, App inutilizzate, Note Apple, Backup iCloud, Ottimizza spazio iPhone, Eliminati di recente, Dati delle app in iCloud, Mail di iCloud."
                ])
            ],
            tutorialID: "icloud",
            destination: .iCloudCenter
        ),
        GuideChapter(
            id: "protections",
            title: "Protezioni e sicurezza",
            systemImage: "lock.shield",
            summary: "Ciò che non deve mai essere proposto e le regole che proteggono i tuoi dati.",
            sections: [
                section("Protezioni automatiche", points: [
                    "Proteggi i preferiti.",
                    "Proteggi le foto nascoste.",
                    "Segnala i contenuti potenzialmente importanti: documenti, ricevute, codici e testi sensibili non sono bloccati, ma evidenziati e con conferma dedicata."
                ]),
                section("Album, cartelle e periodi", [
                    "In Impostazioni → Elementi protetti scegli gli album e le cartelle da proteggere, e aggiungi periodi (nome, dal… al…) come un viaggio o un evento: i loro contenuti non compaiono nelle sessioni. Un periodo si toglie scorrendolo verso sinistra."
                ]),
                section("Protezione di un singolo elemento", [
                    "Dai Dettagli: «Proteggi questo elemento» o «Rimuovi la protezione». Per sbloccare una protezione automatica solo per quell'elemento: «Sblocca solo questo elemento»; «Ripristina la protezione automatica» la rimette. Da una griglia: seleziona e tocca Proteggi."
                ]),
                section("Le regole di sicurezza", points: [
                    "Uno swipe o una selezione cambia solo lo stato di revisione.",
                    "Gli elementi protetti non entrano mai nella lista delle eliminazioni.",
                    "Si elimina solo ciò che compare in un piano mostrato e confermato.",
                    "Prima di eseguire, ogni elemento viene ricontrollato.",
                    "Dopo l'esecuzione si verifica l'esito e si registra solo ciò che è avvenuto davvero.",
                    "Nessuna analisi automatica può avviare un'eliminazione."
                ])
            ],
            tutorialID: "details",
            destination: .protections
        ),
        GuideChapter(
            id: "settings",
            title: "Le impostazioni",
            systemImage: "gearshape",
            summary: "Ogni opzione spiegata.",
            sections: [
                section("Analisi", points: [
                    "Scarica da iCloud solo con Wi‑Fi.",
                    "Consenti il download degli originali per le verifiche dei duplicati.",
                    "Pausa con batteria scarica o dispositivo caldo.",
                    "Includi le foto nascoste nell'analisi (restano protette)."
                ]),
                section("Foto simili", points: [
                    "Rigorosa: solo scatti quasi identici, fatti a pochi secondi di distanza. Gruppi più piccoli.",
                    "Normale (consigliata): scatti dello stesso soggetto fatti entro pochi minuti.",
                    "Ampia: anche inquadrature un po' diverse o scatti più distanti nel tempo. Gruppi più grandi.",
                    "Cambiandola parte un'analisi rapida che ricalcola i gruppi; decisioni e stelle restano."
                ]),
                section("Revisione", points: [
                    "Riproduci i video automaticamente (senza audio).",
                    "Foto nitide anche con la rete cellulare: nel confronto e a tutto schermo, una alla volta, mai con Dati ridotti."
                ]),
                section("Soglie, iCloud, sicurezza, audio", points: [
                    "Video considerati grandi: oltre 100, 250, 500 MB o 1 GB.",
                    "Elementi nella pulizia rapida: 25, 50, 100, 200.",
                    "Foto di iCloud: Attivo, Disattivato, Non so; scorciatoia al Centro iCloud.",
                    "Elementi protetti.",
                    "Lingua della trascrizione: italiano, inglese, spagnolo, francese, tedesco."
                ]),
                section("Piano e informazioni", [
                    "Il piano attuale e le funzioni di ciascun piano (in questa anteprima tutto è sbloccato). Informazioni su ClearSpace, novità, guida, tutorial, introduzione e invio di un commento tramite TestFlight."
                ])
            ],
            tutorialID: nil,
            destination: nil
        ),
        GuideChapter(
            id: "privacy",
            title: "Privacy",
            systemImage: "hand.raised",
            summary: "Cosa resta sul telefono (tutto) e cosa iOS permette.",
            sections: [
                section("Sul dispositivo", points: [
                    "Analisi di foto, video, documenti e audio, riconoscimento del testo, dei volti e la trascrizione avvengono sull'iPhone.",
                    "L'indice contiene solo riferimenti e metadati, mai copie dei file; è cifrato (AES-GCM, con la chiave nel Portachiavi) ed escluso dai backup.",
                    "Nessun account, nessuna pubblicità, nessun tracciamento, nessun server.",
                    "Unica eccezione, solo su tua richiesta: il nome di un luogo in Modalità viaggio, chiesto ad Apple."
                ]),
                section("Cosa permette iOS", [
                    "Il capitolo «Cosa può fare ClearSpace su iPhone» (Impostazioni → Informazioni) spiega per ogni tipo di contenuto cosa un'app può fare e cosa no: ad esempio le app non possono leggere i dati di WhatsApp o il totale del piano iCloud."
                ])
            ],
            tutorialID: nil,
            destination: nil
        ),
        GuideChapter(
            id: "faq",
            title: "Domande frequenti",
            systemImage: "questionmark.bubble",
            summary: "I dubbi più comuni e come risolverli.",
            sections: [
                section("Le foto restano sfocate", [
                    "È l'anteprima a bassa qualità di Foto di iCloud. Tocca «Scarica quella nitida», oppure apri il confronto o la foto a tutto schermo: lì arriva nitida anche in 4G. In Wi‑Fi succede da sola."
                ]),
                section("Perché «probabili» duplicati?", [
                    "Perché sono uguali solo nelle anteprime. Consenti il download degli originali nelle opzioni dell'analisi per verificarli e trasformarli in duplicati esatti."
                ]),
                section("Ho eliminato ma lo spazio non aumenta", [
                    "Le foto restano 30 giorni in Eliminati di recente: svuotalo nell'app Foto (in Risultati «Apri l'app Foto» ti ci porta). Con iCloud lo spazio si aggiorna dopo la sincronizzazione. In Risultati usa «Aggiorna la misura»."
                ]),
                section("I gruppi di foto simili sono troppo grandi o troppo piccoli", [
                    "Cambia la sensibilità in Impostazioni → Foto simili: «Rigorosa» unisce solo scatti quasi identici, «Ampia» anche quelli con piccole differenze. I gruppi si ricalcolano da soli con un'analisi rapida."
                ]),
                section("Un elemento non si può proporre", [
                    "È protetto (preferito, nascosto, in un album, cartella o periodo protetto, o protetto da te). Puoi sbloccarlo dai Dettagli."
                ]),
                section("Ho sbagliato una scelta", [
                    "Nello swipe tocca Annulla. Altrimenti ripristina l'elemento dalla Revisione: finché non confermi, nulla è perso."
                ]),
                section("Un video non parte", [
                    "Probabilmente è solo su iCloud: tocca «Riproduci comunque»."
                ]),
                section("L'analisi è lenta o in pausa", [
                    "Con batteria bassa, risparmio energetico o telefono caldo si mette in pausa da sola. Collega il caricatore o lasciala lavorare con l'app aperta."
                ]),
                section("Come segnalo un problema?", [
                    "Fai uno screenshot: TestFlight propone di inviarlo con una nota. Oppure Impostazioni → Invia un commento."
                ])
            ],
            tutorialID: nil,
            destination: nil
        ),
        GuideChapter(
            id: "shortcuts",
            title: "Tutti i gesti e le scorciatoie",
            systemImage: "hand.tap",
            summary: "Il riepilogo di ogni gesto dell'app.",
            sections: [
                section("Swipe", points: [
                    "Destra: conserva · Sinistra: proponi · Alto: dettagli · Basso: più tardi.",
                    "Due dita sulla carta: ingrandisci · Doppio tocco: tutto schermo.",
                    "Annulla: ultima mossa, anche su un gruppo intero."
                ]),
                section("Video", points: [
                    "Tocco: pausa · Altoparlante: audio · 1×/2×: velocità · Barra e fotogrammi: spostarsi."
                ]),
                section("Striscia dei simili", points: [
                    "Tocco: porta sulla carta · Tieni premuto: menu · Griglia · Confronta · Tieni la migliore · Tieni solo questa."
                ]),
                section("Galleria e griglie", points: [
                    "Tocco: seleziona · Trascina in orizzontale: selezione multipla (anche su più righe) · Parti da una selezionata: deseleziona · Tieni premuto: anteprima e menu.",
                    "Un gruppo dopo l'altro: Tieni solo la migliore = passa al gruppo successivo · Salta = lascialo da decidere · Avanti = prossimo gruppo già deciso."
                ]),
                section("Confronto", points: [
                    "Doppio tocco: zoom ×3 · Due dita: zoom libero · Trascina: sposta l'ingrandimento · Scorri in orizzontale: foto vicina · Riduci."
                ]),
                section("Altrove", points: [
                    "Revisione: freccia blu = ripristina · tocco su un'anteprima = guardala.",
                    "Elenchi: scorri verso sinistra un periodo protetto per toglierlo.",
                    "Screenshot ovunque: TestFlight propone di inviarlo come commento."
                ])
            ],
            tutorialID: nil,
            destination: nil
        )
    ]
}
