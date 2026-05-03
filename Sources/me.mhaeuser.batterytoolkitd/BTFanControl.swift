import Foundation
import os.log

@MainActor
enum BTFanControl {
    private static var fanModeKeyIsLower: Bool?
    private static var leaseTimer: DispatchSourceTimer?
    private static var curveTimer: DispatchSourceTimer?
    private static let logger = OSLog(subsystem: "me.mhaeuser.batterytoolkitd", category: "FanControl")

    private static let keyTypeFlt = SMCComm.KeyType("f", "l", "t", " ")
    private static let keyTypeFpe2 = SMCComm.KeyType("f", "p", "e", "2")
    private static let curveRefreshSeconds = 5

    @inline(__always)
    private static func fail(_ error: BTError, _ message: String) -> BTError {
        os_log("%{public}@ error=%{public}u", log: logger, type: .error, message, error.rawValue)
        return error
    }

    private static func toSMCKey(_ key: String) -> SMCComm.Key? {
        guard key.count == 4 else { return nil }
        let chars = Array(key)
        return SMCComm.Key(chars[0], chars[1], chars[2], chars[3])
    }

    private static func readInfo(_ key: String) -> SMCComm.KeyInfoData? {
        guard let smcKey = toSMCKey(key) else { return nil }
        return SMCComm.getKeyInfo(key: smcKey)
    }

    private static func readBytes(_ key: String, size: Int) -> [UInt8]? {
        guard let smcKey = toSMCKey(key) else { return nil }
        return SMCComm.readKey(key: smcKey, dataSize: size)
    }

    private static func writeBytes(_ key: String, bytes: [UInt8]) -> Bool {
        guard let smcKey = toSMCKey(key) else { return false }
        return SMCComm.writeKey(key: smcKey, bytes: bytes)
    }

    private static func writeBytesWithRetry(
        _ key: String,
        bytes: [UInt8],
        attempts: Int = 10,
        delayMicros: useconds_t = 50_000
    ) -> Bool {
        guard attempts > 0 else { return false }
        for attempt in 0..<attempts {
            if writeBytes(key, bytes: bytes) {
                return true
            }
            if attempt < attempts - 1 {
                usleep(delayMicros)
            }
        }
        return false
    }

    private static func readNumericValue(_ key: String) -> Double? {
        guard let info = readInfo(key) else { return nil }
        let size = Int(info.dataSize)
        guard size > 0, let bytes = readBytes(key, size: size) else { return nil }
        if bytes.allSatisfy({ $0 == 0 }) && key != "FS! " && !key.hasPrefix("F") {
            return nil
        }

        switch info.dataType {
        case SMCComm.KeyTypes.ui8:
            return Double(bytes[0])
        case SMCComm.KeyTypes.ui32:
            guard bytes.count >= 4 else { return nil }
            let value = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
            return Double(value)
        case SMCComm.KeyTypes.sp78:
            guard bytes.count >= 2 else { return nil }
            let value = Double(Int(bytes[0]) * 256 + Int(bytes[1]))
            return value / 256.0
        case keyTypeFlt:
            guard bytes.count >= 4 else { return nil }
            let value = bytes.withUnsafeBytes { raw in
                raw.load(fromByteOffset: 0, as: Float.self)
            }
            return Double(value)
        case keyTypeFpe2:
            guard bytes.count >= 2 else { return nil }
            let value = (Int(bytes[0]) << 6) + (Int(bytes[1]) >> 2)
            return Double(value)
        default:
            return nil
        }
    }

    static func readTemperatures(keys: [String]) -> [String: NSObject & Sendable] {
        var out: [String: NSObject & Sendable] = [:]
        for key in keys {
            guard key.count == 4 else { continue }
            if let value = readNumericValue(key) {
                out[key] = NSNumber(value: value)
            }
        }
        return out
    }

    static func fanCount() -> Int {
        return Int(readNumericValue("FNum") ?? 0)
    }

