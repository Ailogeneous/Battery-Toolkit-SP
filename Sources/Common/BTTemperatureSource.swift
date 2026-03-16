//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

public enum BTTemperatureSource: UInt8, Sendable {
    case iops = 0
    case smcTB0T
    case smcTB1T
    case smcTB2T
    case smcBATP
}
