import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import adapters
from queue_checks.adapters import wring_clothing as a
from tests.test_queue_tv_controls_adapter import placement_proof as tile_placement_proof

PROJECT = Path(__file__).resolve().parents[1]


def placement_proof(target, mode='local'):
    proof = tile_placement_proof(target, mode)
    proof.update(centered=True, centers=1 if mode == 'local' else 0)
    proof['actual'].update(x=target['x'] + .5, y=target['y'] + .5)
    return proof


def worn_alias_fixture():
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().fixture = str(PROJECT / 'tests/native_queue/wring-clothing/shared/QueueWringClothing.lua')
    lua.execute(r'''
package.loaded.QueueEnergyPlacement={atCentered=function()return true end}
function instanceof(value,kind)return value.class==kind end
function getClassSimpleName(value)return value.class end
F=dofile(fixture)
local function location(name)return setmetatable({class='ItemBodyLocation'},{__tostring=function()return 'base:'..name end})end
local shoes,socks=location('shoes'),location('socks')
ItemBodyLocation=setmetatable({SHOES=shoes,SOCKS=socks},{__index=function(_,key)return key end})
root={};local values={};local slot
local function item(id,kind,body)
 return{class='Clothing',getID=function()return id end,getFullType=function()return kind end,
 getBodyLocation=function()return body end,getContainer=function()return root end,getWetness=function()return 99 end,
 getActualWeight=function()return .1 end,hasTag=function()return false end,getCategory=function()return 'Clothing'end,
 IsClothing=function()return true end,setJobType=function()end,setJobDelta=function()end,getName=function()return kind end}
end
function root:getItems()return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
function root:getItemById(id)for _,value in ipairs(values)do if value:getID()==id then return value end end end
player={getInventory=function()return root end,getWornItem=function(_,body)return body==shoes and slot or nil end,
 setWornItem=function(_,body,value)assert(body==shoes);slot=value end,
 getWornItems=function()return{contains=function(_,value)return value==slot end,
 getItemById=function(_,id)return slot and slot:getID()==id and slot or nil end}end,
 reportEvent=function()end,playSound=function()return 0 end,
 getHumanVisual=function()return{getHairModel=function()return{contains=function()return false end}end}end}
ids={case='worn',nativeWearSetup=true,origin={},source={kind='worn',bag=false,world=false},items={}}
for i,name in ipairs(F.names)do
 local shoe=name=='target'or name=='tail';local body=shoe and shoes or socks
 local kind=shoe and 'Base.Shoes_FlipFlop'or 'Base.Socks_Ankle'
 local value=item(i,kind,body);values[i]=value
 local spec=F.nativeWetnessContract(value);spec.id=i;spec.type=kind;ids.items[name]=spec
end
canonical=values[2];proxy=item(2,'Base.Shoes_FlipFlop',shoes);slot=proxy
assert(F.resolve(player,ids)==nil,'same-ID worn alias was accepted as canonical')
state=assert(F.resolve(player,ids,true),'declared provisional native wear input could not resolve')
assert(F.wearBaseline(state)==nil,'same-ID worn alias became authority baseline')
local diagnostic=F.preparedDiagnostic(player,ids)
assert(diagnostic.items.target.present and diagnostic.items.target.exactOwner and diagnostic.items.target.wetness==99)
assert(diagnostic.items.target.wornId==2 and diagnostic.items.target.slotId==2 and not diagnostic.items.target.wornSame)
assert(not diagnostic.items.target.canonicalWorn and not diagnostic.items.target.slotSame,'prepared diagnostic hid worn alias')
''')
    return lua


