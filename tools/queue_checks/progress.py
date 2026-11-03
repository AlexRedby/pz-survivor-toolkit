"""Throttled diagnostic progress; stdout remains available for JSON protocols."""
from contextvars import ContextVar
from functools import wraps
import hashlib
import json
from pathlib import Path
import re
import sys
import time


INTERVAL_SECONDS = 5
_CURRENT = ContextVar('native_progress', default=None)


class Phase:
    def __init__(self, name, *, total=None, clock=None, stream=None, **fields):
        self.name, self.total, self.completed = name, total, 0
        self.clock, self.stream = clock or time.perf_counter, stream
        self.started, self.last = self.clock(), None
        parent = _CURRENT.get()
        inherited = {key: value for key, value in parent.fields.items() if key in ('suite', 'role', 'run')} if parent else {}
        self.fields = dict(inherited, **fields)
        self.token = None

    def __enter__(self):
        self.token = _CURRENT.set(self)
        self.update(force=True)
        return self

    def update(self, *, force=False, status='running', **fields):
        self.fields.update(fields)
        now = self.clock()
        if not force and self.last is not None and now - self.last < INTERVAL_SECONDS:
            return
        self.last = now
        values = dict(phase=self.name, status=status, elapsed_seconds=round(now - self.started, 1), **self.fields)
        if self.total is not None:
            values['files'] = str(self.completed) + '/' + str(self.total)
        elif self.completed:
            values['files'] = self.completed
        line = 'PROGRESS ' + ' '.join(key + '=' + json.dumps(value, ensure_ascii=False)
            for key, value in values.items() if value is not None)
        try:
            print(line, file=self.stream or sys.stderr, flush=True)
        except (OSError, ValueError):
            pass  # A closed diagnostic stream cannot alter admission or cleanup.

    def step(self, detail=None):
        self.completed += 1
        self.update(detail=str(detail)[-160:] if detail is not None else None)

    def finish(self, status='done'):
        self.update(force=True, status=status)

    def __exit__(self, kind, error, traceback):
        try:
            self.finish('failed' if kind else 'done')
        finally:
            _CURRENT.reset(self.token)


def file(path):
    current = _CURRENT.get()
    if current is not None:
        current.step(Path(path).name)


def pulse(path):
    current = _CURRENT.get()
    if current is not None:
        current.update(detail=Path(path).name)


def hash_file(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
            pulse(path)
    return value.hexdigest()


def total(count, **fields):
    current = _CURRENT.get()
    if current is not None:
        current.total = count
        current.update(force=True, **fields)


def operation(name):
    def decorate(function):
        @wraps(function)
        def wrapped(*args, **kwargs):
            selection = next((value for value in (*args, *kwargs.values())
                              if isinstance(value, dict) and isinstance(value.get('suite'), str)), {})
            with Phase(name, suite=selection.get('suite')):
                return function(*args, **kwargs)
        return wrapped
    return decorate


_STAGE = re.compile(r'\[(?:STORAGE_PROFILE|SMART_DEPOSIT(?:_HOST)?|ITEM_CATALOG|FOOD_TEST)\]\s+(\w+)(?:\s+(.*))?')


class Fixture:
    """Summarize already observed fixture logs; never query or mutate the game."""
    def __init__(self, selection, *, clock=None, stream=None):
        self.selection, self.clock, self.stream = selection, clock, stream
        self.phase = None

    def update(self, logs, execution):
        barrier = execution.get('preflight', {})
        state = 'gameplay' if barrier.get('released') else 'fixture-setup' if barrier.get('setup_released') else 'client-readiness'
        changed = self.phase is None or self.phase.name != state
        if changed:
            if self.phase is not None:
                self.phase.finish()
            self.phase = Phase(state, suite=self.selection['suite'], clock=self.clock, stream=self.stream)
        timing = barrier.get('timing', {})
        elapsed = timing.get('setup_elapsed_seconds' if state == 'fixture-setup' else 'gameplay_elapsed_seconds')
        limit = timing.get('setup_timeout_seconds') if state == 'fixture-setup' else self.selection['timeout_seconds']
        fields = dict(ready=len(barrier.get('ready', {})), setup_ready=len(barrier.get('fixture_setup', {})),
                      clients=len(barrier.get('required_roles', [])),
                      remaining_seconds=round(max(0, limit - elapsed), 1) if elapsed is not None and limit is not None else None)
        # Only inspect a bounded tail and scalar counters. Do not echo fixture
        # payloads, saved state, item collections or whole timing observations.
        for role, text in logs.items():
            for line in text[-16384:].splitlines()[-100:]:
                match = _STAGE.search(line)
                if not match:
                    continue
                fields.update(role=role, stage=match[1])
                try:
                    row = json.loads(match[2]) if match[2] and match[2].startswith('{') else dict(
                        re.findall(r'\b(phase|completed|total|items|crates|skipped)=(\w+)', match[2] or ''))
                except ValueError:
                    continue
                if isinstance(row, dict):
                    for key in ('index', 'count', 'target', 'stage', 'phase', 'total', 'completed', 'items', 'crates', 'skipped', 'case'):
                        value = row.get(key)
                        if type(value) in (int, float, str) and len(str(value)) <= 80:
                            fields['fixture_' + key] = value
        self.phase.update(force=changed, **fields)

    def finish(self, status):
        if self.phase is not None:
            self.phase.finish(status)
