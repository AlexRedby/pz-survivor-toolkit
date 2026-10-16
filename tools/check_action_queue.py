#!/usr/bin/env python3
"""Prepare/run isolated native suites, audit results, and display actual coverage."""
import argparse
import json
from pathlib import Path
import sys
import subprocess

from queue_checks import native, report, runner, adapters, worlds, pack, admission

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "tests/native_queue/catalog.json"


def selection(args, catalog, options=None):
    suite = catalog["suites"][args.suite]
    if suite["status"] != "ready":
        raise ValueError("Suite has not been migrated: " + args.suite)
    all_cases = {case["id"]: case for case in suite["cases"]}
    if args.cases == '':
        raise ValueError('--cases requires at least one case ID')
    kind = args.kind or suite['cases'][0]['kinds'][0]
    cases = args.cases.split(",") if args.cases else ([suite['cases'][0]['id']] if args.suite != 'health' else [case['id'] for case in suite['cases'] if kind in case['kinds']])
    if not cases or len(cases) != len(set(cases)) or any(identifier not in all_cases for identifier in cases):
        raise ValueError("Select known unique case IDs; see matrix")
    spec = all_cases[cases[0]]
    if args.mods == "selected":
        mods = native._metadata(ROOT / "SurvivorQoL-selected.ini")["Mods"].split(";")
    else:
        mods = args.mods.split(",") if args.mods else spec.get('default_mods', suite.get('default_mods', ['PZSurvivorToolkit']))
    language = args.language or spec.get('languages', ['EN'])[0]
    clients = 1 if kind == 'sp' else suite.get('clients', 2)
    options = (report.read_json(args.config) if args.config else {}) if options is None else options
    if not isinstance(options, dict):
        raise ValueError('--config must contain a JSON object of suite options')
    if getattr(args, 'pack_lock', None):
        options['pack_lock'] = str(args.pack_lock.resolve())
    if options.get('pack_lock') and not args.mods:
        locked = report.read_json(options['pack_lock'])
        mods = [row['id'] for row in locked['mods']]
    overrides = dict(options.get('mod_sources', {}))
    for value in args.mod_source:
        identifier, separator, path = value.partition('=')
        if not separator or not identifier or not Path(path).is_absolute():
            raise ValueError('--mod-source requires MOD_ID=/absolute/mod/root')
        overrides[identifier] = path
    if overrides:
        options['mod_sources'] = overrides
    if getattr(args, 'world_template', None):
        options['world_template'] = str(args.world_template.resolve())
    for identifier in cases:
        if kind not in all_cases[identifier]['kinds'] or args.mode not in all_cases[identifier].get('modes', ['toolkit', 'native']):
            raise ValueError('Unsupported kind/mode for ' + identifier)
    resources = getattr(args, 'resources', {})
    if not isinstance(resources, dict):
        raise ValueError('resources must be an object')
    return {"schema_version": 1, "suite": args.suite, "mode": args.mode,
            "cases": cases, "mods": mods, 'kind': kind, 'clients': clients, 'options': options,
            'config_source': str(args.config.resolve()) if args.config else None,
            "languages": [language] if clients == 1 else ["EN", "RU"],
            "timeout_seconds": args.timeout, "ports": args.ports or [17343, 17344], 'ports_auto': args.ports is None,
            'resources': dict(admission.DEFAULTS, **resources), "expected_checks": len(cases) + 2}


def save_report(output, catalog, control=None):
    value = report.build_report(output, catalog, report.build_report(control, catalog) if control else None)
    report.write_json(output / 'report.json', value)
    (output / 'report.txt').write_text(report.summary(value), encoding='utf-8')
    report.write_json(output / 'coverage.json', report.matrix(catalog, [value]))
    return value


def selected_jobs(plan, only=None, sets=(), skip=None):
    jobs = plan.get('jobs') if isinstance(plan, dict) else None
    if not isinstance(jobs, list) or not jobs or any(not isinstance(job, dict) for job in jobs):
        raise ValueError('Batch plan requires a nonempty jobs list')
    identifiers = [job.get('id') for job in jobs]
    if any(not isinstance(id, str) or not native.MOD_ID.fullmatch(id) or id in ('.', '..') for id in identifiers) or len(set(identifiers)) != len(jobs):
        raise ValueError('Batch job IDs must be unique safe directory names')
    by_id = {job['id']: job for job in jobs}
    groups = plan.get('sets', {})
    if not isinstance(groups, dict) or any(not isinstance(v, list) or not v or any(id not in by_id for id in v) for v in groups.values()):
        raise ValueError('Batch sets must contain nonempty lists of known job IDs')
    if only == '':
        raise ValueError('--jobs requires at least one job ID')
    wanted = set(only.split(',')) if only else set()
    for name in sets:
        if name not in groups:
            raise ValueError('Unknown test set: ' + name)
        wanted.update(groups[name])
    if not only and not sets:
        wanted.update(identifiers)
    excluded = set(skip.split(',')) if skip else set()
    if (wanted | excluded) - by_id.keys():
        raise ValueError('Unknown job IDs: ' + ', '.join(sorted((wanted | excluded) - by_id.keys())))
    wanted -= excluded
    def include(id, trail):
        if id in trail:
            raise ValueError('Cyclic job dependency: ' + id)
        if id not in by_id or id in excluded:
            raise ValueError('Missing or disabled job dependency: ' + id)
        for key in ('control_job', 'seed_job'):
            if by_id[id].get(key):
                include(by_id[id][key], trail | {id})
        wanted.add(id)
    for id in list(wanted):
        include(id, set())
    selected = [job for job in jobs if job['id'] in wanted]
    seen = set()
    for job in selected:
        for key in ('control_job', 'seed_job'):
            if job.get(key) and job[key] not in seen:
                raise ValueError('Dependencies must precede job: ' + job['id'])
        seen.add(job['id'])
    if not selected:
        raise ValueError('No test jobs selected')
    return selected


