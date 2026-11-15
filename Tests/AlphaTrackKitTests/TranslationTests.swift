import XCTest
@testable import AlphaTrackKit

private func rep(_ hex: String) -> InputReport {
    InputReport(hex.split(separator: " ").map { UInt8($0, radix: 16)! })!
}

final class ReportTranslatorTests: XCTestCase {
    func testOnlineThenButtonPressAndRelease() {
        var t = ReportTranslator()
        let first = t.feed(rep("00 01 00 00 00 00 00 00 00 00 00 00"))
        XCTAssertTrue(first.cameOnline)
        XCTAssertEqual(first.midi, [[0xe0, 0x00, 0x00]]) // initial fader position is reported once
        XCTAssertEqual(t.feed(rep("00 00 00 00 00 00 00 00 00 00 00 00")).midi, [])
        XCTAssertEqual(t.feed(rep("00 00 08 00 00 00 00 00 00 00 00 00")).midi, [[0x90, 0x5e, 0x7f]])
        XCTAssertEqual(t.feed(rep("00 00 08 00 00 00 00 00 00 00 00 00")).midi, [])
        XCTAssertEqual(t.feed(rep("00 00 00 00 00 00 00 00 00 00 00 00")).midi, [[0x90, 0x5e, 0x00]])
    }

    func testTouchIsDebounced() {
        var t = ReportTranslator(touchDebounce: 3)
        _ = t.feed(rep("00 01 00 00 00 00 00 00 00 00 00 00"))
        let touched = rep("00 00 00 00 00 40 00 00 00 00 00 00")
        XCTAssertEqual(t.feed(touched).midi, [])
        XCTAssertEqual(t.feed(touched).midi, [])
        XCTAssertEqual(t.feed(touched).midi, [[0x90, 0x68, 0x7f]])
        // A one-report glitch back to untouched is ignored.
        XCTAssertEqual(t.feed(rep("00 00 00 00 00 00 00 00 00 00 00 00")).midi, [])
        XCTAssertEqual(t.feed(touched).midi, [])
        XCTAssertEqual(t.feed(touched).midi, [])
    }

    func testEncodersAndFader() {
        var t = ReportTranslator()
        _ = t.feed(rep("00 01 00 00 00 00 00 00 00 00 00 00"))
        XCTAssertEqual(t.feed(rep("00 00 00 00 00 00 00 00 01 00 00 00")).midi, [[0xb0, 0x10, 0x01]])
        XCTAssertEqual(t.feed(rep("00 00 00 00 00 00 00 00 00 ff 00 00")).midi, [[0xb0, 0x11, 0x41]])
        XCTAssertEqual(t.feed(rep("00 00 00 00 00 00 00 00 00 00 03 00")).midi, [[0xb0, 0x12, 0x03]])
        // fader to 5 = 0b0000000101 -> yy = (5 & 7) << 4 = 0x50, zz = 5 >> 3 = 0
        XCTAssertEqual(t.feed(rep("00 00 00 00 00 00 01 40 00 00 00 00")).midi, [[0xe0, 0x50, 0x00]])
        XCTAssertEqual(t.feed(rep("00 00 00 00 00 00 01 40 00 00 00 00")).midi, [])
        XCTAssertEqual(t.feed(rep("00 00 00 00 00 00 ff c0 00 00 00 00")).midi, [[0xe0, 0x70, 0x7f]])
    }

    func testStripReportsPositionOnlyWhileTouched() {
        var t = ReportTranslator(touchDebounce: 1)
        _ = t.feed(rep("00 01 00 00 00 00 00 00 00 00 00 00"))
        // byte 11 changes while untouched: nothing.
        XCTAssertEqual(t.feed(rep("00 00 00 00 00 00 00 00 00 00 00 28")).midi, [])
        // one-finger touch at position 5
        XCTAssertEqual(t.feed(rep("00 00 00 00 00 02 00 00 00 00 00 28")).midi,
                       [[0x90, 0x74, 0x7f], [0xe9, 0x00, 0x14]])
        XCTAssertEqual(t.feed(rep("00 00 00 00 00 02 00 00 00 00 00 30")).midi, [[0xe9, 0x00, 0x18]])
        XCTAssertEqual(t.feed(rep("00 00 00 00 00 00 00 00 00 00 00 30")).midi, [[0x90, 0x74, 0x00]])
    }

