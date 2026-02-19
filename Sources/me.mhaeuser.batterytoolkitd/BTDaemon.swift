//
// Copyright (C) 2022 - 2025 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log
import IOKit.pwr_mgt

@MainActor
public enum BTDaemon {
    private(set) static var supported = false
    private static var enabled = false

    private static var uniqueId: Data? = nil

    /// SIGTERM source signal. Needs to be preserved for the program lifetime.
    private static var termSource: DispatchSourceSignal? = nil

    static func getUniqueId() -> Data? {
        return self.uniqueId
    }

    static func getState() -> [String: NSObject & Sendable] {
        let chargingDisabled = BTPowerState.isChargingDisabled()
        let connected = enabled ? BTPowerEvents.unlimitedPower : IOPSPrivate.DrawingUnlimitedPower()
        let powerDisabled = BTPowerState.isPowerAdapterDisabled()
        let progress = enabled ? BTPowerEvents.getChargingProgress() : BTStateInfo.ChargingProgress.full
        let mode = enabled ? BTPowerEvents.chargingMode : BTStateInfo.ChargingMode.standard
        let maxCharge = BTSettings.maxCharge

        var batteryPercent: NSNumber? = nil
        var isCharging: NSNumber? = nil
        var isACConnected: NSNumber? = nil

        if let (percent, charging, _) = IOPSPrivate.GetPercentRemaining() {
            batteryPercent = NSNumber(value: Double(percent))
            isCharging = NSNumber(value: charging)
            isACConnected = NSNumber(value: connected)
        }

        if BTSettings.magSafeSync {
            BTPowerState.syncMagSafeState()
        }

        var state: [String: NSObject & Sendable] = [
            BTStateInfo.Keys.enabled: NSNumber(value: enabled ? 1 : 0),
            BTStateInfo.Keys.powerDisabled: NSNumber(value: powerDisabled),
            BTStateInfo.Keys.connected: NSNumber(value: connected),
            BTStateInfo.Keys
                .chargingDisabled: NSNumber(value: chargingDisabled),
            BTStateInfo.Keys.progress: NSNumber(value: progress.rawValue),
            BTStateInfo.Keys.chargingMode: NSNumber(value: mode.rawValue),
            BTStateInfo.Keys.maxCharge: NSNumber(value: maxCharge)
        ]

        let powerModes = BTPowerMode.readCurrent()
        if let value = powerModes.all {
            state[BTStateInfo.Keys.powerModeAll] = NSNumber(value: value)
        }
        if let value = powerModes.battery {
            state[BTStateInfo.Keys.powerModeBattery] = NSNumber(value: value)
        }
        if let value = powerModes.charger {
            state[BTStateInfo.Keys.powerModeCharger] = NSNumber(value: value)
        }

        if let batteryPercent { state[BTStateInfo.Keys.batteryPercent] = batteryPercent }
        if let isCharging { state[BTStateInfo.Keys.isCharging] = isCharging }
        if let isACConnected { state[BTStateInfo.Keys.isACConnected] = isACConnected }
        if let temperatureC = IOPSPrivate.GetBatteryTemperatureCelsius() {
            state[BTStateInfo.Keys.batteryTemperature] = NSNumber(value: temperatureC)
        }

        return state
    }
    
    private static func start() throws {
        try BTPowerEvents.start()

        let callback: IOServiceInterestCallback = { refCon, service, messageType, messageArgument in
            if messageType == PowerEvents.kIOMessageCanSystemSleep ||
               messageType == PowerEvents.kIOMessageSystemWillSleep {
                IOAllowPowerChange(
                    PowerEvents.root_port,
                    Int(bitPattern: messageArgument)
                )
            } else if messageType == PowerEvents.kIOMessageSystemHasPoweredOn {
                BTPowerEvents.wakeFromSleep()
            }
        }

        let success = PowerEvents.register(callback: callback)
        guard success else {
            os_log("Error registering system power event")
            exit(-1)
        }
    }

    static func resume() {
        guard !self.enabled else {
            return
        }

        do {
            try self.start()
            self.enabled = true
        } catch {
            //
            // If we got unsupported here, this would contradict earlier
            // success. Force a restart just in case.
            //
            os_log("Power events start failed")
            exit(-1)
        }
    }
    
    static func pause() {
        guard self.enabled else {
            return
        }

        PowerEvents.deregister()

        self.enabled = false
        BTPowerEvents.stop()
    }

    public nonisolated static func run() {
        Task { @MainActor in
            self.runMain()
        }
        dispatchMain()
    }

    private static func runMain() {
        //
        // Cache the unique ID immediately, as this is not safe against
        // modifications of the daemon on-disk. This ID must not be used for
        // security-criticial purposes.
        //
        self.uniqueId = CSIdentification.getUniqueIdSelf()

        BTSettings.readDefaults()

        // Host application owns pmset policy decisions and can trigger
        // enforcement explicitly via settings/actions when desired.
        GlobalSleep.restoreOnStart()

        do {
            try self.start()
            self.enabled = true
            self.supported = true

            let termSource = DispatchSource.makeSignalSource(
                signal: SIGTERM,
                queue: DispatchQueue.main
            )
            termSource.setEventHandler {
                BTPowerEvents.exit()
                exit(0)
            }
            termSource.resume()
            //
            // Preserve termSource globally, so it is not deallocated.
            //
            self.termSource = termSource
            //
            // Ignore SIGTERM to catch it above and gracefully stop the service.
            //
            signal(SIGTERM, SIG_IGN)

            let status = SimpleAuth.duplicateRight(
                rightName: BTAuthorizationRights.manage,
                templateName: kAuthorizationRuleAuthenticateAsAdmin,
                comment: "Used by \(BTPreprocessor.daemonId) to allow access to its privileged functions",
                timeout: 300
            )
            if status != errSecSuccess {
                os_log("Error adding manage right: \(status)")
            }
        } catch BTError.unsupported {
            //
            // Still run the XPC server if the machine is unsupported to cleanly
            // uninstall the daemon, but don't initialize the rest of the stack.
            //
            self.supported = false
        } catch {
            os_log("Power events start failed")
            exit(-1)
        }

        BTDaemonXPCServer.start()
    }
}