def batch(args, catalog):
    plan = report.read_json(args.plan)
    jobs = selected_jobs(plan, getattr(args, 'jobs', None), getattr(args, 'sets', ()), getattr(args, 'skip_jobs', None))
    identifiers = [job['id'] for job in jobs]
    if args.output.exists():
        raise FileExistsError('Fresh batch output directory required')
    args.output.mkdir(parents=True)
    results, reports, completed = [], [], {}
    for job in jobs:
        output = args.output / job['id']
        item = {'id': job['id'], 'run': str(output.resolve())}
        interrupted = False
        print('START ' + job['id'], flush=True)
        try:
            options = dict(plan.get('options', {}), **job.get('options', {}))
            if job.get('seed_job'):
                options['seed_run'] = str(completed[job['seed_job']])
            mods = job.get('mods', plan.get('mods'))
            if mods is not None and mods != 'selected' and (not isinstance(mods, list) or any(not isinstance(id, str) for id in mods)):
                raise ValueError('Batch mods must be a list of Mod IDs or selected')
            if not isinstance(plan.get('resources', {}), dict) or not isinstance(job.get('resources', {}), dict):
                raise ValueError('Batch resources must be objects')
            namespace = argparse.Namespace(suite=job['suite'], cases=job.get('case'), mode=job.get('mode', 'toolkit'),
                kind=job.get('kind'), language=job.get('language'), mods='selected' if mods == 'selected' else ','.join(mods) if mods else None,
                config=args.plan, mod_source=[], timeout=job.get('timeout', 900), ports=job.get('ports'),
                resources=dict(plan.get('resources', {}), **job.get('resources', {})))
            selected = selection(namespace, catalog, options)
            native.prepare(ROOT, output, Path(plan['game']), Path(plan['jdk']), selected, [Path(p) for p in plan.get('workshop', [])])
            execution = runner.run(output, resource_wait=job.get('resource_wait', plan.get('resource_wait', 300)))
            interrupted = execution.get('interrupted', False)
            control = completed[job['control_job']] if job.get('control_job') else None
            value = save_report(output, catalog, control)
            reports.append(value)
            completed[job['id']] = output.resolve()
            item.update(status=value['status'], functional=value['functional']['status'], runtime=value['runtime']['status'])
            print(report.summary(value), flush=True)
        except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
            item.update(status='blocked' if not (output / 'execution.json').exists() else 'failed', error=str(error))
            print(item['status'].upper() + ' ' + job['id'] + ': ' + str(error), flush=True)
        results.append(item)
        overall = 'failed' if any(row['status'] in ('failed', 'blocked') for row in results) else 'needs-review' if any(row['status'] == 'needs-review' for row in results) else 'passed'
        report.write_json(args.output / 'batch-report.json', {'status': overall, 'jobs': results, 'remaining': identifiers[len(results):]})
        report.write_json(args.output / 'coverage.json', report.matrix(catalog, reports))
        if interrupted:
            return 130
    return {'passed': 0, 'failed': 1, 'needs-review': 2}[overall]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("prepare", "run"):
        command = commands.add_parser(name)
        command.add_argument("output", type=Path, help="Fresh isolated output directory")
        command.add_argument("--suite", default="health")
        command.add_argument("--kind", choices=("sp", "mp"))
        command.add_argument("--mode", choices=("toolkit", "native"), default="toolkit")
        command.add_argument("--cases", help="Comma-separated case IDs; omitted uses the suite default (all health cases for kind)")
        command.add_argument("--mods", help="Comma-separated Mod IDs, or selected for project INI; omitted uses suite defaults")
        command.add_argument('--config', type=Path, help='JSON suite options with explicit dependency paths')
        command.add_argument('--mod-source', action='append', default=[], help='Explicit candidate MOD_ID=/absolute/mod/root; repeatable')
        command.add_argument('--world-template', type=Path, help='Copy a sealed prepared world into this fresh run; never launch the template itself')
        command.add_argument('--pack-lock', type=Path, help='Use the exact selected pack; reject missing or changed inputs before launch')
        command.add_argument("--language", choices=("EN", "RU"))
        command.add_argument("--game", type=Path, required=True, help="Directory containing projectzomboid.jar")
        command.add_argument("--jdk", type=Path, required=True)
        command.add_argument("--workshop", action="append", type=Path, default=[], help="Repeatable installed Workshop roots")
        command.add_argument("--timeout", type=int, default=3600, help="Total gameplay deadline seconds")
        command.add_argument("--ports", nargs=2, type=int, help='Explicit UDP ports; omitted allocates an isolated adjacent pair')
        command.add_argument('--heap-mib', type=int, default=2048, help='Maximum Java heap per game process')
        command.add_argument('--native-mib', type=int, default=1024, help='Estimated native/graphics/encoder memory per process, beyond heap')
        command.add_argument('--cpu-per-instance', type=float, default=1.0, help='Estimated logical CPU budget per game process')
        command.add_argument('--exclusive', action='store_true', help='Reserve the desktop exclusively for physical input or timing measurements')
        if name == "run":
            command.add_argument("--resource-wait", type=float, default=300, help="Seconds to wait for admission; 0 refuses immediately")
            command.add_argument("--control", type=Path, help="Completed matching native control run directory")
    command = commands.add_parser("resume", help="Launch a fresh already prepared snapshot")
    command.add_argument("output", type=Path)
    command.add_argument("--control", type=Path)
    command.add_argument("--resource-wait", type=float, default=300)
    command = commands.add_parser("report", help="Audit a run without launching anything")
    command.add_argument("output", type=Path)
    command.add_argument("--control", type=Path)
    command = commands.add_parser("matrix", help="List declared cases and actual evidence; never infer passes")
    command.add_argument("reports", type=Path, nargs="*")
    command.add_argument("--output", type=Path)
    command = commands.add_parser('batch', help='Run an explicit stand plan sequentially with fresh profiles and a combined report')
    command.add_argument('plan', type=Path)
    command.add_argument('output', type=Path)
    command.add_argument('--jobs', help='Run only these comma-separated job IDs and their control/seed dependencies')
    command.add_argument('--set', dest='sets', action='append', default=[], help='Run a named set from the plan; repeatable')
    command.add_argument('--skip-jobs', help='Disable comma-separated jobs; required dependencies cannot be disabled')
    command = commands.add_parser('lock-pack', help='Resolve and hash the actual SurvivorQoL-selected.ini pack without launching the game')
    command.add_argument('output', type=Path)
    command.add_argument('--game', type=Path, required=True)
    command.add_argument('--workshop', action='append', type=Path, default=[])
    command.add_argument('--mod-source', action='append', default=[])
    command = commands.add_parser('save-world', help='Export Saves/db from a completed, stopped disposable run as a sealed reusable template')
    command.add_argument('run', type=Path)
    command.add_argument('output', type=Path)
    args = parser.parse_args(argv)
    try:
        catalog = report.read_json(CATALOG)
        catalog['suites'].update(adapters.definitions())
        if args.command == 'lock-pack':
            overrides = {}
            for argument in args.mod_source:
                id, separator, path = argument.partition('=')
                if not separator or not Path(path).is_absolute():
                    raise ValueError('--mod-source requires MOD_ID=/absolute/mod/root')
                overrides[id] = path
            value = pack.create(ROOT, args.output, args.game, args.workshop, overrides)
            print('Locked ' + str(len(value['mods'])) + ' ordered Mod IDs: ' + str(args.output.resolve()))
            return 0
        if args.command == 'save-world':
            value = worlds.export(args.run, args.output)
            print('Saved world template: ' + str(args.output.resolve()) + ' (' + str(len(value['files'])) + ' files)')
            return 0
        if args.command == 'batch':
            return batch(args, catalog)
        if args.command == "matrix":
            value = report.matrix(catalog, [report.read_json(path) for path in args.reports])
            if args.output:
                report.write_json(args.output, value)
            for row in value["rows"]:
                print(" | ".join(str(row.get(key, "-")) for key in ("suite", "case", "producer", "capability", "kind", "mode", "status")))
            return 0
        if args.command in ("prepare", "run"):
            args.resources = {key: getattr(args, key) for key in admission.DEFAULTS}
            native.prepare(ROOT, args.output, args.game, args.jdk, selection(args, catalog), args.workshop)
            print("Prepared: " + str(args.output.resolve()), flush=True)
            if args.command == "prepare":
                return 0
        if args.command in ("run", "resume"):
            runner.run(args.output, resource_wait=args.resource_wait)
        value = save_report(args.output, catalog, args.control)
        print(report.summary(value))
        if value['execution'].get('interrupted'):
            return 130
        return {"passed": 0, "failed": 1, "needs-review": 2}[value["status"]]
    except KeyboardInterrupt:
        return 130
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
