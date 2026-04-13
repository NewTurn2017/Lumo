import Foundation
import CoreGraphics
import ImageIO

/// Region capture backed by macOS's native `/usr/sbin/screencapture -i` picker.
///
/// Apple's interactive picker is the same tool `⌘⇧4` invokes — it handles multi-
/// monitor layouts, the crosshair cursor, Space-to-window-mode switching, ESC
/// cancellation, and HiDPI scaling natively. Re-implementing any of that in-app
/// is a maintenance burden and historically did not work reliably across displays
/// from an `LSUIElement` accessory app.
final class NativeScreenCapture: CaptureService {
    func captureRegion() async throws -> CGImage {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumo-capture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i: interactive selection UI
        // -x: silent (we play our own confirmation sound from the orchestrator)
        // -t png: explicit output format
        process.arguments = ["-i", "-x", "-t", "png", tempURL.path]

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (cont: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in cont.resume() }
                do {
                    try process.run()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }

        // ESC / empty drag → screencapture exits 0 without writing a file.
        guard FileManager.default.fileExists(atPath: tempURL.path),
              let source = CGImageSourceCreateWithURL(tempURL as CFURL, nil),
              let loaded = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw CancellationError()
        }
        // `CGImageSourceCreateImageAtIndex` lazy-loads pixels; the returned
        // CGImage still references the file. Our `defer` cleanup deletes the
        // file before the caller runs OCR, which silently yields an empty
        // image. Force-decode into an independent pixel buffer here so the
        // returned CGImage has no file dependency.
        let image = try Self.forceDecode(loaded)

        // Copy to a stable debug path so the user can inspect what was actually
        // captured when translation output seems wrong. Overwrites each run.
        let debugPath = "/tmp/lumo-last-capture.png"
        try? FileManager.default.removeItem(atPath: debugPath)
        try? FileManager.default.copyItem(atPath: tempURL.path, toPath: debugPath)
        Log.capture.info(
            "captured region: \(image.width)x\(image.height) px, saved to \(debugPath, privacy: .public)"
        )
        return image
    }

    private static func forceDecode(_ image: CGImage) throws -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CancellationError()
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let decoded = ctx.makeImage() else {
            throw CancellationError()
        }
        return decoded
    }
}
