"""Attach an ordinary strict resume to its original prepared batch unit."""
from contextlib import contextmanager
from copy import deepcopy
import json
import os
from pathlib import Path
import stat
import tempfile

try:
    import fcntl
except ImportError:
    fcntl = None

from . import campaign, provenance, report


def anchor(root, control=None):
    root = Path(root).resolve()
    control = Path(control).resolve() if control is not None else None
    return dict(snapshot_sha256=provenance.digest(root / 'snapshot-hashes.json'),
                control_run=str(control) if control else None,
                control_snapshot_sha256=provenance.digest(control / 'snapshot-hashes.json') if control else None)


def _rows(value, root):
    jobs = value.get('jobs')
    if not isinstance(jobs, list) or any(not isinstance(row, dict) for row in jobs):
        raise ValueError('Invalid batch accounting jobs')
    rows = [row for row in jobs if row.get('run') == str(root)]
    if not rows or not any('snapshot_sha256' in row for row in rows):
        return []  # No prepared-snapshot binding exists for a legacy/pre-prepare attempt.
    if (len({row.get('id') for row in rows}) != len(rows) or rows[0].get('id') != root.name
            or any(row.get('snapshot_sha256') != rows[0].get('snapshot_sha256')
                   or row.get('control_run') != rows[0].get('control_run')
                   or row.get('control_snapshot_sha256') != rows[0].get('control_snapshot_sha256') for row in rows)):
        raise ValueError('Inconsistent batch prepared-snapshot binding')
    sessions = value.get('sessions')
    if not isinstance(sessions, list):
        raise ValueError('Missing batch session accounting')
    units = [unit for unit in sessions if isinstance(unit, dict) and unit.get('run') == str(root)]
    if (len(units) != 1 or units[0].get('jobs') != [row['id'] for row in rows]
            or len(rows) > 1 and (not rows[0].get('session') or
                                 any(row.get('session') != rows[0]['session'] for row in rows))):
        raise ValueError('Batch unit membership differs from its prepared run')
    return rows


def resolve(root, control=None):
    """Validate accounting/control binding before the ordinary runner can launch."""
    root = Path(root).resolve()
    path = root.parent / 'batch-report.json'
    if not path.exists():
        return None, control
    value = provenance.read_json(path)
    if not isinstance(value, dict):
        raise ValueError('Invalid batch accounting')
    rows = _rows(value, root)
    if not rows:
        return None, control
    expected_control = rows[0]['control_run']
    if control is not None and str(Path(control).resolve()) != expected_control:
        raise ValueError('Resume control differs from the original batch control')
    actual = anchor(root, expected_control)
    if any(any(row.get(key) != expected for key, expected in actual.items()) for row in rows):
        raise ValueError('Resume snapshot differs from the original batch binding')
    if any(row.get('status') != 'blocked' for row in rows):
        raise ValueError('Batch resume requires a previously blocked, unlaunched unit')
    return dict(path=path, root=root, rows=deepcopy(rows), anchor=actual), (
        Path(expected_control) if expected_control is not None else None)


