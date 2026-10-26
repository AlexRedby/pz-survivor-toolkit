"""Real WashFix flat clothing menus, finite resources and native reset isolation."""
import hashlib
import json
import math
from pathlib import Path
import re

from . import craft
from ..mod_selection import selected_mod_version

CLOTHING_CASES = ['borrowed-batch', 'borrowed-single-soap', 'cancel-after-pickup']
BODY_CASES = ['body-full', 'body-water-limited', 'body-cancel']
CASES = CLOTHING_CASES + BODY_CASES
MODS = craft.MODS + ['WashFix']
GARMENTS = ['Base.Tshirt_DefaultTEXTURE_TINT', 'Base.Shirt_FormalWhite']
BEHAVIOR = 'compat.wash-clothing'
REPLAY_PATH = 'media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'
REPLAY_BODY_SHA256 = '23bf70f5078a5f6f9fbe0aca3a4348255caf14582a080e3a7f91fca733bba30a'


def replay_source(cache):
    """Derive only the reviewed final replay loop from the sealed selected Toolkit."""
    mod = Path(cache) / 'mods/PZSurvivorToolkit'
    source = selected_mod_version(mod) / REPLAY_PATH
    text = source.read_text(encoding='utf-8')
    begin = 'local function repairTidyFloor(character, callback, ...)\n'
    end = '\nlocal function installTidyFloorValidation()'
    loop = '    for _, action in ipairs(planned) do add(action) end'
    if text.count(begin) != 1 or text.count(end) != 1 or text.count(loop) != 1:
        raise ValueError('Washing MP replay source is not the unique reviewed helper')
    start, finish = text.index(begin), text.index(end)
    site = text.index(loop)
    if not start < site < finish:
        raise ValueError('Washing MP replay loop left the reviewed helper')
    body_sha256 = hashlib.sha256(text[start:finish].encode('utf-8')).hexdigest()
    if body_sha256 != REPLAY_BODY_SHA256:
        raise ValueError('Washing MP replay helper differs from its reviewed body')
    # Match SourceProof's Java readLine + UTF-16 code-unit Adler checksum.
    lines = text.split('\n')
    if lines[-1] == '': lines.pop()
    data = ''.join(line + '\n' for line in lines).encode('utf-16-le')
    value, total = 1, 0
    for i in range(0, len(data), 2):
        value = (value + data[i] + data[i + 1] * 256) % 65521
        total = (total + value) % 65521
    return dict(mod='PZSurvivorToolkit', path=REPLAY_PATH, checksum=total * 65536 + value,
                helperSha256=body_sha256,
                replayLine=text[:site].count('\n') + 1,
                frameSuffix='/mods/PZSurvivorToolkit/' + source.relative_to(mod).as_posix())


def definitions():
    return {'washing': {'status': 'ready', 'clients': 1, 'default_mods': MODS,
                        'cases': [dict(id=case, producer='fixture', capability='effect', kinds=['sp', 'mp'],
                                       languages=['EN'], modes=['native', 'toolkit']) for case in CASES]}}


def validate(selection):
    cases, options = selection.get('cases'), selection.get('options', {})
    if (type(cases) is not list or not cases or cases != [case for case in CASES if case in cases]
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') not in ('native', 'toolkit')
            or selection.get('languages') != ['EN'] or type(selection.get('clients', 1)) is not int
            or selection.get('clients', 1) != 1 or type(options) is not dict or options.get('world_template')
            or selection.get('actor', 'client1') != 'client1' or not set(MODS) <= set(selection.get('mods', []))
            or selection.get('kind') == 'mp' and options.get('mp_host') is not True):
        raise ValueError('Washing requires ordered cases, fresh SP/menu Host, one EN client and WashFix')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [Path(__file__), Path(craft.__file__), *sorted((root / 'washing').rglob('*.lua')),
            *sorted((root / 'craft/scripts').rglob('*.txt')), root / 'health/shared/QueueHealthEvents.lua',
            *sorted((root / 'startup').rglob('*.lua'))]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    craft.stage_common(project, output, game, jdk, selection, locations, runtime)
    if selection['kind'] == 'mp' and any(case in CLOTHING_CASES for case in selection['cases']):
        proofs = []
        for role in runtime['roles'].values():
            proof = replay_source(role['cache']);proofs.append(proof)
            target = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua/shared/QueueWashingReplayProof.lua'
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('return {' + ','.join(k + '=' + (json.dumps(v) if isinstance(v, str) else str(v))
                                                   for k, v in proof.items()) + '}\n', encoding='utf-8')
        if not proofs or any(v != proofs[0] for v in proofs):
            raise ValueError('Washing MP replay source differs across sealed roles')


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(r'\[WASHING_TEST\] COMPLETE(?:\s|$)', text)) == 1


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def same(a, b):
    if number(a) and number(b):
        return math.isclose(a, b, rel_tol=2e-5, abs_tol=2e-5)
    if type(a) is not type(b):
        return False
    if isinstance(a, dict):
        return set(a) == set(b) and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b


