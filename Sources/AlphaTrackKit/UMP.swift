import Foundation

/// Universal MIDI Packet encoding of MIDI 1.0 messages (the MIDI 1.0 protocol inside UMP),
/// as used by CoreMIDI's MIDIEventList API. Group 0 throughout.
public enum UMP {
    /// Encode one complete MIDI 1.0 message (channel voice or SysEx with F0…F7) into words.
    public static func encode(_ message: [UInt8]) -> [UInt32] {
        guard let status = message.first else { return [] }
        if status == 0xF0 {
            return encodeSysEx(message)
        }
        if status >= 0xF8 {
            return [0x1 << 28 | UInt32(status) << 16]  // system real time
        }
        if status >= 0xF0 {
            let d1 = message.count > 1 ? UInt32(message[1]) : 0
            let d2 = message.count > 2 ? UInt32(message[2]) : 0
            return [0x1 << 28 | UInt32(status) << 16 | d1 << 8 | d2]  // system common
        }
        let d1 = message.count > 1 ? UInt32(message[1]) : 0
        let d2 = message.count > 2 ? UInt32(message[2]) : 0
        return [0x2 << 28 | UInt32(status) << 16 | d1 << 8 | d2]  // MIDI 1.0 channel voice
    }

    /// SysEx7: 64-bit packets carrying up to 6 payload bytes each; F0/F7 are not transmitted.
    static func encodeSysEx(_ message: [UInt8]) -> [UInt32] {
        var payload = Array(message.dropFirst())
        if payload.last == 0xF7 { payload.removeLast() }
        let chunks: [[UInt8]] = stride(from: 0, to: max(payload.count, 1), by: 6).map {
            Array(payload[$0..<min($0 + 6, payload.count)])
        }
        var words: [UInt32] = []
        for (i, chunk) in chunks.enumerated() {
            let status: UInt32
            if chunks.count == 1 { status = 0 }            // complete
            else if i == 0 { status = 1 }                   // start
            else if i == chunks.count - 1 { status = 3 }    // end
            else { status = 2 }                             // continue
            var b = chunk
            while b.count < 6 { b.append(0) }
            words.append(0x3 << 28 | status << 20 | UInt32(chunk.count) << 16 | UInt32(b[0]) << 8 | UInt32(b[1]))
            words.append(UInt32(b[2]) << 24 | UInt32(b[3]) << 16 | UInt32(b[4]) << 8 | UInt32(b[5]))
        }
        return words
    }

    /// Number of 32-bit words a packet occupies, from its message type nibble.
    public static func wordCount(forType type: UInt32) -> Int {
        switch type {
        case 0x0, 0x1, 0x2, 0x6, 0x7: return 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
        case 0xB, 0xC: return 3
        default: return 4
        }
    }
}

/// Turns a stream of UMP words back into complete MIDI 1.0 byte messages.
/// Utility, real-time and anything that is not MIDI 1.0 channel voice or SysEx7 is dropped.
public struct UMPDecoder {
    private var sysex: [UInt8]? = nil

    public init() {}

    public mutating func feed(_ words: [UInt32]) -> [[UInt8]] {
        var out: [[UInt8]] = []
        var i = 0
        while i < words.count {
            let w0 = words[i]
            let type = w0 >> 28
            let n = UMP.wordCount(forType: type)
            guard i + n <= words.count else { break }
            switch type {
            case 0x2:
                let status = UInt8((w0 >> 16) & 0xFF), d1 = UInt8((w0 >> 8) & 0x7F), d2 = UInt8(w0 & 0x7F)
                switch status & 0xF0 {
                case 0xC0, 0xD0: out.append([status, d1])
                default: out.append([status, d1, d2])
                }
            case 0x3:
                let w1 = words[i + 1]
                let status = (w0 >> 20) & 0xF
                let count = Int((w0 >> 16) & 0xF)
                let bytes: [UInt8] = [UInt8((w0 >> 8) & 0x7F), UInt8(w0 & 0x7F),
                                      UInt8((w1 >> 24) & 0x7F), UInt8((w1 >> 16) & 0x7F),
                                      UInt8((w1 >> 8) & 0x7F), UInt8(w1 & 0x7F)]
                let payload = Array(bytes.prefix(min(count, 6)))
                switch status {
                case 0: out.append([0xF0] + payload + [0xF7]); sysex = nil
                case 1: sysex = payload
                case 2: sysex?.append(contentsOf: payload)
                case 3:
                    if var s = sysex { s.append(contentsOf: payload); out.append([0xF0] + s + [0xF7]) }
                    sysex = nil
                default: break
                }
            default:
                break
            }
            i += n
        }
        return out
    }
}
