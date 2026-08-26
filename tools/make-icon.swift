import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Trialhead's app icon, drawn in code so it can be tweaked and re-rendered
// without a design tool. Run:
//   swift tools/make-icon.swift <output.png>
//
// The mark is a map pin with a medical cross cut out of it: health, and finding
// one near you. A cross alone would say "clinic"; a pin alone said nothing about
// medicine at all.

let S: CGFloat = 1024
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S),
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }

// Teal rather than blue: it reads as health, and sidesteps looking like either
// a maps app or a certain large health insurer.
let bg = CGGradient(colorsSpace: space,
                    colors: [rgb(0.10, 0.82, 0.74), rgb(0.02, 0.38, 0.45)] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

let glow = CGGradient(colorsSpace: space,
                      colors: [rgb(1, 1, 1, 0.20), rgb(1, 1, 1, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow,
                       startCenter: CGPoint(x: S * 0.26, y: S * 0.80), startRadius: 0,
                       endCenter: CGPoint(x: S * 0.26, y: S * 0.80), endRadius: S * 0.74,
                       options: [])

func flip(_ y: CGFloat) -> CGFloat { S - y }

// MARK: Pin outline — a circle joined to a point by its two tangent lines.
let head = CGPoint(x: S / 2, y: flip(414))
let radius: CGFloat = 238
let tip = CGPoint(x: S / 2, y: flip(878))

let span = head.y - tip.y                       // centre to tip
let phi = acos(radius / span)                   // angle from the centre-tip axis
                                                // to each tangent point
let axis = -CGFloat.pi / 2                      // centre → tip points straight down
let rightTangent = axis + phi
let leftTangent = axis - phi

let pin = CGMutablePath()
pin.move(to: tip)
pin.addLine(to: CGPoint(x: head.x + radius * cos(rightTangent),
                        y: head.y + radius * sin(rightTangent)))
// Sweep the long way over the top of the head, back round to the other tangent.
pin.addArc(center: head, radius: radius,
           startAngle: rightTangent, endAngle: leftTangent + 2 * .pi,
           clockwise: false)
pin.closeSubpath()

// MARK: Cross — one closed twelve-point outline, so an even-odd fill punches it
// cleanly out of the pin rather than cancelling itself where arms overlap.
// Generous relative to the pin head: at home-screen size the cross is the
// detail carrying the meaning, and a dainty one just reads as a dot.
let arm: CGFloat = 150      // half length
let thick: CGFloat = 52     // half thickness
let crossPoints: [(CGFloat, CGFloat)] = [
    (thick, thick), (arm, thick), (arm, -thick), (thick, -thick),
    (thick, -arm), (-thick, -arm), (-thick, -thick), (-arm, -thick),
    (-arm, thick), (-thick, thick), (-thick, arm), (thick, arm),
]
let cross = CGMutablePath()
for (index, point) in crossPoints.enumerated() {
    let at = CGPoint(x: head.x + point.0, y: head.y + point.1)
    index == 0 ? cross.move(to: at) : cross.addLine(to: at)
}
cross.closeSubpath()

let mark = CGMutablePath()
mark.addPath(pin)
mark.addPath(cross)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 44,
              color: rgb(0, 0.10, 0.14, 0.34))
// One transparency layer, so the shadow falls behind the finished mark instead
// of being drawn once per sub-path.
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.setFillColor(rgb(1, 1, 1))
ctx.addPath(mark)
ctx.fillPath(using: .evenOdd)
ctx.endTransparencyLayer()
ctx.restoreGState()

guard let image = ctx.makeImage() else { exit(1) }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
