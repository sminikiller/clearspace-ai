import Foundation
import PDFKit
import UIKit

/// Testo di un documento, pagina per pagina.
struct DocumentText: Sendable {
    /// Numero reale di pagine del documento.
    var pageCount: Int
    /// Testo delle pagine lette (può essere un sottoinsieme iniziale del documento).
    var pages: [String]
    /// `true` se il testo è stato ricavato con il riconoscimento ottico (documento scansionato).
    var usedOCR: Bool

    var fullText: String { pages.joined(separator: "\n") }
}

/// Estrae il testo dai PDF per confrontarne le versioni. Tutto avviene sul dispositivo.
enum DocumentTextExtractor {

    static func extract(pdfAt url: URL, maxPages: Int = 40, ocrPages: Int = 8) -> DocumentText? {
        guard let document = PDFDocument(url: url) else { return nil }
        let pageCount = document.pageCount
        // I documenti protetti da password non vengono letti.
        guard !document.isLocked, pageCount > 0 else {
            return DocumentText(pageCount: pageCount, pages: [], usedOCR: false)
        }

        let readable = min(pageCount, maxPages)
        var pages: [String] = []
        pages.reserveCapacity(readable)
        for index in 0..<readable {
            pages.append(document.page(at: index)?.string ?? "")
        }

        // Pochissimo testo rispetto alle pagine: probabile scansione, serve il riconoscimento ottico.
        let characters = pages.reduce(0) { $0 + $1.count }
        guard characters < readable * 20 else {
            return DocumentText(pageCount: pageCount, pages: pages, usedOCR: false)
        }

        var recognizedPages: [String] = []
        for index in 0..<min(pageCount, ocrPages) {
            guard let page = document.page(at: index) else {
                recognizedPages.append("")
                continue
            }
            let image = page.thumbnail(of: CGSize(width: 1_100, height: 1_500), for: .mediaBox)
            if let cgImage = image.cgImage {
                recognizedPages.append(ImageAnalyzer.recognizeText(in: cgImage, accurate: true).text)
            } else {
                recognizedPages.append("")
            }
        }
        return DocumentText(pageCount: pageCount, pages: recognizedPages, usedOCR: true)
    }
}
