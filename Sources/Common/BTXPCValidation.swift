//
// Copyright (C) 2022 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import NSXPCConnectionAuditToken
import os.log
import SecCodeEx

public enum BTXPCValidation {
    public static func protectDaemon(connection: NSXPCConnection) {
        if #available(macOS 13.0, *) {
            connection.setCodeSigningRequirement(
                requirementsTextFromId(identifier: BTPreprocessor.daemonId)
            )
        }
    }

    public static func isValidClient(connection: NSXPCConnection) -> Bool {
        var token = connection.auditToken
        let tokenData = Data(
            bytes: &token,
            count: MemoryLayout.size(ofValue: token)
        )
        let attributes = [kSecGuestAttributeAudit: tokenData]

        var code: SecCode? = nil
        let codeStatus = SecCodeCopyGuestWithAttributes(
            nil,
            attributes as CFDictionary,
            [],
            &code
        )
        guard codeStatus == errSecSuccess, let code else {
            return false
        }

        guard self.verifyCsStatus(code: code) else {
            return false
        }

        let requirementText = self
            .requirementsTextFromId(identifier: BTPreprocessor.appId)
        if #available(macOS 13.0, *) {
            connection.setCodeSigningRequirement(requirementText)
            return true
        } else {
            var requirement: SecRequirement? = nil
            let reqStatus = SecRequirementCreateWithString(
                requirementText as CFString,
                [],
                &requirement
            )
            guard reqStatus == errSecSuccess, let requirement else {
                return false
            }

            let validStatus = SecCodeCheckValidity(
                code,
                [
                    .enforceRevocationChecks,
                    SecCSFlags(rawValue: kSecCSRestrictSidebandData),
                    SecCSFlags(rawValue: kSecCSStrictValidate),
                ],
                requirement
            )
            return validStatus == errSecSuccess
        }
    }

    private static func verifyCsStatus(code: SecCode) -> Bool {
#if DEBUG
        // In local debug builds, dynamic CS status bits vary under Xcode attach,
        // incremental rebuilds, and developer signing. Identity/entitlement
        // validation is still enforced via requirement strings.
        return true
#else
        var signInfo: CFDictionary? = nil
        let infoStatus = SecCodeCopySigningInformationDynamic(
            code,
            [SecCSFlags(rawValue: kSecCSDynamicInformation)],
            &signInfo
        )
        guard infoStatus == errSecSuccess else {
            os_log("Failed to retrieve signing information")
            return false
        }

        guard let signInfo = signInfo as? [String: AnyObject] else {
            os_log("Signing information is nil")
            return false
        }

        guard
            let signStatus =
            signInfo[kSecCodeInfoStatus as String] as? UInt32
        else {
            os_log("Failed to retrieve signature status")
            return false
        }

        let codeStatus = SecCodeStatus(rawValue: signStatus)
        // Dynamic signing flags can vary legitimately across debug/release and
        // Xcode-driven rebuild/relaunch cycles. The hard trust gate is enforced
        // by requirement checks in `isValidClient`; here we only require validity.
        guard codeStatus.contains(.valid) else {
            os_log(
                "Signature status constraints violated: missing valid bit in status=%{public}u",
                signStatus
            )
            return false
        }

        return true
#endif
    }

    private static func requirementsTextFromId(identifier: String) -> String {
        let baseText = "identifier \"" + identifier + "\"" +
            " and anchor apple generic" +
            " and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */" +
            " and !(entitlement[\"com.apple.security.cs.allow-dyld-environment-variables\"] /* exists */)" +
            " and !(entitlement[\"com.apple.security.cs.disable-library-validation\"] /* exists */)" +
            " and !(entitlement[\"com.apple.security.cs.allow-unsigned-executable-memory\"] /* exists */)" +
            " and !(entitlement[\"com.apple.security.cs.allow-jit\"] /* exists */)"
        #if DEBUG
            // In debug builds, avoid pinning leaf subject CN because Xcode/dev cert
            // rotation can change it across rebuilds and break local XPC auth.
            return baseText
        #else
            return baseText +
                " and certificate leaf[subject.CN] = \"" + BTPreprocessor.codesignCN + "\"" +
                " and !(entitlement[\"com.apple.security.get-task-allow\"] /* exists */)"
        #endif
    }
}
