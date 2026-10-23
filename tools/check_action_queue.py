#!/usr/bin/env python3
"""Prepare/run isolated native suites, audit results, and display actual coverage."""
import argparse
import json
from pathlib import Path
import sys
import subprocess

from queue_checks import native, report, runner, adapters, worlds, pack, admission, scenarios

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "tests/native_queue/catalog.json"


def load_catalog(suites=None):
    """Resolve only the requested declarations; full reports retain the complete catalog."""
    catalog = report.read_json(CATALOG)
    if suites is not None:
        known = dict.fromkeys([*catalog['suites'], *adapters.MODULES])
        unknown = set(suites) - known.keys()
        if unknown:
            raise ValueError('Unknown suites: ' + ', '.join(sorted(unknown))
                             + '; available: ' + ', '.join(known))
    catalog['suites'].update(adapters.definitions(suites))
    if suites is not None:
        catalog['suites'] = {suite: catalog['suites'][suite] for suite in suites}
    return catalog


def selection(args, catalog, options=None):
    suite = catalog["suites"][args.suite]
    if suite["status"] != "ready":
        raise ValueError("Suite has not been migrated: " + args.suite)
    all_cases = {case["id"]: case for case in suite["cases"]}
    if args.cases is not None and (not isinstance(args.cases, str) or not args.cases):
        raise ValueError('--cases requires a nonempty comma-separated string of case IDs')
    kind = args.kind or suite['cases'][0]['kinds'][0]
    cases = args.cases.split(",") if args.cases else ([suite['cases'][0]['id']] if args.suite != 'health' else [case['id'] for case in suite['cases'] if kind in case['kinds']])
    if not cases or len(cases) != len(set(cases)) or any(identifier not in all_cases for identifier in cases):
        raise ValueError("Select known unique case IDs; see matrix")
    scenario_ids = getattr(args, 'scenarios', None)
    action_ids = getattr(args, 'actions', None)
    required_mods = []
    if action_ids is not None and scenario_ids is None:
        raise ValueError('--actions requires --scenarios')
    if scenario_ids is not None:
        if args.cases is not None:
            raise ValueError('Use either --cases or --scenarios')
        cases, required_mods = scenarios.select(suite, scenario_ids, action_ids, kind, args.mode)
    spec = all_cases[cases[0]]
    if args.mods == 'vanilla':
        if args.suite != 'startup' or args.mode != 'native':
            raise ValueError('--mods vanilla requires startup in native mode')
        mods = []
    elif args.mods == "selected":
        mods = native._metadata(ROOT / "SurvivorQoL-selected.ini")["Mods"].split(";")
    else:
        mods = args.mods.split(",") if args.mods else spec.get('default_mods', suite.get('default_mods', ['PZSurvivorToolkit']))
    language = args.language or spec.get('languages', ['EN'])[0]
    clients = 1 if kind == 'sp' else suite.get('clients', 2)
    options = (report.read_json(args.config) if args.config else {}) if options is None else options
    if not isinstance(options, dict):
        raise ValueError('--config must contain a JSON object of suite options')
    if getattr(args, 'cart_scene', None):
        if args.suite != 'wooden_cart_motion':
            raise ValueError('--cart-scene requires the wooden_cart_motion suite')
        options['cart_scenes'] = args.cart_scene
    if getattr(args, 'pack_lock', None):
        options['pack_lock'] = str(args.pack_lock.resolve())
    if options.get('pack_lock') and not args.mods:
        locked = report.read_json(options['pack_lock'])
        mods = [row['id'] for row in locked['mods']]
    if set(required_mods) - set(mods):
        raise ValueError('Scenario requires enabled mods: ' + ', '.join(required_mods))
    sources = options.get('mod_sources', {})
    if not isinstance(sources, dict):
        raise ValueError('options.mod_sources must contain a JSON object')
    overrides = dict(sources)
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


