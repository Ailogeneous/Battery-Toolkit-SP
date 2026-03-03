//
// Copyright (C) 2022 - 2025 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log

@BTBackgroundActor
public enum BTDaemonXPCClient {
    private static var connect: NSXPCConnection? = nil
    private static var eventSink: EventSink? = nil

    private final class EventSink: NSObject, BTDaemonEventsProtocol {
        let handler: @Sendable ([String: NSObject & Sendable]) -> Void

        init(handler: @escaping @Sendable ([String: NSObject & Sendable]) -> Void) {
            self.handler = handler
        }

        func stateDidChange(_ state: [String: NSObject & Sendable]) {
            self.handler(state)
        }
    }

    public static func disconnectDaemon() {
        guard let connect = self.connect else {
            return
        }

        self.connect = nil
        connect.invalidate()
    }

    public static func startEventStream(
        handler: @escaping @Sendable ([String: NSObject & Sendable]) -> Void
    ) {
        os_log("BTDaemonXPCClient startEventStream")
        self.eventSink = EventSink(handler: handler)
        if self.connect != nil {
            self.disconnectDaemon()
        }
        _ = self.connectDaemon()
    }

    public static func stopEventStream() {
        self.eventSink = nil
        if self.connect != nil {
            self.disconnectDaemon()
        }
    }

