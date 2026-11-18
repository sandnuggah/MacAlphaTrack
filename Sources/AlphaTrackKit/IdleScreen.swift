import Foundation

/// What the unit shows when no host is using it: a bar sweeping under the product name,
/// and a "playground" that follows whichever control is being used. Pure state machine:
/// feed every input report with a timestamp, get the frame to display.
///
/// Drawing uses three characters from the display's built-in set (see docs/PROTOCOL.md):
/// a solid block, a hollow box and a centred dot. The custom glyphs 0x00-0x07 are avoided
/// because each has a line through its middle.
public struct IdleScreen {
    public static let columns = AlphaTrackUSB.lcdColumns
    public static let block: UInt8 = 0xff
    public static let hollow: UInt8 = 0xdb
    public static let dot: UInt8 = 0xa5
    /// A level bar has two steps per cell (hollow box, then solid block).
    public static let barRange = 0...(columns * 2)
    /// Knob turns move the marker one cell per `knobTicksPerCell` ticks.
    public static let knobTicksPerCell = 3
    static let knobRange = 0...(columns * knobTicksPerCell - 1)
    static let knobCentre = columns * knobTicksPerCell / 2

    public struct Frame: Equatable {
        /// 32 character codes, top row then bottom row.
        public var lcd: [UInt8]
        public var lights: Set<AlphaTrackUSB.Light> = []
        /// Set when the fader was moved by hand: the unit must be told the new position,
        /// or it drives the fader back to the old one on release.
        public var faderSetpoint: UInt16? = nil
    }

    enum Focus: Equatable {
        case fader
        case knob(Int)
        case strip
        case button(InputReport.Switch)
    }

    /// Seconds the playground stays up after the last use of a control.
    public var playgroundHold: TimeInterval = 4
    /// Seconds per cell of sweep movement.
    public var sweepStep: TimeInterval = 0.1

    private var focus: Focus? = nil
    private var lastActivity: TimeInterval = -.infinity
    private var knobs = [knobCentre, knobCentre, knobCentre]
    private var lastFader: UInt16? = nil
    private var lastMask: UInt32 = 0
    private var sweepStart: TimeInterval? = nil

    public init() {}

    private static let pushes: [InputReport.Switch] = [.encoderPushLeft, .encoderPushMiddle, .encoderPushRight]
    private static let stripTouches: [InputReport.Switch] = [.stripTouch1, .stripTouch2]
    private static let buttons: [InputReport.Switch] = InputReport.Switch.allCases.filter {
        !ReportTranslator.touchSwitches.contains($0) && !pushes.contains($0)
    }

    public mutating func feed(_ report: InputReport, at now: TimeInterval) -> Frame {
        if report.status == .online {
            lastFader = nil
            lastMask = 0
        }
        var setpoint: UInt16? = nil
        func mark(_ f: Focus, _ me: inout IdleScreen) { me.focus = f; me.lastActivity = now }
        let mask = report.switchMask
        let pressed = mask & ~lastMask
        lastMask = mask

        if let last = lastFader, last != report.faderPosition {
            setpoint = report.faderPosition
            mark(.fader, &self)
        }
        lastFader = report.faderPosition

        for (i, d) in report.encoderDeltas.enumerated() where d != 0 {
            knobs[i] = min(max(knobs[i] + Int(d), IdleScreen.knobRange.lowerBound), IdleScreen.knobRange.upperBound)
            mark(.knob(i), &self)
        }
        for (i, s) in IdleScreen.pushes.enumerated() where pressed & s.mask != 0 {
            knobs[i] = IdleScreen.knobCentre
            mark(.knob(i), &self)
        }
        if IdleScreen.stripTouches.contains(where: { report.isDown($0) }) { mark(.strip, &self) }

        let held = IdleScreen.buttons.filter { report.isDown($0) }
        if let s = IdleScreen.buttons.first(where: { pressed & $0.mask != 0 }) {
            mark(.button(s), &self)
        } else if case .button(let s)? = focus, held.contains(s) {
            lastActivity = now
        }
        let lights = Set(held.compactMap { AlphaTrackUSB.Light(note: $0.note) })

        if let f = focus, now - lastActivity < playgroundHold {
            sweepStart = nil
            return Frame(lcd: playground(f, report), lights: lights, faderSetpoint: setpoint)
        }
        focus = nil
        let start = sweepStart ?? now
        sweepStart = start
        let span = IdleScreen.columns - 1
        let step = Int((now - start) / sweepStep) % (2 * span)
        let row = step < span ? IdleScreen.cometRow(at: step, movingRight: true)
                              : IdleScreen.cometRow(at: 2 * span - step, movingRight: false)
        return Frame(lcd: IdleScreen.text("MacAlphaTrack", centred: true) + row,
                     lights: lights, faderSetpoint: setpoint)
    }

