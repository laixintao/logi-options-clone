import Foundation
import IOKit.hid

enum Failure: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case .message(let s): return s } }
}

final class HIDConnection {
    let device: IOHIDDevice
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    var reports: [[UInt8]] = []
    init(_ device: IOHIDDevice) throws {
        self.device = device
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw Failure.message("Cannot open HID device: \(result). Check Input Monitoring permission.") }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, _, _, bytes, count in
            guard result == kIOReturnSuccess, let context else { return }
            let connection = Unmanaged<HIDConnection>.fromOpaque(context).takeUnretainedValue()
            connection.reports.append(Array(UnsafeBufferPointer(start: bytes, count: count)))
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }
    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deallocate()
    }
    func request(slot: UInt8, feature: UInt8, function: UInt8, params: [UInt8] = [], attempts: Int = 3) throws -> [UInt8] {
        var lastError: Error = Failure.message("No response")
        for _ in 0..<attempts {
            do { return try exchange(slot: slot, feature: feature, function: function, params: params) }
            catch { lastError = error }
        }
        throw lastError
    }
    private func exchange(slot: UInt8, feature: UInt8, function: UInt8, params: [UInt8]) throws -> [UInt8] {
        reports.removeAll()
        let fn = (function << 4) | 0x0D
        var packet: [UInt8] = [0x10, slot, feature, fn] + params
        packet += Array(repeating: 0, count: max(0, 7 - packet.count))
        let result = packet.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(packet[0]), $0.baseAddress!, packet.count) }
        guard result == kIOReturnSuccess else { throw Failure.message("HID request failed: \(result)") }
        let deadline = Date().addingTimeInterval(0.7)
        while Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, true)
            for report in reports where report.count >= 7 && report[1] == slot {
                if report[2] == feature && report[3] == fn { return report }
                if report[2] == 0xFF && report[3] == feature && report[4] == fn {
                    throw Failure.message("HID++ error: \(report[5])")
                }
            }
            reports.removeAll()
        }
        throw Failure.message("HID++ response timed out (slot \(slot))")
    }
}

struct Mouse {
    let connection: HIDConnection
    let slot: UInt8
    let feature: UInt8
    let identity: String
    func dpi() throws -> Int {
        let r = try connection.request(slot: slot, feature: feature, function: 2, params: [0])
        return Int(r[5]) * 256 + Int(r[6])
    }
    func setDPI(_ value: Int) throws {
        guard (100...65535).contains(value) else { throw Failure.message("Invalid DPI") }
        _ = try connection.request(slot: slot, feature: feature, function: 3,
                                   params: [0, UInt8(value >> 8), UInt8(value & 255)])
        guard try dpi() == value else { throw Failure.message("Mouse did not retain requested DPI") }
    }
}

func discover() throws -> [Mouse] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x046D] as CFDictionary)
    // Opening only the vendor interface avoids claiming keyboard or pointer input.
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
    var mice: [Mouse] = []
    for device in devices {
        let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
        guard page >= 0xFF00 else { continue }
        let connection: HIDConnection
        do { connection = try HIDConnection(device) }
        catch { fputs("\(error)\n", stderr); continue }
        for slot: UInt8 in [1, 2, 3, 4, 5, 6, 0xFF] {
            guard let reply = try? connection.request(slot: slot, feature: 0, function: 0, params: [0x22, 0x01], attempts: 1), reply[4] != 0 else { continue }
            guard let infoFeature = try? connection.request(slot: slot, feature: 0, function: 0, params: [0, 3]), infoFeature[4] != 0,
                  let info = try? connection.request(slot: slot, feature: infoFeature[4], function: 0), info.count >= 9 else { continue }
            let identity = info[5...8].map { String(format: "%02x", $0) }.joined()
            guard identity != "00000000" else { continue }
            let mouse = Mouse(connection: connection, slot: slot, feature: reply[4], identity: identity)
            if let dpi = try? mouse.dpi(), dpi > 0 {
                mice.append(mouse)
            }
        }
    }
    return mice
}

struct Configuration: Codable {
    let identity: String
    let dpi: Int
}

func restore(_ config: Configuration, force: Bool = false) throws -> Bool {
    for mouse in try discover() where mouse.identity == config.identity {
        let current = try mouse.dpi()
        if force || current != config.dpi {
            try mouse.setDPI(config.dpi)
            print("\(Date()): verified DPI \(current) -> \(config.dpi)")
            fflush(stdout)
        }
        return true
    }
    return false
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    let command = args.first ?? "probe"
    switch command {
    case "probe", "capture":
        let mice = try discover()
        guard !mice.isEmpty else { throw Failure.message("No accessible Logitech mouse with adjustable DPI found. Wake the mouse and check Input Monitoring permission.") }
        if command == "probe" {
            for mouse in mice { print("id=\(mouse.identity) slot=\(mouse.slot) dpi=\(try mouse.dpi())") }
        } else {
            guard args.count == 2, mice.count == 1 else { throw Failure.message("Usage: mouse-speed capture CONFIG.json (exactly one mouse must be connected)") }
            let config = Configuration(identity: mice[0].identity, dpi: try mice[0].dpi())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: URL(fileURLWithPath: args[1]), options: .atomic)
            print("Saved current DPI \(config.dpi)")
        }
    case "apply", "watch":
        guard args.count == 2 else { throw Failure.message("Usage: mouse-speed \(command) CONFIG.json") }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        guard (100...65535).contains(config.dpi), config.identity.count == 8 else { throw Failure.message("Invalid configuration") }
        if command == "apply" {
            guard try restore(config, force: true) else { throw Failure.message("Configured mouse is not connected or accessible") }
        } else {
            // Polling also covers mouse power cycles and wake without requiring accessibility event taps.
            // Each pass reopens the device so stale handles after USB reconnect are discarded.
            var previousError: String?
            while true {
                autoreleasepool {
                    do {
                        _ = try restore(config)
                        previousError = nil
                    } catch {
                        let message = String(describing: error)
                        if message != previousError { fputs("\(Date()): \(message)\n", stderr) }
                        previousError = message
                    }
                }
                Thread.sleep(forTimeInterval: 5)
            }
        }
    default:
        throw Failure.message("Usage: mouse-speed [probe | capture CONFIG.json | apply CONFIG.json | watch CONFIG.json]")
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
