//
// Copyright (C) 2022 - 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log

@MainActor
internal enum BTEventHub {
    private static var connections: [NSXPCConnection] = []

    static func register(connection: NSXPCConnection) {
        self.connections.append(connection)
    }

    static func unregister(connection: NSXPCConnection) {
        self.connections.removeAll { $0 === connection }
        if self.connections.isEmpty {
            Task { @MainActor in
                _ = await BTFanControl.resetFanControl()
            }
        }
    }

    static func notifyStateChanged() {
        let state = BTDaemon.getState()
        os_log("EventHub notify: %{public}d connections", self.connections.count)
        for connection in self.connections {
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                os_log("XPC event callback failed: \(error, privacy: .public))")
            } as? BTDaemonEventsProtocol
            proxy?.stateDidChange(state)
        }
    }
}
