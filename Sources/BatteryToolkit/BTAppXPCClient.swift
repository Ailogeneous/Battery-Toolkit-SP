//
// Copyright (C) 2022 - 2025 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import ServiceManagement

@BTBackgroundActor
public enum BTAppXPCClient {
    public static func getAuthorization() async throws -> Data {
        try await self.getAuthorizationData(rightName: nil)
    }

    public static func getDaemonAuthorization() async throws -> Data {
        try await self.getAuthorizationData(rightName: kSMRightModifySystemDaemons)
    }

    public static func getManageAuthorization() async throws -> Data {
        return Data()
    }

    private static func getAuthorizationData(rightName: String?) async throws -> Data {
        guard let simpleAuth = SimpleAuth.empty() else {
            throw BTError.notAuthorized
        }

        if let rightName {
            let success = SimpleAuth.acquireInteractive(
                simpleAuth: simpleAuth,
                rightName: rightName
            )
            guard success else {
                throw BTError.notAuthorized
            }
        }

        guard let data = SimpleAuth.toData(simpleAuth: simpleAuth) else {
            throw BTError.malformedData
        }

        return data
    }
}