def matches(value, expected):
    return isinstance(value, dict) and all(k in value and same(value[k], v) for k, v in expected.items())


def replay_matches(value, expected):
    # Source hashes and code lines require exact integers, never resource tolerances.
    return (type(value) is dict and set(value) == set(expected)
            and all(type(value[k]) is type(v) and value[k] == v for k, v in expected.items()))


def ids(values):
    return type(values) is list and all(type(v) is int for v in values) and len(set(values)) == len(values)


def clothing(value):
    if (not isinstance(value, dict) or type(value.get('id')) is not int or value.get('kind') not in GARMENTS
            or value.get('transforming') is not False
            or not all(number(value.get(k)) and 0 <= value[k] <= 100 for k in ('blood', 'dirt', 'wetness'))):
        return False
    parts = value.get('parts')
    return (type(parts) is list and bool(parts) and all(isinstance(p, dict) and type(p.get('index')) is int
            and all(number(p.get(k)) and 0 <= p[k] <= 1 for k in ('blood', 'dirt')) for p in parts)
            and len({p['index'] for p in parts}) == len(parts))


def prepared(value, case):
    if not isinstance(value, dict) or value.get('case') != case or case not in CASES:
        return False
    count = 2 if case == 'borrowed-batch' else 1
    sink, soap, garments = value.get('sink'), value.get('soap'), value.get('garments')
    return (type(value.get('actorId')) is int and type(value.get('bagId')) is int
            and value.get('bagType') == 'Base.Bag_ALICEpack_Army' and type(value.get('book')) is int
            and isinstance(sink, dict) and all(type(sink.get(k)) is int for k in ('x', 'y', 'z', 'objectIndex'))
            and sink['objectIndex'] >= 0 and sink.get('sprite') == 'location_business_office_generic_01_49'
            and sink.get('entity') == 'Base.WaterDispenser' and same(sink.get('capacity'), 15)
            and isinstance(sink.get('ownerToken'), str) and sink['ownerToken'].startswith(case + ':')
            and all(number(sink.get(k)) and sink[k] > 0 for k in ('amount', 'capacity'))
            and same(sink['amount'], sink['capacity']) and sink['amount'] < 10000
            and matches(sink, dict(moved=True, usesExternalWaterSource=False, canBeWaterPiped=True, inputLocked=True))
            and isinstance(soap, dict) and type(soap.get('id')) is int and soap.get('kind') == 'Base.Soap2'
            and type(soap.get('uses')) is int and soap['uses'] > count
            and type(garments) is list and len(garments) == count
            and [v.get('kind') for v in garments if isinstance(v, dict)] == GARMENTS[:count]
            and all(clothing(v) and v['blood'] > 0 and v['dirt'] > 0 and v['wetness'] == 0
                    and v.get('requiredSoap') == sum(p['blood'] > 0 for p in v['parts'])
                    and type(v.get('requiredSoap')) is int and v['requiredSoap'] == 1
                    and type(v.get('requiredWater')) is int
                    and v['requiredWater'] == math.ceil(4 + sum(p['blood'] * 3 + p['dirt'] for p in v['parts']))
                    for v in garments)
            and sink['amount'] > sum(v['requiredWater'] for v in garments)
            and ids(value.get('allIds')) and value['allIds'] == sorted(value['allIds'])
            and ids([value['bagId'], value['book'], soap['id'], *[v['id'] for v in garments]])
            and set([value['bagId'], value['book'], soap['id'], *[v['id'] for v in garments]]) <= set(value['allIds']))


