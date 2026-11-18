import XCTest

/// Prova d'uso sul simulatore: percorre i flussi principali dell'app come farebbe una persona
/// e salva una schermata a ogni passo. Serve a verificare che l'app funzioni davvero,
/// non soltanto che compili. Gli strumenti comuni sono in `UITestCase`.
final class SmokeTests: UITestCase {

    // MARK: - Foto simili e video

    /// Foto simili, scelta dello scatto migliore e video nella carta. Usa i contenuti di prova che il
    /// workflow aggiunge al simulatore: tre scatti della stessa scena (nitido, sfocato, scuro) e un video.
    /// Il nome fa partire questa prova per prima: le foto simili devono essere ancora tutte presenti.
    /// Alla fine tutto viene conservato, così la prova successiva ritrova la libreria come se l'aspetta.
    func testA_SimilarShotsAndVideo() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["SEEDED_MEDIA"] == "1", "Sul simulatore non ci sono i contenuti di prova")
        continueAfterFailure = true

        completeOnboardingIfNeeded()
        XCTAssertTrue(app.buttons["Avvia pulizia intelligente"].waitForExistence(timeout: 40), "La Home non è comparsa")
        app.tabBars.buttons["Analizza"].tap()
        XCTAssertTrue(analysisCompleted.waitForExistence(timeout: 300), "L'analisi non è terminata")

        // Pulizia guidata → foto simili: nello swipe devono comparire tutti gli scatti del gruppo
        app.tabBars.buttons["Home"].tap()
        pause(1)
        reviewSimilarShotsInSwipe()

        // Esplora → Foto → Foto simili → primo gruppo
        app.tabBars.buttons["Esplora"].tap()
        pause(1)
        let photos = element(startingWith: "Foto")
        XCTAssertTrue(photos.waitForExistence(timeout: 10), "Manca la sezione Foto")
        photos.tap()
        pause(1)
        let similar = element(startingWith: "Foto simili")
        bringIntoView(similar)
        guard similar.exists else {
            XCTFail("Manca la categoria Foto simili")
            return
        }
        similar.tap()
        let groupRow = element(containing: "potenziali")
        guard groupRow.waitForExistence(timeout: 20) else {
            capture("40-nessun-gruppo")
            XCTFail("Le tre foto di prova non sono state riconosciute come simili")
            return
        }
        capture("40-foto-simili")
        groupRow.tap()

        // Galleria del gruppo: tutte le anteprime insieme, con la stella messa durante lo swipe
        let counter = app.staticTexts["grid.selectionCount"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "La galleria del gruppo non si è aperta")
        XCTAssertTrue(
            element(containing: "la tua migliore").waitForExistence(timeout: 5),
            "La stella messa nello swipe non si ritrova nella galleria"
        )
        pause(2)
        capture("40b-galleria-del-gruppo")

        // Confronto: tutte le foto del gruppo, lo scatto consigliato e il motivo
        let compare = app.buttons["Confronta"].firstMatch
        XCTAssertTrue(compare.waitForExistence(timeout: 5), "Nella galleria manca il pulsante Confronta")
        compare.tap()
        XCTAssertTrue(app.navigationBars["Confronto"].waitForExistence(timeout: 10), "Il confronto non si è aperto")
        XCTAssertTrue(
            element(startingWith: "Conserva la foto").waitForExistence(timeout: 30),
            "Manca l'indicazione dello scatto consigliato"
        )
        pause(3)
        capture("41-confronto")
        checkComparisonLayout()

        // Zoom condiviso: si ingrandisce una foto e si passa a un'altra restando sullo stesso punto
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).doubleTap()
        pause(1.5)
        capture("42-confronto-zoom")
        let second = element(startingWith: "Foto 2")
        if second.waitForExistence(timeout: 5) {
            second.tap()
            pause(2)
            capture("43-confronto-zoom-altra-foto")
        }
        let third = element(startingWith: "Foto 3")
        if third.exists {
            third.tap()
            pause(2)
            capture("44-confronto-zoom-terza-foto")
        }

        // Tieni solo la tua migliore (quella con la stella): le altre passano alla revisione,
        // nulla viene eliminato
        let keepBest = app.buttons["Tieni solo la tua migliore"]
        XCTAssertTrue(keepBest.waitForExistence(timeout: 5), "Manca il pulsante per tenere la foto con la stella")
        keepBest.tap()
        XCTAssertTrue(
            element(containing: "alla revisione").waitForExistence(timeout: 6),
            "La scelta sul gruppo non è stata registrata"
        )
        capture("45-migliore-tenuta")

        // Si rimette tutto com'era: le tre foto vengono conservate
        let keepAll = app.buttons["Tieni tutte"]
        XCTAssertTrue(keepAll.waitForExistence(timeout: 5), "Manca il pulsante per tenerle tutte")
        keepAll.tap()
        XCTAssertTrue(
            element(containing: "sono stati conservati").waitForExistence(timeout: 6),
            "Le foto non sono state riportate tra quelle conservate"
        )
        // Confronto → galleria → gruppi → categorie delle foto → Esplora
        goBack()
        goBack()
        goBack()
        goBack()

        // Video: si riproduce dentro la carta, senza aprire altre schermate
        guard environment["SEEDED_VIDEO"] == "1" else { return }
        let videos = element(startingWith: "Video")
        bringIntoView(videos)
        guard videos.exists else {
            XCTFail("Manca la sezione Video")
            return
        }
        videos.tap()
        pause(1)
        let allVideos = element(startingWith: "Tutti i video")
        guard allVideos.waitForExistence(timeout: 10) else {
            XCTFail("Manca la categoria Tutti i video")
            return
        }
        allVideos.tap()
        let swipeButton = app.buttons["Rivedi con gli swipe"]
        guard swipeButton.waitForExistence(timeout: 30) else {
            capture("46-nessun-video")
            XCTFail("Il video di prova non è tra quelli da rivedere")
            return
        }
        swipeButton.tap()
        let keep = app.buttons["Conserva"]
        XCTAssertTrue(keep.waitForExistence(timeout: 20), "La modalità swipe non si è aperta")
        pause(4)
        capture("46-video-nella-carta")
        // Un tocco sul video lo mette in pausa
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        pause(1.5)
        capture("47-video-in-pausa")

        // Video simili: gli altri si devono poter guardare e scegliere, non solo il primo
        if environment["SEEDED_VIDEO_PAIR"] == "1" {
            reviewSimilarVideosInSwipe()
        }

        // Si conserva tutto ciò che resta, per lasciare la libreria com'era
        let summary = element(containing: "Sessione completata")
        var taps = 0
        while !summary.exists && keep.exists && taps < 6 {
            keep.tap()
            taps += 1
            pause(1.2)
        }
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "La sessione non si è conclusa dopo l'ultimo elemento")
        capture("51-sessione-completata")
        app.buttons["Chiudi"].firstMatch.tap()
        pause(1)
    }

    /// Due riprese quasi uguali compaiono insieme sotto la carta. Toccando quella non in primo piano
    /// deve passare sulla carta e partire; poi la si sceglie con "Tieni solo questo" e si annulla.
    private func reviewSimilarVideosInSwipe() {
        let firstIsCurrent = element(startingWith: "Video 1 del gruppo, sulla carta").waitForExistence(timeout: 15)
        let otherPrefix = firstIsCurrent ? "Video 2 del gruppo" : "Video 1 del gruppo"
        let other = element(startingWith: otherPrefix)
        guard other.waitForExistence(timeout: 5) else {
            capture("48-video-senza-striscia")
            XCTFail("I due video di prova non compaiono come video simili sotto la carta")
            return
        }
        capture("48-video-simili")

        // Un tocco sull'altro video: passa sulla carta e parte
        other.tap()
        XCTAssertTrue(
            element(startingWith: otherPrefix + ", sulla carta").waitForExistence(timeout: 6),
            "Il video toccato nella striscia non è passato sulla carta"
        )
        pause(3)
        capture("49-altro-video-sulla-carta")

        // Lo si sceglie: resta questo, l'altro va in revisione
        let keepThis = app.buttons["Tieni solo questo"]
        guard keepThis.waitForExistence(timeout: 5) else {
            XCTFail("Manca il pulsante per tenere solo il video sulla carta")
            return
        }
        keepThis.tap()
        XCTAssertTrue(
            element(containing: "Sessione completata").waitForExistence(timeout: 10),
            "La scelta sul video non ha concluso la sessione"
        )
        pause(1)
        capture("50-video-scelto")

        // Si annulla: entrambi tornano da decidere
        let undo = app.buttons["Annulla l'ultima scelta"]
        if undo.waitForExistence(timeout: 5) {
            bringIntoView(undo)
            undo.tap()
            XCTAssertTrue(
                app.buttons["Conserva"].waitForExistence(timeout: 10),
                "L'annullamento non ha riportato i video nella sessione"
            )
            pause(1)
        } else {
            XCTFail("Manca il pulsante per annullare la scelta sui video")
        }
    }

    /// Dalla pulizia guidata avvia lo swipe sulle foto simili: controlla la striscia con tutti gli
    /// scatti del gruppo, la scelta "tieni la migliore" e il suo annullamento con un solo gesto.
    /// Al termine le foto tornano com'erano.
    private func reviewSimilarShotsInSwipe() {
        let guided = element(startingWith: "Pulizia guidata")
        bringIntoView(guided)
        guard guided.exists else {
            XCTFail("Voce non trovata nella Home: Pulizia guidata")
            return
        }
        guided.tap()
        guard app.navigationBars["Pulizia guidata"].waitForExistence(timeout: 10) else {
            XCTFail("La pulizia guidata non si è aperta")
            return
        }
        defer { goBack() }

        // Solo il passo delle foto simili ha elementi: è l'unico pulsante attivo.
        let enabledSwipe = app.buttons
            .matching(NSPredicate(format: "label == %@ AND enabled == true", "Rivedi con gli swipe"))
            .firstMatch
        guard enabledSwipe.waitForExistence(timeout: 20) else {
            capture("35-guidata-senza-simili")
            XCTFail("La pulizia guidata non propone le foto simili")
            return
        }
        bringIntoView(enabledSwipe)
        capture("35-guidata-con-simili")
        enabledSwipe.tap()

        let keepBest = app.buttons["Tieni la migliore"]
        guard keepBest.waitForExistence(timeout: 20) else {
            capture("36-swipe-senza-striscia")
            XCTFail("Nello swipe manca la striscia degli scatti simili")
            if app.buttons["Chiudi"].firstMatch.exists {
                app.buttons["Chiudi"].firstMatch.tap()
            }
            return
        }
        pause(2)
        capture("36-swipe-con-simili")

        // Un tocco su un'anteprima della striscia porta quello scatto sulla carta
        let firstShot = element(startingWith: "Foto 1 del gruppo")
        if firstShot.waitForExistence(timeout: 5) {
            firstShot.tap()
            XCTAssertTrue(
                element(startingWith: "Foto 1 del gruppo, sulla carta").waitForExistence(timeout: 6),
                "Lo scatto toccato nella striscia non è passato sulla carta"
            )
            pause(2)
            capture("36b-scatto-scelto-dalla-striscia")
        } else {
            XCTFail("Nella striscia mancano le anteprime degli scatti simili")
        }

        // Un tocco decide l'intero gruppo: resta la migliore, le altre vanno in revisione
        keepBest.tap()
        XCTAssertTrue(
            element(containing: "Sessione completata").waitForExistence(timeout: 10),
            "La scelta sul gruppo non ha concluso la sessione"
        )
        pause(1)
        capture("37-gruppo-deciso")

        // Un solo gesto annulla l'intera scelta
        let undo = app.buttons["Annulla l'ultima scelta"]
        if undo.waitForExistence(timeout: 5) {
            bringIntoView(undo)
            undo.tap()
            XCTAssertTrue(
                app.buttons["Conserva"].waitForExistence(timeout: 10),
                "L'annullamento non ha riportato le foto nella sessione"
            )
            pause(1)
            capture("38-gruppo-annullato")
        } else {
            XCTFail("Manca il pulsante per annullare la scelta sul gruppo")
        }

        reviewSimilarShotsInGrid()
        app.buttons["Chiudi"].firstMatch.tap()
        pause(1)
    }

    /// Dalla striscia sotto la carta apre la griglia del gruppo: selezione trascinando il dito,
    /// tocchi per deselezionare, stella sulla migliore, «Tieni solo la tua migliore» e annullamento.
    /// Alla fine la foto con la stella resta conservata e le altre due tornano da decidere.
    private func reviewSimilarShotsInGrid() {
        let gridButton = app.buttons["Griglia"]
        guard gridButton.waitForExistence(timeout: 10) else {
            capture("38a-striscia-senza-griglia")
            XCTFail("Nella striscia manca il pulsante Griglia")
            return
        }
        gridButton.tap()
        let counter = app.staticTexts["grid.selectionCount"]
        guard counter.waitForExistence(timeout: 10), gridCell(2).waitForExistence(timeout: 5) else {
            capture("38a-griglia-non-aperta")
            XCTFail("La griglia del gruppo non si è aperta con tutte le foto")
            return
        }
        pause(1.5)
        capture("38a-griglia")

        // Trascinando il dito dalla prima alla terza anteprima si selezionano tutte e tre
        dragAcrossGrid(from: 0, to: 2)
        XCTAssertTrue(
            waitForLabel(counter, "3 selezionate", timeout: 4),
            "Il trascinamento non ha selezionato le tre foto (\(counter.label))"
        )
        pause(0.5)
        capture("38b-griglia-trascinamento")

        // Due tocchi deselezionano: resta solo la prima
        gridCell(1).tap()
        gridCell(2).tap()
        XCTAssertTrue(
            waitForLabel(counter, "1 selezionata", timeout: 4),
            "I tocchi non hanno deselezionato le foto (\(counter.label))"
        )

        // La stella: la foto resta conservata e si riconosce
        let star = app.buttons["Segna come migliori"]
        guard star.waitForExistence(timeout: 5) else {
            XCTFail("Nella griglia manca il pulsante per segnare la migliore")
            return
        }
        star.tap()
        XCTAssertTrue(
            element(containing: "la tua migliore").waitForExistence(timeout: 5),
            "La stella non compare sulla foto scelta"
        )
        pause(1)
        capture("38c-griglia-stella")

        // Tieni solo la tua migliore: le altre vanno in revisione e la griglia si chiude
        let keepStarred = app.buttons["Tieni solo la tua migliore"]
        guard keepStarred.waitForExistence(timeout: 5) else {
            XCTFail("Manca il pulsante per tenere solo la foto con la stella")
            return
        }
        keepStarred.tap()
        XCTAssertTrue(
            element(containing: "Sessione completata").waitForExistence(timeout: 10),
            "La scelta fatta nella griglia non ha concluso la sessione"
        )
        pause(1)
        capture("38d-griglia-scelta-fatta")

        // Si annulla: le due foto senza stella tornano da decidere
        let undo = app.buttons["Annulla l'ultima scelta"]
        if undo.waitForExistence(timeout: 5) {
            bringIntoView(undo)
            undo.tap()
            XCTAssertTrue(
                app.buttons["Conserva"].waitForExistence(timeout: 10),
                "L'annullamento non ha riportato le foto nella sessione"
            )
            pause(1)
        } else {
            XCTFail("Manca il pulsante per annullare la scelta fatta nella griglia")
        }
    }

    /// Nel confronto i pulsanti devono stare sopra il bordo inferiore e il contatore sotto la barra
    /// del titolo: prima finivano dietro la barra delle schede e dietro il pulsante per tornare indietro.
    private func checkComparisonLayout() {
        let window = app.windows.firstMatch.frame
        let keepAll = app.buttons["Tieni tutte"]
        guard keepAll.waitForExistence(timeout: 5) else {
            XCTFail("Nel confronto manca il pulsante per tenerle tutte")
            return
        }
        XCTAssertTrue(keepAll.isHittable, "«Tieni tutte» non si può toccare")
        XCTAssertLessThanOrEqual(keepAll.frame.maxY, window.maxY - 16, "«Tieni tutte» esce dal bordo inferiore")
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists && tabBar.isHittable {
            XCTAssertFalse(tabBar.frame.intersects(keepAll.frame), "La barra delle schede copre i pulsanti del confronto")
        }

        let position = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+ di [0-9]+$")).firstMatch
        let titleBar = app.navigationBars["Confronto"]
        if position.waitForExistence(timeout: 3) && titleBar.exists {
            XCTAssertGreaterThanOrEqual(
                position.frame.minY,
                titleBar.frame.maxY - 1,
                "Il contatore delle foto finisce sotto la barra del titolo"
            )
        } else {
            XCTFail("Nel confronto manca il contatore delle foto")
        }
    }

    /// Selezione rapida nella griglia di una categoria: «Seleziona», poi un trascinamento orizzontale
    /// sulla prima riga seleziona tre elementi in un gesto.
    private func checkCategoryGridDragSelection() {
        let photos = element(startingWith: "Foto")
        guard photos.waitForExistence(timeout: 10) else {
            XCTFail("Manca la sezione Foto")
            return
        }
        photos.tap()
        pause(1)
        let allPhotos = element(startingWith: "Tutte le foto")
        guard allPhotos.waitForExistence(timeout: 10) else {
            XCTFail("Manca la categoria Tutte le foto")
            goBack()
            return
        }
        allPhotos.tap()
        let select = app.buttons["Seleziona"]
        guard select.waitForExistence(timeout: 15) else {
            XCTFail("Nella griglia manca il pulsante Seleziona")
            goBack()
            goBack()
            return
        }
        select.tap()
        if gridCell(0).waitForExistence(timeout: 5) && gridCell(2).exists {
            // Con almeno due righe il gesto scende anche di una riga: dalla prima cella alla sesta
            // (seconda riga, terza colonna) devono risultare selezionate sei celle.
            let crossesRows = gridCell(5).exists
            dragAcrossGrid(from: 0, to: crossesRows ? 5 : 2)
            let expected = crossesRows ? "6 selezionati" : "3 selezionati"
            let counter = app.staticTexts["grid.selectionCount"]
            XCTAssertTrue(
                waitForLabel(counter, expected, timeout: 4),
                "Il trascinamento nella griglia non ha selezionato le celle attese (\(counter.label), attese \(expected))"
            )
            pause(0.5)
            capture("24b-griglia-selezione-rapida")
        } else {
            XCTFail("Nella griglia mancano le anteprime")
        }
        let done = app.navigationBars.buttons["Fine"]
        if done.exists {
            done.tap()
            pause(0.5)
        }
        goBack()
        goBack()
    }

    // MARK: - Flusso principale: analisi, swipe, revisione, eliminazione confermata

    func testCleanupFlow() throws {
        completeOnboardingIfNeeded()

        // Home
        XCTAssertTrue(app.buttons["Avvia pulizia intelligente"].waitForExistence(timeout: 40), "La Home non è comparsa")
        capture("01-home")

        // Analisi: deve arrivare in fondo da sola
        app.tabBars.buttons["Analizza"].tap()
        XCTAssertTrue(analysisCompleted.waitForExistence(timeout: 300), "L'analisi non è terminata")
        capture("02-analizza")

        app.tabBars.buttons["Home"].tap()
        pause(2)
        capture("03-home-dopo-analisi")

        // Esplora → Foto → Tutte le foto
        app.tabBars.buttons["Esplora"].tap()
        pause(1)
        capture("04-esplora")
        let photos = element(startingWith: "Foto")
        XCTAssertTrue(photos.waitForExistence(timeout: 10), "Manca la sezione Foto")
        photos.tap()
        pause(1)
        capture("05-categorie-foto")
        let allPhotos = element(startingWith: "Tutte le foto")
        XCTAssertTrue(allPhotos.waitForExistence(timeout: 10), "Manca la categoria Tutte le foto")
        allPhotos.tap()

        let swipeButton = app.buttons["Rivedi con gli swipe"]
        XCTAssertTrue(swipeButton.waitForExistence(timeout: 30), "La griglia non contiene elementi da rivedere")
        pause(2)
        capture("06-griglia")
        swipeButton.tap()

        // Modalità swipe
        let keep = app.buttons["Conserva"]
        XCTAssertTrue(keep.waitForExistence(timeout: 20), "La modalità swipe non si è aperta")
        pause(2)
        capture("07-swipe")

        // Swipe a sinistra: aggiunge alla lista, non elimina
        let window = app.windows.firstMatch
        let center = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        let farLeft = window.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.42))
        center.press(forDuration: 0.1, thenDragTo: farLeft)
        XCTAssertTrue(
            element(containing: "Da eliminare: 1").waitForExistence(timeout: 6),
            "Lo swipe a sinistra non ha aggiunto l'elemento alla lista"
        )

        // Pulsanti equivalenti ai gesti
        keep.tap()
        XCTAssertTrue(element(containing: "Conservati: 1").waitForExistence(timeout: 6), "Conserva non ha funzionato")
        app.buttons["Più tardi"].tap()
        pause(1)
        app.buttons["Annulla"].tap()
        pause(1)
        capture("08-swipe-dopo-annulla")
        app.buttons["Elimina"].tap()
        XCTAssertTrue(element(containing: "Da eliminare: 2").waitForExistence(timeout: 6), "Elimina non ha funzionato")
        pause(1)
        capture("09-swipe-due-selezionati")

        // Dettagli
        app.buttons["Dettagli"].tap()
        XCTAssertTrue(app.navigationBars["Dettagli"].waitForExistence(timeout: 10), "I dettagli non si sono aperti")
        pause(1)
        capture("10-dettagli")
        app.navigationBars["Dettagli"].buttons["Fine"].tap()
        pause(1)

        // Revisione
        app.navigationBars.buttons["Revisione"].tap()
        let review = app.buttons["Controlla ed elimina"]
        XCTAssertTrue(review.waitForExistence(timeout: 15), "La revisione non mostra gli elementi selezionati")
        pause(1)
        capture("11-revisione")
        review.tap()

        // Conferma
        XCTAssertTrue(app.navigationBars["Conferma eliminazione"].waitForExistence(timeout: 30), "Manca la schermata di conferma")
        pause(1)
        capture("12-conferma")
        let acknowledge = app.switches["Ho capito gli effetti su iCloud"]
        if acknowledge.waitForExistence(timeout: 5) {
            bringIntoView(acknowledge)
            acknowledge.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            pause(0.5)
            if (acknowledge.value as? String) != "1" {
                acknowledge.tap()
            }
        }
        let delete = element(startingWith: "Elimina 2")
        bringIntoView(delete)
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Manca il pulsante di eliminazione")
        capture("13-conferma-pronta")
        delete.tap()

        // iOS chiede sempre un'ulteriore conferma per le foto
        XCTAssertTrue(tapSystemButton(["Delete", "Elimina"], timeout: 40), "Manca la conferma di sistema di iOS")
        XCTAssertTrue(app.navigationBars["Esito"].waitForExistence(timeout: 40), "L'esito non è comparso")
        pause(1)
        capture("14-esito")
        XCTAssertTrue(element(containing: "Eliminati correttamente").exists, "Il resoconto non riporta gli stati")
        let done = app.buttons["Fine"]
        bringIntoView(done)
        done.tap()

        // Dopo l'eliminazione la lista di revisione deve essere vuota
        XCTAssertTrue(
            element(containing: "Nessun elemento da eliminare").waitForExistence(timeout: 15),
            "Gli elementi eliminati sono ancora nella lista di revisione"
        )
        pause(1)
        capture("15-revisione-vuota")

        app.tabBars.buttons["Risultati"].tap()
        pause(1)
        capture("16-risultati")
    }

    // MARK: - Giro delle schermate

    /// Apre le altre schermate e ne salva l'aspetto. Un passo non riuscito non blocca i successivi.
    func testScreensTour() throws {
        continueAfterFailure = true
        completeOnboardingIfNeeded()
        XCTAssertTrue(app.buttons["Avvia pulizia intelligente"].waitForExistence(timeout: 40), "La Home non è comparsa")

        // Impostazioni
        let settings = app.navigationBars.buttons["Impostazioni"]
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            XCTAssertTrue(app.navigationBars["Impostazioni"].waitForExistence(timeout: 10))
            pause(1)
            capture("20-impostazioni")
            checkAboutScreens()
            app.navigationBars["Impostazioni"].buttons["Fine"].tap()
            pause(1)
        }

        // Parte bassa della Home
        app.swipeUp()
        pause(1)
        capture("21-home-modalita")
        app.swipeUp()
        pause(1)
        capture("22-home-categorie")

        visitFromHome("Pulizia guidata", title: "Pulizia guidata", name: "23-pulizia-guidata")
        visitFromHome("Pulizia avanzata", title: "Pulizia avanzata", name: "24-pulizia-avanzata")

        // Esplora
        app.tabBars.buttons["Esplora"].tap()
        pause(1)
        checkCategoryGridDragSelection()

        let search = element(startingWith: "Ricerca intelligente")
        if search.waitForExistence(timeout: 5) {
            search.tap()
            let field = app.textFields.firstMatch
            if field.waitForExistence(timeout: 5) {
                field.tap()
                field.typeText("screenshot piu vecchi di un anno con testo")
                app.buttons["Cerca"].tap()
                pause(2)
                capture("25-ricerca-intelligente")
            }
            goBack()
        }

        visitFromList("Centro iCloud", name: "26-centro-icloud")
        visitFromList("Assistente app", name: "27-assistente-app")
        visitFromList("Archivio storico", name: "28-archivio-storico")
        visitFromList("Documenti e file", name: "29-documenti")
        visitFromList("Audio e registrazioni", name: "30-audio")
        visitFromList("Modalità viaggio", name: "31-modalita-viaggio")
        visitFromList("Modalità nostalgia", name: "32-modalita-nostalgia")

        // Analizza → trasparenza su cosa permette iOS
        app.tabBars.buttons["Analizza"].tap()
        pause(1)
        capture("33-analizza")
        visitFromList("Cosa può fare ClearSpace", name: "34-cosa-permette-ios")

        checkGuideAndTutorials()
    }

    /// Guida completa e tutorial dalla Home. La prova precedente ha fatto uno swipe a sinistra, ha usato
    /// i pulsanti e l'annullamento: i relativi esercizi del tutorial sullo swipe devono essere spuntati.
    private func checkGuideAndTutorials() {
        app.tabBars.buttons["Home"].tap()
        pause(1)
        let card = app.descendants(matching: .any)["home.guide"]
        bringIntoView(card)
        guard card.exists else {
            XCTFail("Nella Home manca la scheda Guida e tutorial")
            return
        }
        card.tap()
        XCTAssertTrue(app.navigationBars["Guida e tutorial"].waitForExistence(timeout: 5), "La guida non si è aperta")
        pause(1)
        capture("35a-guida-e-tutorial")

        let chapter = element(startingWith: "Lo swipe")
        bringIntoView(chapter)
        if chapter.exists {
            chapter.tap()
            XCTAssertTrue(app.navigationBars["Lo swipe"].waitForExistence(timeout: 5), "Il capitolo non si è aperto")
            XCTAssertTrue(element(containing: "Verso sinistra").waitForExistence(timeout: 5), "Nel capitolo mancano i gesti")
            pause(1)
            capture("35b-capitolo-swipe")
            goBack()
        } else {
            XCTFail("Nella guida manca il capitolo sullo swipe")
        }

        let tutorials = element(startingWith: "Tutti i tutorial")
        bringIntoView(tutorials)
        guard tutorials.exists else {
            XCTFail("Nella guida mancano i tutorial")
            goBack()
            return
        }
        tutorials.tap()
        XCTAssertTrue(app.navigationBars["Tutorial"].waitForExistence(timeout: 5), "L'elenco dei tutorial non si è aperto")
        pause(1)
        capture("35c-elenco-tutorial")
        let swipeTutorial = element(startingWith: "Lo swipe")
        if swipeTutorial.waitForExistence(timeout: 5) {
            swipeTutorial.tap()
            XCTAssertTrue(app.navigationBars["Lo swipe"].waitForExistence(timeout: 5), "Il tutorial non si è aperto")
            pause(1)
            capture("35d-tutorial-swipe")
            for taskID in ["swipe.left", "swipe.undo", "swipe.buttons"] {
                let row = app.descendants(matching: .any)["tutorial.task.\(taskID)"]
                bringIntoView(row)
                let isDone = row.exists && (row.label.contains("completato") || row.staticTexts["Completato"].exists)
                XCTAssertTrue(isDone, "L'esercizio \(taskID) non si è spuntato da solo dopo l'azione")
            }
            capture("35e-tutorial-swipe-spuntato")
            goBack()
        }
        goBack()
        goBack()
    }

    /// Informazioni con autore e crediti, novità della versione e guida rapida, dalle Impostazioni.
    private func checkAboutScreens() {
        let about = element(startingWith: "Informazioni su ClearSpace")
        bringIntoView(about)
        guard about.exists else {
            XCTFail("Nelle Impostazioni manca «Informazioni su ClearSpace»")
            return
        }
        about.tap()
        XCTAssertTrue(app.navigationBars["Informazioni"].waitForExistence(timeout: 5), "Le informazioni non si sono aperte")
        XCTAssertTrue(element(containing: "Lorenzo Minichilli").waitForExistence(timeout: 5), "Nelle informazioni manca l'autore")
        pause(1)
        capture("20b-informazioni")
        scroll(by: 0.45)
        capture("20c-informazioni-crediti")
        goBack()

        for (prefix, title, name) in [
            ("Novità di questa versione", "Novità", "20d-novita"),
            ("Guida rapida", "Guida rapida", "20e-guida-rapida")
        ] {
            let link = element(startingWith: prefix)
            bringIntoView(link)
            guard link.exists else {
                XCTFail("Nelle Impostazioni manca «\(prefix)»")
                continue
            }
            link.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "Non si è aperta: \(title)")
            pause(1)
            capture(name)
            goBack()
        }
    }

    private func visitFromHome(_ prefix: String, title: String, name: String) {
        let link = element(startingWith: prefix)
        bringIntoView(link)
        guard link.exists else {
            XCTFail("Voce non trovata nella Home: \(prefix)")
            return
        }
        link.tap()
        guard app.navigationBars[title].waitForExistence(timeout: 10) else {
            XCTFail("Schermata non aperta: \(title)")
            return
        }
        pause(1)
        capture(name)
        goBack()
    }

    private func visitFromList(_ prefix: String, name: String) {
        let link = element(startingWith: prefix)
        bringIntoView(link)
        guard link.exists else {
            XCTFail("Voce non trovata: \(prefix)")
            return
        }
        let origin = currentTitle
        link.tap()
        pause(1.5)
        guard currentTitle != origin else {
            XCTFail("La schermata non si è aperta: \(prefix)")
            return
        }
        capture(name)
        goBack()
    }
}
