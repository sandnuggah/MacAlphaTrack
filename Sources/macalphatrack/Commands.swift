import Foundation
import AlphaTrackKit
import AlphaTrackDriver

private var stopRequested = false
private var sigintSource: DispatchSourceSignal?
private var currentDevice: AlphaTrackDevice?

/// Stop the dump loop on Ctrl-C or after `seconds`, by aborting the blocked USB read.
private func installStop(after seconds: Double?) {
    signal(SIGINT, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    src.setEventHandler { stopRequested = true; currentDevice?.abortReads() }
    src.resume()
    sigintSource = src
    if let s = seconds {
        DispatchQueue.global().asyncAfter(deadline: .now() + s) { stopRequested = true; currentDevice?.abortReads() }
    }
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

func cmdDescriptors() throws {
    let dev = try AlphaTrackDevice()
    print("Opened AlphaTrack. Endpoints in configuration 1:")
    for ep in dev.endpoints { print("  \(ep)") }
    print("Using IN \(String(format: "0x%02x", dev.inEndpoint.address)), OUT \(String(format: "0x%02x", dev.outEndpoint.address))")
}

/// Print every input report, highlighting what changed since the previous one.
/// Survives the device resetting itself: on a USB error it waits and reopens.
func cmdDump(showAll: Bool, seconds: Double?) throws {
    installStop(after: seconds)
    print("Dumping raw reports (\(showAll ? "all" : "changes only")). Press buttons, turn knobs, move the fader. Ctrl-C to stop.")
    print("cols: [elapsed] b0 b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 b11 | decoded")
    let start = Date()
    var previous: [UInt8]? = nil
    var count = 0
    var reportedWaiting = false
    while !stopRequested {
        let dev: AlphaTrackDevice
        do {
            dev = try AlphaTrackDevice()
        } catch {
            if !reportedWaiting {
                print(String(format: "[%7.3f] cannot open device (%@); waiting for it to come back...",
                             Date().timeIntervalSince(start), "\(error)"))
                reportedWaiting = true
            }
            usleep(500_000)
            continue
        }
        if reportedWaiting { print(String(format: "[%7.3f] device reopened", Date().timeIntervalSince(start))) }
        reportedWaiting = false
        currentDevice = dev
        previous = nil
        do {
            while !stopRequested {
                guard let report = try dev.read() else { continue }
                if !showAll, report == previous { continue }
                count += 1
                let t = String(format: "%7.3f", Date().timeIntervalSince(start))
                var cells: [String] = []
                for (i, b) in report.enumerated() {
                    let changed = previous.map { i >= $0.count || $0[i] != b } ?? true
                    let s = String(format: "%02x", b)
                    cells.append(changed ? "\u{1b}[1;33m\(s)\u{1b}[0m" : s)
                }
                print("[\(t)] \(cells.joined(separator: " ")) | \(decode(report, previous: previous))")
                previous = report
            }
        } catch {
            print(String(format: "[%7.3f] DEVICE ERROR: %@ -- reopening", Date().timeIntervalSince(start), "\(error)"))
        }
        currentDevice = nil
    }
    print("\(count) reports.")
}

/// Human-readable interpretation of a report, naming verified switches and flagging unknown bits.
func decode(_ r: [UInt8], previous: [UInt8]?) -> String {
    guard let rep = InputReport(r) else { return "short report (\(r.count) bytes)" }
    let prev = previous.flatMap(InputReport.init)
    var parts: [String] = []
    switch rep.status {
    case .online?: parts.append("ONLINE")
    case .offline?: parts.append("OFFLINE")
    case .event?: break
    case nil: parts.append(String(format: "status=%02x?", rep.rawStatus))
    }
    let prevMask = prev?.switchMask ?? 0
    for bit in (0..<32).reversed() {
        let now = rep.switchMask & (1 << UInt32(bit)) != 0, before = prevMask & (1 << UInt32(bit)) != 0
        if now != before {
            let name = InputReport.Switch(rawValue: bit).map { "\($0)" } ?? "UNKNOWN bit\(bit)"
            parts.append((now ? "+" : "-") + name)
        }
    }
    if prev == nil || rep.faderPosition != prev!.faderPosition { parts.append("fader=\(rep.faderPosition)") }
    for (i, d) in rep.encoderDeltas.enumerated() where d != 0 {
        parts.append(["encL", "encM", "encR"][i] + (d > 0 ? "+\(d)" : "\(d)") + String(format: " (0x%02x)", r[8 + i]))
    }
    if prev == nil || rep.stripPosition != prev!.stripPosition { parts.append("strip=\(rep.stripPosition)") }
    return parts.joined(separator: " ")
}

/// Cycle through every light id so the physical LED for each id can be recorded.
/// The LCD names the id currently lit and the LED we expect it to be.
func cmdLights(_ arg: String?, dwell: Double) throws {
    let dev = try AlphaTrackDevice()
    func lcd(_ top: String, _ bottom: String) throws {
        for (cell, chunk) in lcdCells(top: top, bottom: bottom).enumerated() { try dev.writeLCDCell(cell, chunk) }
    }
    switch arg {
    case "on":
        for l in AlphaTrackUSB.Light.allCases { try dev.setLight(l, on: true) }
        print("all lights on")
    case "off":
        for l in AlphaTrackUSB.Light.allCases { try dev.setLight(l, on: false) }
        print("all lights off")
    default:
        for l in AlphaTrackUSB.Light.allCases { try dev.setLight(l, on: false) }
        print("Cycling light ids 0...22, \(dwell) s each. The LCD shows the id and the expected LED; note any mismatch.")
        for l in AlphaTrackUSB.Light.allCases {
            let expect = "\(l)"
            print(String(format: "  id %2d  expect %@", Int(l.rawValue), expect))
            try lcd(String(format: "LIGHT ID %02d", Int(l.rawValue)), "exp " + expect)
            try dev.setLight(l, on: true)
            usleep(UInt32(dwell * 1_000_000))
            try dev.setLight(l, on: false)
        }
        try lcd("cycle done", "")
        print("done")
    }
}

/// Split two text lines into the 8 four-character LCD cells (padded / truncated).
func lcdCells(top: String, bottom: String) -> [[UInt8]] {
    func row(_ s: String) -> [UInt8] {
        var b = Array(s.utf8.prefix(AlphaTrackUSB.lcdColumns))
        while b.count < AlphaTrackUSB.lcdColumns { b.append(0x20) }
        return b
    }
    let screen = row(top) + row(bottom)
    return (0..<AlphaTrackUSB.lcdCells).map { cell in
        let start = cell * AlphaTrackUSB.lcdCellWidth
        return Array(screen[start..<start + AlphaTrackUSB.lcdCellWidth])
    }
}

/// Write two lines of text to the LCD.
func cmdLCD(top: String, bottom: String) throws {
    let dev = try AlphaTrackDevice()
    for (cell, chunk) in lcdCells(top: top, bottom: bottom).enumerated() { try dev.writeLCDCell(cell, chunk) }
    print("wrote LCD")
}

/// Send one raw 8-byte output command given as hex bytes (debugging aid).
func cmdSend(_ hexBytes: [String]) throws {
    let bytes = hexBytes.compactMap { UInt8($0, radix: 16) }
    guard bytes.count == hexBytes.count, bytes.count <= AlphaTrackUSB.outputCommandLength else {
        throw NSError(domain: "macalphatrack", code: 64,
                      userInfo: [NSLocalizedDescriptionKey: "send expects up to 8 hex bytes, e.g. send 00 01 00 48 69 20 20 00"])
    }
    var cmd = bytes
    while cmd.count < AlphaTrackUSB.outputCommandLength { cmd.append(0x00) }
    let dev = try AlphaTrackDevice()
    try dev.write(cmd)
    print("sent \(hex(cmd))")
}

/// Search for the fader motor command. Candidate 8-byte commands are sent one by one;
/// the LCD shows the running candidate number so a human can report which one moved
/// the fader. A background reader also logs the raw report in case the device does
/// report motor-driven positions after all.
func cmdFaderProbe(dwell: Double, commandRange: ClosedRange<UInt8>) throws {
    let dev = try AlphaTrackDevice()
    let lock = NSLock()
    var latest: [UInt8]? = nil
    var reportCount = 0
    let reader = Thread {
        while true {
            guard let bytes = try? dev.read() else { break }
            lock.lock(); latest = bytes; reportCount += 1; lock.unlock()
        }
    }
    reader.start()
    func snapshot() -> (raw: [UInt8]?, count: Int) {
        lock.lock(); defer { lock.unlock() }
        return (latest, reportCount)
    }
    func lcd(_ top: String, _ bottom: String) throws {
        for (cell, chunk) in lcdCells(top: top, bottom: bottom).enumerated() { try dev.writeLCDCell(cell, chunk) }
    }
    usleep(2_500_000) // first report arrives ~1.9 s after open
    print("Probing commands \(commandRange), \(dwell) s each. Watch the fader; the LCD shows the PROBE number.")

    /// Ways a 10-bit position might be packed into bytes 2...5 of the command.
    let encodings: [(String, (UInt16) -> [UInt8])] = [
        ("b2=pos>>2 b3=(pos&3)<<6 (like input)", { p in [UInt8(p >> 2), UInt8((p & 3) << 6), 0, 0] }),
        ("b2=hi b3=lo (big-endian 16)",           { p in [UInt8(p >> 8), UInt8(p & 0xff), 0, 0] }),
        ("b2=lo b3=hi (little-endian 16)",        { p in [UInt8(p & 0xff), UInt8(p >> 8), 0, 0] }),
        ("b2=lsb7 b3=msb7 (MIDI pitch bend)",     { p in [UInt8(p & 0x7f), UInt8(p >> 7), 0, 0] }),
        ("b2=msb7 b3=lsb7",                       { p in [UInt8(p >> 7), UInt8(p & 0x7f), 0, 0] }),
        ("b2=pos>>3 (7-bit) b3=0",                { p in [UInt8(p >> 3), 0, 0, 0] }),
        ("b2=pos>>2 (8-bit) b3=0",                { p in [UInt8(p >> 2), 0, 0, 0] }),
        ("b2=0 b3=pos>>2 b4=(pos&3)<<6",          { p in [0, UInt8(p >> 2), UInt8((p & 3) << 6), 0] }),
        ("b2=0 b3=hi b4=lo",                      { p in [0, UInt8(p >> 8), UInt8(p & 0xff), 0] }),
        ("b2=0 b3=pos>>2 (8-bit)",                { p in [0, UInt8(p >> 2), 0, 0] }),
    ]
    var index = 0
    for cmd in commandRange {
        for (name, enc) in encodings {
            index += 1
            // Alternate top/bottom so a valid command always produces visible motion.
            let target: UInt16 = index % 2 == 0 ? 900 : 120
            let command: [UInt8] = [0x00, cmd] + enc(target) + [0x00, 0x00]
            try lcd(String(format: "PROBE %03d", index), String(format: "cmd %02x %@", Int(cmd), target == 900 ? "up" : "down"))
            let before = snapshot()
            try dev.write(command)
            usleep(UInt32(dwell * 1_000_000))
            let after = snapshot()
            print(String(format: "PROBE %03d  cmd %02x  %-40@ sent %@  target %4d  reports +%d  last %@",
                         index, Int(cmd), name, hex(command), Int(target), after.count - before.count, hex(after.raw ?? [])))
        }
    }
    try lcd("probe done", "")
    print("done: \(index) candidates")
    dev.abortReads()
}

/// Run the driver headless until Ctrl-C / SIGTERM.
func cmdRun(verbose: Bool) throws {
    let service = DriverService(verbose: verbose, callbackQueue: DispatchQueue(label: "macalphatrack.log"))
    let iso = ISO8601DateFormatter()
    service.onLog = { message in
        FileHandle.standardError.write("\(iso.string(from: Date())) \(message)\n".data(using: .utf8)!)
    }
    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        src.setEventHandler { service.stop() }
        src.resume()
        signalSources.append(src)
    }
    try service.runUntilStopped()
}
private var signalSources: [DispatchSourceSignal] = []

/// Copy the Ableton Live control-surface script into Live's User Library.
func cmdInstallLive(folder: String?) throws {
    guard let source = LiveScriptInstaller.bundledSource() else {
        throw NSError(domain: "macalphatrack", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot find the LiveRemoteScript/AlphaTrack folder"])
    }
    let detected = LiveScriptInstaller.detectUserLibrary()
    let dest = folder.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        ?? detected?.remoteScriptsFolder
        ?? LiveScriptInstaller.defaultRemoteScriptsFolder
    let installer = LiveScriptInstaller(source: source, remoteScriptsFolder: dest)
    if folder == nil, let detected { print("Live \(detected.liveVersion) User Library: \(detected.userLibrary.path)") }
    print("source:      \(source.path)")
    print("destination: \(installer.destination.path)")
    print("before:      \(installer.status())")
    try installer.install()
    print("after:       \(installer.status())")
    print("Restart Live, then Preferences > Link, Tempo & MIDI > Control Surface: AlphaTrack, Input/Output: AlphaTrack.")
}