    private static func modeKey(for fanId: Int) -> String {
        if let cached = fanModeKeyIsLower {
            return cached ? "F\(fanId)md" : "F\(fanId)Md"
        }
        let probe = readInfo("F0md")
        fanModeKeyIsLower = (probe?.dataSize ?? 0) > 0
        return fanModeKeyIsLower == true ? "F\(fanId)md" : "F\(fanId)Md"
    }

    static func getFans() -> [[String: NSObject & Sendable]] {
        let count = fanCount()
        guard count > 0 else { return [] }

        var fans: [[String: NSObject & Sendable]] = []
        fans.reserveCapacity(count)

        for id in 0..<count {
            let min = readNumericValue("F\(id)Mn") ?? 0
            let max = readNumericValue("F\(id)Mx") ?? 0
            let current = readNumericValue("F\(id)Ac") ?? 0
            let target = readNumericValue("F\(id)Tg") ?? 0
            let mode = readNumericValue(modeKey(for: id)) ?? 0

            fans.append([
                "id": NSNumber(value: id),
                "min": NSNumber(value: min),
                "max": NSNumber(value: max),
                "current": NSNumber(value: current),
                "target": NSNumber(value: target),
                "mode": NSNumber(value: mode)
            ])
        }

        return fans
    }

    private static func unlockFanControl(fanId: Int) async -> BTError {
        let key = modeKey(for: fanId)
        guard let info = readInfo(key), info.dataSize > 0 else {
            return fail(.fanModeInfoUnavailable, "unlock mode_info fanId=\(fanId) key=\(key)")
        }
        let size = Int(info.dataSize)
        guard var bytes = readBytes(key, size: size) else {
            return fail(.fanModeReadFailed, "unlock mode_read fanId=\(fanId) key=\(key)")
        }
        bytes[0] = 1
        if writeBytesWithRetry(key, bytes: bytes, attempts: 20, delayMicros: 100_000) {
            return .success
        }

        guard let ftstInfo = readInfo("Ftst"), ftstInfo.dataSize > 0 else {
            return fail(.fanUnlockFailed, "unlock ftst_info fanId=\(fanId)")
        }
        let ftstSize = Int(ftstInfo.dataSize)
        guard var ftstBytes = readBytes("Ftst", size: ftstSize) else {
            return fail(.fanUnlockFailed, "unlock ftst_read fanId=\(fanId)")
        }
        if ftstBytes[0] == 1 {
            return writeBytesWithRetry(key, bytes: bytes, attempts: 20, delayMicros: 100_000)
                ? .success
                : fail(.fanModeWriteFailed, "unlock mode_write_after_ftst_ready fanId=\(fanId) key=\(key)")
        }
        ftstBytes[0] = 1
        guard writeBytesWithRetry("Ftst", bytes: ftstBytes, attempts: 100, delayMicros: 50_000) else {
            return fail(.fanUnlockFailed, "unlock ftst_write fanId=\(fanId)")
        }

        try? await Task.sleep(nanoseconds: 3_000_000_000)
        return writeBytesWithRetry(key, bytes: bytes, attempts: 300, delayMicros: 100_000)
            ? .success
            : fail(.fanModeWriteFailed, "unlock mode_write_after_delay fanId=\(fanId) key=\(key)")
    }

