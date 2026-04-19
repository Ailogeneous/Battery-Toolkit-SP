//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import IOKit.pwr_mgt

@MainActor
enum BTCaffeinate {
    private static var activeAssertions: [BTCaffeinateFlags: IOPMAssertionID] = [:]
    private static var sessions: [Int: BTCaffeinateFlags] = [:]
    private static var sessionTimers: [Int: DispatchSourceTimer] = [:]

    private static let allFlags: [BTCaffeinateFlags] = [
        .preventUserIdleSystemSleep,
        .preventUserIdleDisplaySleep,
        .preventDiskIdle,
        .preventSystemSleep
    ]

    private static let assertionTypeMap: [BTCaffeinateFlags: CFString] = [
        .preventUserIdleSystemSleep: "PreventUserIdleSystemSleep" as CFString,
        .preventUserIdleDisplaySleep: "PreventUserIdleDisplaySleep" as CFString,
        .preventDiskIdle: "PreventDiskIdle" as CFString,
        .preventSystemSleep: "PreventSystemSleep" as CFString
    ]

    static func set(flags: BTCaffeinateFlags, durationSeconds: Int) {
        if durationSeconds <= 0 || flags.isEmpty {
            killAll()
            return
        }
        setBuckets([(flags, durationSeconds)])
    }

    static func setBuckets(_ buckets: [(BTCaffeinateFlags, Int)]) {
        var desired: [Int: BTCaffeinateFlags] = [:]
        for (flags, duration) in buckets {
            guard duration > 0, !flags.isEmpty else { continue }
            desired[duration, default: []].formUnion(flags)
        }

        let removedDurations = sessions.keys.filter { desired[$0] == nil }
        for duration in removedDurations {
            removeSession(duration: duration)
        }

        for (duration, flags) in desired {
            sessions[duration] = flags
            startOrResetSession(duration: duration)
        }

        let combined = sessions.values.reduce(BTCaffeinateFlags()) { $0.union($1) }
        updateAssertions(for: combined)
    }

    static func killAll() {
        for duration in sessionTimers.keys {
            sessionTimers[duration]?.cancel()
        }
        sessionTimers.removeAll()
        sessions.removeAll()
        for (flag, assertion) in activeAssertions {
            IOPMAssertionRelease(assertion)
            activeAssertions[flag] = nil
        }
        activeAssertions.removeAll()
    }

    private static func startOrResetSession(duration: Int) {
        sessionTimers[duration]?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(duration))
        timer.setEventHandler {
            Task { @MainActor in
                removeSession(duration: duration)
                let combined = sessions.values.reduce(BTCaffeinateFlags()) { $0.union($1) }
                updateAssertions(for: combined)
            }
        }
        timer.resume()
        sessionTimers[duration] = timer
    }

    private static func removeSession(duration: Int) {
        sessionTimers[duration]?.cancel()
        sessionTimers[duration] = nil
        sessions[duration] = nil
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
