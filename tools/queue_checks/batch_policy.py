"""Explicit batch failure policy and structured setup evidence."""

POLICIES = ('continue', 'stop-on-setup-failure')


def resolve(plan, override=None):
    configured = plan.get('failure_policy', 'continue')
    if configured not in POLICIES or (override is not None and override not in POLICIES):
        raise ValueError('failure_policy must be one of: ' + ', '.join(POLICIES))
    if any('failure_policy' in job for job in plan.get('jobs', [])):
        raise ValueError('failure_policy is a batch-level setting')
    return override if override is not None else configured


def setup_failure(execution, expected_clients=None):
    """Do not infer infrastructure failure from gameplay status or log text."""
    if not isinstance(execution, dict):
        return None
    if 'setup_failure' in execution:
        finding = execution['setup_failure']
        if (not isinstance(finding, dict) or not all(isinstance(finding.get(key), str)
                and finding[key] for key in ('kind', 'phase', 'reason'))):
            return dict(kind='invalid-setup-evidence', phase='audit',
                        reason='Execution contains malformed setup_failure evidence')
        return dict(finding)
    if 'fixture_load_error' in execution:
        finding = execution['fixture_load_error']
        return dict(kind='fixture-load', phase='fixture-load', reason='Fixture Lua failed to load',
                    evidence=finding)
    if 'preflight' in execution:
        barrier = execution['preflight']
        roles = barrier.get('required_roles') if isinstance(barrier, dict) else None
        if (not isinstance(roles, list) or not roles or any(not isinstance(role, str) for role in roles)
                or len(set(roles)) != len(roles) or (expected_clients is not None and roles != expected_clients)
                or barrier.get('setup_released') is not True or barrier.get('released') is not True
                or any(not isinstance(barrier.get(key), dict) or set(barrier[key]) != set(roles)
                       or any(not isinstance(receipt, dict) or type(receipt.get('line')) is not int
                              or receipt['line'] <= 0 for receipt in barrier[key].values())
                       for key in ('ready', 'fixture_setup'))):
            return dict(kind='incomplete-client-preflight', phase='preflight',
                        reason='Execution requires completed preflight and fixture setup for every selected client')
    return None


def exception_failure(stage, error):
    return dict(kind='batch-' + stage, phase=stage, reason=str(error) or type(error).__name__)
