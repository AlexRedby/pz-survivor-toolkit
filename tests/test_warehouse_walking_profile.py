import copy
import os
from pathlib import Path
import tempfile
import unittest

from tools.queue_checks.adapters import warehouse_walking_profile as observer

ROOT = Path(__file__).resolve().parents[1]


def receipt():
    metrics = [dict(name=name, source='consumer.lua', first_line=index+1,
                    calls=1, inclusive_ms=1, exclusive_ms=.5, max_ms=1)
               for index, name in enumerate(('page.refreshBackpacks', 'pane.refreshContainer',
                   'pane.restoreSelection', 'pane.itemSortFunc', 'rows.restoreSelection',
                   'filter.choices', 'categoryRules.forItem', 'categories.prepareContainer'))]
    return dict(**observer.SCOPE_DETAILS, phase=1, index=1, clock='nanoTime', elapsed_ms=100,
                scope='registered-native-lua-calls', identities_unchanged=True,
                observer_overhead_included=True, hooks=dict(init=20, shrink=20), metrics=metrics)


class WarehouseWalkingObserverChecks(unittest.TestCase):
    def test_valid_and_hidden_rows(self):
        value = receipt()
        for row in value['metrics'][1:]:
            row.update(calls=0, inclusive_ms=0, exclusive_ms=0, max_ms=0)
        self.assertIs(observer.verify_profile(value), value)
        self.assertIs(observer.verify_profile(value, 1), value)
        with self.assertRaises(ValueError):
            observer.verify_profile(value, 2)

    def test_incompatible_capture_rejected(self):
        for key, bad in [('clock', 'milliseconds'), ('index', 17), ('phase', 2),
                         ('phase', True), ('hooks', []), ('elapsed_ms', float('nan')), ('identities_unchanged', False),
                         ('observer_overhead_included', False), ('hooks', dict(init=2, shrink=0)),
                         ('metrics', []), ('tail_calls', 'whole-chain'),
                         ('receiver_scope', 'per-page'), ('exclusive_scope', 'all-lua-children'), ('registration', 'all-closures')]:
            with self.subTest(key=key):
                value = receipt(); value[key] = bad
                with self.assertRaises(ValueError):
                    observer.verify_profile(value)

    def test_invalid_nested_metrics_rejected(self):
        for key, bad in [('inclusive_ms', float('inf')), ('exclusive_ms', 2), ('max_ms', 2),
                         ('calls', -1), ('calls', 0), ('first_line', -1), ('source', '')]:
            with self.subTest(key=key, bad=bad):
                value = receipt(); value['metrics'][0][key] = bad
                with self.assertRaises(ValueError):
                    observer.verify_profile(value)
        value = receipt(); value['metrics'].append(copy.deepcopy(value['metrics'][0]))
        with self.assertRaises(ValueError):
            observer.verify_profile(value)
        value = receipt(); value['metrics'][0].update(calls=0, inclusive_ms=0, exclusive_ms=0, max_ms=0)
        with self.assertRaisesRegex(ValueError, 'discovery'):
            observer.verify_profile(value)

    def test_wall_interval_and_invocation_bounds(self):
        value = receipt(); row = value['metrics'][0]
        row.update(inclusive_ms=101, exclusive_ms=0, max_ms=101)
        with self.assertRaisesRegex(ValueError, 'invocation exceeds'):
            observer.verify_profile(value)
        value = receipt(); value['metrics'][0].update(inclusive_ms=2, exclusive_ms=0, max_ms=1)
        with self.assertRaisesRegex(ValueError, 'calls times maximum'):
            observer.verify_profile(value)
        value = receipt(); value['elapsed_ms'] = 3.5
        with self.assertRaisesRegex(ValueError, 'exclusive durations'):
            observer.verify_profile(value)
        # Inclusive spans can overlap across registered ancestors and descendants.
        value = receipt(); value['elapsed_ms'] = 10
        for row in value['metrics']:
            row.update(inclusive_ms=10, exclusive_ms=1, max_ms=10)
        observer.verify_profile(value)

    def test_nanosecond_rounding_allowance_is_absolute(self):
        epsilon = observer.TIMING_EPSILON_MS
        value = receipt(); value['metrics'][0].update(inclusive_ms=1 + epsilon / 2)
        observer.verify_profile(value)
        value['metrics'][0]['inclusive_ms'] = 1 + epsilon * 2
        with self.assertRaises(ValueError):
            observer.verify_profile(value)
        value = receipt(); value['elapsed_ms'] = 4 - epsilon / 2
        observer.verify_profile(value)
        value['elapsed_ms'] = 4 - epsilon * 2
        with self.assertRaises(ValueError):
            observer.verify_profile(value)
        value = receipt(); value['elapsed_ms'] = 100 - epsilon / 2
        value['metrics'][0].update(inclusive_ms=100, exclusive_ms=0, max_ms=100)
        observer.verify_profile(value)
        value['elapsed_ms'] = 100 - epsilon * 2
        with self.assertRaises(ValueError):
            observer.verify_profile(value)

    @unittest.skipUnless(os.environ.get('PZ_GAME') and os.environ.get('PZ_JDK'),
                         'PZ_GAME/PZ_JDK required for installed native Kahlua/ZombieBuddy test')
    def test_real_native_kahlua_nested_timing(self):
        with tempfile.TemporaryDirectory(prefix='pz-warehouse-observer-test-') as temporary:
            observer.compile_check(ROOT, Path(os.environ['PZ_GAME']), Path(os.environ['PZ_JDK']), Path(temporary))


if __name__ == '__main__':
    unittest.main()
