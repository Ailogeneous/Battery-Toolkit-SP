//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

public enum BTMagSafeIndicatorMode: UInt8, Sendable {
    case sync = 0
    case system = 1
    case off = 2
    case green = 3
    case orange = 4
    case orangeSlowBlink = 5
    case orangeFastBlink = 6
    case orangeBlinkOff = 7
}
