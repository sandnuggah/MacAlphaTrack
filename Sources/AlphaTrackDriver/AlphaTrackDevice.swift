import Foundation
import IOKit
import IOUSBHost
import AlphaTrackKit

public enum DeviceError: Error, CustomStringConvertible {
    case notFound
    case noInterface
    case noEndpoints
    case shortWrite(Int)

    public var description: String {
        switch self {
        case .notFound: return "no AlphaTrack found (vendor 0x165b, product 0xfad1). Is it plugged in?"
        case .noInterface: return "device configured but no USB interface appeared"
        case .noEndpoints: return "could not find interrupt IN/OUT endpoints on interface 0"
        case .shortWrite(let n): return "short write: \(n) bytes"
        }
    }
}

public struct EndpointInfo: CustomStringConvertible {
    public let address: UInt8
    public let attributes: UInt8
    public let maxPacketSize: UInt16
    public let interval: UInt8

    public var isIn: Bool { address & 0x80 != 0 }
    public var isInterrupt: Bool { attributes & 0x03 == 0x03 }
    public var description: String {
        let kind = ["control", "isochronous", "bulk", "interrupt"][Int(attributes & 0x03)]
        return String(format: "ep 0x%02x %@ %@ maxPacket=%d interval=%d",
                      address, isIn ? "IN " : "OUT", kind, maxPacketSize, interval)
    }
}

/// Raw USB access to one AlphaTrack via IOUSBHost (user space, no kext).
public final class AlphaTrackDevice {
    private let device: IOUSBHostDevice
    private let interface: IOUSBHostInterface
    private let inPipe: IOUSBHostPipe
    private let outPipe: IOUSBHostPipe
    public let endpoints: [EndpointInfo]
    public let inEndpoint: EndpointInfo
    public let outEndpoint: EndpointInfo

    /// Find, configure and open the first AlphaTrack. Exclusive access.
    public init() throws {
        let matching = IOUSBHostDevice.__createMatchingDictionary(
            withVendorID: NSNumber(value: AlphaTrackUSB.vendorID),
            productID: NSNumber(value: AlphaTrackUSB.productID),
            bcdDevice: nil, deviceClass: nil, deviceSubclass: nil,
            deviceProtocol: nil, speed: nil, productIDArray: nil)
        // IOServiceGetMatchingService consumes one reference to the dictionary.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching.takeRetainedValue())
        guard service != 0 else { throw DeviceError.notFound }
        defer { IOObjectRelease(service) }

        device = try IOUSBHostDevice(__ioService: service, options: [], queue: nil, interestHandler: nil)

        // macOS leaves vendor-specific devices unconfigured; select config 1 so the
        // interface nub exists, then parse the descriptor to find our endpoints.
        let config = try device.configurationDescriptor(withConfigurationValue: 1)
        endpoints = AlphaTrackDevice.parseEndpoints(config)
        try device.__configure(withValue: 1, matchInterfaces: true)

        guard let inEp = endpoints.first(where: { $0.isIn && $0.isInterrupt }),
              let outEp = endpoints.first(where: { !$0.isIn && $0.isInterrupt })
        else { throw DeviceError.noEndpoints }
        inEndpoint = inEp
        outEndpoint = outEp

        interface = try AlphaTrackDevice.openInterface(of: device)
        inPipe = try interface.copyPipe(withAddress: Int(inEp.address))
        outPipe = try interface.copyPipe(withAddress: Int(outEp.address))
    }

    deinit {
        interface.destroy()
        device.destroy()
    }

    /// Blocking read of one interrupt IN transfer. IOUSBHost forbids timeouts on
    /// interrupt pipes, so this blocks until data arrives or `abortReads()` is called,
    /// in which case it returns nil.
    public func read() throws -> [UInt8]? {
        let buffer = NSMutableData(length: Int(inEndpoint.maxPacketSize))!
        var transferred: UInt = 0
        var attempt = 0
        while true {
            do {
                try inPipe.__sendIORequest(with: buffer, bytesTransferred: &transferred, completionTimeout: 0)
                return Array(buffer.prefix(Int(transferred)))
            } catch let e as NSError where e.code == Int(kIOReturnAborted) {
                return nil
            } catch let e as NSError where attempt < maxRetries {
                // Full-speed devices occasionally fail a transaction (kIOReturnNotResponding).
                // Clear the endpoint and try again instead of tearing down.
                attempt += 1
                log("read error \(ioReturnName(e.code)), clearing pipe and retrying (\(attempt)/\(maxRetries))")
                try? inPipe.clearStall()
                usleep(50_000)
            }
        }
    }

