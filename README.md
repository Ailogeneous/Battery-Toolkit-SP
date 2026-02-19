[logo]: Resources/logo.png

![Logo][logo]

<div align="center">

**A Swift Package that provides Apple Silicon Mac battery charging control logic.**

[Capabilities](#capabilities) • [Limitations](#limitations) • [Using BatteryToolkit](#using-batterytoolkit) • [Copy (SMAppService helper)](#copy-smappservice-helper)

</div>

-----

# About

This is a Swift Package version of the original [Battery-Toolkit](https://github.com/mhaeuser/Battery-Toolkit/) project. It uses SMAppService (not SMJobBless) and removes the UI so you can provide your own. This repository is now SwiftPM‑only (no Xcode project file).

# Capabilities

`BatteryToolkit` provides the core logic to manage the power state of Apple Silicon Macs. You can integrate features such as:

## Limiting battery charge to an upper limit

Modern batteries deteriorate more when always kept at full charge. Apple’s “Optimized Charging” is not configurable. `BatteryToolkit` allows specifying a hard limit past which charging is turned off. For safety reasons, this limit cannot be lower than 50%.

## Allowing battery charge to drain to a lower limit

`BatteryToolkit` allows specifying a limit below which charging is turned on. For safety reasons, this limit cannot be lower than 20%.

**Note:** This setting is not honoured for cold boots or reboots, because Apple Silicon Macs reset their platform state in these cases. As battery charging will already be ongoing when a client using `BatteryToolkit` starts, it lets charging proceed to the upper limit to avoid short bursts across reboots.

## Disabling the power adapter

You can turn off the power adapter without unplugging it (for example, to discharge the battery). You can also integrate logic to disable sleeping when the adapter is disabled.

**Note:** Your Mac may go to sleep immediately after enabling the power adapter again. This is a macOS bug and cannot easily be worked around.

## Manual control

Commands include:
* Enabling and disabling the power adapter
* Requesting a full charge
* Requesting a charge to the specified upper limit
* Stopping charging immediately
* Pausing all background activity

# Limitations

* **Sleep management:** When actively managing charging to an upper limit, a client may need to disable sleep to prevent the system from entering a state where charging control is lost. Sleep can be re-enabled once charging is stopped.
* **Shutdown state:** Control over the charge state is not possible when the machine is shut down. If the charger remains plugged in while the Mac is off, the battery will charge to 100%.
* **Power adapter and sleep:** When the power adapter is disabled, sleep should generally also be disabled. Otherwise, exiting Clamshell mode may cause the machine to sleep immediately.

# Using BatteryToolkit

> [!IMPORTANT]
> `BatteryToolkit` currently only supports Apple Silicon Macs ([#15](https://github.com/mhaeuser/Battery-Toolkit/issues/15))

## Add the package

1. In your Xcode project, go to `File > Add Packages...`.
2. Paste the repo URL: `https://github.com/Ailogeneous/Battery-Toolkit-SP`.
3. Add the package to the targets that need battery control logic (app, helper, or both).

## Quick start

1. Add the package to your app and helper targets.
2. Create a helper target (see “Helper target setup”).
3. Configure App Group entitlements for both targets (see “App Group setup”).
4. Set the required UserDefaults values in your app at launch.

## Helper target setup

Create a minimal helper target that links BatteryToolkit. This helper should be a macOS command‑line tool or app that runs the daemon entrypoint.

1. In Xcode, create a new target:
   - macOS “Command Line Tool” (recommended)
   - Product Name: your helper bundle ID suffix (e.g. `TetheredHelper`)
2. Add `BatteryToolkit` package to the helper target’s dependencies.
3. Add a `main.swift` file to the helper target with:

```swift
import BatteryToolkit

BTPreprocessor.configure(appGroupSuiteName: "group.your.app")

// Start the daemon process.
BTDaemon.main()
```

4. Add a launchd plist to your app bundle (used by SMAppService):
   - Filename must match the helper bundle ID (e.g. `com.example.app.helper.plist`)
   - The `Label` and `MachServices` must match the daemon connection name.
   - It must be embedded at: `YourApp.app/Contents/Library/LaunchServices/`

Example launchd plist:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.example.app.helper</string>
  <key>MachServices</key>
  <dict>
    <key>TEAMID.com.example.app.helper</key>
    <true/>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
```

## App Group setup

You must enable an App Group so the app and helper can share UserDefaults.

1. In Xcode, select your app target.
2. Go to “Signing & Capabilities”.
3. Add “App Groups”.
4. Create or select an App Group ID, e.g. `group.com.example.app`.
5. Repeat steps 1–4 for the helper target using the same App Group ID.

Use that App Group ID with `BTPreprocessor.configure(appGroupSuiteName:)` in both app and helper at process startup (app: `applicationDidFinishLaunching`, helper: `main.swift`).

## Runtime config (UserDefaults + App Group)

`BatteryToolkit` reads its identifiers from a shared `UserDefaults` suite (App Group). This allows the main app to set values at launch, and the daemon to read the same values at runtime.

### Required keys (UserDefaults)

Set these in the shared App Group suite:

* `BT_APP_ID` (your app bundle identifier)
* `BT_DAEMON_ID` (your daemon bundle identifier)
* `BT_DAEMON_CONN` (your launchd Mach service name)
* `BT_CODESIGN_CN` (the certificate Common Name used to sign app + helper)

- See "Finding BTPreprocessor Values" below on where to find these IDs.

### Configure the suite

Call this **at process startup** (before any BatteryToolkit usage):

```swift
BTPreprocessor.configure(appGroupSuiteName: "group.your.app")
```

### Set values (from the app)

```swift
BTPreprocessor.setValues(
    appId: "com.example.app",
    daemonId: "com.example.app.helper",
    daemonConn: "TEAMID.com.example.app.helper",
    codesignCN: "Apple Development: Your Name (TEAMID)"
)
```

If any required key is missing, BatteryToolkit will fail with an explicit error.

> [!IMPORTANT]
> Both the App and Helper targets must include the same App Group entitlement, or shared UserDefaults will not work.

### Finding BTPreprocessor Values (manual)

Check these sources for ID constants:
* `BT_APP_ID`: your app `Info.plist` `CFBundleIdentifier`
* `BT_DAEMON_ID`: helper `Info.plist` `CFBundleIdentifier`
* `BT_DAEMON_CONN`: launchd plist `MachServices` key
* `BT_TEAM_ID`: run `codesign -dv --verbose=4 /path/MyApp.app` or  Xcode signing settings
* `BT_CODESIGN_CN`: run `codesign -dv --verbose=4 /path/MyApp.app` and use the first `Authority=` line (it looks like `Authority=Apple Development: Your Name (TEAMID)`).

## App-side registration (SMAppService)

Use this in your app target to register/unregister the helper. The `plistName` must match the launchd plist filename (without extension) that you embed in your app bundle.

```swift
import ServiceManagement

BTPreprocessor.configure(appGroupSuiteName: "group.your.app")
BTPreprocessor.setValues(
    appId: "com.example.app",
    daemonId: "com.example.app.helper",
    daemonConn: "TEAMID.com.example.app.helper",
    codesignCN: "Apple Development: Your Name (TEAMID)"
)

let service = SMAppService.daemon(plistName: "\(BTPreprocessor.daemonId).plist")
try await service.register()
// Later, to remove it:
// try await service.unregister()
```

## App-side interaction

Use the app client to request authorization and call into the helper. These helpers are intentionally light wrappers around XPC calls.

```swift
import BatteryToolkit

// Convenience facade (optional)
let status = await BTActions.startDaemon()
if status == .requiresApproval {
    try await BTActions.approveDaemon(timeout: 6)
}

// Direct client usage
let authData = try await BTAppXPCClient.getManageAuthorization()
try await BTDaemonXPCClient.disableCharging()

let state = try await BTDaemonXPCClient.getState()

// Update settings
try await BTDaemonXPCClient.setSettings(settings: [
    BTSettingsInfo.Keys.minCharge: NSNumber(value: 70),
    BTSettingsInfo.Keys.maxCharge: NSNumber(value: 80),
    BTSettingsInfo.Keys.adapterSleep: NSNumber(value: false),
    BTSettingsInfo.Keys.magSafeSync: NSNumber(value: false),
])
```

## Helper-side validation

The helper validates `authData` per privileged call with `AuthorizationCopyRights`. It also validates client identity with audit token and code signing checks (`BTXPCValidation`).

## Wiring checklist

* Your app’s `NSXPCConnection(machServiceName:options:)` must match the helper’s Mach service name (`BTDaemonConn`).
* The helper launchd plist `Label` and `MachServices` must match `BTDaemonConn`.
* The helper `Info.plist` `SMAuthorizedClients` must match your app’s code signing identity.
* Both app and helper must use the same App Group suite and set the four `BT_*` keys in shared UserDefaults.

# Credits
*   Icon based on [reference icon by Streamline](https://seekicon.com/free-icon/rechargable-battery_1)

# Donate
Message from Battery Toolkit Owner: For various reasons, I will not accept personal donations. However, if you would like to support my work with the [Kinderschutzbund Kaiserslautern-Kusel](https://www.kinderschutzbund-kaiserslautern.de/) child protection association, you may donate [here](https://www.kinderschutzbund-kaiserslautern.de/helfen-sie-mit/spenden/).
