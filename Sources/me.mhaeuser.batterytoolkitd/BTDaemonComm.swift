//
// Copyright (C) 2022 - 2025 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log
import ServiceManagement

internal final class BTDaemonComm: NSObject, BTDaemonCommProtocol, Sendable {
    func getUniqueId(
        reply: @Sendable @escaping (Data?) -> Void
    ) {
        Task { @MainActor in
            reply(BTDaemon.getUniqueId())
        }
    }

    func execute(
        authData: Data?,
        command: UInt8,
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    ) {
        Task { @MainActor in
            switch command {
            //
            // Report the supported state to the client, so that it can, e.g.,
            // cleanly uninstall itself if it is unsupported.
            //
            case BTDaemonCommCommand.isSupported.rawValue:
                reply(
                    BTDaemon.supported ?
                        BTError.success.rawValue :
                        BTError.unsupported.rawValue
                )
                return
            //
            // The update commands are optional notifications that allow to
            // optimise the process. Usually, the platform power state is reset
            // to its defaults when the daemon exits. These signals may be used
            // to temporarily override this behaviour to preserve the state
            // instead.
            //
            case BTDaemonCommCommand.prepareUpdate.rawValue:
                os_log("Preparing update")
                BTPowerEvents.updating = true
                reply(BTError.success.rawValue)
                return
            case BTDaemonCommCommand.finishUpdate.rawValue:
                os_log("Update finished")
                BTPowerEvents.updating = false
                reply(BTError.success.rawValue)
                return

            default:
                //
                // Power state management functions may only be invoked when
                // supported.
                //
                guard BTDaemon.supported else {
                    reply(BTError.unsupported.rawValue)
                    return
                }

                switch command {
                case BTDaemonCommCommand.enablePowerAdapter.rawValue:
                    let success = BTPowerState.enablePowerAdapter()
                    reply(BTError(fromBool: success).rawValue)
                    Task { @MainActor in
                        BTEventHub.notifyStateChanged()
                    }
                    return
                case BTDaemonCommCommand.chargeToFull.rawValue:
                    let success = BTPowerEvents.chargeToFull()
                    reply(BTError(fromBool: success).rawValue)
                    Task { @MainActor in
                        BTEventHub.notifyStateChanged()
                    }
                    return
                case BTDaemonCommCommand.chargeToLimit.rawValue:
                    let success = BTPowerEvents.chargeToLimit()
                    reply(BTError(fromBool: success).rawValue)
                    Task { @MainActor in
                        BTEventHub.notifyStateChanged()
                    }
                    return
                    
                case BTDaemonCommCommand.disablePowerAdapter.rawValue:
                    let authorized = self.checkRight(
                        authData: authData,
                        rightName: BTAuthorizationRights.manage
                    )
                    guard authorized else {
                        reply(BTError.notAuthorized.rawValue)
                        return
                    }

                    let success = BTPowerState.disablePowerAdapter()
                    reply(BTError(fromBool: success).rawValue)
                    Task { @MainActor in
                        BTEventHub.notifyStateChanged()
                    }
                    return

                case BTDaemonCommCommand.disableCharging.rawValue:
                    let authorized = self.checkRight(
                        authData: authData,
                        rightName: BTAuthorizationRights.manage
                    )
                    guard authorized else {
                        reply(BTError.notAuthorized.rawValue)
                        return
                    }

                    let success = BTPowerEvents.disableCharging()
                    reply(BTError(fromBool: success).rawValue)
                    Task { @MainActor in
                        BTEventHub.notifyStateChanged()
                    }
                    return

                case BTDaemonCommCommand.pauseActivity.rawValue:
                    let authorized = self.checkRight(
                        authData: authData,
                        rightName: BTAuthorizationRights.manage
                    )
                    guard authorized else {
                        reply(BTError.notAuthorized.rawValue)
                        return
                    }

                    BTDaemon.pause()
                    reply(BTError.success.rawValue)
                    Task { @MainActor in
                        BTEventHub.notifyStateChanged()
                    }
                    return

                case BTDaemonCommCommand.resumeActivity.rawValue:
                    let authorized = self.checkRight(
                        authData: authData,
                        rightName: BTAuthorizationRights.manage
                    )
                    guard authorized else {
                        reply(BTError.notAuthorized.rawValue)
                        return
                    }

                    BTDaemon.resume()
                    reply(BTError.success.rawValue)
                    Task { @MainActor in
                        BTEventHub.notifyStateChanged()
                    }
                    return

                default:
                    os_log("Unknown command: \(command)")
                    reply(BTError.commFailed.rawValue)
                    return
                }
            }
        }
    }

