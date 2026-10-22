import Foundation
import IOKit
import ObjectiveC
import os.log

@objc(BTArchivedChargePolicy27)
private final class BTArchivedChargePolicy27: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    var limit: Int
    var owner: Int
    var reason: NSString
    var token: NSUUID
    var drain: Bool
    var inhibitFull: Bool
    var eoc: Bool
    var terminated: Bool

    init(limit: Int, inhibitFull: Bool) {
        self.limit = limit
        self.owner = Int(getpid())
        self.reason = "BatteryToolkit.macOS27"
        self.token = NSUUID()
        self.drain = false
        self.inhibitFull = inhibitFull
        self.eoc = true
        self.terminated = false
        super.init()
    }

    required init?(coder: NSCoder) {
        self.limit = coder.decodeInteger(forKey: "soclimit")
        self.owner = coder.decodeInteger(forKey: "owner")
        self.reason = coder.decodeObject(of: NSString.self, forKey: "reason") ?? ""
        self.token = coder.decodeObject(of: NSUUID.self, forKey: "token") ?? NSUUID()
        self.drain = coder.decodeBool(forKey: "drain")
        self.inhibitFull = coder.decodeBool(forKey: "noChargeToFull")
        self.eoc = coder.decodeBool(forKey: "isEndOfCharge")
        self.terminated = coder.decodeBool(forKey: "terminated")
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(limit, forKey: "soclimit")
        coder.encode(owner, forKey: "owner")
        coder.encode(reason, forKey: "reason")
        coder.encode(token, forKey: "token")
        coder.encode(drain, forKey: "drain")
        coder.encode(inhibitFull, forKey: "noChargeToFull")
        coder.encode(eoc, forKey: "isEndOfCharge")
        coder.encode(terminated, forKey: "terminated")
    }
}

