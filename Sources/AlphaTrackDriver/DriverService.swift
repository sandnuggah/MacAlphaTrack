import Foundation
import AlphaTrackKit

/// The driver: USB reports -> Native-mode MIDI on the virtual source, MIDI on the virtual
/// destination -> LEDs, LCD and fader motor. Survives the device disappearing and
/// reappearing. Runs on its own thread; callbacks are delivered on `callbackQueue`.
public final class DriverService {
    public enum State: Equatable {
        case stopped
        case waitingForDevice
        case connected
    }

    public struct Activity: Equatable {
        public var midiIn = 0
        public var midiOut = 0
        public var reconnects = 0
        public init() {}
    }

    public var onStateChange: ((State) -> Void)?
    public var onActivity: ((Activity) -> Void)?
    public var onLog: ((String) -> Void)?
    public let callbackQueue: DispatchQueue
    public let verbose: Bool

    public private(set) var state: State = .stopped
    public private(set) var activity = Activity()

    private var bridge: MIDIBridge?
    private var translator = ReportTranslator()
    private var deviceState = DeviceState()

    /// Guards `deviceState` and the idle-screen fields, which the MIDI thread and the USB
    /// read thread both use.
    private let stateLock = NSLock()
    private var idle = IdleScreen()
    private var idleEnabled = true
    /// What the idle screen has put on the LCD and LEDs; nil while a host owns the display.
    private var idleShown: [UInt8]? = nil
    private var idleLights: Set<AlphaTrackUSB.Light> = []
    private var lastHostOutput = Date.distantPast
    /// A host is considered gone when it has left the unit blank and quiet for this long.
    private static let idleDelay: TimeInterval = 3

    /// Show the idle screen (sweep and control playground) while no host is using the
    /// unit. On by default.
    public var idleScreenEnabled: Bool {
        get { stateLock.withLock { idleEnabled } }
        set { write(stateLock.withLock { idleEnabled = newValue; return newValue ? [] : endIdle() }) }
    }
    private let writeQueue = DispatchQueue(label: "macalphatrack.usb-out")
    private var device: AlphaTrackDevice? // only touched on writeQueue
    private var thread: Thread?
    private var stopRequested = false
    private let stopLock = NSLock()
    private let stopped = DispatchSemaphore(value: 0)

    public init(verbose: Bool = false, callbackQueue: DispatchQueue = .main) {
        self.verbose = verbose
        self.callbackQueue = callbackQueue
    }

    deinit { stop() }

    /// Create the MIDI ports and start looking for the device. Throws if CoreMIDI refuses.
    public func start() throws {
        guard thread == nil else { return }
        let bridge = try MIDIBridge()
        bridge.onReceive = { [weak self] message in self?.handleMIDI(message) }
        self.bridge = bridge
        stopLock.lock(); stopRequested = false; stopLock.unlock()
        log("MIDI ports \"\(MIDIBridge.portName)\" created. Waiting for AlphaTrack...")
        setState(.waitingForDevice)
        let t = Thread { [weak self] in self?.loop() }
        t.name = "macalphatrack.driver"
        thread = t
        t.start()
    }

    /// Stop, blank the unit, and tear down the MIDI ports. Blocks until the loop has exited.
    public func stop() {
        guard let t = thread else { return }
        stopLock.lock(); stopRequested = true; stopLock.unlock()
        writeQueue.sync { device?.abortReads() }
        while !t.isFinished { usleep(10_000) }
        thread = nil
        if let dev = try? AlphaTrackDevice() {
            for cmd in DeviceState.clearCommands() { try? dev.write(cmd) }
        }
        bridge = nil
        setState(.stopped)
        log("stopped")
        stopped.signal()
    }

    /// Convenience for the CLI: start and block until `stop()` is called from elsewhere.
    public func runUntilStopped() throws {
        try start()
        stopped.wait()
    }

    private var shouldStop: Bool {
        stopLock.lock(); defer { stopLock.unlock() }
        return stopRequested
    }

    // MARK: - loop

    private func loop() {
        var waiting = false
        while !shouldStop {
            let dev: AlphaTrackDevice
            do {
                dev = try AlphaTrackDevice()
            } catch {
                if !waiting { log("AlphaTrack not available (\(error)); waiting"); waiting = true }
                usleep(500_000)
                continue
            }
            waiting = false
            writeQueue.sync { device = dev }
            setState(.connected)
            log("AlphaTrack connected")
            readLoop(dev)
            writeQueue.sync { device = nil }
            if !shouldStop {
                activity.reconnects += 1
                setState(.waitingForDevice)
                log("AlphaTrack disconnected; waiting for it to return")
            }
        }
    }

