# ClearSpace AI

**Meno spazio occupato. Più controllo sui tuoi ricordi.**

Ideata e sviluppata da **Lorenzo Minichilli**.

App iOS nativa (Swift, SwiftUI) per la pulizia e l'organizzazione di iPhone e iCloud: foto, video, documenti, download, registrazioni audio, iCloud Drive e assistenza guidata per le altre app. Tutte le analisi avvengono sul dispositivo e nulla viene eliminato senza revisione e conferma.

---

## Stato del progetto: da leggere prima di tutto

Il codice è stato scritto su Windows, dove Xcode non esiste. Compilazione, test e prova d'uso avvengono su GitHub Actions, su un runner macOS con Xcode 26 e un simulatore di iPhone con iOS 26.

Verificato a ogni modifica del codice (ultimo esito: tutto superato):

- compilazione di app e test senza errori;
- test unitari sulla logica: regole di sicurezza, piano di eliminazione, sessioni e scelte di gruppo, ricerca, analisi, scelta dello scatto migliore, selezione nella griglia e stelle, pianificazione, formati;
- prova d'uso automatica sul simulatore, con una schermata salvata a ogni passo:
  - introduzione, permesso per Foto, analisi completa fino al termine, swipe e pulsanti, annullamento, dettagli, revisione, conferma, eliminazione reale di due foto di prova ed esito;
  - foto simili: il workflow aggiunge al simulatore tre scatti della stessa scena (nitido, sfocato, scuro) e l'app deve riconoscerli come gruppo e consigliare quello nitido; nello swipe deve comparire la striscia con tutti gli scatti, «Tieni la migliore» deve chiudere il gruppo e un solo annullamento deve ripristinarlo;
  - un gruppo dopo l'altro: dall'elenco dei gruppi si apre il primo gruppo da decidere con «Gruppo 1 di N» nel titolo; «Salta» porta al riepilogo finale e «Torna all'elenco» riporta indietro senza cambiare nulla;
  - griglia del gruppo: trascinando il dito sulla prima riga si selezionano le tre foto, i tocchi deselezionano, la stella resta sulla foto scelta e si ritrova in Esplora, «Tieni solo la tua migliore» chiude il gruppo; nel confronto i pulsanti stanno sopra il bordo inferiore e il contatore sotto la barra del titolo; nella griglia di una categoria «Seleziona» e un trascinamento selezionano tre elementi;
  - video: un video di prova deve riprodursi dentro la carta e mettersi in pausa con un tocco; con due riprese quasi uguali, toccando l'altra nella striscia deve passare sulla carta e partire, e «Tieni solo questo» deve chiudere il gruppo;
  - un giro di tutte le altre schermate;
  - un secondo giro di tutte le schermate con il testo ingrandito (Accessibilità, dimensione AX1) e il tema scuro: per ogni schermata si controlla in automatico che nessun testo o pulsante esca dallo schermo e che i pulsanti principali si possano raggiungere, e si salva un'immagine.

Cosa **non** è stato verificato:

- il comportamento su un iPhone reale e con una libreria grande: prestazioni, memoria, durata dell'analisi;
- il download delle anteprime nitide e dei video da iCloud: il simulatore non ha una libreria su iCloud, quindi quel percorso è scritto ma non provato;
- la valutazione dei volti (qualità, occhi chiusi, sorrisi): le foto di prova non contengono persone;
- le funzioni su file e cartelle (documenti, iCloud Drive, audio, compressione dei video): di queste schermate è verificato l'aspetto, non l'uso con contenuti veri.

Le soglie numeriche delle analisi (sfocatura, somiglianza, silenzi) sono punti di partenza ragionevoli e vanno tarate su librerie reali.

---

## Requisiti

- Mac con **Xcode 16 o successivo** (il progetto usa le cartelle sincronizzate di Xcode 16).
- iOS 17 o successivo sul dispositivo o sul simulatore.
- Un account Apple per firmare l'app; per TestFlight e App Store serve l'iscrizione all'Apple Developer Program.

## Come compilare

1. Apri `ClearSpace.xcodeproj`.
2. Nel target **ClearSpace**, scheda *Signing & Capabilities*, scegli il tuo team. L'identificativo dell'app è `com.sminikiller.clearspace`, già registrato nell'account sviluppatore.
3. Seleziona un simulatore o un iPhone e premi Esegui.