@MainActor
internal enum BTNativeCharging27 {
    static var active: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 }
    private static let topoffDomain = "com.apple.smartcharging.topoffprotection" as CFString
    private static let topoffKeys = ["mclLimitValue", "MCLFeatureState"]
    private static var submissionSucceeded = false
    private static let domain = "com.apple.powerd.charging" as CFString
    private static let directory = URL(fileURLWithPath: "/Library/Application Support/BatteryToolkit/macOS27", isDirectory: true)
    private static var snapshotURL: URL { directory.appendingPathComponent("original.plist") }
    private static var journalURL: URL { directory.appendingPathComponent("charging.jsonl") }
    private static var timer: DispatchSourceTimer?
    private static var logProcess: Process?
    private static var logPipe: Pipe?
    private static var requested: Int?
    private static var suppress = false
    private static var attempts = 0
    private static var lastWrite = Date.distantPast
    private static var boot: String?

    static func start() -> Bool {
        guard active, geteuid() == 0 else { return false }
        if timer != nil { return true }
        guard SMCComm.readKey(key: SMCComm.Key("C", "H", "L", "T"), dataSize: 3)?.count == 3 else { return false }
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0 else { return false }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else { return false }
        boot = String(cString: bytes)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if !FileManager.default.fileExists(atPath: snapshotURL.path) {
                let original = preferences()
                var topoff: [String: Any] = [:]
                for key in topoffKeys {
                    if let value = CFPreferencesCopyValue(key as CFString, topoffDomain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) { topoff[key] = value }
                }
                let record: [String: Any] = ["boot": boot!, "preferences": original, "topoff": topoff]
                let data = try PropertyListSerialization.data(fromPropertyList: record, format: .binary, options: 0)
                try data.write(to: snapshotURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshotURL.path)
            }
            timer?.cancel()
            let source = DispatchSource.makeTimerSource(queue: .main)
            source.schedule(deadline: .now() + 15, repeating: 15)
            source.setEventHandler { MainActor.assumeIsolated { sampleAndReconcile() } }
            source.resume()
            timer = source
            journal("start", extra: ["boot": boot!])
            startSystemLog()
            return true
        } catch {
            os_log("macOS27 native startup failed %{public}@", error.localizedDescription)
            return false
        }
    }

    private static func preferences() -> [String: Any] {
        CFPreferencesCopyMultiple(nil, domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost) as? [String: Any] ?? [:]
    }

    private static func policies() throws -> [BTArchivedChargePolicy27] {
        guard let data = preferences()["policies"] as? Data else { return [] }
        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
        decoder.requiresSecureCoding = true
        decoder.decodingFailurePolicy = .setErrorAndReturn
        decoder.setClass(BTArchivedChargePolicy27.self, forClassName: "ChargeCtrlPolicy")
        let objects = decoder.decodeObject(of: [NSArray.self, BTArchivedChargePolicy27.self, NSString.self, NSUUID.self], forKey: NSKeyedArchiveRootObjectKey) as? [BTArchivedChargePolicy27]
        decoder.finishDecoding()
        if let error = decoder.error { throw error }
        guard let objects else { throw NSError(domain: "BTNativeCharging27", code: 1) }
        return objects
    }

    @discardableResult
    static func request(limit: Int, suppressCalibration: Bool) -> Bool {
        guard active, boot != nil, (20...100).contains(limit) else { return false }
        let inhibit = suppressCalibration && limit < 80
        if requested == limit && suppress == inhibit { return submissionSucceeded }
        requested = limit
        suppress = inhibit
        attempts = 0
        journal("request", extra: ["limit": limit, "noChargeToFull": inhibit])
        submissionSucceeded = writePolicy()
        return submissionSucceeded
    }

    private static func releaseSystemLimit() -> Bool {
        guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW) != nil,
              let type = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
              let allocated = type.perform(NSSelectorFromString("alloc"))?.takeRetainedValue() as? NSObject,
              let client = allocated.perform(NSSelectorFromString("initWithClientName:"), with: "BatteryToolkit.macOS27")?.takeUnretainedValue() as? NSObject else { return false }
        let selector = NSSelectorFromString("setMCLLimit:error:")
        guard client.responds(to: selector), let method = class_getInstanceMethod(type, selector) else { return false }
        typealias Setter = @convention(c) (AnyObject, Selector, UInt8, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool
        let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)
        var error: NSError?
        let accepted = setter(client, selector, 100, &error)
        journal("system-policy-released", extra: ["accepted": accepted, "error": error?.localizedDescription ?? "none"])
        return accepted && error == nil
    }

    private static func writePolicy() -> Bool {
        guard let requested, let boot else { return false }
        do {
            guard releaseSystemLimit() else { throw NSError(domain: "BTNativeCharging27", code: 3, userInfo: [NSLocalizedDescriptionKey: "PowerUI could not release its ordinary policy"]) }
            let current = preferences()
            let sameBoot = (current["bootSessionUUID"] as? String) == boot
            var entries = sameBoot ? try policies() : []
            entries.removeAll { $0.reason == "BatteryToolkit.macOS27" }
            if requested < 100 {
                entries.append(BTArchivedChargePolicy27(limit: requested, inhibitFull: suppress))
            }
            let encoder = NSKeyedArchiver(requiringSecureCoding: true)
            encoder.setClassName("ChargeCtrlPolicy", for: BTArchivedChargePolicy27.self)
            encoder.encode(entries as NSArray, forKey: NSKeyedArchiveRootObjectKey)
            encoder.finishEncoding()
            CFPreferencesSetMultiple(["bootSessionUUID": boot, "policies": encoder.encodedData] as CFDictionary, nil, domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost)
            guard CFPreferencesSynchronize(domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost) else { throw NSError(domain: "BTNativeCharging27", code: 2) }
            lastWrite = Date()
            attempts += 1
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["-HUP", "powerd"]
            try process.run()
            process.waitUntilExit()
            journal("policy-written", extra: ["signalExit": Int(process.terminationStatus), "attempt": attempts])
            return process.terminationStatus == 0
        } catch {
            attempts += 1
            lastWrite = Date()
            journal("write-failed", extra: ["error": error.localizedDescription, "attempt": attempts])
            return false
        }
    }

    static func sampleAndReconcile() {
        let observation = batteryObservation()
        journal("sample", extra: observation)
        guard let requested, Date().timeIntervalSince(lastWrite) >= 45 else { return }
        let expected = requested == 100 ? 0 : requested
        let state = SMCComm.readKey(key: SMCComm.Key("C", "H", "L", "T"), dataSize: 3)
        let expectedFlags = requested == 100 ? 0 : (suppress ? 6 : 4)
        if let state, state.count == 3, Int(state[0]) == expected, Int(state[1]) == expectedFlags {
            attempts = 0
        } else if attempts < 3 {
            journal("policy-drift", extra: ["observedSMC": state?.map { String(format: "%02x", $0) }.joined() ?? "unavailable"])
            submissionSucceeded = writePolicy()
        }
    }

    static func suspend() {
        timer?.cancel()
        timer = nil
        logPipe?.fileHandleForReading.readabilityHandler = nil
        if logProcess?.isRunning == true { logProcess?.terminate() }
        logProcess = nil
        logPipe = nil
    }

    static func restore() -> Bool {
        guard active, let boot else { return false }
        suspend()
        do {
            let data = try Data(contentsOf: snapshotURL)
            guard let record = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], let original = record["preferences"] as? [String: Any] else { return false }
            guard let topoff = record["topoff"] as? [String: Any] else { journal("restore-failed", extra: ["error": "snapshot missing topoff values"]); return false }
            for key in topoffKeys { CFPreferencesSetValue(key as CFString, topoff[key] as CFPropertyList?, topoffDomain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) }
            guard CFPreferencesSynchronize(topoffDomain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else { return false }
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName("com.apple.smartcharging.defaultschanged" as CFString), nil, nil, true)
            let entries = try policies().filter { $0.reason != "BatteryToolkit.macOS27" }
            if entries.isEmpty, record["boot"] as? String == boot {
                let keys = ["bootSessionUUID", "policies"]
                for key in keys { CFPreferencesSetValue(key as CFString, original[key] as CFPropertyList?, domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost) }
            } else {
                let encoder = NSKeyedArchiver(requiringSecureCoding: true)
                encoder.setClassName("ChargeCtrlPolicy", for: BTArchivedChargePolicy27.self)
                encoder.encode(entries as NSArray, forKey: NSKeyedArchiveRootObjectKey)
                encoder.finishEncoding()
                CFPreferencesSetValue("policies" as CFString, encoder.encodedData as CFData, domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost)
            }
            guard CFPreferencesSynchronize(domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost) else { return false }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["-HUP", "powerd"]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return false }
            requested = nil
            journal("restored")
            try FileManager.default.removeItem(at: snapshotURL)
            return true
        } catch { journal("restore-failed", extra: ["error": error.localizedDescription]); return false }
    }

    private static func batteryObservation() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return ["battery": "unavailable"] }
        defer { IOObjectRelease(service) }
        var values: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &values, kCFAllocatorDefault, 0) == KERN_SUCCESS, let properties = values?.takeRetainedValue() as? [String: Any] else { return [:] }
        var result: [String: Any] = [:]
        for key in ["ExternalConnected", "IsCharging", "CurrentCapacity", "Amperage", "InstantAmperage", "Voltage", "BatteryData"] {
            if let value = properties[key], key != "BatteryData" {
                if ["Amperage", "InstantAmperage"].contains(key), let number = value as? NSNumber { result[key] = number.int64Value }
                else { result[key] = value }
            }
        }
        if let state = SMCComm.readKey(key: SMCComm.Key("C", "H", "L", "T"), dataSize: 3) { result["CHLT"] = state.map { String(format: "%02x", $0) }.joined() }
        if let requested { result["requestedLimit"] = requested }
        result["noChargeToFull"] = suppress
        return result
    }

    static func diagnostics() -> [String: NSObject & Sendable] {
        var values: [String: NSObject & Sendable] = [
            "smcSupported": NSNumber(value: timer != nil),
            "nativeCharging27": NSNumber(value: true),
            "nativePolicySubmitted": NSNumber(value: submissionSucceeded),
            "nativeNoChargeToFull": NSNumber(value: suppress),
            "nativeRetryCount": NSNumber(value: attempts)
        ]
        if let requested { values["nativeRequestedLimit"] = NSNumber(value: requested) }
        if let state = SMCComm.readKey(key: SMCComm.Key("C", "H", "L", "T"), dataSize: 3) {
            values["nativeSMCState"] = NSNumber(value: state.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
        }
        return values
    }

    private static func startSystemLog() {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "ndjson", "--level", "info", "--predicate", "(process == 'powerd' OR process == 'PowerUIAgent') AND (eventMessage CONTAINS[c] 'gauging' OR eventMessage CONTAINS[c] 'mitigation' OR eventMessage CONTAINS[c] 'MCL' OR eventMessage CONTAINS[c] 'SOC limit' OR eventMessage CONTAINS[c] 'chargingtofulloverride')"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                journal("system-log", extra: ["text": text])
            }
        }
        do {
            try process.run()
            logProcess = process
            logPipe = pipe
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            journal("system-log-unavailable", extra: ["error": error.localizedDescription])
        }
    }

    private static func journal(_ event: String, extra: [String: Any] = [:]) {
        var record = extra
        record["event"] = event
        record["time"] = ISO8601DateFormatter().string(from: Date())
        do {
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) + Data([10])
            if let size = try? journalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 8 * 1024 * 1024 {
                let previous = directory.appendingPathComponent("charging.previous.jsonl")
                if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
                try FileManager.default.moveItem(at: journalURL, to: previous)
            }
            if !FileManager.default.fileExists(atPath: journalURL.path) { FileManager.default.createFile(atPath: journalURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            let handle = try FileHandle(forWritingTo: journalURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            os_log("macOS27 charging %{public}@", String(data: data, encoding: .utf8) ?? event)
        } catch { os_log("macOS27 charging journal failure %{public}@", error.localizedDescription) }
    }
}
