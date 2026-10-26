"""Per-case native client topology must be explicit and cannot be mixed."""
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import check_action_queue as cli
from queue_checks.adapters import craft_ui


class JoinedSelectionTests(unittest.TestCase):
    def select(self, cases, kind='mp', catalog=None):
        args = SimpleNamespace(suite='craft-ui', cases=','.join(cases), kind=kind, mode='native',
                               scenarios=None, actions=None, mods=None, language=None, config=None,
                               mod_source=[], resources={}, timeout=600, ports=None)
        return cli.selection(args, catalog or {'suites': craft_ui.definitions()}, options={'mp_host': True})

    def test_joined_case_uses_two_real_clients_and_only_declared_actor(self):
        selection = self.select(craft_ui.JOINED_CASES)
        self.assertEqual((2, ['EN', 'RU'], 'client2'),
                         tuple(selection[key] for key in ('clients', 'languages', 'actor')))
        craft_ui.validate(selection)

    def test_existing_cases_keep_the_one_client_default_and_selection_shape(self):
        selection = self.select(['context', 'cook-batch'])
        self.assertEqual(1, selection['clients'])
        self.assertEqual(['EN'], selection['languages'])
        self.assertNotIn('actor', selection)
        craft_ui.validate(selection)

    def test_mixed_joined_and_owner_topologies_fail_before_preparation(self):
        with self.assertRaisesRegex(ValueError, 'different client topologies'):
            self.select(['context', craft_ui.JOINED_CASES[0]])

    def test_role_mismatch_is_rejected_even_with_equal_client_counts(self):
        catalog = {'suites': {'craft-ui': {'status': 'ready', 'clients': 2, 'default_mods': [], 'cases': [
            dict(id='first', actor='client1', kinds=['mp']),
            dict(id='second', actor='client2', kinds=['mp'])]}}}
        with self.assertRaisesRegex(ValueError, 'different actor roles'):
            self.select(['first', 'second'], catalog=catalog)

    def test_joined_case_does_not_become_single_player_by_overriding_kind(self):
        with self.assertRaisesRegex(ValueError, 'Unsupported kind'):
            self.select([craft_ui.JOINED_CASES[0]], kind='sp')


if __name__ == '__main__':
    unittest.main()
