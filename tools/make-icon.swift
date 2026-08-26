import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S),
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }

// Background: a diagonal blue → indigo gradient. Deep enough that the white
// mark stays legible at 60pt on a home screen, which is where it actually lives.
let bg = CGGradient(colorsSpace: space,
                    colors: [rgb(0.20, 0.60, 1.00), rgb(0.04, 0.16, 0.68)] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

// A soft light source, top-left, so the flat square has some depth.
let glow = CGGradient(colorsSpace: space,
                      colors: [rgb(1, 1, 1, 0.22), rgb(1, 1, 1, 0)] as CFArray,
                      locations: [0, 1])!
ctx.saveGState()
ctx.drawRadialGradient(glow,
                       startCenter: CGPoint(x: S * 0.26, y: S * 0.80), startRadius: 0,
                       endCenter: CGPoint(x: S * 0.26, y: S * 0.80), endRadius: S * 0.72,
                       options: [])
ctx.restoreGState()

// The mark: a navigation arrow with a notched base — a compass needle read as
// forward motion. One shape, no text, so it survives being shrunk.
func flip(_ y: CGFloat) -> CGFloat { S - y }
let apex   = CGPoint(x: S / 2,  y: flip(258))
let left   = CGPoint(x: 282,    y: flip(784))
let notch  = CGPoint(x: S / 2,  y: flip(640))
let right  = CGPoint(x: 742,    y: flip(784))

let arrow = CGMutablePath()
arrow.move(to: apex)
arrow.addLine(to: right)
arrow.addLine(to: notch)
arrow.addLine(to: left)
arrow.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46,
              color: rgb(0, 0.04, 0.22, 0.35))
// Composite fill and stroke into one layer before the shadow lands, otherwise
// the stroke's own shadow is drawn over the fill and reads as a dark outline
// inside the shape.
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.setFillColor(rgb(1, 1, 1))
ctx.setStrokeColor(rgb(1, 1, 1))
// Stroking the same path with round joins is what softens the points —
// razor-sharp corners look dated and alias badly when scaled down.
ctx.setLineJoin(.round)
ctx.setLineCap(.round)
ctx.setLineWidth(58)
ctx.addPath(arrow)
ctx.drawPath(using: .fillStroke)
ctx.endTransparencyLayer()
ctx.restoreGState()

guard let image = ctx.makeImage() else { exit(1) }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