def evidence(kind='mp', mode='toolkit', case='root'):
    origin = dict(x=11, y=20, z=0)
    source = dict(kind=case, bag=20 if case == 'worn-bag' else False,
                  world=dict(x=11, y=19, z=0, index=1) if case == 'world' else False)
    specs = {}
    for index, name in enumerate(a.NAMES):
        shoes = name == 'tail' or name == 'target' and case in ('worn', 'world')
        specs[name] = dict(id=10 + index, type='Base.Shoes_FlipFlop' if shoes else 'Base.Socks_Ankle',
                           cap=10, nativeShoe=False, bodyLocationClass='ItemBodyLocation',
                           bodyLocation='base:shoes' if shoes else 'base:socks', initial=100, weight=.1)
    ids = dict(case=case, mode=mode, source=source, origin=origin, items=specs,
               placementProof=placement_proof(origin, 'replica' if kind == 'mp' else 'local'))
    carried = case == 'worn-bag'
    if carried:
        ids['preparedGroups'] = True
        for spec in specs.values(): spec.update(wetWeight=.125, capacityWeight=.1)
    native_wear = kind == 'mp' and case in ('worn', 'worn-bag')
    if native_wear: ids['nativeWearSetup'] = True
    def snapshot(final):
        return dict(case=case, source=copy.deepcopy(source), items={
            name: dict(id=spec['id'], type=spec['type'], wetness=99 if not final or name == 'cancelled' and not(carried and mode == 'native') else spec['cap'],
                       native={key: spec[key] for key in ('bodyLocation', 'bodyLocationClass', 'nativeShoe', 'cap')},
                       weight=.1, worn=not final and case == 'worn' and name == 'target', counts=a._counts(case, name, final))
            for name, spec in specs.items()})
    editing = mode == 'toolkit' and case == 'root'
    plan = [('front', 'ISWringClothing')]
    if carried:
        plan += ([('cancelled', 'ISQueueActionsAction')] if mode == 'toolkit' else []) + [('cancelled', 'ISInventoryTransferAction'), ('cancelled', 'ISWringClothing')]
    elif editing: plan += [('cancelled', 'ISWringClothing')]
    if case == 'worn': plan += [('target', 'ISUnequipAction')]
    if carried and mode == 'toolkit': plan += [('target', 'ISQueueActionsAction')]
    if case in ('worn-bag', 'world'): plan += [('target', 'ISInventoryTransferAction')]
    plan += [('target', 'ISWringClothing')]
    if editing: plan += [('repeat', 'ISWringClothing')]
    plan += [('tail', 'ISWringClothing')]
    commands = []
    for index, (name, type_) in enumerate(plan):
        cancelled = editing and name in ('cancelled', 'repeat') or carried and mode == 'toolkit' and name == 'cancelled'
        command = dict(name=name, type=type_, producer=a.PRODUCER, item=specs['target' if name == 'repeat' else name]['id'],
                       duration=495 if type_ == 'ISWringClothing' else -1 if type_ == 'ISInventoryTransferAction' and kind == 'mp' else 50,
                       started=not cancelled, progress=not cancelled)
        if cancelled: command['cancelled'] = True
        else: command['startedAt'] = 100 + index
        if type_ == 'ISWringClothing': command.update(constructorWetness=99, callbacksUntouched=True)
        commands.append(command)
    final = snapshot(True)
    row = dict(ids=copy.deepcopy(ids), clientPlacement=placement_proof(origin), input=snapshot(False),
               client=copy.deepcopy(final), server=copy.deepcopy(final), status='passed', queueIdle=True,
               settleMilliseconds=1000, commands=commands,
               edit=dict(cancelled=editing or carried and mode == 'toolkit', reordered=editing or carried and mode == 'toolkit', repeatDenied=editing, untouched=True))
    if native_wear:
        row.update(authorityBaseline=snapshot(False), wearSetup=dict(type='ISWearClothing', producer='native ISWearClothing constructor',
            item=specs['target']['id'] if case == 'worn' else source['bag'], duration=50, started=True, progress=True, startedAt=10))
    if carried:
        for phase in ('input', 'client', 'server', 'authorityBaseline'):
            if phase in row:
                for value in row[phase]['items'].values(): value.update(wetWeight=.1 + value['wetness'] / 100 * .025, capacityWeight=.1)
        final = copy.deepcopy(row['server'])
        editing_group = mode == 'toolkit'; count = 3 if editing_group else 2
        for index, command in enumerate(commands):
            command.update(actionRef='native-action-' + str(index), operation=dict(front=1, cancelled=2, target=3, tail=4)[command['name']])
            if command['type'] == 'ISWringClothing' and not command.get('cancelled'):
                start = copy.deepcopy(row['input']['items'][command['name']]);start['counts'] = dict(actor=1, root=1, source=0)
                command['rootAtStart'] = start
            elif command['type'] == 'ISQueueActionsAction':
                command.update(duration=-1, started=False, progress=False, admitted=not command.get('cancelled', False),
                    preparation=dict(container=source['bag'], owned=True, callbacksUntouched=True))
                command.pop('startedAt', None)
                if not command.get('cancelled'):
                    command['resolver'] = [dict(boundary=boundary, phase=phase, succeeded=boundary == 'finish',
                        nativeRef='native-resolver-episode', nativeClass='LuaTimedActionNew', ownedContainer=True,
                        position={key: row['clientPlacement']['actual'][key] for key in ('x','y','z')}, unexpectedChildren=[], expansionClosed=True)
                        for phase in (('perform','complete') if kind == 'sp' else ('perform',)) for boundary in ('begin','finish')]
        refs = [command['actionRef'] for command in commands]
        cancel_indexes = list(range(1, count + 1)); target_indexes = list(range(count + 1, count * 2 + 1)); tail_index = len(commands) - 1
        def group(name, indexes):
            first, last = indexes[0], indexes[-1]
            result = dict(token=commands[first]['operation'], fetch=refs[last - 1], body=refs[last], item=specs[name]['id'], bounds=dict(first=first + 1, last=last + 1), unallocated=True)
            if editing_group:
                result['prep'] = refs[first]
                result['descriptor'] = dict(fetchSource='native.ISInventoryTransferAction', bodySource='native.ISWringClothing', item=specs[name]['id'],
                    actual='bag', requires='root', fetchSets='root', sourceBag=source['bag'], canonical=True, prepSource='toolkit.approach', prepOwned=True,
                    prepLease=dict(capacity='unchanged', owner=source['bag'], ownerRoot=True, effectsEmpty=True, fresh=True), bodyCapacity='external', fetchCapacity='external', projection='allowed')
            return result
        discarded = group('cancelled', cancel_indexes); kept = group('target', target_indexes)
        retained = [refs[0]] + [refs[index] for index in target_indexes] + [refs[tail_index]]
        moves = []
        if editing_group:
            discarded.update(selected=refs[cancel_indexes[-1]], accepted=True, afterOrder=retained)
            moves = [dict(selected=refs[target_indexes[-2]], after=True, accepted=True,
                          order=[refs[0], refs[tail_index]] + [refs[index] for index in target_indexes], bounds=dict(first=3, last=count + 2)),
                     dict(selected=refs[target_indexes[-1]], after=False, accepted=True, order=retained, bounds=dict(first=2, last=count + 1))]
        members = [dict(id=specs[name]['id'], type=specs[name]['type']) for name in (('target',) if editing_group else ('target', 'cancelled'))]
        members.sort(key=lambda item: item['id'])
        returns = [dict(actionRef='native-return', type='ISInventoryTransferAction', **{'from': 'root'}, toBag=source['bag'], duration=-1 if kind == 'mp' else 50,
            allowMissing=False, items=members, events=[dict(boundary='begin', phase='perform', nativeRef='native-return-episode'),
                                                     dict(boundary='finish', phase='perform', succeeded=True, nativeRef='native-return-episode')])]
        row['prepared'] = dict(sourceBag=source['bag'], front=refs[0], frontNative='native-front-episode', initialOrder=refs,
            cancelled=discarded, target=kept, moves=moves, finalOrder=retained if editing_group else refs, returns=returns,
            before=copy.deepcopy(row['input']), after=copy.deepcopy(row['input']))
    return row, dict(kind=kind, mode=mode), ids, final