    public static func getUniqueId() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.executeDaemonRetry(continuation: continuation) { daemon in
                daemon.getUniqueId { data in
                    guard let data = data else {
                        continuation.resume(throwing: BTError.malformedData)
                        return
                    }

                    continuation.resume(returning: data)
                }
            }
        }
    }

    public static func getState() async throws -> [String: NSObject & Sendable] {
        try await withCheckedThrowingContinuation { continuation in
            self.executeDaemonRetry(continuation: continuation) { daemon in
                daemon.getState { state in
                    continuation.resume(returning: state)
                }
            }
        }
    }

    public static func disablePowerAdapter() async throws {
        let authData = try await BTAppXPCClient.getManageAuthorization()
        try await withCheckedThrowingContinuation { continuation in
            self.runExecute(
                continuation: continuation,
                authData: authData,
                command: BTDaemonCommCommand.disablePowerAdapter
            )
        }
    }

    public static func enablePowerAdapter() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.runExecute(
                continuation: continuation,
                authData: nil,
                command: BTDaemonCommCommand.enablePowerAdapter
            )
        }
    }

    public static func chargeToLimit() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.runExecute(
                continuation: continuation,
                authData: nil,
                command: BTDaemonCommCommand.chargeToLimit
            )
        }
    }

    public static func chargeToFull() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.runExecute(
                continuation: continuation,
                authData: nil,
                command: BTDaemonCommCommand.chargeToFull
            )
        }
    }

    public static func disableCharging() async throws {
        let authData = try await BTAppXPCClient.getManageAuthorization()
        try await withCheckedThrowingContinuation { continuation in
            self.runExecute(
                continuation: continuation,
                authData: authData,
                command: BTDaemonCommCommand.disableCharging
            )
        }
    }

    public static func pauseActivity() async throws {
        let authData = try await BTAppXPCClient.getManageAuthorization()
        try await withCheckedThrowingContinuation { continuation in
            self.runExecute(
                continuation: continuation,
                authData: authData,
                command: BTDaemonCommCommand.pauseActivity
            )
        }
    }

    public static func resumeActivity() async throws {
        let authData = try await BTAppXPCClient.getManageAuthorization()
        try await withCheckedThrowingContinuation { continuation in
            self.runExecute(
                continuation: continuation,
                authData: authData,
                command: BTDaemonCommCommand.resumeActivity
            )
        }
    }

    public static func setMagSafeIndicator(mode: BTMagSafeIndicatorMode) async throws {
        let authData = try await BTAppXPCClient.getManageAuthorization()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            self.executeDaemonManageRetry(continuation: continuation) { daemon in
                daemon.setMagSafeIndicator(
                    authData: authData,
                    mode: mode.rawValue,
                    reply: self.continuationStatusHandler(continuation: continuation)
                )
            }
        }
    }

    public static func getSettings() async throws -> [String: NSObject & Sendable] {
        try await withCheckedThrowingContinuation { continuation in
            self.executeDaemonRetry(continuation: continuation) { daemon in
                daemon.getSettings { settings in
                    continuation.resume(returning: settings)
                }
            }
        }
    }

    public static func setSettings(settings: [String: NSObject & Sendable]) async throws {
        let authData = try await BTAppXPCClient.getManageAuthorization()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            self.executeDaemonManageRetry(continuation: continuation) { daemon in
                daemon.setSettings(
                    authData: authData,
                    settings: settings,
                    reply: self.continuationStatusHandler(continuation: continuation)
                )
            }
        }
    }


    public static func setPMSet(setting: BTPMSetSetting, value: Int, scope: BTPowerModeScope) async throws {
        let authData = try await BTAppXPCClient.getManageAuthorization()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            self.executeDaemonManageRetry(continuation: continuation) { daemon in
                daemon.setPMSet(
                    authData: authData,
                    setting: setting.rawValue,
                    value: value,
                    scope: scope.rawValue,
                    reply: self.continuationStatusHandler(continuation: continuation)
                )
            }
        }
    }

    public static func setPowerMode(scope: BTPowerModeScope, mode: UInt8) async throws {
        let authData = try await BTAppXPCClient.getManageAuthorization()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            self.executeDaemonManageRetry(continuation: continuation) { daemon in
                daemon.setPowerMode(
                    authData: authData,
                    scope: scope.rawValue,
                    mode: mode,
                    reply: self.continuationStatusHandler(continuation: continuation)
                )
            }
        }
    }

    public static func prepareUpdate() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            self.executeDaemonRetry(continuation: continuation) { daemon in
                daemon.execute(
                    authData: nil,
                    command: BTDaemonCommCommand.prepareUpdate.rawValue,
                    reply: self.continuationStatusHandler(continuation: continuation)
                )
            }
        }
    }

    public static func finishUpdate() {
        Task {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    self.runExecute(continuation: continuation, authData: nil, command: BTDaemonCommCommand.finishUpdate)
                }
            }
            catch {
                //
                // Deliberately ignore errors as this is an optional notification.
                //
            }
        }
    }



    public static func isSupported() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            self.runExecute(continuation: continuation, authData: nil, command: BTDaemonCommCommand.isSupported)
        }
    }

    private static func continuationStatusHandler(continuation: CheckedContinuation<Void, any Error>) -> (@Sendable (BTError.RawValue) -> Void) {
        return { error in
            guard error == BTError.success.rawValue else {
                continuation.resume(throwing: BTError.init(rawValue: error)!)
                return
            }
            continuation.resume()
        }
    }
    
    private static func connectDaemon() -> NSXPCConnection {
        if let connect = self.connect {
            return connect
        }

        let connect = NSXPCConnection(
            machServiceName: BTPreprocessor.daemonConn,
            options: .privileged
        )
        connect.remoteObjectInterface = NSXPCInterface(
            with: BTDaemonCommProtocol.self
        )
        if let eventSink = self.eventSink {
            connect.exportedInterface = NSXPCInterface(
                with: BTDaemonEventsProtocol.self
            )
            connect.exportedObject = eventSink
        }

        BTXPCValidation.protectDaemon(connection: connect)

        connect.resume()
        self.connect = connect

        os_log("XPC client connected")

        return connect
    }

    private static func executeDaemon(
        command: @BTBackgroundActor @Sendable (BTDaemonCommProtocol) -> Void,
        errorHandler: @escaping @Sendable (any Error) -> Void
    ) {
        let connect = self.connectDaemon()
        let daemon = connect.remoteObjectProxyWithErrorHandler(
            errorHandler
        ) as! BTDaemonCommProtocol
        command(daemon)
    }

    private static func executeDaemonRetry<T>(
        continuation: CheckedContinuation<T, any Error>,
        command: @BTBackgroundActor @escaping @Sendable (BTDaemonCommProtocol) -> Void
    ) {
        self.executeDaemon(command: command) { error in
            os_log("XPC client remote error: \(error, privacy: .public))")
            os_log("Retrying...")
            Task { @BTBackgroundActor in
                self.disconnectDaemon()
                self.executeDaemon(command: command) { error in
                    os_log("XPC client remote error: \(error, privacy: .public))")
                    continuation.resume(throwing: BTError.commFailed)
                }
            }
        }
    }

    private static func executeDaemonManageRetry<T>(
        continuation: CheckedContinuation<T, any Error>,
        command: @BTBackgroundActor @escaping @Sendable (BTDaemonCommProtocol) -> Void
    ) {
        self.executeDaemonRetry(continuation: continuation, command: command)
    }

    private static func runExecute(
        continuation: CheckedContinuation<Void, any Error>,
        authData: Data?,
        command: BTDaemonCommCommand
    ) {
        self.executeDaemonManageRetry(continuation: continuation) { daemon in
            daemon.execute(
                authData: authData,
                command: command.rawValue,
                reply: self.continuationStatusHandler(continuation: continuation)
            )
        }
    }
}
