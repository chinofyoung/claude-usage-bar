#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

// MARK: - Configuration

let outputDir = "/Users/chinoyoung/Code/desktop/ClaudeUsageBar/Resources"
let iconsetName = "AppIcon.iconset"
let icnsName = "AppIcon.icns"
let iconsetPath = (outputDir as NSString).appendingPathComponent(iconsetName)
let icnsPath = (outputDir as NSString).appendingPathComponent(icnsName)

// Icon sizes required by macOS iconset format: (point size, scale factor)
let iconSizes: [(Int, Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

// MARK: - Drawing

/// Draw the ClaudeUsageBar gauge icon into the given CGContext at the specified pixel size.
func drawIcon(context ctx: CGContext, size: Int) {
    let s = CGFloat(size)
    let center = CGPoint(x: s / 2, y: s / 2)
    let radius = s * 0.42

    // --- Background circle ---
    // Dark navy/charcoal: #1a1a2e
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -(s * 0.03)),
        blur: s * 0.08,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55)
    )
    ctx.setFillColor(CGColor(red: 0.102, green: 0.102, blue: 0.180, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    ))
    ctx.restoreGState()

    // --- Gauge geometry ---
    // The arc sweeps from 210° to 330° clockwise (bottom-left to bottom-right),
    // covering 300° total, which is standard for a gauge/speedometer.
    // In CoreGraphics, angles are measured from the positive x-axis counter-clockwise.
    // We want the gauge to start at the lower-left (210° from x-axis, which in
    // standard math is 210°, but CGContext uses a flipped Y so we adjust).
    //
    // We'll draw:
    //   - Full track arc: the entire 300° span in a dark gray
    //   - Filled arc: 75% of 300° = 225° in orange-amber gradient

    let trackWidth = s * 0.085
    let trackRadius = radius * 0.78

    // Gauge sweeps 300 degrees. Start at 240° (lower-left), end at 300° (going clockwise).
    // In CGContext (Y-axis up after flip): we flip angles.
    // Standard gauge: start = 225° (bottom-left), end at -45° (bottom-right) going clockwise.
    // CGContext clockwise = false in normal coords, but we work in a flipped context.
    // We'll use explicit radian values in a non-flipped way:
    //   gauge start = 225°, sweeps 300° clockwise visually → end = 225° - 300° = -75° = 285°
    // In CGContext with default (Y-up): clockwise param is false for visual CW in flipped screen.
    //
    // Simplest approach: work with angles directly, use addArc with clockwise = true
    // which in a standard (non-flipped) CG context draws counter-clockwise visually.
    // Since AppKit bitmap contexts are Y-flipped, clockwise=true → visually clockwise.

    let startAngle: CGFloat = (.pi * 5) / 4   // 225°
    let totalAngle: CGFloat = .pi * (5.0 / 3.0) // 300°
    let endAngle: CGFloat = startAngle - totalAngle // sweep clockwise (decreasing angle in Y-up)

    // 75% fill
    let fillFraction: CGFloat = 0.75
    let fillAngle: CGFloat = startAngle - totalAngle * fillFraction

    // --- Track arc (background, dark gray) ---
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 0.25, green: 0.25, blue: 0.30, alpha: 1.0))
    ctx.setLineWidth(trackWidth)
    ctx.setLineCap(.round)
    let trackPath = CGMutablePath()
    trackPath.addArc(
        center: center,
        radius: trackRadius,
        startAngle: startAngle,
        endAngle: endAngle,
        clockwise: true
    )
    ctx.addPath(trackPath)
    ctx.strokePath()
    ctx.restoreGState()

    // --- Filled arc (orange-amber gradient) ---
    // CoreGraphics can't directly stroke with a gradient, so we:
    // 1. Create a stroked path region by stroking to a clipping area
    // 2. Fill with a gradient inside that clip

    ctx.saveGState()

    // Build the fill arc path
    let fillPath = CGMutablePath()
    fillPath.addArc(
        center: center,
        radius: trackRadius,
        startAngle: startAngle,
        endAngle: fillAngle,
        clockwise: true
    )

    // Convert stroke to a fill-able region via path replacement
    ctx.addPath(fillPath)
    ctx.setLineWidth(trackWidth)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()

    // Draw a linear gradient across the filled arc region
    // Colors: #D97706 (amber-600) → #F59E0B (amber-400) → #FCD34D (amber-200)
    let gradientColors: [CGColor] = [
        CGColor(red: 0.851, green: 0.467, blue: 0.024, alpha: 1.0),  // #D97706 deep amber
        CGColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1.0),  // #F59E0B bright amber
        CGColor(red: 0.988, green: 0.827, blue: 0.302, alpha: 1.0),  // #FCD34D light amber/yellow
    ]
    let gradientLocations: [CGFloat] = [0.0, 0.55, 1.0]

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let gradient = CGGradient(
              colorsSpace: colorSpace,
              colors: gradientColors as CFArray,
              locations: gradientLocations
          ) else {
        ctx.restoreGState()
        return
    }

    // Gradient start = bottom-left of arc, end = top of arc region
    let gradStart = CGPoint(x: center.x - trackRadius * 0.7, y: center.y - trackRadius * 0.7)
    let gradEnd   = CGPoint(x: center.x + trackRadius * 0.5, y: center.y + trackRadius * 0.5)
    ctx.drawLinearGradient(gradient, start: gradStart, end: gradEnd, options: [])

    ctx.restoreGState()

    // --- Center text ---
    // Draw "75" in bold white, centered
    // Use CoreText for crisp rendering at all sizes

    let fontSize = s * 0.22
    let font = CTFontCreateWithName("SF Pro Display" as CFString, fontSize, nil)
        ?? CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
    ]

    let attrString = NSAttributedString(string: "75", attributes: attributes)
    let line = CTLineCreateWithAttributedString(attrString)
    let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

    let textX = center.x - textBounds.width / 2 - textBounds.minX
    let textY = center.y - textBounds.height / 2 - textBounds.minY + s * 0.02

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -(s * 0.01)),
        blur: s * 0.025,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6)
    )
    ctx.textPosition = CGPoint(x: textX, y: textY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()

    // --- Small "%" label below the number ---
    let smallFontSize = s * 0.09
    let smallFont = CTFontCreateWithName("SF Pro Display" as CFString, smallFontSize, nil)
        ?? CTFontCreateWithName("HelveticaNeue" as CFString, smallFontSize, nil)

    let smallAttrs: [NSAttributedString.Key: Any] = [
        .font: smallFont,
        .foregroundColor: CGColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 0.9), // amber
    ]
    let pctString = NSAttributedString(string: "%", attributes: smallAttrs)
    let pctLine = CTLineCreateWithAttributedString(pctString)
    let pctBounds = CTLineGetBoundsWithOptions(pctLine, .useOpticalBounds)

    let pctX = center.x - pctBounds.width / 2 - pctBounds.minX
    let pctY = textY - textBounds.height * 0.55

    ctx.saveGState()
    ctx.textPosition = CGPoint(x: pctX, y: pctY)
    CTLineDraw(pctLine, ctx)
    ctx.restoreGState()

    // --- Subtle inner ring highlight ---
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.06))
    ctx.setLineWidth(s * 0.008)
    ctx.strokeEllipse(in: CGRect(
        x: center.x - radius + s * 0.012,
        y: center.y - radius + s * 0.012,
        width: (radius - s * 0.012) * 2,
        height: (radius - s * 0.012) * 2
    ))
    ctx.restoreGState()
}