@contextmanager
def _locked(path):
    lock = path.with_name('batch-report.resume.lock')
    descriptor = os.open(lock, os.O_CREAT | os.O_RDWR | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise ValueError('Batch accounting lock must be a regular file')
        if fcntl is not None:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise RuntimeError('Batch accounting is busy; another writer holds its lock') from error
        else:
            import msvcrt
            if os.fstat(descriptor).st_size == 0:
                os.write(descriptor, b'\0')
            os.lseek(descriptor, 0, os.SEEK_SET)
            try:
                msvcrt.locking(descriptor, msvcrt.LK_NBLCK, 1)
            except OSError as error:
                raise RuntimeError('Batch accounting lock is busy or unavailable: ' + str(error)) from error
        yield
    finally:
        # Both backends release ownership on close/process death. Keep the inode
        # so a new writer can never bypass an existing owner's lock via unlink.
        os.close(descriptor)


def _atomic_json(path, value):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                         prefix='.' + path.name + '.', delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _status(accounting):
    states = {row['status'] for row in accounting['jobs']}
    return ('failed' if states & {'failed', 'blocked'} else
            'needs-review' if 'needs-review' in states else
            'pending' if accounting.get('remaining') else 'passed')


def _coverage(accounting, catalog):
    reports = []
    for run in dict.fromkeys(row['run'] for row in accounting['jobs'] if row.get('report_sha256')):
        row = next(row for row in accounting['jobs'] if row['run'] == run and row.get('report_sha256'))
        saved = Path(run) / 'report.json'
        if provenance.digest(saved) != row['report_sha256']:
            raise ValueError('A previously accounted report changed: ' + run)
        value = provenance.read_json(saved)
        if provenance.digest(saved) != row['report_sha256']:
            raise ValueError('An accounted report changed while reading: ' + run)
        reports.append(value)
    return report.matrix(catalog, reports)


def write_accounting(path, accounting, catalog):
    """A still-running batch must retain resumes recorded between its own units."""
    path = Path(path)
    with _locked(path):
        if path.exists():
            previous = provenance.read_json(path)
            preserved = set()
            for field in ('jobs', 'sessions'):
                old = {(row['id'], row['run']): row for row in previous[field]}
                merged = []
                for row in accounting[field]:
                    prior = old.get((row['id'], row['run']))
                    if prior and prior.get('attempts') and prior['attempts'][0] == row:
                        row = deepcopy(prior)
                        preserved.add(row['id'])
                    merged.append(row)
                accounting[field] = merged
            if preserved:
                accounting['stop_history'] = deepcopy(previous.get('stop_history', []))
                stop = accounting.get('stop_reason')
                if isinstance(stop, dict) and stop.get('job') in preserved:
                    if stop not in accounting['stop_history']:
                        accounting['stop_history'].append(deepcopy(stop))
                    accounting['stop_reason'] = None
                accounting['campaign'] = campaign.refresh(accounting.get('campaign'), accounting['jobs'])
                accounting['status'] = _status(accounting)
        coverage = _coverage(accounting, catalog)
        _atomic_json(path.parent / 'coverage.json', coverage)
        _atomic_json(path, accounting)


def record(context, value, catalog):
    """Refresh only the bound unit; keep its exact first blocked attempt."""
    root, path = context['root'], context['path']
    if anchor(root, context['anchor']['control_run']) != context['anchor']:
        raise ValueError('Prepared snapshot changed while resuming; batch accounting was preserved')
    if value.get('run') != str(root) or value.get('selection') != provenance.read_json(root / 'selection.json'):
        raise ValueError('Resumed report does not belong to its prepared run')
    frozen = provenance.read_json(root / 'snapshot-hashes.json')
    if frozen.get('selection.json') != provenance.digest(root / 'selection.json'):
        raise ValueError('Resumed selection differs from the bound snapshot')
    reference = dict(report=str(root / 'report.json'), report_sha256=provenance.digest(root / 'report.json'),
                     execution_seal_sha256=provenance.digest(root / provenance.EXECUTION_SEAL))
    if provenance.read_json(root / 'report.json') != value:
        raise ValueError('Saved resumed report differs from the accounted result')
    if value.get('status') not in ('passed', 'failed', 'needs-review'):
        raise ValueError('Invalid resumed report status')
    if value['status'] == 'passed' and (value.get('provenance', {}).get('verified') is not True
            or value.get('functional', {}).get('status') != 'passed'):
        raise ValueError('Campaign resume requires a verified functional pass')

    def resumed(original):
        result = {key: deepcopy(item) for key, item in original.items()
                  if key not in ('error', 'setup_failure', 'attempts')}
        result.update(status=value['status'], functional=value['functional']['status'],
                      runtime=value['runtime']['status'], **reference)
        result['attempts'] = [deepcopy(original), dict(kind='resume', run=str(root), status=value['status'], **reference)]
        return result

    with _locked(path):
        accounting = provenance.read_json(path)
        rows = _rows(accounting, root)
        if rows != context['rows']:
            raise ValueError('Batch unit accounting changed while resuming')
        identifiers = {row['id'] for row in rows}
        accounting['jobs'] = [resumed(row) if row.get('id') in identifiers else row for row in accounting['jobs']]
        accounting['sessions'] = [resumed(unit) if unit.get('run') == str(root) else unit
                                   for unit in accounting['sessions']]
        stop_reason = accounting.get('stop_reason')
        if isinstance(stop_reason, dict) and stop_reason.get('job') in identifiers:
            accounting.setdefault('stop_history', []).append(deepcopy(accounting['stop_reason']))
            accounting['stop_reason'] = None
        accounting['campaign'] = campaign.refresh(accounting.get('campaign'), accounting['jobs'])
        accounting['status'] = _status(accounting)
        coverage = _coverage(accounting, catalog)
        # The accounting report is authoritative; publish it last after coverage is ready.
        _atomic_json(path.parent / 'coverage.json', coverage)
        _atomic_json(path, accounting)
    return path