def batch_selection(plan, job, catalog, config, runs):
    if 'cases' in job:
        raise ValueError("Batch jobs use 'case' with comma-separated IDs; 'cases' would be ignored")
    plan_options, job_options = plan.get('options', {}), job.get('options', {})
    if not isinstance(plan_options, dict) or not isinstance(job_options, dict):
        raise ValueError('Batch options must contain JSON objects')
    plan_sources, job_sources = plan_options.get('mod_sources', {}), job_options.get('mod_sources', {})
    if not isinstance(plan_sources, dict) or not isinstance(job_sources, dict):
        raise ValueError('options.mod_sources must contain a JSON object')
    options = dict(plan_options, **job_options)
    if 'mod_sources' in plan_options or 'mod_sources' in job_options:
        # An explicit empty job map opts out of plan pins for another mod selection.
        options['mod_sources'] = ({} if 'mod_sources' in job_options and not job_sources
                                  else {**plan_sources, **job_sources})
    if job.get('seed_job'):
        options['seed_run'] = str(runs[job['seed_job']])
    mods = job.get('mods', plan.get('mods'))
    if mods is not None and mods not in ('selected', 'vanilla') and (not isinstance(mods, list) or not mods or any(not isinstance(id, str) for id in mods)):
        raise ValueError('Batch mods must be a nonempty list of Mod IDs, selected or vanilla')
    if not isinstance(plan.get('resources', {}), dict) or not isinstance(job.get('resources', {}), dict):
        raise ValueError('Batch resources must be objects')
    namespace = argparse.Namespace(suite=job['suite'], cases=job.get('case'), scenarios=job.get('scenarios'), actions=job.get('actions'), mode=job.get('mode', 'toolkit'),
        kind=job.get('kind'), language=job.get('language'), mods=mods if isinstance(mods, str) else ','.join(mods) if mods else None,
        config=config, mod_source=[], timeout=job.get('timeout', 900), ports=job.get('ports'),
        resources=dict(plan.get('resources', {}), **job.get('resources', {})))
    return selection(namespace, catalog, options)


