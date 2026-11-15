import Foundation

extension AlphaTrackUSB.Light {
    /// Which light a Native-mode LED note drives (all verified on hardware).
    public init?(note: NativeMIDI.Note) {
        switch note {
        case .record: self = .record
        case .shift: self = .shift
        case .trackLeft: self = .trackLeft
        case .trackRight: self = .trackRight
        case .loop: self = .loop
        case .flip: self = .flip
        case .mute: self = .mute
        case .solo: self = .solo
        case .recArm: self = .recArm
        case .f1: self = .f1
        case .f2: self = .f2
        case .f3: self = .f3
        case .f4: self = .f4
        case .pan: self = .pan
        case .send: self = .send
        case .eq: self = .eq
        case .plugin: self = .plugin
        case .auto: self = .auto
        case .autoWriteLED: self = .autoWrite
        case .autoReadLED: self = .autoRead
        case .anySoloLED: self = .anySolo
        default: return nil
        }
    }
}

/// Host-side mirror of everything the device displays, and the translation from
/// Native-mode MIDI (DAW -> AlphaTrack) into raw USB output commands.
public struct DeviceState: Equatable {
    public private(set) var lights: Set<AlphaTrackUSB.Light> = []
    public private(set) var lcd: [UInt8] = Array(repeating: 0x20, count: AlphaTrackUSB.lcdColumns * AlphaTrackUSB.lcdRows)
    /// Last fader position commanded by the host, if any.
    public private(set) var faderPosition: UInt16? = nil

    public init() {}

    /// What one incoming MIDI message means for the device.
    public struct Result: Equatable {
        public var usbCommands: [[UInt8]] = []
        /// A reply the host must send back on the MIDI source (device inquiry).
        public var midiReply: [UInt8]? = nil
        /// Messages we recognise but cannot act on.
        public var unsupported: String? = nil
    }

    public mutating func apply(midi message: [UInt8]) -> Result {
        var result = Result()
        guard let status = message.first else { return result }
        switch status {
        case NativeMIDI.noteOn where message.count == 3:
            guard let note = NativeMIDI.Note(rawValue: message[1]),
                  let light = AlphaTrackUSB.Light(note: note) else { return result }
            let on = message[2] != 0
            if on { lights.insert(light) } else { lights.remove(light) }
            result.usbCommands = [AlphaTrackUSB.lightCommand(light, on: on)]
        case NativeMIDI.faderPitchBend where message.count == 3:
            if let pos = NativeMIDI.faderPosition(from: message) {
                faderPosition = pos
                result.usbCommands = [AlphaTrackUSB.faderCommand(position: pos)]
            }
        case 0xf0:
            if let (pos, text) = NativeMIDI.parseLCDSysEx(message) {
                result.usbCommands = AlphaTrackUSB.lcdCommands(writing: text, at: Int(pos), current: lcd)
                for (i, b) in text.enumerated() where Int(pos) + i < lcd.count { lcd[Int(pos) + i] = b }
            } else if message == NativeMIDI.deviceInquiry {
                result.midiReply = NativeMIDI.deviceInquiryReply
            } else if message == NativeMIDI.forceNativeMode {
                break // we are always in native mode
            }
        default:
            break
        }
        return result
    }

    /// Commands that bring a freshly (re)connected device in line with this state.
    public func restoreCommands() -> [[UInt8]] {
        var cmds: [[UInt8]] = []
        for light in AlphaTrackUSB.Light.allCases {
            cmds.append(AlphaTrackUSB.lightCommand(light, on: lights.contains(light)))
        }
        for cell in 0..<AlphaTrackUSB.lcdCells {
            let start = cell * AlphaTrackUSB.lcdCellWidth
            cmds.append(AlphaTrackUSB.lcdCellCommand(cell: cell, chars: Array(lcd[start..<start + AlphaTrackUSB.lcdCellWidth])))
        }
        if let pos = faderPosition { cmds.append(AlphaTrackUSB.faderCommand(position: pos)) }
        return cmds
    }

    /// Commands that switch every light off and blank the LCD (use on exit).
    public static func clearCommands() -> [[UInt8]] {
        DeviceState().restoreCommands()
    }
}
