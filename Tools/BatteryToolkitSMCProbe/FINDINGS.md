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

The active kernelcache was read from Preboot boot/active (9C7ABC5A...E959715818D8), IMG4 LZFSE payload decompressed to /tmp/tethered-kernelcache.decoded. Symbols identify AppleSMCClient::initWithTask, smcYPCEventCheck, and check_specific_entitlements. Driver init requests com.apple.private.applesmc.user-access and stores a Boolean for unrestricted access; it also loads com.apple.smc.keys_entitlement as per-key authorization. smcYPCEventCheck consults the per-key collection and contains a 56-entry wildcard table including bfD*, bfE*, bfF* and other patterns; CHLS is not in that table (see evidence/kernel-key-patterns.txt for the actual table). Exact branch semantics and the precise check responsible for CHLS denial remain under analysis. Do not equate the powerd SOC entitlement gate with the driver's per-key gate without completing that trace.

## Evidence and limitations

Disassembly excerpts are in evidence/. Addresses refer to these specific installed binaries and can change after updates. The synthetic Mach-O slices used only for disassembly contain copied instruction bytes; they are not runnable patched system binaries. Original system files were never modified. Full binary analysis outputs and decoded kernel remain in /tmp and can disappear. Raw capture data has not been published.

Community references: https://github.com/charlie0129/batt/issues/152 ; https://github.com/charlie0129/batt/pull/154 ; https://github.com/actuallymentor/battery/pull/469 ; https://github.com/acidanthera/VirtualSMC/blob/master/VirtualSMCSDK/AppleSmc.h . Treat entitlement/SIP workaround proposals as unverified, not established fixes.

## Next experiment

access-probe.c performs only raw reads, supplying CHLS size 2 and readback keys CHLT/bfG0 size 3 without metadata lookup. Run as root with AC connected to distinguish metadata denial from value-read denial. No write operation is implemented. Build with the same SMCParamStruct include path and IOKit/CoreFoundation linkage as probe.c. A raw write test is still outstanding, not proven denied by read failures. Any future write test must be narrowly scoped with known native payload and an explicit restoration procedure; do not modify Toolkit behavior while investigating.

## Additional raw-read result

The access probe compiled cleanly and ran as UID 501. CHLS raw read with supplied size 2 returned IOKit 0xe00002c1; CHLT, bfG0 and CHIE reads succeeded with zero values. The user subsequently ran this exact probe as root: CHLS again returned 0xe00002c1; all four control/state reads succeeded. See evidence/chls-raw-read-root.txt. This rules out a metadata-only failure and ordinary user privilege as explanations for CHLS read denial. A raw write remains untested.