Se Xcode non riuscisse ad aprire il progetto, puoi rigenerarlo con [XcodeGen](https://github.com/yonaskolb/XcodeGen) a partire da `project.yml`:

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

### Senza un Mac: GitHub Actions

Il repository contiene due workflow, che girano su runner macOS di GitHub.

| Workflow | Quando parte | Cosa fa |
| --- | --- | --- |
| `iOS build` | a ogni push su `main` e sulle pull request che toccano il codice, oppure a mano | compila app e test per il simulatore, esegue i test unitari e la prova d'uso automatica |
| `TestFlight` | solo a mano | crea l'archivio di distribuzione, lo firma e lo carica su App Store Connect |

Nel riepilogo di ogni esecuzione compaiono solo errori e risultati; i log completi di `xcodebuild` e le schermate della prova d'uso sono allegati come artefatto `risultati`. Le modifiche ai soli file `.md` non avviano la compilazione. Nei repository privati i minuti macOS di GitHub sono limitati e contano dieci volte: se si esauriscono, rendere pubblico il repository li rende gratuiti.

La prova d'uso (`ClearSpaceUITests/SmokeTests.swift`) usa l'app sul simulatore come farebbe una persona: completa l'introduzione, concede l'accesso a Foto, attende la fine dell'analisi, rivede le foto con gli swipe e con i pulsanti, annulla una scelta, apre i dettagli, passa dalla Revisione alla conferma, elimina davvero due foto di prova (compreso l'avviso di sistema di iOS) e controlla l'esito, compreso l'aiuto per svuotare Eliminati di recente. Un secondo giro apre le altre schermate. Ogni passo salva una schermata.

### TestFlight

Configurazione attuale (già fatta per questo repository):

| Dato | Dove sta | Valore |
| --- | --- | --- |
| Identificativo dell'app | variabile `APP_BUNDLE_ID` | `com.sminikiller.clearspace`, registrato in *Certificates, Identifiers & Profiles* |
| Team | variabile `APPLE_TEAM_ID` | ID del team sviluppatore |
| App in App Store Connect | — | «ClearSpace AI», iOS, lingua principale italiano, SKU `clearspace-ai` |
| Chiave API | variabili `ASC_KEY_ID`, `ASC_ISSUER_ID` | chiave del team «GitHub Actions ClearSpace», ruolo Amministrazione |
| Chiave privata | segreto `ASC_PRIVATE_KEY` | contenuto del file `.p8`, scaricabile una sola volta |

Gli ID non sono segreti e stanno tra le variabili. L'unico segreto è il file `.p8`: va caricato dal titolare dell'account, senza copiarlo in file o messaggi.

```powershell
Get-Content -Raw "$env:USERPROFILE\Downloads\AuthKey_XXXXXXXXXX.p8" | gh secret set ASC_PRIVATE_KEY
```

**Avvio.** Scheda *Actions → TestFlight → Run workflow*, oppure:

```powershell
gh workflow run TestFlight
```

**Dopo il caricamento.** Apple elabora la build in qualche minuto, poi la rende disponibile da sola al gruppo di tester interni «Interni» (distribuzione automatica attiva). Chi è nel gruppo la installa dall'app TestFlight, con lo stesso Apple ID. I tester interni sono utenti del team in App Store Connect: per aggiungerne uno va prima inserito in *Utenti e accessi*, poi nel gruppo.

**Conformità all'esportazione.** `Config/Info.plist` dichiara `ITSAppUsesNonExemptEncryption = NO`: l'app usa soltanto la crittografia del sistema operativo (CryptoKit). Così App Store Connect non chiede più la dichiarazione a ogni build. Se un giorno l'app adottasse algoritmi propri o librerie crittografiche di terze parti, questa dichiarazione andrebbe rivista.

Tutto questo riguarda solo TestFlight: nulla arriva sull'App Store finché una versione non viene inviata alla revisione.

La firma usa i certificati gestiti da Apple ("cloud signing"): non servono file `.p12` né profili da caricare, ma la chiave API deve avere il ruolo Amministrazione. Il numero di build è il numero progressivo dell'esecuzione del workflow.

Per rifare la configurazione da zero su un altro account: registra un identificativo, crea l'app in App Store Connect, genera una chiave API del team in *Utenti e accessi → Integrazioni → API di App Store Connect* e imposta le quattro variabili con `gh variable set NOME --body "valore"`.

---

## Struttura

