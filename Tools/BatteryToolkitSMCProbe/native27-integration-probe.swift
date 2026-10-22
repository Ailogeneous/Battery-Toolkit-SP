import Foundation

@main
struct NativeChargingIntegrationProbe {
    @MainActor static func main() async {
        guard CommandLine.arguments.count == 2, ["--test-75-and-restore", "--restore"].contains(CommandLine.arguments[1]) else {
            print("Usage: native27-integration-probe --test-75-and-restore | --restore")
            exit(1)
        }
        guard SMCComm.start(), BTNativeCharging27.start() else { print("START FAILED"); exit(2) }
        if CommandLine.arguments[1] == "--restore" {
            let restored = BTNativeCharging27.restore()
            print("restored=\(restored)")
            exit(restored ? 0 : 3)
        }
        let signals = [SIGINT, SIGTERM, SIGHUP].map { value -> DispatchSourceSignal in
            signal(value, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: value, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    let restored = BTNativeCharging27.restore()
                    print("interrupted restored=\(restored)")
                    exit(restored ? 0 : 3)
                }
            }
            source.resume()
            return source
        }
        let accepted = BTNativeCharging27.request(limit: 75, suppressCalibration: true)
        print("pid=\(getpid()) submitted=\(accepted)")
        if accepted {
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                process.arguments = ["-g", "battlimit"]
                try? process.run()
                process.waitUntilExit()
                BTNativeCharging27.sampleAndReconcile()
            }
        }
        let restored = BTNativeCharging27.restore()
        print("restored=\(restored)")
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "battlimit"]
        try? process.run()
        process.waitUntilExit()
        withExtendedLifetime(signals) {}
        SMCComm.stop()
        exit(accepted && restored ? 0 : 3)
    }
}
