//
// Copyright (C) 2022 - 2024 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log

@MainActor
internal enum BTSettings {
    private(set) static var minCharge = BTSettingsInfo.Defaults.minCharge
    private(set) static var maxCharge = BTSettingsInfo.Defaults.maxCharge
    private(set) static var adapterSleep = BTSettingsInfo.Defaults.adapterSleep
    private(set) static var sleepProtection = BTSettingsInfo.Defaults.sleepProtection
    private(set) static var magSafeSync = BTSettingsInfo.Defaults.magSafeSync
    private(set) static var magSafeInvertedIndicator = BTSettingsInfo.Defaults.magSafeInvertedIndicator

    static func readDefaults() {
        self.adapterSleep = UserDefaults.standard.bool(
            forKey: BTSettingsInfo.Keys.adapterSleep
        )
        self.sleepProtection = UserDefaults.standard.bool(
            forKey: BTSettingsInfo.Keys.sleepProtection
        )
        self.magSafeSync = UserDefaults.standard.bool(
            forKey: BTSettingsInfo.Keys.magSafeSync
        )
        self.magSafeInvertedIndicator = UserDefaults.standard.bool(
            forKey: BTSettingsInfo.Keys.magSafeInvertedIndicator
        )

        let minCharge = UserDefaults.standard.integer(
            forKey: BTSettingsInfo.Keys.minCharge
        )
        let maxCharge = UserDefaults.standard.integer(
            forKey: BTSettingsInfo.Keys.maxCharge
        )
        guard
            BTSettingsInfo.chargeLimitsValid(
                minCharge: minCharge,
                maxCharge: maxCharge
            )
        else {
            os_log("Charge limits malformed, restore current values")
            self.writeDefaults()
            return
        }

        self.minCharge = UInt8(minCharge)
        self.maxCharge = UInt8(maxCharge)
    }

    static func removeDefaults() {
        UserDefaults.standard.removeObject(
            forKey: BTSettingsInfo.Keys.adapterSleep
        )
        UserDefaults.standard.removeObject(
            forKey: BTSettingsInfo.Keys.sleepProtection
        )
        UserDefaults.standard.removeObject(
            forKey: BTSettingsInfo.Keys.magSafeSync
        )
        UserDefaults.standard.removeObject(
            forKey: BTSettingsInfo.Keys.magSafeInvertedIndicator
        )
        UserDefaults.standard.removeObject(
            forKey: BTSettingsInfo.Keys.minCharge
        )
        UserDefaults.standard.removeObject(
            forKey: BTSettingsInfo.Keys.maxCharge
        )

        _ = CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }

    static func getSettings() -> [String: NSObject & Sendable] {
        let minCharge = NSNumber(value: self.minCharge)
        let maxCharge = NSNumber(value: self.maxCharge)
        let adapterSleep = NSNumber(value: self.adapterSleep)
        let sleepProtection = NSNumber(value: self.sleepProtection)
        let magSafeSync = NSNumber(value: self.magSafeSync)
        let magSafeInvertedIndicator = NSNumber(value: self.magSafeInvertedIndicator)
        var settings: [String: NSObject & Sendable] = [
            BTSettingsInfo.Keys.minCharge: minCharge,
            BTSettingsInfo.Keys.maxCharge: maxCharge,
            BTSettingsInfo.Keys.adapterSleep: adapterSleep,
            BTSettingsInfo.Keys.sleepProtection: sleepProtection,
        ]

        if SMCComm.MagSafe.supported {
            settings.updateValue(magSafeSync,
                forKey: BTSettingsInfo.Keys.magSafeSync)
            settings.updateValue(magSafeInvertedIndicator,
                forKey: BTSettingsInfo.Keys.magSafeInvertedIndicator)
        }

        return settings
    }

