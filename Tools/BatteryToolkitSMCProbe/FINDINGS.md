# Charging-control investigation, 2026-10-21

## Scope and current state

Diagnostic investigation only. Functional capability refactor commits ce3ef7b and f3fe685 were reverted by 408425b and 990cda4. Runtime sources retain original support gates. Logging commit cc6be96 is diagnostic-only. Standalone capture tool is under Tools/BatteryToolkitSMCProbe, outside the library target. No unknown-key write sweep has been performed.

## Target and observed results

Mac15,6; macOS 27.0.1 build 26A434; firmware mBoot-20457.1.29.

CHTE, CH0B and CH0C: metadata returns IOKit success with SMC result 132. CHTE (4 bytes) and CH0C (1 byte) raw reads also return 132 as root with AC connected. Those keys were absent from the 2,422-entry advertised directory. CH0J, CHLS, bfD0, bfE0 and bfF0 metadata requests return 0xe00002c1 even as root.

CHIE metadata matches hex_, size 1, attributes 0xD4. A user-run root experiment wrote 08, verified readback and observed AC charging become battery discharging; restoring 00 verified readback and returned AC connection. Charging had not resumed after eight seconds. This proves adapter-cut behavior, not charging inhibition while running on AC.

## Native-limit capture experiment

Six root captures completed without enumeration failures. Data remains in ignored captures/01-100.json through captures/06-100.json. AC stayed connected. At baseline 100%, battery was 97% and charging at +844 mA. At 80%, charging stopped and current was negative. Both CHLT and bfG0 changed from 000000 to 500503 and returned to 000000 after restoring 100%. CHIE stayed 00. Native pmset getter showed manualChargeLimit=80, drain=1, isEOC=1, noChargeToFull=0 at 80%, then no battery limits after returning to 100%. Charging had not resumed in the return captures. Current values can lag; SMC and I/O Registry observations are sequential, not atomic.

Both CHLT and bfG0 expose size 3, hex_, attributes 0x94. VirtualSMC reverse-engineered definitions assign write permission to bit 0x40, absent here. This suggests readback state, not a demonstrated writable control. Third byte 03 is not decoded.

## Direct binary evidence

Installed executable: /System/Library/CoreServices/powerd.bundle/powerd.

The SOC-limit XPC handler checks the requesting task entitlement com.apple.private.iokit.soc-limit via its audit token and SecTaskCopyValueForEntitlement. Missing entitlement takes the NotPrivileged 0xe00002c1 path. powerd itself has com.apple.private.iokit.soc-limit and com.apple.private.applesmc.user-access in its signed entitlements.

IOKit IOPSLimitBatteryLevel, Register and Cancel are XPC clients of com.apple.iokit.powerdxpc, using chargeSocLimit messages. They are not direct SMC writers.

powerd's policy application at 0x100058388 builds a two-byte CHLS payload and invokes its SMC writer at 0x10005f708. Payload byte 0 is socLimit. Byte 1 = drain | (noChargeToFull ? 2 : 0) | (isEOC ? 4 : 0). The native observed 80% policy therefore corresponds to 50 05. The SMC helper first queries metadata (operation 9), then writes (operation 6), through AppleSMC user client type 1 and external selector 2, 80-byte structures. No direct CHLS write has been attempted by our probe.

The active kernelcache was read from Preboot boot/active (9C7ABC5A...E959715818D8), IMG4 LZFSE payload decompressed to /tmp/tethered-kernelcache.decoded. Symbols identify AppleSMCClient::initWithTask, smcYPCEventCheck, and check_specific_entitlements. Driver init requests com.apple.private.applesmc.user-access and stores a Boolean for unrestricted access; it also supports a per-key collection through that same user-access entitlement (corrected below). smcYPCEventCheck consults the per-key collection and contains a 56-entry wildcard table including bfD*, bfE*, bfF* and other patterns; CHLS is not in that table (see evidence/kernel-key-patterns.txt for the actual table). Exact branch semantics and the precise check responsible for CHLS denial remain under analysis. Do not equate the powerd SOC entitlement gate with the driver's per-key gate without completing that trace.

## Evidence and limitations

