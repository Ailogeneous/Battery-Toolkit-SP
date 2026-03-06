//
// Copyright (C) 2024 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import CoreGraphics
import IOKit
import notify
import os.log

public enum IOPSPrivate {
    static let kIOPSNotifyPercentChange = "com.apple.system.powersources.percent"

    private static let kPSTimeRemainingNotifyExternalBit: UInt64 = 1 << 16
    private static let kPSTimeRemainingNotifyChargingBit: UInt64 = 1 << 17
    private static let kPSTimeRemainingNotifyValidBit: UInt64 = 1 << 19
    private static let kPSTimeRemainingNotifyFullyChargedBit: UInt64 = 1 << 21

    static func GetPercentRemaining() -> (UInt8, Bool, Bool)? {
        guard let packedBatteryBits = GetPackedBatteryBits() else {
            return nil
        }

        let percent = UInt8(min((packedBatteryBits & 0xFF), 100))
        let isCharging = ((packedBatteryBits & kPSTimeRemainingNotifyChargingBit) != 0)
        let isFullyCharged = ((packedBatteryBits & kPSTimeRemainingNotifyFullyChargedBit) != 0)

        return (percent, isCharging, isFullyCharged)
    }

    static func DrawingUnlimitedPower() -> Bool {
        guard let packedBatteryBits = GetPackedBatteryBits() else {
            return true
        }

        return (packedBatteryBits & kPSTimeRemainingNotifyExternalBit) != 0
    }

    static func GetBatteryTemperatureCelsius() -> Double? {
        let service = IOServiceGetMatchingService(
            kIOMasterPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else {
            return nil
        }
        defer {
            IOObjectRelease(service)
        }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "Temperature" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }

        let rawValue: Double
        if let number = value as? NSNumber {
            rawValue = number.doubleValue
        } else if let string = value as? String, let parsed = Double(string) {
            rawValue = parsed
        } else {
            return nil
        }

        // AppleSmartBattery reports temperature in deci-Kelvin.
        let celsius = (rawValue / 10.0) - 273.15
        guard celsius.isFinite else {
            return nil
        }

        return celsius
    }

    static func IsClamshellClosed() -> Bool? {
        let service = IOServiceGetMatchingService(
            kIOMasterPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != IO_OBJECT_NULL else {
            return nil
        }
        defer {
            IOObjectRelease(service)
        }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }

        if let boolValue = value as? Bool {
            return boolValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }
        return nil
    }

    static func HasExternalDisplayConnected() -> Bool {
        var displayCount: UInt32 = 0
        let countResult = CGGetOnlineDisplayList(0, nil, &displayCount)
        guard countResult == .success, displayCount > 0 else {
            return false
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        let listResult = CGGetOnlineDisplayList(displayCount, &displays, &displayCount)
        guard listResult == .success else {
            return false
        }

        for display in displays.prefix(Int(displayCount)) {
            if CGDisplayIsBuiltin(display) == 0 {
                return true
            }
        }

        return false
    }
    
    private static func GetPackedBatteryBits() -> UInt64? {
        var token: Int32 = 0
        let status = notify_register_check(kIOPSNotifyPercentChange, &token)
        guard status == NOTIFY_STATUS_OK else {
            os_log("Failed to retrieve packed battery bits - \(status)")
            return nil
        }

        var packedBatteryBits: UInt64 = 0
        notify_get_state(token, &packedBatteryBits)
        notify_cancel(token)

        if ((packedBatteryBits & kPSTimeRemainingNotifyValidBit) == 0) {
            os_log("Invalid packed battery bits - \(packedBatteryBits)")
            return nil
        }

        return packedBatteryBits
    }
}
