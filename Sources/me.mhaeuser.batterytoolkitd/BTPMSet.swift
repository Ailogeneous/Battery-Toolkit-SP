//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log

@MainActor
internal enum BTPMSet {
    static func set(setting: BTPMSetSetting, value: Int, scope: BTPowerModeScope) -> Bool {
        let scopeFlag: String
        switch scope {
        case .all: scopeFlag = "-a"
        case .battery: scopeFlag = "-b"
        case .charger: scopeFlag = "-c"
        }

        let result = run("/usr/bin/pmset", args: [scopeFlag, setting.cliName, String(value)])
        if result.status != 0 {
            os_log("pmset set failed for %{public}@=%{public}d: %{public}@", setting.cliName, value, result.stderr)
            return false
        }
        return true
    }

    private static func run(_ executable: String, args: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, "", error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