def p4_restoration(record, prep, reset, replay_proof=None):
    """One native same-item return from the pinned P4 reequip add site, not a WMI continuation."""
    if not isinstance(reset, dict) or not isinstance(record, dict):
        return False
    original = next((v for v in prep['garments'] if v['id'] == record.get('id')), None)
    trace = record.get('creation')
    if original is None or not isinstance(trace, dict):
        return False
    frames = trace.get('frames')
    return (matches(record, dict(kind='ISInventoryTransferAction', postReset=True, ownedRestore=True,
                                pickup=False, returned=True, progress=True, sourceProof=True, methodsUnchanged=True))
            and record.get('behavior') in ('native.ISInventoryTransferAction', 'compat.tidy-transfers')
            and matches(trace, dict(itemId=original['id'], itemKind=original['kind'], actorMatches=True, fromRoot=True, toDeclaredBag=True,
                    destinationBagId=prep['bagId'], destinationBagType=prep['bagType'], rootPresent=True, noCallbacks=True,
                    p4SourceVerified=True, stackAvailable=True, onStart='nil', onComplete='nil', onCancel='nil'))
            and type(trace.get('generation')) is int and type(reset.get('beforeGeneration')) is int
            and trace['generation'] >= reset['beforeGeneration'] and number(trace.get('at')) and trace['at'] >= 0
            and type(frames) is list and 0 < len(frames) <= 32
            and all(isinstance(f, dict) and isinstance(f.get('file'), str) and type(f.get('line')) is int for f in frames)
            and (trace.get('p4RestoreSite') is True and any(f['file'].replace('\\', '/').rsplit('/', 1)[-1] == 'P4TidyUpMeister.lua' and f['line'] == 839
                    and any(g['file'].replace('\\', '/') == f['file'].replace('\\', '/') and g['line'] == 895 for g in frames[i + 1:])
                    for i, f in enumerate(frames))
                 or replay_proof is not None and trace.get('compatReplaySite') is True
                    and replay_matches(trace.get('replayProof'), dict(replay_proof, verified=True))
                    and any(f['file'].replace('\\', '/').endswith(replay_proof['frameSuffix']) and f['line'] == replay_proof['replayLine'] for f in frames)))


def body_snapshot(value):
    if not isinstance(value, dict) or not ids(value.get('makeupIds')):
        return False
    parts = value.get('parts')
    return (type(parts) is list and len(parts) == 18 and all(isinstance(p, dict) and type(p.get('index')) is int
            and p['index'] == i and all(number(p.get(k)) and 0 <= p[k] <= 1 for k in ('blood', 'dirt'))
            for i, p in enumerate(parts)))


def body_prepared(p, case):
    if not isinstance(p, dict) or case not in BODY_CASES or p.get('case') != case:
        return False
    sink, soap, makeup, body = (p.get(k) for k in ('sink', 'soap', 'makeup', 'body'))
    if not body_snapshot(body): return False
    return (type(p.get('actorId')) is int and type(p.get('book')) is int
            and isinstance(sink, dict) and all(type(sink.get(k)) is int for k in ('x', 'y', 'z', 'objectIndex'))
            and sink['objectIndex'] >= 0 and matches(sink, dict(sprite='location_business_office_generic_01_49', entity='Base.WaterDispenser',
                capacity=15, amount=1 if case == 'body-water-limited' else 15, moved=True, usesExternalWaterSource=False, canBeWaterPiped=True, inputLocked=True))
            and isinstance(sink.get('ownerToken'), str) and sink['ownerToken'].startswith(case + ':')
            and isinstance(soap, dict) and type(soap.get('id')) is int and soap.get('kind') == 'Base.Soap2'
            and type(soap.get('uses')) is int and soap['uses'] > 1
            and isinstance(makeup, dict) and type(makeup.get('id')) is int and makeup.get('kind') == 'Base.MakeUp_Crow'
            and isinstance(makeup.get('slot'), str) and makeup['slot'] == 'base:makeup_eyes'
            and matches(p.get('weather'), dict(precipitation=0, rain=0, snow=0, rainAlwaysClean=False))
            and body['makeupIds'] == [makeup['id']]
            and body['parts'][0]['blood'] > 0 and body['parts'][0]['dirt'] > 0
            and body['parts'][1]['blood'] == 0 and body['parts'][1]['dirt'] > 0
            and all(v['blood'] == v['dirt'] == 0 for v in body['parts'][2:])
            and matches(p, dict(requiredWater=2, requiredSoap=1, expectedDuration=70 if case == 'body-water-limited' else 140))
            and ids(p.get('allIds')) and p['allIds'] == sorted(p['allIds'])
            and ids([p['book'], soap['id'], makeup['id']]) and set([p['book'], soap['id'], makeup['id']]) <= set(p['allIds']))


