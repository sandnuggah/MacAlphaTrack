import Foundation
import AlphaTrackKit

let usage = """
macalphatrack – user-space macOS driver for the Frontier AlphaTrack

usage: macalphatrack <command> [args]

commands:
  run [--verbose]        run the driver: virtual MIDI device "AlphaTrack" speaking Native mode
  descriptors            open the device and list its USB endpoints
  dump [--all] [-t SEC]  print raw 12-byte input reports (changes only unless --all)
  lights [on|off]        cycle every light id (default), or switch all on/off
  lcd "TOP" "BOTTOM"     write two 16-character lines to the LCD
  send b0 b1 ... b7      send one raw 8-byte output command (hex)
  info                   print protocol constants this build knows about
  help                   show this message
"""

func info() {
    print("AlphaTrack USB id: \(String(AlphaTrackUSB.vendorID, radix: 16)):\(String(AlphaTrackUSB.productID, radix: 16))")
    print("Input report: \(AlphaTrackUSB.inputReportLength) bytes, output command: \(AlphaTrackUSB.outputCommandLength) bytes")
    print("Lights known: \(AlphaTrackUSB.Light.allCases.count)")
    print("Native-mode notes known: \(NativeMIDI.Note.allCases.count)")
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write("macalphatrack: \(message)\n".data(using: .utf8)!)
    exit(code)
}

// Line-buffer stdout so dump output reaches pipes and log files promptly.
setvbuf(stdout, nil, _IOLBF, 0)

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "info":
        info()
    case "run":
        try cmdRun(verbose: args.contains("--verbose") || args.contains("-v"))
    case "descriptors":
        try cmdDescriptors()
    case "dump":
        var seconds: Double? = nil
        if let i = args.firstIndex(of: "-t"), i + 1 < args.count { seconds = Double(args[i + 1]) }
        try cmdDump(showAll: args.contains("--all"), seconds: seconds)
    case "lights":
        try cmdLights(args.count > 1 ? args[1] : nil)
    case "lcd":
        guard args.count >= 2 else { fail("usage: lcd \"TOP\" [\"BOTTOM\"]", code: 64) }
        try cmdLCD(top: args[1], bottom: args.count > 2 ? args[2] : "")
    case "send":
        try cmdSend(Array(args.dropFirst()))
    case nil, "help", "-h", "--help":
        print(usage)
    default:
        fail("unknown command: \(args[0])\n\n\(usage)", code: 64)
    }
} catch {
    fail("\(error)")
}
