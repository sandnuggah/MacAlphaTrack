import XCTest
@testable import AlphaTrackKit

final class UMPTests: XCTestCase {
    private func roundTrip(_ msg: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
        var d = UMPDecoder()
        XCTAssertEqual(d.feed(UMP.encode(msg)), [msg], file: file, line: line)
    }

    func testChannelVoice() {
        XCTAssertEqual(UMP.encode([0x90, 0x5e, 0x7f]), [0x2090_5e7f])
        XCTAssertEqual(UMP.encode([0xb0, 0x10, 0x41]), [0x20b0_1041])
        XCTAssertEqual(UMP.encode([0xe0, 0x70, 0x7f]), [0x20e0_707f])
        roundTrip([0x90, 0x5e, 0x7f]); roundTrip([0xe9, 0x00, 0x7c]); roundTrip([0xc0, 0x05])
    }

    func testShortSysExIsOnePacket() {
        // Device inquiry: payload 7e 00 06 01 (4 bytes) -> complete packet
        let words = UMP.encode(NativeMIDI.deviceInquiry)
        XCTAssertEqual(words, [0x3004_7e00, 0x0601_0000])
        roundTrip(NativeMIDI.deviceInquiry)
    }

    func testLongSysExSplitsIntoStartContinueEnd() {
        // Inquiry reply: 15 payload bytes -> 6 + 6 + 3
        let words = UMP.encode(NativeMIDI.deviceInquiryReply)
        XCTAssertEqual(words.count, 6)
        XCTAssertEqual(words[0] >> 20 & 0xF, 1)
        XCTAssertEqual(words[2] >> 20 & 0xF, 2)
        XCTAssertEqual(words[4] >> 20 & 0xF, 3)
        XCTAssertEqual(words[4] >> 16 & 0xF, 3)
        roundTrip(NativeMIDI.deviceInquiryReply)
    }

    func testLCDSysExOfVariousLengths() {
        for n in [1, 5, 6, 7, 12, 13, 32] {
            let text = [UInt8](repeating: 0x41, count: n)
            roundTrip(NativeMIDI.lcdSysEx(position: 0, text: text))
        }
    }

    func testEmptySysEx() {
        roundTrip([0xF0, 0xF7])
    }

    func testDecoderSkipsRealTimeAndUnknownTypesAndSplitsAcrossFeeds() {
        var d = UMPDecoder()
        let words = UMP.encode(NativeMIDI.deviceInquiryReply)
        XCTAssertEqual(d.feed([0x10F8_0000] + Array(words[0..<2])), [])        // clock, then sysex start
        XCTAssertEqual(d.feed([0x0000_0000] + Array(words[2..<4])), [])         // utility NOOP, continue
        XCTAssertEqual(d.feed(Array(words[4..<6]) + [0x2090_5e7f]), [NativeMIDI.deviceInquiryReply, [0x90, 0x5e, 0x7f]])
    }

    func testWordCounts() {
        XCTAssertEqual(UMP.wordCount(forType: 0x4), 2)
        XCTAssertEqual(UMP.wordCount(forType: 0x5), 4)
        XCTAssertEqual(UMP.wordCount(forType: 0xF), 4)
    }
}
