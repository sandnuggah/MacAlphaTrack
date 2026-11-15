import Foundation
import CoreMIDI
import AlphaTrackKit

/// A virtual CoreMIDI device named "AlphaTrack": one source (device -> DAW) and one
/// destination (DAW -> device). Uses the MIDI 1.0 packet-list API, which is
/// deprecated but far simpler for SysEx than UMP and still fully functional.
public final class MIDIBridge {
    public static let portName = "AlphaTrack"
    // Stable unique ids so DAWs recognise the ports across restarts.
    private static let sourceUniqueID: Int32 = 0x4d41_5453 // "MATS"
    private static let destinationUniqueID: Int32 = 0x4d41_5444 // "MATD"

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var destination = MIDIEndpointRef()
    private var parser = MIDIParser()
    private let parserQueue = DispatchQueue(label: "macalphatrack.midi-in")
    /// Called with each complete MIDI message received on the destination.
    public var onReceive: (([UInt8]) -> Void)?

    public init() throws {
        try check(MIDIClientCreateWithBlock("MacAlphaTrack" as CFString, &client) { _ in }, "MIDIClientCreate")
        try check(MIDISourceCreate(client, MIDIBridge.portName as CFString, &source), "MIDISourceCreate")
        MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, MIDIBridge.sourceUniqueID)
        try check(MIDIDestinationCreateWithBlock(client, MIDIBridge.portName as CFString, &destination) { [weak self] packetList, _ in
            self?.handle(packetList)
        }, "MIDIDestinationCreate")
        MIDIObjectSetIntegerProperty(destination, kMIDIPropertyUniqueID, MIDIBridge.destinationUniqueID)
        for endpoint in [source, destination] {
            MIDIObjectSetStringProperty(endpoint, kMIDIPropertyManufacturer, "Frontier Design Group" as CFString)
            MIDIObjectSetStringProperty(endpoint, kMIDIPropertyModel, "AlphaTrack" as CFString)
        }
    }

    deinit {
        MIDIEndpointDispose(destination)
        MIDIEndpointDispose(source)
        MIDIClientDispose(client)
    }

    /// Emit one complete MIDI message on the source.
    public func send(_ message: [UInt8]) {
        guard !message.isEmpty else { return }
        let size = 64 + message.count
        var storage = [UInt8](repeating: 0, count: size)
        storage.withUnsafeMutableBytes { raw in
            let list = raw.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
            var packet = MIDIPacketListInit(list)
            packet = MIDIPacketListAdd(list, size, packet, 0, message.count, message)
            MIDIReceived(source, list)
        }
    }

    private func handle(_ packetList: UnsafePointer<MIDIPacketList>) {
        var bytes: [UInt8] = []
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            let length = Int(packet.length)
            withUnsafeBytes(of: &packet.data) { bytes.append(contentsOf: $0.prefix(length)) }
            packet = MIDIPacketNext(&packet).pointee
        }
        parserQueue.async { [self] in
            for message in parser.feed(bytes) { onReceive?(message) }
        }
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "\(what) failed (\(status))"])
        }
    }
}