    func getState(
        reply: @Sendable @escaping ([String: NSObject & Sendable]) -> Void
    ) {
        Task { @MainActor in
            guard BTDaemon.supported else {
                reply([:])
                return
            }
            
            reply(BTDaemon.getState())
        }
    }

    func getSettings(
        reply: @Sendable @escaping ([String: NSObject & Sendable]) -> Void
    ) {
        Task { @MainActor in
            guard BTDaemon.supported else {
                reply([:])
                return
            }
            
            reply(BTSettings.getSettings())
        }
    }

    func setSettings(
        authData: Data,
        settings: [String: NSObject & Sendable],
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    ) {
        Task { @MainActor in
            //
            // Power state management functions may only be invoked when
            // supported.
            //
            guard BTDaemon.supported else {
                reply(BTError.unsupported.rawValue)
                return
            }
            
            let authorized = self.checkRight(
                authData: authData,
                rightName: BTAuthorizationRights.manage
            )
            guard authorized else {
                reply(BTError.notAuthorized.rawValue)
                return
            }
            
            BTSettings.setSettings(settings: settings) { result in
                if result == BTError.success.rawValue {
                    Task { @MainActor in
                        BTEventHub.notifyStateChanged()
                    }
                }
                reply(result)
            }
        }
    }

    func setPowerMode(
        authData: Data,
        scope: UInt8,
        mode: UInt8,
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    ) {
        Task { @MainActor in
            guard BTDaemon.supported else {
                reply(BTError.unsupported.rawValue)
                return
            }

            let authorized = self.checkRight(
                authData: authData,
                rightName: BTAuthorizationRights.manage
            )
            guard authorized else {
                reply(BTError.notAuthorized.rawValue)
                return
            }

            guard let scope = BTPowerModeScope(rawValue: scope) else {
                reply(BTError.unknown.rawValue)
                return
            }

            // Use the updated set method that auto-detects supported mode type
            let success = BTPowerMode.set(scope: scope, mode: mode)
            let result = BTError(fromBool: success).rawValue
            if result == BTError.success.rawValue {
                Task { @MainActor in
                    BTEventHub.notifyStateChanged()
                }
            }
            reply(result)
        }
    }

    func setMagSafeIndicator(
        authData: Data,
        mode: UInt8,
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    ) {
        Task { @MainActor in
            guard BTDaemon.supported else {
                reply(BTError.unsupported.rawValue)
                return
            }

            let authorized = self.checkRight(
                authData: authData,
                rightName: BTAuthorizationRights.manage
            )
            guard authorized else {
                reply(BTError.notAuthorized.rawValue)
                return
            }

            guard let mode = BTMagSafeIndicatorMode(rawValue: mode) else {
                reply(BTError.malformedData.rawValue)
                return
            }

            let success = BTPowerState.setMagSafeIndicator(mode: mode)
            reply(BTError(fromBool: success).rawValue)
        }
    }


    func setPMSet(
        authData: Data,
        setting: UInt8,
        value: Int,
        scope: UInt8,
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    ) {
        Task { @MainActor in
            guard BTDaemon.supported else {
                reply(BTError.unsupported.rawValue)
                return
            }

            let authorized = self.checkRight(
                authData: authData,
                rightName: BTAuthorizationRights.manage
            )
            guard authorized else {
                reply(BTError.notAuthorized.rawValue)
                return
            }

            guard let setting = BTPMSetSetting(rawValue: setting),
                  let scope = BTPowerModeScope(rawValue: scope) else {
                reply(BTError.malformedData.rawValue)
                return
            }

            let success = BTPMSet.set(setting: setting, value: value, scope: scope)
            reply(BTError(fromBool: success).rawValue)
        }
    }

