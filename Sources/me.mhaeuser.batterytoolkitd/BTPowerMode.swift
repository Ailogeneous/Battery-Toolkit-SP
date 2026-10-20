//
// Copyright (C) 2026 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

enum BTPowerModeType {
    case powermode
    case highpowermode
    case lowpowermode
    case none
}

enum BTPowerMode {
    private static func parseCapabilityTokens(_ output: String) -> Set<String> {
        var tokens: Set<String> = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let first = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first
            if let first {
                tokens.insert(String(first).lowercased())
            }
        }
        return tokens
    }

    static func getSupportedType() -> BTPowerModeType {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "cap"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
        } catch {
            return .none
        }
        
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return .none
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.lowercased() else {
            return .none
        }

        let tokens = parseCapabilityTokens(output)
        if tokens.contains("highpowermode") {
            return .highpowermode
        } else if tokens.contains("powermode") {
            return .powermode
        } else if tokens.contains("lowpowermode") {
            return .lowpowermode
        }
        
        return .none
    }
    
    static func set(scope: BTPowerManagementScope, mode: UInt8) -> Bool {
        return set(scope: scope, mode: mode, type: getSupportedType())
    }
    
    static func set(scope: BTPowerManagementScope, mode: UInt8, type: BTPowerModeType) -> Bool {
        guard mode <= 2 else {
            return false
        }
        guard type != .none else {
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
        
        let modeKey: String
        switch type {
        case .highpowermode:
            modeKey = "highpowermode"
        case .powermode:
            modeKey = "powermode"
        case .lowpowermode:
            modeKey = "lowpowermode"
        case .none:
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = [scopeArg, modeKey, "\(mode)"]
        let errPipe = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                _ = errPipe.fileHandleForReading.readDataToEndOfFile()
                return false
            }
            return true
        } catch {
            return false
        }
    }
    
    static func readCurrent(type: BTPowerModeType? = nil) -> (all: Int?, battery: Int?, charger: Int?) {
        let resolvedType = type ?? getSupportedType()
        guard resolvedType != .none else {
            return (nil, nil, nil)
        }
        
        let modeKey: String
        switch resolvedType {
        case .highpowermode:
            modeKey = "highpowermode"
        case .powermode:
            modeKey = "powermode"
        case .lowpowermode:
            modeKey = "lowpowermode"
        case .none:
            return (nil, nil, nil)
        }
        
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
        var section: BTPowerManagementScope = .all

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
            guard parts[0].lowercased() == modeKey.lowercased() else {
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
    
    static func checkAndSetHighPowerMode() -> Bool {
        let type = getSupportedType()
        guard type != .none else {
            return false
        }
        let currentState = readCurrent(type: type)
        let previousAll = currentState.all
        let previousAC = currentState.charger
        let previousBattery = currentState.battery

        let setAll = set(scope: .all, mode: 2, type: type)
        let afterSet = readCurrent(type: type)
        let highStuck = afterSet.all == 2 || afterSet.charger == 2 || afterSet.battery == 2

        if let previousAll {
            _ = set(scope: .all, mode: UInt8(previousAll), type: type)
        }
        if let previousBattery {
            _ = set(scope: .battery, mode: UInt8(previousBattery), type: type)
        }
        if let previousAC {
            _ = set(scope: .charger, mode: UInt8(previousAC), type: type)
        }

        return setAll && highStuck
    }
}
