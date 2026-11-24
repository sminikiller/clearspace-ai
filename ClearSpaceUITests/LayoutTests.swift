import XCTest

/// Giro di tutte le schermate con il testo ingrandito (come con Accessibilità → Testo più grande)
/// e con il tema scuro, che il workflow imposta sul simulatore prima di questa prova.
///
/// Per ogni schermata salva un'immagine e segnala come errore i testi o i pulsanti che escono dai
/// bordi dello schermo. Sulle schermate principali controlla anche che i pulsanti essenziali si
/// possano raggiungere e non finiscano sotto le barre. Parte dopo `SmokeTests`, quindi trova la
/// libreria già analizzata, con foto simili e video di prova.
final class LayoutTests: UITestCase {

    override var launchArguments: [String] {
        ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
    }

    func testEveryScreenWithLargeText() throws {
        continueAfterFailure = true
        completeOnboardingIfNeeded()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 40), "L'app non si è aperta")
        pause(2)

        homeScreens()
        analyzeScreens()
        exploreScreens()
        // La galleria ha proposto le foto simili per l'eliminazione: la Revisione le mostra e poi le
        // ripristina, così tornano da decidere e lo swipe le presenta con la striscia dei simili.
        reviewScreens()
        startAndBatchScreens()
        swipeScreens()
        resultsScreens()
    }

    // MARK: - Da dove iniziare e tutti i gruppi

    /// Con le foto simili di nuovo da decidere: la riga «Foto simili» della Home e la schermata
    /// «Tutti i gruppi», con il testo grande. Nulla viene deciso.
    private func startAndBatchScreens() {
        app.tabBars.buttons["Home"].tap()
        pause(1)
        let row = app.descendants(matching: .any)["home.start.similarPhotos"]
        bringIntoView(row)
        guard row.exists, row.isHittable else {
            XCTFail("Home: «Foto simili» in «Da dove iniziare» non si raggiunge")
            return
        }
        checkLayout("L49b-home-da-dove-iniziare")
        row.tap()
        pause(1.5)
        let batch = app.descendants(matching: .any)["groups.batch"]
        bringIntoView(batch)
        guard batch.exists, batch.isHittable else {
            XCTFail("Gruppi: «Tieni la migliore in tutti i gruppi» non si raggiunge")
            goBack()
            scrollToTop()
            return
        }
        checkLayout("L49c-gruppi-dalla-home")
        batch.tap()
        if app.staticTexts["batch.summary"].waitForExistence(timeout: 10) {
            pause(1)
            checkLayout("L49d-tutti-i-gruppi")
            checkReachable(app.buttons["batch.delete"], "Tutti i gruppi: «Elimina»")
            checkReachable(app.buttons["batch.review"], "Tutti i gruppi: «Aggiungi alla Revisione»")
        } else {
            XCTFail("La schermata «Tutti i gruppi» non si è aperta")
        }
        goBack()
        goBack()
        scrollToTop()
    }

    // MARK: - Supporto

    /// Chiude un foglio o una schermata a tutto schermo con il pulsante previsto, oppure trascinandolo giù.
    private func closeTopScreen() {
        for label in ["Chiudi", "Fine", "Annulla"] {
            let button = app.navigationBars.buttons[label]
            if button.exists && button.isHittable {
                button.tap()
                pause(1)
                return
            }
        }
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        pause(1)
    }

    private func scrollToTop() {
        for _ in 0..<4 {
            scroll(by: -0.6)
        }
    }

    /// Apre la voce indicata, salva le schermate (anche scorrendo) e torna indietro.
    private func visit(startingWith prefix: String, name: String, scrolls: Int = 1) {
        let link = element(startingWith: prefix)
        bringIntoView(link)
        guard link.exists, link.isHittable else {
            XCTFail("Voce non raggiungibile: \(prefix)")
            return
        }
        let origin = currentTitle
        link.tap()
        pause(1.5)
        guard currentTitle != origin else {
            XCTFail("La schermata non si è aperta: \(prefix)")
            return
        }
        checkLayout(name)
        for index in 0..<scrolls {
            scroll(by: 0.45)
            checkLayout("\(name)-\(index + 2)")
        }
        goBack()
    }

    /// Il pulsante deve esistere, stare per intero nello schermo e poter essere toccato.
    private func checkReachable(_ element: XCUIElement, _ description: String) {
        guard element.waitForExistence(timeout: 3) else {
            XCTFail("\(description): non c'è")
            return
        }
        XCTAssertTrue(isFullyOnScreen(element), "\(description): esce dallo schermo o finisce sotto una barra")
        XCTAssertTrue(element.isHittable, "\(description): non si può toccare")
    }

    // MARK: - Home

    private func homeScreens() {
        app.tabBars.buttons["Home"].tap()
        pause(1)
        checkLayout("L01-home")
        let start = app.buttons["Avvia pulizia intelligente"]
        bringIntoView(start)
        XCTAssertTrue(start.exists && start.isHittable, "Home: «Avvia pulizia intelligente» non si raggiunge")
        checkLayout("L02-home-pulizia-rapida")
        scroll(by: 0.45)
        checkLayout("L03-home-modalita")
        scroll(by: 0.45)
        checkLayout("L04-home-categorie")

        let quick = app.buttons["Scegli quanti elementi rivedere"]
        bringIntoView(quick)
        if quick.exists && quick.isHittable {
            quick.tap()
            pause(1.2)
            checkLayout("L05-foglio-pulizia-rapida")
            closeTopScreen()
        } else {
            XCTFail("Home: «Scegli quanti elementi rivedere» non si raggiunge")
        }
        let goal = element(startingWith: "Pulizia per obiettivo")
        bringIntoView(goal)
        if goal.exists && goal.isHittable {
            goal.tap()
            pause(1.2)
            checkLayout("L06-foglio-obiettivo")
            closeTopScreen()
        } else {
            XCTFail("Home: «Pulizia per obiettivo» non si raggiunge")
        }

        visit(startingWith: "Pulizia guidata", name: "L07-pulizia-guidata", scrolls: 2)
        visit(startingWith: "Pulizia avanzata", name: "L08-pulizia-avanzata", scrolls: 2)
        visit(startingWith: "Pulizia annuale", name: "L09-pulizia-annuale", scrolls: 1)

        scrollToTop()
        let settings = app.navigationBars.buttons["Impostazioni"]
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            pause(1.2)
            checkLayout("L10-impostazioni")
            scroll(by: 0.45)
            checkLayout("L11-impostazioni-2")
            scroll(by: 0.45)
            checkLayout("L12-impostazioni-3")
            visit(startingWith: "Informazioni su ClearSpace", name: "L12b-informazioni", scrolls: 2)
            visit(startingWith: "Novità di questa versione", name: "L12c-novita", scrolls: 1)
            visit(startingWith: "Guida rapida", name: "L12d-guida-rapida", scrolls: 2)
            closeTopScreen()
        } else {
            XCTFail("Home: manca il pulsante Impostazioni")
        }
        guideScreens()
    }

    /// Guida completa, un capitolo, l'elenco dei tutorial e un tutorial, con il testo grande.
    private func guideScreens() {
        let card = app.descendants(matching: .any)["home.guide"]
        bringIntoView(card)
        guard card.exists, card.isHittable else {
            XCTFail("Home: la scheda Guida e tutorial non si raggiunge")
            return
        }
        card.tap()
        guard app.navigationBars["Guida e tutorial"].waitForExistence(timeout: 5) else {
            XCTFail("La guida non si è aperta")
            return
        }
        checkLayout("L17-guida")
        scroll(by: 0.45)
        checkLayout("L17b-guida-capitoli")
        visit(startingWith: "Come l'app sceglie la migliore", name: "L18-capitolo-consiglio", scrolls: 3)
        let tutorials = element(startingWith: "Tutti i tutorial")
        bringIntoView(tutorials)
        if tutorials.exists && tutorials.isHittable {
            tutorials.tap()
            pause(1)
            checkLayout("L19-tutorial")
            visit(startingWith: "Galleria e stelle", name: "L19b-tutorial-galleria", scrolls: 3)
            goBack()
        } else {
            XCTFail("Guida: «Tutti i tutorial» non si raggiunge")
        }
        goBack()
        scrollToTop()
    }



    // MARK: - Analizza

    private func analyzeScreens() {
        app.tabBars.buttons["Analizza"].tap()
        pause(1)
        checkLayout("L13-analizza")
        scroll(by: 0.45)
        checkLayout("L14-analizza-2")
        scroll(by: 0.45)
        checkLayout("L15-analizza-3")
        visit(startingWith: "Cosa può fare ClearSpace", name: "L16-cosa-permette-ios", scrolls: 1)
    }

    // MARK: - Esplora

    private func exploreScreens() {
        app.tabBars.buttons["Esplora"].tap()
        pause(1)
        checkLayout("L20-esplora")

        let photos = element(startingWith: "Foto")
        if photos.waitForExistence(timeout: 10) {
            photos.tap()
            pause(1)
            checkLayout("L21-categorie-foto")
            photoGrid()
            similarGroup()
            goBack()
        } else {
            XCTFail("Esplora: manca la sezione Foto")
        }

        let others: [(String, String)] = [
            ("Ricerca intelligente", "L30-ricerca"),
            ("Video", "L31-categorie-video"),
            ("Documenti e file", "L32-documenti"),
            ("Audio e registrazioni", "L33-audio"),
            ("Archivio storico", "L34-archivio"),
            ("Modalità viaggio", "L35-viaggio"),
            ("Modalità nostalgia", "L36-nostalgia"),
            ("Centro iCloud", "L37-centro-icloud"),
            ("Assistente app", "L38-assistente-app"),
            ("Già conservati", "L39-gia-conservati"),
            ("Elementi protetti", "L40-protetti")
        ]
        for (prefix, name) in others {
            visit(startingWith: prefix, name: name, scrolls: 1)
        }
    }

    /// Griglia di tutte le foto: anteprima a tutto schermo, selezione, una foto proposta per
    /// l'eliminazione (serve poi a mostrare Revisione e Conferma; non viene eliminata).
    private func photoGrid() {
        let all = element(startingWith: "Tutte le foto")
        guard all.waitForExistence(timeout: 5) else {
            XCTFail("Manca la categoria Tutte le foto")
            return
        }
        all.tap()
        _ = app.buttons["Rivedi con gli swipe"].waitForExistence(timeout: 20)
        checkLayout("L22-griglia-foto")

        if gridCell(0).exists {
            gridCell(0).tap()
            pause(2)
            checkLayout("L22b-anteprima-a-tutto-schermo")
            closeTopScreen()
        }

        let select = app.buttons["Seleziona"]
        if select.exists {
            select.tap()
            pause(0.5)
            if gridCell(1).exists {
                gridCell(1).tap()
            }
            checkLayout("L23-griglia-selezione")
            checkReachable(app.buttons["grid.delete"], "Griglia: «Elimina»")
            let mark = app.buttons["Aggiungi alla Revisione"]
            if mark.exists && mark.isHittable {
                mark.tap()
                pause(1)
            } else {
                XCTFail("Griglia: il pulsante «Revisione» non si raggiunge")
                let done = app.navigationBars.buttons["Fine"]
                if done.exists { done.tap() }
            }
        }
        goBack()
    }

    /// Gruppo di foto simili: galleria con selezione e confronto.
    private func similarGroup() {
        let similar = element(startingWith: "Foto simili")
        bringIntoView(similar)
        guard similar.exists, similar.isHittable else {
            XCTFail("Manca la categoria Foto simili")
            return
        }
        similar.tap()
        let row = element(containing: "potenziali")
        guard row.waitForExistence(timeout: 15) else {
            checkLayout("L24-nessun-gruppo")
            goBack()
            return
        }
        checkLayout("L24-gruppi-simili")

        // Un gruppo dopo l'altro: galleria con «Gruppo 1 di N» e «Salta» (o «Avanti») raggiungibile.
        let sequence = app.descendants(matching: .any)["groups.sequence"]
        bringIntoView(sequence)
        if sequence.exists && sequence.isHittable {
            sequence.tap()
            if app.staticTexts["grid.selectionCount"].waitForExistence(timeout: 10) {
                pause(1)
                checkLayout("L24b-gruppo-dopo-gruppo")
                checkReachable(sequenceNextButton, "Gruppo dopo gruppo: «Salta» o «Avanti»")
            } else {
                XCTFail("La revisione gruppo per gruppo non si è aperta")
            }
            goBack()
        } else {
            XCTFail("Gruppi: «Decidi un gruppo dopo l'altro» non si raggiunge")
        }
        // Con il testo grande la voce della sequenza spinge il primo gruppo in basso, sotto la barra
        // delle schede: un tocco lì finirebbe sulla barra. Lo si porta prima al centro dello schermo.
        bringIntoView(row)
        row.tap()
        if app.staticTexts["grid.selectionCount"].waitForExistence(timeout: 10) {
            pause(1)
            checkLayout("L25-galleria-gruppo")
            if gridCell(1).exists {
                dragAcrossGrid(from: 0, to: 1)
            }
            checkLayout("L26-galleria-selezione")
            checkReachable(app.buttons["group.delete"], "Galleria: «Elimina»")
            checkReachable(app.buttons["group.keepAll"], "Galleria: «Tieni tutte»")
            scroll(by: 0.45)
            checkLayout("L26b-galleria-scorsa")

            // Tutte le foto del gruppo vanno in revisione, senza eliminarle: più avanti vengono ripristinate.
            if chooseFromMenu("Segna tutte da eliminare") {
                checkLayout("L26c-galleria-tutte-da-eliminare")
                if chooseFromMenu("Aggiungi alla Revisione") {
                    pause(1)
                    checkLayout("L26d-galleria-proposte")
                }
            }
            let compare = app.buttons["Confronta"].firstMatch
            if compare.exists && compare.isHittable {
                compare.tap()
                if app.navigationBars["Confronto"].waitForExistence(timeout: 10) {
                    pause(2)
                    checkLayout("L27-confronto")
                    checkReachable(app.buttons["Tieni tutte"], "Confronto: «Tieni tutte»")
                    scroll(by: 0.3)
                    checkLayout("L27b-confronto-dettagli")
                    goBack()
                }
            } else {
                XCTFail("Galleria: «Confronta» non si raggiunge")
            }
            goBack()
        } else {
            XCTFail("La galleria del gruppo non si è aperta")
        }
        goBack()
    }

    // MARK: - Swipe

    /// Swipe sulle foto simili dalla pulizia guidata: carta, striscia con tutto il gruppo, pulsanti,
    /// griglia del gruppo e dettagli, tutto con il testo grande.
    private func swipeScreens() {
        app.tabBars.buttons["Home"].tap()
        pause(1)
        let guided = element(startingWith: "Pulizia guidata")
        bringIntoView(guided)
        guard guided.exists, guided.isHittable else {
            XCTFail("Home: «Pulizia guidata» non si raggiunge")
            return
        }
        guided.tap()
        guard app.navigationBars["Pulizia guidata"].waitForExistence(timeout: 10) else {
            XCTFail("La pulizia guidata non si è aperta")
            return
        }
        let swipe = app.buttons
            .matching(NSPredicate(format: "label == %@ AND enabled == true", "Rivedi con gli swipe"))
            .firstMatch
        // L'elenco crea le righe solo quando entrano nello schermo: con il testo grande il passo delle
        // foto simili sta più in basso, quindi lo si cerca scorrendo.
        _ = swipe.waitForExistence(timeout: 8)
        var attempts = 0
        while !swipe.exists && attempts < 8 {
            scroll(by: 0.4)
            attempts += 1
        }
        guard swipe.exists else {
            checkLayout("L41-guidata-senza-simili")
            XCTFail("La pulizia guidata non propone le foto simili da rivedere")
            goBack()
            return
        }
        bringIntoView(swipe)
        swipe.tap()
        guard app.buttons["Conserva"].waitForExistence(timeout: 20) else {
            XCTFail("La modalità swipe non si è aperta")
            return
        }
        pause(2.5)
        checkLayout("L41-swipe-foto-simili")
        for label in ["Elimina", "Più tardi", "Dettagli", "Conserva", "Griglia", "Confronta"] {
            checkReachable(app.buttons[label], "Swipe: «\(label)»")
        }
        let keepBest = element(startingWith: "Tieni la")
        if keepBest.exists {
            XCTAssertTrue(isFullyOnScreen(keepBest), "Swipe: «\(keepBest.label)» esce dallo schermo")
        }

        let grid = app.buttons["Griglia"]
        if grid.exists && grid.isHittable {
            grid.tap()
            pause(1.5)
            checkLayout("L42-swipe-griglia")
            closeTopScreen()
        }
        let compare = app.buttons["Confronta"]
        if compare.exists && compare.isHittable {
            compare.tap()
            pause(2)
            checkLayout("L43-swipe-confronto")
            closeTopScreen()
        }
        let details = app.buttons["Dettagli"]
        if details.exists && details.isHittable {
            details.tap()
            pause(1.2)
            checkLayout("L44-dettagli")
            scroll(by: 0.45)
            checkLayout("L44b-dettagli-2")
            closeTopScreen()
        }
        let close = app.buttons["Chiudi"].firstMatch
        if close.exists {
            close.tap()
            pause(1)
        }
        goBack()
    }

    // MARK: - Revisione e conferma

    private func reviewScreens() {
        // La Home ricorda ciò che aspetta la conferma e porta alla Revisione con un tocco.
        app.tabBars.buttons["Home"].tap()
        pause(1)
        let pending = app.descendants(matching: .any)["home.pendingReview"]
        bringIntoView(pending)
        if pending.exists && pending.isHittable {
            checkLayout("L49-home-pronto-da-liberare")
            pending.tap()
            pause(1)
        } else {
            XCTFail("Home: manca la scheda «Pronto da liberare» con gli elementi proposti")
        }
        app.tabBars.buttons["Revisione"].tap()
        pause(1.5)
        checkLayout("L50-revisione")
        let review = app.buttons["Controlla ed elimina"]
        bringIntoView(review)
        guard review.exists, review.isHittable else {
            XCTFail("Revisione: «Controlla ed elimina» non si raggiunge")
            return
        }
        review.tap()
        guard app.navigationBars["Conferma eliminazione"].waitForExistence(timeout: 30) else {
            XCTFail("La conferma non si è aperta")
            return
        }
        pause(1)
        checkLayout("L51-conferma")
        scroll(by: 0.45)
        checkLayout("L52-conferma-2")
        scroll(by: 0.45)
        checkLayout("L53-conferma-3")
        // Nulla viene eliminato: si chiude la conferma e si ripristina tutto.
        closeTopScreen()
        // Con il testo grande la barra in basso copre parte dell'elenco: il pulsante va portato in alto.
        let restore = app.buttons["Ripristina gruppo"].firstMatch
        bringToUpperHalf(restore)
        if restore.exists && restore.isHittable {
            restore.tap()
            pause(1.5)
            checkLayout("L54-revisione-ripristinata")
            XCTAssertTrue(
                element(containing: "Nessun elemento da eliminare").waitForExistence(timeout: 5),
                "Revisione: il ripristino del gruppo non ha svuotato l'elenco"
            )
        } else {
            XCTFail("Revisione: «Ripristina gruppo» non si raggiunge")
        }
        // Se un tocco ha aperto un altro pannello, lo si chiude prima di proseguire.
        if !app.tabBars.firstMatch.isHittable {
            closeTopScreen()
        }
    }

    // MARK: - Risultati

    private func resultsScreens() {
        app.tabBars.buttons["Risultati"].tap()
        pause(1.2)
        checkLayout("L60-risultati")
        scroll(by: 0.45)
        checkLayout("L61-risultati-2")
        scroll(by: 0.45)
        checkLayout("L62-risultati-3")
    }
}
