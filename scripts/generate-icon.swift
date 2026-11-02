import AppKit

// An original tunnel-arch mark, rendered offline with no remote image service.
let size = 1024
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let background = NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size))
NSGradient(colors: [
    NSColor(red: 0.03, green: 0.17, blue: 0.23, alpha: 1),
    NSColor(red: 0.06, green: 0.44, blue: 0.47, alpha: 1)
])!.draw(in: background, angle: 60)
let arch = NSBezierPath()
arch.move(to: NSPoint(x: 260, y: 280))
arch.line(to: NSPoint(x: 260, y: 500))
arch.curve(to: NSPoint(x: 764, y: 500),
           controlPoint1: NSPoint(x: 260, y: 835),
           controlPoint2: NSPoint(x: 764, y: 835))
arch.line(to: NSPoint(x: 764, y: 280))
arch.lineWidth = 90
arch.lineCapStyle = .round
NSColor(red: 0.82, green: 0.98, blue: 0.91, alpha: 1).setStroke()
arch.stroke()
let route = NSBezierPath()
route.move(to: NSPoint(x: 512, y: 258))
route.line(to: NSPoint(x: 512, y: 506))
route.lineWidth = 52
route.lineCapStyle = .round
NSColor.white.setStroke()
route.stroke()
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: 476, y: 594, width: 72, height: 72)).fill()
NSGraphicsContext.restoreGraphicsState()
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
