import Foundation

/// Native-mode MIDI protocol as documented in Frontier's
/// "AlphaTrack Native Mode MIDI Interface Description" rev 1.0 (2006-12-21).
/// This is what the virtual CoreMIDI device speaks.
public enum NativeMIDI {
    /// Note numbers on channel 1. Buttons report `90 nn 7f` (down) / `90 nn 00` (up);
    /// the matching LED is driven by the same note number on the output side.
    public enum Note: UInt8, CaseIterable {
        case recArm = 0x00
        case solo = 0x08
        case mute = 0x10
        case encoderPushLeft = 0x20
        case encoderPushMiddle = 0x21
        case encoderPushRight = 0x22
        case send = 0x29
        case pan = 0x2a
        case plugin = 0x2b
        case eq = 0x2c
        case flip = 0x32
        case f1 = 0x36
        case f2 = 0x37
        case f3 = 0x38
        case f4 = 0x39
        case shift = 0x46
        case auto = 0x4a
        case autoWriteLED = 0x4b
        case autoReadLED = 0x4e
        case loop = 0x56
        case trackLeft = 0x57
        case trackRight = 0x58
        case rewind = 0x5b
        case fastForward = 0x5c
        case stop = 0x5d
        case play = 0x5e
        case record = 0x5f
        case footswitch = 0x67
        case faderTouch = 0x68
        case anySoloLED = 0x73
        case stripTouch1 = 0x74
        case encoderTouchLeft = 0x78
        case encoderTouchMiddle = 0x79
        case encoderTouchRight = 0x7a
        case stripTouch2 = 0x7b
    }

    /// Encoder turns are relative: `b0 cc nn`, nn = 01..3f ticks forward, 41..7f ticks backward.
    public enum EncoderCC: UInt8 {
        case left = 0x10
        case middle = 0x11
        case right = 0x12
    }

    public static let noteOn: UInt8 = 0x90
    public static let controlChange: UInt8 = 0xb0
    public static let faderPitchBend: UInt8 = 0xe0
    public static let stripPitchBend: UInt8 = 0xe9

    public static let frontierSysExID: [UInt8] = [0x00, 0x01, 0x40]
    public static let forceNativeMode: [UInt8] = [0xf0, 0x00, 0x01, 0x40, 0x20, 0x01, 0x00, 0xf7]
    public static let deviceInquiry: [UInt8] = [0xf0, 0x7e, 0x00, 0x06, 0x01, 0xf7]
    /// Response to a device inquiry; trailing "0100" is the firmware revision in ASCII.
    public static let deviceInquiryReply: [UInt8] =
        [0xf0, 0x7e, 0x00, 0x06, 0x02, 0x00, 0x01, 0x40, 0x20, 0x00, 0x01, 0x00, 0x30, 0x31, 0x30, 0x30, 0xf7]

    public static func button(_ note: Note, down: Bool) -> [UInt8] {
        [noteOn, note.rawValue, down ? 0x7f : 0x00]
    }

    /// Relative encoder message. `ticks` is clamped to ±63.
    public static func encoder(_ enc: EncoderCC, ticks: Int) -> [UInt8] {
        let t = max(-63, min(63, ticks))
        let value: UInt8 = t >= 0 ? UInt8(t) : UInt8(0x40 + (-t))
        return [controlChange, enc.rawValue, value]
    }

    /// 10-bit fader position as `e0 yy zz`: yy carries the 3 LSBs in bits 4-6, zz the 7 MSBs.
    public static func fader(position: UInt16) -> [UInt8] {
        let p = min(position, 0x3ff)
        return [faderPitchBend, UInt8((p & 0x7) << 4), UInt8(p >> 3)]
    }

    public static func faderPosition(from message: [UInt8]) -> UInt16? {
        guard message.count == 3, message[0] == faderPitchBend else { return nil }
        return (UInt16(message[2]) << 3) | (UInt16(message[1]) >> 4)
    }

    /// Touch strip absolute position 0..31 as `e9 00 nn`, nn = position << 2.
    public static func strip(position: UInt8) -> [UInt8] {
        [stripPitchBend, 0x00, (position & 0x1f) << 2]
    }

    /// LCD write SysEx: `f0 00 01 40 20 00 pp c1 .. cn f7`, pp = 0..0x1f start position.
    public static func lcdSysEx(position: UInt8, text: [UInt8]) -> [UInt8] {
        precondition(position < 0x20)
        let room = Int(0x20 - position)
        return [0xf0] + frontierSysExID + [0x20, 0x00, position] + Array(text.prefix(room)) + [0xf7]
    }

    /// Parse an incoming LCD SysEx into (start position, bytes), or nil if it is not one.
    public static func parseLCDSysEx(_ message: [UInt8]) -> (position: UInt8, text: [UInt8])? {
        guard message.count >= 8,
              message.first == 0xf0, message.last == 0xf7,
              Array(message[1...3]) == frontierSysExID,
              message[4] == 0x20, message[5] == 0x00,
              message[6] < 0x20
        else { return nil }
        return (message[6], Array(message[7..<(message.count - 1)]))
    }
}
