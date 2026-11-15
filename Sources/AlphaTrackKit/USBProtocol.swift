import Foundation

/// Raw USB layer of the AlphaTrack. Everything here is reconstructed from the Linux
/// staging driver (drivers/staging/frontier/alphatrack.c) and David Täht's Ardour
/// surface code. Items marked "unverified" must be confirmed against real hardware
/// with `macalphatrack dump`.
public enum AlphaTrackUSB {
    public static let vendorID: UInt16 = 0x165b
    public static let productID: UInt16 = 0xfad1

    /// Interrupt IN reports are always this long.
    public static let inputReportLength = 12
    /// Interrupt OUT commands are always this long.
    public static let outputCommandLength = 8

    /// Byte 1 of every input report.
    public enum Status: UInt8 {
        case event = 0x00
        case online = 0x01
        case offline = 0xff
    }

    /// Light ids used by the LED command. Order confirmed by the Ardour `lightmap`.
    /// `out`/`in` are the TranzPort names; on the AlphaTrack they are most likely the
    /// TRACK R / TRACK L backlights (unverified).
    public enum Light: UInt8, CaseIterable {
        case eq = 0
        case out = 1
        case f2 = 2
        case send = 3
        case `in` = 4
        case f1 = 5
        case pan = 6
        case undefined7 = 7
        case undefined8 = 8
        case shift = 9
        case mute = 10
        case solo = 11
        case recArm = 12
        case autoRead = 13
        case autoWrite = 14
        case anySolo = 15
        case auto = 16
        case f4 = 17
        case record = 18
        case window = 19
        case plugin = 20
        case f3 = 21
        case loop = 22
    }

    /// Build the 8-byte "set light" command: `00 00 nn ss 00 00 00 00`.
    public static func lightCommand(_ light: Light, on: Bool) -> [UInt8] {
        [0x00, 0x00, light.rawValue, on ? 0x01 : 0x00, 0x00, 0x00, 0x00, 0x00]
    }

    /// The 16x2 LCD is written in 8 cells of 4 characters: cells 0-3 are the top row,
    /// 4-7 the bottom row. Command: `00 01 cc a0 a1 a2 a3 00`.
    public static let lcdCells = 8
    public static let lcdCellWidth = 4
    public static let lcdColumns = 16
    public static let lcdRows = 2

    /// Build one LCD cell write. `chars` is padded with spaces / truncated to 4 bytes.
    public static func lcdCellCommand(cell: Int, chars: [UInt8]) -> [UInt8] {
        precondition((0..<lcdCells).contains(cell), "LCD cell out of range")
        var c = Array(chars.prefix(lcdCellWidth))
        while c.count < lcdCellWidth { c.append(0x20) }
        return [0x00, 0x01, UInt8(cell), c[0], c[1], c[2], c[3], 0x00]
    }

    /// Convenience: the cell commands needed to write `text` starting at a
    /// (row, column) position, mirroring the Native-mode LCD SysEx semantics.
    /// Only whole cells touched by the text are emitted; untouched columns inside
    /// those cells are filled from `current` (the host-side shadow of the display).
    public static func lcdCommands(
        writing text: [UInt8],
        at position: Int,
        current: [UInt8]
    ) -> [[UInt8]] {
        precondition(current.count == lcdColumns * lcdRows)
        var shadow = current
        for (i, byte) in text.enumerated() {
            let p = position + i
            guard p < shadow.count else { break }
            shadow[p] = byte
        }
        let firstCell = position / lcdCellWidth
        let lastCell = min(position + text.count - 1, shadow.count - 1) / lcdCellWidth
        guard text.count > 0, firstCell <= lastCell else { return [] }
        return (firstCell...lastCell).map { cell in
            let start = cell * lcdCellWidth
            return lcdCellCommand(cell: cell, chars: Array(shadow[start..<start + lcdCellWidth]))
        }
    }
}