    func setCaffeinate(
        authData: Data,
        flags: UInt32,
        durationSeconds: Int,
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    ) {
        Task { @MainActor in
            guard BTDaemon.supported else {
                reply(BTError.unsupported.rawValue)
                return
            }

            let authorized = self.checkRight(
                authData: authData,
                rightName: BTAuthorizationRights.manage
            )
            guard authorized else {
                reply(BTError.notAuthorized.rawValue)
                return
            }

            let resolvedFlags = BTCaffeinateFlags(rawValue: flags)
            BTCaffeinate.set(flags: resolvedFlags, durationSeconds: durationSeconds)
            reply(BTError.success.rawValue)
        }
    }

    func setCaffeinateBuckets(
        authData: Data,
        flags: [UInt32],
        durations: [Int],
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    ) {
        Task { @MainActor in
            guard BTDaemon.supported else {
                reply(BTError.unsupported.rawValue)
                return
            }

            let authorized = self.checkRight(
                authData: authData,
                rightName: BTAuthorizationRights.manage
            )
            guard authorized else {
                reply(BTError.notAuthorized.rawValue)
                return
            }

            guard flags.count == durations.count else {
                reply(BTError.malformedData.rawValue)
                return
            }

            let buckets = zip(flags, durations).map { (raw, seconds) in
                (BTCaffeinateFlags(rawValue: raw), seconds)
            }
            BTCaffeinate.setBuckets(buckets)
            reply(BTError.success.rawValue)
        }
    }

    func killCaffeinate(
        authData: Data,
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    ) {
        Task { @MainActor in
            guard BTDaemon.supported else {
                reply(BTError.unsupported.rawValue)
                return
            }

            let authorized = self.checkRight(
                authData: authData,
                rightName: BTAuthorizationRights.manage
            )
            guard authorized else {
                reply(BTError.notAuthorized.rawValue)
                return
            }

            BTCaffeinate.killAll()
            reply(BTError.success.rawValue)
        }
    }

    func getBatteryTemperature(
        source: UInt8,
        reply: @Sendable @escaping (NSNumber?) -> Void
    ) {
        Task { @MainActor in
            guard BTDaemon.supported else {
                reply(nil)
                return
            }

            guard let source = BTTemperatureSource(rawValue: source) else {
                reply(nil)
                return
            }

            let value = BatteryTemperatureSources.read(source: source)
            reply(value.map(NSNumber.init(value:)))
        }
    }

    func copyPowerlogDatabase(
        authData: Data,
        destinationPath: String,
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    ) {
        Task { @MainActor in
            guard BTDaemon.supported else {
                reply(BTError.unsupported.rawValue)
                return
            }
            let authorized = self.checkRight(
                authData: authData,
                rightName: BTAuthorizationRights.manage
            )
            guard authorized else {
                reply(BTError.notAuthorized.rawValue)
                return
            }

            let sourceURL = URL(fileURLWithPath: "/private/var/db/powerlog/Library/BatteryLife/CurrentPowerlog.PLSQL")
            let destinationURL = URL(fileURLWithPath: destinationPath)
            let destinationDir = destinationURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                reply(BTError.success.rawValue)
            } catch {
                os_log("Failed to copy powerlog database: %{public}@", error.localizedDescription)
                reply(BTError.unknown.rawValue)
            }
        }
    }

    func checkHighPowerMode(
        authData: Data,
        reply: @Sendable @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            guard BTDaemon.supported else {
                reply(false)
                return
            }

            let authorized = self.checkRight(
                authData: authData,
                rightName: BTAuthorizationRights.manage
            )
            guard authorized else {
                reply(false)
                return
            }

            let success = BTPowerMode.checkAndSetHighPowerMode()
            if success {
                Task { @MainActor in
                    BTEventHub.notifyStateChanged()
                }
            }
            reply(success)
        }
    }
    
    private func checkRight(authData: Data?, rightName: String) -> Bool {
#if DEBUG
        return true
#else
        let simpleAuth = SimpleAuth.fromData(authData: authData)
        guard let simpleAuth else {
            return false
        }

        return SimpleAuth.checkRight(
            simpleAuth: simpleAuth,
            rightName: rightName
        )
#endif
    }
}
