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
    case womp = 5
    case powernap = 6
    case proximitywake = 7
    case lidwake = 8
    case acwake = 9
    case autorestart = 10
    case halfdim = 11
    case lessbright = 12

    var cliName: String {
        switch self {
        case .hibernatemode: return "hibernatemode"
        case .standby: return "standby"
        case .standbydelaylow: return "standbydelaylow"
        case .standbydelayhigh: return "standbydelayhigh"
        case .highstandbythreshold: return "highstandbythreshold"
        case .womp: return "womp"
        case .powernap: return "powernap"
        case .proximitywake: return "proximitywake"
        case .lidwake: return "lidwake"
        case .acwake: return "acwake"
        case .autorestart: return "autorestart"
        case .halfdim: return "halfdim"
        case .lessbright: return "lessbright"
        }
    }
}
