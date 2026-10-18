"""Exact native ignition trials; expected vanilla queue failures remain per case."""
import math

CASES = ['literature', 'petrol', 'last-match', 'bbq-fuel', 'bbq-literature', 'bbq-petrol', 'bbq-kindle',
         'fireplace-fuel', 'fireplace-literature', 'fireplace-petrol', 'fireplace-kindle', 'kindle-retry']
ACTIONS = {'literature': ('ISLightFromLiterature', 100), 'petrol': ('ISLightFromPetrol', 20),
           'last-match': ('ISLightFromPetrol', 20), 'kindle-retry': ('ISLightFromKindle', 1500),
           'bbq-fuel': ('ISBBQAddFuel', 100), 'bbq-literature': ('ISBBQLightFromLiterature', 100),
           'bbq-petrol': ('ISBBQLightFromPetrol', 20), 'bbq-kindle': ('ISBBQLightFromKindle', 1500),
           'fireplace-fuel': ('ISBBQAddFuel', 100), 'fireplace-literature': ('ISBBQLightFromLiterature', 100),
           'fireplace-petrol': ('ISBBQLightFromPetrol', 20), 'fireplace-kindle': ('ISBBQLightFromKindle', 1500)}
RESOURCE_FIELDS = {'role', 'id', 'kind', 'sourceCount', 'rootCount', 'condition', 'uses', 'amount', 'consumed'}
PETROL_CASES = ('petrol', 'last-match', 'bbq-petrol', 'fireplace-petrol')
TIDY_FIELDS = {'id', 'sessionId', 'nativeTransfer', 'fromRoot', 'toSource', 'groupCleanup', 'progress', 'tailRead', 'tokenCancelled'}


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
    if case in ('bbq-fuel', 'fireplace-fuel'):
        return {'fuel': ('Base.Log', 0, 0, 0, 0, True, False, False, 'crate')}
    if case in ('kindle-retry', 'bbq-kindle', 'fireplace-kindle'):
        result = {'plank': ('Base.PercedWood', 0, 0, 0, 0, False, False, True, 'crate'),
                  'stick': ('Base.WoodenStick2', 0, 0, 0, 0, False, True, True, 'crate')}
        if case != 'kindle-retry':
            return result
        reserves = [role for role in roles if role.startswith('reserve')]
        if reserves != ['reserve' + str(i) for i in range(1, len(reserves) + 1)] or not 1 <= len(reserves) <= 3:
            return {}
        result.update({role: ('Base.WoodenStick2', 0, 0, 0, 0, False, True, False, 'root') for role in reserves})
        return result
    last = case in ('last-match', 'bbq-petrol', 'fireplace-petrol')
    result = {'starter': ('Base.Matches', 1 if last else 2, 0, 1, 0, last, False, True, 'crate')}
    if case in ('literature', 'bbq-literature', 'fireplace-literature'):
        result['tinder'] = ('Base.SheetPaper2', 0, 0, 0, 0, True, False, False, 'crate')
    else:
        result['petrol'] = ('Base.PetrolCan', 0, 2, 0, 0.1, False, False, False, 'crate')
    return result


def _tidy_ids(case, prepared, ids):
    if not _ids(ids) or len(ids) > 1:
        return False
    petrol = [row.get('id') for row in prepared if isinstance(row, dict) and row.get('role') == 'petrol'] if isinstance(prepared, list) else []
    return not ids or case in PETROL_CASES and ids == petrol


