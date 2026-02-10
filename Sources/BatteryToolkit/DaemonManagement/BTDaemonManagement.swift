//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log

public enum BTDaemonManagement {
    @BTBackgroundActor
    public static func start() async -> BTDaemonManagementStatus {
        let daemonId = try? await BTDaemonXPCClient.getUniqueId()
        guard self.daemonUpToDate(daemonId: daemonId) else {
            return await self.Service.register()
        }

        os_log("Daemon is up-to-date, skip install")
        return .enabled
    }

    @BTBackgroundActor
    public static func upgrade() async -> BTDaemonManagementStatus {
        return await self.Service.upgrade()
    }

    public static func approve(timeout: UInt8) async throws {
        try await self.Service.approve(timeout: timeout)
    }

    @BTBackgroundActor
    public static func remove() async throws {
        try await self.Service.unregister()
    }

    private static func daemonUpToDate(daemonId: Data?) -> Bool {
        guard let daemonId else {
            os_log("Daemon unique ID is nil")
            return false
        }

        let bundleId = CSIdentification.getBundleRelativeUniqueId(
            relative: "Contents/Library/LaunchServices/" + BTPreprocessor.daemonId
        )
        guard let bundleId else {
            os_log("Bundle daemon unique ID is nil")
            return false
        }

        return bundleId == daemonId
    }
}