def batch(args, catalog):
    plan = report.read_json(args.plan)
    jobs = selected_jobs(plan, getattr(args, 'jobs', None), getattr(args, 'sets', ()), getattr(args, 'skip_jobs', None))
    identifiers = [job['id'] for job in jobs]
    if args.output.exists():
        raise FileExistsError('Fresh batch output directory required')
    if getattr(args, 'dry_run', False):
        runs, rows = {}, []
        for job in jobs:
            selected = batch_selection(plan, job, catalog, args.plan, runs)
            output = (args.output / job['id']).resolve()
            rows.append({'id': job['id'], 'run': str(output), 'selection': selected,
                         'control': str(runs[job['control_job']]) if job.get('control_job') else None,
                         'resource_wait': job.get('resource_wait', plan.get('resource_wait', 300))})
            runs[job['id']] = output
        print(json.dumps({'status': 'planned', 'game': plan['game'], 'jdk': plan['jdk'],
                          'workshop': plan.get('workshop', []), 'jobs': rows}, indent=2))
        return 0
    args.output.mkdir(parents=True)
    results, reports, completed = [], [], {}
    for job in jobs:
        output = args.output / job['id']
        item = {'id': job['id'], 'run': str(output.resolve())}
        interrupted = False
        print('START ' + job['id'], flush=True)
        try:
            for key in ('control_job', 'seed_job'):
                if job.get(key) and job[key] not in completed:
                    raise ValueError('Dependency has no completed report: ' + job[key])
            control = completed[job['control_job']] if job.get('control_job') else None
            selected = batch_selection(plan, job, catalog, args.plan, completed)
            native.prepare(ROOT, output, Path(plan['game']), Path(plan['jdk']), selected, [Path(p) for p in plan.get('workshop', [])])
            execution = runner.run(output, resource_wait=job.get('resource_wait', plan.get('resource_wait', 300)))
            interrupted = execution.get('interrupted', False)
            value = save_report(output, catalog, control)
            reports.append(value)
            completed[job['id']] = output.resolve()
            item.update(status=value['status'], functional=value['functional']['status'], runtime=value['runtime']['status'])
            print(report.summary(value), flush=True)
        except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError, KeyboardInterrupt) as error:
            interrupted = interrupted or isinstance(error, KeyboardInterrupt)
            item.update(status='blocked' if not (output / 'execution.json').exists() else 'failed',
                        error='Batch job interrupted' if isinstance(error, KeyboardInterrupt) else str(error))
            print(item['status'].upper() + ' ' + job['id'] + ': ' + item['error'], flush=True)
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
    command = commands.add_parser('status', help='Show native stand owners, FIFO waiters and blocking reasons without launching the game')
    command.add_argument('--json', action='store_true', help='Print the machine-readable admission snapshot')
    for name in ("prepare", "run"):
        command = commands.add_parser(name)
        command.add_argument("output", type=Path, help="Fresh isolated output directory")
        command.add_argument("--suite", default="health")
        command.add_argument("--kind", choices=("sp", "mp"))
        command.add_argument("--mode", choices=("toolkit", "native"), default="toolkit")
        command.add_argument('--scenarios', help='Comma-separated common behavior IDs; all requested action/scenario pairs must be implemented')
        command.add_argument('--actions', help='Comma-separated scenario action IDs; omitted selects all mapped actions in the suite')
        command.add_argument("--cases", help="Comma-separated case IDs; omitted uses the suite default (all health cases for kind)")
        command.add_argument('--cart-scene', action='append', help='Exact SP cart scene ID for a partial debug capture; repeatable, e.g. male-full-corner')
        command.add_argument("--mods", help="Comma-separated Mod IDs, selected for project INI, or vanilla for startup/native without production mods; omitted uses suite defaults")
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
    command.add_argument('--scenarios', action='store_true', help='Show behavior requirements per action, including implementation gaps')
    command.add_argument("--output", type=Path)
    command.add_argument('--suite', action='append', default=[], help='Show only this suite; repeatable')
    command.add_argument('--kind', choices=('sp', 'mp'), help='Show only single-player or multiplayer cases')
    command.add_argument('--mode', choices=('toolkit', 'native'), help='Show only this feature mode')
    command = commands.add_parser('batch', help='Run an explicit stand plan sequentially with fresh profiles and a combined report')
    command.add_argument('plan', type=Path)
    command.add_argument('output', type=Path)
    command.add_argument('--jobs', help='Run only these comma-separated job IDs and their control/seed dependencies')
    command.add_argument('--set', dest='sets', action='append', default=[], help='Run a named set from the plan; repeatable')
    command.add_argument('--skip-jobs', help='Disable comma-separated jobs; required dependencies cannot be disabled')
    command.add_argument('--dry-run', action='store_true', help='Print resolved job selections as JSON without preparing profiles or launching games')
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
        if args.command == 'status':
            value = admission.status(legacy_lock=runner.LOCK)
            if args.json:
                print(json.dumps(value, indent=2))
            else:
                print('Running: ' + str(len(value['running'])))
                for item in value['running']:
                    print('  %s | PID %s%s | %s/%s/%s | %s | game PIDs %s' % (
                        item['root'], item.get('pid', '?'), ' (owner exited)' if not item['owner_alive'] else '', item.get('suite') or '?',
                        item.get('kind') or '?', item.get('mode') or '?',
                        'exclusive' if item['budget']['exclusive'] else 'shared',
                        ','.join(str(p['pid']) for p in item['processes']) or 'none'))
                print('Waiting: ' + str(len(value['waiting'])))
                for item in value['waiting']:
                    print('  #%s %s | PID %s | %.0fs | %s | %s' % (
                        item['position'], item['root'], item['pid'], item['wait_seconds'],
                        'exclusive' if item['exclusive'] else 'shared', item['reason']))
                print('Prepared port reservations: ' + str(len(value['prepared'])))
                lock = value['legacy_lock']
                print('Legacy lock: ' + ('exclusive' if lock['exclusive'] else 'shared/busy' if lock['busy'] else 'free'))
                for limit in value['limits']:
                    print('Note: ' + limit)
            return 0
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
        if args.command == 'prepare':
            catalog = load_catalog([args.suite])
        elif args.command == 'matrix' and args.suite:
            catalog = load_catalog(args.suite)
        else:
            catalog = load_catalog()
        if args.command == 'batch':
            return batch(args, catalog)
        if args.command == "matrix":
            value = report.matrix(catalog, [report.read_json(path) for path in args.reports])
            for field in ('rows', 'scenarios'):
                value[field] = [row for row in value[field]
                                if (not args.suite or row['suite'] in args.suite)
                                and (args.kind is None or row.get('kind') == args.kind or row['status'] == 'unmapped')
                                and (args.mode is None or row.get('mode') == args.mode or row['status'] == 'unmapped')]
            if args.scenarios:
                value['rows'] = value['scenarios']
            if args.output:
                report.write_json(args.output, value)
            columns = ('suite', 'action', 'scenario', 'kind', 'mode', 'status') if args.scenarios else ('suite', 'case', 'producer', 'capability', 'kind', 'mode', 'status')
            for row in value['rows']:
                print(' | '.join(str(row.get(key, '-')) for key in columns))
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
