import XCTest

/// Base delle prove d'uso: avvio dell'app e strumenti comuni (schermate, ricerca degli elementi,
/// scorrimento senza inerzia, ritorno alla schermata precedente, controlli sul layout).
class UITestCase: XCTestCase {

    var app: XCUIApplication!
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    /// Argomenti di avvio aggiuntivi, ad esempio la dimensione del testo.
    var launchArguments: [String] { [] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += launchArguments
        app.launch()
    }

    // MARK: - Schermate e attese

    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Aspetta che l'etichetta di un elemento diventi esattamente quella attesa.
    func waitForLabel(_ element: XCUIElement, _ expected: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: - Ricerca degli elementi

    func element(startingWith prefix: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    func element(containing text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    /// Indicazione che l'analisi è arrivata in fondo: il titolo «Analisi completata» appena finisce,
    /// oppure la riga «Ultima analisi completata…» quando l'app viene riaperta.
    var analysisCompleted: XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", "analisi completata")
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    /// Cella della griglia in una certa posizione (0 = la prima in alto a sinistra).
    func gridCell(_ index: Int) -> XCUIElement {
        app.descendants(matching: .any)["grid.cell.\(index)"]
    }

    /// Titolo della schermata in primo piano: serve a capire se un tocco ne ha aperta un'altra.
    var currentTitle: String {
        let bar = app.navigationBars.firstMatch
        return bar.exists ? bar.identifier : ""
    }

    // MARK: - Movimenti

    /// Vero se l'elemento è visibile lontano dalle barre in alto e in basso. Sotto le barre traslucide
    /// un elemento risulta comunque toccabile, ma il tocco finisce sulla barra e non apre nulla.
    func isComfortablyVisible(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let screen = app.windows.firstMatch.frame
        let middle = element.frame.midY
        return middle > screen.minY + 130 && middle < screen.maxY - 110
    }

    /// Trascina il contenuto senza inerzia, di una frazione dell'altezza dello schermo.
    /// Valori positivi mostrano ciò che sta più in basso.
    func scroll(by fraction: CGFloat) {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 - fraction))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Porta l'elemento nella zona centrale dello schermo. Se non è ancora in elenco
    /// lo cerca prima più in basso e poi più in alto.
    func bringIntoView(_ element: XCUIElement) {
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

    /// Trascina il dito in orizzontale dalla cella `from` alla cella `to`, come per selezionare
    /// più foto insieme nell'app Foto.
    func dragAcrossGrid(from: Int, to: Int) {
        let start = gridCell(from).coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let end = gridCell(to).coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    /// Tocca un pulsante di un avviso di sistema (permessi, conferma di eliminazione).
    @discardableResult
    func tapSystemButton(_ labels: [String], timeout: TimeInterval) -> Bool {
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

    /// Torna alla schermata precedente. Va chiamata solo dopo aver verificato che se ne sia aperta una.
    func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        guard back.waitForExistence(timeout: 3) else { return }
        back.tap()
        pause(0.8)
    }

    /// Completa l'introduzione del primo avvio e concede l'accesso a Foto.
    func completeOnboardingIfNeeded() {
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

    // MARK: - Controlli sul layout

    /// Testi e pulsanti visibili che escono, anche solo in parte, dai bordi laterali dello schermo.
    /// Gli elementi del tutto fuori schermo (in una fila che scorre di lato) non contano, e nemmeno
    /// le anteprime di foto e video, che in una striscia scorrevole possono essere tagliate dal bordo.
    func horizontalOverflows() -> [String] {
        // Un'unica lettura dell'albero dell'accessibilità: interrogare gli elementi uno per uno
        // richiederebbe secondi per ogni schermata.
        guard let root = try? app.snapshot() else { return [] }
        let window = root.frame
        guard window.width > 0 else { return [] }
        var offenders: [String] = []

        func inspect(_ node: XCUIElementSnapshot) {
            if node.elementType == .staticText || node.elementType == .button {
                let frame = node.frame
                let label = node.label
                let isThumbnail = label.hasPrefix("Foto ") || label.hasPrefix("Video ") || label.hasPrefix("Elemento ")
                if !frame.isEmpty, !label.isEmpty, !isThumbnail,
                   // Solo ciò che si trova nella parte visibile, in verticale e in orizzontale.
                   frame.maxY > window.minY + 1, frame.minY < window.maxY - 1,
                   frame.maxX > window.minX + 1, frame.minX < window.maxX - 1,
                   frame.minX < window.minX - 1 || frame.maxX > window.maxX + 1 {
                    offenders.append("«\(label.prefix(40))» da x=\(Int(frame.minX)) a x=\(Int(frame.maxX))")
                }
            }
            for child in node.children {
                inspect(child)
            }
        }

        inspect(root)
        return offenders
    }

    /// Salva la schermata e segnala come errore i testi che escono dallo schermo.
    func checkLayout(_ name: String) {
        pause(0.8)
        capture(name)
        let offenders = horizontalOverflows()
        if !offenders.isEmpty {
            XCTFail("\(name): testi o pulsanti che escono dallo schermo: \(offenders.joined(separator: "; "))")
        }
    }

    /// Vero se l'elemento sta per intero dentro lo schermo e non è coperto dalla barra delle schede.
    func isFullyOnScreen(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let window = app.windows.firstMatch.frame
        let frame = element.frame
        guard window.insetBy(dx: -1, dy: -1).contains(frame) else { return false }
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists && tabBar.isHittable && tabBar.frame.intersects(frame) {
            return false
        }
        return true
    }
}
