"""Keep runnable checks and unresolved acceptance gates in one campaign report."""
import re


def validate(plan):
    if 'campaign' not in plan:
        return
    items = plan['campaign']
    if not isinstance(items, list) or not items:
        raise ValueError('Campaign requires a nonempty list of coverage blocks')
    known = {job['id'] for job in plan['jobs']}
    seen, covered = set(), set()
    for item in items:
        if not isinstance(item, dict) or set(item) != {'id', 'title', 'todo', 'jobs', 'gates'}:
            raise ValueError('Campaign blocks require id, title, todo, jobs and gates')
        identifier = item['id']
        if (not isinstance(identifier, str) or not re.fullmatch(r'[a-z][a-z0-9-]*', identifier)
                or identifier in seen):
            raise ValueError('Campaign block IDs must be unique safe names')
        seen.add(identifier)
        for key in ('title', 'todo'):
            if not isinstance(item[key], str) or not item[key].strip():
                raise ValueError('Campaign ' + key + ' must be nonempty')
        jobs, gates = item['jobs'], item['gates']
        if (not isinstance(jobs, list) or any(not isinstance(job, str) or job not in known for job in jobs)
                or len(set(jobs)) != len(jobs)):
            raise ValueError('Campaign jobs must be unique known job IDs: ' + identifier)
        if (not isinstance(gates, list) or any(not isinstance(gate, str) or not gate.strip() for gate in gates)
                or not jobs and not gates):
            raise ValueError('Campaign block needs runnable jobs or explicit remaining gates: ' + identifier)
        covered.update(jobs)
    if known - covered:
        raise ValueError('Jobs missing from campaign coverage: ' + ', '.join(sorted(known - covered)))
    for job in plan['jobs']:
        if not job.get('session') and (not isinstance(job.get('boundary'), str) or not job['boundary'].strip()):
            raise ValueError('Separate campaign job needs a boundary reason: ' + job['id'])


def build(plan, selected, results=(), planned=False):
    """A partial selection or manual gate must never become a full campaign pass."""
    if 'campaign' not in plan:
        return None
    validate(plan)
    chosen = {job['id'] for job in selected}
    by_id = {row['id']: row for row in results}
    blocks = []
    for item in plan['campaign']:
        jobs = [dict(id=job, status=by_id[job]['status'] if job in by_id else
                     'planned' if planned and job in chosen else 'pending' if job in chosen else 'not-selected')
                for job in item['jobs']]
        states = {job['status'] for job in jobs}
        status = ('failed' if states & {'failed', 'blocked'} else
                  'needs-review' if states & {'needs-review', 'captured'} else
                  'passed' if jobs and states == {'passed'} and not item['gates'] else 'pending')
        blocks.append(dict(item, jobs=jobs, status=status))
    statuses = {block['status'] for block in blocks}
    return {'status': 'failed' if 'failed' in statuses else 'passed' if statuses == {'passed'} else 'pending',
            'blocks': blocks,
            'remaining_gates': sum(len(item['gates']) for item in plan['campaign'])}
