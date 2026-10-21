# Native Charge Limit comparison probe

Standalone read-only diagnostics. No SMC write operation is implemented. Toolkit runtime sources are unchanged. Python 3 and Xcode command-line tools are required.

The probe enumerates the complete advertised directory and samples metadata and values for CH*, AC*, B*, and bf* candidates. Values larger than 32 bytes are skipped. Metadata and read denials are retained. Captures are sequential observations, not atomic snapshots. Directory membership and changing values do not establish charging-control semantics.

## Build

From this directory:

```sh
python3 capture.py build
mkdir -p captures
```

## Experiment

Keep AC physically connected and keep Optimized Battery Charging unchanged throughout. Choose a battery level above 80% and below 100% so the two native limits can produce distinguishable behavior. Record whether any other charging controller is active; do not mix captures across different controller configurations.

Set the native macOS Charge Limit manually to 100%. Wait for its power state to settle, then capture twice without changing anything to measure ordinary telemetry variation:

```sh
sudo python3 capture.py capture 100-baseline --limit 100 --output captures/01-100.json
sudo python3 capture.py capture 100-repeat --limit 100 --output captures/02-100.json
```

Change only the native limit to 80%. Capture immediately, then once actual charging has settled:

```sh
sudo python3 capture.py capture 80-immediate --limit 80 --output captures/03-80.json
sudo python3 capture.py capture 80-settled --limit 80 --output captures/04-80.json
```

Return the native limit to 100% and repeat:

```sh
sudo python3 capture.py capture 100-return --limit 100 --output captures/05-100.json
sudo python3 capture.py capture 100-settled --limit 100 --output captures/06-100.json
python3 capture.py compare captures/01-100.json captures/02-100.json captures/03-80.json captures/04-80.json captures/05-100.json captures/06-100.json
```

Repeat the cycle if candidates emerge. Restore your original native limit afterward. The --limit argument is a user-supplied experiment label, not an independently verified setting. Captures also retain the pmset limit getter output, battery state, signed current readings, OS/model/firmware context, timestamps, UID and probe errors. The comparison reports all changed candidate observations; it does not rank them or treat correlation as proof. Denied or absent keys cannot be ruled out as controls from value comparisons.

Output files must not already exist. Captures can contain hardware identifiers in firmware registry context; keep them local. No automatic sampling, setting changes, writes, or Toolkit integration is performed.
