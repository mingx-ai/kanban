// Regenerate with `xcrun swift macOS/GenerateIcon.swift /tmp/AppIcon.iconset`
// followed by `iconutil -c icns /tmp/AppIcon.iconset -o macOS/AppIcon.icns`.
import CoreGraphics
import Foundation
import ImageIO

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: height),
           cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(pixels: Int, output: URL) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                              bytesPerRow: pixels * 4, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)
    let plate = roundedRect(78, 90, 868, 852, 196)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 17 * scale,
                  color: CGColor(srgbRed: 0.02, green: 0.13, blue: 0.35, alpha: 0.24))
    ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.36, blue: 0.79, alpha: 1))
    ctx.addPath(plate)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.addPath(plate)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(srgbRed: 0.12, green: 0.64, blue: 0.98, alpha: 1),
        CGColor(srgbRed: 0.03, green: 0.39, blue: 0.82, alpha: 1),
        CGColor(srgbRed: 0.035, green: 0.27, blue: 0.67, alpha: 1)
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 148, y: 916), end: CGPoint(x: 825, y: 88),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    func fill(_ path: CGPath, white: CGFloat, alpha: CGFloat) {
        ctx.setFillColor(red: white, green: white, blue: 1, alpha: alpha)
        ctx.addPath(path)
        ctx.fillPath()
    }

    // Three lanes share a top edge. The stepped stacks remain legible in the Dock.
    for (column, count) in [3, 2, 1].enumerated() {
        let x = 200 + CGFloat(column) * 217
        fill(roundedRect(x, 252, 190, 512, 37), white: 0.88, alpha: 0.18)
        fill(roundedRect(x + 20, 672, 150, 56, 19), white: 1, alpha: 0.98)
        for index in 0..<count {
            fill(roundedRect(x + 20, 535 - CGFloat(index) * 117, 150, 94, 18),
                 white: 0.97, alpha: index == 0 ? 0.96 : 0.79)
        }
    }
    guard let image = ctx.makeImage(),
          let writer = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(writer, image, nil)
    guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: GenerateIcon.swift output.iconset\n".utf8))
    exit(64)
}
let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let suffix = density == 2 ? "@2x" : ""
        let name = "icon_\(points)x\(points)\(suffix).png"
        try drawIcon(pixels: points * density, output: iconset.appendingPathComponent(name))
    }
}