def check_body_case(selection, row, p, receipt):
    if not isinstance(p, dict) or not body_prepared(p, p.get('case')):
        return ['Body native preparation/identity/seed differs']
    if not isinstance(row, dict) or not isinstance(receipt, dict): return ['Body actor/server evidence is not an object']
    cancel, enabled = p['case'] == 'body-cancel', selection['mode'] == 'toolkit'
    charged = 0 if cancel else 1 if p['case'] == 'body-water-limited' else 2
    issues = []
    def fail(reason): issues.append(reason + ': ' + p['case'])
    soap_list = dict(shape='java-list', count=1, ownOnly=True, items=[p['soap']])
    if (not matches(row, dict(status='passed', sourceMethodsUnchanged=True, nativeSourceVerified=True, localDeferrals=0,
            tailProgress=True, tailIndependent=True, originalTailStarted=not cancel, reset=cancel, lateSourceActions=0))
            or not matches(row.get('menu'), dict(method='WS.WMI_BuildWashMenu+ISContextMenu.onMouseUp', choice='yourself', exactArguments=True,
                actorMatches=True, sinkMatches=True, closeContextMatches=True, soapList=soap_list))
            or not isinstance(row.get('menu', {}).get('callback'), str)):
        fail('Real native Yourself menu/progress/reset evidence differs')
    expected_parts = [dict(v, blood=0, dirt=0) if i < charged else dict(v) for i, v in enumerate(p['body']['parts'])]
    remaining_ids = p['allIds'] if cancel else [v for v in p['allIds'] if v != p['makeup']['id']]
    water = p['sink']['amount'] - charged
    if (not matches(receipt, dict(case=p['case'], actorId=p['actorId'], bookId=p['book'], tailRead=True, allIds=remaining_ids,
            weather=p['weather'], body=dict(parts=expected_parts, makeupIds=[p['makeup']['id']] if cancel else []),
            soap=dict(p['soap'], uses=p['soap']['uses'] - int(not cancel), rootCount=1, totalCount=1),
            makeup=dict(p['makeup'], rootCount=int(cancel), totalCount=int(cancel), worn=cancel),
            sink=dict(source=p['sink'], amount=water, fluidAmount=water, pureWater=water > 0,
                moved=True, usesExternalWaterSource=False, canBeWaterPiped=True, inputLocked=True)))
            or not matches(row, {k: v for k, v in receipt.items() if k != 'case'}) or not same(row.get('actualResources'), receipt)):
        fail('Authoritative body/soap/water/makeup/identity cost or client view differs')
    records = row.get('records')
    if type(records) is not list or len(records) != 1 or not isinstance(records[0], dict):
        return issues + ['Exactly one original native body action required']
    record = records[0]
    if (not matches(record, dict(kind='ISWashYourself', actorId=p['actorId'], duration=p['expectedDuration'], progress=True,
            behavior='native.ISWashYourself', sourceProof=True, methodsUnchanged=True, sinkMatches=True,
            soaps=soap_list, requiredWater=2, requiredSoap=1)) or record.get('failedBoundary')):
        fail('Original native body class, actor, soap selection, duration or progress differs')
    begin, finish, shared = record.get('begin'), record.get('finish'), record.get('sharedFinish')
    for values in (begin, finish, shared):
        if not isinstance(values, dict) or set(values) != {'perform', 'complete', 'stop'} or not all(type(v) is int and 0 <= v <= 1 for v in values.values()):
            return issues + ['Body native boundary envelope missing or repeated']
    if not same(begin, finish): fail('Body native boundary did not finish once')
    if cancel:
        if begin['perform'] or begin['complete'] or any(shared.values()): fail('Canceled body action completed or claimed a shared effect')
        reset = row.get('resetProof')
        if (not matches(reset, dict(method='ISTimedActionQueue.clear', oldTailRemoved=True, freshIndependent=True))
                or not number(reset.get('progress')) or not 0 < reset['progress'] < .25
                or not all(type(reset.get(k)) is int for k in ('beforeGeneration', 'afterGeneration', 'freshGeneration'))
                or reset['afterGeneration'] <= reset['beforeGeneration'] or reset['freshGeneration'] != reset['afterGeneration']
                or not number(row.get('lateObservedMs')) or row['lateObservedMs'] < 3000):
            fail('Body reset/fresh reader/late-callback observation differs')
    else:
        phases = dict(perform=1, complete=int(selection['kind'] == 'sp'), stop=0)
        if not same(begin, phases) or not same(shared, {k: int(enabled) * v for k, v in phases.items()}):
            fail('Body bypassed common native lifecycle or entered legacy completion scope')
    return issues


