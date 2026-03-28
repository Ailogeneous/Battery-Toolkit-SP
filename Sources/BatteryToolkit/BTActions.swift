//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

@BTBackgroundActor
public enum BTActions {
    public static func startDaemon() async -> BTDaemonManagementStatus {
        return await BTDaemonManagement.start()
    }

    public static func approveDaemon(timeout: UInt8) async throws {
        try await BTDaemonManagement.approve(timeout: timeout)
    }

    public static func upgradeDaemon() async -> BTDaemonManagementStatus {
        return await BTDaemonManagement.upgrade()
    }

    public static func stop() {
        BTDaemonXPCClient.disconnectDaemon()
    }

    public static func disablePowerAdapter() async throws {
        try await BTDaemonXPCClient.disablePowerAdapter()
    }

    public static func enablePowerAdapter() async throws {
        try await BTDaemonXPCClient.enablePowerAdapter()
    }

    public static func chargeToLimit() async throws {
        try await BTDaemonXPCClient.chargeToLimit()
    }

    public static func chargeToFull() async throws {
        try await BTDaemonXPCClient.chargeToFull()
    }

    public static func disableCharging() async throws {
        try await BTDaemonXPCClient.disableCharging()
    }

    public static func getState() async throws -> [String: NSObject & Sendable] {
        return try await BTDaemonXPCClient.getState()
    }

    public static func getSettings() async throws -> [String: NSObject & Sendable] {
        return try await BTDaemonXPCClient.getSettings()
    }

    public static func getBatteryTemperature(source: BTTemperatureSource) async throws -> Double? {
        return try await BTDaemonXPCClient.getBatteryTemperature(source: source)
    }

    public static func copyPowerlogDatabase(destinationPath: String) async throws {
        try await BTDaemonXPCClient.copyPowerlogDatabase(destinationPath: destinationPath)
    }

    public static func setSettings(settings: [String: NSObject & Sendable]) async throws {
        try await BTDaemonXPCClient.setSettings(settings: settings)
    }

    public static func setPowerMode(scope: BTPowerModeScope, mode: UInt8) async throws {
        try await BTDaemonXPCClient.setPowerMode(scope: scope, mode: mode)
    }

    public static func setPMSetHibernatemode(_ value: Int, scope: BTPowerModeScope = .all) async throws {
        try await BTDaemonXPCClient.setPMSet(setting: .hibernatemode, value: value, scope: scope)
    }

    public static func setPMSetStandby(_ value: Int, scope: BTPowerModeScope = .all) async throws {
        try await BTDaemonXPCClient.setPMSet(setting: .standby, value: value, scope: scope)
    }

    public static func setPMSetStandbyDelayLow(_ value: Int, scope: BTPowerModeScope = .all) async throws {
        try await BTDaemonXPCClient.setPMSet(setting: .standbydelaylow, value: value, scope: scope)
    }

    public static func setPMSetStandbyDelayHigh(_ value: Int, scope: BTPowerModeScope = .all) async throws {
        try await BTDaemonXPCClient.setPMSet(setting: .standbydelayhigh, value: value, scope: scope)
    }

    public static func setPMSetHighStandbyThreshold(_ value: Int, scope: BTPowerModeScope = .all) async throws {
        try await BTDaemonXPCClient.setPMSet(setting: .highstandbythreshold, value: value, scope: scope)
    }

    public static func caffeinate(flags: BTCaffeinateFlags, durationSeconds: Int) async throws {
        try await BTDaemonXPCClient.setCaffeinate(flags: flags, durationSeconds: durationSeconds)
    }

    public static func setCaffeinateBuckets(
        buckets: [(flags: BTCaffeinateFlags, durationSeconds: Int)]
    ) async throws {
        try await BTDaemonXPCClient.setCaffeinateBuckets(buckets: buckets)
    }

    public static func killCaffeinate() async throws {
        try await BTDaemonXPCClient.killCaffeinate()
    }

    public static func removeDaemon() async throws {
        try await BTDaemonManagement.remove()
    }

    public static func pauseActivity() async throws {
        try await BTDaemonXPCClient.pauseActivity()
    }

    public static func resumeActivity() async throws {
        try await BTDaemonXPCClient.resumeActivity()
    }

    public static func setMagSafeIndicator(mode: BTMagSafeIndicatorMode) async throws {
        try await BTDaemonXPCClient.setMagSafeIndicator(mode: mode)
    }
}
