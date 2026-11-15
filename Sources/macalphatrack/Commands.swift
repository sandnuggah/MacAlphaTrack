import Foundation
import AlphaTrackKit

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
func cmdLights(_ arg: String?) throws {
    let dev = try AlphaTrackDevice()
    switch arg {
    case "on":
        for l in AlphaTrackUSB.Light.allCases { try dev.setLight(l, on: true) }
        print("all lights on")
    case "off", nil where arg == "off":
        for l in AlphaTrackUSB.Light.allCases { try dev.setLight(l, on: false) }
        print("all lights off")
    default:
        for l in AlphaTrackUSB.Light.allCases { try dev.setLight(l, on: false) }
        print("Cycling light ids 0...22, 700 ms each. Note which LED lights for each id.")
        for l in AlphaTrackUSB.Light.allCases {
            print("  id \(l.rawValue) (\(l))")
            try dev.setLight(l, on: true)
            usleep(700_000)
            try dev.setLight(l, on: false)
        }
        print("done")
    }
}

/// Write two lines of text to the LCD.
func cmdLCD(top: String, bottom: String) throws {
    let dev = try AlphaTrackDevice()
    func row(_ s: String) -> [UInt8] {
        var b = Array(s.utf8.prefix(AlphaTrackUSB.lcdColumns))
        while b.count < AlphaTrackUSB.lcdColumns { b.append(0x20) }
        return b
    }
    let screen = row(top) + row(bottom)
    for cell in 0..<AlphaTrackUSB.lcdCells {
        let start = cell * AlphaTrackUSB.lcdCellWidth
        try dev.writeLCDCell(cell, Array(screen[start..<start + AlphaTrackUSB.lcdCellWidth]))
    }
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
