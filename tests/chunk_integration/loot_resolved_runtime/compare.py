#!/usr/bin/env python3
"""Compare actual successful-loot receipts; never treat a build/headless pass as game parity."""
import argparse
import difflib
import json
import math
import struct
import re
from pathlib import Path

EXPECTED_CASES = (
    "direct-real-items", "bag-real-items", "accept-mutates-next-name", "accept-mutates-tags-options",
    "native-nested-fill-reentrant", "native-denied", "native-full", "native-accept-error",
)


RNG_SCOPE = "owner-thread-private-native-randstandard-v1"
RNG_ACTIVATION = dict(rng_scope=RNG_SCOPE, rng_audit_definitions="1",
                      rng_abstract_definitions="1", rng_standard_definitions="1", rng_interface_definitions="1")


def rng(cache, pid):
    value = values(cache / ("loot-resolved-runtime-rng-" + str(pid) + ".txt"))
    required = dict(rng_scope=RNG_SCOPE, rng_scope_complete="true", reason="null",
                    owner_bypass_rejections="0", owner_unseeded_float_bool_rejections="0", foreign_private_receiver_rejections="0",
                    shared_singleton_writes="0", foreign_counts_scope="nonblocking-entry-snapshot")
    if any(value.get(k) != v for k, v in required.items()):
        raise ValueError("RNG scope failed, poisoned or unqualified")
    for key in ("owner_wrapper_selections", "owner_receiver_entries", "foreign_wrapper_selections", "foreign_receiver_entries"):
        if not re.fullmatch(r"[0-9]+", value.get(key, "")) or (key.startswith("owner_") and int(value[key]) == 0):
            raise ValueError("Missing/invalid RNG scope observations: " + key)
    if int(value["foreign_wrapper_selections"]) + int(value["foreign_receiver_entries"]) > 0:
        if (any(value.get(k, "none") == "none" for k in ("foreign_first_thread", "foreign_first_caller", "foreign_first_entry"))
                or not re.fullmatch(r"[1-9][0-9]*", value.get("foreign_first_thread_id", ""))):
            raise ValueError("Foreign RNG entry observation lacks provenance")
    return value


def _number_bits(value, size):
    if not re.fullmatch(r"[0-9a-f]{1," + str(size * 2) + "}", value):
        raise ValueError("Malformed clock/age bits")
    number = struct.unpack(">d" if size == 8 else ">f", int(value, 16).to_bytes(size, "big"))[0]
    if not math.isfinite(number) or number < 0:
        raise ValueError("Nonfinite/negative clock or food age")
    return number


def _float(value):
    try:
        return struct.unpack(">f", struct.pack(">f", value))[0]
    except OverflowError as error:
        raise ValueError("Food clock exceeds finite float32 range") from error


def _float_bits(value):
    try:
        return format(struct.unpack(">I", struct.pack(">f", value))[0], "x")
    except OverflowError as error:
        raise ValueError("Food age exceeds finite float32 range") from error


