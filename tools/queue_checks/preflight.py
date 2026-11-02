"""Fresh, role-bound client readiness receipts and the fixture start barrier."""
import json
from pathlib import Path
import re

from . import adapters
from .report import STAMP


PREFIX = '[QUEUE_PREFLIGHT] '
RELEASE = 'queue-preflight-release.txt'
SETUP = 'queue-preflight-setup.txt'
LUA_LOG = re.compile(r'^\s*LOG\s*:\s*Lua\b[^>\r\n]*>\s*')


def fail(execution, kind, role, phase, reason, **evidence):
    """Preserve the first setup failure, including when later cleanup also fails."""
    finding = dict(kind=kind, role=role, phase=phase, reason=str(reason))
    if evidence:
        finding['evidence'] = evidence
    execution.setdefault('setup_failure', finding)
    raise RuntimeError(str(reason))


class ClientPreflight:
    def __init__(self, root, runtime, selection):
        self.root, self.runtime = Path(root), runtime
        config = runtime.get('fixture', {}).get('preflight')
        if (not isinstance(config, dict) or type(config.get('version')) is not int or config['version'] != 1
                or not isinstance(config.get('token'), str)
                or not re.fullmatch('[a-f0-9]{32}', config['token'])
                or config.get('roles') != adapters.roles(selection, False)):
            raise ValueError('Prepared client preflight barrier is missing or invalid; prepare a fresh snapshot')
        self.token, self.roles = config['token'], config['roles']
        self.setup_released, self.released = False, False
        for role in self.roles:
            for name in (SETUP, RELEASE):
                path = self.release_path(role, name)
                if path.exists() or path.is_symlink():
                    raise ValueError('Prepared client preflight release already exists: ' + role)

    def release_path(self, role, name=RELEASE):
        cache = Path(self.runtime['roles'][role]['cache'])
        if (cache.resolve() != (self.root / role).resolve() or cache.is_symlink() or (cache / 'Lua').is_symlink()
                or not (cache / 'Lua').is_dir()):
            raise ValueError('Client preflight cache must belong to its run role: ' + role)
        return cache / 'Lua' / name

    def check(self, logs, execution, *, release=True):
        ready, setup = {}, {}
        execution['preflight'] = {'required_roles': self.roles, 'ready': ready, 'fixture_setup': setup,
                                  'setup_released': self.setup_released, 'released': self.released}
        # Inspect all roles before granting any release. Failure always wins over
        # a successful receipt or fixture completion in the same log snapshot.
        for role in self.roles:
            complete = logs.get(role, '').rsplit('\n', 1)[0].splitlines() if '\n' in logs.get(role, '') else []
            for number, raw in enumerate(complete, 1):
                line = LUA_LOG.sub('', STAMP.sub('', raw))
                if not line.startswith(PREFIX):
                    # Historical release preflight failures remain fatal even
                    # if a fixture prints completion later in the same dispatch.
                    if '[QUEUE_TEST] FAIL release preflight ' in line:
                        fail(execution, 'client-preflight', role, 'preflight',
                             line.split('[QUEUE_TEST] FAIL release preflight ', 1)[1], line=number)
                    continue
                try:
                    row = json.loads(line[len(PREFIX):])
                except (ValueError, TypeError):
                    fail(execution, 'preflight-protocol', role, 'preflight', 'Malformed client preflight receipt', line=number)
                if (not isinstance(row, dict) or row.get('token') != self.token
                        or row.get('role') != role or row.get('event') not in ('ready', 'setup-ready', 'failed')):
                    fail(execution, 'preflight-protocol', role, 'preflight', 'Mismatched client preflight receipt', line=number)
                if row['event'] == 'failed':
                    if row.get('phase') not in ('preflight', 'fixture-setup') or not isinstance(row.get('reason'), str) or not row['reason'].strip():
                        fail(execution, 'preflight-protocol', role, 'preflight', 'Invalid client preflight failure', line=number)
                    fail(execution, 'client-preflight' if row['phase'] == 'preflight' else 'fixture-setup', role,
                         row['phase'], row['reason'], line=number)
                if row['event'] == 'setup-ready':
                    if role not in ready or not self.setup_released:
                        fail(execution, 'preflight-protocol', role, 'fixture-setup', 'Fixture setup preceded required preflights', line=number)
                    setup[role] = {'line': number}
                else:
                    ready[role] = {'line': number}
        if release and not self.setup_released and len(ready) == len(self.roles):
            self.grant(SETUP)
            self.setup_released = True
            execution['preflight']['setup_released'] = True
        if release and not self.released and len(setup) == len(self.roles):
            self.grant(RELEASE)
            self.released = True
            execution['preflight']['released'] = True
        return self.released

    def grant(self, name):
        # The Lua readers require the complete token line. Atomic rename
        # prevents observation of a partial grant while native callbacks run.
        for role in self.roles:
            target = self.release_path(role, name)
            temporary = target.with_suffix('.tmp')
            if target.exists() or target.is_symlink():
                raise RuntimeError('Client preflight grant appeared before runner release: ' + role)
            with temporary.open('x', encoding='utf-8') as stream:
                stream.write(self.token + '\n')
            temporary.replace(target)

    def pending(self):
        return not self.released

    def failure(self, execution, reason):
        phase = 'fixture-setup' if self.setup_released else 'preflight'
        receipts = execution.get('preflight', {}).get('fixture_setup' if self.setup_released else 'ready', {})
        role = next((role for role in self.roles if role not in receipts), self.roles[0])
        fail(execution, 'fixture-setup' if self.setup_released else 'client-preflight', role, phase, reason)

    def record_exception(self, execution, error):
        if not self.pending() or isinstance(error, KeyboardInterrupt) or execution.get('fixture_load_error'):
            return
        phase = 'fixture-setup' if self.setup_released else 'readiness'
        receipts = execution.get('preflight', {}).get('fixture_setup' if self.setup_released else 'ready', {})
        role = next((role for role in self.roles if role not in receipts), self.roles[0])
        execution.setdefault('setup_failure', {'kind': 'fixture-setup' if self.setup_released else 'native-readiness',
                                              'role': role, 'phase': phase, 'reason': str(error)})