def check_case(selection, row, prep, receipt, replay_proof=None):
    if isinstance(prep, dict) and prep.get("case") in BODY_CASES:
        return check_body_case(selection, row, prep, receipt)
    if not isinstance(prep, dict) or not prepared(prep, prep.get('case')):
        return ['Washing native preparation/identity/resource envelope differs']
    if not isinstance(row, dict) or not isinstance(receipt, dict):
        return ['Washing actor/server receipt is not an object']
    cancel, enabled = prep['case'] == 'cancel-after-pickup', selection['mode'] == 'toolkit'
    no_soap = prep['case'] == 'borrowed-batch'
    issues = []
    def fail(reason):
        issues.append(reason + ': ' + prep['case'])
    records = row.get('records')
    if type(records) is not list or not all(isinstance(v, dict) for v in records):
        return ['Native washing action observations missing']
    cleanup = [v for v in records if v.get('postReset') is True]
    live_replay = (replay_proof if selection['kind'] == 'mp'
                   and replay_matches(row.get('replayProof'), dict(replay_proof or {}, verified=True)) else None)
    approved_cleanup = [v for v in cleanup if p4_restoration(v, prep, row.get('resetProof'), live_replay)
                        and (enabled or v.get('behavior') == 'native.ISInventoryTransferAction')]
    if (any(v.get('revivedAfterReset') for v in records) or len(approved_cleanup) != len(cleanup)
            or not cancel and cleanup or len(approved_cleanup) > 1
            or type(row.get('ownedCleanupActions', 0)) is not int or row.get('ownedCleanupActions', 0) != len(approved_cleanup)
            or row.get('creationOverflow', False) is not False):
        fail('Post-reset source work is not one proven native P4 owned restoration')
    if (not matches(row, dict(status='passed', sourceMethodsUnchanged=True, localDeferrals=0, tailProgress=True, tailIndependent=True,
                             lateSourceActions=0, reset=cancel, originalTailStarted=not cancel,
                             returnsBeforeRead=not cancel))
            or not matches(row.get('menu'), dict(method='WS.WMI_BuildWashMenu+ISContextMenu.onMouseUp',
                    exactArguments=True, noSoap=no_soap, requested=len(prep['garments']), bagWorn=True,
                    soapId=prep['soap']['id'],soapUses=prep['soap']['uses'],choice='bag-aggregate' if no_soap else 'bag-individual'))
            or not isinstance(row.get('menu', {}).get('callback'), str)):
        fail('Real native menu, callbacks, tail or reset contract differs')
    menu = row.get('menu')
    input_ids = menu.get('inputIds') if isinstance(menu, dict) else None
    if not ids(input_ids) or sorted(input_ids) != sorted(v['id'] for v in prep['garments']):
        fail('Native flat menu selected another physical clothing batch')
    soaps = menu.get('soapList') if isinstance(menu, dict) else None
    if (not isinstance(soaps, dict) or soaps.get('shape') not in ('lua-table', 'java-list')
            or not matches(soaps, dict(count=1, ownOnly=True, items=[prep['soap']])) or soaps.get('truncated')):
        fail('Actual native soap-list argument shape or exact items differ')
    if (not matches(receipt, dict(case=prep['case'], actorId=prep['actorId'], bagId=prep['bagId'], bagType=prep['bagType'],
                                  bagRootCount=1, bookId=prep['book'], tailRead=True, allIds=prep['allIds']))
            or not matches(row, {k: v for k, v in receipt.items() if k != 'case'})):
        fail('Native authority identity, conservation or reader receipt differs')
    expected_soap = prep['soap']['uses'] - (0 if cancel or no_soap else sum(v['requiredSoap'] for v in prep['garments']))
    if not matches(receipt.get('soap'), dict(id=prep['soap']['id'], kind='Base.Soap2', uses=expected_soap, rootCount=1, totalCount=1)):
        fail('Actual soap uses differ from native covered-part charges')
    expected_water = prep['sink']['amount'] - (0 if cancel else sum(v['requiredWater'] for v in prep['garments']))
    if not matches(receipt.get('sink'), dict(source=prep['sink'], amount=expected_water, fluidAmount=expected_water, pureWater=True,
                                            moved=True, usesExternalWaterSource=False, canBeWaterPiped=True, inputLocked=True)):
        fail('Actual finite sink water debit differs')
    garments = receipt.get('garments')
    if type(garments) is not list or len(garments) != len(prep['garments']) or not all(clothing(v) for v in garments):
        return issues + ['Washing final clothing snapshots missing']
    for actual, before in zip(garments, prep['garments']):
        restored = any(v['id'] == before['id'] for v in approved_cleanup)
        if not matches(actual, dict(id=before['id'], kind=before['kind'], totalCount=1,
                                    rootCount=int(cancel and not restored), sourceCount=int(not cancel or restored))):
            fail('Same-ID clothing was duplicated, transformed or returned to another endpoint')
        if cancel:
            if not matches(actual, {k: before[k] for k in ('blood', 'dirt', 'parts')}):
                fail('Canceled wash changed clothing')
        elif (actual['blood'] != 0 or actual['dirt'] != 0
              or not same(actual['parts'], [dict(p, blood=0, dirt=0) for p in before['parts']])):
            fail('Native wash did not clean covered blood/dirt')
    local = row.get('actualResources')
    if not isinstance(local, dict):
        fail('Independent local resource snapshot missing')
    else:
        # Wetness dries naturally between client and server observations.
        for key, value in receipt.items():
            if key != 'garments' and not same(local.get(key), value):
                fail('Client and server resources disagree')
        observed = local.get('garments')
        if type(observed) is not list or len(observed) != len(garments) or not all(clothing(v) for v in observed):
            fail('Client clothing view missing')
        else:
            for a, b in zip(observed, garments):
                if not matches(a, {k: v for k, v in b.items() if k != 'wetness'}):
                    fail('Client and server clothing views disagree')
    if cancel:
        reset = row.get('resetProof')
        if (not matches(reset, dict(method='ISTimedActionQueue.clear', id=prep['garments'][0]['id'],
                                   rootObserved=True, oldTailRemoved=True, freshIndependent=True))
                or not number(reset.get('progress')) or not 0 < reset['progress'] < .25
                or not all(type(reset.get(k)) is int for k in ('beforeGeneration', 'afterGeneration', 'freshGeneration'))
                or reset['afterGeneration'] <= reset['beforeGeneration']
                or reset['freshGeneration'] != reset['afterGeneration']
                or not number(row.get('lateObservedMs')) or row['lateObservedMs'] < 3000):
            fail('Native reset, fresh generation or late-callback observation missing')
    washes = [v for v in records if v.get('kind') == 'ISWashClothing']
    transfers = [v for v in records if v.get('kind') == 'ISInventoryTransferAction' and v.get('postReset') is not True]
    waits = [v for v in records if v.get('kind') == 'WMI_WaitForInvUpdate']
    if type(row.get('waitsObserved')) is not int or row['waitsObserved'] != len(waits):
        fail('Natural inventory-wait observation count differs')
    for wait in waits:
        if (wait.get('id') not in {v['id'] for v in prep['garments']} or wait.get('duration') != 1
                or type(wait.get('duration')) not in (int, float)
                or not matches(wait.get('begin'), dict(perform=int(enabled)))):
            fail('Original one-tick inventory wait binding or native boundary differs')
    if [v.get('id') for v in washes] != input_ids:
        fail('Native washes missing, duplicated or reordered')
    for r in records:
        owned_cleanup = r in approved_cleanup
        if not matches(r, dict(methodsUnchanged=True)):
            fail('Original native washing source methods changed')
        if enabled and not owned_cleanup:
            if not matches(r, dict(behavior=BEHAVIOR, sourceProof=True)):
                fail('Sealed washing family/source method proof differs')
        elif not owned_cleanup:
            unclassified = r.get('behavior') is None and r.get('sourceProof') is False
            native_transfer = r.get('kind') == 'ISInventoryTransferAction' and matches(r, dict(behavior='native.ISInventoryTransferAction', sourceProof=True))
            if not (unclassified or native_transfer):
                fail('Disabled queue claimed foreign integration ownership')
        if r.get('kind') not in ('ISWashClothing', 'ISInventoryTransferAction', 'WMI_WaitForInvUpdate') or r.get('id') not in {v['id'] for v in prep['garments']}:
            fail('Foreign native action in washing family observations')
        begin, finish = r.get('begin'), r.get('finish')
        if (not isinstance(begin, dict) or set(begin) != {'perform', 'complete', 'stop'}
                or not all(type(v) is int and 0 <= v <= 1 for v in begin.values()) or not same(begin, finish)
                or r.get('failedBoundary')):
            fail('Native shared lifecycle boundary was repeated or not finished')
        if (not enabled or owned_cleanup) and not same(begin, dict(perform=0, complete=0, stop=0)):
            fail('Shared washing lifecycle was claimed without enabled family ownership')
    original_by_id = {v['id']: v for v in prep['garments']}
    for r in washes:
        before = original_by_id.get(r.get('id'))
        if before is None:
            fail('Foreign native wash action');continue
        raw_duration = max(100, min(800, min(500, (before['blood'] + before['dirt']) * 15) * (5 if no_soap else 1)))
        if (not matches(r, dict(progress=True, inputRoot=True, noSoap=no_soap, bloodAmount=before['blood'], dirtAmount=before['dirt']))
                or not number(r.get('duration')) or r['duration'] < raw_duration
                or not matches(r.get('begin'), dict(perform=int(enabled and not cancel), complete=int(enabled and not cancel and selection['kind'] == 'sp')))):
            fail('Wash ran without real root input, native cost/progress or shared boundary')
    for before in prep['garments']:
        related = [v for v in transfers if v.get('id') == before['id']]
        if (len(related) != 2 or not related[0].get('pickup') or not related[1].get('returned')
                or related[0].get('progress') is not True or (not cancel and related[1].get('progress') is not True)):
            fail('Native same-ID pickup or original-container return chain differs')
        if selection['kind'] == 'mp' and any(not number(v.get('transactionDuration')) or v['transactionDuration'] <= 1 for v in related if v.get('progress')):
            fail('Native inventory transaction cost missing')
        if cancel and related and related[-1].get('progress') is True:
            fail('Old return revived after native clear')
    for restoration in approved_cleanup:
        if selection['kind'] == 'mp' and (not number(restoration.get('transactionDuration')) or restoration['transactionDuration'] <= 1):
            fail('Owned P4 restoration did not pay native transaction cost')
    return issues