    private let maxRetries = 5

    private func log(_ message: String) {
        FileHandle.standardError.write("macalphatrack: \(message)\n".data(using: .utf8)!)
    }

    private func ioReturnName(_ code: Int) -> String {
        switch Int32(truncatingIfNeeded: code) {
        case kIOReturnNotResponding: return "kIOReturnNotResponding"
        case kIOReturnTimeout: return "kIOReturnTimeout"
        case kIOReturnNoDevice: return "kIOReturnNoDevice"
        case kIOReturnBadArgument: return "kIOReturnBadArgument"
        default: return String(format: "0x%08x", UInt32(truncatingIfNeeded: code))
        }
    }

    /// Cancel a blocked `read()` from another thread.
    public func abortReads() {
        try? inPipe.__abort(with: .asynchronous)
    }

    /// Blocking write of one 8-byte command.
    public func write(_ command: [UInt8]) throws {
        precondition(command.count == AlphaTrackUSB.outputCommandLength)
        let data = NSMutableData(bytes: command, length: command.count)
        var transferred: UInt = 0
        do {
            try outPipe.__sendIORequest(with: data, bytesTransferred: &transferred, completionTimeout: 0)
        } catch let e as NSError where e.code != Int(kIOReturnAborted) {
            log("write error \(ioReturnName(e.code)), clearing pipe and retrying once")
            try? outPipe.clearStall()
            usleep(50_000)
            try outPipe.__sendIORequest(with: data, bytesTransferred: &transferred, completionTimeout: 0)
        }
        guard Int(transferred) == command.count else { throw DeviceError.shortWrite(Int(transferred)) }
    }

    public func setLight(_ light: AlphaTrackUSB.Light, on: Bool) throws {
        try write(AlphaTrackUSB.lightCommand(light, on: on))
    }

    public func writeLCDCell(_ cell: Int, _ chars: [UInt8]) throws {
        try write(AlphaTrackUSB.lcdCellCommand(cell: cell, chars: chars))
    }

    // MARK: - helpers

    private static func parseEndpoints(_ config: UnsafePointer<IOUSBConfigurationDescriptor>) -> [EndpointInfo] {
        let total = Int(config.pointee.wTotalLength)
        let bytes = UnsafeRawPointer(config).assumingMemoryBound(to: UInt8.self)
        var result: [EndpointInfo] = []
        var offset = 0
        while offset + 2 <= total {
            let length = Int(bytes[offset])
            let type = bytes[offset + 1]
            guard length >= 2 else { break }
            if type == 0x05, length >= 7 { // ENDPOINT descriptor
                result.append(EndpointInfo(
                    address: bytes[offset + 2],
                    attributes: bytes[offset + 3],
                    maxPacketSize: UInt16(bytes[offset + 4]) | (UInt16(bytes[offset + 5]) << 8),
                    interval: bytes[offset + 6]))
            }
            offset += length
        }
        return result
    }

    /// The interface nub can take a moment to register after configure(); poll briefly.
    private static func openInterface(of device: IOUSBHostDevice) throws -> IOUSBHostInterface {
        for _ in 0..<50 {
            var iterator: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(device.ioService, kIOServicePlane, &iterator) == KERN_SUCCESS {
                defer { IOObjectRelease(iterator) }
                var child = IOIteratorNext(iterator)
                while child != 0 {
                    defer { IOObjectRelease(child); child = IOIteratorNext(iterator) }
                    if IOObjectConformsTo(child, "IOUSBHostInterface") != 0 {
                        return try IOUSBHostInterface(__ioService: child, options: [], queue: nil, interestHandler: nil)
                    }
                }
            }
            usleep(20_000)
        }
        throw DeviceError.noInterface
    }
}
