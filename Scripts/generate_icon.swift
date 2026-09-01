#!/usr/bin/env swift
//
//  Generates the Copas app icon and the logo the README shows.
//
//  The mark is a capture viewfinder wrapped around two text bars — the
//  Capture to Text gesture, which is what sets Copas apart from a plain
//  clipboard manager.
//
//  Two variants are drawn. The regular one carries both text bars. Below
//  the 32pt slot they blur into each other, so the compact variant drops
//  to a single bar and thickens every stroke. Variants are chosen by the
//  slot's POINT size, not its pixel size, so 16pt@2x uses the same art as
//  16pt@1x — the way Apple's own icons are tuned per size.
//
//  Run from the repository root:   swift Scripts/generate_icon.swift
//
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

let gradientTop = CGColor(red: 0.329, green: 0.341, blue: 0.941, alpha: 1)    // #5457F0
let gradientBottom = CGColor(red: 0.545, green: 0.361, blue: 0.965, alpha: 1) // #8B5CF6

// MARK: - Variants

enum Variant {
    case regular   // 128pt and up
    case compact   // 32pt and below

    /// Bounds of the viewfinder brackets, in the 1024 reference space
    var frame: CGRect {
        switch self {
        case .regular: return CGRect(x: 252, y: 252, width: 520, height: 520)
        case .compact: return CGRect(x: 232, y: 232, width: 560, height: 560)
        }
    }

    var armLength: CGFloat {
        switch self {
        case .regular: return 165
        case .compact: return 145
        }
    }

    var strokeWidth: CGFloat {
        switch self {
        case .regular: return 64
        case .compact: return 76
        }
    }

    /// Text bars: width, bottom edge, opacity
    var bars: [(width: CGFloat, y: CGFloat, alpha: CGFloat)] {
        switch self {
        case .regular: return [(300, 542, 1.0), (190, 422, 0.75)]
        case .compact: return [(240, 474, 1.0)]
        }
    }

    var barHeight: CGFloat {
        switch self {
        case .regular: return 60
        case .compact: return 76
        }
    }

    var barX: CGFloat {
        switch self {
        case .regular: return 362
        case .compact: return 392
        }
    }
}

// MARK: - Drawing (authored in a 1024×1024 reference space)

func drawIcon(in ctx: CGContext, pixelSize: CGFloat, variant: Variant) {
    let scale = pixelSize / 1024.0
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)

    // The rounded square sits inside the canvas the way macOS icons do,
    // leaving room for the drop shadow.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Shadow first, cast by an opaque copy of the plate. Drawing it under the
    // gradient rather than with it keeps the gradient's own alpha out of the blur.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18),
                  blur: 34,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
    ctx.addPath(platePath)
    ctx.setFillColor(gradientTop)
    ctx.fillPath()
    ctx.restoreGState()

    // Gradient body
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: space,
                                 colors: [gradientTop, gradientBottom] as CFArray,
                                 locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: plate.maxY),
                               end: CGPoint(x: 0, y: plate.minY),
                               options: [])
    }
    // Soft highlight across the top edge
    if let sheen = CGGradient(colorsSpace: space,
                              colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
                                       CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                              locations: [0, 1]) {
        ctx.drawLinearGradient(sheen,
                               start: CGPoint(x: 0, y: plate.maxY),
                               end: CGPoint(x: 0, y: plate.maxY - 420),
                               options: [])
    }
    ctx.restoreGState()

    // MARK: Viewfinder brackets
    let frame = variant.frame
    let arm = variant.armLength

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(variant.strokeWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let corners: [[CGPoint]] = [
        [CGPoint(x: frame.minX, y: frame.maxY - arm),   // top-left
         CGPoint(x: frame.minX, y: frame.maxY),
         CGPoint(x: frame.minX + arm, y: frame.maxY)],
        [CGPoint(x: frame.maxX - arm, y: frame.maxY),   // top-right
         CGPoint(x: frame.maxX, y: frame.maxY),
         CGPoint(x: frame.maxX, y: frame.maxY - arm)],
        [CGPoint(x: frame.minX, y: frame.minY + arm),   // bottom-left
         CGPoint(x: frame.minX, y: frame.minY),
         CGPoint(x: frame.minX + arm, y: frame.minY)],
        [CGPoint(x: frame.maxX - arm, y: frame.minY),   // bottom-right
         CGPoint(x: frame.maxX, y: frame.minY),
         CGPoint(x: frame.maxX, y: frame.minY + arm)]
    ]

    for corner in corners {
        ctx.beginPath()
        ctx.move(to: corner[0])
        ctx.addLine(to: corner[1])
        ctx.addLine(to: corner[2])
        ctx.strokePath()
    }

    // MARK: Captured text
    let barHeight = variant.barHeight
    let barX = variant.barX
    for bar in variant.bars {
        let rect = CGRect(x: barX, y: bar.y, width: bar.width, height: barHeight)
        ctx.addPath(CGPath(roundedRect: rect,
                           cornerWidth: barHeight / 2,
                           cornerHeight: barHeight / 2,
                           transform: nil))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: bar.alpha))
        ctx.fillPath()
    }

    ctx.restoreGState()
}

// MARK: - Output

func renderPNG(size: Int, variant: Variant, to path: String) {
    guard let ctx = CGContext(data: nil,
                              width: size,
                              height: size,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("Could not create bitmap context for \(size)px")
    }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    drawIcon(in: ctx, pixelSize: CGFloat(size), variant: variant)

    guard let image = ctx.makeImage() else { fatalError("Could not render \(size)px") }
    let url = URL(fileURLWithPath: path)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                           UTType.png.identifier as CFString,
                                                           1, nil) else {
        fatalError("Could not open \(path) for writing")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(path)") }
    print("wrote \(path) (\(size)×\(size), \(variant) art)")
}

let iconSet = "Resources/Assets.xcassets/AppIcon.appiconset"
let iconSizes: [(name: String, size: Int, variant: Variant)] = [
    ("icon_16x16.png", 16, .compact), ("icon_16x16@2x.png", 32, .compact),
    ("icon_32x32.png", 32, .compact), ("icon_32x32@2x.png", 64, .compact),
    ("icon_128x128.png", 128, .regular), ("icon_128x128@2x.png", 256, .regular),
    ("icon_256x256.png", 256, .regular), ("icon_256x256@2x.png", 512, .regular),
    ("icon_512x512.png", 512, .regular), ("icon_512x512@2x.png", 1024, .regular)
]

for icon in iconSizes {
    renderPNG(size: icon.size, variant: icon.variant, to: "\(iconSet)/\(icon.name)")
}
renderPNG(size: 512, variant: .regular, to: "docs/logo.png")