def verify(root, selection, catalog):
    from ..report import events
    root, issues = Path(root), []
    replay_proof = None
    if selection['kind'] == 'mp' and any(case in CLOTHING_CASES for case in selection['cases']):
        try:
            replay_proof = replay_source(root / 'client1')
            if replay_source(root / 'server') != replay_proof:
                issues.append('Washing MP replay source differs between sealed actor/server')
        except (OSError, ValueError) as error:
            issues.append('Washing sealed MP replay source invalid: ' + str(error))
    text = (root / 'client1-launch.log').read_text(errors='replace')
    authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
    records, raw = events(text), []
    for match in re.finditer(r'\[WASHING_TEST\] (PREPARED|VERIFIED) (.*)', authority):
        try:
            value = json.loads(match.group(2))
            if not isinstance(value, dict): raise ValueError('not an object')
            raw.append((match.group(1), value))
        except (ValueError, TypeError) as error:
            issues.append('Invalid washing authority JSON: ' + str(error))
    cases = selection['cases']
    if [v.get('event') for v in records] != ['setup'] + ['case'] * len(cases) + ['complete']:
        issues.append('Missing, duplicated or reordered washing events')
    if [(k, v.get('case')) for k, v in raw] != [(k, c) for c in cases for k in ('PREPARED', 'VERIFIED')]:
        issues.append('Missing, duplicated or reordered washing authority')
    if not complete(selection, 'client1', text) or '[QUEUE_TEST] FAIL ' in text + authority:
        issues.append('Native washing fixture failed or completion missing')
    for row in records:
        if not matches(row, dict(suite='washing', kind=selection['kind'], mode=selection['mode'], actor='client1')):
            issues.append('Washing event context differs')
    for event, expected in [('setup', dict(cases=cases, expected=len(cases), queueEnabled=selection['mode'] == 'toolkit', nativeDurations=True)),
                            ('complete', dict(cases=cases, expected=len(cases), performed=len(cases), failed=0, skipped=0))]:
        rows = [v for v in records if v.get('event') == event]
        if len(rows) != 1 or not matches(rows[0], expected): issues.append('Washing ' + event + ' differs')
    rows = [v for v in records if v.get('event') == 'case']
    if [v.get('id') for v in rows] != cases: issues.append('Washing selected cases differ')
    outcomes = []
    for case in cases:
        row = next((v for v in rows if v.get('id') == case), {})
        prep = next((v for k, v in raw if k == 'PREPARED' and v.get('case') == case), {})
        receipt = next((v for k, v in raw if k == 'VERIFIED' and v.get('case') == case), {})
        failures = check_case(selection, row, prep, receipt, replay_proof)
        if case in CLOTHING_CASES and selection['kind'] == 'mp' and (replay_proof is None or not replay_matches(row.get('replayProof'), dict(replay_proof, verified=True))):
            failures.append('Live MP replay source does not match independently sealed source: ' + case)
        issues.extend(failures)
        outcomes.append(dict(actor='client1', case=case, status='failed' if failures else 'passed',
                             reason='; '.join(failures), outcome=row))
    if issues:
        for row in outcomes: row.update(status='failed', reason='; '.join(issues))
    evidence = {'limits': [
        'Ordinary non-transforming Clothing from a genuinely worn bag through the public WashFix flat menu; finite native sink, soap and same-ID endpoints.',
        'waitsObserved counts only naturally observed one-tick inventory waits; zero does not establish delayed-replication coverage.',
        'The real bag aggregate retains WashFix noSoap=true even with soap present; it cleans without consuming soap at native no-soap cost. The individual completed case independently covers actual soap consumption.',
        'Native clear after paid pickup/current wash cancels the old tail; a fresh independent reader must survive. One exact same-ID native P4 restoration is allowed only with its pinned creation site or source-verified MP final replay loop, original bag, no callbacks and unchanged resources; late WashFix continuations fail. No expanded edit permissions, aggregate-All or bandage transformations. Separate body cases use existing native.ISWashYourself through the real Yourself menu with enum-ordered dirty parts, one worn Crow makeup item and partial-water/native-reset controls.']}
    if selection['kind'] == 'mp': evidence['replaySource'] = replay_proof
    return dict(issues=issues, outcomes=outcomes, evidence=evidence)
