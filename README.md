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
- Explicit charging actions (`chargeToLimit`, `chargeToFull`, `disableCharging`)
- Adapter control (`disablePowerAdapter`, `enablePowerAdapter`)
- Pause/resume daemon activity
- Daemon state fetch + live event streaming
- macOS power mode switching (`pmset powermode`)
- `pmset` value updates (`hibernatemode`, `standby`, delays, threshold)
- MagSafe indicator control modes
- Battery temperature included in daemon state

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
// mode: 0 = low, 1 = automatic, 2 = high
try await BTActions.setPowerMode(scope: .all, mode: 1)
try await BTActions.setPowerMode(scope: .battery, mode: 0)
try await BTActions.setPowerMode(scope: .charger, mode: 2)
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
