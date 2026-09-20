import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Trialhead's app icon, drawn in code so it can be tweaked and re-rendered
// without a design tool. Run:
//   swift tools/make-icon.swift <output.png> [--size N] [--style square|rounded|mark]
//
// The mark is a map pin with a medical cross cut out of it: health, and finding
// one near you. A cross alone would say "clinic"; a pin alone said nothing about
// medicine at all.
//
// Styles:
//   square   the app icon as iOS wants it — full bleed, no alpha (default)
//   rounded  the same, corner-masked with transparency, for email and the web
//            where nothing applies iOS's mask for you
//   mark     pin and cross alone in teal on transparency, for a page header
//
// Everything is drawn in a fixed 1024 design space and the canvas is scaled, so
// the tuned constants below stay meaningful at any output size.

let design: CGFloat = 1024
let space = CGColorSpaceCreateDeviceRGB()

enum Style: String { case square, rounded, mark }

var outputSize: CGFloat = 1024
var style: Style = .square
var outputPath: String?

var args = Array(CommandLine.arguments.dropFirst())
while let arg = args.first {
    args.removeFirst()
    switch arg {
    case "--size":
        guard let value = args.first.flatMap(Double.init), value >= 16, value <= 8192 else {
            FileHandle.standardError.write(Data("--size needs a number between 16 and 8192\n".utf8))
            exit(1)
        }
        outputSize = CGFloat(value)
        args.removeFirst()
    case "--style":
        guard let value = args.first.flatMap(Style.init(rawValue:)) else {
            FileHandle.standardError.write(Data("--style must be square, rounded or mark\n".utf8))
            exit(1)
        }
        style = value
        args.removeFirst()
    default:
        outputPath = arg
    }
}

guard let outputPath else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.png> [--size N] [--style square|rounded|mark]\n".utf8))
    exit(1)
}

// `square` keeps the opaque buffer iOS requires of an app icon; the other two
// are meant to sit on someone else's background, so they need alpha.
let opaque = style == .square
let S = design

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

guard let ctx = CGContext(data: nil, width: Int(outputSize), height: Int(outputSize),
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast
                                              : CGImageAlphaInfo.premultipliedLast).rawValue)
else { exit(1) }

ctx.scaleBy(x: outputSize / design, y: outputSize / design)

// iOS masks the app icon itself, so only the standalone versions round their own
// corners. 22.37% of the width is the ratio Apple's own icon grid uses.
if style == .rounded {
    let radius = S * 0.2237
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
}

// Teal rather than blue: it reads as health, and sidesteps looking like either
// a maps app or a certain large health insurer.
let bg = CGGradient(colorsSpace: space,
                    colors: [rgb(0.10, 0.82, 0.74), rgb(0.02, 0.38, 0.45)] as CFArray,
                    locations: [0, 1])!
if style != .mark {
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
}

let glow = CGGradient(colorsSpace: space,
                      colors: [rgb(1, 1, 1, 0.20), rgb(1, 1, 1, 0)] as CFArray,
                      locations: [0, 1])!
if style != .mark {
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: S * 0.26, y: S * 0.80), startRadius: 0,
                           endCenter: CGPoint(x: S * 0.26, y: S * 0.80), endRadius: S * 0.74,
                           options: [])
}

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
if style == .mark {
    // No drop shadow on transparency — it smears grey over whatever the mark is
    // placed on. Teal rather than white, since it has to read on a pale page.
    ctx.setFillColor(rgb(0.03, 0.45, 0.50))
} else {
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 44,
                  color: rgb(0, 0.10, 0.14, 0.34))
    ctx.setFillColor(rgb(1, 1, 1))
}
// One transparency layer, so the shadow falls behind the finished mark instead
// of being drawn once per sub-path.
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.addPath(mark)
ctx.fillPath(using: .evenOdd)
ctx.endTransparencyLayer()
ctx.restoreGState()

guard let image = ctx.makeImage() else { exit(1) }
let out = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path) — \(Int(outputSize))px, \(style.rawValue)")
