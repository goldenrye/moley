import Foundation
import CoreGraphics
import ImageIO

// Draws the Moley app icon: a chubby brown mole in a headlamp helmet waving
// both digging hands in warm sunshine, with flowers along the bottom.
// Vector drawing keeps it sharp at every icon size.
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
let ink = rgb(0x2A1E2E)
let line: CGFloat = 20
func fill(_ path: CGPath, _ color: CGColor) {
    c.addPath(path); c.setFillColor(color); c.fillPath()
}
func outline(_ path: CGPath, _ width: CGFloat = line) {
    c.addPath(path); c.setStrokeColor(ink); c.setLineWidth(width)
    c.setLineJoin(.round); c.setLineCap(.round); c.strokePath()
}
func shape(_ path: CGPath, _ color: CGColor) { fill(path, color); outline(path) }
func ellipse(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height), transform: nil)
}
func dot(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: CGColor) {
    fill(ellipse(x, y, 2 * radius, 2 * radius), color)
}

let fur = rgb(0xA0745C)
let belly = rgb(0xE2C2AA)
let pink = rgb(0xFFA6BE)
let white = rgb(0xFFFFFF)

func flower(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ petal: UInt32) {
    c.setStrokeColor(rgb(0x3E8E3A)); c.setLineWidth(radius * 0.28); c.setLineCap(.round)
    c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x, y: y + radius * 3.2)); c.strokePath()
    for i in 0..<5 {
        let angle = CGFloat(i) * 2 * .pi / 5 - .pi / 2
        fill(ellipse(x + cos(angle) * radius * 0.75, y + sin(angle) * radius * 0.75,
                     radius * 1.05, radius * 1.05), rgb(petal))
    }
    dot(x, y, radius * 0.42, rgb(0xFFC93C))
}
func heart(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ color: UInt32) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: x, y: y + s * 0.9))
    path.addCurve(to: CGPoint(x: x - s, y: y - s * 0.1),
                  control1: CGPoint(x: x - s * 0.5, y: y + s * 0.55), control2: CGPoint(x: x - s, y: y + s * 0.3))
    path.addArc(center: CGPoint(x: x - s * 0.5, y: y - s * 0.15), radius: s * 0.5, startAngle: .pi, endAngle: 0, clockwise: false)
    path.addArc(center: CGPoint(x: x + s * 0.5, y: y - s * 0.15), radius: s * 0.5, startAngle: .pi, endAngle: 0, clockwise: false)
    path.addCurve(to: CGPoint(x: x, y: y + s * 0.9),
                  control1: CGPoint(x: x + s, y: y + s * 0.3), control2: CGPoint(x: x + s * 0.5, y: y + s * 0.55))
    fill(path, rgb(color))
}

// Warm sunshine with soft rays.
let sun = CGGradient(colorsSpace: space, colors: [rgb(0xFFF6C8), rgb(0xFFD66B)] as CFArray, locations: [0, 1])!
c.drawRadialGradient(sun, startCenter: CGPoint(x: 512, y: 420), startRadius: 0,
                     endCenter: CGPoint(x: 512, y: 420), endRadius: 720, options: [.drawsAfterEndLocation])
c.saveGState()
c.translateBy(x: 512, y: 420)
for i in 0..<12 {
    c.rotate(by: .pi / 6)
    guard i % 2 == 0 else { continue }
    let ray = CGMutablePath()
    ray.move(to: .zero)
    ray.addLine(to: CGPoint(x: -90, y: -900))
    ray.addLine(to: CGPoint(x: 90, y: -900))
    ray.closeSubpath()
    fill(ray, rgb(0xFFFFFF, 0.22))
}
c.restoreGState()

// The mole, drawn on a 1024 design grid and nudged down so the body meets the grass.
c.saveGState()
c.translateBy(x: -10, y: 90)
c.scaleBy(x: 1.02, y: 1.02)

// Arms raised behind the body, each ending in a wide digging hand.
for (shoulder, hand) in [(330.0, 175.0), (694.0, 849.0)] as [(CGFloat, CGFloat)] {
    let arm = CGMutablePath()
    arm.move(to: CGPoint(x: shoulder, y: 640))
    arm.addQuadCurve(to: CGPoint(x: hand, y: 420),
                     control: CGPoint(x: (shoulder + hand) / 2 + (hand < 512 ? -40 : 40), y: 600))
    c.addPath(arm); c.setStrokeColor(ink); c.setLineWidth(120 + 2 * line); c.setLineCap(.round); c.strokePath()
    c.addPath(arm); c.setStrokeColor(fur); c.setLineWidth(120); c.strokePath()
    let tilt: CGFloat = hand < 512 ? -1 : 1
    for i in -2...2 {
        let angle = -CGFloat.pi / 2 + tilt * 0.25 + CGFloat(i) * 0.42
        let fingerX = hand + cos(angle) * 78, fingerY = 380 + sin(angle) * 78
        let claw = ellipse(fingerX + cos(angle) * 30, fingerY + sin(angle) * 30, 22, 22)
        fill(claw, rgb(0xFFF6EE)); outline(claw, 8)
        shape(ellipse(fingerX, fingerY, 50, 50), pink)
    }
    shape(ellipse(hand, 392, 150, 118), pink)
    dot(hand, 400, 30, rgb(0xFFD0DD))
}

