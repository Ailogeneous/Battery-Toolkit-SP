//
// Copyright (C) 2022 - 2024 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log

@MainActor
internal enum BTPowerState {
    private struct PowerModeSnapshot {
        let all: Int?
        let battery: Int?
        let charger: Int?
    }

    private static var chargingDisabled = false
    private static var powerDisabled = false
    private static var chargeSleepAssertionHeld = false
    private static var chargeSleepPowerModeSnapshot: PowerModeSnapshot?
    private static var chargeStagnationStartAt: Date?
    private static var chargeStagnationStartPercent: UInt8?
    private static let chargeStagnationInterval: TimeInterval = 15 * 60
    private static let chargeProgressStepPercent: UInt8 = 1
    private static let thermalStopCelsius: Double = 37.0
    // Temporary kill switch for assertion-loop experiments while debugging paused charging behavior.
    private static let chargingSleepAssertionPolicyEnabled = false

    static func initState() {
        let chargingDisabled = SMCComm.Power.isChargingDisabled()
        self.chargingDisabled = chargingDisabled
        self.syncChargingSleepAssertionPolicy()

        let powerDisabled = SMCComm.Power.isPowerAdapterDisabled()
        self.powerDisabled = powerDisabled
        if powerDisabled {
            //
            // Sleep must be disabled when external power is disabled.
            //
            self.disableAdapterSleep()
        }

        SMCComm.MagSafe.prepare()

        if BTSettings.magSafeSync {
            self.syncMagSafeState()
        }
    }

    static func refreshState() {
        //
        // Refresh platform stated when waking from sleep, as events might not
        // fire.
        //
        let chargingDisabled = SMCComm.Power.isChargingDisabled()
        if chargingDisabled != self.chargingDisabled {
            self.chargingDisabled = chargingDisabled
        }
        self.syncChargingSleepAssertionPolicy()

        let powerDisabled = SMCComm.Power.isPowerAdapterDisabled()
        if powerDisabled != self.powerDisabled {
            self.powerDisabled = powerDisabled

            if powerDisabled {
                self.disableAdapterSleep()
            } else {
                self.restoreAdapterSleep()
            }
        }

        if BTSettings.magSafeSync {
            self.syncMagSafeState()
        }
    }

    static func getPercentRemaining() -> (UInt8, Bool, Bool) {
        return IOPSPrivate.GetPercentRemaining() ?? (100, false, false)
    }

    static func adapterSleepSettingToggled() {
        //
        // If power is disabled, toggle sleep.
        //
        guard self.powerDisabled else {
            return
        }

        if !BTSettings.adapterSleep {
            GlobalSleep.disable()
        } else {
            GlobalSleep.restore()
        }
    }

    static func syncMagSafeStatePowerEnabled(percent: UInt8) {
        assert(BTSettings.magSafeSync)
        assert(!self.powerDisabled)

        if percent >= BTSettings.maxCharge {
            let success = BTSettings.magSafeInvertedIndicator
                ? SMCComm.MagSafe.setOrange()
                : SMCComm.MagSafe.setGreen()
            os_log("MagSafe sync: green (percent=%{public}u max=%{public}u chargingDisabled=%{public}@ success=%{public}@)", percent, BTSettings.maxCharge, self.chargingDisabled.description, success.description)
            NSLog("MagSafe sync: green (percent=%u max=%u chargingDisabled=%@ success=%@)", percent, BTSettings.maxCharge, self.chargingDisabled.description, success.description)
        } else if self.chargingDisabled {
            let success = SMCComm.MagSafe.setOrange()
            os_log("MagSafe sync: orange (percent=%{public}u max=%{public}u chargingDisabled=%{public}@ success=%{public}@)", percent, BTSettings.maxCharge, self.chargingDisabled.description, success.description)
            NSLog("MagSafe sync: orange (percent=%u max=%u chargingDisabled=%@ success=%@)", percent, BTSettings.maxCharge, self.chargingDisabled.description, success.description)
        } else {
            let success = BTSettings.magSafeInvertedIndicator
                ? SMCComm.MagSafe.setGreen()
                : SMCComm.MagSafe.setOrange()
            os_log("MagSafe sync: orangeCharging (percent=%{public}u max=%{public}u chargingDisabled=%{public}@ success=%{public}@)", percent, BTSettings.maxCharge, self.chargingDisabled.description, success.description)
            NSLog("MagSafe sync: orangeCharging (percent=%u max=%u chargingDisabled=%@ success=%@)", percent, BTSettings.maxCharge, self.chargingDisabled.description, success.description)
        }
    }

