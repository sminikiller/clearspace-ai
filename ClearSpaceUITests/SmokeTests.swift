import XCTest

/// Prova d'uso sul simulatore: percorre i flussi principali dell'app come farebbe una persona
/// e salva una schermata a ogni passo. Serve a verificare che l'app funzioni davvero,
/// non soltanto che compili.
final class SmokeTests: XCTestCase {

    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Supporto

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func element(startingWith prefix: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func element(containing text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    /// Vero se l'elemento è visibile lontano dalle barre in alto e in basso. Sotto le barre traslucide
    /// un elemento risulta comunque toccabile, ma il tocco finisce sulla barra e non apre nulla.
    private func isComfortablyVisible(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let screen = app.windows.firstMatch.frame
        let middle = element.frame.midY
        return middle > screen.minY + 130 && middle < screen.maxY - 110
    }

    /// Trascina il contenuto senza inerzia, di una frazione dell'altezza dello schermo.
    /// Valori positivi mostrano ciò che sta più in basso.
    private func scroll(by fraction: CGFloat) {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 - fraction))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Porta l'elemento nella zona centrale dello schermo. Se non è ancora in elenco
    /// lo cerca prima più in basso e poi più in alto.
    private func bringIntoView(_ element: XCUIElement) {
        var step = 0
        var stalled = 0
        while !isComfortablyVisible(element) && step < 16 && stalled < 2 {
            let previous = element.exists ? element.frame : CGRect.null
            if element.exists {
                let screen = app.windows.firstMatch.frame
                let distance = (element.frame.midY - screen.midY) / max(screen.height, 1)
                scroll(by: min(0.45, max(-0.45, distance)))
            } else {
                scroll(by: step < 5 ? 0.4 : -0.4)
            }
            // Fine del contenuto: l'elemento non si sposta più.
            if element.exists && element.frame == previous {
                stalled += 1
            } else {
                stalled = 0
            }
            step += 1
        }
    }

    /// Tocca un pulsante di un avviso di sistema (permessi, conferma di eliminazione).
    @discardableResult
    private func tapSystemButton(_ labels: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in labels {
                let button = springboard.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            pause(0.5)
        }
        return false
    }

    /// Completa l'introduzione del primo avvio e concede l'accesso a Foto.
    private func completeOnboardingIfNeeded() {
        // Gli identificatori distinguono i pulsanti dell'introduzione da quelli, omonimi, della Home sottostante.
        let next = app.buttons["onboarding.continue"]
        guard next.waitForExistence(timeout: 12) else { return }
        capture("00-introduzione-1")
        next.tap()
        pause(1)
        capture("00-introduzione-2")
        next.tap()
        pause(1)

        let primary = app.buttons["onboarding.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5), "Manca l'ultima pagina dell'introduzione")
        capture("00-introduzione-3")
        let needsPermission = primary.label.contains("Consenti")
        primary.tap()
        if needsPermission {
            let granted = tapSystemButton(
                ["Allow Full Access", "Allow Access to All Photos", "Consenti accesso completo"],
                timeout: 20
            )
            XCTAssertTrue(granted, "L'avviso di sistema per l'accesso a Foto non è comparso")
        }
        pause(1)
    }

    /// Titolo della schermata in primo piano: serve a capire se un tocco ne ha aperta un'altra.
    private var currentTitle: String {
        let bar = app.navigationBars.firstMatch
        return bar.exists ? bar.identifier : ""
    }

    /// Torna alla schermata precedente. Va chiamata solo dopo aver verificato che se ne sia aperta una.
    private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        guard back.waitForExistence(timeout: 3) else { return }
        back.tap()
        pause(0.8)
    }

    // MARK: - Flusso principale: analisi, swipe, revisione, eliminazione confermata

    func testCleanupFlow() throws {
        completeOnboardingIfNeeded()

        // Home
        XCTAssertTrue(app.buttons["Avvia pulizia intelligente"].waitForExistence(timeout: 40), "La Home non è comparsa")
        capture("01-home")

        // Analisi: deve arrivare in fondo da sola
        app.tabBars.buttons["Analizza"].tap()
        XCTAssertTrue(
            element(containing: "Analisi completata").waitForExistence(timeout: 300),
            "L'analisi non è terminata"
        )
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