    private func readLoop(_ dev: AlphaTrackDevice) {
        do {
            while !shouldStop {
                guard let bytes = try dev.read(), let report = InputReport(bytes) else { continue }
                let out = translator.feed(report)
                if out.cameOnline {
                    log("device online; restoring LEDs, LCD and fader")
                    write(stateLock.withLock {
                        idleShown = nil
                        idleLights = []
                        return deviceState.restoreCommands()
                    })
                }
                write(stateLock.withLock { idleCommands(for: report) })
                for m in out.midi {
                    if verbose { log("MIDI out: \(hexString(m))") }
                    bridge?.send(m)
                    activity.midiOut += 1
                }
                if !out.midi.isEmpty { publishActivity() }
            }
        } catch {
            log("USB read failed: \(error)")
        }
    }

    private func handleMIDI(_ message: [UInt8]) {
        if verbose { log("MIDI in:  \(hexString(message))") }
        activity.midiIn += 1
        publishActivity()
        let (handBack, result) = stateLock.withLock { () -> ([[UInt8]], DeviceState.Result) in
            // Restore from the state as it was before this message, then apply the message.
            let before = deviceState
            let result = deviceState.apply(midi: message)
            guard !result.usbCommands.isEmpty else { return ([], result) }
            lastHostOutput = Date()
            return (endIdle(restoring: before), result)
        }
        if let reply = result.midiReply { bridge?.send(reply) }
        if let why = result.unsupported { log("ignoring \(hexString(message)): \(why)") }
        write(handBack + result.usbCommands)
    }

    // MARK: - idle screen (call with stateLock held)

    private var hostLeftUnitBlank: Bool {
        deviceState.lights.isEmpty && deviceState.lcd.allSatisfy { $0 == 0x20 }
    }

    /// Commands that draw the next idle frame, or hand the display back if a host is active.
    private func idleCommands(for report: InputReport) -> [[UInt8]] {
        let now = Date()
        guard idleEnabled, hostLeftUnitBlank,
              now.timeIntervalSince(lastHostOutput) > DriverService.idleDelay else { return endIdle() }
        if idleShown == nil {
            idle = IdleScreen()
            log("no host is using the unit; showing the idle display")
        }
        let frame = idle.feed(report, at: now.timeIntervalSinceReferenceDate)
        var cmds: [[UInt8]] = []
        let shown = idleShown ?? deviceState.lcd
        let width = AlphaTrackUSB.lcdCellWidth
        for cell in 0..<AlphaTrackUSB.lcdCells {
            let range = cell * width..<(cell + 1) * width
            if frame.lcd[range] != shown[range] {
                cmds.append(AlphaTrackUSB.lcdCellCommand(cell: cell, chars: Array(frame.lcd[range])))
            }
        }
        idleShown = frame.lcd
        for light in frame.lights.symmetricDifference(idleLights) {
            cmds.append(AlphaTrackUSB.lightCommand(light, on: frame.lights.contains(light)))
        }
        idleLights = frame.lights
        if let pos = frame.faderSetpoint { cmds.append(AlphaTrackUSB.faderCommand(position: pos)) }
        return cmds
    }

    /// Stop the idle screen and return the commands that put the host's own state back.
    private func endIdle(restoring state: DeviceState? = nil) -> [[UInt8]] {
        guard idleShown != nil else { return [] }
        idleShown = nil
        log("idle display off; display handed back")
        idleLights = []
        return (state ?? deviceState).restoreCommands()
    }

    private func write(_ commands: [[UInt8]]) {
        guard !commands.isEmpty else { return }
        writeQueue.async { [self] in
            guard let dev = device else { return }
            for cmd in commands {
                do { try dev.write(cmd) } catch { log("USB write failed: \(error)"); return }
            }
        }
    }

    // MARK: - callbacks

    private func setState(_ new: State) {
        state = new
        let cb = onStateChange
        callbackQueue.async { cb?(new) }
    }

    private var lastPublish = Date.distantPast
    private func publishActivity() {
        // Coalesce: at most ~10 updates a second.
        let now = Date()
        guard now.timeIntervalSince(lastPublish) > 0.1 else { return }
        lastPublish = now
        let snapshot = activity
        let cb = onActivity
        callbackQueue.async { cb?(snapshot) }
    }

    private func log(_ message: String) {
        let cb = onLog
        callbackQueue.async { cb?(message) }
    }
}

public func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}