    static func syncMagSafeState() {
        assert(BTSettings.magSafeSync)

        if self.powerDisabled {
            _ = SMCComm.MagSafe.setOff()
        } else {
            let (percent, _, _) = self.getPercentRemaining()
            self.syncMagSafeStatePowerEnabled(percent: percent)
        }
    }

    static func magSafeSyncSettingToggled() {
        if BTSettings.magSafeSync {
            self.syncMagSafeState()
        } else {
            _ = SMCComm.MagSafe.setSystem()
        }
    }

    static func disableCharging(percent: UInt8) -> Bool {
        guard !self.chargingDisabled else {
            return true
        }

        let success = SMCComm.Power.disableCharging()
        guard success else {
            os_log("Failed to disable charging")
            return false
        }

        self.chargingDisabled = true

        if BTSettings.magSafeSync {
            BTPowerState.syncMagSafeStatePowerEnabled(percent: percent)
        }

        self.syncChargingSleepAssertionPolicy(currentPercent: percent)

        return true
    }

    static func enableCharging(percent: UInt8) -> Bool {
        guard self.chargingDisabled else {
            return true
        }

        let success = SMCComm.Power.enableCharging()
        if !success {
            os_log("Failed to enable charging")
            return false
        }

        self.chargingDisabled = false
        self.syncChargingSleepAssertionPolicy(currentPercent: percent)

        if BTSettings.magSafeSync {
            BTPowerState.syncMagSafeStatePowerEnabled(percent: percent)
        }

        return true
    }

    static func disablePowerAdapter() -> Bool {
        guard !self.powerDisabled else {
            return true
        }

        self.disableAdapterSleep()

        let success = SMCComm.Power.disablePowerAdapter()
        guard success else {
            os_log("Failed to disable power adapter")
            self.restoreAdapterSleep()
            return false
        }

        if BTSettings.magSafeSync {
            _ = SMCComm.MagSafe.setOff()
        }

        self.powerDisabled = true
        return true
    }

    static func enablePowerAdapter() -> Bool {
        guard self.powerDisabled else {
            return true
        }

        let success = SMCComm.Power.enablePowerAdapter()
        guard success else {
            os_log("Failed to enable power adapter")
            return false
        }

        self.powerDisabled = false

        if BTSettings.magSafeSync {
            let (percent, _, _) = self.getPercentRemaining()
            BTPowerState.syncMagSafeStatePowerEnabled(percent: percent)
        }

        self.restoreAdapterSleep()

        return true
    }


    static func setMagSafeIndicator(mode: BTMagSafeIndicatorMode) -> Bool {
        switch mode {
        case .sync:
            guard BTSettings.magSafeSync else {
                return SMCComm.MagSafe.setSystem()
            }
            self.syncMagSafeState()
            return true
        case .system:
            return SMCComm.MagSafe.setSystem()
        case .off:
            return SMCComm.MagSafe.setOff()
        case .green:
            return SMCComm.MagSafe.setGreen()
        case .orange:
            return SMCComm.MagSafe.setOrange()
        case .orangeSlowBlink:
            return SMCComm.MagSafe.setOrangeSlowBlink()
        case .orangeFastBlink:
            return SMCComm.MagSafe.setOrangeFastBlink()
        case .orangeBlinkOff:
            return SMCComm.MagSafe.setOrangeBlinkOff()
        }
    }

    static func isChargingDisabled() -> Bool {
        return self.chargingDisabled
    }

    static func isPowerAdapterDisabled() -> Bool {
        return self.powerDisabled
    }

