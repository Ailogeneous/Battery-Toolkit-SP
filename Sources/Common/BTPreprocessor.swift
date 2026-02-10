//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

public enum BTPreprocessor {
    private static var suiteName: String?

    public static func configure(appGroupSuiteName: String) {
        self.suiteName = appGroupSuiteName
    }

    public static func setValues(
        appId: String,
        daemonId: String,
        daemonConn: String,
        codesignCN: String
    ) {
        let defaults = self.defaults()
        defaults.set(appId, forKey: "BT_APP_ID")
        defaults.set(daemonId, forKey: "BT_DAEMON_ID")
        defaults.set(daemonConn, forKey: "BT_DAEMON_CONN")
        defaults.set(codesignCN, forKey: "BT_CODESIGN_CN")
    }

    private static func defaults() -> UserDefaults {
        guard let suiteName = self.suiteName else {
            preconditionFailure(
                "BTPreprocessor not configured. Call BTPreprocessor.configure(appGroupSuiteName:) before use."
            )
        }
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to access UserDefaults suite: \(suiteName)")
        }
        return defaults
    }

    private static func string(key: String) -> String {
        let defaults = self.defaults()
        guard let value = defaults.string(forKey: key), !value.isEmpty else {
            preconditionFailure("Missing UserDefaults key: \(key)")
        }
        return value
    }

    public static var appId: String {
        return self.string(key: "BT_APP_ID")
    }

    public static var daemonId: String {
        return self.string(key: "BT_DAEMON_ID")
    }

    public static var daemonConn: String {
        return self.string(key: "BT_DAEMON_CONN")
    }

    public static var codesignCN: String {
        return self.string(key: "BT_CODESIGN_CN")
    }
}
