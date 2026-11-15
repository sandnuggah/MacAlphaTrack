import Foundation
import CoreMIDI
import AlphaTrackKit

/// A virtual CoreMIDI device named "AlphaTrack": one source (device -> DAW) and one
/// destination (DAW -> device), created with the protocol-based API and declared as
/// MIDI 1.0, so CoreMIDI hands us MIDI 1.0 UMP and downconverts anything newer.
public final class MIDIBridge {
    public static let portName = "AlphaTrack"
    // Stable unique ids so DAWs recognise the ports across restarts.
    private static let sourceUniqueID: Int32 = 0x4d41_5453 // "MATS"
    private static let destinationUniqueID: Int32 = 0x4d41_5444 // "MATD"

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var destination = MIDIEndpointRef()
    private var decoder = UMPDecoder()
    private let decodeQueue = DispatchQueue(label: "macalphatrack.midi-in")
    /// Called with each complete MIDI 1.0 message received on the destination.
    public var onReceive: (([UInt8]) -> Void)?

    public init() throws {
        try check(MIDIClientCreateWithBlock("MacAlphaTrack" as CFString, &client) { _ in }, "MIDIClientCreate")
        try check(MIDISourceCreateWithProtocol(client, MIDIBridge.portName as CFString, ._1_0, &source), "MIDISourceCreate")
        MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, MIDIBridge.sourceUniqueID)
        try check(MIDIDestinationCreateWithProtocol(client, MIDIBridge.portName as CFString, ._1_0, &destination) { [weak self] eventList, _ in
            self?.handle(eventList)
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

    /// Emit one complete MIDI 1.0 message on the source.
    public func send(_ message: [UInt8]) {
        let words = UMP.encode(message)
        guard !words.isEmpty else { return }
        var list = MIDIEventList()
        withUnsafeMutablePointer(to: &list) { listPtr in
            let packet = MIDIEventListInit(listPtr, ._1_0)
            words.withUnsafeBufferPointer { buf in
                _ = MIDIEventListAdd(listPtr, MemoryLayout<MIDIEventList>.size, packet, 0, buf.count, buf.baseAddress!)
            }
            MIDIReceivedEventList(source, listPtr)
        }
    }

    private func handle(_ eventList: UnsafePointer<MIDIEventList>) {
        var words: [UInt32] = []
        for packet in eventList.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            withUnsafeBytes(of: packet.pointee.words) { raw in
                words.append(contentsOf: raw.bindMemory(to: UInt32.self).prefix(count))
            }
        }
        decodeQueue.async { [self] in
            for message in decoder.feed(words) { onReceive?(message) }
        }
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "\(what) failed (\(status))"])
        }
    }
}