// MARK: - Image generation

func generateImage(pixelSize: Int) -> NSBitmapImageRep? {
    let size = CGSize(width: pixelSize, height: pixelSize)

    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("Error: Could not create NSBitmapImageRep for size \(pixelSize)")
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
        print("Error: Could not create NSGraphicsContext for size \(pixelSize)")
        return nil
    }
    NSGraphicsContext.current = nsCtx

    guard let cgCtx = nsCtx.cgContext as CGContext? else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }

    // Clear to transparent
    cgCtx.clear(CGRect(origin: .zero, size: size))

    // AppKit bitmap contexts are Y-flipped relative to CoreGraphics default.
    // Flip so that y=0 is at the bottom (standard CG coordinates for our drawing).
    cgCtx.translateBy(x: 0, y: CGFloat(pixelSize))
    cgCtx.scaleBy(x: 1, y: -1)

    drawIcon(context: cgCtx, size: pixelSize)

    NSGraphicsContext.restoreGraphicsState()
    return bitmapRep
}

// MARK: - Main

func main() {
    let fm = FileManager.default

    // Create Resources directory if needed
    if !fm.fileExists(atPath: outputDir) {
        do {
            try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
            print("Created directory: \(outputDir)")
        } catch {
            print("Error creating Resources dir: \(error)")
            exit(1)
        }
    }

    // Remove existing iconset if present
    if fm.fileExists(atPath: iconsetPath) {
        try? fm.removeItem(atPath: iconsetPath)
    }

    // Create iconset directory
    do {
        try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)
    } catch {
        print("Error creating iconset dir: \(error)")
        exit(1)
    }

    // Generate all sizes
    for (points, scale) in iconSizes {
        let pixels = points * scale
        let filename: String
        if scale == 1 {
            filename = "icon_\(points)x\(points).png"
        } else {
            filename = "icon_\(points)x\(points)@2x.png"
        }
        let filePath = (iconsetPath as NSString).appendingPathComponent(filename)

        print("Generating \(filename) (\(pixels)x\(pixels)px)...")

        guard let bitmapRep = generateImage(pixelSize: pixels) else {
            print("  Failed to generate \(filename)")
            continue
        }

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            print("  Failed to encode PNG for \(filename)")
            continue
        }

        do {
            try pngData.write(to: URL(fileURLWithPath: filePath))
            print("  Saved: \(filePath)")
        } catch {
            print("  Error saving \(filename): \(error)")
        }
    }

    // Write Contents.json (required by some tools, optional for iconutil)
    let contentsJSON = """
    {
      "images": [
        { "filename": "icon_16x16.png",      "idiom": "mac", "scale": "1x", "size": "16x16" },
        { "filename": "icon_16x16@2x.png",   "idiom": "mac", "scale": "2x", "size": "16x16" },
        { "filename": "icon_32x32.png",      "idiom": "mac", "scale": "1x", "size": "32x32" },
        { "filename": "icon_32x32@2x.png",   "idiom": "mac", "scale": "2x", "size": "32x32" },
        { "filename": "icon_128x128.png",    "idiom": "mac", "scale": "1x", "size": "128x128" },
        { "filename": "icon_128x128@2x.png", "idiom": "mac", "scale": "2x", "size": "128x128" },
        { "filename": "icon_256x256.png",    "idiom": "mac", "scale": "1x", "size": "256x256" },
        { "filename": "icon_256x256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256" },
        { "filename": "icon_512x512.png",    "idiom": "mac", "scale": "1x", "size": "512x512" },
        { "filename": "icon_512x512@2x.png", "idiom": "mac", "scale": "2x", "size": "512x512" }
      ],
      "info": { "author": "generate_icon.swift", "version": 1 }
    }
    """
    let contentsPath = (iconsetPath as NSString).appendingPathComponent("Contents.json")
    try? contentsJSON.write(toFile: contentsPath, atomically: true, encoding: .utf8)

    // Run iconutil to convert iconset → .icns
    print("\nRunning iconutil...")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", "-o", icnsPath, iconsetPath]

    let errorPipe = Pipe()
    task.standardError = errorPipe

    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        print("Error running iconutil: \(error)")
        exit(1)
    }

    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    if !errorData.isEmpty, let errorStr = String(data: errorData, encoding: .utf8) {
        print("iconutil stderr: \(errorStr)")
    }

    if task.terminationStatus == 0 {
        print("Successfully created: \(icnsPath)")
    } else {
        print("iconutil failed with status: \(task.terminationStatus)")
        exit(1)
    }

    // Clean up iconset directory
    do {
        try fm.removeItem(atPath: iconsetPath)
        print("Cleaned up iconset directory.")
    } catch {
        print("Warning: Could not remove iconset directory: \(error)")
    }

    print("\nDone. AppIcon.icns written to:\n  \(icnsPath)")
}

main()
