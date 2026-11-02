"""Source-bound offline qualification before Host container-borrowing banks."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from . import preparation_process
from .mod_selection import mod_layers

TEST = 'test_action_queue_borrowing_composition.lua'
CHECKS = ('plain', 'singleton-guarded', 'merge-preserving', 'return-failure')
FITNESS_CASES = {'closed-ui-restore', 'empty-restore', 'active-cancel-restore',
                 'pickup-cancel-restore', 'placement-cancel-restore', 'storage-walk-away',
                 'storage-peer-pickup', 'multi-storage', 'multi-storage-closed'}
EQUIPMENT_PICKUP_CASES = {'waiting-cancel', 'bag-capacity', 'hotbar-chain', 'belt-knife',
                          'belt-hammer', 'bulk-pickup', 'bulk-waiting-cancel'}


def required(selection):
    if (selection.get('kind') != 'mp' or selection.get('options', {}).get('mp_host') is not True
            or not {'PZSurvivorToolkit', 'P4TidyUpMeister'}.issubset(selection['mods'])):
        return False
    cases = set(selection['cases'])
    if selection['suite'] == 'book-controls':
        return any(case.startswith(('worn-bag.', 'world.')) for case in cases)
    if selection['suite'] == 'equipment':
        from .adapters.equipment import TIDY_RETURN_CASES
        return bool(cases.intersection(TIDY_RETURN_CASES | EQUIPMENT_PICKUP_CASES))
    return selection['suite'] == 'fitness' and bool(cases.intersection(FITNESS_CASES))


def sources(project):
    project = Path(project)
    return [project / 'tools/run_tests.py', project / 'tools/mod_integrations.py',
            project / 'tests' / TEST, project / 'tests/support/borrowing_composition.lua',
            project / 'tests/support/source_binding.lua']


def qualify(project, game, locations):
    """Use selected candidate bytes, never rediscover installed mod fallbacks."""
    project, game = Path(project), Path(game)
    for path in sources(project):
        if not path.is_file():
            raise ValueError('Missing borrowing composition source: ' + str(path))
    toolkit = Path(locations['PZSurvivorToolkit'])
    p4 = Path(locations['P4TidyUpMeister'])
    # An explicit content root must describe the same effective overlay as the
    # game. Materialize only its three declared upstream files in the private
    # check directory, rather than silently ignoring common-layer overrides.
    relative = ('media/lua/client/P4TidyUpMeister.lua',
                'media/lua/shared/TimedActions/P4RestoreAction.lua',
                'media/lua/shared/TimedActions/P4RestoreFloorAction.lua')
    with tempfile.TemporaryDirectory(prefix='pz-borrowing-check-') as directory:
        root = Path(directory)
        for name in relative:
            source = next((layer / name for layer in reversed(mod_layers(p4)) if (layer / name).is_file()), None)
            if source is None:
                raise ValueError('Missing selected P4 borrowing source: ' + name)
            target = root / 'p4' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
        output = root / 'report.json'
        command = [sys.executable, str(project / 'tools/run_tests.py'), '--test', TEST,
                   '--native-action-root', str(game / 'media/lua'), '--p4-source', str(root / 'p4'),
                   '--toolkit-source', str(toolkit), '--require-complete', '--report', str(output)]
        try:
            result = preparation_process.run(command, cwd=project, capture_output=True, text=True,
                                             check=True, timeout=120)
            value = json.loads(output.read_text(encoding='utf-8'))
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            detail = getattr(error, 'stderr', None) or str(error)
            if isinstance(detail, bytes):
                detail = detail.decode('utf-8', errors='replace')
            raise ValueError('Borrowing composition preflight failed: ' + detail[-6000:]) from error
        rows = value.get('results') if isinstance(value, dict) else None
        if (not isinstance(value, dict) or value.get('status') != 'passed' or value.get('require_complete') is not True
                or not isinstance(rows, list) or len(rows) != 1
                or not isinstance(rows[0], dict)
                or rows[0].get('test') != TEST or rows[0].get('status') != 'passed'
                or rows[0].get('variant') != 'default'
                or rows[0].get('checks') != [{'id': key, 'status': 'passed', 'reason': None} for key in CHECKS]):
            raise ValueError('Borrowing composition preflight requires all four completed source checks')
        return value, result.stdout + result.stderr
