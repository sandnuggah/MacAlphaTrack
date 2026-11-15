import Foundation
import AlphaTrackKit

let usage = """
macalphatrack – user-space macOS driver for the Frontier AlphaTrack

usage: macalphatrack <command>

commands:
  dump      open the AlphaTrack over USB and print raw input reports (not yet implemented)
  info      print protocol constants this build knows about
  help      show this message
"""

func info() {
    let vid = String(AlphaTrackUSB.vendorID, radix: 16)
    let pid = String(AlphaTrackUSB.productID, radix: 16)
    print("AlphaTrack USB id: \(vid):\(pid)")
    print("Input report: \(AlphaTrackUSB.inputReportLength) bytes, output command: \(AlphaTrackUSB.outputCommandLength) bytes")
    print("Lights known: \(AlphaTrackUSB.Light.allCases.count)")
    print("Native-mode notes known: \(NativeMIDI.Note.allCases.count)")
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "info":
    info()
case "dump":
    FileHandle.standardError.write("dump: not implemented yet (next milestone)\n".data(using: .utf8)!)
    exit(2)
case nil, "help", "-h", "--help":
    print(usage)
default:
    FileHandle.standardError.write("unknown command: \(args[0])\n\n\(usage)\n".data(using: .utf8)!)
    exit(64)
}
