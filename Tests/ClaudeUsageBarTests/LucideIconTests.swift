import XCTest
import AppKit
@testable import ClaudeUsageBar

final class LucideIconTests: XCTestCase {

    // A single horizontal line "M2 12 H22" must produce a non-empty path
    // whose bounding box spans x 2->22 at y 12.
    func testPathReaderLinePrimitive() {
        let path = LucideIcon.cgPath(fromElements: [.path("M2 12 H22")])
        XCTAssertFalse(path.isEmpty)
        let box = path.boundingBox
        XCTAssertEqual(box.minX, 2, accuracy: 0.01)
        XCTAssertEqual(box.maxX, 22, accuracy: 0.01)
        XCTAssertEqual(box.minY, 12, accuracy: 0.01)
    }

    // Relative arc (circular) should advance the current point and add geometry.
    func testPathReaderHandlesCircularArc() {
        // Quarter circle radius 9 from (3,12) — Lucide refresh-style arc.
        let path = LucideIcon.cgPath(fromElements: [.path("M3 12a9 9 0 0 1 9-9")])
        XCTAssertFalse(path.isEmpty)
        XCTAssertGreaterThan(path.boundingBox.width, 0)
        XCTAssertGreaterThan(path.boundingBox.height, 0)
    }

    func testCircleAndRectPrimitives() {
        let circle = LucideIcon.cgPath(fromElements: [.circle(cx: 12, cy: 12, r: 10)])
        XCTAssertEqual(circle.boundingBox.width, 20, accuracy: 0.01)
        let rect = LucideIcon.cgPath(fromElements: [.rect(x: 3, y: 4, w: 18, h: 18, rx: 2)])
        XCTAssertEqual(rect.boundingBox.width, 18, accuracy: 0.01)
    }

    // Every shipping icon renders to a correctly-sized, non-blank template image.
    func testEveryIconRendersNonBlankTemplate() throws {
        for icon in LucideIcon.allCases {
            let image = icon.image(pointSize: 22)
            XCTAssertTrue(image.isTemplate, "\(icon) must be a template image")
            XCTAssertEqual(image.size.width, 22, accuracy: 0.5, "\(icon) width")
            XCTAssertEqual(image.size.height, 22, accuracy: 0.5, "\(icon) height")

            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 44,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: CGRect(x: 0, y: 0, width: 44, height: 44))
            NSGraphicsContext.restoreGraphicsState()

            var opaquePixels = 0
            for x in 0..<44 { for y in 0..<44 {
                if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.01 { opaquePixels += 1 }
            } }
            XCTAssertGreaterThan(opaquePixels, 0, "\(icon) rendered blank")
        }
    }
}
