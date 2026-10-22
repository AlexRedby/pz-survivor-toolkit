"""Behavior contracts over native cases; declarations and controls never imply coverage."""

# IDs describe behavior, not an action implementation or a game fixture.
SCENARIOS = {
    'success-empty': 'Start with an empty queue; verify exact effects and completion.',
    'success-queued': 'Complete behind unrelated work and preserve the queue tail.',
    'repeat-same': 'Repeat requests using the same target/resource without loss or duplication.',
    'repeat-independent': 'Queue requests for independent targets/resources.',
    'move-independent': 'Move independent work and verify exact order and effects.',
    'move-dependent': 'Reject unsafe reordering without mutating the queue.',
    'priority-preempt': 'Run priority work before current work and resume safely.',
    'cancel-waiting': 'Cancel the whole waiting operation and retain unrelated work.',
    'cancel-active': 'Exercise active cancellation or its documented protection, preserving effects.',
    'cancel-after-effect': 'Cancel after an authoritative effect without losing required completion.',
    'cancel-cleanup': 'Exercise cancellation during return/cleanup without losing items.',
    'lost-before-start': 'Remove a target/resource before execution and preserve unrelated work.',
    'lost-during-action': 'Remove a target/resource after execution starts.',
    'replaced-target': 'Replace the target, including reused identity, without affecting its replacement.',
    'capacity': 'Verify capacity conflicts against exact source/destination/ancestor state.',
    'return-items': 'Return borrowed items to their exact containers without duplication.',
    'restore-hands': 'Restore original hands, including empty hands and activation.',
    'restore-hotbar': 'Restore a temporary held item to its exact original hotbar slot/model with empty captured hands.',
    'restore-clothing': 'Restore original clothing with exact item identities and worn slots.',
    'return-unavailable': 'Handle a full, removed or inaccessible return container.',
    'callback-changed': 'Reject unreviewed callback/helper changes without losing native behavior.',
    'server-authority': 'Verify exact server effects independently of client completion.',
    'multiplayer-contention': 'Two players compete for the same target/resource.',
    'delayed-response': 'Handle delayed authoritative completion without predicting success.',
    'duplicate-response': 'Handle duplicate/late results without repeating effects.',
    'disconnect': 'Disconnect/reconnect with in-flight work and audit ownership/cleanup.',
    'death-reset': 'Handle character death/reset with in-flight work.',
    'save-reload': 'Save/reload a generated world and verify preserved effects.',
    'presentation': 'Check labels, translations, icons and denial reasons.',
    'physical-input': 'Exercise actual menu clicks, drag and cancellation shortcuts.',
}
QUEUE_ONLY = {'move-independent', 'move-dependent', 'priority-preempt', 'cancel-waiting',
              'cancel-active', 'cancel-after-effect', 'cancel-cleanup'}
MP_ONLY = {'server-authority', 'multiplayer-contention', 'delayed-response', 'duplicate-response', 'disconnect'}


def identifiers(value, known, label):
    if not isinstance(value, str) or not value:
        raise ValueError(label + ' requires nonempty comma-separated IDs')
    result = value.split(',')
    if len(result) != len(set(result)) or any(key not in known for key in result):
        raise ValueError('Select known unique ' + label + ': ' + ', '.join(known))
    return result


def validate(suite):
    actions = suite.get('scenario_actions', {})
    if not isinstance(actions, dict):
        raise ValueError('scenario_actions must be an object')
    cases = {case['id']: case for case in suite['cases']}
    for name, action in actions.items():
        if not isinstance(name, str) or not name or not isinstance(action, dict) or not action.get('scope'):
            raise ValueError('Scenario actions require an ID and an explicit scope')
        checks, excluded = action.get('checks', {}), action.get('not_applicable', {})
        if not isinstance(checks, dict) or not isinstance(excluded, dict) or set(checks) & set(excluded):
            raise ValueError('Scenario checks and exclusions must be disjoint objects')
        if (set(checks) | set(excluded)) - SCENARIOS.keys():
            raise ValueError('Unknown scenario binding in ' + name)
        if any(not isinstance(reason, str) or not reason.strip() for reason in excluded.values()):
            raise ValueError('Inapplicable scenarios require a reason')
        toolkit_only = action.get('toolkit_only', [])
        if not isinstance(toolkit_only, list) or set(toolkit_only) - checks.keys():
            raise ValueError('toolkit_only must name implemented scenarios')
        mods = action.get('mods', [])
        if not isinstance(mods, list) or any(not isinstance(mod, str) or not mod for mod in mods):
            raise ValueError('Scenario mods must be a list of Mod IDs')
        for scenario, bindings in checks.items():
            if not isinstance(bindings, dict) or not bindings or set(bindings) - cases.keys():
                raise ValueError('Scenario bindings require known native cases: ' + name + '/' + scenario)
            if any(not isinstance(fields, dict) or not fields for fields in bindings.values()):
                raise ValueError('Scenario bindings require explicit outcome evidence')
    return actions


