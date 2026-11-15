import XCTest
@testable import AlphaTrackKit

final class USBProtocolTests: XCTestCase {
    func testLightCommand() {
        XCTAssertEqual(AlphaTrackUSB.lightCommand(.record, on: true),
                       [0x00, 0x00, 18, 0x01, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(AlphaTrackUSB.lightCommand(.eq, on: false),
                       [0x00, 0x00, 0, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    func testFaderCommand() {
        XCTAssertEqual(AlphaTrackUSB.faderCommand(position: 0), [0, 2, 0x00, 0x00, 0, 0, 0, 0])
        XCTAssertEqual(AlphaTrackUSB.faderCommand(position: 5), [0, 2, 0x01, 0x40, 0, 0, 0, 0])
        XCTAssertEqual(AlphaTrackUSB.faderCommand(position: 1023), [0, 2, 0xff, 0xc0, 0, 0, 0, 0])
        XCTAssertEqual(AlphaTrackUSB.faderCommand(position: 5000), [0, 2, 0xff, 0xc0, 0, 0, 0, 0])
    }

    func testLCDCellPadsAndTruncates() {
        XCTAssertEqual(AlphaTrackUSB.lcdCellCommand(cell: 5, chars: Array("AB".utf8)),
                       [0x00, 0x01, 5, 0x41, 0x42, 0x20, 0x20, 0x00])
        XCTAssertEqual(AlphaTrackUSB.lcdCellCommand(cell: 0, chars: Array("ABCDEF".utf8)),
                       [0x00, 0x01, 0, 0x41, 0x42, 0x43, 0x44, 0x00])
    }

    func testLCDWriteSpanningCellsUsesShadow() {
        // Manual example: "Hello" at position 0x10 = start of bottom line -> cells 4 and 5.
        let shadow = [UInt8](repeating: 0x20, count: 32)
        let cmds = AlphaTrackUSB.lcdCommands(writing: Array("Hello".utf8), at: 0x10, current: shadow)
        XCTAssertEqual(cmds, [
            [0x00, 0x01, 4, 0x48, 0x65, 0x6c, 0x6c, 0x00],
            [0x00, 0x01, 5, 0x6f, 0x20, 0x20, 0x20, 0x00],
        ])
    }
}

final class NativeMIDITests: XCTestCase {
    func testButton() {
        XCTAssertEqual(NativeMIDI.button(.play, down: true), [0x90, 0x5e, 0x7f])
        XCTAssertEqual(NativeMIDI.button(.play, down: false), [0x90, 0x5e, 0x00])
    }

    func testEncoder() {
        XCTAssertEqual(NativeMIDI.encoder(.middle, ticks: 4), [0xb0, 0x11, 0x04])
        XCTAssertEqual(NativeMIDI.encoder(.right, ticks: -3), [0xb0, 0x12, 0x43])
        XCTAssertEqual(NativeMIDI.encoder(.left, ticks: 200), [0xb0, 0x10, 0x3f])
    }

    func testFaderRoundTrip() {
        for p: UInt16 in [0, 1, 7, 8, 511, 1023] {
            let msg = NativeMIDI.fader(position: p)
            XCTAssertEqual(msg[0], 0xe0)
            XCTAssertEqual(msg[1] & 0x8f, 0, "LSBs must sit in bits 4-6")
            XCTAssertEqual(NativeMIDI.faderPosition(from: msg), p)
        }
    }

    func testStrip() {
        XCTAssertEqual(NativeMIDI.strip(position: 31), [0xe9, 0x00, 0x7c])
        XCTAssertEqual(NativeMIDI.strip(position: 1), [0xe9, 0x00, 0x04])
    }

    func testLCDSysExMatchesManualExample() {
        let msg = NativeMIDI.lcdSysEx(position: 0x10, text: Array("Hello".utf8))
        XCTAssertEqual(msg, [0xf0, 0x00, 0x01, 0x40, 0x20, 0x00, 0x10, 0x48, 0x65, 0x6c, 0x6c, 0x6f, 0xf7])
        let parsed = NativeMIDI.parseLCDSysEx(msg)
        XCTAssertEqual(parsed?.position, 0x10)
        XCTAssertEqual(parsed?.text, Array("Hello".utf8))
        XCTAssertNil(NativeMIDI.parseLCDSysEx(NativeMIDI.forceNativeMode))
    }
}
