import Foundation
import AlphaTrackKit

/// The daemon: USB reports -> Native-mode MIDI on the virtual source, MIDI on the
/// virtual destination -> LEDs and LCD. Survives the device disappearing and reappearing.
final class Daemon {
    private let verbose: Bool
    private let bridge: MIDIBridge
    private var translator = ReportTranslator()
    private var state = DeviceState()
    private let writeQueue = DispatchQueue(label: "macalphatrack.usb-out")
    private var device: AlphaTrackDevice? // only touched on writeQueue
    private var stop = false
    private var faderWarned = false

    init(verbose: Bool) throws {
        self.verbose = verbose
        bridge = try MIDIBridge()
        bridge.onReceive = { [weak self] message in self?.handleMIDI(message) }
    }

    func run() {
        installSignalHandlers()
        log("MIDI ports \"\(MIDIBridge.portName)\" created. Waiting for AlphaTrack...")
        var waiting = false
        while !stop {
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
            log("AlphaTrack connected")
            readLoop(dev)
            writeQueue.sync { device = nil }
            if !stop { log("AlphaTrack disconnected; waiting for it to return") }
        }
        shutdown()
    }

    private func readLoop(_ dev: AlphaTrackDevice) {
        do {
            while !stop {
                guard let bytes = try dev.read(), let report = InputReport(bytes) else { continue }
                let out = translator.feed(report)
                if out.cameOnline {
                    log("device online; restoring LEDs and LCD")
                    write(state.restoreCommands())
                }
                for m in out.midi {
                    if verbose { log("MIDI out: \(hex(m))") }
                    bridge.send(m)
                }
            }
        } catch {
            log("USB read failed: \(error)")
        }
    }

    private func handleMIDI(_ message: [UInt8]) {
        if verbose { log("MIDI in:  \(hex(message))") }
        let result = state.apply(midi: message)
        if let reply = result.midiReply { bridge.send(reply) }
        if let why = result.unsupported, !faderWarned {
            log("ignoring \(hex(message)): \(why)")
            faderWarned = true
        }
        write(result.usbCommands)
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

    private var signalSources: [DispatchSourceSignal] = []
    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            src.setEventHandler { [weak self] in
                guard let self else { return }
                self.stop = true
                self.writeQueue.sync { self.device?.abortReads() }
            }
            src.resume()
            signalSources.append(src)
        }
    }

    private func shutdown() {
        log("shutting down; clearing LEDs and LCD")
        // The device was closed by the read loop; reopen briefly to blank it.
        if let dev = try? AlphaTrackDevice() {
            for cmd in DeviceState.clearCommands() { try? dev.write(cmd) }
        }
    }

    private func log(_ message: String) {
        let t = ISO8601DateFormatter().string(from: Date())
        FileHandle.standardError.write("\(t) \(message)\n".data(using: .utf8)!)
    }
}

func cmdRun(verbose: Bool) throws {
    let daemon = try Daemon(verbose: verbose)
    daemon.run()
}
