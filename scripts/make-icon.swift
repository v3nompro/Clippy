import AppKit

let image = NSImage(size: NSSize(width: 512, height: 512))
image.lockFocus()
let rect = NSRect(x: 24, y: 24, width: 464, height: 464)
NSColor(calibratedRed: 0.12, green: 0.20, blue: 0.21, alpha: 1).setFill()
NSBezierPath(roundedRect: rect, xRadius: 106, yRadius: 106).fill()
NSColor(calibratedRed: 0.40, green: 0.86, blue: 0.75, alpha: 1).setStroke()
let paper = NSBezierPath(roundedRect: NSRect(x: 151, y: 114, width: 210, height: 278), xRadius: 24, yRadius: 24)
paper.lineWidth = 20
paper.stroke()
NSColor(calibratedRed: 0.40, green: 0.86, blue: 0.75, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 201, y: 361, width: 110, height: 44), xRadius: 16, yRadius: 16).fill()
for y in [210, 266, 322] {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 204, y: y)); line.line(to: NSPoint(x: 308, y: y))
    line.lineWidth = 14; line.lineCapStyle = .round; line.stroke()
}
image.unlockFocus()
let tiff = image.tiffRepresentation!
let output = URL(fileURLWithPath: CommandLine.arguments[1])
// An ICNS container with one 512px PNG (ic09) is supported by macOS and avoids external tools.
let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
var data = Data("icns".utf8)
var length = UInt32(png.count + 16).bigEndian
withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
data.append(Data("ic09".utf8))
length = UInt32(png.count + 8).bigEndian
withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
data.append(png)
try data.write(to: output)
