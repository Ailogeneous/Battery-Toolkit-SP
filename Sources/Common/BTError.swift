//
// Copyright (C) 2022 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

public enum BTError: UInt8, Error {
    case success
    case unknown
    case notAuthorized
    case commFailed
    case malformedData
    case unsupported
    case fanCountUnavailable
    case fanModeInfoUnavailable
    case fanModeReadFailed
    case fanModeWriteFailed
    case fanUnlockFailed
    case fanTargetInfoUnavailable
    case fanTargetReadFailed
    case fanTargetWriteFailed
    case fanUnsupportedDataType
    case fanResetFailed

    public init(fromBool: Bool) {
        self = fromBool ? .success : .unknown
    }
}

extension BTError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .success:
            return "Success."
        case .unknown:
            return "Unknown error."
        case .notAuthorized:
            return "Not authorized."
        case .commFailed:
            return "Communication with daemon failed."
        case .malformedData:
            return "Malformed data."
        case .unsupported:
            return "Unsupported on this machine."
        case .fanCountUnavailable:
            return "Fan count unavailable."
        case .fanModeInfoUnavailable:
            return "Fan mode key info unavailable."
        case .fanModeReadFailed:
            return "Failed to read fan mode."
        case .fanModeWriteFailed:
            return "Failed to write fan mode."
        case .fanUnlockFailed:
            return "Failed to unlock manual fan control."
        case .fanTargetInfoUnavailable:
            return "Fan target key info unavailable."
        case .fanTargetReadFailed:
            return "Failed to read fan target."
        case .fanTargetWriteFailed:
            return "Failed to write fan target."
        case .fanUnsupportedDataType:
            return "Unsupported fan data type."
        case .fanResetFailed:
            return "Failed to reset fan control."
        }
    }
}