```
ClearSpace.xcodeproj/        progetto Xcode
Config/Info.plist            permessi, attività in background, tipi di documento
Config/ExportOptions.plist   opzioni di esportazione per App Store Connect
.github/workflows/           compilazione, test e caricamento su TestFlight
project.yml                  definizione XcodeGen di riserva
ClearSpace/
  App/                       punto d'ingresso
  Application/               ambiente dell'app, scansione, sessioni, motore di sicurezza
  Core/                      modelli e logica pura (solo Foundation, testabile)
  Storage/                   indice locale cifrato, preferenze, storico
  Services/                  Foto, file, audio, video, sistema, piani
  UI/                        schermate SwiftUI
  Resources/                 icona, colore principale, manifest della privacy
ClearSpaceTests/             test unitari sulla logica
ClearSpaceUITests/           prova d'uso automatica sul simulatore
```

95 file Swift per l'app (circa 24.300 righe), 9 file di test unitari e 3 per la prova d'uso e il giro con il testo grande.

## Architettura

| Strato | Contenuto |
| --- | --- |
| Presentazione | SwiftUI: Home, Analizza, Esplora, Revisione, Risultati, modalità swipe |
| Servizi applicativi | `SessionManager`, `ScanCoordinator`, `CleanupPlanner` |
| Foto | `PhotoLibraryService`, `PhotoIndexer`, `PhotoAnalysisPipeline` (PhotoKit) |
| File | `FolderAccessService`, `FileIndexer`, `FileAnalysisPipeline`, `FileOperationService` |
| Motore di analisi | `ImageAnalyzer` (Vision, OCR), `ShotAnalyzer` (volti, occhi, nitidezza del soggetto), `TextSimilarity`, `QualityRanker`, `RecoverabilityScorer` |
| Sicurezza | `SafetyEngine`, `SafetyRules`, `PlanBuilder`, `ProtectionEvaluator` |
| Dati locali | `IndexStore`, `HistoryStore`, `PreferencesStore`, `SecureFileStore` |

### Il flusso di eliminazione

1. **Selezione.** Uno swipe a sinistra (o il pulsante equivalente) cambia soltanto lo stato dell'elemento in "in attesa di eliminazione". Nessun file viene toccato.
2. **Revisione.** La scheda Revisione mostra tutto ciò che è stato selezionato; si può ripristinare un elemento, un gruppo o tutto.
3. **Conferma.** `PlanBuilder` prepara l'elenco con gli effetti distinti su iPhone e iCloud. L'utente deve confermare, e dichiarare di aver compreso gli effetti su iCloud e di aver controllato i contenuti sensibili quando presenti.
4. **Esecuzione.** Solo `SafetyEngine.execute` può eliminare, e solo con una conferma valida per quel piano. Ricontrolla ogni elemento, esegue, verifica l'esito e registra ciò che è realmente avvenuto: eliminato, non riuscito o in attesa.
5. **Eliminati di recente.** Foto e video vanno in Eliminati di recente e occupano spazio per altri 30 giorni. iOS non permette alle app di svuotare quell'album: l'esito e, per 30 giorni, la scheda Risultati spiegano come farlo e aprono l'app Foto.

Finché qualcosa aspetta la conferma, la Home mostra la scheda «Pronto da liberare» con il numero di elementi, lo spazio e il collegamento alla Revisione.

Gli elementi protetti (preferiti, foto nascoste, album, cartelle e periodi scelti, elementi protetti singolarmente) non possono entrare nella lista delle eliminazioni.

### Foto simili e scelta dello scatto migliore

Quando una foto ha degli scatti simili, l'app li mostra tutti: nella modalità swipe compare una striscia con l'intero gruppo, la griglia li mette tutti insieme in miniatura e il confronto li apre in grande uno dopo l'altro.

- **Griglia con selezione rapida.** Come nell'app Foto: un tocco seleziona, trascinando il dito in orizzontale si selezionano tutte le anteprime toccate (anche su più righe, con lo scorrimento automatico vicino ai bordi), partendo da una già selezionata si deseleziona. Tenendo premuta un'anteprima la si vede in grande. Scelte rapide: tutte, tutte tranne le migliori, nessuna. La stessa selezione a trascinamento c'è nelle griglie delle categorie, dopo «Seleziona».
- **Le tue migliori.** Si possono segnare una o più foto con una stella: restano conservate e la stella si vede ovunque (striscia, carta, confronto, griglie). Le stelle prevalgono sul consiglio dell'app: «Tieni solo le tue migliori» conserva quelle con la stella e propone le altre. Il consiglio dell'app è indicato a parte, con le scintille.