// Head and body as one chubby silhouette.
let head = ellipse(512, 455, 580, 500)
let body = ellipse(512, 720, 520, 440)
outline(head, 2 * line); outline(body, 2 * line)
fill(head, fur); fill(body, fur)
fill(ellipse(512, 760, 320, 260), belly)

// Little helmet with the headlamp, tilted on top of the head.
c.saveGState()
c.translateBy(x: 512, y: 230)
c.rotate(by: -0.12)
let dome = CGMutablePath()
dome.move(to: CGPoint(x: -185, y: 30))
dome.addCurve(to: CGPoint(x: 0, y: -135), control1: CGPoint(x: -185, y: -70), control2: CGPoint(x: -100, y: -135))
dome.addCurve(to: CGPoint(x: 185, y: 30), control1: CGPoint(x: 100, y: -135), control2: CGPoint(x: 185, y: -70))
dome.closeSubpath()
shape(dome, rgb(0xFFC93C))
shape(CGPath(roundedRect: CGRect(x: -230, y: 10, width: 460, height: 56),
             cornerWidth: 28, cornerHeight: 28, transform: nil), rgb(0xF2A922))
shape(ellipse(0, -55, 96, 96), rgb(0xFFF3CC))
dot(0, -55, 24, rgb(0xFFA02E))
c.restoreGState()

// Big shiny eyes, blush, a laughing mouth and a round button nose.
for x in [418.0, 606.0] as [CGFloat] {
    fill(ellipse(x, 445, 84, 104), ink)
    dot(x + 14, 420, 20, white)
    dot(x - 14, 470, 9, white)
}
for x in [340.0, 684.0] as [CGFloat] {
    fill(ellipse(x, 545, 104, 58), rgb(0xF08AA6, 0.75))
}
let mouth = CGMutablePath()
mouth.move(to: CGPoint(x: 455, y: 575))
mouth.addQuadCurve(to: CGPoint(x: 569, y: 575), control: CGPoint(x: 512, y: 590))
mouth.addQuadCurve(to: CGPoint(x: 455, y: 575), control: CGPoint(x: 512, y: 700))
fill(mouth, rgb(0x8E3446))
c.saveGState()
c.addPath(mouth); c.clip()
fill(ellipse(512, 655, 80, 60), rgb(0xFF7F98))
c.restoreGState()
outline(mouth)
shape(ellipse(512, 530, 140, 100), pink)
dot(488, 510, 18, rgb(0xFFD3E0))
c.restoreGState()

// Grass with flowers in front, and two floating hearts.
let grass = CGMutablePath()
grass.move(to: CGPoint(x: 0, y: 900))
grass.addQuadCurve(to: CGPoint(x: 1024, y: 900), control: CGPoint(x: 512, y: 840))
grass.addLine(to: CGPoint(x: 1024, y: 1024))
grass.addLine(to: CGPoint(x: 0, y: 1024))
grass.closeSubpath()
fill(grass, rgb(0x76C75A))
for (x, radius, petal) in [(90.0, 40.0, 0xFFFFFF), (250, 34, 0xFF8FB1), (512, 30, 0xFFFFFF),
                           (770, 34, 0xFF8FB1), (930, 40, 0xFFFFFF)] as [(CGFloat, CGFloat, UInt32)] {
    flower(x, 930, radius, petal)
}
heart(880, 150, 48, 0xFF7F9E)
heart(140, 160, 36, 0xFF9DB4)

let encoder = CGImageDestinationCreateWithURL(destination as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(encoder, c.makeImage()!, nil)
guard CGImageDestinationFinalize(encoder) else { fatalError("Could not write app icon.") }
if CommandLine.arguments.count <= 1 {
    let logo = root.appendingPathComponent("App/Assets.xcassets/MoleyLogo.imageset/Moley.png")
    try Data(contentsOf: destination).write(to: logo)
}
print("Created opaque 1024x1024 icon at \(destination.path)")
