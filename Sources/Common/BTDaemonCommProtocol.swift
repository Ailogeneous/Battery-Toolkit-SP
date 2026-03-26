//
// Copyright (C) 2022 - 2025 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

public enum BTDaemonCommCommand: UInt8 {
    case disablePowerAdapter
    case enablePowerAdapter
    case chargeToFull
    case chargeToLimit
    case disableCharging
    case prepareUpdate
    case finishUpdate
    case isSupported
    case pauseActivity
    case resumeActivity
    case setPowerMode
    case setMagSafeIndicator
    case setPMSet
}

@objc public protocol BTDaemonCommProtocol {
    func getUniqueId(
        reply: @Sendable @escaping (Data?) -> Void
    )

    func execute(
        authData: Data?,
        command: UInt8,
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    )

    func getState(
        reply: @Sendable @escaping ([String: NSObject & Sendable]) -> Void
    )

    func getSettings(
        reply: @Sendable @escaping ([String: NSObject & Sendable]) -> Void
    )

    func setSettings(
        authData: Data,
        settings: [String: NSObject & Sendable],
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    )

    func setPowerMode(
        authData: Data,
        scope: UInt8,
        mode: UInt8,
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    )

    func setMagSafeIndicator(
        authData: Data,
        mode: UInt8,
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    )

    func setPMSet(
        authData: Data,
        setting: UInt8,
        value: Int,
        scope: UInt8,
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    )

    func setCaffeinate(
        authData: Data,
        flags: UInt32,
        durationSeconds: Int,
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    )

    func setCaffeinateBuckets(
        authData: Data,
        flags: [UInt32],
        durations: [Int],
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    )

    func killCaffeinate(
        authData: Data,
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    )

    func getBatteryTemperature(
        source: UInt8,
        reply: @Sendable @escaping (NSNumber?) -> Void
    )
}
