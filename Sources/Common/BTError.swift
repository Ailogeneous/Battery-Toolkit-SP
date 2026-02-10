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

    public init(fromBool: Bool) {
        self = fromBool ? .success : .unknown
    }
}
