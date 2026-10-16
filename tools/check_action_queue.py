#!/usr/bin/env python3
"""Prepare/run isolated native suites, audit results, and display actual coverage."""
import argparse
import json
from pathlib import Path
import sys
import subprocess

from queue_checks import native, report, runner

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "tests/native_queue/catalog.json"


def selection(args, catalog):
    suite = catalog["suites"][args.suite]
    if suite["status"] != "ready":
        raise ValueError("Suite has not been migrated: " + args.suite)
    all_cases = {case["id"]: case for case in suite["cases"]}
    cases = args.cases.split(",") if args.cases else [case["id"] for case in suite["cases"] if args.kind in case["kinds"]]
    if not cases or len(cases) != len(set(cases)) or any(identifier not in all_cases for identifier in cases):
        raise ValueError("Select known unique case IDs; see matrix")
    if args.mods == "selected":
        mods = native._metadata(ROOT / "SurvivorQoL-selected.ini")["Mods"].split(";")
    else:
        mods = args.mods.split(",")
    return {"schema_version": 1, "suite": args.suite, "kind": args.kind, "mode": args.mode,
            "cases": cases, "mods": mods, "languages": [args.language] if args.kind == "sp" else ["EN", "RU"],
            "timeout_seconds": args.timeout, "ports": args.ports, "expected_checks": len(cases) + 2}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("prepare", "run"):
        command = commands.add_parser(name)
        command.add_argument("output", type=Path, help="Fresh isolated output directory")
        command.add_argument("--suite", default="health")
        command.add_argument("--kind", choices=("sp", "mp"), default="sp")
        command.add_argument("--mode", choices=("toolkit", "native"), default="toolkit")
        command.add_argument("--cases", help="Comma-separated case IDs; omitted means all cases for kind")
        command.add_argument("--mods", default="PZSurvivorToolkit", help="Comma-separated Mod IDs, or selected for project INI")
        command.add_argument("--language", choices=("EN", "RU"), default="EN")
        command.add_argument("--game", type=Path, required=True, help="Directory containing projectzomboid.jar")
        command.add_argument("--jdk", type=Path, required=True)
        command.add_argument("--workshop", action="append", type=Path, default=[], help="Repeatable installed Workshop roots")
        command.add_argument("--timeout", type=int, default=3600, help="Total gameplay deadline seconds")
        command.add_argument("--ports", nargs=2, type=int, default=[17343, 17344])
        if name == "run":
            command.add_argument("--control", type=Path, help="Completed matching native control run directory")
    command = commands.add_parser("resume", help="Launch a fresh already prepared snapshot")
    command.add_argument("output", type=Path)
    command.add_argument("--control", type=Path)
    command = commands.add_parser("report", help="Audit a run without launching anything")
    command.add_argument("output", type=Path)
    command.add_argument("--control", type=Path)
    command = commands.add_parser("matrix", help="List declared cases and actual evidence; never infer passes")
    command.add_argument("reports", type=Path, nargs="*")
    command.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    try:
        catalog = report.read_json(CATALOG)
        if args.command == "matrix":
            value = report.matrix(catalog, [report.read_json(path) for path in args.reports])
            if args.output:
                report.write_json(args.output, value)
            for row in value["rows"]:
                print(" | ".join(str(row.get(key, "-")) for key in ("suite", "case", "producer", "capability", "kind", "mode", "status")))
            return 0
        if args.command in ("prepare", "run"):
            native.prepare(ROOT, args.output, args.game, args.jdk, selection(args, catalog), args.workshop)
            print("Prepared: " + str(args.output.resolve()), flush=True)
            if args.command == "prepare":
                return 0
        if args.command in ("run", "resume"):
            runner.run(args.output)
        control = report.build_report(args.control, catalog) if args.control else None
        value = report.build_report(args.output, catalog, control)
        if (args.output / "execution.json").is_file():
            value["execution"] = report.read_json(args.output / "execution.json")
            if value["execution"]["status"] != "completed":
                value["status"] = "failed"
        report.write_json(args.output / "report.json", value)
        (args.output / "report.txt").write_text(report.summary(value), encoding="utf-8")
        report.write_json(args.output / "coverage.json", report.matrix(catalog, [value]))
        print(report.summary(value))
        return {"passed": 0, "failed": 1, "needs-review": 2}[value["status"]]
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
