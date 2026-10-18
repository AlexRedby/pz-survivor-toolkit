"""Exact native ignition trials; expected vanilla queue failures remain per case."""
import math

CASES = ['literature', 'petrol', 'last-match', 'bbq-fuel', 'bbq-literature', 'bbq-petrol', 'kindle-retry']
ACTIONS = {'literature': ('ISLightFromLiterature', 100), 'petrol': ('ISLightFromPetrol', 20),
           'last-match': ('ISLightFromPetrol', 20), 'kindle-retry': ('ISLightFromKindle', 1500),
           'bbq-fuel': ('ISBBQAddFuel', 100), 'bbq-literature': ('ISBBQLightFromLiterature', 100),
           'bbq-petrol': ('ISBBQLightFromPetrol', 20)}
RESOURCE_FIELDS = {'role', 'id', 'kind', 'sourceCount', 'rootCount', 'condition', 'uses', 'amount', 'consumed'}


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def _close(left, right):
    return _number(left) and _number(right) and abs(left - right) <= 1e-6


def _ids(values):
    return isinstance(values, list) and all(type(value) is int for value in values) and len(set(values)) == len(values)


def _same_resources(left, right):
    if not isinstance(left, list) or not isinstance(right, list) or len(left) != len(right):
        return False
    for first, second in zip(left, right):
        if not isinstance(first, dict) or not isinstance(second, dict) or set(first) != RESOURCE_FIELDS or set(second) != RESOURCE_FIELDS:
            return False
        for key in RESOURCE_FIELDS:
            if key in ('uses', 'amount'):
                if not _close(first[key], second[key]): return False
            elif type(first[key]) is not type(second[key]) or first[key] != second[key]:
                return False
    return True


def _profile(case, roles):
    # kind, initial uses, amount, use debit, fluid debit, consumed, optional, return, source
    if case == 'bbq-fuel':
        return {'fuel': ('Base.Log', 0, 0, 0, 0, True, False, False, 'crate')}
    if case == 'kindle-retry':
        result = {'plank': ('Base.PercedWood', 0, 0, 0, 0, False, False, True, 'crate'),
                  'stick': ('Base.WoodenStick2', 0, 0, 0, 0, False, True, True, 'crate')}
        reserves = [role for role in roles if role.startswith('reserve')]
        if reserves != ['reserve' + str(i) for i in range(1, len(reserves) + 1)] or not 1 <= len(reserves) <= 3:
            return {}
        result.update({role: ('Base.WoodenStick2', 0, 0, 0, 0, False, True, False, 'root') for role in reserves})
        return result
    last = case in ('last-match', 'bbq-petrol')
    result = {'starter': ('Base.Matches', 1 if last else 2, 0, 1, 0, last, False, True, 'crate')}
    if case in ('literature', 'bbq-literature'):
        result['tinder'] = ('Base.SheetPaper2', 0, 0, 0, 0, True, False, False, 'crate')
    else:
        result['petrol'] = ('Base.PetrolCan', 0, 2, 0, 0.1, False, False, False, 'crate')
    return result


def _resources(case, prepared, received, enabled):
    issues = []
    if not isinstance(prepared, list) or not isinstance(received, list):
        return ['Ignition resources must be arrays']
    if any(not isinstance(row, dict) for row in prepared + received):
        return ['Invalid ignition resource envelope']
    roles = [row.get('role') for row in prepared]
    if any(not isinstance(role, str) for role in roles) or len(set(roles)) != len(roles):
        return ['Missing or duplicate ignition resource role']
    profile = _profile(case, roles)
    if set(roles) != set(profile) or not profile:
        return ['Ignition resource profile differs']
    if not _ids([row.get('id') for row in prepared]) or not _ids([row.get('id') for row in received]):
        issues.append('Missing, invalid or duplicate ignition resource ID')
    if [row.get('role') for row in received] != roles:
        issues.append('Ignition resource roles are missing, duplicated or reordered')
    for spec in prepared:
        role = spec['role']
        actual = next((row for row in received if row.get('role') == role), {})
        kind, uses, amount, debit, fluid_debit, consumed, optional, returned, source = profile[role]
        expected = dict(kind=kind, consumed=consumed, optionalConsume=optional, returnToSource=returned, source=source)
        if (any(type(spec.get(key)) is not type(value) or spec.get(key) != value for key, value in expected.items())
                or any(not _close(spec.get(key), value) for key, value in
                       (('initialUses', uses), ('initialAmount', amount), ('expectedUse', debit), ('expectedAmountDelta', fluid_debit)))
                or type(spec.get('condition')) is not int or spec['condition'] < 0):
            issues.append('Ignition prepared resource effect differs: ' + role)
        if (set(actual) != RESOURCE_FIELDS or type(actual.get('id')) is not int or actual.get('id') != spec.get('id')
                or actual.get('kind') != kind or type(actual.get('condition')) is not int
                or actual.get('condition') != spec.get('condition') or type(actual.get('consumed')) is not bool
                or any(type(actual.get(key)) is not int or actual[key] not in (0, 1) for key in ('sourceCount', 'rootCount'))):
            issues.append('Ignition exact resource identity/condition/count differs: ' + role)
            continue
        total = actual['sourceCount'] + actual['rootCount']
        gone = actual['consumed']
        if total != (0 if gone else 1) or not optional and gone != consumed:
            issues.append('Ignition resource conservation/consumption differs: ' + role)
        if (not _close(actual.get('uses'), uses - debit) or not _close(actual.get('amount'), amount - fluid_debit)):
            issues.append('Ignition resource use/fluid debit differs: ' + role)
        if not gone:
            must_source = enabled and returned
            must_root = source == 'root' or role == 'petrol'
            if must_source and (actual['sourceCount'], actual['rootCount']) != (1, 0):
                issues.append('Ignition borrowed resource was not returned: ' + role)
            if must_root and (actual['sourceCount'], actual['rootCount']) != (0, 1):
                issues.append('Ignition conserved resource must remain in root: ' + role)
    return issues


