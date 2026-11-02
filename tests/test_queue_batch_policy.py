"""Only explicit infrastructure evidence invalidates an ordinary comparison control."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import batch_policy, report


class BatchPolicyTests(unittest.TestCase):
    def test_gameplay_and_dirty_runtime_are_not_setup_evidence(self):
        for execution in ({'status': 'failed', 'error': 'preflight mentioned by gameplay'},
                          {'status': 'completed', 'runtime': {'status': 'dirty'}}, None):
            self.assertIsNone(batch_policy.setup_failure(execution))

    def test_declared_but_malformed_setup_evidence_fails_closed(self):
        for finding in (None, [], {}, {'kind': 'x', 'phase': 'y', 'reason': ''}):
            with self.subTest(finding=finding):
                execution = dict(status='completed', setup_failure=finding)
                self.assertIsNotNone(batch_policy.setup_failure(execution))
                issues = report.execution_issues(Path.cwd(), {'suite': 'health', 'kind': 'sp'}, execution)
                self.assertTrue(any('Setup failure:' in issue for issue in issues))

    def test_fixture_load_evidence_is_preserved_and_invalidates_completion(self):
        finding = dict(kind='runtime', role='client2', file='ZZFixture.lua', block='load failed')
        execution = dict(status='completed', fixture_load_error=finding)
        result = batch_policy.setup_failure(execution)
        self.assertEqual(finding, result['evidence'])
        issues = report.execution_issues(Path.cwd(), {'suite': 'health', 'kind': 'sp'}, execution)
        self.assertTrue(any('Setup failure:' in issue for issue in issues))

    def test_job_policy_cannot_silently_override_the_batch(self):
        with self.assertRaises(ValueError):
            batch_policy.resolve({'jobs': [{'failure_policy': 'continue'}]})

    def test_declared_barrier_requires_all_roles_and_both_releases(self):
        selection = dict(suite='health', kind='mp')
        barrier = dict(required_roles=['client1', 'client2'], setup_released=True, released=True,
                       ready={'client1': {'line': 1}, 'client2': {'line': 1}},
                       fixture_setup={'client1': {'line': 2}, 'client2': {'line': 2}})
        execution = dict(status='completed', preflight=barrier,
                         processes={role: dict(pid=123, exit_code=0) for role in ('server', 'client1', 'client2')})
        self.assertEqual([], report.execution_issues(Path.cwd(), selection, execution))
        for key, value in (('ready', {'client1': {}}), ('fixture_setup', {}), ('released', False),
                           ('setup_released', False), ('required_roles', ['client1'])):
            with self.subTest(key=key):
                invalid = dict(execution, preflight=dict(barrier, **{key: value}))
                self.assertTrue(report.execution_issues(Path.cwd(), selection, invalid))
        self.assertFalse(report.execution_issues(Path.cwd(), selection,
            {key: value for key, value in execution.items() if key != 'preflight'}), 'legacy report compatibility')


if __name__ == '__main__':
    unittest.main()
