//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

public enum BTDaemonManagementStatus: UInt8 {
    case notRegistered = 0
    case enabled = 1
    case requiresApproval = 2
}