    func testOfflineReport() {
        var t = ReportTranslator()
        let out = t.feed(rep("00 ff 00 00 00 00 00 00 00 00 00 00"))
        XCTAssertTrue(out.wentOffline)
        XCTAssertEqual(out.midi, [])
    }
}

final class DeviceStateTests: XCTestCase {
    func testLEDNotes() {
        var s = DeviceState()
        XCTAssertEqual(s.apply(midi: [0x90, 0x5f, 0x7f]).usbCommands, [[0, 0, 18, 1, 0, 0, 0, 0]])
        XCTAssertEqual(s.lights, [.record])
        XCTAssertEqual(s.apply(midi: [0x90, 0x5f, 0x00]).usbCommands, [[0, 0, 18, 0, 0, 0, 0, 0]])
        XCTAssertEqual(s.lights, [])
        // notes with no LED (e.g. PLAY) are ignored
        XCTAssertEqual(s.apply(midi: [0x90, 0x5e, 0x7f]).usbCommands, [])
    }

    func testLCDSysExBecomesCellWritesAndUpdatesShadow() {
        var s = DeviceState()
        let r = s.apply(midi: NativeMIDI.lcdSysEx(position: 0x10, text: Array("Hello".utf8)))
        XCTAssertEqual(r.usbCommands, [
            [0x00, 0x01, 4, 0x48, 0x65, 0x6c, 0x6c, 0x00],
            [0x00, 0x01, 5, 0x6f, 0x20, 0x20, 0x20, 0x00],
        ])
        // A later partial write to the same cell keeps the earlier characters.
        let r2 = s.apply(midi: NativeMIDI.lcdSysEx(position: 0x14, text: Array("!".utf8)))
        XCTAssertEqual(r2.usbCommands, [[0x00, 0x01, 5, 0x21, 0x20, 0x20, 0x20, 0x00]])
        XCTAssertEqual(Array(s.lcd[16..<21]), Array("Hell!".utf8))
    }

    func testInquiryAndUnsupported() {
        var s = DeviceState()
        XCTAssertEqual(s.apply(midi: NativeMIDI.deviceInquiry).midiReply, NativeMIDI.deviceInquiryReply)
        XCTAssertNotNil(s.apply(midi: [0xe0, 0x00, 0x40]).unsupported)
        XCTAssertEqual(s.apply(midi: NativeMIDI.forceNativeMode).usbCommands, [])
    }

    func testRestoreAndClear() {
        var s = DeviceState()
        _ = s.apply(midi: [0x90, 0x46, 0x7f]) // shift LED
        let restore = s.restoreCommands()
        XCTAssertEqual(restore.count, 23 + 8)
        XCTAssertTrue(restore.contains([0, 0, 9, 1, 0, 0, 0, 0]))
        XCTAssertTrue(DeviceState.clearCommands().allSatisfy { $0[1] == 1 || $0[3] == 0 })
    }
}

final class MIDIParserTests: XCTestCase {
    func testChannelMessagesAndRunningStatus() {
        var p = MIDIParser()
        XCTAssertEqual(p.feed([0x90, 0x5e, 0x7f, 0x5e, 0x00]), [[0x90, 0x5e, 0x7f], [0x90, 0x5e, 0x00]])
        XCTAssertEqual(p.feed([0xb0, 0x10]), [])
        XCTAssertEqual(p.feed([0x03]), [[0xb0, 0x10, 0x03]])
    }

    func testSysExAcrossPacketsWithRealtimeInside() {
        var p = MIDIParser()
        XCTAssertEqual(p.feed([0xf0, 0x00, 0x01, 0xf8]), [])
        XCTAssertEqual(p.feed([0x40, 0x20, 0x00, 0x10, 0x48, 0xf7, 0x90]), [[0xf0, 0x00, 0x01, 0x40, 0x20, 0x00, 0x10, 0x48, 0xf7]])
        XCTAssertEqual(p.feed([0x08, 0x7f]), [[0x90, 0x08, 0x7f]])
    }
}
