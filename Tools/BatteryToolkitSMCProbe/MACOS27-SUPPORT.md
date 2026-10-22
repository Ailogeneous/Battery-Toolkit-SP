# macOS 27 charging support development

The Toolkit now selects BTNativeCharging27 only when the OS major version is exactly 27. Other OS versions retain the existing SMC charge-key path. AppleSMC and a readable CHLT state key remain startup requirements.

The daemon releases the ordinary PowerUI limit through its client, serializes its own ChargeCtrlPolicy with its own PID, preserves unrelated policy owners, updates powerd's charging preferences and sends SIGHUP. On the tested OS this restarts powerd. The policy uses drain=false and isEndOfCharge=true. noChargeToFull is enabled only for configured limits below80, and only while the effective target is also below80. Charge-to-full removes that protection and the Toolkit policy. The existing upper/lower charge event handling selects thresholds; a pause request never selects a threshold above current charge. Requests below20 are rejected. Exact arbitrary charge pause and firmware response timing are not guaranteed by this native threshold mechanism.

The integration uses the PowerUI release before policy injection. Writing and notifying the BatFi topoff preferences at the same time produced a race in testing: PowerUIAgent replaced the protected policy. That combined writer was removed. Root topoff values are still captured/restored because the PowerUI client changes them.

## Recovery

Before control starts the daemon saves original charging preferences, topoff key presence/values, and boot identity to /Library/Application Support/BatteryToolkit/macOS27/original.plist. It retains this file across helper updates/crashes. Pause/normal termination removes Toolkit policies, restores the original manual policies and preferences, preserves unrelated current policy owners, and restarts powerd. The snapshot remains if recovery reports failure. An update suspends observation while preserving the recovery snapshot for the replacement daemon.

The standalone native27-integration-probe supports --restore for recovery, --test-75-and-restore for a two-minute hold, and --test-transitions-and-restore for 75 ->80 ->100 ->75. SIGINT/TERM/HUP trigger recovery. Forced termination cannot guarantee immediate cleanup; retain the snapshot.

Build the standalone probe from the repository root:

```sh
xcrun clang -c Sources/Modules/MachTaskSelf/MachTaskSelf.c -o /tmp/tethered-machself.o
xcrun swiftc -parse-as-library -I Sources/Modules/MachTaskSelf -I Sources/Modules/SMCParamStruct Sources/Libraries/SMCComm.swift Sources/me.mhaeuser.batterytoolkitd/BTNativeCharging27.swift Tools/BatteryToolkitSMCProbe/native27-integration-probe.swift /tmp/tethered-machself.o -framework IOKit -o /tmp/tethered-native27-integration-probe
sudo /tmp/tethered-native27-integration-probe --test-75-and-restore
```

## Observation

After rebuilding the application and replacing its helper, observation starts with the Toolkit daemon. The currently installed app/helper is not replaced by swift build or by running the standalone probe.

Root-only charging.jsonl and charging.previous.jsonl live beside the snapshot. Each file rotates at approximately8MiB, bounding storage at approximately16MiB. Samples every15seconds include AC presence, signed current, charging state, battery percentage, voltage, CHLT/bfG0, requested policy and persisted policy fields. A child log stream captures selected powerd/PowerUIAgent policy, MCL and gauging-mitigation events. Pause/stop ends this stream. XPC diagnostics expose requested target, submission status, protection flag, retry count and SMC state separately.

After45seconds, an unexpected CHLT target/flag triggers a bounded retry. Three failed/drifting submissions exhaust automatic retries until a different request or a subsequently observed matching state resets the budget. Accepted requests are not proof of physical charging state. Preserve journals when reporting a calibration event; include powerd mitigation messages and actual current direction.

## Verified and remaining

On macOS27.0.1/build26A434: package build and independent archive-schema/secure-decoding validation passed. The live transition test adopted75 with protection,80 without protection,100 with no Toolkit limit, then75 with protection; cleanup returned no native battery limits. The two-minute75 hold on AC eventually showed charging=false and current0, while CHLT stayed4b0601. It took about64seconds for the current observation to settle. Final cleanup returned CHLT/bfG0 to000000 and no battery limit.

Still unverified: suppression during an actual calibration event, holding at75 after discharging to it, charging from below the lower threshold, sleep/wake behavior and long-running daemon operation after the application rebuild. The policy flag bypasses an identified powerd suspension branch; this does not establish that the calibration scheduler stops running. No claim of days-long validation is made.
