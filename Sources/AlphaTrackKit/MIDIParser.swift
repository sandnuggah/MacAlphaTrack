import Foundation

/// Reassembles a MIDI 1.0 byte stream into complete messages. Handles running
/// status and SysEx split across packets; drops real-time bytes.
public struct MIDIParser {
    private var buffer: [UInt8] = []
    private var inSysEx = false
    private var runningStatus: UInt8? = nil

    public init() {}

    public mutating func feed(_ bytes: [UInt8]) -> [[UInt8]] {
        var out: [[UInt8]] = []
        for b in bytes {
            if b >= 0xf8 { continue } // real-time, may appear anywhere
            if inSysEx {
                if b == 0xf7 {
                    buffer.append(b)
                    out.append(buffer)
                    buffer = []
                    inSysEx = false
                } else if b & 0x80 != 0 {
                    // Status byte inside SysEx: abandon it, process the new status.
                    buffer = []
                    inSysEx = false
                    startStatus(b, into: &out)
                } else {
                    buffer.append(b)
                }
                continue
            }
            if b & 0x80 != 0 {
                startStatus(b, into: &out)
            } else {
                if buffer.isEmpty, let rs = runningStatus { buffer = [rs] }
                guard !buffer.isEmpty else { continue } // stray data byte
                buffer.append(b)
                if buffer.count == MIDIParser.length(of: buffer[0]) {
                    out.append(buffer)
                    buffer = []
                }
            }
        }
        return out
    }

    private mutating func startStatus(_ b: UInt8, into out: inout [[UInt8]]) {
        buffer = []
        if b == 0xf0 {
            inSysEx = true
            buffer = [b]
            runningStatus = nil
        } else if b >= 0xf0 {
            runningStatus = nil
            if MIDIParser.length(of: b) == 1 { out.append([b]) } else { buffer = [b] }
        } else {
            runningStatus = b
            buffer = [b]
        }
    }

    /// Total message length for a status byte (0 for SysEx).
    static func length(of status: UInt8) -> Int {
        switch status & 0xf0 {
        case 0xc0, 0xd0: return 2
        case 0x80, 0x90, 0xa0, 0xb0, 0xe0: return 3
        default:
            switch status {
            case 0xf1, 0xf3: return 2
            case 0xf2: return 3
            case 0xf0: return 0
            default: return 1
            }
        }
    }
}
