#!/usr/bin/env swift
// generate-icon.swift — Generate DevPulse app icon as .icns
// Usage: swift scripts/generate-icon.swift

import Cocoa

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size
    let pad = s * 0.08

    // Background: rounded rectangle with dark gradient
    let bgRect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let radius = s * 0.22
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Gradient: dark charcoal to near-black
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradColors = [
        CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0),
        CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0, 1]) {
        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()
        ctx.drawLinearGradient(gradient,
            start: CGPoint(x: s/2, y: s - pad),
            end: CGPoint(x: s/2, y: pad),
            options: [])
        ctx.restoreGState()
    }

    // Subtle border
    ctx.setStrokeColor(CGColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 0.6))
    ctx.setLineWidth(s * 0.008)
    ctx.addPath(bgPath)
    ctx.strokePath()

    // Memory chip shape (simplified rectangle with notches)
    let chipW = s * 0.36
    let chipH = s * 0.42
    let chipX = s * 0.5 - chipW / 2
    let chipY = s * 0.52 - chipH / 2
    let chipRadius = s * 0.04
    let chipRect = CGRect(x: chipX, y: chipY, width: chipW, height: chipH)
    let chipPath = CGPath(roundedRect: chipRect, cornerWidth: chipRadius, cornerHeight: chipRadius, transform: nil)

    // Chip fill: dark with slight green tint
    ctx.setFillColor(CGColor(red: 0.10, green: 0.14, blue: 0.12, alpha: 1.0))
    ctx.addPath(chipPath)
    ctx.fillPath()

    // Chip border: green glow
    ctx.setStrokeColor(CGColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 0.7))
    ctx.setLineWidth(s * 0.012)
    ctx.addPath(chipPath)
    ctx.strokePath()

    // Chip pins (4 on each side)
    let pinW = s * 0.06
    let pinH = s * 0.02
    let pinGap = chipH / 5
    ctx.setFillColor(CGColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 0.5))

    for i in 1...4 {
        let py = chipY + pinGap * CGFloat(i) - pinH / 2
        // Left pins
        ctx.fill(CGRect(x: chipX - pinW, y: py, width: pinW, height: pinH))
        // Right pins
        ctx.fill(CGRect(x: chipX + chipW, y: py, width: pinW, height: pinH))
    }
    // Top and bottom pins
    let hPinW = s * 0.02
    let hPinH = s * 0.06
    let hPinGap = chipW / 4
    for i in 1...3 {
        let px = chipX + hPinGap * CGFloat(i) - hPinW / 2
        // Bottom pins
        ctx.fill(CGRect(x: px, y: chipY - hPinH, width: hPinW, height: hPinH))
        // Top pins
        ctx.fill(CGRect(x: px, y: chipY + chipH, width: hPinW, height: hPinH))
    }

    // Pulse/heartbeat line across the chip
    let pulseY = s * 0.52
    let pulseStartX = chipX + s * 0.04
    let pulseEndX = chipX + chipW - s * 0.04
    let pulseW = pulseEndX - pulseStartX

    ctx.setStrokeColor(CGColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1.0))
    ctx.setLineWidth(s * 0.018)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    ctx.beginPath()
    ctx.move(to: CGPoint(x: pulseStartX, y: pulseY))
    // Flat segment
    ctx.addLine(to: CGPoint(x: pulseStartX + pulseW * 0.25, y: pulseY))
    // Spike down
    ctx.addLine(to: CGPoint(x: pulseStartX + pulseW * 0.35, y: pulseY - s * 0.08))
    // Spike up (big peak)
    ctx.addLine(to: CGPoint(x: pulseStartX + pulseW * 0.45, y: pulseY + s * 0.12))
    // Spike down small
    ctx.addLine(to: CGPoint(x: pulseStartX + pulseW * 0.55, y: pulseY - s * 0.04))
    // Back to baseline
    ctx.addLine(to: CGPoint(x: pulseStartX + pulseW * 0.65, y: pulseY))
    // Flat to end
    ctx.addLine(to: CGPoint(x: pulseEndX, y: pulseY))
    ctx.strokePath()

    // Glow effect: draw pulse again wider and transparent
    ctx.setStrokeColor(CGColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 0.2))
    ctx.setLineWidth(s * 0.05)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: pulseStartX, y: pulseY))
    ctx.addLine(to: CGPoint(x: pulseStartX + pulseW * 0.25, y: pulseY))
    ctx.addLine(to: CGPoint(x: pulseStartX + pulseW * 0.35, y: pulseY - s * 0.08))
    ctx.addLine(to: CGPoint(x: pulseStartX + pulseW * 0.45, y: pulseY + s * 0.12))
    ctx.addLine(to: CGPoint(x: pulseStartX + pulseW * 0.55, y: pulseY - s * 0.04))
    ctx.addLine(to: CGPoint(x: pulseStartX + pulseW * 0.65, y: pulseY))
    ctx.addLine(to: CGPoint(x: pulseEndX, y: pulseY))
    ctx.strokePath()

    // "DP" text at bottom
    let textY = s * 0.18
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: s * 0.09, weight: .bold),
        .foregroundColor: NSColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 0.6)
    ]
    let text = NSAttributedString(string: "DevPulse", attributes: attrs)
    let textSize = text.size()
    text.draw(at: NSPoint(x: (s - textSize.width) / 2, y: textY - textSize.height / 2))

    image.unlockFocus()
    return image
}

// Generate all required sizes
let sizes: [(Int, String)] = [
    (1024, "icon_512x512@2x"),
    (512,  "icon_512x512"),
    (512,  "icon_256x256@2x"),
    (256,  "icon_256x256"),
    (256,  "icon_128x128@2x"),
    (128,  "icon_128x128"),
    (64,   "icon_32x32@2x"),
    (32,   "icon_32x32"),
    (32,   "icon_16x16@2x"),
    (16,   "icon_16x16"),
]

let rootDir = FileManager.default.currentDirectoryPath
let iconsetPath = "\(rootDir)/build/DevPulse.iconset"

// Create iconset directory
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (size, name) in sizes {
    let image = drawIcon(size: CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(name)")
        continue
    }
    let path = "\(iconsetPath)/\(name).png"
    try! png.write(to: URL(fileURLWithPath: path))
    print("Generated: \(name).png (\(size)x\(size))")
}

// Convert iconset to icns
let icnsPath = "\(rootDir)/DevPulse.app/Resources/AppIcon.icns"
try? fm.createDirectory(atPath: "\(rootDir)/DevPulse.app/Resources", withIntermediateDirectories: true)

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try! proc.run()
proc.waitUntilExit()

if proc.terminationStatus == 0 {
    print("\nIcon created: \(icnsPath)")
    // Cleanup
    try? fm.removeItem(atPath: iconsetPath)
} else {
    print("iconutil failed with status \(proc.terminationStatus)")
}
