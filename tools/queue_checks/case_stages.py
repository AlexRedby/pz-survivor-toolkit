"""Opt-in, run-bound case boundaries; gameplay text never implies setup failure."""
import json
from pathlib import Path
import re

from . import adapters

PREFIX = '[QUEUE_CASE_STAGE] '


class CaseStages:
    def __init__(self, runtime, selection):
        fixture = runtime.get('fixture', {}) if isinstance(runtime, dict) else None
        if not isinstance(fixture, dict):
            raise ValueError('Invalid prepared fixture metadata')
        contract = fixture.get('case_stages')
        self.enabled = 'case_stages' in fixture
        self.suite = selection['suite']
        self.roles = adapters.roles(selection, False)
        self.cases = selection.get('cases', [])
        preflight = fixture.get('preflight', {})
        self.token = preflight.get('token') if isinstance(preflight, dict) else None
        if self.enabled and (contract != {'version': 1} or type(contract.get('version')) is not int
                or not isinstance(self.token, str) or not re.fullmatch('[a-f0-9]{32}', self.token)
                or not isinstance(self.cases, list) or not self.cases
                or any(not isinstance(case, str) or not case for case in self.cases)
                or len(set(self.cases)) != len(self.cases)):
            raise ValueError('Invalid prepared case-stage contract; prepare a fresh snapshot')

    @staticmethod
    def failure(execution, role, case, stage, reason, line=None, *, protocol=False):
        finding = dict(kind='fixture-case-stage-protocol' if protocol else 'fixture-case-' + stage,
                       phase='case-stage-audit' if protocol else 'fixture-' + stage,
                       role=role, case=case, reason=str(reason), evidence=dict(stage=stage, line=line))
        execution.setdefault('setup_failure', finding)
        raise RuntimeError(str(reason))

    def check(self, logs, execution, *, final=False):
        if not self.enabled:
            return
        # Import after report's module initialization (the report also audits stages).
        from .preflight import LUA_LOG
        from .report import STAMP
        evidence = dict(version=1, receipts={role: [] for role in self.roles})
        execution['case_stages'] = evidence
        active = {}
        completed = {}
        gameplay_failure = None
        for role in self.roles:
            text = logs.get(role, '')
            lines = text.splitlines() if final else text.rsplit('\n', 1)[0].splitlines() if '\n' in text else []
            index, current, failed = 0, None, False
            for number, raw in enumerate(lines, 1):
                line = LUA_LOG.sub('', STAMP.sub('', raw))
                if not line.startswith(PREFIX):
                    continue
                case = self.cases[index] if index < len(self.cases) else None
                def invalid(reason):
                    self.failure(execution, role, case, current, reason, number, protocol=True)
                try:
                    row = json.loads(line[len(PREFIX):])
                except (ValueError, TypeError):
                    invalid('Malformed case-stage receipt')
                if (not isinstance(row, dict) or row.get('token') != self.token or row.get('suite') != self.suite
                        or row.get('role') != role or row.get('case') != case or case is None
                        or row.get('stage') not in ('setup', 'gameplay', 'cleanup')
                        or row.get('status') not in ('started', 'passed', 'failed')
                        or set(row) != {'token', 'suite', 'role', 'case', 'stage', 'status'} | (
                            {'reason'} if row.get('status') == 'failed' else set())):
                    invalid('Mismatched case-stage receipt')
                stage, status = row['stage'], row['status']
                if failed:
                    invalid('Case-stage receipt followed a terminal failure')
                if status == 'failed':
                    if current != stage or not isinstance(row.get('reason'), str) or not row['reason'].strip():
                        invalid('Invalid case-stage failure')
                    failed = True
                elif status == 'passed':
                    if stage != 'cleanup' or current != 'cleanup':
                        invalid('Invalid case-stage completion')
                    index += 1
                    current = None
                else:
                    expected = {None: 'setup', 'setup': 'gameplay', 'gameplay': 'cleanup'}.get(current)
                    if stage != expected:
                        invalid('Duplicated or out-of-order case-stage transition')
                    current = stage
                evidence['receipts'][role].append(dict(row, line=number))
                if status == 'failed' and stage != 'gameplay':
                    self.failure(execution, role, case, stage, row['reason'], number)
                if status == 'failed':
                    gameplay_failure = row['reason']
            active[role] = (self.cases[index] if index < len(self.cases) else None, current)
            completed[role] = index
        if final:
            # A process/timeout failure during setup or cleanup is still structured
            # infrastructure failure even when Lua could not emit its own failure.
            for role, (case, stage) in active.items():
                if execution.get('status') != 'completed' and stage in ('setup', 'cleanup'):
                    self.failure(execution, role, case, stage,
                                 execution.get('error') or 'Execution stopped during case ' + stage)
            for role in self.roles:
                if not evidence['receipts'][role]:
                    self.failure(execution, role, self.cases[0], None,
                                 'Missing required case-stage receipts', protocol=True)
        if gameplay_failure:
            raise RuntimeError(gameplay_failure)
        if final:
            # Failed gameplay may stop before cleanup or before the next case.
            # Completed executions, however, need every declared cleanup receipt.
            if execution.get('status') == 'completed':
                for role, count in completed.items():
                    if count != len(self.cases):
                        case, stage = active[role]
                        self.failure(execution, role, case, stage, 'Missing required case-stage completion', protocol=True)


def audit(root, selection, execution):
    """Reconstruct stage evidence without changing the sealed execution record."""
    root = Path(root)
    runtime_path = root / 'runtime.json'
    if not runtime_path.is_file():
        return None, []  # Historical reports without an opted-in contract.
    checked = dict(execution)
    try:
        runtime = json.loads(runtime_path.read_text())
        tracker = CaseStages(runtime, selection)
        if not tracker.enabled:
            return None, []
        logs = {role: (root / (role + '-launch.log')).read_text(errors='replace')
                if (root / (role + '-launch.log')).is_file() else '' for role in tracker.roles}
        tracker.check(logs, checked, final=True)
    except RuntimeError as error:
        return checked.get('setup_failure'), ['Case stage failure: ' + str(error)]
    except (OSError, ValueError) as error:
        finding = checked.get('setup_failure') or dict(kind='fixture-case-stage-protocol', phase='case-stage-audit', reason=str(error))
        return finding, ['Case stage failure: ' + str(error)]
    return None, []