Disassembly excerpts are in evidence/. Addresses refer to these specific installed binaries and can change after updates. The synthetic Mach-O slices used only for disassembly contain copied instruction bytes; they are not runnable patched system binaries. Original system files were never modified. Full binary analysis outputs and decoded kernel remain in /tmp and can disappear. Raw capture data has not been published.

Community references: https://github.com/charlie0129/batt/issues/152 ; https://github.com/charlie0129/batt/pull/154 ; https://github.com/actuallymentor/battery/pull/469 ; https://github.com/acidanthera/VirtualSMC/blob/master/VirtualSMCSDK/AppleSmc.h . Treat entitlement/SIP workaround proposals as unverified, not established fixes.

## Next experiment

access-probe.c performs only raw reads, supplying CHLS size 2 and readback keys CHLT/bfG0 size 3 without metadata lookup. Run as root with AC connected to distinguish metadata denial from value-read denial. No write operation is implemented. Build with the same SMCParamStruct include path and IOKit/CoreFoundation linkage as probe.c. A raw write test is still outstanding, not proven denied by read failures. Any future write test must be narrowly scoped with known native payload and an explicit restoration procedure; do not modify Toolkit behavior while investigating.

## Additional raw-read result

The access probe compiled cleanly and ran as UID 501. CHLS raw read with supplied size 2 returned IOKit 0xe00002c1; CHLT, bfG0 and CHIE reads succeeded with zero values. The user subsequently ran this exact probe as root: CHLS again returned 0xe00002c1; all four control/state reads succeeded. See evidence/chls-raw-read-root.txt. This rules out a metadata-only failure and ordinary user privilege as explanations for CHLS read denial. A raw write remains untested.

## Raw-write access probe prepared

chls-write-access.c performs exactly one operation-6 raw write to CHLS with data size 2 and payload 0000. It requires root, an explicit command-line flag, and successful CHLT/bfG0 reads that both equal 000000. This reasserts the inferred native unrestricted payload; it does not request a different percentage. CHLS is unreadable, so its exact original bytes cannot be independently saved. The existing state correlation is an indirect precondition, not direct CHLS readback. Do not change native charging settings concurrently. No entitlement, SIP, signature, or driver changes are performed. Even a successful call would establish only acceptance of this payload, not proof of useful charging control. Execution requires the user's authenticated Terminal; no raw CHLS write has been executed by the agent.

## Root raw-write result

The user executed the bounded probe as root. One CHLS raw operation-6 write, supplied size 2 and payload 0000, returned IOKit 0xe00002c1 (NotPrivileged), with SMC result field 0. The IOKit failure means that zero SMC field is not evidence of success. CHLT and bfG0 read 000000 before and after. See evidence/chls-raw-write-root.txt. Root metadata requests, raw reads, and this raw write are now all experimentally denied. Bypassing metadata lookup does not restore direct CHLS access. The exact driver authorization branch remains unresolved; no SIP or entitlement modifications have been tested.

## Protected-key classification traced

Further static analysis of the active decoded kernel identifies CHLS explicitly in AppleSMCClient::smcYPCEventCheck. At 0xfffffe0009d1ac78 it constructs 0x43484c53 (CHLS), compares it with the requested key, and branches to the protected-key path at 0xfffffe0009d1aca8. CH0J is also explicitly classified. This is separate from the 56-entry wildcard table; earlier absence of CHLS from that table does not mean it is unrestricted. The protected path tests a client authorization Boolean, with a failure route to 0xfffffe0009d1adbc that returns 0xe00002c1 before the provider call at 0xfffffe0009d1ae98. The observed raw-read/write denials are consistent with this route. This is static correlation, not a live kernel execution trace.

Correction: driver init reads com.apple.private.applesmc.user-access using IOUserClient::copyClientEntitlement; it accepts collection/Boolean forms and stores derived client fields. The earlier attribution to com.apple.smc.keys_entitlement was incorrect. Root privilege is checked separately. Register-level provenance of all derived authorization fields and inherited policy is not fully resolved. An explicit arm64e code-signature dump for installed powerd contains applesmc.user-access=true and iokit.soc-limit=true. The formerly noted absence of com.apple.smc.keys_entitlement is irrelevant: it was not the entitlement queried by init. Whether a third-party signature can validly claim these private privileges remains untested.