def verify_case(case, selection, result, preparedList, receiptsList):
    issues, outcome = [], {'actor': 'client1', 'case': case, 'outcome': {}}
    if case not in ACTIONS or not isinstance(result, dict):
        return ['Unknown ignition case or invalid result'], outcome, None
    if (not isinstance(preparedList, list) or not isinstance(receiptsList, list)
            or any(not isinstance(row, dict) for row in preparedList + receiptsList)):
        return ['Invalid ignition trial envelopes'], outcome, None
    prepared = [row for row in preparedList if row.get('case') == case]
    receipts = [row for row in receiptsList if row.get('case') == case]
    trial = result.get('trial')
    maximum = 8 if case == 'kindle-retry' else 1
    if type(trial) is not int or not 1 <= trial <= maximum:
        return ['Ignition final trial is invalid'], outcome, None
    expected_trials = list(range(1, trial + 1))
    if (len(prepared) != trial or len(receipts) != trial
            or any(type(row.get('trial')) is not int for row in prepared + receipts)
            or [row.get('trial') for row in prepared] != expected_trials
            or [row.get('trial') for row in receipts] != expected_trials):
        return ['Ignition trials are missing, duplicated or out of order'], outcome, None
    enabled = selection.get('mode') == 'toolkit'
    action, duration = ACTIONS[case]
    if result.get('id') != case or result.get('actionType') != action or type(result.get('nativeDuration')) is not int or result['nativeDuration'] != duration:
        issues.append('Ignition action type/duration differs')
    if type(result.get('attempts')) is not int or result['attempts'] < (2 if case == 'kindle-retry' else 1):
        issues.append('Ignition native attempt count does not prove the case')
    if type(result.get('tokenCancelled')) is not bool or enabled and result.get('tokenCancelled') is not False:
        issues.append('Completed ignition operation was cancelled')
    for key in ('expanded', 'actionProgress', 'pickupProgress', 'tailProgress', 'returnedBeforeTail', 'retryBeforeReturns'):
        if type(result.get(key)) is not bool:
            issues.append('Ignition progress must be boolean: ' + key)
        elif (key in ('expanded', 'actionProgress', 'pickupProgress') or enabled and key in ('tailProgress', 'returnedBeforeTail')
              or enabled and case == 'kindle-retry' and key == 'retryBeforeReturns') and not result[key]:
            issues.append('Ignition native progress/order missing: ' + key)
    for spec, receipt in zip(prepared, receipts):
        if (spec.get('actionType') != action or type(spec.get('nativeDuration')) is not int or spec['nativeDuration'] != duration
                or type(spec.get('book')) is not int or type(receipt.get('bookId')) is not int or receipt['bookId'] != spec['book']):
            issues.append('Ignition authoritative action/reader identity differs')
        for key in ('x', 'y', 'z', 'objectIndex', 'crateX', 'crateY', 'crateZ', 'crateIndex'):
            if type(spec.get(key)) is not int or key.endswith('Index') and spec[key] < 0:
                issues.append('Ignition authoritative world identity missing: ' + key)
        if (any(spec.get('crate' + key.upper()) != spec.get(key) for key in ('x', 'y', 'z'))
                or type(spec.get('crateIndex')) is int and type(spec.get('objectIndex')) is int
                and spec['crateIndex'] >= spec['objectIndex']):
            issues.append('Ignition source must precede the target on the same square')
        resources = spec.get('resources')
        issues.extend(_resources(case, resources, receipt.get('resources'), enabled))
        if isinstance(resources, list) and any(isinstance(row, dict) and row.get('id') == spec.get('book') for row in resources):
            issues.append('Ignition reader and resource IDs overlap')
        initial, expected_fuel = spec.get('initialFuel'), spec.get('expectedFuel')
        if (not _number(initial) or initial < 0 or not _number(expected_fuel) or expected_fuel <= 0
                or case in ('petrol', 'last-match', 'bbq-petrol', 'kindle-retry') and not _close(initial, expected_fuel)
                or case in ('literature', 'bbq-literature', 'bbq-fuel') and _number(initial) and _number(expected_fuel) and expected_fuel <= initial):
            issues.append('Ignition prepared fuel effect differs')
        exhausted = case == 'kindle-retry' and receipt.get('lit') is False
        if exhausted:
            optional = [row for row in resources if isinstance(row, dict) and row.get('optionalConsume') is True] if isinstance(resources, list) else []
            actual_resources = receipt.get('resources')
            if (not optional or not isinstance(actual_resources, list)
                    or any(not any(isinstance(actual, dict) and actual.get('id') == row.get('id')
                                   and actual.get('consumed') is True for actual in actual_resources) for row in optional)):
                issues.append('Unlit Kindle trial did not consume every optional stick')
            if not _close(receipt.get('effectFuel'), initial) or not _close(receipt.get('fuel'), initial):
                issues.append('Exhausted Kindle trial changed the initial fuel')
        lit = case != 'bbq-fuel' and not exhausted
        if type(receipt.get('lit')) is not bool or receipt['lit'] != lit or not _close(receipt.get('effectFuel'), expected_fuel):
            issues.append('Ignition authoritative lit/first fuel effect differs')
        final_fuel = receipt.get('fuel')
        if (not _number(final_fuel) or not _number(expected_fuel) or not 0 < final_fuel <= expected_fuel + 1e-6
                or not lit and not _close(final_fuel, expected_fuel)):
            issues.append('Ignition authoritative final fuel differs')
        if type(receipt.get('tailRead')) is not bool or enabled and receipt.get('tailRead') is not True:
            issues.append('Ignition authoritative reading proof differs')
    final, final_spec = receipts[-1], prepared[-1]
    for key in ('bookId', 'lit', 'tailRead'):
        if type(result.get(key)) is not type(final.get(key)) or result.get(key) != final.get(key):
            issues.append('Ignition client differs from authoritative receipt: ' + key)
    for key in ('effectFuel', 'fuel'):
        if not _close(result.get(key), final.get(key)):
            issues.append('Ignition client differs from authoritative receipt: ' + key)
    issues.extend(_resources(case, final_spec.get('resources'), result.get('resources'), enabled))
    if not _same_resources(result.get('resources'), final.get('resources')):
        issues.append('Ignition client resources differ from the final receipt')
    specs = final_spec.get('resources', [])
    actual = final.get('resources', [])
    if isinstance(specs, list) and isinstance(actual, list) and all(isinstance(row, dict) for row in specs + actual):
        pickup_ids = [row.get('id') for row in specs if row.get('source') == 'crate']
        survivors = {row.get('id') for row in actual if row.get('consumed') is False and type(row.get('id')) is int}
        return_ids = {row.get('id') for row in specs if row.get('returnToSource') is True and type(row.get('id')) is int and row['id'] in survivors}
        if not _ids(pickup_ids) or not _ids(result.get('pickupIds')) or set(result['pickupIds']) != set(pickup_ids):
            issues.append('Ignition exact borrowed pickup IDs differ')
        if (not _ids(result.get('returnIds')) or not set(result['returnIds']) <= return_ids
                or enabled and set(result['returnIds']) != return_ids):
            issues.append('Ignition exact surviving return IDs differ')
    reason = None
    if not enabled:
        if any(row.get('tailRead') is False for row in receipts): reason = 'native-independent-tail-not-preserved'
        elif result.get('returnedBeforeTail') is False: reason = 'native-returns-not-before-tail'
        elif case == 'kindle-retry' and result.get('retryBeforeReturns') is False: reason = 'native-retry-not-before-returns'
    if result.get('status') != ('failed' if reason else 'passed') or result.get('reason') != reason:
        issues.append('Ignition declared status/reason differs from observed outcome')
    outcome['outcome'] = {key: result.get(key) for key in ('trial', 'actionType', 'nativeDuration', 'attempts', 'bookId', 'resources',
                          'lit', 'effectFuel', 'fuel', 'tailRead', 'returnedBeforeTail', 'retryBeforeReturns', 'pickupIds', 'returnIds', 'tokenCancelled')}
    return issues, outcome, reason
