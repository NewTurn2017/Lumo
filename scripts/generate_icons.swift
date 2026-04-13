#!/usr/bin/env swift
import AppKit

// MARK: - App Icon Generator
// Design: Rounded rectangle with blue-purple gradient background + white "L" letter

func generateAppIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * 0.22

    // Rounded rect path (macOS icon shape)
    let path = CGPath(roundedRect: rect.insetBy(dx: s * 0.02, dy: s * 0.02),
                      cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                      transform: nil)

    // Gradient background: blue to purple
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.30, green: 0.50, blue: 1.0, alpha: 1.0),  // bright blue
        CGColor(red: 0.55, green: 0.30, blue: 0.95, alpha: 1.0),  // purple
    ]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: s),
                               end: CGPoint(x: s, y: 0),
                               options: [])
    }
    ctx.restoreGState()

    // Subtle inner shadow / light overlay at top
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let overlayColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.25),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ]
    if let overlay = CGGradient(colorsSpace: colorSpace, colors: overlayColors as CFArray, locations: [0.0, 0.5]) {
        ctx.drawLinearGradient(overlay,
                               start: CGPoint(x: s / 2, y: s),
                               end: CGPoint(x: s / 2, y: s * 0.3),
                               options: [])
    }
    ctx.restoreGState()

    // Draw "L" letter
    let fontSize = s * 0.55
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let str = NSAttributedString(string: "L", attributes: attrs)
    let strSize = str.size()
    let x = (s - strSize.width) / 2
    let y = (s - strSize.height) / 2 - s * 0.02
    str.draw(at: NSPoint(x: x, y: y))

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("Created: \(path)")
    } catch {
        print("Error writing \(path): \(error)")
    }
}

// MARK: - Menu Bar Icon Generator
// Design: Simple "L" with a subtle glow/circle, rendered as template image (black on transparent)

func generateMenuBarIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Draw a small circle outline with more padding
    let circleInset = s * 0.22
    let circleRect = CGRect(x: circleInset, y: circleInset,
                            width: s - circleInset * 2, height: s - circleInset * 2)
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1.0))
    ctx.setLineWidth(s * 0.06)
    ctx.strokeEllipse(in: circleRect)

    // Draw "L" in the center
    let fontSize = s * 0.32
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.black,
    ]
    let str = NSAttributedString(string: "L", attributes: attrs)
    let strSize = str.size()
    let x = (s - strSize.width) / 2
    let y = (s - strSize.height) / 2
    str.draw(at: NSPoint(x: x, y: y))

    image.unlockFocus()
    return image
}

// MARK: - Generate All

let basePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// App icons
let appIconSizes = [16, 32, 64, 128, 256, 512, 1024]
for size in appIconSizes {
    let image = generateAppIcon(size: size)
    savePNG(image, to: "\(basePath)/AppIcon.appiconset/icon_\(size).png")
}

// Menu bar icons
let menuBar1x = generateMenuBarIcon(size: 18)
savePNG(menuBar1x, to: "\(basePath)/MenuBarIcon.imageset/menubar_icon.png")

let menuBar2x = generateMenuBarIcon(size: 36)
savePNG(menuBar2x, to: "\(basePath)/MenuBarIcon.imageset/menubar_icon@2x.png")

print("Done! All icons generated.")