class WringClothingEvidenceTests(unittest.TestCase):
    def test_selected_pack_and_grouped_sp_host_modes(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                selection = dict(suite='wring-clothing', cases=list(a.CASES), kind=kind, mode=mode, languages=['EN'],
                                 clients=1, mods=a.MODS, options={'mp_host': True} if kind == 'mp' else {})
                a.validate(selection)
                self.assertIs(adapters.get('wring-clothing'), a)
                for case in a.CASES:
                    self.assertEqual([], a.check_case(*evidence(kind, mode, case)))
        selection['options'] = {}
        with self.assertRaises(ValueError): a.validate(selection)
        selection['options'] = {'mp_host': True, 'world_template': 'old-save'}
        with self.assertRaises(ValueError): a.validate(selection)

    def test_carried_only_selector_preserves_historical_cases(self):
        base = dict(suite='wring-clothing', kind='mp', mode='toolkit', languages=['EN'], clients=1, mods=a.MODS, options={'mp_host': True})
        for chosen in (['worn-bag'], ['root', 'worn-bag'], list(a.CASES)):
            a.validate(dict(base, cases=chosen))
        for chosen in ([], ['worn-bag', 'root'], ['worn-bag', 'worn-bag'], ['bag-magazine']):
            with self.assertRaises(ValueError): a.validate(dict(base, cases=chosen))
        self.assertTrue(a.complete(dict(base, cases=['worn-bag']), 'client1', a.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=['worn-bag']))))

    def test_prepared_groups_require_exact_tokens_bounds_moves_and_unadmitted_cancel(self):
        for change in ('split-token', 'front-token', 'split-order', 'wrong-bound', 'wrong-selection', 'missing-body-move',
                       'cancelled-admitted', 'cancelled-physical', 'fetch-not-started', 'wrong-start-owner', 'wrong-facts',
                       'root-not-required', 'missing-fetch-projection', 'physical-edit', 'future-drying-credit', 'allocated', 'forged-pending-source'):
            result = evidence(case='worn-bag'); row = result[0]; prepared = row['prepared']
            body = next(command for command in row['commands'] if command['name'] == 'target' and command['type'] == 'ISWringClothing')
            fetch = next(command for command in row['commands'] if command['name'] == 'target' and command['type'] == 'ISInventoryTransferAction')
            if change == 'split-token': body['operation'] = 100
            if change == 'front-token': fetch['operation'] = body['operation'] = row['commands'][0]['operation']
            if change == 'split-order': prepared['finalOrder'][1], prepared['finalOrder'][2] = prepared['finalOrder'][2], prepared['finalOrder'][1]
            if change == 'wrong-bound': prepared['target']['bounds']['first'] = 1
            if change == 'wrong-selection': prepared['moves'][0]['selected'] = prepared['target']['body']
            if change == 'missing-body-move': prepared['moves'].pop()
            if change == 'cancelled-admitted': row['commands'][2]['started'] = True
            if change == 'cancelled-physical': row['client']['items']['cancelled']['wetness'] = 10
            if change == 'fetch-not-started': fetch['started'] = False
            if change == 'wrong-start-owner': body['rootAtStart']['counts'] = dict(actor=1, root=0, source=1)
            if change == 'wrong-facts': prepared['target']['descriptor']['actual'] = 'root'
            if change == 'root-not-required': prepared['target']['descriptor']['requires'] = 'bag'
            if change == 'missing-fetch-projection': prepared['target']['descriptor']['projection'] = 'unhandled'
            if change == 'physical-edit': prepared['after']['items']['target']['wetness'] = 10
            if change == 'future-drying-credit': row['client']['items']['target']['capacityWeight'] = .01
            if change == 'allocated': prepared['cancelled']['unallocated'] = False
            if change == 'forged-pending-source':
                for phase in ('before','after'): prepared[phase]['items']['target']['counts'] = dict(actor=1, root=1, source=0)
            self.assertTrue(a.check_case(*result), change)

    def test_deferred_container_resolver_is_owned_real_closed_and_has_no_walk_expansion(self):
        for kind in ('sp','mp'):
            row = evidence(kind=kind, case='worn-bag')[0]
            self.assertEqual(['ISWringClothing','ISQueueActionsAction','ISInventoryTransferAction','ISWringClothing',
                              'ISQueueActionsAction','ISInventoryTransferAction','ISWringClothing','ISWringClothing'], [command['type'] for command in row['commands']])
            self.assertEqual([], a.check_case(*evidence(kind=kind, case='worn-bag')))
        for change in ('missing-prep', 'wrong-container', 'callbacks', 'cancel-admitted', 'cancel-resolved', 'no-real-perform', 'failed',
                       'missing-native', 'wrong-owner', 'open-expansion', 'walk-child', 'foreign-child', 'position', 'wrong-capacity', 'wrong-owner-key', 'stale-lease'):
            result = evidence(case='worn-bag'); row = result[0]
            prep = next(command for command in row['commands'] if command['name'] == 'target' and command['type'] == 'ISQueueActionsAction')
            cancelled = next(command for command in row['commands'] if command['name'] == 'cancelled' and command['type'] == 'ISQueueActionsAction')
            if change == 'missing-prep': row['commands'].remove(prep)
            if change == 'wrong-container': prep['preparation']['container'] = 999
            if change == 'callbacks': prep['preparation']['callbacksUntouched'] = False
            if change == 'cancel-admitted': cancelled['admitted'] = True
            if change == 'cancel-resolved': cancelled['resolver'] = copy.deepcopy(prep['resolver'])
            if change == 'no-real-perform': prep['resolver'] = []
            if change == 'failed': prep['resolver'][1]['succeeded'] = False
            if change == 'missing-native': prep['resolver'][0]['nativeRef'] = False
            if change == 'wrong-owner': prep['resolver'][0]['ownedContainer'] = False
            if change == 'open-expansion': prep['resolver'][0]['expansionClosed'] = False
            if change == 'walk-child': prep['resolver'][0]['unexpectedChildren'] = [dict(type='ISWalkToTimedAction', actionRef='native-walk')]
            if change == 'foreign-child': prep['resolver'][0]['unexpectedChildren'] = [dict(type='ISEquipWeaponAction', actionRef='foreign')]
            if change == 'position': prep['resolver'][0]['position']['x'] += 1
            if change == 'wrong-capacity': row['prepared']['target']['descriptor']['prepLease']['capacity'] = 'external'
            if change == 'wrong-owner-key': row['prepared']['target']['descriptor']['prepLease']['owner'] = 999
            if change == 'stale-lease': row['prepared']['target']['descriptor']['prepLease']['fresh'] = False
            self.assertTrue(a.check_case(*result), change)
        disabled = evidence(mode='native', case='worn-bag')
        self.assertNotIn('ISQueueActionsAction', [command['type'] for command in disabled[0]['commands']])
        disabled[0]['commands'][1]['type'] = 'ISQueueActionsAction'
        self.assertTrue(a.check_case(*disabled), 'disabled controls cannot adopt owned deferred preparation')

    def test_native_p4_return_requires_exact_earned_item_endpoint_episode_and_success(self):
        for mode in ('native', 'toolkit'):
            self.assertEqual([], a.check_case(*evidence(case='worn-bag', mode=mode)))
        for change in ('missing-return', 'wrong-id', 'cancelled-return', 'wrong-bag', 'missing-native', 'failed', 'missing-finish', 'wrong-duration'):
            result = evidence(case='worn-bag'); receipt = result[0]['prepared']['returns'][0]
            if change == 'missing-return': result[0]['prepared']['returns'] = []
            if change == 'wrong-id': receipt['items'][0]['id'] = 999
            if change == 'cancelled-return': receipt['items'].append(dict(id=result[2]['items']['cancelled']['id'], type='Base.Socks_Ankle'))
            if change == 'wrong-bag': receipt['toBag'] = 999
            if change == 'missing-native': receipt['events'][0]['nativeRef'] = False
            if change == 'failed': receipt['events'][1]['succeeded'] = False
            if change == 'missing-finish': receipt['events'].pop()
            if change == 'wrong-duration': receipt['duration'] = 50
            self.assertTrue(a.check_case(*result), change)

    def test_centered_placement_rejects_tile_edges_and_unproven_centering(self):
        for kind in ('sp', 'mp'):
            result = evidence(kind=kind)
            result[0]['clientPlacement']['actual']['x'] = result[2]['origin']['x']
            self.assertTrue(a.check_case(*result))
            result = evidence(kind=kind)
            result[2]['placementProof']['actual']['y'] = result[2]['origin']['y']
            result[0]['ids'] = copy.deepcopy(result[2])
            self.assertTrue(a.check_case(*result))
            result = evidence(kind=kind)
            del result[0]['clientPlacement']['centered']
            self.assertTrue(a.check_case(*result))
            result = evidence(kind=kind)
            result[0]['clientPlacement']['centers'] = 0
            self.assertTrue(a.check_case(*result))

    def test_drying_bounds_preserve_observed_native_caps(self):
        for case in a.CASES:
            result = evidence(case=case)
            for phase in ('client', 'server'):
                for name in ('front', 'target', 'tail'):
                    result[0][phase]['items'][name]['wetness'] -= 1
            result[3].update(copy.deepcopy(result[0]['server']))
            self.assertEqual([], a.check_case(*result))
        for case, name, wetness in [('root', 'target', 60), ('world', 'target', 60), ('root', 'cancelled', 10)]:
            result = evidence(case=case); result[0]['client']['items'][name]['wetness'] = wetness
            self.assertTrue(a.check_case(*result))

    def test_exact_input_source_debit_identity_and_equipment(self):
        for case in a.CASES:
            for phase in ('input', 'client', 'server'):
                result = evidence(case=case); result[0][phase]['items']['target']['counts']['source'] += 1
                self.assertTrue(a.check_case(*result))
                result = evidence(case=case); result[0][phase]['items']['target']['id'] += 1
                self.assertTrue(a.check_case(*result))
        result = evidence(case='worn'); result[0]['client']['items']['target']['worn'] = True
        self.assertTrue(a.check_case(*result))
        result = evidence(case='world'); result[2]['source']['world']['x'] += 1; result[0]['ids'] = copy.deepcopy(result[2])
        self.assertTrue(a.check_case(*result))
        for case in ('worn-bag', 'world'):
            result = evidence(case=case); result[0]['client']['items']['target']['counts']['root'] = 1
            self.assertTrue(a.check_case(*result))

    def test_native_preludes_durations_and_pending_only_edits(self):
        for case in ('worn', 'worn-bag', 'world'):
            result = evidence(case=case); result[0]['commands'].pop(1)
            self.assertTrue(a.check_case(*result))
        for change in ('callbacks', 'duration', 'progress', 'cancelled', 'dependency', 'untouched', 'tail'):
            result = evidence(); row = result[0]
            if change == 'callbacks': row['commands'][0]['callbacksUntouched'] = False
            if change == 'duration': row['commands'][0]['duration'] = 1
            if change == 'progress': row['commands'][0]['progress'] = False
            if change == 'cancelled': row['commands'][1]['started'] = True
            if change == 'dependency': row['edit']['repeatDenied'] = False
            if change == 'untouched': row['edit']['untouched'] = False
            if change == 'tail': row['commands'].pop()
            self.assertTrue(a.check_case(*result), change)

    def test_transfer_wait_sentinel_is_specific_to_native_mp_wrapper(self):
        for case in ('worn-bag', 'world'):
            for mode in ('native', 'toolkit'):
                result = evidence(mode=mode, case=case)
                self.assertEqual([], a.check_case(*result))
                for duration in (0, -2, 50, False):
                    result = evidence(mode=mode, case=case); next(command for command in result[0]['commands'] if command['type'] == 'ISInventoryTransferAction')['duration'] = duration
                    self.assertTrue(a.check_case(*result))
                result = evidence(kind='sp', mode=mode, case=case); next(command for command in result[0]['commands'] if command['type'] == 'ISInventoryTransferAction')['duration'] = -1
                self.assertTrue(a.check_case(*result))
        for case, index in (('root', 0), ('worn', 1)):
            result = evidence(case=case); result[0]['commands'][index]['duration'] = -1
            self.assertTrue(a.check_case(*result), 'wring/unequip must not inherit transfer sentinel')

    def test_captured_v6_host_command_rows_preserve_transfer_constructor_sentinel(self):
        # Emitted v6 Host receipts; IDs/clocks are normalized by evidence().
        captured = [('front', 'ISWringClothing', 500), ('target', 'ISInventoryTransferAction', -1),
                    ('target', 'ISWringClothing', 500), ('tail', 'ISWringClothing', 500)]
        for case in ('world',):
            result = evidence(mode='native', case=case)
            for command, (name, kind, duration) in zip(result[0]['commands'], captured):
                self.assertEqual((name, kind), (command['name'], command['type']))
                command['duration'] = duration
                if kind == 'ISWringClothing': command['constructorWetness'] = 100
            self.assertEqual([], a.check_case(*result))

    def test_authority_receipts_require_all_grouped_cases(self):
        selection = dict(kind='mp', mode='toolkit', cases=list(a.CASES)); cases = selection['cases']
        client = ['[QUEUE_CHECK] ' + json.dumps(dict(suite='wring-clothing', event='setup', cases=cases, queueEnabled=True, nativeDurations=True, adapterInstalled=True))]
        server = []
        for case in cases:
            row, _, ids, verified = evidence(case=case)
            row.update(suite='wring-clothing', event='case', id=case, actor='client1', kind='mp', mode='toolkit')
            client += [a.PREFIX + 'CLIENT_PLACEMENT ' + json.dumps(dict(case=case, proof=row['clientPlacement'])), '[QUEUE_CHECK] ' + json.dumps(row)]
            server.append(a.PREFIX + 'PREPARED ' + json.dumps(ids))
            if ids.get('nativeWearSetup'): server.append(a.PREFIX + 'WEAR_BASELINE ' + json.dumps(row['authorityBaseline']))
            server.append(a.PREFIX + 'VERIFIED ' + json.dumps(verified))
        client += ['[QUEUE_CHECK] ' + json.dumps(dict(suite='wring-clothing', event='complete', cases=cases, performed=len(cases), failed=0, skipped=0)),
                   a.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=cases))]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); (root / 'client1-launch.log').write_text('\n'.join(client)); (root / 'server-launch.log').write_text('\n'.join(server))
            self.assertEqual([], a.verify(root, selection, {})['issues'])
            false_setup = client.copy(); false_setup[0] = false_setup[0].replace('"adapterInstalled": true', '"adapterInstalled": false')
            (root / 'client1-launch.log').write_text('\n'.join(false_setup))
            self.assertTrue(a.verify(root, selection, {})['issues'])

            (root / 'client1-launch.log').write_text('\n'.join(client))
            (root / 'server-launch.log').write_text('\n'.join(server[:-1]))
            self.assertTrue(a.verify(root, selection, {})['issues'])

    def test_host_native_wear_setup_requires_exact_input_and_authority_baseline(self):
        for case in ('worn', 'worn-bag'):
            result = evidence(case=case)
            self.assertEqual([], a.check_case(*result, copy.deepcopy(result[0]['authorityBaseline'])))
            result = evidence(case=case); result[0]['wearSetup']['duration'] = 1
            self.assertTrue(a.check_case(*result))
            result = evidence(case=case); result[0]['wearSetup']['progress'] = False
            self.assertTrue(a.check_case(*result))
            result = evidence(case=case); result[0]['wearSetup']['item'] += 100
            self.assertTrue(a.check_case(*result))
            result = evidence(case=case); result[0]['authorityBaseline']['items']['target']['wetness'] = 10
            self.assertTrue(a.check_case(*result))
            result = evidence(case=case); baseline = copy.deepcopy(result[0]['authorityBaseline']); baseline['items']['target']['counts']['source'] = 0
            self.assertTrue(a.check_case(*result, baseline))
            result = evidence(case=case); del result[0]['authorityBaseline']
            self.assertTrue(a.check_case(*result))


    def test_prepared_wait_diagnoses_same_id_alias_without_accepting_it(self):
        lua = worn_alias_fixture()
        lua.execute("player:setWornItem(canonical:getBodyLocation(),canonical);assert(F.resolve(player,ids));assert(F.wearBaseline(state))")

    def test_host_bag_provisional_resolution_never_weakens_final_worn_identity(self):
        lua = worn_alias_fixture()
        lua.execute(r'''
local old=root:getItems();local front,tail,cancelled=old:get(0),old:get(2),old:get(3)
local function list(values)return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
local source={getItems=function()return list({canonical,cancelled})end}
local bag={class='InventoryContainer',getID=function()return 10 end,getFullType=function()return 'Base.Bag_Military'end,
 getContainer=function()return root end,getItemContainer=function()return source end,canBeEquipped=function()return 'Back'end}
local worn
function root:getItems()return list({front,tail,bag})end
function root:getItemById(id)if id==10 then return bag end end
canonical.getContainer=function()return source end
cancelled.getContainer=function()return source end
player.getWornItems=function()return{contains=function(_,value)return value==worn end,
 getItemById=function(_,id)return worn and worn:getID()==id and worn or nil end}end
player.getWornItem=function(_,slot)return slot=='Back'and worn or nil end
ids.case='worn-bag';ids.source={kind='worn-bag',bag=10,world=false}
assert(not F.resolve(player,ids),'unworn bag became ready baseline')
local s=assert(F.resolve(player,ids,true));assert(not F.wearBaseline(s))
worn={getID=function()return 10 end};assert(not F.resolve(player,ids),'same-ID bag alias accepted')
local diagnostic=F.preparedDiagnostic(player,ids)
assert(diagnostic.bag.slotId==10 and not diagnostic.bag.slotSame and not diagnostic.bag.canonicalWorn)
worn=bag;assert(F.resolve(player,ids));assert(F.wearBaseline(s))
worn=nil;assert(not F.resolve(player,ids)and not F.wearBaseline(s))
assert(not pcall(F.verify,s),'nativeWearSetup permanently relaxed final canonical worn bag identity')
''')

    def test_native_wear_source_rebinds_and_completes_exact_root_item(self):
        game = os.environ.get('PZ_GAME')
        if not game: self.skipTest('PZ_GAME required for installed native wear source regression')
        native = Path(game) / 'media/lua/shared/TimedActions/ISWearClothing.lua'
        self.assertEqual(a.NATIVE_CRC['media/lua/shared/TimedActions/ISWearClothing.lua'], zlib.crc32(native.read_bytes()))
        lua = worn_alias_fixture(); lua.globals().nativeWearSource = str(native)
        lua.execute(r'''
require=function()end
ISBaseTimedAction={derive=function(_,name)local cls={Type=name};cls.__index=cls;return cls end}
ItemTag={WEARABLE='wearable',REPLACE_PRIMARY='primary'}
function isClient()return true end
function getText(value)return value end
dofile(nativeWearSource)
local action=setmetatable({item=proxy,character=player,setActionAnim=function()end,setAnimVariable=function()end,
 forceComplete=function()error('same-ID proxy must not force-complete canonical wear')end},ISWearClothing)
action:start();assert(action.item==canonical,'native wear start did not rebind exact root item')
assert(action:complete(),'native wear complete failed')
assert(player:getWornItem(canonical:getBodyLocation())==canonical and F.resolve(player,ids))
assert(F.wearBaseline(state),'native canonical wear did not satisfy strict baseline')
''')

    def test_native_source_audit_fails_before_launch_on_drift(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); data = b'native source fixture'
            paths = {name: zlib.crc32(data) for name in a.NATIVE_CRC}
            for relative in paths:
                path = root / relative; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
            with patch.object(a, 'NATIVE_CRC', paths):
                self.assertEqual(paths, a.audit_native(root))
                (root / next(iter(paths))).write_bytes(b'changed native method')
                with self.assertRaises(ValueError): a.audit_native(root)

    def test_report_verifier_has_explicit_separate_source_roles(self):
        from queue_checks import provenance
        selection = {'suite': 'wring-clothing'}
        declared = {path.resolve() for path in provenance.verifier_sources(PROJECT, selection)}
        verifier = Path(a.__file__).with_name('wring_clothing_verifier.py').resolve()
        self.assertIn(verifier, declared)
        self.assertIn(Path(__file__).resolve(), declared)
        inputs = {path.resolve() for path in a.sources(PROJECT, selection)} | declared | {Path(a.__file__).resolve()}
        manifest = {str(path): provenance.digest(path) for path in inputs}
        roles = provenance.source_roles(PROJECT, selection, manifest)
        self.assertEqual({str(path) for path in declared}, set(roles['verifier']))
        self.assertIn(str(Path(a.__file__).resolve()), roles['runtime'])
        self.assertIn(str(PROJECT / 'tests/native_queue/wring-clothing/client/ZZWringClothing.lua'), roles['runtime'])
        self.assertNotIn(str(verifier), roles['runtime'])
        sentinel = object()
        with patch('queue_checks.provenance.run_verifier', return_value=sentinel) as run:
            self.assertIs(sentinel, a.verify(Path('unused-evidence'), selection, {}))
        self.assertEqual(verifier, Path(run.call_args.args[0]).resolve())
        self.assertEqual('queue_checks.adapters', run.call_args.args[1])

    def test_fixture_native_callbacks_and_dry_baseline(self):
        root = PROJECT / 'tests/native_queue/wring-clothing'
        shared = (root / 'shared/QueueWringClothing.lua').read_text()
        client = (root / 'client/ZZWringClothing.lua').read_text()
        self.assertIn('precipitation:setEnableAdmin(true)', shared)
        self.assertEqual(shared.count('item:setWetness('), 1)
        self.assertIn('item:setWetness(100)', shared)
        self.assertIn("nativeShoe=location=='Shoes'", shared)
        self.assertIn('player:getInventoryWeight()<player:getMaxWeight()', shared)
        self.assertIn('if item:getContainer()==root then sendAddItemToContainer(root,item)end', shared)
        self.assertIn('Ops.run(ISInventoryPaneContextMenu.onWringClothing', client)
        self.assertNotIn('toolkitQueueOperation=', client)
        for name in ('complete', 'perform', 'getDuration', 'isValid'):
            self.assertNotIn('ISWringClothing.' + name + '=', client)
        self.assertNotRegex(client, r'\.maxTime\s*=(?!=)')
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        compile_ = lua.eval('function(source) local f,e=loadstring(source); assert(f,e) end')
        for file in root.rglob('*.lua'):
            compile_(file.read_text())

    def test_unique_canonical_clothing_handle_replacement_preserves_identity(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        source = PROJECT / 'tests/native_queue/wring-clothing/shared/QueueWringClothing.lua'
        script = r'''
package.loaded.QueueEnergyPlacement={}
function instanceof(value,kind)return value.class==kind end
function getClassSimpleName(value)return value.class end
local F=dofile(arg[1])
local values={};local root={}
local socks=setmetatable({class='ItemBodyLocation'},{__tostring=function()return 'base:socks'end})
local function item(id,kind)
 return {class='Clothing',getID=function()return id end,getFullType=function()return kind end,
 getWetness=function()return 99 end,getActualWeight=function()return .1 end,getContainer=function()return root end,
 getBodyLocation=function()return socks end}
end
function root:getItems()return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
local player={getInventory=function()return root end,getWornItems=function()return{contains=function()return false end}end}
local s={player=player,source=root,items={},ids={case='root',source={kind='root',bag=false,world=false},items={}}}
for i,name in ipairs(F.names)do
 s.ids.items[name]={id=i,type='Base.Socks_Ankle',bodyLocation='base:socks',bodyLocationClass='ItemBodyLocation',nativeShoe=false,cap=10}
 s.items[name]=item(i,'Base.Socks_Ankle');values[i]=item(i,'Base.Socks_Ankle')
end
local snapshot=F.snapshot(s)
for i,name in ipairs(F.names)do
 assert(s.items[name]==values[i]and snapshot.items[name].counts.root==1 and snapshot.items[name].counts.source==1)
end
values[5]=item(2,'Base.Socks_Ankle');assert(not pcall(F.snapshot,s),'duplicate ID accepted');values[5]=nil
values[2]=item(2,'Base.Shoes_FlipFlop');assert(not pcall(F.snapshot,s),'wrong-type replacement accepted')
values[2]=item(200,'Base.Socks_Ankle');assert(not pcall(F.snapshot,s),'unowned replacement accepted')
'''
        lua.globals().arg = lua.table_from([str(source)])
        lua.execute(script)

    def test_carried_fixture_keeps_cancelled_source_and_requires_exact_native_return(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().fixture = str(PROJECT / 'tests/native_queue/wring-clothing/shared/QueueWringClothing.lua')
        lua.execute(r'''
package.loaded.QueueEnergyPlacement={atCentered=function()return true end}
function instanceof(value,kind)return value.class==kind end
function getClassSimpleName(value)return value.class end
local F=dofile(fixture)
local values,contents={},{};local root,source={},{}
local function list(items)return{size=function()return #items end,get=function(_,i)return items[i+1]end}end
function root:getItems()return list(values)end
function source:getItems()return list(contents)end
local location=setmetatable({class='ItemBodyLocation'},{__tostring=function()return 'base:socks'end})
local bag={class='InventoryContainer',getID=function()return 20 end,getFullType=function()return 'Base.Bag_Military'end,
 getContainer=function()return root end,getItemContainer=function()return source end}
values[1]=bag
function root:getItemById(id)if id==20 then return bag end end
local player={getInventory=function()return root end,getWornItems=function()return{contains=function(_,item)return item==bag end}end}
local ids={case='worn-bag',mode='toolkit',preparedGroups=true,origin={},source={kind='worn-bag',bag=20,world=false},items={}}
local state={player=player,source=source,bag=bag,items={},ids=ids}
for index,name in ipairs(F.names)do
 local owner=(name=='target'or name=='cancelled')and source or root
 local item={class='Clothing',id=index,wet=99,owner=owner}
 function item:getID()return self.id end
 function item:getFullType()return 'Base.Socks_Ankle'end
 function item:getContainer()return self.owner end
 function item:getWetness()return self.wet end
 function item:getActualWeight()return .1 end
 function item:getWeight()return .1+self.wet/100*.025 end
 function item:getUnequippedWeight()return .1 end
 function item:getBodyLocation()return location end
 local spec=F.nativeWetnessContract(item);spec.id=index;spec.type=item:getFullType();spec.weight=.1;spec.wetWeight=.125;spec.capacityWeight=.1
 ids.items[name]=spec;state.items[name]=item
 local collection=owner==source and contents or values;collection[#collection+1]=item
end
assert(F.resolve(player,ids),'carried source canonical resolution failed')
local input=F.snapshot(state)
assert(input.items.target.counts.root==0 and input.items.cancelled.counts.source==1)
for _,name in ipairs({'front','target','tail'})do state.items[name].wet=10 end
local target=state.items.target
for index,item in ipairs(contents)do if item==target then table.remove(contents,index);break end end
values[#values+1]=target;target.owner=root
assert(not F.verify(state),'body root state incorrectly credited a future return')
assert(F.snapshot(state).items.target.counts.root==1 and state.items.cancelled.owner==source and state.items.cancelled.wet==99)
table.remove(values);contents[#contents+1]=target;target.owner=source
assert(F.verify(state),'exact native/P4 return source was not accepted')
ids.mode='native';assert(not F.verify(state),'disabled control omitted its uncancelled body effect')
state.items.cancelled.wet=10;assert(F.verify(state))
contents[#contents+1]=target;assert(not pcall(F.snapshot,state),'duplicate returned identity accepted')
''')

    def test_p4_return_observation_refreshes_native_members_merged_after_start(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().fixture = str(PROJECT / 'tests/native_queue/wring-clothing/shared/QueueWringClothing.lua')
        lua.execute(r'''
package.loaded.QueueEnergyPlacement={}
local F=dofile(fixture)
local function item(id,kind)return{getID=function()return id end,getFullType=function()return kind end}end
local first,second=item(10,'Base.Socks_Ankle'),item(11,'Base.Socks_Ankle')
local action={queueList={{items={first}}}};local original=action.queueList
local observed=F.returnMembers(action,{})
assert(#observed==1 and observed[1].id==10)
-- Native add/merge may extend a currently running transfer before its perform.
action.queueList[2]={items={second}};F.returnMembers(action,observed)
assert(#observed==2 and observed[2].id==11 and action.queueList==original and #action.queueList==2)
action.queueList[1]=nil;action.queueList={{items={second}}};F.returnMembers(action,observed)
assert(#observed==2,'completed native member evidence was lost')
action.queueList={{items={item(10,'Base.Shoes_FlipFlop')}}}
assert(not pcall(F.returnMembers,action,observed),'changed native return identity/type accepted')
''')

    def test_enum_valued_shoe_location_preserves_native_string_predicate(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().fixture = str(PROJECT / 'tests/native_queue/wring-clothing/shared/QueueWringClothing.lua')
        lua.execute(r'''
package.loaded.QueueEnergyPlacement={}
function getClassSimpleName(value)return type(value)=='string'and 'String'or value.class end
local F=dofile(fixture)
local location=setmetatable({class='ItemBodyLocation'},{__tostring=function()return 'base:shoes'end})
local actual=F.nativeWetnessContract({getBodyLocation=function()return location end})
assert(actual.bodyLocation=='base:shoes'and actual.bodyLocationClass=='ItemBodyLocation')
assert(actual.nativeShoe==false and actual.cap==10,'enum-valued shoes must retain the native false string branch')
local legacy=F.nativeWetnessContract({getBodyLocation=function()return 'Shoes'end})
assert(legacy.nativeShoe==true and legacy.cap==60,'fixture must report the native expression, not force a cap')
''')
        result = evidence(case='world')
        for spec in (result[0]['ids']['items']['target'], result[2]['items']['target']):
            spec.update(nativeShoe=True, cap=60)
        self.assertTrue(a.check_case(*result), 'unobserved string-valued shoe branch must not pass')


if __name__ == '__main__':
    unittest.main()
