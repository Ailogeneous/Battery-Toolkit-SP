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
