//
// Copyright (C) 2022 - 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Combine
import Foundation

public enum BTDaemonEventCenter {
    private static let subject = PassthroughSubject<[String: NSObject & Sendable], Never>()

    public static var statePublisher: AnyPublisher<[String: NSObject & Sendable], Never> {
        subject.eraseToAnyPublisher()
    }

    @BTBackgroundActor public static func start() {
        BTDaemonXPCClient.startEventStream { state in
            Task { @MainActor in
                subject.send(state)
            }
        }
    }

    @BTBackgroundActor public static func stop() {
        BTDaemonXPCClient.stopEventStream()
    }
}