def _resources(case, prepared, received, enabled, tidy_return_ids):
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
            tidy_return = role == 'petrol' and spec.get('id') in tidy_return_ids
            must_source = enabled and returned or tidy_return
            must_root = source == 'root' or role == 'petrol' and not tidy_return
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
    target_kind = 'fireplace' if case.startswith('fireplace-') else 'bbq' if case.startswith('bbq-') else 'campfire'
    if result.get('targetKind') != target_kind:
        issues.append('Ignition client target kind differs')
    if result.get('id') != case or result.get('actionType') != action or type(result.get('nativeDuration')) is not int or result['nativeDuration'] != duration:
        issues.append('Ignition action type/duration differs')
    if type(result.get('attempts')) is not int or result['attempts'] < (2 if case == 'kindle-retry' else 1):
        issues.append('Ignition native attempt count does not prove the case')
    if case == 'kindle-retry':
        completion = result.get('nativeCompletion')
        count = result.get('attempts') if enabled else 0
        expected = {'perform': count, 'complete': count if selection.get('kind') == 'sp' else 0, 'flush': count}
        if (not isinstance(completion, dict) or set(completion) != set(expected)
                or any(type(completion.get(key)) is not int or completion[key] != value for key, value in expected.items())):
            issues.append('Ignition native Kindle completion phases differ')
    if type(result.get('petrolBeforeTail')) is not bool or enabled and case in PETROL_CASES and result.get('petrolBeforeTail') is not True:
        issues.append('Ignition retained petrol before reader proof differs')
    final = receipts[-1]
    final_resources = final.get('resources')
    kindle_stop = (selection.get('kind') == 'sp' and case in ('bbq-kindle', 'fireplace-kindle')
                   and (final.get('lit') is True or isinstance(final_resources, list)
                        and any(isinstance(row, dict) and row.get('role') == 'stick' and row.get('consumed') is True
                                for row in final_resources)))
    if type(result.get('tokenCancelled')) is not bool or enabled and result.get('tokenCancelled') is not False and not kindle_stop:
        issues.append('Completed ignition operation was cancelled')
    for key in ('expanded', 'actionProgress', 'pickupProgress', 'tailProgress', 'returnedBeforeTail', 'retryBeforeReturns'):
        if type(result.get(key)) is not bool:
            issues.append('Ignition progress must be boolean: ' + key)
        elif (key in ('expanded', 'actionProgress', 'pickupProgress') or enabled and key in ('tailProgress', 'returnedBeforeTail')
              or enabled and case == 'kindle-retry' and key == 'retryBeforeReturns') and not result[key]:
            issues.append('Ignition native progress/order missing: ' + key)
    unfinished_native_retry = False
    for spec, receipt in zip(prepared, receipts):
        if spec.get('targetKind') != target_kind or receipt.get('targetKind') != target_kind:
            issues.append('Ignition authoritative target kind differs')
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
        tidy_ids = receipt.get('tidyReturnIds')
        if not _tidy_ids(case, resources, tidy_ids):
            issues.append('Ignition authoritative Tidy return IDs differ')
            tidy_ids = []
        issues.extend(_resources(case, resources, receipt.get('resources'), enabled, tidy_ids))
        if isinstance(resources, list) and any(isinstance(row, dict) and row.get('id') == spec.get('book') for row in resources):
            issues.append('Ignition reader and resource IDs overlap')
        initial, expected_fuel = spec.get('initialFuel'), spec.get('expectedFuel')
        if (not _number(initial) or initial < 0 or not _number(expected_fuel) or expected_fuel <= 0
                or case in ('petrol', 'last-match', 'bbq-petrol', 'fireplace-petrol', 'kindle-retry', 'bbq-kindle', 'fireplace-kindle') and not _close(initial, expected_fuel)
                or case in ('literature', 'bbq-literature', 'fireplace-literature', 'bbq-fuel', 'fireplace-fuel') and _number(initial) and _number(expected_fuel) and expected_fuel <= initial):
            issues.append('Ignition prepared fuel effect differs')
        exhausted = case == 'kindle-retry' and receipt.get('lit') is False
        if exhausted:
            optional = [row for row in resources if isinstance(row, dict) and row.get('optionalConsume') is True] if isinstance(resources, list) else []
            actual_resources = receipt.get('resources')
            if (not optional or not isinstance(actual_resources, list)
                    or any(not any(isinstance(actual, dict) and actual.get('id') == row.get('id')
                                   and actual.get('consumed') is True for actual in actual_resources) for row in optional)):
                if enabled:
                    issues.append('Unlit Kindle trial did not consume every optional stick')
                else:
                    unfinished_native_retry = True
            if not _close(receipt.get('effectFuel'), initial) or not _close(receipt.get('fuel'), initial):
                issues.append('Unlit Kindle trial changed the initial fuel')
        # Native BBQ Kindle may finish its duration without lighting or breaking the stick.
        unlit_kindle = case in ('bbq-kindle', 'fireplace-kindle') and receipt.get('lit') is False
        if unlit_kindle and (not _close(receipt.get('effectFuel'), initial) or not _close(receipt.get('fuel'), initial)):
            issues.append('Unlit Kindle trial changed the initial fuel')
        lit = case not in ('bbq-fuel', 'fireplace-fuel') and not exhausted and not unlit_kindle
        if type(receipt.get('lit')) is not bool or receipt['lit'] != lit or not _close(receipt.get('effectFuel'), expected_fuel):
            issues.append('Ignition authoritative lit/first fuel effect differs')
        final_fuel = receipt.get('fuel')
        if (not _number(final_fuel) or not _number(expected_fuel) or not 0 < final_fuel <= expected_fuel + 1e-6
                or not lit and not _close(final_fuel, expected_fuel)):
            issues.append('Ignition authoritative final fuel differs')
        if type(receipt.get('tailRead')) is not bool or enabled and receipt.get('tailRead') is not True:
            issues.append('Ignition authoritative reading proof differs')
    final, final_spec = receipts[-1], prepared[-1]
    tidy_ids = result.get('tidyReturnIds')
    if not _tidy_ids(case, final_spec.get('resources'), tidy_ids) or tidy_ids != final.get('tidyReturnIds'):
        issues.append('Ignition client Tidy return IDs differ from final receipt')
        tidy_ids = []
    tidy_returns = result.get('tidyReturns')
    if (not isinstance(tidy_returns, list) or len(tidy_returns) > 1
            or any(not isinstance(row, dict) for row in tidy_returns)):
        issues.append('Ignition Tidy return proofs must be an array of at most one record')
        tidy_returns = []
    proof_ids = [row.get('id') for row in tidy_returns]
    if not _ids(proof_ids) or proof_ids != tidy_ids:
        issues.append('Ignition Tidy return proof IDs differ')
    if tidy_returns and (not isinstance(selection.get('mods'), list) or 'P4TidyUpMeister' not in selection['mods']):
        issues.append('Ignition Tidy return requires the selected P4 mod')
    for proof in tidy_returns:
        if (set(proof) != TIDY_FIELDS or type(proof.get('sessionId')) is not int or proof['sessionId'] <= 0
                or any(proof.get(key) is not True for key in ('nativeTransfer', 'fromRoot', 'toSource', 'progress'))
                or proof.get('groupCleanup') is not False
                or type(proof.get('tailRead')) is not bool or proof['tailRead'] != final.get('tailRead')
                or type(proof.get('tokenCancelled')) is not bool or proof['tokenCancelled'] != result.get('tokenCancelled')
                or enabled and (proof.get('tailRead') is not True or proof.get('tokenCancelled') is not False)):
            issues.append('Ignition exact native Tidy return provenance differs')
    for key in ('bookId', 'lit', 'tailRead'):
        if type(result.get(key)) is not type(final.get(key)) or result.get(key) != final.get(key):
            issues.append('Ignition client differs from authoritative receipt: ' + key)
    for key in ('effectFuel', 'fuel'):
        if not _close(result.get(key), final.get(key)):
            issues.append('Ignition client differs from authoritative receipt: ' + key)
    issues.extend(_resources(case, final_spec.get('resources'), result.get('resources'), enabled, tidy_ids))
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
        if unfinished_native_retry and reason is None:
            issues.append('Unfinished native Kindle trial lacks a functional failure')
    if result.get('status') != ('failed' if reason else 'passed') or result.get('reason') != reason:
        issues.append('Ignition declared status/reason differs from observed outcome')
    outcome['outcome'] = {key: result.get(key) for key in ('trial', 'targetKind', 'actionType', 'nativeDuration', 'attempts', 'bookId', 'resources',
                          'lit', 'effectFuel', 'fuel', 'tailRead', 'returnedBeforeTail', 'retryBeforeReturns', 'pickupIds', 'returnIds',
                          'tokenCancelled', 'petrolBeforeTail', 'tidyReturnIds', 'tidyReturns')}
    if case == 'kindle-retry':
        outcome['outcome']['nativeCompletion'] = result.get('nativeCompletion')
    return issues, outcome, reason
