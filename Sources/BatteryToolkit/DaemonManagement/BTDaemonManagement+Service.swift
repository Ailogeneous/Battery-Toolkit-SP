//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log
import ServiceManagement

public extension BTDaemonManagement {
    @available(macOS 13.0, *)
    enum Service {
        private static let daemonServicePlist = "\(BTPreprocessor.daemonId).plist"

        @BTBackgroundActor static func register() async -> BTDaemonManagementStatus {
            os_log("Starting daemon service")
            return await self.update()
        }

        @BTBackgroundActor static func upgrade() async -> BTDaemonManagementStatus {
            os_log("Upgrading daemon service")

            do {
                return await self.update()
            } catch {
                return .notRegistered
            }
        }

        static func approve(timeout: UInt8) async throws {
            SMAppService.openSystemSettingsLoginItems()
            try await self.awaitApproval(timeout: timeout)
        }

        @BTBackgroundActor static func unregister() async throws {
            os_log("Unregistering daemon service")
            //
            // Any other status code makes unregister() loop indefinitely.
            //
            let appService = SMAppService.daemon(
                plistName: self.daemonServicePlist
            )
            guard appService.status == .enabled else {
                return
            }

            BTDaemonXPCClient.disconnectDaemon()

            do {
                try await appService.unregister()
                assert(!self.registered(status: appService.status))
            } catch {
                os_log(
                    "Daemon service unregistering failed, error: \(error, privacy: .public)), status: \(appService.status.rawValue)"
                )

                throw BTError.unknown
            }
        }

        private static func registered(status: SMAppService.Status) -> Bool {
            return status != .notRegistered && status != .notFound
        }

        private static func registerSync(appService: SMAppService) {
            os_log("Registering daemon service")

            do {
                try appService.register()
            } catch {
                os_log(
                    "Daemon service registering failed, error: \(error, privacy: .public)), status: \(appService.status.rawValue)"
                )
            }
        }

        @BTBackgroundActor private static func forceRegister() async -> BTDaemonManagementStatus {
            //
            // After unregistering (e.g., to update the daemon), re-registering
            // may fail for a short amount of time.
            //
            for _ in 0...5 {
                let appService = SMAppService.daemon(
                    plistName: self.daemonServicePlist
                )
                self.registerSync(appService: appService)
                if self.registered(status: appService.status) {
                    BTDaemonXPCClient.finishUpdate()
                    return self.status(from: appService.status)
                }

                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            BTDaemonXPCClient.finishUpdate()
            return .notRegistered
        }

        @BTBackgroundActor private static func update() async -> BTDaemonManagementStatus {
            os_log("Updating daemon service")

            try? await BTDaemonXPCClient.prepareUpdate()
            try? await self.unregister()
            return await self.forceRegister()
        }

        private static func awaitApproval(timeout: UInt8) async throws {
            let appService = SMAppService.daemon(
                plistName: self.daemonServicePlist
            )
            for _ in 0...timeout {
                if appService.status == .enabled {
                    return
                }

                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }

            throw BTError.unknown
        }

        private static func status(from status: SMAppService.Status) -> BTDaemonManagementStatus {
            switch status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            default:
                return .notRegistered
            }
        }
    }
}
