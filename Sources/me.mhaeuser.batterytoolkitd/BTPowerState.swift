//
// Copyright (C) 2022 - 2024 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log

@MainActor
internal enum BTPowerState {
    private static var chargingDisabled = false
    private static var powerDisabled = false

    static func initState() {
        let chargingDisabled = SMCComm.Power.isChargingDisabled()
        self.chargingDisabled = chargingDisabled
        if !chargingDisabled {
            //
            // Sleep must always be disabled when charging is enabled.
            //
            GlobalSleep.disable()
        }

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

            if chargingDisabled {
                GlobalSleep.restore()
            } else {
                GlobalSleep.disable()
            }
        }

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

        GlobalSleep.restore()

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

        GlobalSleep.disable()

        self.chargingDisabled = false

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
}