Read-only IORegistry inspection confirms IOUserClientClass=AppleSMCClient. No top-level entitlement/access-policy table was exposed by the AppleSMC service. No signature modifications, SIP changes, extra hardware writes, or Toolkit runtime changes were performed during this follow-up. Evidence: chls-protected-key-branch.txt and powerd-smc-entitlements.txt.

## Authorization-field provenance resolved (correction)

Direct reconstruction of AppleSMCClient::initWithTask shows:

- At 0xfffffe0009d1b4bc..b4c8, x1 is formed as 0xfffffe000772574a. The bytes at that address are exactly com.apple.private.applesmc.user-access. That is the entitlement passed to the lookup, not com.apple.smc.keys_entitlement.
- The returned object is tested as a collection, which is retained in client field +0xf0 when applicable. Otherwise the Boolean singleton path at b548..b568 compares with the true singleton and sets client byte +0xe9 to 1.
- Root privilege is independently checked against the string root and stored in byte +0xe8 at b3fc.
- smcYPCEventCheck loads +0xe9 at a6bc. CHLS is explicitly classified at ac78..ac84. Its protected path tests authorization at aca8; absence branches to the NotPrivileged path at adbc..add0, before the provider call.
- The installed arm64e powerd signature declares com.apple.private.applesmc.user-access=true. This statically explains its expected general SMC authorization. It separately declares com.apple.private.iokit.soc-limit=true for requests routed through powerd.

Earlier notes incorrectly called com.apple.smc.keys_entitlement a per-key entitlement. That string occurs next to analytics field names key_name and key_op; its mere presence did not support the earlier interpretation. It is not the name used by the init entitlement lookup. See evidence/authorization-field-provenance.txt. This conclusion is static analysis, supported by root probe denial; not a live trace of powerd's client memory. No private entitlement has been added to our code or tested under a third-party signature.

Practical consequence: another ordinary root probe cannot distinguish a new key or payload issue here. The key/payload and expected entitlement source are identified. A subsequent signing experiment would investigate whether macOS accepts that private entitlement for a development binary, not discover another SMC command. No SIP/AMFI changes or such signing experiment have been performed.

## Development-signed private-entitlement launch experiment

A separate copy of the read-only access probe was signed with the available Apple Development identity and an entitlement plist containing only com.apple.private.applesmc.user-access=true. The original probe and application were unchanged. codesign --verify --strict passed on disk and the entitlement dump confirmed the entry. SIP was enabled.

Execution as UID 501 exited 137 before any probe output. AMFI logged AppleMobileFileIntegrityError -413, No matching profile found, with unsatisfiedEntitlements explicitly naming com.apple.private.applesmc.user-access. The kernel logged fatal signature validation failure and AppleSystemPolicy rejected the process. This establishes launch rejection for this development-signed configuration, not an SMC read failure. No root execution, Developer ID variant, ad-hoc variant, provisioning-profile authorization, SIP change, or AMFI change was tested. Signing verification alone is not runtime authorization. See evidence/development-entitlement-launch-denial.txt. The temporary binary is /tmp/tethered-chls-entitled-probe; it is not a usable diagnostic executable in the tested configuration.

## BattOpt lead

Inspected https://github.com/js4jiang5/BattOpt at bac99b19f21e90ed72ae003ea57cc122f8bf89b6 (v1.2.9). Public tree contains docs/assets/installer, no implementation source. README claims macOS 27 support; changelog describes repeated charging fixes. Downloaded the v1.2.9 DMG and legacy CLI for static inspection only. Mounted DMG read-only; did not install or execute any BattOpt code.

Released Resources/battopt ARM64 code at 0x10007a168 onward dynamically loads /System/Library/PrivateFrameworks/PowerUI.framework/PowerUI, resolves PowerUISmartChargeClient, allocates and initializes with initWithClientName: and name ObjCTest, checks isMCLSupported, then invokes setMCLLimit:error: with the requested byte-sized percentage. A separate routine resolves getMCLLimitWithError:. This is a concrete alternative interface to investigate, not a proven bypass or working implementation on our Mac. Its signed ARM64 entitlements contain disable-library-validation and network.client; neither private SMC nor SOC-limit entitlement is present. Other code references PowerUIAgent and policy parsing; their role is not yet decoded. Do not infer full functionality from this one setter.

