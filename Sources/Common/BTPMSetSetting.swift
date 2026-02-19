//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

public enum BTPMSetSetting: UInt8 {
    case hibernatemode = 0
    case standby = 1
    case standbydelaylow = 2
    case standbydelayhigh = 3
    case highstandbythreshold = 4

    var cliName: String {
        switch self {
        case .hibernatemode: return "hibernatemode"
        case .standby: return "standby"
        case .standbydelaylow: return "standbydelaylow"
        case .standbydelayhigh: return "standbydelayhigh"
        case .highstandbythreshold: return "highstandbythreshold"
        }
    }
}
