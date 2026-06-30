import AppKit
import SwiftUI

/// One drawable element from a Lucide SVG.
enum LucideElement {
    case path(String)                                  // SVG `d` attribute
    case circle(cx: CGFloat, cy: CGFloat, r: CGFloat)
    case rect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, rx: CGFloat)
}

enum LucideIcon: String, CaseIterable {
    case clock, calendar, sparkles, refresh, settings, power, lock

    /// Verbatim Lucide geometry (lucide.dev, ISC license), 24x24 viewBox.
    var elements: [LucideElement] {
        switch self {
        case .clock:
            return [.circle(cx: 12, cy: 12, r: 10), .path("M12 6v6l4 2")]
        case .calendar: // lucide "calendar-days"
            return [
                .path("M8 2v4"), .path("M16 2v4"),
                .rect(x: 3, y: 4, w: 18, h: 18, rx: 2),
                .path("M3 10h18"),
                .path("M8 14h.01"), .path("M12 14h.01"), .path("M16 14h.01"),
                .path("M8 18h.01"), .path("M12 18h.01"), .path("M16 18h.01"),
            ]
        case .sparkles:
            return [
                .path("M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z"),
                .path("M20 2v4"), .path("M22 4h-4"),
                .circle(cx: 4, cy: 20, r: 2),
            ]
        case .refresh: // lucide "refresh-cw"
            return [
                .path("M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"),
                .path("M21 3v5h-5"),
                .path("M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"),
                .path("M8 16H3v5"),
            ]
        case .settings:
            return [
                .path("M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915"),
                .circle(cx: 12, cy: 12, r: 3),
            ]
        case .power:
            return [.path("M12 2v10"), .path("M18.4 6.6a9 9 0 1 1-12.77.04")]
        case .lock:
            return [
                .rect(x: 3, y: 11, w: 18, h: 11, rx: 2),
                .path("M7 11V7a5 5 0 0 1 10 0v4"),
            ]
        }
    }
}

// MARK: - Path Reader

extension LucideIcon {

