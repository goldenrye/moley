import Foundation
import CoreGraphics
import ImageIO

// Draws the Moley app icon: a brown mole with a headlamp helmet peeking out of
// its burrow on a sunny day. Vector drawing keeps it sharp at every icon size.
// The earlier artwork is kept in Design/Moley-icon-source.png for reference.
// Usage: swift scripts/generate-icon.swift [output.png]
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let destination = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/Moley.png")

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Draw top-down so coordinates read like the picture.
c.translateBy(x: 0, y: CGFloat(size))
c.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let ink = rgb(0x1C1A33)
func shape(_ path: CGPath, fill: CGColor, outline: Bool = true) {
    c.addPath(path); c.setFillColor(fill); c.fillPath()
    guard outline else { return }
    c.addPath(path); c.setStrokeColor(ink); c.setLineWidth(22); c.setLineJoin(.round); c.strokePath()
}
func ellipse(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height), transform: nil)
}
func dot(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: CGColor) {
    c.setFillColor(color)
    c.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
}

// Sky with two clouds.
let sky = CGGradient(colorsSpace: space, colors: [rgb(0x5CC2FF), rgb(0xBFEBFF)] as CFArray, locations: [0, 1])!
c.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: 760),
                     options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
for (x, y, width) in [(170.0, 170.0, 220.0), (860, 330, 180)] as [(CGFloat, CGFloat, CGFloat)] {
    c.setFillColor(rgb(0xFFFFFF, 0.95))
    c.fillEllipse(in: CGRect(x: x - width / 2, y: y - 30, width: width, height: 60))
    c.fillEllipse(in: CGRect(x: x - width / 4, y: y - 62, width: width / 2, height: 80))
}

// Grassy hill and the back of the burrow.
let hill = CGMutablePath()
hill.move(to: CGPoint(x: 0, y: 790))
hill.addQuadCurve(to: CGPoint(x: 1024, y: 790), control: CGPoint(x: 512, y: 720))
hill.addLine(to: CGPoint(x: 1024, y: 1024))
hill.addLine(to: CGPoint(x: 0, y: 1024))
hill.closeSubpath()
c.addPath(hill); c.setFillColor(rgb(0x6CC24A)); c.fillPath()
let burrowY: CGFloat = 850
let rim = rgb(0x8A5A3C)
shape(ellipse(512, burrowY, 880, 200), fill: rim, outline: false)
shape(ellipse(512, burrowY, 740, 140), fill: rgb(0x1B1316), outline: false)

// The mole, drawn 15 points lower than its design grid.
c.saveGState()
c.translateBy(x: 0, y: 15)
c.saveGState()
c.clip(to: CGRect(x: 0, y: -15, width: 1024, height: burrowY))
shape(CGPath(roundedRect: CGRect(x: 222, y: 260, width: 580, height: 900),
             cornerWidth: 270, cornerHeight: 270, transform: nil), fill: rgb(0x9A7563))
shape(ellipse(512, 770, 330, 170), fill: rgb(0xD2B19C), outline: false)
c.restoreGState()

// Miner's helmet with the headlamp.
let dome = CGMutablePath()
dome.move(to: CGPoint(x: 240, y: 345))
dome.addCurve(to: CGPoint(x: 512, y: 90), control1: CGPoint(x: 240, y: 190), control2: CGPoint(x: 360, y: 90))
dome.addCurve(to: CGPoint(x: 784, y: 345), control1: CGPoint(x: 664, y: 90), control2: CGPoint(x: 784, y: 190))
dome.closeSubpath()
shape(dome, fill: rgb(0xFFC93C))
shape(CGPath(roundedRect: CGRect(x: 185, y: 318, width: 654, height: 78),
             cornerWidth: 39, cornerHeight: 39, transform: nil), fill: rgb(0xF2A922))
shape(ellipse(512, 215, 140, 140), fill: rgb(0xFFF3CC))
shape(ellipse(512, 215, 66, 66), fill: rgb(0xFFA02E), outline: false)

// Face: shiny eyes, blush, nose and a small smile.
for x in [400.0, 624.0] as [CGFloat] {
    shape(ellipse(x, 495, 62, 80), fill: ink, outline: false)
    dot(x + 12, 475, 14, rgb(0xFFFFFF))
    dot(x - 10, 515, 6, rgb(0xFFFFFF))
}
for x in [335.0, 689.0] as [CGFloat] {
    shape(ellipse(x, 600, 100, 56), fill: rgb(0xE58AA3, 0.9), outline: false)
}
shape(ellipse(512, 595, 170, 125), fill: rgb(0xFFA9C2))
dot(485, 570, 22, rgb(0xFFD3E0))
c.setStrokeColor(ink); c.setLineWidth(16); c.setLineCap(.round)
c.move(to: CGPoint(x: 480, y: 680))
c.addQuadCurve(to: CGPoint(x: 544, y: 680), control: CGPoint(x: 512, y: 710))
c.strokePath()

// Paws resting on the rim.
for x in [360.0, 664.0] as [CGFloat] {
    shape(ellipse(x, 830, 190, 112), fill: rgb(0xFFA9C2))
}
c.restoreGState()

// Front lip of the burrow, over the paws.
c.saveGState()
c.clip(to: CGRect(x: 0, y: burrowY + 25, width: 1024, height: 400))
shape(ellipse(512, burrowY, 880, 200), fill: rim, outline: false)
c.restoreGState()

let encoder = CGImageDestinationCreateWithURL(destination as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(encoder, c.makeImage()!, nil)
guard CGImageDestinationFinalize(encoder) else { fatalError("Could not write app icon.") }
if CommandLine.arguments.count <= 1 {
    let logo = root.appendingPathComponent("App/Assets.xcassets/MoleyLogo.imageset/Moley.png")
    try Data(contentsOf: destination).write(to: logo)
}
print("Created opaque 1024x1024 icon at \(destination.path)")
