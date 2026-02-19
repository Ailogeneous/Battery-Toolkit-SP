//
// Copyright (C) 2022 - 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

@objc public protocol BTDaemonEventsProtocol {
    func stateDidChange(_ state: [String: NSObject & Sendable])
}
