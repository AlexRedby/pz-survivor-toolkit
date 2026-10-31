#!/usr/bin/env python3
"""Compare actual successful-loot receipts; never treat a build/headless pass as game parity."""
import argparse
import difflib
import json
from pathlib import Path

EXPECTED_CASES = (
    "direct-real-items", "bag-real-items", "accept-mutates-next-name", "accept-mutates-tags-options",
    "native-nested-fill-reentrant", "native-denied", "native-full", "native-accept-error",
)


def values(path):
    result = {}
    for line in path.read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            if key != "observed":
                if key in result:
                    raise ValueError("Duplicate receipt key: " + key)
                result[key] = value
    return result


def read(cache, mode):
    status = values(cache / "loot-resolved-runtime-status.txt")
    if status.get("status") != "complete" or status.get("mode") != mode or status.get("cases") != str(len(EXPECTED_CASES)) or status.get("reason"):
        raise ValueError("Unqualified bank status: " + repr(status))
    pid = status.get("pid", "")
    if not pid.isdecimal():
        raise ValueError("Missing authority PID")
    activation = values(cache / ("loot-resolved-runtime-activation-" + pid + ".txt"))
    if any(activation.get(key) != value for key, value in {
        "state": "active", "mode": mode, "pid": pid, "definitions": "1", "rng_audit_definitions": "1",
    }.items()):
        raise ValueError("Authority activation mismatch: " + repr(activation))
    if not activation.get("input") or not activation.get("output"):
        raise ValueError("Missing definition byte proof")
    if (activation["input"] == activation["output"]) != (mode == "control"):
        raise ValueError("Native/control or candidate output-byte proof invalid")
    lines = (cache / "loot-resolved-runtime.tsv").read_text().splitlines(keepends=True)
    if not lines or lines[0] != "kind\tcase\tdetail\n":
        raise ValueError("Receipt header")
    begin = tuple(line.split("\t")[1] for line in lines if line.startswith("BEGIN\t"))
    end = tuple(line.split("\t")[1] for line in lines if line.startswith("END\t"))
    cleanup = tuple(line.split("\t")[1] for line in lines if line.startswith("CLEANUP\t"))
    if begin != EXPECTED_CASES or end != EXPECTED_CASES or cleanup != EXPECTED_CASES:
        raise ValueError("Incomplete/duplicate/out-of-order case rows")
    if not any(line.startswith("ITEM\tdirect-real-items\t") and ":initialized=true" in line for line in lines):
        raise ValueError("No actual initialized direct items")
    if not any(line.startswith("ITEM\tbag-real-items\t") and ":initialized=true" in line for line in lines):
        raise ValueError("No actual initialized bag items")
    if not any(line.startswith("FILL\tnative-nested-fill-reentrant\t") for line in lines):
        raise ValueError("No actual native OnFillContainer callback")
    return status, activation, lines


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--control-cache", type=Path, required=True)
    parser.add_argument("--candidate-cache", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="New comparison receipt JSON")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Comparison output must be new")
    control, stock, a = read(args.control_cache, "control")
    candidate, patched, b = read(args.candidate_cache, "candidate")
    if stock["input"] != patched["input"]:
        raise ValueError("Different native inputs")
    equal = a == b
    report = {"format": 1, "status": "equal" if equal else "different", "cases": len(EXPECTED_CASES),
              "control_pid": control["pid"], "candidate_pid": candidate["pid"], "native_input": stock["input"],
              "candidate_output": patched["output"], "rows": {"control": len(a)-1, "candidate":len(b)-1},
              "limits": ["live-script-reload", "module-item-replacement", "source-square-regional-multiplier",
                         "arbitrary concurrent script mutation", "later Java transformations", "full runtime-log audit required"],
              "diff": list(difflib.unified_diff(a,b,fromfile="control",tofile="candidate"))}
    args.output.write_text(json.dumps(report,indent=2) + "\n")
    if not equal:
        print("".join(report["diff"])[:16000])
        raise SystemExit("Actual native loot receipts differ; comparison retained")
    print("LOOT_RESOLVED_RUNTIME_PARITY_PASS cases=8 rows=" + str(len(a)-1))
    print("Native fixture parity only; inspect full logs and the declared uncovered gates")


if __name__ == "__main__":
    main()
