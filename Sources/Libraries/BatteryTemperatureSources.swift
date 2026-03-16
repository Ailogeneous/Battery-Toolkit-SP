//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

public enum BatteryTemperatureSources {
    public static func read(source: BTTemperatureSource) -> Double? {
        switch source {
        case .iops:
            return IOPSPrivate.GetBatteryTemperatureCelsius()
        case .smcTB0T:
            return readSMCTemperature(key: SMCComm.Key("T", "B", "0", "T"))
        case .smcTB1T:
            return readSMCTemperature(key: SMCComm.Key("T", "B", "1", "T"))
        case .smcTB2T:
            return readSMCTemperature(key: SMCComm.Key("T", "B", "2", "T"))
        case .smcBATP:
            return readSMCTemperature(key: SMCComm.Key("B", "A", "T", "P"))
        }
    }

    private static func readSMCTemperature(key: SMCComm.Key) -> Double? {
        return SMCComm.withSession {
            guard let info = SMCComm.getKeyInfo(key: key) else {
                return nil
            }

            let dataSize = Int(info.dataSize)
            guard let bytes = SMCComm.readKey(key: key, dataSize: dataSize) else {
                return nil
            }

            if info.dataType == SMCComm.KeyTypes.sp78 || dataSize >= 2 {
                return parseSP78(bytes)
            }

            return nil
        }
    }

    private static func parseSP78(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 2 else {
            return nil
        }

        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let signed = Int16(bitPattern: raw)
        return Double(signed) / 256.0
    }
}