    /// Builds a CGPath from an array of LucideElement descriptors.
    /// Coordinates are in SVG user space (origin top-left, y-down).
    static func cgPath(fromElements elements: [LucideElement]) -> CGPath {
        let mutable = CGMutablePath()
        for element in elements {
            switch element {
            case .circle(let cx, let cy, let r):
                mutable.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
            case .rect(let x, let y, let w, let h, let rx):
                mutable.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h),
                                       cornerWidth: rx, cornerHeight: rx)
            case .path(let d):
                parseSVGPath(d, into: mutable)
            }
        }
        return mutable
    }

    // MARK: SVG path `d` mini-language parser

    private static func parseSVGPath(_ d: String, into path: CGMutablePath) {
        let tokens = tokenize(d)
        var i = 0
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCmd: Character = "M"

        func nextNum() -> CGFloat? {
            guard i < tokens.count, let v = Double(tokens[i]) else { return nil }
            i += 1
            return CGFloat(v)
        }

        while i < tokens.count {
            let token = tokens[i]
            // If the token is a command letter, consume it; otherwise repeat lastCmd
            let isCmd = token.count == 1 && token.first.map({ $0.isLetter }) == true
            let cmd: Character
            if isCmd {
                cmd = token.first!
                i += 1
                lastCmd = cmd
            } else {
                // Implicit repeat — after M/m implicit is L/l
                switch lastCmd {
                case "M": cmd = "L"; lastCmd = "L"
                case "m": cmd = "l"; lastCmd = "l"
                default: cmd = lastCmd
                }
            }

            switch cmd {
            case "M":
                guard let x = nextNum(), let y = nextNum() else { break }
                current = CGPoint(x: x, y: y)
                subpathStart = current
                path.move(to: current)
                lastCmd = "M"
            case "m":
                guard let dx = nextNum(), let dy = nextNum() else { break }
                current = CGPoint(x: current.x + dx, y: current.y + dy)
                subpathStart = current
                path.move(to: current)
                lastCmd = "m"
            case "L":
                guard let x = nextNum(), let y = nextNum() else { break }
                current = CGPoint(x: x, y: y)
                path.addLine(to: current)
            case "l":
                guard let dx = nextNum(), let dy = nextNum() else { break }
                current = CGPoint(x: current.x + dx, y: current.y + dy)
                path.addLine(to: current)
            case "H":
                guard let x = nextNum() else { break }
                current = CGPoint(x: x, y: current.y)
                path.addLine(to: current)
            case "h":
                guard let dx = nextNum() else { break }
                current = CGPoint(x: current.x + dx, y: current.y)
                path.addLine(to: current)
            case "V":
                guard let y = nextNum() else { break }
                current = CGPoint(x: current.x, y: y)
                path.addLine(to: current)
            case "v":
                guard let dy = nextNum() else { break }
                current = CGPoint(x: current.x, y: current.y + dy)
                path.addLine(to: current)
            case "A":
                guard let rx = nextNum(), let ry = nextNum(),
                      let _ = nextNum(), // xAxisRotation (always 0 for our icons)
                      let laF = nextNum(), let swF = nextNum(),
                      let x = nextNum(), let y = nextNum() else { break }
                let p1 = CGPoint(x: x, y: y)
                addSVGArc(to: path, from: current,
                          rx: rx, ry: ry,
                          largeArc: laF != 0, sweep: swF != 0,
                          to: p1)
                current = p1
            case "a":
                guard let rx = nextNum(), let ry = nextNum(),
                      let _ = nextNum(), // xAxisRotation
                      let laF = nextNum(), let swF = nextNum(),
                      let dx = nextNum(), let dy = nextNum() else { break }
                let p1 = CGPoint(x: current.x + dx, y: current.y + dy)
                addSVGArc(to: path, from: current,
                          rx: rx, ry: ry,
                          largeArc: laF != 0, sweep: swF != 0,
                          to: p1)
                current = p1
            case "Z", "z":
                path.closeSubpath()
                current = subpathStart
            default:
                break
            }
        }
    }

    /// Tokenizes an SVG `d` string into command letters and number strings.
    /// Handles: spaces, commas, sign-separated numbers (e.g. "9-9" → ["9", "-9"]).
    private static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        func flush() {
            let t = current.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { tokens.append(t) }
            current = ""
        }

        for ch in d {
            if ch.isLetter {
                flush()
                tokens.append(String(ch))
            } else if ch == "," || ch == " " || ch == "\t" || ch == "\n" {
                flush()
            } else if ch == "-" {
                flush()
                current = "-"
            } else if ch == "+" {
                flush()
                // unary plus — skip it, the number follows
            } else {
                current.append(ch)
            }
        }
        flush()
        return tokens
    }

    /// Converts SVG endpoint arc parameters to a CGPath arc call.
    /// All icons use rx == ry (circular arcs) and xAxisRotation == 0.
    private static func addSVGArc(to path: CGMutablePath, from p0: CGPoint,
                                  rx: CGFloat, ry: CGFloat, largeArc: Bool,
                                  sweep: Bool, to p1: CGPoint) {
        // rx == ry for all our icons; treat as circular radius r.
        let r = max(rx, ry)
        if r == 0 || p0 == p1 { path.addLine(to: p1); return }
        let mid = CGPoint(x: (p0.x - p1.x) / 2, y: (p0.y - p1.y) / 2)
        var rr = r
        // Ensure radius is large enough.
        let dsq = mid.x * mid.x + mid.y * mid.y
        if dsq > rr * rr { rr = sqrt(dsq) }
        // Center parameterization for circular arc.
        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        let num = max(rr * rr - dsq, 0)
        let coef = sign * sqrt(num / dsq)
        let cxp = coef * mid.y
        let cyp = -coef * mid.x
        let cx = cxp + (p0.x + p1.x) / 2
        let cy = cyp + (p0.y + p1.y) / 2
        let start = atan2(p0.y - cy, p0.x - cx)
        let end   = atan2(p1.y - cy, p1.x - cx)
        // In CGPath's coordinate space we draw before the y-flip, so `clockwise`
        // is the SVG sweep flag inverted (verify visually).
        path.addArc(center: CGPoint(x: cx, y: cy), radius: rr,
                    startAngle: start, endAngle: end, clockwise: !sweep)
    }
}

// MARK: - Rendering

extension LucideIcon {
    /// Renders the glyph centered in a `pointSize` square as a template image.
    func image(pointSize: CGFloat, lineWidthScale: CGFloat = 1) -> NSImage {
        let viewBox: CGFloat = 24
        let strokeViewBox: CGFloat = 2 * lineWidthScale          // Lucide stroke-width
        let path = LucideIcon.cgPath(fromElements: elements)

        let image = NSImage(size: NSSize(width: pointSize, height: pointSize),
                            flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Inset by half the (scaled) stroke so the stroke isn't clipped.
            let scale = pointSize / viewBox
            let strokePts = strokeViewBox * scale
            let inset = strokePts / 2
            let drawScale = (pointSize - strokePts) / viewBox

            // Map SVG space (0..24, y-down) into the y-up image, with inset.
            ctx.translateBy(x: inset, y: pointSize - inset)
            ctx.scaleBy(x: drawScale, y: -drawScale)

            ctx.addPath(path)
            ctx.setLineWidth(strokeViewBox)          // in SVG units; scaled by ctx
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(NSColor.black.cgColor) // template: color is ignored
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
