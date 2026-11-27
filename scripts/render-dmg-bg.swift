#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: render-dmg-bg.swift <output-png-path> [version]\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let versionText = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : ""

let widthPt: CGFloat = 660
let heightPt: CGFloat = 420
let scale: CGFloat = 2
let pixelsWide = Int(widthPt * scale)
let pixelsHigh = Int(heightPt * scale)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelsWide,
    pixelsHigh: pixelsHigh,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to allocate bitmap image rep.\n", stderr)
    exit(1)
}

// 144 DPI metadata so macOS Finder maps 1320x840 px cleanly to 660x420 pt on Retina & standard displays.
rep.size = NSSize(width: widthPt, height: heightPt)

guard let rawContext = NSGraphicsContext(bitmapImageRep: rep) else {
    fputs("Failed to create NSGraphicsContext.\n", stderr)
    exit(1)
}

let cg = rawContext.cgContext
cg.saveGState()
// NSGraphicsContext(bitmapImageRep:) already applies the 2x Retina scale from rep.size.
cg.translateBy(x: 0, y: heightPt)
cg.scaleBy(x: 1, y: -1)

let flippedContext = NSGraphicsContext(cgContext: cg, flipped: true)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = flippedContext

// 1. Background soft gradient
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bgColors = [
    NSColor(calibratedRed: 0.985, green: 0.990, blue: 0.998, alpha: 1.0).cgColor,
    NSColor(calibratedRed: 0.935, green: 0.955, blue: 0.982, alpha: 1.0).cgColor
] as CFArray
if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
    cg.drawLinearGradient(
        gradient,
        start: CGPoint(x: widthPt / 2, y: 0),
        end: CGPoint(x: widthPt / 2, y: heightPt),
        options: []
    )
}

// Subtle top ambient accent glow
let glowColors = [
    NSColor(calibratedRed: 0.24, green: 0.52, blue: 0.98, alpha: 0.08).cgColor,
    NSColor(calibratedRed: 0.24, green: 0.52, blue: 0.98, alpha: 0.0).cgColor
] as CFArray
if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
    cg.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: widthPt / 2, y: 40),
        startRadius: 0,
        endCenter: CGPoint(x: widthPt / 2, y: 40),
        endRadius: 340,
        options: [.drawsBeforeStartLocation]
    )
}

func drawCenteredText(
    _ text: String,
    y: CGFloat,
    font: NSFont,
    color: NSColor
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    let size = str.size()
    let rect = NSRect(x: 24, y: y, width: widthPt - 48, height: ceil(size.height) + 4)
    str.draw(in: rect)
}

// 2. Top header
let titleString = versionText.isEmpty ? "安装 MakeTools" : "安装 MakeTools \(versionText)"
drawCenteredText(
    titleString,
    y: 34,
    font: .systemFont(ofSize: 24, weight: .bold),
    color: NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.17, alpha: 1.0)
)
drawCenteredText(
    "将左侧 MakeTools 拖入右侧「应用程序」文件夹即可完成安装",
    y: 68,
    font: .systemFont(ofSize: 13.5, weight: .regular),
    color: NSColor(calibratedRed: 0.34, green: 0.40, blue: 0.49, alpha: 1.0)
)

// 3. Left & right visual card pedestals aligned to Finder icons at (178, 224) and (482, 224)
let leftCard = NSRect(x: 94, y: 140, width: 168, height: 184)
let rightCard = NSRect(x: 398, y: 140, width: 168, height: 184)

// Left card (clean solid pedestal)
cg.saveGState()
cg.setShadow(
    offset: CGSize(width: 0, height: 6),
    blur: 18,
    color: NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.28, alpha: 0.07).cgColor
)
let leftPath = NSBezierPath(roundedRect: leftCard, xRadius: 22, yRadius: 22)
NSColor(calibratedWhite: 1.0, alpha: 0.86).setFill()
leftPath.fill()
cg.restoreGState()

NSColor(calibratedRed: 0.80, green: 0.85, blue: 0.91, alpha: 0.9).setStroke()
leftPath.lineWidth = 1.2
leftPath.stroke()

// Right card (accent dashed drop target)
let rightPath = NSBezierPath(roundedRect: rightCard, xRadius: 22, yRadius: 22)
NSColor(calibratedRed: 0.20, green: 0.49, blue: 0.96, alpha: 0.065).setFill()
rightPath.fill()

NSColor(calibratedRed: 0.24, green: 0.53, blue: 0.96, alpha: 0.55).setStroke()
rightPath.lineWidth = 1.75
let dash: [CGFloat] = [6, 5]
rightPath.setLineDash(dash, count: dash.count, phase: 0)
rightPath.stroke()

// 4. Center directional drag arrow between (262..398) centered at y = 224
let arrowY: CGFloat = 224
let arrowStartX: CGFloat = 286
let arrowEndX: CGFloat = 374
let accentBlue = NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.96, alpha: 1.0)

// Soft circular halo behind arrow
let badgeRect = NSRect(x: 304, y: arrowY - 24, width: 52, height: 48)
let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 16, yRadius: 16)
NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.96, alpha: 0.11).setFill()
badgePath.fill()

// Arrow shaft + chevron head
let arrowPath = NSBezierPath()
arrowPath.move(to: NSPoint(x: arrowStartX + 24, y: arrowY))
arrowPath.line(to: NSPoint(x: arrowEndX - 24, y: arrowY))
arrowPath.move(to: NSPoint(x: arrowEndX - 35, y: arrowY - 10))
arrowPath.line(to: NSPoint(x: arrowEndX - 24, y: arrowY))
arrowPath.line(to: NSPoint(x: arrowEndX - 35, y: arrowY + 10))
arrowPath.lineWidth = 3.2
arrowPath.lineCapStyle = .round
arrowPath.lineJoinStyle = .round
accentBlue.setStroke()
arrowPath.stroke()

// Subtle animated-style trailing dots to the left of the badge
for (idx, alpha) in [0.22, 0.40, 0.60].enumerated() {
    let dotX = arrowStartX - 6 + CGFloat(idx) * 8
    let dotRect = NSRect(x: dotX, y: arrowY - 2.2, width: 4.4, height: 4.4)
    NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.96, alpha: alpha).setFill()
    NSBezierPath(ovalIn: dotRect).fill()
}

let dragLabelParagraph = NSMutableParagraphStyle()
dragLabelParagraph.alignment = .center
let dragLabel = NSAttributedString(
    string: "拖入安装",
    attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
        .foregroundColor: accentBlue,
        .paragraphStyle: dragLabelParagraph
    ]
)
dragLabel.draw(in: NSRect(x: 274, y: arrowY + 32, width: 112, height: 20))

// 5. Bottom guidance caption
drawCenteredText(
    "安装后从「应用程序」打开 MakeTools，即可启用灵动岛与访达 Markdown 预览",
    y: 368,
    font: .systemFont(ofSize: 11.5, weight: .regular),
    color: NSColor(calibratedRed: 0.43, green: 0.48, blue: 0.56, alpha: 1.0)
)

NSGraphicsContext.restoreGraphicsState()
cg.restoreGState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG.\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL)
