//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import IOKit.pwr_mgt

@MainActor
enum BTCaffeinate {
    private static var timer: DispatchSourceTimer?
    private static var activeAssertions: [BTCaffeinateFlags: IOPMAssertionID] = [:]

    private static let allFlags: [BTCaffeinateFlags] = [
        .preventUserIdleSystemSleep,
        .preventUserIdleDisplaySleep,
        .preventDiskIdle,
        .preventSystemSleep,
        .userIsActive
    ]

    private static let assertionTypeMap: [BTCaffeinateFlags: CFString] = [
        .preventUserIdleSystemSleep: "PreventUserIdleSystemSleep" as CFString,
        .preventUserIdleDisplaySleep: "PreventUserIdleDisplaySleep" as CFString,
        .preventDiskIdle: "PreventDiskIdle" as CFString,
        .preventSystemSleep: "PreventSystemSleep" as CFString,
        .userIsActive: "UserIsActive" as CFString
    ]

    static func set(flags: BTCaffeinateFlags, durationSeconds: Int) {
        if durationSeconds <= 0 || flags.isEmpty {
            cancel()
            return
        }

        updateAssertions(for: flags)

        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(durationSeconds))
        timer.setEventHandler { [weak timer] in
            timer?.cancel()
            Task { @MainActor in
                cancel()
            }
        }
        timer.resume()
        self.timer = timer
    }

    static func cancel() {
        timer?.cancel()
        timer = nil

        for (flag, assertion) in activeAssertions {
            IOPMAssertionRelease(assertion)
            activeAssertions[flag] = nil
        }
        activeAssertions.removeAll()
    }

    private static func updateAssertions(for flags: BTCaffeinateFlags) {
        for flag in allFlags {
            if flags.contains(flag) {
                if activeAssertions[flag] == nil {
                    if let assertionID = createAssertion(for: flag) {
                        activeAssertions[flag] = assertionID
                    }
                }
            } else if let assertionID = activeAssertions[flag] {
                IOPMAssertionRelease(assertionID)
                activeAssertions[flag] = nil
            }
        }
    }

    private static func createAssertion(for flag: BTCaffeinateFlags) -> IOPMAssertionID? {
        guard let assertionType = assertionTypeMap[flag] else { return nil }
        let name = "BatteryToolkit Caffeinate" as CFString

        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            return nil
        }
        return assertionID
    }
}
