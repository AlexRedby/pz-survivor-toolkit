"""Receipts cannot substitute coordinates, square witnesses, roles or settling."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import placement


def proof(mode='local'):
    target = dict(x=12, y=34, z=0)
    actual = dict(x=12.5, y=34.5, z=0, square=dict(target), currentSquare=dict(target))
    if mode == 'local':
        actual.update(queued=0, timed=False, moving=False, hasPath=False, deferredX=0, deferredY=0)
    return dict(mode=mode, target=target, actual=actual, teleports=1 if mode == 'local' else 0,
                stableMs=500, quietMs=500 if mode == 'local' else 0, elapsedMs=1001)


class PlacementProofTests(unittest.TestCase):
    def test_centered_receipts_require_explicit_mode_and_centered_coordinates(self):
        for mode in ('local', 'replica'):
            for offset in (.41, .5, .59):
                value = proof(mode)
                value.update(centered=True, centers=1 if mode == 'local' else 0)
                value['actual'].update(x=12 + offset, y=34 + offset)
                self.assertIs(value, placement.validate(value, value['target'], mode, centered=True))
                with self.assertRaisesRegex(ValueError, 'fields'):
                    placement.validate(value, value['target'], mode)
            with self.assertRaisesRegex(ValueError, 'fields'):
                value = proof(mode)
                placement.validate(value, value['target'], mode, centered=True)

    def test_centered_schema_counts_roles_corners_and_existing_gates(self):
        mutations = [lambda p: p.update(centered=False), lambda p: p.update(centered=1),
                     lambda p: p.pop('centered'), lambda p: p.pop('centers'),
                     lambda p: p.update(centers=True), lambda p: p.update(centers=-1),
                     lambda p: p.update(mode='unknown'), lambda p: p.update(extra=True),
                     lambda p: p['actual'].update(x=12), lambda p: p['actual'].update(y=34),
                     lambda p: p['actual'].update(x=12.39), lambda p: p['actual'].update(y=34.61),
                     lambda p: p['actual']['square'].update(x=13),
                     lambda p: p['actual']['currentSquare'].update(y=35),
                     lambda p: p['actual'].update(z=.5), lambda p: p.update(stableMs=499),
                     lambda p: p.update(elapsedMs=30000), lambda p: p.update(elapsedMs=0),
                     lambda p: p['target'].update(x=13)]
        for mode in ('local', 'replica'):
            role_mutations = mutations + [lambda p: p.update(centers=0 if mode == 'local' else 1),
                                          lambda p: p.update(teleports=0 if mode == 'local' else 1),
                                          lambda p: p.update(quietMs=0 if mode == 'local' else 500)]
            if mode == 'local':
                role_mutations += [lambda p: p['actual'].update(moving=True),
                                   lambda p: p['actual'].update(deferredX=.01),
                                   lambda p: p['actual'].update(timed=True),
                                   lambda p: p['actual'].update(queued=1),
                                   lambda p: p['actual'].update(hasPath=True)]
            for change in role_mutations:
                value = proof(mode)
                value.update(centered=True, centers=1 if mode == 'local' else 0)
                change(value)
                with self.subTest(mode=mode, value=value), self.assertRaises(ValueError):
                    placement.validate(value, dict(x=12, y=34, z=0), mode, centered=True)

    def test_native_corner_and_centre_receipts_from_both_roles(self):
        for mode in ('local', 'replica'):
            for offset in (0, .5):
                value = proof(mode)
                value['actual'].update(x=12 + offset, y=34 + offset)
                self.assertIs(value, placement.validate(value, value['target'], mode))

    def test_role_target_timing_movement_and_both_squares_are_required(self):
        mutations = [lambda p: p.update(mode='replica'), lambda p: p.update(teleports=0),
                     lambda p: p.update(teleports=True), lambda p: p.update(stableMs=499),
                     lambda p: p.update(quietMs=499), lambda p: p.update(elapsedMs=30000),
                     lambda p: p.update(elapsedMs=999), lambda p: p.update(stableMs=float('nan')),
                     lambda p: p['target'].update(x=13), lambda p: p['target'].update(z=False),
                     lambda p: p['actual'].update(x=13),
                     lambda p: p['actual'].update(z=.5), lambda p: p['actual'].update(x=float('inf')),
                     lambda p: p['actual'].update(square=False),
                     lambda p: p['actual']['currentSquare'].update(y=35),
                     lambda p: p['actual'].update(moving=True), lambda p: p['actual'].update(timed=True),
                     lambda p: p['actual'].update(hasPath=True), lambda p: p['actual'].update(queued=1),
                     lambda p: p['actual'].update(deferredX=.01),
                     lambda p: p['actual'].pop('deferredY'), lambda p: p.update(arrived=True)]
        for change in mutations:
            value = proof()
            change(value)
            with self.subTest(value=value), self.assertRaises(ValueError):
                placement.validate(value, dict(x=12, y=34, z=0), 'local')

    def test_authority_receipt_never_authorizes_a_remote_teleport(self):
        value = proof('replica')
        value['teleports'] = 1
        with self.assertRaisesRegex(ValueError, 'teleports'):
            placement.validate(value, value['target'], 'replica')
        value = proof('replica')
        value['quietMs'] = 500
        with self.assertRaisesRegex(ValueError, 'unsettled'):
            placement.validate(value, value['target'], 'replica')


if __name__ == '__main__':
    unittest.main()
