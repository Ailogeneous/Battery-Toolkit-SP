//
// Copyright (C) 2022 - 2024 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log

import NSXPCConnectionAuditToken
import Security

internal enum BTDaemonXPCServer {
    @MainActor private static let listener = NSXPCListener(
        machServiceName: BTPreprocessor.daemonConn
    )

    private static let delegate: Delegate = Delegate()

    private static let daemonComm = BTDaemonComm()

    @MainActor static func start() {
        self.listener.delegate = self.delegate
        self.listener.resume()
    }
}

private extension BTDaemonXPCServer {
    final class Delegate: NSObject, NSXPCListenerDelegate, Sendable {
        func listener(
            _: NSXPCListener,
            shouldAcceptNewConnection newConnection: NSXPCConnection
        ) -> Bool {
            guard BTXPCValidation.isValidClient(connection: newConnection)
            else {
                os_log("XPC server connection by invalid client")
                return false
            }

            newConnection.exportedInterface = NSXPCInterface(with: BTDaemonCommProtocol.self)
            newConnection.exportedObject = BTDaemonXPCServer.daemonComm
            newConnection.remoteObjectInterface = NSXPCInterface(with: BTDaemonEventsProtocol.self)

            newConnection.invalidationHandler = { [weak newConnection] in
                guard let connection = newConnection else { return }
                Task { @MainActor in
                    BTEventHub.unregister(connection: connection)
                }
            }
            newConnection.interruptionHandler = { [weak newConnection] in
                guard let connection = newConnection else { return }
                Task { @MainActor in
                    BTEventHub.unregister(connection: connection)
                }
            }

            Task { @MainActor in
                BTEventHub.register(connection: newConnection)
                BTEventHub.notifyStateChanged()
            }
            newConnection.resume()

            return true
        }
    }
}