The legacy battopt1012 executable has no-op set_limit stubs; do not use it as evidence against the modern ARM64 implementation. No claim that native limits below 80 or arbitrary charging pause/resume work is established by the inspected call site. Next: separate read-only PowerUI client support/getter probe, then investigate setter constraints before any bounded write experiment. Evidence: battopt-powerui-path.txt.

## PowerUI service trace

Read-only Objective-C runtime introspection and copied instruction disassembly of the installed PowerUI framework identified the path below; no client setters or service requests were executed.

PowerUISmartChargeClient initWithClientName: creates a connection to com.apple.powerui.smartChargeManager. The server manager's listener:shouldAcceptNewConnection: calls valueForEntitlement: for com.apple.powerui.smartcharging and boolValue. A missing/false entitlement takes a logging path which rejoins acceptance: the listener still exports its interface/object, resumes the connection and returns true. This shows no rejection in this listener method; it is not proof that every service method is unauthenticated. Whether Apple intends this behavior or considers it a vulnerability is unknown.

The server method client:setMCLLimit:withHandler: checks isMCLSupported and tests the requested value by subtracting 80 and comparing unsigned with 20, rejecting values outside 80..100. Accepted values clearMCLOverride and call setMCLLimit:. The server setMCLLimit: persists the value and invokes enableMCL/disableMCL. The policy engine's engageManualChargeLimit obtains _chargingController (PowerUIChargingController) and invokes setChargeLimitTo:forLimitType:, with type 3. That controller's implementation calls IOPSLimitBatteryLevel via the resolved import stub. Thus the native broker chain is PowerUI client -> PowerUIAgent/manager -> PowerUIChargingController -> IOKit SOC-limit XPC client -> powerd -> CHLS. PowerUIAgent has com.apple.private.iokit.soc-limit=true, so it can make the downstream request that our standalone process cannot.

Evidence files: powerui-listener.txt, powerui-mcl-server-setter.txt, powerui-charging-controller.txt, powerui-resolved-call-targets.txt. Runtime addresses are from this OS mapping and are not stable across updates. Copied method windows can include adjacent method instructions; resolved-call lists after a method's return must not be attributed automatically to the named method. The selector resolution and 80..100 check are explicit in the captured ranges.

This explains BattOpt's ordinary native-limit setter without requiring a forged SMC entitlement. It does not explain all BattOpt behavior, particularly advertised below-80 limits; references to PowerUIAgent and archived objects in BattOpt remain untraced. No claim of a known exploit or working sub-80 route is established. Next functional experiment should be a separate support/getter probe, followed by a bounded 80..100 setter test only after recording the user's original native setting.

## Standalone PowerUI functional probe prepared

powerui-probe.m declares the runtime-verified Objective-C signatures (BOOL support/setter, unsigned-char getter/limit). --read requests only support/current limit. --test-80-and-restore requires AC, a successful getter, support, and original limit 81..100. It requests 80, observes for 25 seconds, restores the original value with up to three setter attempts, verifies through the getter, then observes recovery for 30 seconds. SIGINT/TERM/HUP request early restoration; forced termination cannot guarantee cleanup. No concurrent native setting changes should be made during the test. It uses no private entitlement and does not issue direct SMC operations. Results pending.

## PowerUI functional experiment result

The standalone unsigned/ad-hoc-default local executable ran as UID 501 without private entitlements or sudo. Support returned YES; original getter value 100, no error. AC connected, battery 99%, pmset reported finishing charge before the test. Requesting 80 returned YES with no error and pmset -g battlimit immediately showed the native manualChargeLimit=80 policy owned by PowerUIAgent (694) and owner 0. The policy persisted for the 25-second observation, but pmset continued reporting finishing charge throughout; actual charging cessation was NOT established. A separate I/O Registry sample near the end/restore boundary showed IsCharging=true and +664 mA, but its timing does not isolate the 80% phase and must not be treated as a settled under-limit measurement.