def clock_rows(lines):
    """Validate exact native nonchilled Apple aging before normalizing its clock inputs.

    All raw rows remain in the source TSV and comparison report. No age tolerance,
    world-clock mutation or normalization of unrelated item fields is permitted.
    """
    clocks, apples = {}, {}
    keys = {"fulltype", "id", "days_before", "days_after", "hours_before", "hours_after",
            "time_since_apo_before", "time_since_apo_after", "rot_option_before", "rot_option_after",
            "rot_factor", "expected_age", "actual_age", "is_fridge", "is_freezer"}
    for index, line in enumerate(lines[1:], 1):
        fields = line.rstrip("\n").split("\t")
        if len(fields) != 3:
            raise ValueError("Malformed semantic row")
        kind, case, detail = fields
        if kind == "CLOCK":
            tokens = detail.split(":"); position = tokens[0]
            pairs = [token.split("=", 1) for token in tokens[1:]]
            if any(len(pair) != 2 for pair in pairs):
                raise ValueError("Malformed food clock proof")
            proof = dict(pairs)
            if (len(proof) != len(pairs) or set(proof) != keys or case != "direct-real-items"
                    or not re.fullmatch(r"direct/[0-9]+", position) or position in clocks
                    or proof["fulltype"] != "Base.Apple" or proof["is_fridge"] != "false" or proof["is_freezer"] != "false"):
                raise ValueError("Unsupported/duplicate food clock proof")
            for stem in ("days", "hours", "time_since_apo", "rot_option"):
                if proof[stem + "_before"] != proof[stem + "_after"]:
                    raise ValueError("Food clock/options changed inside synchronous case")
            for key in ("time_since_apo_before", "rot_option_before"):
                if not re.fullmatch(r"[1-9][0-9]*", proof[key]) or int(proof[key]) > 2147483647:
                    raise ValueError("Invalid food clock sandbox option")
            days = _number_bits(proof["days_before"], 8)
            hours = _number_bits(proof["hours_before"], 8)
            expected_days = hours / 24.0 + (int(proof["time_since_apo_before"]) - 1) * 30
            if struct.pack(">d", days) != struct.pack(">d", expected_days):
                raise ValueError("World age days/hours/apocalypse inputs disagree")
            option = int(proof["rot_option_before"])
            if option not in range(1, 6):
                raise ValueError("Unsupported food rot option")
            factor = _number_bits(proof["rot_factor"], 4)
            if proof["rot_factor"] != _float_bits({1: 1.7, 2: 1.4, 3: 1.0, 4: 0.7, 5: 0.4}[option]):
                raise ValueError("Native food rot factor/option mismatch")
            expected = _float_bits(_float(days) * factor)
            if proof["expected_age"] != expected or proof["actual_age"] != expected:
                raise ValueError("Food age differs from exact native float32 oracle")
            clocks[position] = (index, proof)
        elif kind == "ITEM":
            parts = detail.split(":")
            if len(parts) >= 3 and parts[1] == "zombie.inventory.types.Food":
                if case != "direct-real-items" or parts[2] != "Base.Apple" or parts[0] in apples:
                    raise ValueError("Food snapshot outside reviewed clock scope")
                pairs = [token.split("=", 1) for token in parts[3:] if "=" in token]
                props = dict(pairs)
                if len(props) != len(pairs) or "age" not in props or "id" not in props:
                    raise ValueError("Malformed food snapshot")
                apples[parts[0]] = (index, props)
    if not apples or clocks.keys() != apples.keys():
        raise ValueError("Food clock proof cardinality differs from actual Apple snapshots")
    normalized = list(lines)
    proofs = []
    for position, (index, proof) in clocks.items():
        item_index, props = apples[position]
        if props["age"] != proof["actual_age"] or props["id"] != proof["id"]:
            raise ValueError("Food clock proof does not bind actual item identity/age")
        normalized[item_index] = normalized[item_index].replace(":age=" + props["age"] + ":", ":age=clock-derived:", 1)
        stable = dict(proof)
        for key in ("days_before", "days_after", "hours_before", "hours_after", "expected_age", "actual_age"):
            stable[key] = "clock-derived"
        normalized[index] = "CLOCK\tdirect-real-items\t" + position + ":" + ":".join(k + "=" + v for k, v in stable.items()) + "\n"
        proofs.append(dict(position=position, **proof))
    return normalized, proofs


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
    profile = status.get("resource_profile")
    manifest = status.get("optimizer_manifest_sha256", "")
    if profile not in ("native", "optimized-client", "native-host") or status.get("runtime_profile_checked") != "true":
        raise ValueError("Missing runtime resource/profile qualification")
    if (profile == "native" and manifest != "none") or (profile != "native" and not re.fullmatch(r"[0-9a-f]{64}",manifest)):
        raise ValueError("Runtime optimizer manifest proof differs")
    pid = status.get("pid", "")
    if not pid.isdecimal():
        raise ValueError("Missing authority PID")
    activation = values(cache / ("loot-resolved-runtime-activation-" + pid + ".txt"))
    if any(activation.get(key) != value for key, value in {
        "state": "active", "mode": mode, "pid": pid, "definitions": "1", "rng_audit_definitions": "1",
        "resource_profile": profile, "optimizer_manifest_sha256": manifest, "runtime_profile_checked": "true", **RNG_ACTIVATION,
    }.items()):
        raise ValueError("Authority activation mismatch: " + repr(activation))
    if any(not re.fullmatch(r"[0-9a-f]{64}", activation.get(key, "")) for key in ("input", "output")):
        raise ValueError("Missing definition byte proof")
    if (activation["input"] == activation["output"]) != (mode == "control"):
        raise ValueError("Native/control or candidate output-byte proof invalid")
    if status.get("rng_scope") != RNG_SCOPE or status.get("rng_scope_complete") != "true":
        raise ValueError("Bank RNG scope was not closed successfully")
    rng(cache, pid)
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
    clock_rows(lines)
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
    if control["resource_profile"] != candidate["resource_profile"] or control["optimizer_manifest_sha256"] != candidate["optimizer_manifest_sha256"]:
        raise ValueError("Different runtime resource/profile inputs")
    normalized_a, clocks_a = clock_rows(a)
    normalized_b, clocks_b = clock_rows(b)
    equal = normalized_a == normalized_b
    report = {"format": 2, "status": "equal" if equal else "different", "cases": len(EXPECTED_CASES),
              "control_pid": control["pid"], "candidate_pid": candidate["pid"], "native_input": stock["input"],
              "candidate_output": patched["output"], "rows": {"control": len(a)-1, "candidate":len(b)-1},
              "resource_profile":control["resource_profile"], "optimizer_manifest_sha256":control["optimizer_manifest_sha256"],
              "limits": ["live-script-reload", "module-item-replacement", "source-square-regional-multiplier",
                         "arbitrary concurrent script mutation", "later Java transformations", "full runtime-log audit required"],
              "raw_equal": a == b, "clock_proofs": {"control": clocks_a, "candidate": clocks_b},
              "rng_scope": {"control": rng(args.control_cache, control["pid"]), "candidate": rng(args.candidate_cache, candidate["pid"])},
              "raw_diff": list(difflib.unified_diff(a,b,fromfile="control-raw",tofile="candidate-raw")),
              "diff": list(difflib.unified_diff(normalized_a,normalized_b,fromfile="control-validated",tofile="candidate-validated"))}
    args.output.write_text(json.dumps(report,indent=2) + "\n")
    if not equal:
        print("".join(report["diff"])[:16000])
        raise SystemExit("Actual native loot receipts differ; comparison retained")
    print("LOOT_RESOLVED_RUNTIME_PARITY_PASS cases=8 rows=" + str(len(a)-1))
    print("Native fixture parity only; inspect full logs and the declared uncovered gates")


if __name__ == "__main__":
    main()