    static func setSettings(
        settings: [String: NSObject & Sendable],
        reply: @Sendable @escaping (BTError.RawValue) -> Void
    ) {
        let minChargeNum = settings[BTSettingsInfo.Keys.minCharge] as? NSNumber
        let minCharge = minChargeNum?.intValue ??
            Int(BTSettingsInfo.Defaults.minCharge)

        let maxChargeNum = settings[BTSettingsInfo.Keys.maxCharge] as? NSNumber
        let maxCharge = maxChargeNum?.intValue ??
            Int(BTSettingsInfo.Defaults.maxCharge)

        let success = self.setChargeLimits(
            minCharge: minCharge,
            maxCharge: maxCharge
        )
        guard success else {
            reply(BTError.malformedData.rawValue)
            return
        }

        let adapterSleepNum =
            settings[BTSettingsInfo.Keys.adapterSleep] as? NSNumber
        let adapterSleep = adapterSleepNum?.boolValue ??
            BTSettingsInfo.Defaults.adapterSleep

        self.setAdapterSleep(enabled: adapterSleep)

        let sleepProtectionNum =
            settings[BTSettingsInfo.Keys.sleepProtection] as? NSNumber
        let sleepProtection = sleepProtectionNum?.boolValue ??
            BTSettingsInfo.Defaults.sleepProtection

        self.setSleepProtection(enabled: sleepProtection)

        let magSafeSyncNum =
            settings[BTSettingsInfo.Keys.magSafeSync] as? NSNumber
        let magSafeSync = magSafeSyncNum?.boolValue ??
            BTSettingsInfo.Defaults.magSafeSync

        self.setMagSafeSync(enabled: magSafeSync)

        let magSafeInvertedNum =
            settings[BTSettingsInfo.Keys.magSafeInvertedIndicator] as? NSNumber
        let magSafeInverted = magSafeInvertedNum?.boolValue ??
            BTSettingsInfo.Defaults.magSafeInvertedIndicator

        self.setMagSafeInvertedIndicator(enabled: magSafeInverted)

        self.writeDefaults()

        reply(BTError.success.rawValue)
    }

    private static func setChargeLimits(
        minCharge: Int,
        maxCharge: Int
    ) -> Bool {
        guard
            BTSettingsInfo.chargeLimitsValid(
                minCharge: minCharge,
                maxCharge: maxCharge
            )
        else {
            os_log("Client charge limits malformed, preserve current values")
            return false
        }

        self.minCharge = UInt8(minCharge)
        self.maxCharge = UInt8(maxCharge)

        BTPowerEvents.settingsChanged()

        return true
    }

    private static func setAdapterSleep(enabled: Bool) {
        guard self.adapterSleep != enabled else {
            return
        }

        self.adapterSleep = enabled

        BTPowerState.adapterSleepSettingToggled()
    }

    private static func setSleepProtection(enabled: Bool) {
        guard self.sleepProtection != enabled else {
            return
        }

        self.sleepProtection = enabled
        BTPowerState.reevaluateChargingSleepAssertionPolicy()
    }

    private static func setMagSafeSync(enabled: Bool) {
        guard self.magSafeSync != enabled else {
            return
        }

        self.magSafeSync = enabled

        BTPowerState.magSafeSyncSettingToggled()
    }

    private static func setMagSafeInvertedIndicator(enabled: Bool) {
        guard self.magSafeInvertedIndicator != enabled else {
            return
        }

        self.magSafeInvertedIndicator = enabled
        BTPowerState.magSafeSyncSettingToggled()
    }

    private static func writeDefaults() {
        assert(
            BTSettingsInfo.chargeLimitsValid(
                minCharge: Int(self.minCharge),
                maxCharge: Int(self.maxCharge)
            )
        )

        UserDefaults.standard.set(
            self.minCharge,
            forKey: BTSettingsInfo.Keys.minCharge
        )
        UserDefaults.standard.set(
            self.maxCharge,
            forKey: BTSettingsInfo.Keys.maxCharge
        )
        UserDefaults.standard.set(
            self.adapterSleep,
            forKey: BTSettingsInfo.Keys.adapterSleep
        )
        UserDefaults.standard.set(
            self.sleepProtection,
            forKey: BTSettingsInfo.Keys.sleepProtection
        )
        UserDefaults.standard.set(
            self.magSafeSync,
            forKey: BTSettingsInfo.Keys.magSafeSync
        )
        UserDefaults.standard.set(
            self.magSafeInvertedIndicator,
            forKey: BTSettingsInfo.Keys.magSafeInvertedIndicator
        )
        //
        // As NSUserDefaults are not automatically synchronized without
        // NSApplication, do so manually.
        //
        _ = CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }

}