Restoring 100 returned YES with no error. Getter verified 100; pmset showed no battery limits set. Thirty seconds of subsequent observations and a fresh separate --read invocation confirmed 100 and no limit. Process completed successfully. This demonstrates client access, accepted native-policy update and restoration, not verified physical charging inhibition or recovery. The high baseline percentage/finishing phase and short observation are limitations. Before integration, repeat with longer timestamped current/IsCharging and CHLT/bfG0 observation at 80%, capture powerd policy logs, and establish an actual power-flow transition. No Toolkit runtime changes were made.


## Longer PowerUI hardware observation

The --long-test-80-and-restore run on 2026-10-21 held 80 for 120 seconds and observed restoration for 60 seconds. Baseline: AC connected, battery 100%, IsCharging=true, +481 mA, CHLT/bfG0=000000. Approximately five seconds after requesting 80, IsCharging became false and current negative (-632 mA, later -1096 mA) while AC remained connected. Native policy held 80 and CHLT/bfG0 settled to 500503. This establishes a charging-to-discharging transition above the requested limit through the ordinary PowerUI client; it does not establish stable holding at 80 or charging up to 80 from below. pmset still called the battery charged, reinforcing the need for current observations.

Restoration to original 100 returned YES and getter verified 100. Native policy cleared, and CHLT/bfG0 returned to 000000 within five seconds. Current remained negative at -924 mA and IsCharging=false through the 60-second restoration observation. Therefore policy/SMC restoration is verified, but positive-current charging recovery is not. The full battery baseline limits interpretation. Process exited 0. Evidence: evidence/powerui-long-test.txt. No Toolkit runtime changes.

## BatFi macOS 27 below-80 claim and static lead

Official support page https://micropixels.software/support/ explicitly states BatFi 4.0+ supports macOS 27 and charge limits below 80. Official changelog https://files.micropixels.software/batfi/BatFi-latest.html repeats this for 4.0.0; 4.0.1 notes acceptance can take up to 45 seconds and fixes status reporting by using actual current direction. These are vendor claims, not our hardware verification.

The website DMG downloaded in this investigation contained old 3.0.1; it was excluded from modern analysis. The stable appcast ZIP contained 4.0.3. Static inspection of its helper shows PowerUISmartChargeClient, setMCLLimit:error:, temporarilyOverrideMCLTargetSoC:error:, and a separate ManualChargeLimitDefaults actor. The actor initializes domain com.apple.smartcharging.topoffprotection, key mclLimitValue, key MCLFeatureState, notification com.apple.smartcharging.defaultschanged, current-user/current-host preference scope, and a powerd charging-plist observation path. At 0x10000ec90 onward the writer bridges the requested integer, calls CFPreferencesSetValue for the limit, sets feature-state integer 1, synchronizes, and posts the Darwin notification. Helper diagnostics explicitly describe applying a refused system limit through charge-limit defaults, waiting for powerd adoption, and retrying missing requests. This is concrete evidence of a preferences-based alternative to the 80..100 setter; the exact backend selected on our hardware and below-80 adoption remain untested. Temporary override is another code path; its presence alone does not prove sub-80 support.

The helper signature inspected contains application identity but no private SMC/SOC-limit entitlement. No BatFi code was installed or executed, no preferences were changed by this investigation, and no below-80 experiment was run. Next diagnostic should separately save original preference presence/types/values, apply one bounded sub-80 preference request, observe adopted native policy plus current/SMC state for sufficient time, then restore exact prior preferences and policy. Evidence: evidence/batfi-4.0.3-static.txt.


## BatFi defaults lead tested: native 75% policy and discharge

On 2026-10-21, batfi-defaults-probe.m saved exact presence/value of mclLimitValue and MCLFeatureState in the current-user/current-host com.apple.smartcharging.topoffprotection domain to a persistent /tmp plist. It wrote integer 75 and feature-state 1, synchronized, posted com.apple.smartcharging.defaultschanged, observed for 90 seconds, restored the original PowerUI limit, restored exact preference presence/values, posted again, and observed for 30 seconds. This is a separate diagnostic executable; no Toolkit runtime integration.

First run as UID 501: both keys originally absent, original getter 100. PowerUIAgent received notification but logged Manual Charge Limit=0; no native limit or SMC change followed. Exact absence and getter100 were restored. This demonstrates why the user-scope write is insufficient on this system.

