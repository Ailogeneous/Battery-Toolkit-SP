//
// Copyright (C) 2022 - 2023 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log

import IOPMPrivate

@MainActor
public enum GlobalSleep {
    /// There can be multiple factors to disable sleep, e.g., active battery
    /// charging or a disabled power adapter. Use a counter to allow independent
    /// control by all sources.
    private static var disabledCounter: UInt8 = 0

    /// Honour the user-specified sleep disabled state for restoration.
    private static var previousDisabled = false

    static func forceRestore() {
        guard self.disabledCounter > 0 else {
            return
        }

        self.disabledCounter = 0
        self.restorePrevious()
    }

    static func restore() {
        assert(self.disabledCounter > 0)
        self.disabledCounter -= 1

        guard self.disabledCounter == 0 else {
            return
        }

        self.restorePrevious()
    }

    static func disable() {
        assert(self.disabledCounter >= 0)
        self.disabledCounter += 1

        guard self.disabledCounter == 1 else {
            return
        }

        let sleepDisable = self.getSleepDisabledIOPMValue()
        self.previousDisabled = sleepDisable

        guard !sleepDisable else {
            return
        }

        self.setSleepDisabledIOPMValue(value: kCFBooleanTrue)
    }

    static func isSleepDisabled() -> Bool {
        return self.getSleepDisabledIOPMValue()
    }

    static func reconcile(expectedDisabled: Bool) {
        let actualDisabled = self.getSleepDisabledIOPMValue()
        guard actualDisabled != expectedDisabled else {
            return
        }
        self.setSleepDisabledIOPMValue(value: expectedDisabled ? kCFBooleanTrue : kCFBooleanFalse)
    }

    private static func getSleepDisabledIOPMValue() -> Bool {
        guard let settingsRef = IOPMCopySystemPowerSettings() else {
            os_log("System power settings could not be retrieved")
            return false
        }

        guard
            let settings =
            settingsRef.takeUnretainedValue() as? [String: AnyObject]
        else {
            os_log("System power settings are malformed")
            return false
        }

        guard let sleepDisable = settings[kIOPMSleepDisabledKey] as? Bool else {
            os_log("Sleep disable setting is malformed")
            return false
        }

        return sleepDisable
    }

    private static func setSleepDisabledIOPMValue(value: CFBoolean) {
        let result = IOPMSetSystemPowerSetting(
            kIOPMSleepDisabledKey as CFString,
            value
        )
        if result != kIOReturnSuccess {
            os_log("Failed to set \(value) SleepDisabled setting - \(result)")
        }
    }

    private static func restorePrevious() {
        guard !self.previousDisabled else {
            self.previousDisabled = false
            return
        }

        self.setSleepDisabledIOPMValue(value: kCFBooleanFalse)
    }
}
