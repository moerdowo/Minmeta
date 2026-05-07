// Generates an .iconset folder from a source PNG with the macOS Big Sur+
// squircle mask applied at every size. Pipe through `iconutil -c icns` to get
// the final AppIcon.icns.
//
//   swift Tools/make_icon.swift App/icon-source.png App/AppIcon.iconset
//   iconutil -c icns App/AppIcon.iconset -o App/AppIcon.icns
//
// The mask is a rounded rect with 22.37% corner radius — Apple's actual icon
// shape is a squircle with continuous-curvature corners, but at icon
// resolutions a circular-arc rounded rect is visually indistinguishable.

import Cocoa

guard CommandLine.arguments.count >= 3 else {
    fputs("usage: make_icon <input.png> <outdir>\n", stderr)
    exit(1)
}

let srcPath = CommandLine.arguments[1]
let outDir  = CommandLine.arguments[2]

guard let src = NSImage(contentsOfFile: srcPath) else {
    fputs("could not load \(srcPath)\n", stderr)
    exit(1)
}

struct Spec { let filename: String; let px: Int }
let specs: [Spec] = [
    Spec(filename: "icon_16x16.png",      px: 16),
    Spec(filename: "icon_16x16@2x.png",   px: 32),
    Spec(filename: "icon_32x32.png",      px: 32),
    Spec(filename: "icon_32x32@2x.png",   px: 64),
    Spec(filename: "icon_128x128.png",    px: 128),
    Spec(filename: "icon_128x128@2x.png", px: 256),
    Spec(filename: "icon_256x256.png",    px: 256),
    Spec(filename: "icon_256x256@2x.png", px: 512),
    Spec(filename: "icon_512x512.png",    px: 512),
    Spec(filename: "icon_512x512@2x.png", px: 1024),
]

try? FileManager.default.createDirectory(
    atPath: outDir, withIntermediateDirectories: true)

func render(px: Int) -> Data? {
    let size = NSSize(width: px, height: px)
    // Render into an offscreen bitmap so transparency outside the mask survives.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32)
    else { return nil }
    rep.size = size

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(origin: .zero, size: size)
    NSColor.clear.set()
    rect.fill()

    // macOS squircle ≈ rounded rect with 22.37% corner radius.
    let radius = rect.width * 0.2237
    let mask = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    mask.addClip()

    src.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

    return rep.representation(using: .png, properties: [:])
}

for spec in specs {
    guard let data = render(px: spec.px) else {
        fputs("render failed at \(spec.px)\n", stderr)
        continue
    }
    let outPath = (outDir as NSString).appendingPathComponent(spec.filename)
    do {
        try data.write(to: URL(fileURLWithPath: outPath))
        print("wrote \(outPath) (\(spec.px)px)")
    } catch {
        fputs("write failed for \(outPath): \(error)\n", stderr)
        exit(1)
    }
}
