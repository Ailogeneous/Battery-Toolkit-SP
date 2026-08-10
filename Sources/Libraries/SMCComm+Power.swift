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
            //
            // Ensure all required SMC keys are present and well-formed.
            //
            let chargeKey = self.chargeKeys.firstIndex { key in
                let actualInfo = SMCComm.getKeyInfo(key: key.keyInfo.key)
                let supported = actualInfo.map {
                    SMCComm.KeyInfoDataEq(data1: key.keyInfo.info, data2: $0)
                } ?? false
                os_log(
                    "SMC charge key probe key=%{public}@ expectedSize=%{public}u expectedType=%{public}@ expectedAttributes=0x%{public}X actual=%{public}@ supported=%{public}@",
                    self.keyName(key.keyInfo.key),
                    key.keyInfo.info.dataSize,
                    self.typeName(key.keyInfo.info.dataType),
                    key.keyInfo.info.dataAttributes,
                    actualInfo.map { self.infoName($0) } ?? "missing",
                    supported.description
                )
                return supported
            }
            guard let chargeKey = chargeKey else {
                os_log("SMC charging control unsupported: no matching charge key")
                return false;
            }
            self.chargeKey = chargeKey
            
            
            let adapterKey = self.adapterKeys.firstIndex { key in
                let actualInfo = SMCComm.getKeyInfo(key: key.keyInfo.key)
                let supported = actualInfo.map {
                    SMCComm.KeyInfoDataEq(data1: key.keyInfo.info, data2: $0)
                } ?? false
                os_log(
                    "SMC adapter key probe key=%{public}@ expectedSize=%{public}u expectedType=%{public}@ expectedAttributes=0x%{public}X actual=%{public}@ supported=%{public}@",
                    self.keyName(key.keyInfo.key),
                    key.keyInfo.info.dataSize,
                    self.typeName(key.keyInfo.info.dataType),
                    key.keyInfo.info.dataAttributes,
                    actualInfo.map { self.infoName($0) } ?? "missing",
                    supported.description
                )
                return supported
            }
            guard let adapterKey = adapterKey else {
                os_log("SMC adapter control unsupported: no matching adapter key")
                return false;
            }
            self.adapterKey = adapterKey

            os_log(
                "SMC power controls supported chargeKey=%{public}@ adapterKey=%{public}@",
                self.keyName(self.chargeKeys[self.chargeKey].keyInfo.key),
                self.keyName(self.adapterKeys[self.adapterKey].keyInfo.key)
            )

            return true
        }

        static func enableCharging() -> Bool {
            return self.write(
                key: self.chargeKeys[self.chargeKey].keyInfo.key,
                bytes: self.chargeKeys[self.chargeKey].onBytes,
                operation: "enableCharging"
            )
        }

        static func disableCharging() -> Bool {
            return self.write(
                key: self.chargeKeys[self.chargeKey].keyInfo.key,
                bytes: self.chargeKeys[self.chargeKey].offBytes,
                operation: "disableCharging"
            )
        }

        static func isChargingDisabled() -> Bool {
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
            return self.write(
                key: self.adapterKeys[self.adapterKey].keyInfo.key,
                bytes: self.adapterKeys[self.adapterKey].onBytes,
                operation: "enablePowerAdapter"
            )
        }

        static func disablePowerAdapter() -> Bool {
            return self.write(
                key: self.adapterKeys[self.adapterKey].keyInfo.key,
                bytes: self.adapterKeys[self.adapterKey].offBytes,
                operation: "disablePowerAdapter"
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

        private static func write(
            key: SMCComm.Key,
            bytes: [UInt8],
            operation: String
        ) -> Bool {
            let writeResult = SMCComm.writeKey(key: key, bytes: bytes)
            let readback = SMCComm.readKey(key: key, dataSize: bytes.count)
            let readbackMatches = readback == bytes
            os_log(
                "SMC power write operation=%{public}@ key=%{public}@ requested=%{public}@ writeResult=%{public}@ readback=%{public}@ readbackMatches=%{public}@",
                operation,
                self.keyName(key),
                bytes.description,
                writeResult.description,
                readback?.description ?? "missing",
                readbackMatches.description
            )
            return writeResult && readbackMatches
        }

        private static func keyName(_ key: SMCComm.Key) -> String {
            let bytes: [UInt8] = [
                UInt8((key >> 24) & 0xFF),
                UInt8((key >> 16) & 0xFF),
                UInt8((key >> 8) & 0xFF),
                UInt8(key & 0xFF)
            ]
            return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08X", key)
        }

        private static func typeName(_ type: SMCComm.KeyType) -> String {
            self.keyName(type)
        }

        private static func infoName(_ info: SMCComm.KeyInfoData) -> String {
            "size=\(info.dataSize) type=\(self.typeName(info.dataType)) attributes=\(info.dataAttributes)"
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
