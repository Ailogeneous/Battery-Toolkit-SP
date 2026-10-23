[logo]: Resources/logo.png

![Logo][logo]

<div align="center">

**A Swift Package for Apple Silicon battery charging control with an SMAppService daemon.**

[Capabilities](#capabilities) • [Setup](#setup) • [Examples](#examples) • [Troubleshooting](#troubleshooting)

</div>

---

## About

`Battery-Toolkit-SP` is a SwiftPM package fork of [Battery-Toolkit](https://github.com/mhaeuser/Battery-Toolkit/) adapted for app-owned UI and daemon orchestration.

- Uses `SMAppService` (not `SMJobBless`).
- Supports Apple Silicon Macs.
- Uses `BT_*` values from each target's `Info.plist`.
- App Group/shared `UserDefaults` setup is **not required**.

## Capabilities

- Charge limit window management (`minCharge`, `maxCharge`)
- Configurable charge lower bound (`chargeLowerBound`, default 20%, configurable from 1–100%)
- Explicit charging actions (`chargeToLimit`, `chargeToFull`, `disableCharging`)
- Adapter control (`disablePowerAdapter`, `enablePowerAdapter`)
- Pause/resume daemon activity
- Daemon state fetch + live event streaming
- macOS power mode switching (`pmset powermode`)
- `pmset` value updates (`hibernatemode`, `standby`, delays, threshold)
- MagSafe indicator control modes
- Battery temperature included in daemon state

---

## macOS 27 — Charging Backend & Diagnostics

> [!IMPORTANT]
> **macOS 27 uses a separate charging backend.** Review the policy behavior and diagnostics settings below when integrating or upgrading.

On macOS 27, the daemon uses a separate native charging-policy backend instead of the legacy direct SMC charging keys. The public charging actions remain the same. This backend is selected only when the reported macOS major version is 27; earlier versions retain the legacy backend. Newer major versions are not automatically opted into this path.

### Charging Policy

The root daemon releases the ordinary PowerUI charge limit, writes its own archived policy to `com.apple.powerd.charging`, and signals `powerd` with `SIGHUP` to reload it. It reads `CHLT` and `bfG0` to observe the resulting limit. This is an undocumented integration with private system interfaces, not a public Apple API or an entitlement bypass for direct SMC writes. Compatibility must be checked on the target OS build and hardware.

- `chargeToLimit()` submits the configured maximum charge threshold.
- `chargeToFull()` removes the toolkit's limiting policy and requests unrestricted charging.
- `disableCharging()` submits a ceiling at the lower of the configured minimum threshold and the current battery percentage. It does not use the legacy immediate charge-inhibit key.
- For configured maximums below 80%, limited charging requests also set the policy's `noChargeToFull` flag. Full-charge requests do not set it.
- The configurable `chargeLowerBound` defaults to 20%, just as on earlier versions. Lower thresholds require the host app to configure the bound and remove any separate UI or policy clamps.

The charge-limit backend does not cut adapter power to enforce its ceiling. Explicit adapter-control actions remain separate. Lowering a limit below the current battery percentage does not request forced discharge.

### Timing and Diagnostics

Verbose macOS 27 charging diagnostics are **off by default**. Enable or disable them at runtime using the persisted `nativeChargingDiagnosticsEnabled` setting:

```swift
var settings = try await BTActions.getSettings()
settings[BTSettingsInfo.Keys.nativeChargingDiagnosticsEnabled] = NSNumber(value: false)
try await BTActions.setSettings(settings: settings)
```

Use `true` to enable diagnostic recording. Omitting the key preserves the current setting. Disabling it stops the continuous system-log subprocess, periodic battery/policy samples, and native charging journal writes (including their unified-log copies). Existing journal files are retained. Charge enforcement, policy reconciliation, original-policy snapshots/restoration, and on-demand `getDiagnostics()` remain active. Startup and write failures still report through their existing error paths; this setting does not disable unrelated toolkit logs. The setting is stored on all versions but controls this verbose backend only on macOS 27.

Policy submission is not confirmation that charging has stopped. Applications should observe battery state and actual current after applying a limit. With verbose diagnostics enabled, the daemon records a battery sample every 15 seconds. Policy reconciliation runs every 15 seconds regardless of the diagnostics setting and checks for policy drift once at least 45 seconds have elapsed since the last write, with up to three write attempts before it stops retrying that request.

Coalesce slider changes before calling `setSettings`; avoid submitting every intermediate drag value. The current backend performs synchronous PowerUI calls, preference synchronization, and a process wait on the daemon's main actor, so frequent changes can delay subsequent requests.

`BTActions.getDiagnostics()` exposes `nativeCharging27`, `nativePolicySubmitted`, `nativeRequestedLimit`, `nativeNoChargeToFull`, `nativeRetryCount`, and `nativeSMCState` when available. `nativePolicySubmitted` reports submission success, not observed enforcement. Diagnostic journals and the original-policy snapshot are stored under `/Library/Application Support/BatteryToolkit/macOS27/` and require appropriate permissions to read.

---

## Setup

### 1. Add Package

1. Xcode → `File > Add Packages...`
2. URL: `https://github.com/Ailogeneous/Battery-Toolkit-SP`
3. Add package to app target and helper target.

### 2. Runtime Config (`Info.plist`)

Define these keys in both app and helper `Info.plist`:

- `BT_APP_ID`
- `BT_DAEMON_ID`
- `BT_DAEMON_CONN`
- `BT_CODESIGN_CN`

Example:

```xml
<key>BT_APP_ID</key>
<string>com.example.MyApp</string>
<key>BT_DAEMON_ID</key>
<string>com.example.MyApp.helper</string>
<key>BT_DAEMON_CONN</key>
<string>com.example.MyApp.helper</string>
<key>BT_CODESIGN_CN</key>
<string>Apple Development: Your Name (TEAMID)</string>
```

### 3. Helper Target

Use a helper target entrypoint:

```swift
import BatteryToolkit

BTDaemon.run()
```

### 4. launchd plist (for `SMAppService.daemon`)

Embed plist in app bundle at:

- `YourApp.app/Contents/Library/LaunchDaemons/<BT_DAEMON_ID>.plist`

Minimal example:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.example.MyApp.helper</string>

  <key>BundleProgram</key>
  <string>Contents/MacOS/MyHelperExecutable</string>

  <key>AssociatedBundleIdentifiers</key>
  <array>
    <string>com.example.MyApp</string>
  </array>

  <key>MachServices</key>
  <dict>
    <key>com.example.MyApp.helper</key>
    <true/>
  </dict>

  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
```

### 5. App Target Copy Phases

Configure two Copy Files phases in app target:

1. `Copy Helper Binary`
- Destination: `Executables`
- Subpath: *(empty)*
- Add helper product binary
- Enable `Code Sign On Copy`

2. `Copy Launchd Plist`
- Destination: `Contents/Library/LaunchDaemons`
- Add `<BT_DAEMON_ID>.plist`
- Enable `Code Sign On Copy`

### 6. Register / Approve Daemon

```swift
import BatteryToolkit

let status = await BTActions.startDaemon()
if status == .requiresApproval {
    try await BTActions.approveDaemon(timeout: 6)
}
```

## Examples

### Get State + Settings

```swift
import BatteryToolkit

let state = try await BTActions.getState()
let settings = try await BTActions.getSettings()

try await BTActions.setSettings(settings: [
    BTSettingsInfo.Keys.minCharge: NSNumber(value: 75),
    BTSettingsInfo.Keys.maxCharge: NSNumber(value: 90),
    BTSettingsInfo.Keys.adapterSleep: NSNumber(value: false),
    BTSettingsInfo.Keys.magSafeSync: NSNumber(value: true)
])
```

### Configurable Charge Lower Bound

The daemon defaults to a 20% lower bound for both charge thresholds on all backends. Configure `BTSettingsInfo.Keys.chargeLowerBound` through `BTActions.setSettings` to allow thresholds as low as 1%. The bound is persisted, returned by `getSettings`, and preserved when omitted from a settings update.

```swift
var settings = try await BTActions.getSettings()
settings[BTSettingsInfo.Keys.chargeLowerBound] = NSNumber(value: 10)
settings[BTSettingsInfo.Keys.minCharge] = NSNumber(value: 10)
settings[BTSettingsInfo.Keys.maxCharge] = NSNumber(value: 15)
try await BTActions.setSettings(settings: settings)
```

Updates must satisfy `1 <= chargeLowerBound <= minCharge <= maxCharge <= 100`. Invalid updates are rejected without changing the charging thresholds or bound. When raising the bound, submit thresholds at or above it in the same update. Hardware enforcement still depends on the available backend. Host apps must use the returned setting when applying their own threshold clamps; the `Bounds` constants describe the default range.

### Charging Control

```swift
try await BTActions.chargeToLimit()
try await BTActions.chargeToFull()
try await BTActions.disableCharging()
try await BTActions.disablePowerAdapter()
try await BTActions.enablePowerAdapter()
```

### Power Mode Control

```swift
// mode: 0 = auto, 1 = low, 2 = high
try await BTActions.setPowerMode(scope: .all, mode: 1)
try await BTActions.setPowerMode(scope: .battery, mode: 0)
try await BTActions.setPowerMode(scope: .charger, mode: 2)
```

Scope semantics:
- `.all`: apply to both battery and charger contexts
- `.battery`: apply only when on battery
- `.charger`: apply only when on AC power

### High Power Availability Probe

```swift
let supportsHighPowerMode = try await BTActions.checkHighPowerMode()
```

### PMSet Values

```swift
// hibernatemode: common values 0 (none), 3 (safe sleep), 25 (hibernate)
try await BTActions.setPMSetHibernatemode(3, scope: .all)

// standby: 0 (off), 1 (on)
try await BTActions.setPMSetStandby(1, scope: .all)

// delays are seconds
try await BTActions.setPMSetStandbyDelayLow(10800, scope: .all)   // 3h
try await BTActions.setPMSetStandbyDelayHigh(86400, scope: .all)  // 24h

// highstandbythreshold is battery %
try await BTActions.setPMSetHighStandbyThreshold(50, scope: .all)
```

PMSet scope options:
- `.all`
- `.battery`
- `.charger`

### MagSafe Indicator

```swift
try await BTActions.setMagSafeIndicator(mode: .sync)
try await BTActions.setMagSafeIndicator(mode: .green)
try await BTActions.setMagSafeIndicator(mode: .orange)
try await BTActions.setMagSafeIndicator(mode: .orangeSlowBlink)
```

Available modes:

- `.sync`, `.system`, `.off`
- `.green`, `.orange`
- `.orangeSlowBlink`, `.orangeFastBlink`, `.orangeBlinkOff`

### Caffeinate Controls

```swift
// finite session
try await BTActions.caffeinate(
    flags: [.preventUserIdleSystemSleep, .preventUserIdleDisplaySleep],
    durationSeconds: 900
)

// mixed per-flag durations
try await BTActions.setCaffeinateBuckets(buckets: [
    (flags: .preventUserIdleSystemSleep, durationSeconds: 1800),
    (flags: .preventUserIdleDisplaySleep, durationSeconds: 600)
])

// stop all managed caffeinate sessions
try await BTActions.killCaffeinate()
```

Available `BTCaffeinateFlags`:
- `.preventUserIdleSystemSleep`
- `.preventUserIdleDisplaySleep`
- `.preventDiskIdle`
- `.preventSystemSleep`
- `.userIsActive`

Notes:
- Default flags: `.preventUserIdleSystemSleep`
- `userIsActive` can have OS-version-specific behavior changes; validate on your deployment targets.

### Fan Control

```swift
let fans = try await BTActions.getFans()

// mode: 0 = auto, 1 = manual
try await BTActions.setFanMode(fanId: 0, mode: 1)
try await BTActions.setFanSpeed(fanId: 0, speed: 3200)

// lease manual fan control across all fans
try await BTActions.setFanControlLease(percent: 45, durationSeconds: 3600)

// return all fans to automatic system control
try await BTActions.resetFanControl()
```

`getFans()` entries contain:
- `id`
- `min`
- `max`
- `current`
- `target`
- `mode` (`0 = auto`, `1 = manual`)

Validation behavior:
- `setFanMode(fanId:mode:)`: valid mode values are `0` (auto) and `1` (manual).
- `setFanSpeed(fanId:speed:)`: speed is clamped to hardware-supported range.
- `setFanControlLease(percent:durationSeconds:)`: `percent` is clamped to `0...100`; very short durations are normalized by daemon policy.

### Battery Temperature Sources (On-Demand)

You can fetch battery temperature from multiple sources on demand. The daemon state stream still reports the IOKit temperature; these actions are for explicit reads (useful for higher-frequency polling in your app).

```swift
let iopsTemp = try await BTActions.getBatteryTemperature(source: .iops)
let tb0tTemp = try await BTActions.getBatteryTemperature(source: .smcTB0T)
let tb1tTemp = try await BTActions.getBatteryTemperature(source: .smcTB1T)
let tb2tTemp = try await BTActions.getBatteryTemperature(source: .smcTB2T)
let batpTemp = try await BTActions.getBatteryTemperature(source: .smcBATP)
```

### Event Stream

```swift
import Combine
import BatteryToolkit

BTDaemonEventCenter.start()

let cancellable = BTDaemonEventCenter.statePublisher
    .receive(on: RunLoop.main)
    .sink { state in
        // state keys include battery %, charging, AC, temperature, power modes
        print(state)
    }

// later:
BTDaemonEventCenter.stop()
cancellable.cancel()
```

### Calibration Note

Calibration scheduling is **host-app policy**, not package policy. Use package primitives (`chargeToFull`, `disablePowerAdapter`, `chargeToLimit`, state stream) to implement your own monthly/bi-monthly calibration workflow.

## Troubleshooting

- `requiresApproval`: call `BTActions.approveDaemon(timeout:)` and complete approval in System Settings.
- Helper not launching: verify plist location, `BundleProgram`, copy phases, and signing.
- Config failures: confirm all `BT_*` keys exist in app + helper `Info.plist`.
- XPC authorization failures: verify `BT_*` plist values, signing identity/`BT_CODESIGN_CN`, and that `BTXPCValidation` requirements match app/helper identities.
- If Login Items/Extensions background entry is stale, reset BTM and re-register:

```bash
sfltool resetbtm
```

Then relaunch app and call `BTActions.startDaemon()` again.

## License

BSD-3-Clause (see `LICENSE.txt`).

# Credits
* Icon based on [reference icon by Streamline](https://seekicon.com/free-icon/rechargable-battery_1)

# Donate
Message from mhaeuser: For various reasons, I will not accept personal donations. However, if you would like to support my work with the [Kinderschutzbund Kaiserslautern-Kusel](https://www.kinderschutzbund-kaiserslautern.de/) child protection association, you may donate [here](https://www.kinderschutzbund-kaiserslautern.de/helfen-sie-mit/spenden/).
