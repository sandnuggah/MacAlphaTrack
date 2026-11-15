import XCTest
@testable import AlphaTrackKit

/// Reports below are taken verbatim from the 2026-11-15 hardware sweep (dump.log).
final class InputReportTests: XCTestCase {
    private func report(_ hex: String) -> InputReport {
        let bytes = hex.split(separator: " ").map { UInt8($0, radix: 16)! }
        return InputReport(bytes)!
    }

    func testOnlineAndIdle() {
        let online = report("00 01 00 00 00 00 00 00 00 00 00 00")
        XCTAssertEqual(online.status, .online)
        XCTAssertTrue(online.switchesDown.isEmpty)
        XCTAssertEqual(online.faderPosition, 0)
        let idle = report("00 00 00 00 00 00 00 00 00 00 00 00")
        XCTAssertEqual(idle.status, .event)
    }

    func testTransportAndFunctionButtons() {
        XCTAssertEqual(report("00 00 01 00 00 00 00 00 00 00 00 00").switchesDown, [.rewind])
        XCTAssertEqual(report("00 00 04 00 00 00 00 00 00 00 00 00").switchesDown, [.fastForward])
        XCTAssertEqual(report("00 00 10 00 00 00 00 00 00 00 00 00").switchesDown, [.stop])
        XCTAssertEqual(report("00 00 08 00 00 00 00 00 00 00 00 00").switchesDown, [.play])
        XCTAssertEqual(report("00 00 02 00 00 00 00 00 00 00 00 00").switchesDown, [.record])
        XCTAssertEqual(report("00 00 80 00 00 00 00 00 00 00 00 00").switchesDown, [.trackLeft])
        XCTAssertEqual(report("00 00 00 02 00 00 00 00 00 00 00 00").switchesDown, [.trackRight])
        XCTAssertEqual(report("00 00 00 01 00 00 00 00 00 00 00 00").switchesDown, [.loop])
        XCTAssertEqual(report("00 00 40 00 00 00 00 00 00 00 00 00").switchesDown, [.flip])
        XCTAssertEqual(report("00 00 00 10 00 00 00 00 00 00 00 00").switchesDown, [.f1])
        XCTAssertEqual(report("00 00 00 40 00 00 00 00 00 00 00 00").switchesDown, [.f2])
        XCTAssertEqual(report("00 00 00 20 00 00 00 00 00 00 00 00").switchesDown, [.f3])
        XCTAssertEqual(report("00 00 00 08 00 00 00 00 00 00 00 00").switchesDown, [.f4])
        XCTAssertEqual(report("00 00 00 00 02 00 00 00 00 00 00 00").switchesDown, [.pan])
        XCTAssertEqual(report("00 00 00 00 08 00 00 00 00 00 00 00").switchesDown, [.send])
        XCTAssertEqual(report("00 00 00 00 40 00 00 00 00 00 00 00").switchesDown, [.eq])
        XCTAssertEqual(report("00 00 00 00 04 00 00 00 00 00 00 00").switchesDown, [.plugin])
        XCTAssertEqual(report("00 00 00 00 01 00 00 00 00 00 00 00").switchesDown, [.auto])
        XCTAssertEqual(report("00 00 20 00 00 00 00 00 00 00 00 00").switchesDown, [.shift])
        XCTAssertEqual(report("00 00 00 04 00 00 00 00 00 00 00 00").switchesDown, [.mute])
        XCTAssertEqual(report("00 00 00 80 00 00 00 00 00 00 00 00").switchesDown, [.solo])
        XCTAssertEqual(report("00 00 00 00 10 00 00 00 00 00 00 00").switchesDown, [.recArm])
    }

    func testEncoders() {
        let touchLeftTick = report("00 00 00 00 00 08 00 00 01 00 00 00")
        XCTAssertEqual(touchLeftTick.switchesDown, [.encoderTouchLeft])
        XCTAssertEqual(touchLeftTick.encoderDeltas, [1, 0, 0])
        XCTAssertEqual(report("00 00 00 00 00 10 00 00 00 01 00 00").encoderDeltas, [0, 1, 0])
        XCTAssertEqual(report("00 00 00 00 00 20 00 00 00 00 01 00").encoderDeltas, [0, 0, 1])
        XCTAssertEqual(report("00 00 00 00 00 09 00 00 00 00 00 00").switchesDown, [.encoderPushLeft, .encoderTouchLeft])
        XCTAssertEqual(report("00 00 00 00 80 10 00 00 00 00 00 00").switchesDown, [.encoderTouchMiddle, .encoderPushMiddle])
        XCTAssertEqual(report("00 00 00 00 20 20 00 00 00 00 00 00").switchesDown, [.encoderTouchRight, .encoderPushRight])
    }

    func testFader() {
        let touched = report("00 00 00 00 00 40 00 00 00 00 00 00")
        XCTAssertEqual(touched.switchesDown, [.faderTouch])
        XCTAssertEqual(touched.faderPosition, 0)
        XCTAssertEqual(report("00 00 00 00 00 40 01 40 00 00 00 00").faderPosition, 5)
        XCTAssertEqual(report("00 00 00 00 00 40 04 c0 00 00 00 00").faderPosition, 19)
        XCTAssertEqual(report("00 00 00 00 00 40 80 00 00 00 00 00").faderPosition, 512)
        XCTAssertEqual(report("00 00 00 00 00 00 ff c0 00 00 00 00").faderPosition, 1023)
    }

    func testStripFromFollowUpSweep() {
        let one = report("00 00 00 00 00 02 00 00 00 00 00 28")
        XCTAssertEqual(one.switchesDown, [.stripTouch1])
        XCTAssertEqual(one.stripPosition, 5)
        let two = report("00 00 00 00 00 04 00 00 00 00 00 e0")
        XCTAssertEqual(two.switchesDown, [.stripTouch2])
        XCTAssertEqual(two.stripPosition, 28)
        XCTAssertEqual(report("00 00 00 00 00 02 00 00 00 00 00 f8").stripPosition, 31)
    }

    func testCounterClockwiseEncoderIsSigned() {
        XCTAssertEqual(report("00 00 00 00 00 08 00 40 ff 00 00 e0").encoderDeltas, [-1, 0, 0])
        XCTAssertEqual(report("00 00 00 00 00 10 00 00 00 ff 00 e0").encoderDeltas, [0, -1, 0])
        XCTAssertEqual(report("00 00 00 00 00 38 00 00 00 00 ff e0").encoderDeltas, [0, 0, -1])
    }

    func testUnknownBitsAreReported() {
        XCTAssertEqual(report("00 00 00 00 00 80 00 00 00 00 00 00").unknownBits, [7])
        XCTAssertEqual(report("00 00 08 00 00 00 00 00 00 00 00 00").unknownBits, [])
    }

    func testEverySwitchHasDistinctBitAndNote() {
        let bits = InputReport.Switch.allCases.map(\.rawValue)
        XCTAssertEqual(Set(bits).count, bits.count)
        let notes = InputReport.Switch.allCases.map(\.note)
        XCTAssertEqual(Set(notes).count, notes.count)
    }
}
