//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

public struct BTCaffeinateFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let preventUserIdleSystemSleep = BTCaffeinateFlags(rawValue: 1 << 0)
    public static let preventUserIdleDisplaySleep = BTCaffeinateFlags(rawValue: 1 << 1)
    public static let preventDiskIdle = BTCaffeinateFlags(rawValue: 1 << 2)
    public static let preventSystemSleep = BTCaffeinateFlags(rawValue: 1 << 3)
    public static let userIsActive = BTCaffeinateFlags(rawValue: 1 << 4)

    public static let `default`: BTCaffeinateFlags = [.preventUserIdleSystemSleep]
}