Second run, explicitly administrator-authorized via macOS authentication, as UID0 to match the privileged helper scope: both keys originally absent; original getter100; AC connected, baseline current0mA, IsCharging=false, battery100%, CHLT/bfG0=000000. powerd adopted native manualChargeLimit=75 with drain=1 and isEOC=1, owners694 and0. CHLT/bfG0 became 4b0503. Current subsequently became negative (-1288mA observed, later -1231mA), while AC remained connected. This verifies below-80 policy adoption, corresponding firmware-state change, and actual discharge above the limit on this Mac/macOS27. It does not yet verify charging from below75 or sustained holding at75.

Cleanup: original100 setter accepted, getter100 verified, both preferences restored to exact original absence, native policy cleared, CHLT/bfG0 returned000000, process exited0. Current stayed negative during the 30-second recovery window, so positive-current recovery is not established. No SIP, signatures, private entitlements, direct SMC writes, installed helper changes, or BatFi execution. Persistent recovery snapshots: /tmp/tethered-charge-defaults-original-62665.plist (user) and /tmp/tethered-charge-defaults-original-63290.plist (root). Full observations and service logs are in evidence/batfi-defaults-user-test.txt, batfi-defaults-root-test.txt, and batfi-defaults-policy-log.txt.


## BattOpt second enforcement path: persisted powerd policy injection

Static follow-up recovered the XOR decoder at 0x1000755dc: each byte is XORed with 0x5a. Decoded constants include ChargeCtrlPolicy, manualChargeLimit, com.apple.powerd.charging, CFPreferencesCopyMultiple, CFPreferencesSetMultiple, CFPreferencesSynchronize, /usr/bin/killall, -HUP, and powerd. No BattOpt executable was run.

At 0x10007717c, BattOpt constructs X_LayoutConfig, assigns owner PID by finding PowerUIAgent, assigns a reason string decoded as manualChargeLimit, a caller-provided integer SOC and Boolean fields, and a new UUID. It archives an array containing the object with NSKeyedArchiver, remapping the serialized class via setClassName:forClass: to ChargeCtrlPolicy. Supporting decoded field fragments include owner, reason, soclimit, drain, terminated, noChargeToFull, isEndOfCharge and token; exact full field mapping should be verified before reproducing. This is persisted policy construction attributed to an existing Apple process, not an authenticated request sent by that process.

The second path at 0x10007a31c calls the ordinary PowerUI setter with100 first, reads persisted state, compares policy fields and, when necessary, mutates/replaces serialized policy data plus bootSessionUUID through dynamically resolved CFPreferencesSetMultiple and CFPreferencesSynchronize. The related read function at0x10007885c uses CFPreferencesCopyMultiple with AnyUser/CurrentHost. The on-disk /Library/Preferences/com.apple.powerd.charging.plist was inspected read-only and contains bootSessionUUID plus policies archived data, consistent with the destination.

After writing, the path calls0x10007c278. Its three argv values statically resolve to /usr/bin/killall, -HUP, powerd, invoked with posix_spawn and waited for with waitpid. It also schedules follow-up blocks for a below100 target and caches requested values; the delay constant is 10000000000ns (10seconds). Guards around writes/reloads use an approximately11-second time comparison. Full follow-up block behavior and exact caller conditions remain unresolved.

This is a concrete active policy-injection/reload mechanism distinct from BatFi root topoff preferences or the native PowerUI setter. It may explain BattOpt's claim about preventing occasional full charge, but prevention of gauging mitigation is NOT yet established. No calibration-state mutation, gauging-file deletion, or disabling of a gauging timer has been identified in this traced path. A live test must distinguish persisted-policy acceptance from sustained enforcement while actual gauging mitigation is active. Do not label it proven calibration prevention. No system preferences, daemons, hardware controls, or Toolkit runtime behavior were modified during this static investigation. Evidence: evidence/battopt-persisted-policy-trace.txt.


## Calibration suspension exception identified: noChargeToFull

