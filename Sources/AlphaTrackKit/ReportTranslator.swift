import Foundation

/// Turns the stream of raw input reports into Native-mode MIDI messages.
/// Pure state machine: feed reports in order, collect the messages to send.
public struct ReportTranslator {
    /// Capacitive touch sensing on the AlphaTrack is proximity-sensitive: with a hand
    /// anywhere over the unit, neighbouring touch bits oscillate (observed ~120-200 ms on,
    /// ~40-120 ms off). Genuine touches hold for 500 ms or more. So a touch is asserted
    /// only after the bit has been continuously on for `touchAssertReports` reports
    /// (8 ms each), and released only after it has been continuously off for
    /// `touchReleaseReports`, which also smooths flicker during a real touch.
    /// Fader movement asserts fader touch immediately, since a moving fader is a touched fader.
    public var touchAssertReports: Int
    public var touchReleaseReports: Int

    public static let touchSwitches: Set<InputReport.Switch> = [
        .encoderTouchLeft, .encoderTouchMiddle, .encoderTouchRight,
        .faderTouch, .stripTouch1, .stripTouch2,
    ]

    private var emittedMask: UInt32 = 0
    private var pendingCount: [InputReport.Switch: Int] = [:]
    private var lastFader: UInt16? = nil
    private var lastStrip: UInt8? = nil

    /// Defaults: assert after ~210 ms, release after ~260 ms.
    public init(touchAssertReports: Int = 26, touchReleaseReports: Int = 32) {
        self.touchAssertReports = max(1, touchAssertReports)
        self.touchReleaseReports = max(1, touchReleaseReports)
    }

    /// Backwards-compatible symmetric debounce.
    public init(touchDebounce: Int) {
        self.init(touchAssertReports: touchDebounce, touchReleaseReports: touchDebounce)
    }

    /// Result of feeding one report.
    public struct Output: Equatable {
        public var midi: [[UInt8]] = []
        /// The device (re)announced itself; the host should restore LEDs and LCD.
        public var cameOnline = false
        public var wentOffline = false
    }

    public mutating func feed(_ report: InputReport) -> Output {
        var out = Output()
        switch report.status {
        case .online?:
            // Fresh device state: everything is released, positions unknown.
            emittedMask = 0
            pendingCount = [:]
            lastFader = nil
            lastStrip = nil
            out.cameOnline = true
        case .offline?:
            out.wentOffline = true
            return out
        default:
            break
        }

        // Fader movement implies a real touch: bypass the assert delay.
        let faderMoved = lastFader != nil && report.faderPosition != lastFader

        // Switches.
        for s in InputReport.Switch.allCases {
            let raw = report.isDown(s)
            let emitted = emittedMask & s.mask != 0
            if raw == emitted {
                pendingCount[s] = 0
                continue
            }
            if ReportTranslator.touchSwitches.contains(s) {
                let needed = raw ? touchAssertReports : touchReleaseReports
                let n = (pendingCount[s] ?? 0) + 1
                let bypass = s == .faderTouch && raw && faderMoved
                if n < needed && !bypass {
                    pendingCount[s] = n
                    continue
                }
                pendingCount[s] = 0
            }
            if raw { emittedMask |= s.mask } else { emittedMask &= ~s.mask }
            out.midi.append(NativeMIDI.button(s.note, down: raw))
        }

        // Encoders: one relative CC per encoder with a non-zero delta.
        let ccs: [NativeMIDI.EncoderCC] = [.left, .middle, .right]
        for (i, d) in report.encoderDeltas.enumerated() where d != 0 {
            out.midi.append(NativeMIDI.encoder(ccs[i], ticks: d))
        }

        // Fader position, whenever it changes.
        if report.faderPosition != lastFader {
            lastFader = report.faderPosition
            out.midi.append(NativeMIDI.fader(position: report.faderPosition))
        }

        // Strip position: only meaningful while touched. Report on touch start and on change.
        let stripTouched = emittedMask & (InputReport.Switch.stripTouch1.mask | InputReport.Switch.stripTouch2.mask) != 0
        if stripTouched {
            if report.stripPosition != lastStrip {
                lastStrip = report.stripPosition
                out.midi.append(NativeMIDI.strip(position: report.stripPosition))
            }
        } else {
            lastStrip = nil
        }
        return out
    }
}
