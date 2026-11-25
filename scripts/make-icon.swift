import AppKit

// Generates the macOS app icon set. Run: swift scripts/make-icon.swift

let output = URL(fileURLWithPath: "Lingo/Resources/Assets.xcassets/AppIcon.appiconset")
let base: CGFloat = 1024

func render(size: CGFloat) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let scale = size / base
    context.cgContext.scaleBy(x: scale, y: scale)

    let bounds = NSRect(x: 44, y: 44, width: 936, height: 936)
    let path = NSBezierPath(roundedRect: bounds, xRadius: 210, yRadius: 210)

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.24, green: 0.26, blue: 0.36, alpha: 1),
        NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1)
    ])
    gradient?.draw(in: path, angle: -90)

    NSColor.white.withAlphaComponent(0.08).setStroke()
    path.lineWidth = 3
    path.stroke()

    let style = NSMutableParagraphStyle()
    style.alignment = .center

    let latin = NSAttributedString(string: "A", attributes: [
        .font: NSFont.systemFont(ofSize: 470, weight: .semibold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: style
    ])
    latin.draw(in: NSRect(x: 70, y: 250, width: 400, height: 520))

    let cjk = NSAttributedString(string: "文", attributes: [
        .font: NSFont(name: "PingFangSC-Semibold", size: 430)
            ?? NSFont.systemFont(ofSize: 430, weight: .semibold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        .paragraphStyle: style
    ])
    cjk.draw(in: NSRect(x: 540, y: 250, width: 400, height: 520))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024)
]

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for variant in variants {
    guard let data = render(size: CGFloat(variant.pixels)) else {
        fatalError("Failed to render \(variant.name)")
    }
    try data.write(to: output.appendingPathComponent("\(variant.name).png"))
}

let contents: [String: Any] = [
    "images": variants.map { variant in
        [
            "filename": "\(variant.name).png",
            "idiom": "mac",
            "scale": variant.name.contains("@2x") ? "2x" : "1x",
            "size": variant.name
                .replacingOccurrences(of: "@2x", with: "")
                .replacingOccurrences(of: "icon_", with: "")
                .replacingOccurrences(of: "x", with: "x")
        ]
    },
    "info": ["author": "xcode", "version": 1]
]

let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))

print("Wrote \(variants.count) icons to \(output.path)")