Installed powerd at0x1000583d4 loads the mitigation-active Boolean. If active,0x1000583f0 invokes selector noChargeToFull on the selected policy. False takes the suspension log path at0x100058438, then reaches CHLS write with initially zeroed payload. True branches at0x100058400 to0x100058454, reads socLimit/drain/noChargeToFull/isEOC, constructs the requested payload and reaches the same CHLS write. Thus a selected policy with noChargeToFull=true is statically exempt from this calibration suspension branch. This explains why repeating an ordinary policy with noChargeToFull=false would not have the same effect. It does not disable the calibration scheduler or establish every other powerd/firmware path respects this exception.

BattOpt's encodeWithCoder maps X_LayoutConfig.x_p6 to exact key noChargeToFull. At0x100075be8 the coder key is assembled from ARM64 slice bytes0x81f48 (8),0x81f50 (4), literal3636 (2); XOR0x5a yields noChargeToFull. The encoder reads x_p6 at0x100075884 and encodes it at0x1000758b8. Builder0x10007717c receives the third argument inx2, saves tox21, and passes it to setX_p6 at0x100077280. Its caller0x10007a31c saves incomingx2 inx26 and forwards it back tox2 before builder call0x10007b0d8. Inspected direct call sites0x100029bcc,0x100034448,0x10003468c,0x1000349a4,0x100034c40,0x10003da1c,0x100077cd0 all set w2=1. Therefore this is a concrete true flag in BattOpt's constructed policies, not just a string reference or guess about owner identity. Some callers use SOC10 or101; those values are NOT recommendations or tested requests.

Correction/clarification of previous follow-up interpretation: global block0x100099dc8 invokes0x10007c614, which enters a self-test: runs pmset -g battlimit, looks for an owner0 policy, compares expected fields, logs Self Test Passed or failure at attempt5. Global block0x100099de8 invokes0x10007d794, which calls the persisted-policy read function and discards its outputs. Neither decoded block itself is an endless writer loop. Full enclosing daemon/event scheduling remains separate. The previous broad description of these two callbacks as follow-up enforcement was imprecise.

SIGHUP semantics are still unverified: the traced command sends the signal, but no handler was identified in the inspected powerd disassembly. Do not assume an in-process reload rather than termination/relaunch; live PID/launchd observation is required. Persisted-policy loading at0x100057be8 reads AnyUser/CurrentHost charging preferences, checks bootSessionUUID and unarchives policies, establishing a startup/load path but not the signal mechanism.

Next bounded experiment should preserve the exact persisted-policy archive and boot UUID, validate a noChargeToFull=true native policy on this hardware and observe powerd PID/launchd behavior when signaled, then restore original state. Actual calibration override suppression must be verified separately when mitigation is active. No live policies, daemons, gauging records, or Toolkit runtime behavior changed during this trace. Evidence: evidence/battopt-no-charge-to-full-branch.txt.


## macOS 27 backend integrated and tested incrementally

BTNativeCharging27 is now connected to Toolkit startup, charge enable/disable, configured hysteresis, charge-to-full, pause/termination/update handling and diagnostics. Its OS gate is exactly major27. Legacy charge keys are not required on this path; legacy behavior remains for other OS majors. The policy is attributed to our own live daemon PID, not PowerUIAgent. noChargeToFull is restricted to configured/effective sub80 targets; drain=false preserves AC operation above the threshold instead of requesting intentional discharge.

Testing found and fixed two material issues before push: notifying ordinary topoff writes raced with protected-policy injection; and preserving a session-created ordinary manual policy made restoration return success while a75 limit remained. The final writer first releases the ordinary policy via the synchronous PowerUI client, replaces native manual/Toolkit policy records, and preserves unrelated owners. Final cleanup restores original manual records rather than retaining the session-created manual record. The stale experimental75 policy was explicitly removed after verifying it was the only persisted policy, returning the baseline to no limits before rerunning. Earlier test success booleans must not be read as proof of complete restoration.

Final transition run PID73851 at2026-10-22 01:38:49..01:39:54UTC adopted75/noChargeToFull1,80/noChargeToFull0,100/no native limit,75/noChargeToFull1. After restoration, an independent pmset read showed no limits. SIGHUP changed the powerd PID, confirming restart on this build. Earlier follow-up wording suggesting an in-process reload is superseded.

