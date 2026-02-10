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
}
