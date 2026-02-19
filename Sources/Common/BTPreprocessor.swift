//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log

public enum BTPreprocessor {
    @available(*, deprecated, message: "No longer required. BT_* values are read from Info.plist.")
    public static func configure(appGroupSuiteName: String) {
        _ = appGroupSuiteName
    }

    @available(*, deprecated, message: "No longer required. Define BT_* values in Info.plist.")
    public static func setValues(
        appId: String,
        daemonId: String,
        daemonConn: String,
        codesignCN: String
    ) {
        _ = appId
        _ = daemonId
        _ = daemonConn
        _ = codesignCN
    }

    private static func string(key: String) -> String {
        if let info = Bundle.main.infoDictionary,
           let value = info[key] as? String,
           !value.isEmpty {
            return value
        }
        if let execURL = Bundle.main.executableURL {
            let appInfoURL = execURL
                .deletingLastPathComponent() // MacOS
                .deletingLastPathComponent() // Contents
                .appendingPathComponent("Info.plist")
            if let appInfo = NSDictionary(contentsOf: appInfoURL),
               let value = appInfo[key] as? String,
               !value.isEmpty {
                return value
            }
        }
        if let envValue = ProcessInfo.processInfo.environment[key],
           !envValue.isEmpty {
            return envValue
        }
        os_log("Missing configuration value for key: %{public}@", key)
        return ""
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