    static func reevaluateChargingSleepAssertionPolicy() {
        self.syncChargingSleepAssertionPolicy()
    }

    private static func disableAdapterSleep() {
        if !BTSettings.adapterSleep {
            GlobalSleep.disable()
        }
    }

    private static func restoreAdapterSleep() {
        if !BTSettings.adapterSleep {
            GlobalSleep.restore()
        }
    }

    private static func syncChargingSleepAssertionPolicy(currentPercent: UInt8? = nil) {
        guard self.chargingSleepAssertionPolicyEnabled else {
            self.releaseChargingSleepAssertion()
            self.resetChargeStagnationWindow()
            return
        }

        if self.chargingDisabled {
            self.releaseChargingSleepAssertion()
            self.resetChargeStagnationWindow()
            return
        }

        let percent = currentPercent ?? self.getPercentRemaining().0
        let shouldDisableSleep = self.shouldDisableSleepForCharging(currentPercent: percent)

        if shouldDisableSleep {
            self.holdChargingSleepAssertion()
        } else {
            self.releaseChargingSleepAssertion()
        }
    }

    private static func shouldDisableSleepForCharging(currentPercent: UInt8) -> Bool {
        if let clamshellClosed = IOPSPrivate.IsClamshellClosed(), clamshellClosed {
            self.resetChargeStagnationWindow()
            return false
        }

        if let batteryTempC = IOPSPrivate.GetBatteryTemperatureCelsius(), batteryTempC >= self.thermalStopCelsius {
            self.resetChargeStagnationWindow()
            return false
        }

        let now = Date()
        if self.chargeStagnationStartAt == nil || self.chargeStagnationStartPercent == nil {
            self.chargeStagnationStartAt = now
            self.chargeStagnationStartPercent = currentPercent
            return true
        }

        let startPercent = self.chargeStagnationStartPercent ?? currentPercent
        if currentPercent >= startPercent &+ self.chargeProgressStepPercent {
            self.chargeStagnationStartAt = now
            self.chargeStagnationStartPercent = currentPercent
            return true
        }

        guard let startAt = self.chargeStagnationStartAt else {
            return true
        }
        if now.timeIntervalSince(startAt) >= self.chargeStagnationInterval {
            self.resetChargeStagnationWindow()
            return false
        }

        return true
    }

    private static func holdChargingSleepAssertion() {
        guard !self.chargeSleepAssertionHeld else {
            return
        }
        self.captureAndForceLowPowerModeForAssertion()
        GlobalSleep.disable()
        self.chargeSleepAssertionHeld = true
    }

    private static func releaseChargingSleepAssertion() {
        guard self.chargeSleepAssertionHeld else {
            return
        }
        GlobalSleep.restore()
        self.restorePowerModeAfterAssertion()
        self.chargeSleepAssertionHeld = false
    }

    private static func resetChargeStagnationWindow() {
        self.chargeStagnationStartAt = nil
        self.chargeStagnationStartPercent = nil
    }

    private static func captureAndForceLowPowerModeForAssertion() {
        guard self.chargeSleepPowerModeSnapshot == nil else {
            return
        }

        let current = BTPowerMode.readCurrent()
        self.chargeSleepPowerModeSnapshot = PowerModeSnapshot(
            all: current.all,
            battery: current.battery,
            charger: current.charger
        )

        _ = BTPowerMode.set(scope: .all, mode: 1)
    }

    private static func restorePowerModeAfterAssertion() {
        guard let snapshot = self.chargeSleepPowerModeSnapshot else {
            return
        }
        self.chargeSleepPowerModeSnapshot = nil

        if let all = snapshot.all {
            _ = BTPowerMode.set(scope: .all, mode: UInt8(max(0, min(2, all))))
        }
        if let battery = snapshot.battery {
            _ = BTPowerMode.set(scope: .battery, mode: UInt8(max(0, min(2, battery))))
        }
        if let charger = snapshot.charger {
            _ = BTPowerMode.set(scope: .charger, mode: UInt8(max(0, min(2, charger))))
        }
    }
}
