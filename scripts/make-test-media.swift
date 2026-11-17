// Genera i contenuti di prova per la verifica sul simulatore: tre scatti quasi identici della stessa
// scena (uno nitido, uno sfocato, uno scuro) e un breve video. Servono a provare davvero il
// riconoscimento delle foto simili, la scelta dello scatto migliore e il lettore video, che con le
// sole foto di esempio del simulatore non verrebbero mai esercitati.
//
// Uso: swift scripts/make-test-media.swift <cartella di destinazione>

import AVFoundation
import AppKit
import CoreImage
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("Uso: swift make-test-media.swift <cartella>")
    exit(2)
}
let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

/// Disegna una scena ricca di dettaglio: sfondo sfumato, forme, linee sottili e testo.
/// `shift` sposta l'inquadratura di qualche pixel, come tra due scatti consecutivi.
func renderScene(shift: CGFloat) -> CGImage? {
    let sceneWidth = 1_600
    let sceneHeight = 1_200
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: sceneWidth,
        height: sceneHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    let width = CGFloat(sceneWidth)
    let height = CGFloat(sceneHeight)

    let colors = [
        CGColor(red: 0.12, green: 0.45, blue: 0.78, alpha: 1),
        CGColor(red: 0.95, green: 0.78, blue: 0.42, alpha: 1)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
    }

    context.translateBy(x: shift, y: shift * 0.5)

    // Forme grandi: danno alla scena una struttura riconoscibile.
    context.setFillColor(CGColor(red: 0.85, green: 0.20, blue: 0.25, alpha: 1))
    context.fillEllipse(in: CGRect(x: 180, y: 620, width: 380, height: 380))
    context.setFillColor(CGColor(red: 0.15, green: 0.62, blue: 0.35, alpha: 1))
    context.fill(CGRect(x: 760, y: 180, width: 520, height: 360))
    context.setFillColor(CGColor(red: 0.98, green: 0.96, blue: 0.90, alpha: 1))
    context.fillEllipse(in: CGRect(x: 1_020, y: 700, width: 300, height: 300))

    // Linee sottili: è qui che si vede la differenza tra uno scatto nitido e uno sfocato.
    context.setStrokeColor(CGColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 1))
    context.setLineWidth(2)
    var x: CGFloat = 60
    while x < width - 60 {
        context.move(to: CGPoint(x: x, y: 80))
        context.addLine(to: CGPoint(x: x + 90, y: 430))
        x += 22
    }
    context.strokePath()

    var seed: UInt64 = 42
    func nextRandom() -> CGFloat {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat((seed >> 33) % 10_000) / 10_000
    }
    for _ in 0..<900 {
        let gray = nextRandom()
        context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: nextRandom() * width, y: 460 + nextRandom() * 120, width: 6, height: 6))
    }

    let text = NSAttributedString(
        string: "ClearSpace · scatto di prova",
        attributes: [
            .font: NSFont.boldSystemFont(ofSize: 64),
            .foregroundColor: NSColor.white
        ]
    )
    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    text.draw(at: NSPoint(x: 120, y: 1_040))
    NSGraphicsContext.restoreGraphicsState()

    return context.makeImage()
}

func blurred(_ image: CGImage, radius: Double, using ciContext: CIContext) -> CGImage? {
    let input = CIImage(cgImage: image)
    let output = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
    return ciContext.createCGImage(output, from: input.extent)
}

func darkened(_ image: CGImage, exposure: Double, using ciContext: CIContext) -> CGImage? {
    let input = CIImage(cgImage: image)
    let output = input.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure])
    return ciContext.createCGImage(output, from: input.extent)
}

/// Salva un JPEG con la data di scatto indicata: scatti ravvicinati vengono confrontati tra loro.
func writeJPEG(_ image: CGImage, to directory: URL, name: String, secondsOffset: Int) throws {
    let url = directory.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
        throw NSError(domain: "media", code: 1)
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    let base = Date(timeIntervalSince1970: 1_750_000_000)
    let stamp = formatter.string(from: base.addingTimeInterval(TimeInterval(secondsOffset)))
    let properties: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.9,
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: stamp,
            kCGImagePropertyExifDateTimeDigitized: stamp
        ],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: stamp]
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "media", code: 2)
    }
    print("Creato \(name)")
}

guard let sharp = renderScene(shift: 0), let shifted = renderScene(shift: 6) else {
    print("Impossibile disegnare la scena")
    exit(1)
}
let ciContext = CIContext()
try writeJPEG(sharp, to: outputDirectory, name: "simile-1-nitida.jpg", secondsOffset: 0)
if let soft = blurred(shifted, radius: 5, using: ciContext) {
    try writeJPEG(soft, to: outputDirectory, name: "simile-2-sfocata.jpg", secondsOffset: 2)
}
if let dark = darkened(shifted, exposure: -1.6, using: ciContext) {
    try writeJPEG(dark, to: outputDirectory, name: "simile-3-scura.jpg", secondsOffset: 4)
}

// MARK: - Video

/// Video di quattro secondi con un riquadro che si sposta: basta a provare riproduzione e fotogrammi.
/// `variation` cambia appena i colori: due riprese quasi uguali devono risultare "video simili".
func writeVideo(to directory: URL, name: String, variation: CGFloat) async throws {
    let url = directory.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    let width = 640
    let height = 360
    let framesPerSecond: Int32 = 24
    let frameCount = 96

    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
    )
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
    )
    writer.add(input)
    guard writer.startWriting() else {
        throw writer.error ?? NSError(domain: "media", code: 3)
    }
    writer.startSession(atSourceTime: .zero)

    for frame in 0..<frameCount {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, nil, &buffer)
        guard let buffer else { continue }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) {
            let progress = CGFloat(frame) / CGFloat(frameCount)
            context.setFillColor(
                CGColor(red: 0.10 + variation, green: 0.20 + 0.5 * progress, blue: 0.55 - variation, alpha: 1)
            )
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(red: 1, green: 0.85 - variation, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: progress * CGFloat(width - 120), y: 120, width: 120, height: 120))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let time = CMTime(value: CMTimeValue(frame), timescale: framesPerSecond)
        adaptor.append(buffer, withPresentationTime: time)
    }

    input.markAsFinished()
    await writer.finishWriting()
    if writer.status != .completed {
        throw writer.error ?? NSError(domain: "media", code: 4)
    }
    print("Creato \(name)")
}

// Due riprese quasi uguali: l'app deve mostrarle insieme e lasciarle guardare e decidere una per una.
for (name, variation) in [("video-di-prova-1.mp4", CGFloat(0)), ("video-di-prova-2.mp4", CGFloat(0.04))] {
    do {
        try await writeVideo(to: outputDirectory, name: name, variation: variation)
    } catch {
        // I video sono un di più: senza, le prove sulle foto restano valide.
        print("Video non creato (\(name)): \(error)")
    }
}