- **Raggruppamento.** Raffiche (riconosciute da iOS) e scatti ravvicinati nel tempo, confrontati con le impronte visive di Vision. Se Vision non riesce a produrre l'impronta si ripiega sull'hash percettivo delle anteprime.
- **Criteri.** Per ogni membro di un gruppo `ShotAnalyzer` misura: nitidezza dell'intera immagine, nitidezza del soggetto (il volto più grande, altrimenti il centro), qualità dei volti secondo Vision, occhi chiusi e sorrisi, giudizio estetico dove iOS lo mette a disposizione. A questi si aggiungono esposizione e risoluzione.
- **Confronto corretto.** Un criterio viene usato solo se è disponibile per tutti gli scatti del gruppo: non si paragonano numeri calcolati in modo diverso. Preferiti e foto modificate prevalgono sempre, perché sono scelte già fatte dall'utente.
- **Spiegazione.** Il consiglio arriva con il motivo («ha gli occhi aperti e il soggetto più a fuoco») e ogni scatto ha un voto da 0 a 100. Nel confronto lo zoom è condiviso: ingrandito un punto, si passa da una foto all'altra restando lì.
- **Scelta.** «Tieni solo la migliore», «Tieni solo questa» oppure «Tieni tutte». Gli scatti scartati passano alla Revisione come ogni altra scelta, e la mossa si annulla con un solo gesto.
- **Un gruppo dopo l'altro.** Dalla Home («Scegli le foto migliori») o in cima all'elenco dei gruppi si aprono i gruppi da decidere uno dopo l'altro, a partire da quello che libera più spazio: «Gruppo 3 di 12» nel titolo, la galleria del gruppo e, dopo «Tieni solo la migliore» o «Tieni tutte», il gruppo successivo. «Salta» lo lascia da decidere; alla fine un riepilogo porta alla Revisione. Nell'elenco i gruppi già decisi vanno in fondo con l'etichetta «Deciso». La logica (cosa è deciso, ordine, gruppi spariti) è in `Core/Logic/GroupReview.swift`.
- **Sensibilità.** In Impostazioni → Foto simili si sceglie quanto devono somigliarsi due scatti: Rigorosa, Normale o Ampia cambiano insieme distanza tra impronte visive, finestra di tempo e distanza delle impronte percettive. Cambiandola, l'app azzera il controllo di somiglianza delle foto e ricalcola i gruppi con un'analisi rapida; decisioni e stelle restano.
- **Uno per uno.** Vale per le foto e per i video simili: un tocco su un'anteprima della striscia porta quell'elemento sulla carta, dove lo si guarda (un video parte subito) e lo si decide con i soliti gesti. Si può tornare anche su un elemento già deciso e cambiare idea. Tenendo premuta un'anteprima lo si conserva o scarta senza spostarsi.

### Anteprime nitide e video

- Con Foto di iCloud e «Ottimizza spazio iPhone» sul dispositivo resta spesso solo un'anteprima a bassa qualità. L'app mostra subito quella e poi la versione nitida, scaricandola da iCloud se la rete lo consente (rispettando «solo con Wi‑Fi»). Se il download non è consentito lo dice e offre di scaricarla comunque: non resta mai una foto sfocata senza spiegazione.
- Nel confronto, a tutto schermo e nell'anteprima tenendo premuto, la foto che si sta esaminando arriva nitida anche con la rete cellulare: una alla volta, mai con Dati ridotti attivo, e si può spegnere nelle Impostazioni.
- I video si riproducono dentro la carta, senza audio finché non lo si attiva: un tocco mette in pausa, la barra permette di spostarsi, i fotogrammi in basso mostrano i momenti principali, c'è la velocità doppia.
- Le immagini delle carte successive vengono preparate in anticipo.

### Guida completa e tutorial