    private func playground(_ f: Focus, _ report: InputReport) -> [UInt8] {
        switch f {
        case .fader:
            let pos = Int(report.faderPosition)
            let top = IdleScreen.text("Fader", right: "\(pos * 100 / 1023)%")
            return top + IdleScreen.barRow(level: (pos * IdleScreen.barRange.upperBound + 511) / 1023)
        case .knob(let i):
            return IdleScreen.text(["Left knob", "Middle knob", "Right knob"][i]) + IdleScreen.markerRow(at: knobs[i] / IdleScreen.knobTicksPerCell)
        case .strip:
            let two = report.isDown(.stripTouch2)
            return IdleScreen.text("Touch strip", right: two ? "x2" : "")
                + IdleScreen.markerRow(at: Int(report.stripPosition) * (IdleScreen.columns - 1) / 31)
        case .button(let s):
            return IdleScreen.text(IdleScreen.name(of: s), centred: true) + IdleScreen.text("")
        }
    }

    // MARK: - drawing

    /// A solid block at `cell` trailed by a hollow box and a dot on the side it came from.
    public static func cometRow(at cell: Int, movingRight: Bool) -> [UInt8] {
        let cell = min(max(cell, 0), columns - 1)
        var row = [UInt8](repeating: 0x20, count: columns)
        let back = movingRight ? -1 : 1
        if (0..<columns).contains(cell + 2 * back) { row[cell + 2 * back] = dot }
        if (0..<columns).contains(cell + back) { row[cell + back] = hollow }
        row[cell] = block
        return row
    }

    /// A row of dots with a solid block at `cell`: a marker on a track.
    public static func markerRow(at cell: Int) -> [UInt8] {
        var row = [UInt8](repeating: dot, count: columns)
        row[min(max(cell, 0), columns - 1)] = block
        return row
    }

    /// A level bar on a track of dots: solid blocks from the left, a hollow box for a half
    /// step. `level` is 0...32.
    public static func barRow(level: Int) -> [UInt8] {
        let level = min(max(level, barRange.lowerBound), barRange.upperBound)
        var row = [UInt8](repeating: dot, count: columns)
        for cell in 0..<level / 2 { row[cell] = block }
        if level % 2 != 0 { row[level / 2] = hollow }
        return row
    }

    static func text(_ left: String, right: String = "", centred: Bool = false) -> [UInt8] {
        var row = [UInt8](repeating: 0x20, count: columns)
        let l = Array(left.utf8.prefix(columns)), r = Array(right.utf8.prefix(columns))
        let offset = centred ? (columns - l.count) / 2 : 0
        for (i, b) in l.enumerated() { row[offset + i] = b }
        for (i, b) in r.enumerated() { row[columns - r.count + i] = b }
        return row
    }

    static func name(of s: InputReport.Switch) -> String {
        switch s {
        case .auto: return "AUTO"
        case .pan: return "PAN"
        case .plugin: return "PLUG-IN"
        case .send: return "SEND"
        case .recArm: return "REC"
        case .eq: return "EQ"
        case .loop: return "LOOP"
        case .trackRight: return "TRACK >"
        case .trackLeft: return "< TRACK"
        case .mute: return "MUTE"
        case .solo: return "SOLO"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .rewind: return "REW"
        case .record: return "RECORD"
        case .fastForward: return "FFWD"
        case .play: return "PLAY"
        case .stop: return "STOP"
        case .shift: return "SHIFT"
        case .flip: return "FLIP"
        default: return ""
        }
    }
}
