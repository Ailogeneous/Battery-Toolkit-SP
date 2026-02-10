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

    public static func setSettings(settings: [String: NSObject & Sendable]) async throws {
        try await BTDaemonXPCClient.setSettings(settings: settings)
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
}