- **Guida completa** (Home → Guida e tutorial, oppure Impostazioni): 27 capitoli, uno per strumento o argomento, con la ricerca nel testo: primi passi, Home, analisi e riconoscimento, swipe, video, striscia dei simili, come viene scelta la foto migliore (criteri e pesi), galleria, confronto, stelle e preferiti, tutte le categorie (generate dall'elenco reale delle categorie, con la regola di ciascuna), griglie e ordine «Consigliati», anteprima e dettagli, ricerca intelligente con tutte le parole riconosciute, modalità di pulizia, archivio, viaggi e nostalgia, revisione e conferma, risultati e promemoria, documenti, audio, compressione dei video, iCloud e altre app, protezioni e regole di sicurezza, impostazioni, privacy, domande frequenti e riepilogo dei gesti. Il contenuto è in `Core/Content/GuideContent.swift`.
- **Tutorial**: uno per strumento (17), con preparazione, pulsante per aprire lo strumento ed esercizi. Gli esercizi legati a un'azione si spuntano da soli quando l'utente la compie davvero (l'app registra l'azione con `AppEnvironment.recordTutorial`); gli altri si segnano a mano. I progressi sono salvati sul dispositivo e si possono azzerare. Il contenuto è in `Core/Content/TutorialContent.swift`; un test controlla che ogni azione registrata appartenga a un esercizio e che ogni categoria sia spiegata nella guida.

### Informazioni, novità e guida

- **Informazioni** (Impostazioni → Informazioni su ClearSpace): autore e crediti, tecnologie usate, impegni sulla privacy, versione.
- **Novità**: l'elenco dei cambiamenti della versione compare da solo una volta dopo ogni aggiornamento (mai al primo avvio, che ha già l'introduzione) e resta consultabile dalle Impostazioni.
- **Guida rapida**: gesti dello swipe, foto simili, griglia con selezione rapida, stelle, revisione, foto sfocate.
- **Commenti**: un pulsante apre TestFlight, da cui i tester inviano note e schermate.
- **Rivedi l'introduzione**: la ripropone senza far ripartire l'analisi.

### Testo grande e tema scuro

Le schermate che scorrono seguono la dimensione del testo scelta in iOS. Quelle che non possono scorrere (swipe, confronto, barre di comandi) limitano il testo dei controlli a una dimensione che entra sempre; le file di pulsanti e le schede si mettono una sotto l'altra quando non stanno affiancate, le etichette vanno a capo invece di essere tagliate, i selettori a segmenti diventano menu.

### La scansione progressiva

| Fase | Cosa fa |
| --- | --- |
| A, metadati | Date, tipi, dimensioni. Non scarica nulla. Incrementale: riusa i dati degli elementi non modificati. |
| B, anteprime | Nitidezza, luminosità, hash percettivo, testo degli screenshot, foto simili, probabili duplicati, scelta dello scatto migliore nei gruppi. |
| C, approfondita | Hash SHA-256 degli originali, solo per i candidati; versioni dei documenti; audio. |
| D, raccomandazioni | Riepilogo, priorità di revisione, spazio potenziale. |
| E, esecuzione | Solo dalla Revisione, dopo la conferma. |

La scansione si può mettere in pausa, si sospende da sola con batteria scarica o dispositivo caldo e non scarica originali da iCloud senza consenso.

Le analisi pesanti (anteprime, impronte visive dei gruppi, misure degli scatti simili) esaminano più elementi insieme, su un massimo di quattro processori, e chiedono a PhotoKit gli asset a blocchi invece che uno per uno. Durante l'analisi l'indice completo si salva al massimo ogni 10 secondi e il riepilogo si ricalcola al massimo una volta al secondo; le decisioni dell'utente hanno un file a parte, salvato subito.

---

## Corrispondenza con la specifica

| Sezione della specifica | Dove si trova |
| --- | --- |
| 1. Cosa permette iOS | `UI/Settings/PlanAndInfoViews.swift` (`CapabilitiesInfoView`) |
| 2. Dashboard | `UI/Home/HomeView.swift` |
| 3. Pulizia con gli swipe | `UI/Swipe/`, `Application/SessionManager.swift` |
| 4. Categorie di foto, confronto intelligente | `Core/Logic/SmartCollection.swift`, `UI/Explore/GroupViews.swift`, `Core/Logic/QualityRanker.swift` |
| 5. Video e compressione | `Services/Video/VideoCompressionService.swift`, `UI/Videos/VideoCompressionView.swift` |
| 6. Documenti, duplicati, tre operazioni | `Services/Files/`, `UI/Documents/` |
| 7. Centro iCloud | `UI/ICloud/ICloudCenterView.swift` |
| 8. Audio e registrazioni | `Services/Audio/`, `UI/Audio/AudioHubView.swift` |
| 9. Assistente app | `Core/Content/AppGuides.swift`, `UI/Apps/AppAssistantView.swift` |
| 10. ClearSpace Brain | `Services/Photos/`, `Core/Logic/` (ricerca, punteggio, raccomandazioni) |
| 11. Tre modalità di pulizia | `UI/Modes/CleanupModesViews.swift`, `Core/Logic/CleanupPlanner.swift` |
| 12. Funzioni aggiuntive | sessioni salvate, protezioni, viaggio, nostalgia, obiettivo, promemoria, pulizia annuale |
| 13. Sicurezza e privacy | `Application/SafetyEngine.swift`, `Core/Models/CleanupReport.swift`, `Storage/SecureFileStore.swift` |
| 14. Architettura | questa struttura; `Core/Models/IndexedItem.swift` |
| 16. Criteri di qualità | `ClearSpaceTests/` |
| 17. Modello commerciale | `Services/Store/PlanManager.swift` |