    static func setFanMode(fanId: Int, mode: UInt8) async -> BTError {
        let key = modeKey(for: fanId)
        guard let info = readInfo(key), info.dataSize > 0 else {
            return fail(.fanModeInfoUnavailable, "set_mode mode_info fanId=\(fanId) key=\(key)")
        }
        let size = Int(info.dataSize)
        guard var bytes = readBytes(key, size: size) else {
            return fail(.fanModeReadFailed, "set_mode mode_read fanId=\(fanId) key=\(key)")
        }

        if mode == 1 {
            let unlock = await unlockFanControl(fanId: fanId)
            guard unlock == .success else { return unlock }
            bytes[0] = 1
            return writeBytesWithRetry(key, bytes: bytes, attempts: 20, delayMicros: 100_000)
                ? .success
                : fail(.fanModeWriteFailed, "set_mode mode_write_manual fanId=\(fanId) key=\(key)")
        }

        bytes[0] = 0
        let ok = writeBytesWithRetry(key, bytes: bytes, attempts: 10, delayMicros: 50_000)
        guard ok else {
            return fail(.fanModeWriteFailed, "set_mode mode_write_auto fanId=\(fanId) key=\(key)")
        }

        let targetKey = "F\(fanId)Tg"
        guard let targetInfo = readInfo(targetKey), targetInfo.dataSize > 0 else { return .success }
        let targetSize = Int(targetInfo.dataSize)
        guard var targetBytes = readBytes(targetKey, size: targetSize) else { return .success }
        switch targetInfo.dataType {
        case keyTypeFlt:
            let zero = Float(0)
            let zeroBytes = withUnsafeBytes(of: zero, Array.init)
            if targetBytes.count >= 4 {
                targetBytes[0] = zeroBytes[0]
                targetBytes[1] = zeroBytes[1]
                targetBytes[2] = zeroBytes[2]
                targetBytes[3] = zeroBytes[3]
            }
            if !writeBytesWithRetry(targetKey, bytes: targetBytes, attempts: 10, delayMicros: 50_000) {
                return fail(.fanTargetWriteFailed, "set_mode target_clear_write fanId=\(fanId) key=\(targetKey)")
            }
        case keyTypeFpe2:
            if targetBytes.count >= 2 {
                targetBytes[0] = 0
                targetBytes[1] = 0
            }
            if !writeBytesWithRetry(targetKey, bytes: targetBytes, attempts: 10, delayMicros: 50_000) {
                return fail(.fanTargetWriteFailed, "set_mode target_clear_write fanId=\(fanId) key=\(targetKey)")
            }
        default:
            break
        }
        return .success
    }

    static func setFanSpeed(fanId: Int, speed: Int) async -> BTError {
        let max = readNumericValue("F\(fanId)Mx") ?? 0
        let clamped = max > 0 ? min(Double(speed), max) : Double(speed)

        let targetKey = "F\(fanId)Tg"
        guard let info = readInfo(targetKey), info.dataSize > 0 else {
            return fail(.fanTargetInfoUnavailable, "set_speed target_info fanId=\(fanId) key=\(targetKey)")
        }
        let size = Int(info.dataSize)
        guard var bytes = readBytes(targetKey, size: size) else {
            return fail(.fanTargetReadFailed, "set_speed target_read fanId=\(fanId) key=\(targetKey)")
        }

        let modeKey = modeKey(for: fanId)
        if let modeInfo = readInfo(modeKey), modeInfo.dataSize > 0 {
            let modeSize = Int(modeInfo.dataSize)
            guard let modeBytes = readBytes(modeKey, size: modeSize) else {
                return fail(.fanModeReadFailed, "set_speed mode_read fanId=\(fanId) key=\(modeKey)")
            }
            if modeBytes.first != 1 {
                let unlock = await unlockFanControl(fanId: fanId)
                guard unlock == .success else { return unlock }
            }
        }

        switch info.dataType {
        case keyTypeFlt:
            let value = Float(clamped)
            let valueBytes = withUnsafeBytes(of: value, Array.init)
            if bytes.count >= 4 {
                bytes[0] = valueBytes[0]
                bytes[1] = valueBytes[1]
                bytes[2] = valueBytes[2]
                bytes[3] = valueBytes[3]
            }
        case keyTypeFpe2:
            let intValue = Int(clamped)
            if bytes.count >= 2 {
                bytes[0] = UInt8(intValue >> 6)
                bytes[1] = UInt8((intValue << 2) ^ ((intValue >> 6) << 8))
            }
        default:
            return fail(.fanUnsupportedDataType, "set_speed unsupported_type fanId=\(fanId) key=\(targetKey)")
        }

        return writeBytesWithRetry(targetKey, bytes: bytes, attempts: 10, delayMicros: 50_000)
            ? .success
            : fail(.fanTargetWriteFailed, "set_speed target_write fanId=\(fanId) key=\(targetKey) speed=\(Int(clamped.rounded()))")
    }

