//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log

public enum BTDaemonManagement {
    @BTBackgroundActor
    public static func start() async -> BTDaemonManagementStatus {
        let daemonId = try? await BTDaemonXPCClient.getUniqueId()
        guard self.daemonUpToDate(daemonId: daemonId) else {
            return await self.Service.register()
        }

        os_log("Daemon is up-to-date, skip install")
        return .enabled
    }

    @BTBackgroundActor
    public static func upgrade() async -> BTDaemonManagementStatus {
        return await self.Service.upgrade()
    }

    public static func approve(timeout: UInt8) async throws {
        try await self.Service.approve(timeout: timeout)
    }

    @BTBackgroundActor
    public static func remove() async throws {
        try await self.Service.unregister()
    }

    private static func daemonUpToDate(daemonId: Data?) -> Bool {
        guard let daemonId else {
            os_log("Daemon unique ID is nil")
            return false
        }

        if let relativePath = self.daemonBinaryRelativePath() {
            if let bundleId = CSIdentification.getBundleRelativeUniqueId(relative: relativePath) {
                return bundleId == daemonId
            }

            os_log("Bundle daemon unique ID is nil for resolved path: %{public}@", relativePath)
            return false
        }

        // Fallback for older bundle layouts.
        let fallbackPaths = [
            "Contents/MacOS/" + BTPreprocessor.daemonId,
            "Contents/Library/LaunchServices/" + BTPreprocessor.daemonId,
        ]

        for relativePath in fallbackPaths {
            guard let bundleId = CSIdentification.getBundleRelativeUniqueId(relative: relativePath) else {
                continue
            }

            return bundleId == daemonId
        }

        os_log("Bundle daemon unique ID is nil for all known fallback paths")
        return false
    }

    private static func daemonBinaryRelativePath() -> String? {
        let plistName = BTPreprocessor.daemonId + ".plist"
        let plistCandidates = [
            "Contents/Library/LaunchDaemons/" + plistName,
            "Contents/Library/LaunchServices/" + plistName,
        ]

        for plistRelativePath in plistCandidates {
            let plistURL = Bundle.main.bundleURL.appendingPathComponent(plistRelativePath)
            guard
                let plist = NSDictionary(contentsOf: plistURL) as? [String: Any]
            else {
                continue
            }

            if let bundleProgram = plist["BundleProgram"] as? String,
               let relative = self.normalizeBundleRelativePath(bundleProgram) {
                return relative
            }

            if let program = plist["Program"] as? String,
               let relative = self.normalizeBundleRelativePath(program) {
                return relative
            }

            if let arguments = plist["ProgramArguments"] as? [String],
               let first = arguments.first,
               let relative = self.normalizeBundleRelativePath(first) {
                return relative
            }
        }

        return nil
    }

    private static func normalizeBundleRelativePath(_ value: String) -> String? {
        guard !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("Contents/") {
            return value
        }

        if let range = value.range(of: "/Contents/") {
            let start = value.index(after: range.lowerBound)
            return String(value[start...])
        }

        return nil
    }
}
