import Foundation

@MainActor
enum BTFanControl {
    private static var fanModeKeyIsLower: Bool?

    private static let keyTypeFlt = SMCComm.KeyType("f", "l", "t", " ")
    private static let keyTypeFpe2 = SMCComm.KeyType("f", "p", "e", "2")

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

    private static func unlockFanControl(fanId: Int) async -> Bool {
        let key = modeKey(for: fanId)
        guard let info = readInfo(key), info.dataSize > 0 else { return false }
        let size = Int(info.dataSize)
        guard var bytes = readBytes(key, size: size) else { return false }
        bytes[0] = 1
        if writeBytes(key, bytes: bytes) {
            return true
        }

        guard let ftstInfo = readInfo("Ftst"), ftstInfo.dataSize > 0 else {
            return false
        }
        let ftstSize = Int(ftstInfo.dataSize)
        guard var ftstBytes = readBytes("Ftst", size: ftstSize) else { return false }
        if ftstBytes[0] == 1 {
            return writeBytes(key, bytes: bytes)
        }
        ftstBytes[0] = 1
        guard writeBytes("Ftst", bytes: ftstBytes) else { return false }

        try? await Task.sleep(nanoseconds: 3_000_000_000)
        return writeBytes(key, bytes: bytes)
    }

    static func setFanMode(fanId: Int, mode: UInt8) async -> Bool {
        let key = modeKey(for: fanId)
        guard let info = readInfo(key), info.dataSize > 0 else { return false }
        let size = Int(info.dataSize)
        guard var bytes = readBytes(key, size: size) else { return false }

        if mode == 1 {
            guard await unlockFanControl(fanId: fanId) else { return false }
            bytes[0] = 1
            return writeBytes(key, bytes: bytes)
        }

        bytes[0] = 0
        let ok = writeBytes(key, bytes: bytes)
        guard ok else { return false }

        let targetKey = "F\(fanId)Tg"
        guard let targetInfo = readInfo(targetKey), targetInfo.dataSize > 0 else { return ok }
        let targetSize = Int(targetInfo.dataSize)
        guard var targetBytes = readBytes(targetKey, size: targetSize) else { return ok }
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
            _ = writeBytes(targetKey, bytes: targetBytes)
        case keyTypeFpe2:
            if targetBytes.count >= 2 {
                targetBytes[0] = 0
                targetBytes[1] = 0
            }
            _ = writeBytes(targetKey, bytes: targetBytes)
        default:
            break
        }
        return ok
    }

    static func setFanSpeed(fanId: Int, speed: Int) async -> Bool {
        let max = readNumericValue("F\(fanId)Mx") ?? 0
        let clamped = max > 0 ? min(Double(speed), max) : Double(speed)

        let targetKey = "F\(fanId)Tg"
        guard let info = readInfo(targetKey), info.dataSize > 0 else { return false }
        let size = Int(info.dataSize)
        guard var bytes = readBytes(targetKey, size: size) else { return false }

        let modeKey = modeKey(for: fanId)
        if let modeInfo = readInfo(modeKey), modeInfo.dataSize > 0 {
            let modeSize = Int(modeInfo.dataSize)
            if let modeBytes = readBytes(modeKey, size: modeSize), modeBytes.first != 1 {
                guard await unlockFanControl(fanId: fanId) else { return false }
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
            return false
        }

        return writeBytes(targetKey, bytes: bytes)
    }

    static func resetFanControl() async -> Bool {
        if let info = readInfo("Ftst"), info.dataSize > 0 {
            let size = Int(info.dataSize)
            if var bytes = readBytes("Ftst", size: size) {
                if bytes[0] == 0 { return true }
                bytes[0] = 0
                return writeBytes("Ftst", bytes: bytes)
            }
        }

        let count = fanCount()
        guard count > 0 else { return false }
        var ok = true
        for id in 0..<count {
            let key = modeKey(for: id)
            guard let info = readInfo(key), info.dataSize > 0 else { continue }
            let size = Int(info.dataSize)
            guard var bytes = readBytes(key, size: size) else { continue }
            if bytes[0] == 0 { continue }
            bytes[0] = 0
            if !writeBytes(key, bytes: bytes) { ok = false }
        }
        return ok
    }
}
