//
// Copyright (C) 2022 - 2025 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import ServiceManagement

@BTBackgroundActor
public enum BTAppXPCClient {
    private static var manageAuthorizationData: Data?

    public static func getAuthorization() async throws -> Data {
        try await self.getAuthorizationData(rightName: nil)
    }

    public static func getDaemonAuthorization() async throws -> Data {
        try await self.getAuthorizationData(rightName: kSMRightModifySystemDaemons)
    }

    public static func getManageAuthorization() async throws -> Data {
        if let manageAuthorizationData {
            return manageAuthorizationData
        }

#if DEBUG
        let data = try await self.getAuthorizationData(rightName: nil)
#else
        let data = try await self.getAuthorizationData(rightName: BTAuthorizationRights.manage)
#endif
        self.manageAuthorizationData = data
        return data
    }

    public static func invalidateManageAuthorization() {
        self.manageAuthorizationData = nil
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