---

## Scelte tecniche da conoscere

- **Dimensione delle foto.** PhotoKit non offre un'API pubblica per la dimensione su disco di un asset né per sapere se l'originale è sul dispositivo. `PhotoResourceInspector` legge questi valori dalle risorse con KVC (`fileSize`, `locallyAvailable`) in modo difensivo; se non sono disponibili ripiega su una stima, che nell'interfaccia è indicata come tale. È una pratica diffusa ma non documentata: va valutata prima della pubblicazione.
- **Stato di Foto di iCloud.** iOS non lo comunica alle app. Lo indica l'utente; viene dedotto da solo quando si trova un originale presente solo online. Finché è sconosciuto, lo spazio su iCloud è riportato come "fino a…".
- **Totale del piano iCloud.** Non è leggibile da un'app. La dashboard mostra ciò che l'app ha rilevato, oppure i valori inseriti a mano, con la dicitura "inserito da te".
- **Liberare spazio senza eliminare.** Per le foto esiste solo "Ottimizza spazio iPhone" di iOS, a cui l'app rimanda. Per i file di iCloud Drive l'app può rimuovere la sola copia locale.
- **Duplicati.** "Esatto" significa hash SHA-256 identico sull'originale. Il confronto delle sole anteprime produce "probabili duplicati" e non viene mai presentato come certezza.
- **Dati locali.** L'indice contiene solo riferimenti e metadati, è cifrato con AES-GCM (chiave nel Portachiavi) ed è escluso dai backup. Le decisioni sono salvate a parte, a ogni scelta, e associate all'identificativo stabile dell'elemento: sopravvivono anche alla ricostruzione dell'indice.
- **Altre app.** iOS isola i dati di ogni app: per WhatsApp, Telegram, Safari e le altre ClearSpace offre procedure guidate e una checklist, non accessi diretti.
- **Memo Vocali.** L'archivio non è accessibile. L'app è registrata per aprire file audio: da Memo Vocali si usa Condividi e si sceglie ClearSpace. Viene importata una copia.
- **Piani.** `AppConfiguration.monetizationEnabled` è `false`: tutte le funzioni sono sbloccate e StoreKit non viene interrogato. Va attivato dopo aver creato i prodotti in App Store Connect. Le funzioni di sicurezza non dipendono mai dal piano.
- **Ricerca in linguaggio naturale.** È basata su regole, in italiano e in inglese, eseguite sul dispositivo. La ricerca testuale copre nomi dei file, testo riconosciuto e trascrizioni.

## Non incluso

- Sincronizzazione delle preferenze con CloudKit (la specifica la indica come eventuale).
- Applicazione complementare per Mac.
- Estensione di condivisione dedicata: l'importazione avviene con "Apri in ClearSpace" e con il selettore di file.
- Raggruppamento delle foto per dispositivo di scatto (richiede la lettura dei metadati EXIF degli originali).
- Prodotti StoreKit configurati e localizzazione in altre lingue: l'interfaccia è in italiano.

## Test

`ClearSpaceTests` contiene oltre 130 test sulla logica pura: regole di sicurezza e conferma, piano di eliminazione, sessioni e annullamento, ricerca in linguaggio naturale, confronto dei testi, misure sulle immagini, punteggio di recuperabilità, pianificazione delle code, riepilogo e rilevamento dei viaggi, revisione gruppo per gruppo, sensibilità delle foto simili, promemoria di Eliminati di recente e calcolo in parallelo.

Si eseguono da Xcode con Prodotto → Test, oppure con il workflow di GitHub.

## Prima della pubblicazione

- Compilare, correggere gli errori ed eseguire i test.
- Provare con librerie di decine di migliaia di elementi, con Foto di iCloud in modalità ottimizzata, con file solo online e con raccolte condivise.
- Tarare le soglie in `Core/Support/AppConfiguration.swift`.
- Verificare il manifest della privacy (`Resources/PrivacyInfo.xcprivacy`) e compilare la scheda privacy su App Store Connect.
- Sostituire l'icona provvisoria.
