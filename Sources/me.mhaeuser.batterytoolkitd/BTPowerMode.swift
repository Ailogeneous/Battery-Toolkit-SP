//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

enum BTPowerMode {
    static func set(scope: BTPowerModeScope, mode: UInt8) -> Bool {
        guard mode <= 2 else {
            return false
        }

        let scopeArg: String
        switch scope {
        case .all:
            scopeArg = "-a"
        case .battery:
            scopeArg = "-b"
        case .charger:
            scopeArg = "-c"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = [scopeArg, "powermode", "\(mode)"]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func readCurrent() -> (all: Int?, battery: Int?, charger: Int?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "custom"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return (nil, nil, nil)
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return (nil, nil, nil)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return (nil, nil, nil)
        }

        var all: Int?
        var battery: Int?
        var charger: Int?
        var section: BTPowerModeScope = .all

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }
            if line == "Battery Power:" {
                section = .battery
                continue
            }
            if line == "AC Power:" || line == "Charger Power:" {
                section = .charger
                continue
            }

            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else {
                continue
            }
            guard parts[0].lowercased() == "powermode" else {
                continue
            }
            guard let value = Int(parts[1]) else {
                continue
            }

            switch section {
            case .all:
                all = value
            case .battery:
                battery = value
            case .charger:
                charger = value
            }
        }

        return (all, battery, charger)
    }
}

