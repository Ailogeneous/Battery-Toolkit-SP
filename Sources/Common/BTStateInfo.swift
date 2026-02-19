//
// Copyright (C) 2022 - 2025 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

public enum BTStateInfo {
    public enum ChargingMode: UInt8 {
        case standard = 0
        case toLimit = 1
        case toFull = 2
    }

    public enum ChargingProgress: UInt8 {
        case belowMax = 0
        case belowFull = 1
        case full = 2
    }

    public enum Keys {
        public static let enabled = "Enabled"
        public static let powerDisabled = "PowerDisabled"
        public static let connected = "Connected"
        public static let chargingDisabled = "ChargingDisabled"
        public static let progress = "Progress"
        public static let chargingMode = "Mode"
        public static let maxCharge = "MaxCharge"
        public static let batteryPercent = "BatteryPercent"
        public static let isCharging = "IsCharging"
        public static let isACConnected = "IsACConnected"
        public static let batteryTemperature = "BatteryTemperature"
        public static let powerModeAll = "PowerModeAll"
        public static let powerModeBattery = "PowerModeBattery"
        public static let powerModeCharger = "PowerModeCharger"
    }
}
