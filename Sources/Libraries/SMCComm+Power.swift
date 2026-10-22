//
// Copyright (C) 2022 - 2025 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log

public extension SMCComm {
    @MainActor
    enum Power {
        private static let chargeKeys = [
            KeyControl.CHTE,
            KeyControl.CH0C
        ]
        private static let adapterKeys = [
            KeyControl.CHIE,
            KeyControl.CH0J
        ]

        private static var chargeKey = 0
        private static var adapterKey = 0

        static func supported() -> Bool {
            if BTNativeCharging27.active {
                guard let index = adapterKeys.firstIndex(where: { SMCComm.keySupported(keyInfo: $0.keyInfo) }), BTNativeCharging27.start() else { return false }
                adapterKey = index
                return true
            }
            //
            // Ensure all required SMC keys are present and well-formed.
            //
            let chargeKey = self.chargeKeys.firstIndex { key in
                SMCComm.keySupported(keyInfo: key.keyInfo)
            }
            guard let chargeKey = chargeKey else {
                os_log("SMC power support failed: no matching charging key; adapter checks not reached")
                return false;
            }
            self.chargeKey = chargeKey
            os_log("SMC selected charging key=%{public}@", SMCComm.diagnosticKeyName(self.chargeKeys[chargeKey].keyInfo.key))
            
            
            let adapterKey = self.adapterKeys.firstIndex { key in
                SMCComm.keySupported(keyInfo: key.keyInfo)
            }
            guard let adapterKey = adapterKey else {
                os_log("SMC power support failed: no matching adapter key")
                return false;
            }
            self.adapterKey = adapterKey
            os_log("SMC selected adapter key=%{public}@", SMCComm.diagnosticKeyName(self.adapterKeys[adapterKey].keyInfo.key))

            return true
        }

        static func enableCharging() -> Bool {
            if BTNativeCharging27.active {
                let limit = BTPowerEvents.chargingMode == .toFull ? 100 : Int(BTSettings.maxCharge)
                return BTNativeCharging27.request(limit: limit, suppressCalibration: BTSettings.maxCharge < 80 && BTPowerEvents.chargingMode != .toFull)
            }
            return SMCComm.writeKey(
                key: self.chargeKeys[self.chargeKey].keyInfo.key,
                bytes: self.chargeKeys[self.chargeKey].onBytes
            )
        }

        static func disableCharging() -> Bool {
            if BTNativeCharging27.active {
                let current = Int(BTPowerState.getPercentRemaining().0)
                let limit = min(Int(BTSettings.minCharge), current)
                return BTNativeCharging27.request(limit: limit, suppressCalibration: BTSettings.maxCharge < 80)
            }
            return SMCComm.writeKey(
                key: self.chargeKeys[self.chargeKey].keyInfo.key,
                bytes: self.chargeKeys[self.chargeKey].offBytes
            )
        }

        static func isChargingDisabled() -> Bool {
            if BTNativeCharging27.active { return BTPowerState.isChargingDisabled() }
            let value = SMCComm.readKey(
                key: self.chargeKeys[self.chargeKey].keyInfo.key,
                dataSize: self.chargeKeys[self.chargeKey].onBytes.count
            )
            guard let value else {
                return false
            }

            return value != self.chargeKeys[self.chargeKey].onBytes
        }

        static func enablePowerAdapter() -> Bool {
            return SMCComm.writeKey(
                key: self.adapterKeys[self.adapterKey].keyInfo.key,
                bytes: self.adapterKeys[self.adapterKey].onBytes
            )
        }

        static func disablePowerAdapter() -> Bool {
            return SMCComm.writeKey(
                key: self.adapterKeys[self.adapterKey].keyInfo.key,
                bytes: self.adapterKeys[self.adapterKey].offBytes
            )
        }

        static func isPowerAdapterDisabled() -> Bool {
            let value = SMCComm.readKey(
                key: self.adapterKeys[self.adapterKey].keyInfo.key,
                dataSize: self.adapterKeys[self.adapterKey].onBytes.count
            )
            guard let value else {
                return false
            }

            return value != self.adapterKeys[self.adapterKey].onBytes
        }

        static func diagnostics() -> [String: NSObject & Sendable] {
            if BTNativeCharging27.active { return BTNativeCharging27.diagnostics() }
            let isSupported = self.supported()
            guard isSupported else {
                return ["smcSupported": NSNumber(value: false)]
            }
            let chargeKey = self.chargeKeys[self.chargeKey].keyInfo.key
            let adapterKey = self.adapterKeys[self.adapterKey].keyInfo.key
            let chargeValue = SMCComm.readKey(key: chargeKey, dataSize: self.chargeKeys[self.chargeKey].onBytes.count)
            let adapterValue = SMCComm.readKey(key: adapterKey, dataSize: self.adapterKeys[self.adapterKey].onBytes.count)
            return [
                "smcSupported": NSNumber(value: true),
                "chargeKey": NSNumber(value: chargeKey),
                "chargeReadSucceeded": NSNumber(value: chargeValue != nil),
                "chargingDisabled": NSNumber(value: self.isChargingDisabled()),
                "adapterKey": NSNumber(value: adapterKey),
                "adapterReadSucceeded": NSNumber(value: adapterValue != nil),
                "powerAdapterDisabled": NSNumber(value: self.isPowerAdapterDisabled())
            ]
        }
    }
}

private extension SMCComm.Power {
    private enum Keys {
        static let CHTE = SMCComm.KeyInfo(
            key: SMCComm.Key("C", "H", "T", "E"),
            info: SMCComm.KeyInfoData(
                dataSize: 4,
                dataType: SMCComm.KeyTypes.ui32,
                dataAttributes: 0xD4
            )
        )
        static let CH0C = SMCComm.KeyInfo(
            key: SMCComm.Key("C", "H", "0", "C"),
            info: SMCComm.KeyInfoData(
                dataSize: 1,
                dataType: SMCComm.KeyTypes.hex,
                dataAttributes: 0xD4
            )
        )
        static let CHIE = SMCComm.KeyInfo(
            key: SMCComm.Key("C", "H", "I", "E"),
            info: SMCComm.KeyInfoData(
                dataSize: 1,
                dataType: SMCComm.KeyTypes.hex,
                dataAttributes: 0xD4
            )
        )
        static let CH0J = SMCComm.KeyInfo(
            key: SMCComm.Key("C", "H", "0", "J"),
            info: SMCComm.KeyInfoData(
                dataSize: 1,
                dataType: SMCComm.KeyTypes.ui8,
                dataAttributes: 0xD4
            )
        )
    }
    
    private struct KeyControl {
        let keyInfo: SMCComm.KeyInfo
        let onBytes: [UInt8]
        let offBytes: [UInt8]

        static let CHTE = KeyControl(
            keyInfo: Keys.CHTE,
            onBytes: [0x00, 0x00, 0x00, 0x00],
            offBytes: [0x01, 0x00, 0x00, 0x00]
        )
        static let CH0C = KeyControl(
            keyInfo: Keys.CH0C,
            onBytes: [0x00],
            offBytes: [0x01]
        )
        static let CHIE = KeyControl(
            keyInfo: Keys.CHIE,
            onBytes: [0x00],
            offBytes: [0x08]
        )
        static let CH0J = KeyControl(
            keyInfo: Keys.CH0J,
            onBytes: [0x00],
            offBytes: [0x20]
        )
    }
}
