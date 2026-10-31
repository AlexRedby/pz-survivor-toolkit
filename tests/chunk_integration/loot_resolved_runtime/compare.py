#!/usr/bin/env python3
"""Compare actual successful-loot receipts; never treat a build/headless pass as game parity."""
import argparse
import difflib
import json
import hashlib
import math
import struct
import re
from pathlib import Path

EXPECTED_CASES = (
    "direct-real-items", "bag-real-items", "accept-mutates-next-name", "accept-mutates-tags-options",
    "native-nested-fill-reentrant", "native-denied", "native-full", "native-accept-error",
)


BANK_CASES = {"base": EXPECTED_CASES, "semantics": EXPECTED_CASES + (
    "finite-source-direct", "finite-source-bag", "callback-module-replacement-direct", "callback-module-replacement-bag"),
    "reload": ("terminal-live-item-reload",)}


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


def clock_rows(lines, required=True):
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
    if (required and not apples) or (not required and apples) or clocks.keys() != apples.keys():
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


def coverage(bank):
    return dict(source_square="finite-plumbing" if bank == "semantics" else "uncovered",
                regional_multiplier="uncovered-no-differential",
                module_item_replacement="complete" if bank == "semantics" else "uncovered",
                live_script_reload="terminal-complete" if bank == "reload" else "uncovered",
                reload_attempted=str(bank == "reload").lower(), reload_disk_restored=str(bank == "reload").lower(),
                reload_runtime_restored="false")


def limits(bank):
    result = ["source-square differential regional multiplier remains uncovered (native no-Region fallback is General)",
              "arbitrary concurrent script mutation", "later Java transformations", "full runtime-log audit required"]
    if bank != "semantics": result += ["finite nonnull source-square plumbing", "callback-time module-item replacement"]
    if bank != "reload": result += ["actual live Item reload"]
    else: result += ["terminal disposable runtime: disk restored, native reloaded registry not rolled back",
                     "pre-reload zero-chance trials prove misses and script fields, not pre-reload factory creation"]
    return result


def _props(detail):
    pairs = [token.split("=", 1) for token in detail.split(":")]
    if any(len(pair) != 2 for pair in pairs) or len(dict(pairs)) != len(pairs):
        raise ValueError("Malformed/duplicate semantic proof field")
    return dict(pairs)