def select(suite, requested, actions, kind, mode):
    definitions = validate(suite)
    chosen = identifiers(actions, definitions, 'actions') if actions is not None else list(definitions)
    scenarios = identifiers(requested, SCENARIOS, 'scenarios')
    if not chosen:
        raise ValueError('Suite has no scenario action contracts')
    selected = set()
    for name in chosen:
        definition = definitions[name]
        for scenario in scenarios:
            if scenario in MP_ONLY and kind != 'mp':
                raise ValueError(scenario + ' requires MP')
            binding = definition.get('checks', {}).get(scenario)
            if not binding:
                reason = definition.get('not_applicable', {}).get(scenario, 'not implemented')
                raise ValueError(name + '/' + scenario + ': ' + reason)
            selected.update(binding)
    cases = [case for case in suite['cases'] if case['id'] in selected]
    if any(kind not in case['kinds'] or mode not in case.get('modes', ['toolkit', 'native']) for case in cases):
        raise ValueError('Scenario has no complete case/control implementation for this kind/mode')
    # Native resolves the same cases as toolkit, but its matrix cannot claim queue edits.
    return [case['id'] for case in cases], sorted({mod for name in chosen for mod in definitions[name].get('mods', [])})


def matrix(catalog, reports, case_matrix):
    rows, cache = [], {}
    for suite, definition in catalog['suites'].items():
        actions = validate(definition)
        if not actions:
            rows.append(dict(suite=suite, action=None, scenario=None, status='unmapped',
                             reason='Action contracts have not been audited for this suite'))
        for name, action in actions.items():
            mods = tuple(sorted(action.get('mods', [])))
            eligible = [r for r in reports if set(mods) <= set(r.get('selection', {}).get('mods', []))]
            if mods not in cache:
                cache[mods] = {(r['suite'], r.get('case'), r.get('kind'), r.get('mode')): r
                               for r in case_matrix(catalog, eligible)['rows']}
            for scenario, description in SCENARIOS.items():
                for kind in ('sp', 'mp'):
                    for mode in ('toolkit', 'native'):
                        row = dict(suite=suite, action=name, scope=action['scope'], scenario=scenario,
                                   description=description, kind=kind, mode=mode, status='unimplemented')
                        reason = action.get('not_applicable', {}).get(scenario)
                        if scenario in MP_ONLY and kind == 'sp':
                            reason = 'Requires networked execution'
                        if (scenario in QUEUE_ONLY or scenario in action.get('toolkit_only', [])) and mode == 'native':
                            reason = 'Queue disabled: matching native cases are controls, not evidence for this Toolkit behavior'
                        bindings = action.get('checks', {}).get(scenario)
                        if reason:
                            row.update(status='not-applicable', reason=reason)
                        elif bindings:
                            matches = [cache[mods].get((suite, case, kind, mode), {'status': 'unsupported'}) for case in bindings]
                            statuses = {match['status'] for match in matches}
                            row.update(cases=list(bindings), required_mods=list(mods), evidence=matches)
                            row['status'] = next((s for s in ('failed', 'unsupported', 'partial', 'not-run', 'skipped', 'captured') if s in statuses), 'passed')
                            if row['status'] == 'passed' and any(r.get('status') != 'passed' for r in eligible
                                    if any(e.get('suite') == suite and e.get('case') in bindings and e.get('kind') == kind
                                           and e.get('mode') == mode for e in r.get('coverage', []))):
                                row.update(status='needs-review', reason='Matching run has no clean overall verdict')
                            if row['status'] == 'passed':
                                for case, match in zip(bindings, matches):
                                    evidence = match.get('evidence', [])
                                    if not evidence or any(any(type((e.get('outcome') or {}).get(key)) is not type(value)
                                                               or (e.get('outcome') or {}).get(key) != value
                                                               for key, value in bindings[case].items()) for e in evidence):
                                        row.update(status='missing-evidence', reason='Case passed without required scenario outcome fields')
                                        break
                        rows.append(row)
    return rows