Final hold run PID74347 at01:41:00..01:43:07UTC: AC connected throughout, target75, noChargeToFull1, drain0, CHLT4b0601. Current remained+1824mA with charging=true until the observation at01:42:04, then0mA/charging=false for the rest of the hold. The response took about64seconds, so short accepted-policy tests cannot prove inhibition. Cleanup was followed by independent reads: no battery limits, CHLT/bfG0000000. At99% battery current remained0 afterward; positive charging recovery is not established. This did not occur during gauging mitigation.

The new daemon keeps bounded rotating journals and selected system policy/calibration events with a15-second sample timer and bounded drift retries. These run only once the new Toolkit code is rebuilt into the host application/helper and launched. The installed Tethered helper has not been replaced in this task. No multi-day or active-calibration claim. Architecture, recovery and test commands: MACOS27-SUPPORT.md. Evidence: native27-first-policy-test.txt, native27-transition-race.txt, native27-transitions-fixed.txt, native27-transitions-journal.jsonl, native27-hold-test.txt, native27-hold-journal.jsonl.


## Fan-control hardware verification on macOS 27

2026-10-21, same target Mac15,6: compiled the actual SMCComm, BTError and BTFanControl sources into a standalone probe. No charging backend or charging-policy writes were invoked. Baseline and root baseline both exposed two fans, min2317/max6800RPM, measured0RPM, target0, mode3. Lowercase F0md/F1md were unavailable; the production resolver selected uppercase F0Md/F1Md. A first preflight aborted before writes because the test snapshot used the lowercase spelling; the production resolver was not defective.

Root execution of setFanControlLease(percent:65,durationSeconds:30) returned success0. Both targets became5231RPM, mode1; actual measured speeds were approximately5232RPM within the first5-second observation and remained near target. At30seconds, lease expiry changed modes to0. By35seconds firmware had settled to mode3,target0,current0 on both fans. This establishes real fan speed changes and timed release, not merely accepted writes. Probe also restored exact original mode/target/Ftst bytes where present, verified through raw readback. Independent subsequent reads showed the original stopped state. Evidence: evidence/fan-control-macos27.txt.

A subsequent explicit reset returned fanModeWriteFailed9 trying to write0 over the already-settled mode3,target0 state. Fixed only for major27: both setFanMode(auto) and resetFanControlNow recognize mode3 plus readable zero target as already reset. Missing/nonzero targets do not take this shortcut; manual mode1 retains the existing reset write. The narrow classification is supported by the observed lease-expiry transition, not an authoritative universal SMC mode map. Standalone reset-check of updated code returned success0 and preserved both original mode3/target0/current0 states. Installed helper/XPC/menu behavior still needs testing after rebuilding; live test exercised the actual Toolkit implementation directly.


## Power-mode control verified on macOS 27

Compiled the actual BTPowerMode.swift and BTPowerModeTypes.swift into a standalone diagnostic. pmset -g cap advertises lowpowermode on this Mac; both original battery and charger values were0 (Automatic). Root test verified six transitions using actual OS readback: battery1 leaves charger0; charger1 yields1/1; battery0 leaves charger1; charger0 restores0/0; all1 yields1/1; all0 yields0/0. Invalid mode3 and UPS scope returned false. Final restoration writes and independent OS reads confirmed original0/0. Evidence: evidence/power-mode-macos27.txt. No performance/energy benchmark was performed.

The existing checkAndSetHighPowerMode() routine returned false on this target, consistent with capability output lacking highpowermode/powermode. After its bounded probe and restoration both settings remained0. Evidence: evidence/power-mode-high-check-macos27.txt. This is a target-hardware result, not a statement that High Power is unavailable on every macOS27 Mac.

Source tracing confirms existing BTActions.setPowerMode/setPowerModes reach BTDaemonComm authorization/support checks then this same implementation. The host app's applyPowerModeTargets also gates local licensing, and systemPowerModeTargets applies the desired mode to the currently active power source while setting the inactive source to Automatic. The direct test isolates Toolkit/OS functionality; menu shortcuts, automatic rules, licensing and actual rebuilt helper XPC behavior are not thereby runtime-verified. Current source required no power-mode implementation change. Unrelated dirty Tethered work was preserved.