    static func setFanControlLease(percent: Int, durationSeconds: Int) async -> BTError {
        if percent < 0 {
            return await setFanCurveLease(durationSeconds: durationSeconds)
        }

        let count = fanCount()
        guard count > 0 else {
            return fail(.fanCountUnavailable, "lease fan_count_unavailable fixed")
        }
        let clampedPercent = min(100, max(0, percent))
        let duration = max(30, durationSeconds)
        curveTimer?.cancel()
        curveTimer = nil
        let applyResult = await applyFanPercent(clampedPercent)
        guard applyResult == .success else {
            _ = await resetFanControl()
            return applyResult
        }
        scheduleLeaseExpiry(durationSeconds: duration)
        return .success
    }

    private static func setFanCurveLease(durationSeconds: Int) async -> BTError {
        let duration = max(30, durationSeconds)
        let applyResult = await applyAggressiveCurve()
        guard applyResult == .success else {
            _ = await resetFanControl()
            return applyResult
        }

        curveTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.setEventHandler {
            Task { @MainActor in
                let tickResult = await applyAggressiveCurve()
                guard tickResult == .success else {
                    _ = await resetFanControl()
                    return
                }
            }
        }
        timer.schedule(deadline: .now() + .seconds(curveRefreshSeconds), repeating: .seconds(curveRefreshSeconds))
        timer.resume()
        curveTimer = timer
        scheduleLeaseExpiry(durationSeconds: duration)
        return .success
    }

    private static func scheduleLeaseExpiry(durationSeconds: Int) {
        leaseTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.setEventHandler {
            Task { @MainActor in
                _ = await resetFanControl()
            }
        }
        timer.schedule(deadline: .now() + .seconds(durationSeconds))
        timer.resume()
        leaseTimer = timer
    }

    private static func applyAggressiveCurve() async -> BTError {
        let tempKeys = [
            "Tp01", "Tp05", "Tp09", "Tp0D",
            "Tp0j", "Tp0m",
            "Tg05", "Tg0D", "Tg0L",
            "Ts0P", "Ts1P",
            "TB0T", "TB1T", "TB2T",
            "TL0P", "Tm0P",
            "Tn0P", "Tn1P"
        ]

        let tempsRaw = readTemperatures(keys: tempKeys)
        func temp(_ key: String) -> Double? {
            return (tempsRaw[key] as? NSNumber)?.doubleValue
        }

        let cpuPerf = [temp("Tp01"), temp("Tp05"), temp("Tp09"), temp("Tp0D")].compactMap { $0 }.max() ?? 0
        let cpuEff = [temp("Tp0j"), temp("Tp0m")].compactMap { $0 }.max() ?? 0
        let gpu = [temp("Tg05"), temp("Tg0D"), temp("Tg0L")].compactMap { $0 }.max() ?? 0
        let skin = [temp("Ts0P"), temp("Ts1P")].compactMap { $0 }.max() ?? 0
        let battery = [temp("TB0T"), temp("TB1T"), temp("TB2T")].compactMap { $0 }.max() ?? 0
        let logic = [temp("TL0P"), temp("Tm0P")].compactMap { $0 }.max() ?? 0
        let ssd = [temp("Tn0P"), temp("Tn1P")].compactMap { $0 }.max() ?? 0

        let score = max(
            cpuPerf * 1.02,
            cpuEff,
            gpu * 1.02,
            logic,
            ssd * 0.95,
            skin * 0.9,
            battery * 0.85
        )

        let percent: Int
        switch score {
        case ..<71:
            percent = 0
        case ..<72:
            percent = 5
        case ..<73:
            percent = 10
        case ..<74:
            percent = 15
        case ..<75:
            percent = 20
        case ..<76:
            percent = 25
        case ..<77:
            percent = 30
        case ..<78:
            percent = 35
        case ..<79:
            percent = 40
        case ..<80:
            percent = 45
        case ..<81:
            percent = 50
        case ..<82:
            percent = 55
        case ..<83:
            percent = 60
        case ..<84:
            percent = 65
        case ..<85:
            percent = 70
        case ..<86:
            percent = 75
        case ..<87:
            percent = 80
        case ..<88:
            percent = 85
        case ..<89:
            percent = 90
        case ..<90:
            percent = 95
        default:
            percent = 100
        }

        return await applyFanPercent(percent)
    }

