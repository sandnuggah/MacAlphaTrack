import XCTest
@testable import AlphaTrackKit

final class IdleScreenTests: XCTestCase {
    private func report(mask: UInt32 = 0, fader: Int = 0, enc: [Int8] = [0, 0, 0], strip: Int = 0) -> InputReport {
        InputReport([0, 0,
                     UInt8(mask >> 24), UInt8(mask >> 16 & 0xff), UInt8(mask >> 8 & 0xff), UInt8(mask & 0xff),
                     UInt8(fader >> 2), UInt8((fader & 3) << 6),
                     UInt8(bitPattern: enc[0]), UInt8(bitPattern: enc[1]), UInt8(bitPattern: enc[2]),
                     UInt8(strip << 3)])!
    }
    private func top(_ f: IdleScreen.Frame) -> String { String(decoding: f.lcd[0..<16], as: UTF8.self) }
    private func bottom(_ f: IdleScreen.Frame) -> [UInt8] { Array(f.lcd[16..<32]) }

    private let B = IdleScreen.block, H = IdleScreen.hollow, D = IdleScreen.dot

    func testRowsAvoidTheLinedCustomGlyphs() {
        var rows = [IdleScreen.markerRow(at: 3), IdleScreen.cometRow(at: 5, movingRight: true)]
        for level in IdleScreen.barRange { rows.append(IdleScreen.barRow(level: level)) }
        for row in rows {
            XCTAssertEqual(row.count, 16)
            XCTAssertFalse(row.contains { $0 < 0x08 })
        }
    }

    func testCometRow() {
        XCTAssertEqual(Array(IdleScreen.cometRow(at: 0, movingRight: true).prefix(3)), [B, 0x20, 0x20])
        XCTAssertEqual(Array(IdleScreen.cometRow(at: 2, movingRight: true).prefix(4)), [D, H, B, 0x20])
        XCTAssertEqual(Array(IdleScreen.cometRow(at: 15, movingRight: false).suffix(3)), [0x20, 0x20, B])
        XCTAssertEqual(Array(IdleScreen.cometRow(at: 13, movingRight: false).suffix(4)), [0x20, B, H, D])
    }

    func testMarkerAndBarRows() {
        XCTAssertEqual(Array(IdleScreen.markerRow(at: 1).prefix(3)), [D, B, D])
        XCTAssertEqual(IdleScreen.markerRow(at: 99).last, B)
        XCTAssertEqual(IdleScreen.barRow(level: 0), [UInt8](repeating: D, count: 16))
        XCTAssertEqual(Array(IdleScreen.barRow(level: 3).prefix(3)), [B, H, D])
        XCTAssertEqual(IdleScreen.barRow(level: 32), [UInt8](repeating: B, count: 16))
    }

    func testSweepMovesAndBounces() {
        var s = IdleScreen()
        let f0 = s.feed(report(), at: 100)
        XCTAssertEqual(top(f0), " MacAlphaTrack  ")
        XCTAssertEqual(bottom(f0), IdleScreen.cometRow(at: 0, movingRight: true))
        XCTAssertEqual(bottom(s.feed(report(), at: 100.401)), IdleScreen.cometRow(at: 4, movingRight: true))
        XCTAssertEqual(bottom(s.feed(report(), at: 101.501)), IdleScreen.cometRow(at: 15, movingRight: false))
        XCTAssertEqual(bottom(s.feed(report(), at: 101.801)), IdleScreen.cometRow(at: 12, movingRight: false))
        XCTAssertEqual(bottom(s.feed(report(), at: 103.001)), IdleScreen.cometRow(at: 0, movingRight: true))
        XCTAssertTrue(f0.lights.isEmpty)
        XCTAssertNil(f0.faderSetpoint)
    }

    func testFaderMoveShowsLevelAndEchoesSetpoint() {
        var s = IdleScreen()
        _ = s.feed(report(fader: 0), at: 0)
        let f = s.feed(report(fader: 1023), at: 0.008)
        XCTAssertEqual(f.faderSetpoint, 1023)
        XCTAssertEqual(top(f), "Fader       100%")
        XCTAssertEqual(bottom(f), IdleScreen.barRow(level: 32))
        // Holding still: no new setpoint, playground stays, then the sweep returns.
        let still = s.feed(report(fader: 1023), at: 1)
        XCTAssertNil(still.faderSetpoint)
        XCTAssertEqual(top(still), "Fader       100%")
        XCTAssertEqual(top(s.feed(report(fader: 1023), at: 4.1)), " MacAlphaTrack  ")
    }

    func testFirstReportIsNotAFaderMove() {
        var s = IdleScreen()
        let f = s.feed(report(fader: 600), at: 0)
        XCTAssertNil(f.faderSetpoint)
        XCTAssertEqual(top(f), " MacAlphaTrack  ")
    }

    func testKnobMovesBlockAndPushCentres() {
        var s = IdleScreen()
        _ = s.feed(report(), at: 0)
        XCTAssertEqual(bottom(s.feed(report(enc: [0, 2, 0]), at: 0.1)), IdleScreen.markerRow(at: 8))
        let f = s.feed(report(enc: [0, 1, 0]), at: 0.15)
        XCTAssertEqual(top(f), "Middle knob     ")
        XCTAssertEqual(bottom(f), IdleScreen.markerRow(at: 9))
        _ = s.feed(report(enc: [0, -100, 0]), at: 0.2)
        XCTAssertEqual(bottom(s.feed(report(), at: 0.3)), IdleScreen.markerRow(at: 0))
        let pushed = s.feed(report(mask: InputReport.Switch.encoderPushMiddle.mask), at: 0.4)
        XCTAssertEqual(bottom(pushed), IdleScreen.markerRow(at: 8))
    }

    func testStripAndButtons() {
        var s = IdleScreen()
        _ = s.feed(report(), at: 0)
        let strip = s.feed(report(mask: InputReport.Switch.stripTouch2.mask, strip: 31), at: 0.1)
        XCTAssertEqual(top(strip), "Touch strip   x2")
        XCTAssertEqual(bottom(strip), IdleScreen.markerRow(at: 15))

        let mute = s.feed(report(mask: InputReport.Switch.mute.mask), at: 0.2)
        XCTAssertEqual(top(mute).trimmingCharacters(in: .whitespaces), "MUTE")
        XCTAssertEqual(mute.lights, [.mute])
        // Held past the hold time: still shown. Released: light off, sweep after the hold.
        XCTAssertEqual(s.feed(report(mask: InputReport.Switch.mute.mask), at: 10).lights, [.mute])
        XCTAssertTrue(s.feed(report(), at: 10.1).lights.isEmpty)
        XCTAssertEqual(top(s.feed(report(), at: 14.2)), " MacAlphaTrack  ")
    }

    func testHoveringTouchBitsDoNotWakeThePlayground() {
        var s = IdleScreen()
        _ = s.feed(report(), at: 0)
        let hover = InputReport.Switch.encoderTouchLeft.mask | InputReport.Switch.faderTouch.mask
        XCTAssertEqual(top(s.feed(report(mask: hover), at: 0.1)), " MacAlphaTrack  ")
    }
}