def semantic_rows(lines, bank):
    """Admit only the declared native witnesses; retain every raw value for exact parity."""
    if bank not in BANK_CASES: raise ValueError("Unknown semantic bank")
    rows = [line.rstrip("\n").split("\t") for line in lines[1:]]
    if any(len(row) != 3 for row in rows): raise ValueError("Malformed semantic row")
    names = BANK_CASES[bank]
    allowed = {"SETTINGS", "SOURCE", "REBIND", "RESTORE", "REPLACEMENT", "RELOAD_INPUT", "RELOAD", "RELOAD_ITEM", "RELOAD_ROLL", "RELOAD_RESTORE", "DISPOSE"}
    extra = [(kind, case, detail) for kind, case, detail in rows if kind in allowed]
    expected_extra_cases = set(names[8:] if bank == "semantics" else names if bank == "reload" else ())
    if any(case not in expected_extra_cases for _, case, _ in extra):
        raise ValueError("Semantic witness outside selected bank/case")
    proofs = {}
    for case in expected_extra_cases:
        selected = [(kind, detail) for kind, name, detail in rows if name == case]
        def one(kind, expected=None):
            matches = [_props(detail) for k, detail in selected if k == kind]
            if len(matches) != 1: raise ValueError("Missing/duplicate " + kind + " witness: " + case)
            value = matches[0]
            if expected is not None and value != expected: raise ValueError("Invalid " + kind + " witness: " + case)
            return value
        one("SETTINGS", dict(rolls="1.0", memento="0.0", medical="1.0", scope="initial-owned-test-only"))
        if case.startswith("finite-source-"):
            path = case.removeprefix("finite-source-")
            source = [_props(d) for k,d in selected if k == "SOURCE"]
            expected_trials = ["null-hit", "null-miss", "source-hit", "source-miss"]
            if [v.get("trial") for v in source] != expected_trials:
                raise ValueError("Source trial cardinality/order differs")
            for value in source:
                trial = value["trial"]; hit = trial.endswith("-hit"); sourced = trial.startswith("source-")
                expected = {"path", "trial", "source", "region", "global_factor", "square_factor", "draw", "picker_chance", "native_chance", "expected", "actual", "next_rng", "regional_differential"}
                if (set(value) != expected or value["path"] != path or value["source"] != str(sourced).lower()
                        or value["regional_differential"] != "false" or value["expected"] != str(int(hit))
                        or value["actual"] != value["expected"] or not value["region"]
                        or (not sourced and value["region"] != "none")):
                    raise ValueError("Source identity/observed outcome differs")
                draw = int(value["draw"]); chance = _number_bits(value["native_chance"],4)
                if not 1 < draw < 9998 or not 0 < chance < 10000 or (draw < chance) != hit:
                    raise ValueError("Source finite native draw boundary differs")
                if (_number_bits(value["picker_chance"],4) <= 0 or _number_bits(value["global_factor"],4) <= 0
                        or value["square_factor"] != value["global_factor"] or not 0 <= int(value["next_rng"]) < 1_000_000):
                    raise ValueError("Source finite factor/RNG scope differs")
                containers = [d for k,d in selected if k == "CONTAINER" and d.startswith(trial+":")]
                items = [d for k,d in selected if k == "ITEM" and d.startswith(trial+"/")]
                if len(containers) != 1 or int(_props(containers[0].split(":",1)[1])["count"]) != int(hit) or len(items) != int(hit):
                    raise ValueError("Source witness not bound to actual output snapshot")
                if items and (":Base.PZLootRuntimeSource:" not in items[0] or ":initialized=true" not in items[0]):
                    raise ValueError("Source witness wrong native item")
            if sum(k == "DISPOSE" for k,_ in selected) != 4: raise ValueError("Source trial disposal missing")
            if any(k in allowed-{"SETTINGS","SOURCE","DISPOSE"} for k,_ in selected): raise ValueError("Foreign source witness")
            proofs[case] = source
        elif case.startswith("callback-module-replacement-"):
            path = case.removeprefix("callback-module-replacement-")
            rebind = one("REBIND")
            stable = dict(callback="true", qualified_new="true", unqualified_new="true", old_distinct="true",
                          old_chance="0", draw_min="0", draw_max_exclusive="10000")
            if (set(rebind) != set(stable)|{"new_chance","picker_chance"} or any(rebind.get(k)!=v for k,v in stable.items())
                    or _number_bits(rebind["new_chance"],4) < 10000 or _number_bits(rebind["picker_chance"],4) != 20000):
                raise ValueError("Replacement lacks finite changed-classification witness")
            one("REPLACEMENT", dict(path=path, qualified_factory="true", unqualified_factory="true", count="3"))
            one("RESTORE", dict(module="true", fulltype="true", qualified_old="true", unqualified_old="true"))
            accepts = [d for k,d in selected if k == "ACCEPT"]
            items = [d for k,d in selected if k == "ITEM"]
            if (len(accepts) != 3 or ":Base.Nails:" not in accepts[0]
                    or len(items) != 3 or any(":Base.PZLootRuntimeAlternate:" not in d or ":initialized=true" not in d for d in items[1:])):
                raise ValueError("Replacement does not bind first callback and qualified/unqualified factory outputs")
            kinds = [k for k,_ in selected]
            positions = [i for i,k in enumerate(kinds) if k == "ACCEPT"]
            if not positions[0] < kinds.index("REBIND") < positions[1] < positions[2] < kinds.index("REPLACEMENT") < kinds.index("RESTORE"):
                raise ValueError("Replacement callback/finally ordering differs")
            if any(k in allowed-{"SETTINGS","REBIND","REPLACEMENT","RESTORE"} for k,_ in selected): raise ValueError("Foreign replacement witness")
            proofs[case] = rebind
        else:
            inp = one("RELOAD_INPUT")
            if (set(inp) != {"files","bytes","input_digest","original","changed"} or not 0 < int(inp["files"]) <= 4096
                    or not 0 < int(inp["bytes"]) <= 128*1024*1024 or inp["original"] == inp["changed"]
                    or any(not re.fullmatch("[0-9a-f]{64}",inp[k]) for k in ("input_digest","original","changed"))):
                raise ValueError("Reload bounded input/disk edit proof differs")
            original = Path(__file__).with_name("loot-runtime-probes.txt").read_bytes()
            anchor = b"DisplayCategory = Memento,\n        Weight = 0.05,"
            if original.count(anchor) != 1: raise ValueError("Reload fixture edit anchor changed")
            changed = original.replace(anchor,b"DisplayCategory = FirstAid,\n        Weight = 0.125,")
            if inp["original"] != hashlib.sha256(original).hexdigest() or inp["changed"] != hashlib.sha256(changed).hexdigest():
                raise ValueError("Reload disk edit differs from current exact owned fixture")
            one("RELOAD", dict(native_api="ReloadScripts(Item)", same_identity="true", qualified="true", unqualified="true",
                               category="FirstAid", weight=_float_bits(.125), load_errors="false", owned_source="true"))
            one("RELOAD_RESTORE", dict(disk="true", original=inp["original"], runtime_restored="false", terminal="true"))
            rolls = [_props(d) for k,d in selected if k == "RELOAD_ROLL"]
            if [(v.get("phase"),v.get("path")) for v in rolls] != [(phase,path) for phase in ("before","after") for path in ("direct","bag")]:
                raise ValueError("Reload roll cardinality/order differs")
            for value in rolls:
                hit = value["phase"] == "after"; count = 2 if hit else 0
                stable = dict(count=str(count),weight=_float_bits(.125 if hit else .05),script_field_proof="true",factory_proof=str(hit).lower(),
                              picker_chance=_float_bits(20000),draw_min="0",draw_max_exclusive="10000")
                if (set(value) != set(stable)|{"phase","path","native_chance","next_rng"} or any(value.get(k)!=v for k,v in stable.items())
                        or not 0 <= int(value["next_rng"]) < 1_000_000): raise ValueError("Reload native roll proof differs")
                chance = _number_bits(value["native_chance"],4)
                if (chance < 10000 if hit else chance != 0): raise ValueError("Reload lacks finite changed classification")
                prefix = value["phase"]+"-"+value["path"]
                items = [d for k,d in selected if k == "ITEM" and d.startswith(prefix+"/")]
                containers = [d for k,d in selected if k == "CONTAINER" and d.startswith(prefix+":")]
                if (len(items) != count or len(containers) != 1 or int(_props(containers[0].split(":",1)[1])["count"]) != count
                        or any(":Base.PZLootRuntimeProbe:" not in d or ":initialized=true" not in d for d in items)):
                    raise ValueError("Reload roll not bound to actual native items")
            factory = [(i,_props(d)) for i,(k,d) in enumerate(selected) if k == "RELOAD_ITEM"]
            if [(v.get("phase"),v.get("path"),v.get("index")) for _,v in factory] != [
                    ("after",path,str(index)) for path in ("direct","bag") for index in range(2)]:
                raise ValueError("Reload factory field cardinality/order differs")
            for position,value in factory:
                if (set(value) != {"phase","path","index","fulltype","id","stored_weight","public_weight","display_fallback","script_identity","initialized"}
                        or value["fulltype"] != "Base.PZLootRuntimeProbe" or value["stored_weight"] != _float_bits(.125)
                        or value["display_fallback"] not in ("true","false") or value["script_identity"] != "true" or value["initialized"] != "true"
                        or value["public_weight"] != ("0" if value["display_fallback"] == "true" else _float_bits(.125))):
                    raise ValueError("Reload native stored/public weight proof differs")
                prefix="after-"+value["path"]+"/"+value["index"]+":"
                bound=[d for k,d in selected if k == "ITEM" and d.startswith(prefix)
                       and ":Base.PZLootRuntimeProbe:id="+value["id"]+":" in d]
                roll_position=next(i for i,(k,d) in enumerate(selected) if k == "RELOAD_ROLL"
                                   and _props(d).get("phase") == "after" and _props(d).get("path") == value["path"])
                reload_position=next(i for i,(k,_) in enumerate(selected) if k == "RELOAD")
                if len(bound)!=1 or not reload_position < position < roll_position:
                    raise ValueError("Reload field witness is not bound to its native item/roll")
            kinds = [k for k,_ in selected]
            positions = [i for i,k in enumerate(kinds) if k == "RELOAD_ROLL"]
            if not positions[1] < kinds.index("RELOAD_INPUT") < kinds.index("RELOAD") < positions[2] < positions[3] < kinds.index("RELOAD_RESTORE"):
                raise ValueError("Reload before/API/after/restore ordering differs")
            if (sum(k == "DISPOSE" for k in kinds) != 4 or not kinds.index("RELOAD_INPUT") < kinds.index("RELOAD") < kinds.index("RELOAD_RESTORE")
                    or any(k in allowed-{"SETTINGS","RELOAD_INPUT","RELOAD","RELOAD_ITEM","RELOAD_ROLL","RELOAD_RESTORE","DISPOSE"} for k in kinds)):
                raise ValueError("Reload terminal/restore/disposal ordering differs")
            proofs[case] = dict(inputs=inp, rolls=rolls)
    return proofs


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
    bank = status.get("bank")
    expected_cases = BANK_CASES.get(bank)
    if expected_cases is None:
        raise ValueError("Missing/unknown explicit bank")
    if status.get("status") != "complete" or status.get("mode") != mode or status.get("cases") != str(len(expected_cases)) or status.get("reason"):
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
        "state": "active", "mode": mode, "bank": bank, "pid": pid, "definitions": "1", "rng_audit_definitions": "1",
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
    if begin != expected_cases or end != expected_cases or cleanup != expected_cases:
        raise ValueError("Incomplete/duplicate/out-of-order case rows")
    if bank != "reload" and not any(line.startswith("ITEM\tdirect-real-items\t") and ":initialized=true" in line for line in lines):
        raise ValueError("No actual initialized direct items")
    if bank != "reload" and not any(line.startswith("ITEM\tbag-real-items\t") and ":initialized=true" in line for line in lines):
        raise ValueError("No actual initialized bag items")
    if bank != "reload" and not any(line.startswith("FILL\tnative-nested-fill-reentrant\t") for line in lines):
        raise ValueError("No actual native OnFillContainer callback")
    clock_rows(lines, bank != "reload")
    semantic_rows(lines, bank)
    expected_coverage = coverage(bank)
    if any(status.get(k) != v for k, v in expected_coverage.items()):
        raise ValueError("Bank coverage/status proof differs")
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
    if control["bank"] != candidate["bank"]:
        raise ValueError("Different selected banks")
    bank = control["bank"]
    if stock["input"] != patched["input"]:
        raise ValueError("Different native inputs")
    if control["resource_profile"] != candidate["resource_profile"] or control["optimizer_manifest_sha256"] != candidate["optimizer_manifest_sha256"]:
        raise ValueError("Different runtime resource/profile inputs")
    normalized_a, clocks_a = clock_rows(a, bank != "reload")
    normalized_b, clocks_b = clock_rows(b, bank != "reload")
    equal = normalized_a == normalized_b
    report = {"format": 2, "status": "equal" if equal else "different", "bank": bank, "cases": len(BANK_CASES[bank]),
              "control_pid": control["pid"], "candidate_pid": candidate["pid"], "native_input": stock["input"],
              "candidate_output": patched["output"], "rows": {"control": len(a)-1, "candidate":len(b)-1},
              "resource_profile":control["resource_profile"], "optimizer_manifest_sha256":control["optimizer_manifest_sha256"],
              "limits": limits(bank),
              "semantic_proofs": {"control": semantic_rows(a,bank), "candidate": semantic_rows(b,bank)},
              "raw_equal": a == b, "clock_proofs": {"control": clocks_a, "candidate": clocks_b},
              "rng_scope": {"control": rng(args.control_cache, control["pid"]), "candidate": rng(args.candidate_cache, candidate["pid"])},
              "raw_diff": list(difflib.unified_diff(a,b,fromfile="control-raw",tofile="candidate-raw")),
              "diff": list(difflib.unified_diff(normalized_a,normalized_b,fromfile="control-validated",tofile="candidate-validated"))}
    args.output.write_text(json.dumps(report,indent=2) + "\n")
    if not equal:
        print("".join(report["diff"])[:16000])
        raise SystemExit("Actual native loot receipts differ; comparison retained")
    print("LOOT_RESOLVED_RUNTIME_PARITY_PASS bank="+bank+" cases="+str(len(BANK_CASES[bank]))+" rows="+str(len(a)-1))
    print("Native fixture parity only; inspect full logs and the declared uncovered gates")


if __name__ == "__main__":
    main()
