import XCTest
@testable import Core

final class ArtPaletteTests: XCTestCase {
    private func image(side: Int = 24, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> [UInt8] {
        var bytes: [UInt8] = []
        for y in 0..<side {
            for x in 0..<side {
                let (r, g, b) = pixel(x, y)
                bytes += [r, g, b, 255]
            }
        }
        return bytes
    }

    func testHSVRoundTrip() {
        let colours = [RGB(1, 0, 0), RGB(0, 1, 0), RGB(0, 0, 1), RGB(0.8, 0.4, 0.2), RGB(0.3, 0.3, 0.3)]
        for colour in colours {
            let hsv = colour.hsv
            let back = RGB(hue: hsv.h, saturation: hsv.s, brightness: hsv.v)
            XCTAssertEqual(back.r, colour.r, accuracy: 0.0001)
            XCTAssertEqual(back.g, colour.g, accuracy: 0.0001)
            XCTAssertEqual(back.b, colour.b, accuracy: 0.0001)
        }
    }

    func testRedCoverGivesDarkRedTint() {
        let palette = ArtPalette.derive(rgba: image { _, _ in (220, 40, 30) }, width: 24, height: 24)
        XCTAssertFalse(palette.isNeutral)
        XCTAssertGreaterThan(palette.surfaceDark.r, palette.surfaceDark.g)
        XCTAssertGreaterThan(palette.surfaceDark.r, palette.surfaceDark.b)
        XCTAssertLessThanOrEqual(palette.surfaceDark.hsv.v, 0.2001)   // dark enough for white text
        XCTAssertGreaterThan(palette.surfaceLight.hsv.v, 0.9)         // light enough for dark text
        XCTAssertGreaterThan(palette.label.r, palette.label.b)
    }

    func testToneIsADeepVersionOfTheDominantColour() {
        let palette = ArtPalette.derive(rgba: image { _, _ in (220, 40, 30) }, width: 24, height: 24)
        XCTAssertEqual(palette.tone.hsv.v, 0.36, accuracy: 0.001)   // dark enough for white text
        XCTAssertGreaterThan(palette.tone.r, palette.tone.g)
        XCTAssertGreaterThanOrEqual(palette.tone.hsv.s, 0.35)
        XCTAssertEqual(ArtPalette.neutral.tone, RGB(0.2, 0.2, 0.22))
    }

    func testGreyCoverIsNeutral() {
        let palette = ArtPalette.derive(rgba: image { x, _ in x.isMultiple(of: 2) ? (40, 40, 40) : (200, 200, 200) }, width: 24, height: 24)
        XCTAssertTrue(palette.isNeutral)
        XCTAssertEqual(palette.surfaceDark, ArtPalette.neutral.surfaceDark)
    }

    func testEdgeColourComesFromTheBorder() {
        let bytes = image { x, y in
            (x == 0 || y == 0 || x == 23 || y == 23) ? (0, 0, 255) : (255, 160, 0)
        }
        let palette = ArtPalette.derive(rgba: bytes, width: 24, height: 24)
        XCTAssertEqual(palette.edge, RGB(0, 0, 1))
    }

    func testDominantHueWinsOverSmallAccent() {
        // Mostly green with a small red patch.
        let bytes = image { x, y in (x < 4 && y < 4) ? (230, 20, 20) : (30, 180, 60) }
        let palette = ArtPalette.derive(rgba: bytes, width: 24, height: 24)
        XCTAssertGreaterThan(palette.surfaceDark.g, palette.surfaceDark.r)
    }

    func testTooFewBytesFallsBackToNeutral() {
        XCTAssertEqual(ArtPalette.derive(rgba: [1, 2, 3], width: 24, height: 24), .neutral)
    }
}
