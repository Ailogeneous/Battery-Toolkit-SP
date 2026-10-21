import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import subprocess

HERE = Path(__file__).resolve().parent

def command(args):
    result = subprocess.run(args, capture_output=True)
    return {"returncode": result.returncode, "stdout": result.stdout.decode(errors="replace"), "stderr": result.stderr.decode(errors="replace")}

def snapshot(label, limit):
    start = datetime.datetime.now(datetime.timezone.utc).isoformat()
    probe = command([str(HERE / "probe")])
    records = [json.loads(line) for line in probe["stdout"].splitlines()]
    telemetry = {}
    for name, args in {
        "battery": ["/usr/bin/pmset", "-g", "batt"],
        "native_limit": ["/usr/bin/pmset", "-g", "battlimit"],
        "os": ["/usr/bin/sw_vers"],
        "model": ["/usr/sbin/sysctl", "hw.model"],
        "firmware": ["/usr/sbin/ioreg", "-p", "IODeviceTree", "-n", "chosen", "-r", "-l", "-d", "1"],
    }.items():
        telemetry[name] = command(args)
    battery = subprocess.run(["/usr/sbin/ioreg", "-a", "-r", "-c", "AppleSmartBattery"], capture_output=True)
    selected = {}
    if battery.returncode == 0:
        entries = plistlib.loads(battery.stdout)
        if entries:
            keys = ["ExternalConnected", "IsCharging", "CurrentCapacity", "Amperage", "InstantAmperage", "Voltage", "Temperature", "FullyCharged"]
            selected = {k: entries[0][k] for k in keys if k in entries[0]}
            for k in ["Amperage", "InstantAmperage"]:
                if selected.get(k, 0) >= 2**63:
                    selected[k] -= 2**64
    return {"started_utc": start, "finished_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(), "label": label, "declared_native_limit": limit, "uid": os.geteuid(), "probe_returncode": probe["returncode"], "probe_stderr": probe["stderr"], "records": records, "telemetry": telemetry, "battery": selected}

def compare(paths):
    captures = [json.loads(Path(p).read_text()) for p in paths]
    maps = [{(r["kind"], r["key"]): {k:v for k,v in r.items() if k != "index"} for r in c["records"] if "key" in r} for c in captures]
    print("Labels:", " | ".join(c["label"] for c in captures))
    print("UIDs:", [c["uid"] for c in captures])
    print("Probe return codes:", [c["probe_returncode"] for c in captures])
    print("Battery observations:", json.dumps([c["battery"] for c in captures]))
    for identity in sorted(set().union(*(m.keys() for m in maps))):
        values = [m.get(identity) for m in maps]
        if any(v != values[0] for v in values[1:]):
            name = identity[1].to_bytes(4, "big").decode("ascii", errors="backslashreplace")
            print(json.dumps({"key": name, "kind": identity[0], "observations": values}))

parser = argparse.ArgumentParser()
sub = parser.add_subparsers(dest="action", required=True)
build = sub.add_parser("build")
cap = sub.add_parser("capture")
cap.add_argument("label")
cap.add_argument("--limit", type=int, choices=[80, 100], required=True)
cap.add_argument("--output", required=True)
diff = sub.add_parser("compare")
diff.add_argument("captures", nargs="+")
args = parser.parse_args()
if args.action == "build":
    subprocess.run(["xcrun", "clang", "-Wall", "-Wextra", "-I", str(HERE.parent.parent / "Sources/Modules/SMCParamStruct"), str(HERE / "probe.c"), "-framework", "IOKit", "-framework", "CoreFoundation", "-o", str(HERE / "probe")], check=True)
elif args.action == "capture":
    if os.geteuid() != 0:
        parser.error("Capture requires sudo so all captures use the same root access context")
    data = snapshot(args.label, args.limit)
    with open(args.output, "x") as f:
        json.dump(data, f, indent=2)
    print(args.output)
    if data["probe_returncode"] != 0:
        raise SystemExit("Incomplete probe; inspect the saved return code and errors")
else:
    compare(args.captures)
