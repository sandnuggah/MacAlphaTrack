import Foundation

/// Decoded 12-byte interrupt IN report.
///
/// Layout, verified on hardware 2026-11-15 (see docs/PROTOCOL.md):
///
///     byte 0     always 0x00
///     byte 1     status: 0x00 event, 0x01 came online, 0xff offline
///     bytes 2-5  32-bit big-endian switch mask (buttons, encoder touch/press, fader touch)
///     byte 6     fader position bits 9..2
///     byte 7     fader position bits 1..0 in the top two bits
///     byte 8     left encoder delta since previous report
///     byte 9     middle encoder delta
///     byte 10    right encoder delta
///     byte 11    touch strip position, 0x00...0xf8 in steps of 8 (position = byte >> 3, 0...31);
///                holds its last value after the finger lifts
///
/// The device sends a report every 8 ms whether or not anything changed.
public struct InputReport: Equatable {
    /// Switches in the 32-bit mask, by bit index. Bit 7 has never been seen and is
    /// presumably the footswitch (none was connected during verification).
    public enum Switch: Int, CaseIterable {
        case encoderPushLeft = 0
        case stripTouch1 = 1
        case stripTouch2 = 2
        case encoderTouchLeft = 3
        case encoderTouchMiddle = 4
        case encoderTouchRight = 5
        case faderTouch = 6
        case auto = 8
        case pan = 9
        case plugin = 10
        case send = 11
        case recArm = 12
        case encoderPushRight = 13
        case eq = 14
        case encoderPushMiddle = 15
        case loop = 16
        case trackRight = 17
        case mute = 18
        case f4 = 19
        case f1 = 20
        case f3 = 21
        case f2 = 22
        case solo = 23
        case rewind = 24
        case record = 25
        case fastForward = 26
        case play = 27
        case stop = 28
        case shift = 29
        case flip = 30
        case trackLeft = 31

        public var mask: UInt32 { 1 << UInt32(rawValue) }

        /// The Native-mode note this switch reports as.
        public var note: NativeMIDI.Note {
            switch self {
            case .encoderPushLeft: return .encoderPushLeft
            case .encoderPushMiddle: return .encoderPushMiddle
            case .encoderPushRight: return .encoderPushRight
            case .encoderTouchLeft: return .encoderTouchLeft
            case .encoderTouchMiddle: return .encoderTouchMiddle
            case .encoderTouchRight: return .encoderTouchRight
            case .faderTouch: return .faderTouch
            case .stripTouch1: return .stripTouch1
            case .stripTouch2: return .stripTouch2
            case .auto: return .auto
            case .pan: return .pan
            case .plugin: return .plugin
            case .send: return .send
            case .recArm: return .recArm
            case .eq: return .eq
            case .loop: return .loop
            case .trackRight: return .trackRight
            case .mute: return .mute
            case .f1: return .f1
            case .f2: return .f2
            case .f3: return .f3
            case .f4: return .f4
            case .solo: return .solo
            case .rewind: return .rewind
            case .record: return .record
            case .fastForward: return .fastForward
            case .play: return .play
            case .stop: return .stop
            case .shift: return .shift
            case .flip: return .flip
            case .trackLeft: return .trackLeft
            }
        }
    }

    public let status: AlphaTrackUSB.Status?
    public let rawStatus: UInt8
    public let switchMask: UInt32
    /// 0...1023, bottom to top.
    public let faderPosition: UInt16
    /// Per-report tick deltas for left, middle, right encoders as signed bytes.
    /// +1 per clockwise click, -1 per counter-clockwise click.
    public let encoderDeltas: [Int]
    /// Touch strip position 0...31 (left to right). Only meaningful while a strip touch bit is set.
    public let stripPosition: UInt8

    public init?(_ bytes: [UInt8]) {
        guard bytes.count >= AlphaTrackUSB.inputReportLength else { return nil }
        rawStatus = bytes[1]
        status = AlphaTrackUSB.Status(rawValue: bytes[1])
        switchMask = AlphaTrackUSB.buttonMask(of: bytes)
        faderPosition = UInt16(bytes[6]) << 2 | UInt16(bytes[7] >> 6)
        encoderDeltas = (8...10).map { Int(Int8(bitPattern: bytes[$0])) }
        stripPosition = bytes[11] >> 3
    }

    public func isDown(_ s: Switch) -> Bool { switchMask & s.mask != 0 }

    public var switchesDown: [Switch] { Switch.allCases.filter(isDown) }

    /// Bits set in the mask that no known switch claims.
    public var unknownBits: [Int] {
        let known = Switch.allCases.reduce(UInt32(0)) { $0 | $1.mask }
        return (0..<32).filter { switchMask & ~known & (1 << UInt32($0)) != 0 }
    }
}
