import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let rect = CGRect(x: 64, y: 64, width: 896, height: 896)
    let shape = CGPath(roundedRect: rect, cornerWidth: 200, cornerHeight: 200, transform: nil)
    context.saveGState(); context.addPath(shape); context.clip()
    let colors = [CGColor(red: 0.84, green: 0.94, blue: 0.98, alpha: 1), CGColor(red: 0.96, green: 0.98, blue: 1, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 200, y: 100), end: CGPoint(x: 700, y: 950), options: [])
    context.restoreGState()
    context.addPath(shape); context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8)); context.setLineWidth(6); context.strokePath()
    context.setStrokeColor(CGColor(red: 0.13, green: 0.38, blue: 0.54, alpha: 1)); context.setLineWidth(66); context.setLineCap(.round); context.setLineJoin(.round)
    context.move(to: CGPoint(x: 285, y: 505)); context.addLine(to: CGPoint(x: 442, y: 355)); context.addLine(to: CGPoint(x: 750, y: 685)); context.strokePath()
    let image = context.makeImage()!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16"]
    case 32: names = ["icon_16x16@2x", "icon_32x32"]
    case 64: names = ["icon_32x32@2x"]
    case 128: names = ["icon_128x128"]
    case 256: names = ["icon_128x128@2x", "icon_256x256"]
    case 512: names = ["icon_256x256@2x", "icon_512x512"]
    default: names = ["icon_512x512@2x"]
    }
    for name in names {
        let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(name + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil); CGImageDestinationFinalize(destination)
    }
}