    private static func applyFanPercent(_ percent: Int) async -> BTError {
        let count = fanCount()
        guard count > 0 else {
            return fail(.fanCountUnavailable, "apply_percent fan_count_unavailable")
        }
        let clampedPercent = min(100, max(0, percent))
        var firstError: BTError?

        for id in 0..<count {
            let minRPM = readNumericValue("F\(id)Mn") ?? 0
            let maxRPM = readNumericValue("F\(id)Mx") ?? 0
            guard maxRPM > 0 else {
                if firstError == nil {
                    firstError = fail(.fanTargetInfoUnavailable, "apply_percent fan_max_unavailable fanId=\(id)")
                }
                continue
            }
            let lower = minRPM > 0 ? minRPM : 0
            let target = Int((lower + ((maxRPM - lower) * (Double(clampedPercent) / 100.0))).rounded())
            let modeResult = await setFanMode(fanId: id, mode: 1)
            if modeResult != .success {
                if firstError == nil { firstError = modeResult }
                continue
            }
            let speedResult = await setFanSpeed(fanId: id, speed: target)
            if speedResult != .success, firstError == nil {
                firstError = speedResult
            }
        }

        return firstError ?? .success
    }

    static func resetFanControlNow() -> BTError {
        leaseTimer?.cancel()
        leaseTimer = nil
        curveTimer?.cancel()
        curveTimer = nil
        var firstError: BTError?

        if let info = readInfo("Ftst"), info.dataSize > 0 {
            let size = Int(info.dataSize)
            if var bytes = readBytes("Ftst", size: size) {
                if bytes[0] != 0 {
                    bytes[0] = 0
                    if !writeBytesWithRetry("Ftst", bytes: bytes, attempts: 10, delayMicros: 50_000) {
                        if firstError == nil {
                            firstError = fail(.fanResetFailed, "reset ftst_write_failed")
                        }
                    }
                }
            } else if firstError == nil {
                firstError = fail(.fanResetFailed, "reset ftst_read_failed")
            }
        }

        let count = fanCount()
        guard count > 0 else {
            return firstError ?? fail(.fanCountUnavailable, "reset fan_count_unavailable")
        }
        for id in 0..<count {
            let key = modeKey(for: id)
            guard let info = readInfo(key), info.dataSize > 0 else {
                if firstError == nil {
                    firstError = fail(.fanModeInfoUnavailable, "reset mode_info_unavailable fanId=\(id) key=\(key)")
                }
                continue
            }
            let size = Int(info.dataSize)
            guard var bytes = readBytes(key, size: size) else {
                if firstError == nil {
                    firstError = fail(.fanModeReadFailed, "reset mode_read_failed fanId=\(id) key=\(key)")
                }
                continue
            }
            if bytes[0] == 0 { continue }
            bytes[0] = 0
            if !writeBytesWithRetry(key, bytes: bytes, attempts: 10, delayMicros: 50_000), firstError == nil {
                firstError = fail(.fanModeWriteFailed, "reset mode_write_failed fanId=\(id) key=\(key)")
            }
        }
        return firstError ?? .success
    }

    static func resetFanControl() async -> BTError {
        return resetFanControlNow()
    }
}
