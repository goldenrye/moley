import Foundation
import CoreGraphics
import ImageIO

// Regenerate from the user's artwork, never from a replacement illustration.
// Usage: swift scripts/generate-icon.swift [source.png] [output.png]
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("Design/Moley-icon-source.png")
let destination = CommandLine.arguments.count > 2
    ? URL(fileURLWithPath: CommandLine.arguments[2])
    : root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/Moley.png")
guard let decoder = CGImageSourceCreateWithURL(source as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(decoder, 0, nil),
      original.width == original.height else {
    fatalError("The source must be a square logo image.")
}

let width = original.width
let height = original.height
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func canvas(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
              bytesPerRow: size * 4, space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
}
let artwork = canvas(width)
artwork.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
let pixels = artwork.data!.assumingMemoryBound(to: UInt8.self)
func color(x: Int, y: Int) -> [UInt8] {
    let index = (y * width + x) * 4
    return Array(UnsafeBufferPointer(start: pixels + index, count: 3))
}
let sky = color(x: width / 2, y: height / 10)
let ground = color(x: width / 2, y: height * 9 / 10)

func matches(_ color: [UInt8], _ background: [UInt8]) -> Bool {
    zip(color, background).allSatisfy { abs(Int($0) - Int($1)) < 4 }
}
func fill(x: Int, y: Int, with background: [UInt8]) {
    for channel in 0..<3 { pixels[(y * width + x) * 4 + channel] = background[channel] }
}

// Extend the existing sky/ground into the presentation's white rounded corners.
// iOS applies its own icon mask. Preserve every interior illustration pixel.
for y in 0..<height where y < height / 4 || y >= height * 3 / 4 {
    let background = y < height / 2 ? sky : ground
    for x in 0..<width {
        if matches(color(x: x, y: y), background) { break }
        fill(x: x, y: y, with: background)
    }
    for x in stride(from: width - 1, through: 0, by: -1) {
        if matches(color(x: x, y: y), background) { break }
        fill(x: x, y: y, with: background)
    }
}

let size = 1024
let bitmap = canvas(size)
bitmap.interpolationQuality = .high
bitmap.draw(artwork.makeImage()!, in: CGRect(x: 0, y: 0, width: size, height: size))
let encoder = CGImageDestinationCreateWithURL(destination as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(encoder, bitmap.makeImage()!, nil)
guard CGImageDestinationFinalize(encoder) else { fatalError("Could not write app icon.") }
if CommandLine.arguments.count <= 2 {
    let logo = root.appendingPathComponent("App/Assets.xcassets/MoleyLogo.imageset/Moley.png")
    try Data(contentsOf: destination).write(to: logo)
}
print("Created opaque 1024x1024 icon at \(destination.path)")
