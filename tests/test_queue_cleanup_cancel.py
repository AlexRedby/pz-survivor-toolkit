import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.adapters import cleanup_cancel as a


def evidence(case, mode='toolkit', kind='mp'):
    enabled = mode == 'toolkit'; mask = case == a.CASES[0]; keep = enabled and case == 'p4-keep-return'
    items = dict(book=1, mask=2, food=3) if mask else dict(book=1, bag=2, borrowed=3, torch=4, secondary=5)
    inventory = [dict(id=id, type='Base.' + name, container='bag:2' if name == 'borrowed' else 'root') for name, id in items.items()]
    base = dict(case=case, items=inventory, book=219, primary=False if mask else 4, secondary=False if mask else 5,
                maskWorn=mask, borrowedContainer=False if mask else 'bag', torchActive=not mask,
                borrowed=False if mask else dict(pages=219, characterPages=219, total=220), food=dict(hunger=-.4, base=-.4, uses=1) if mask else False)
    ids = dict(case=case, actor=7, items=items, pages=220, initial=219, baseline=copy.deepcopy(base))
    if not mask: ids.update(borrowedType='Base.BookFirstAid1', borrowedPages=220, borrowedInitial=219)
    final = copy.deepcopy(base); final['book'] = 220
    if mask: final['food']['hunger'] = -.3
    else:
        final['borrowed'].update(pages=219 if enabled and not keep else 220, characterPages=219 if enabled and not keep else 220)
        if keep:
            final['borrowedContainer'] = 'root'
            for entry in final['items']:
                if entry['id'] == items['borrowed']: entry['container'] = 'root'
    types = ('ISUnequipAction', 'ISEatFoodAction', 'ISWearClothing') if mask else ('ISInventoryTransferAction', 'ISReadABook', 'ISInventoryTransferAction')
    records = []
    def add(role, type, n, at, performed=None, started=True):
        record = dict(role=role, type=type, sequence=n, item=(1 if role == 'tail' else 3 if role == 'body' or not mask else 2), actionRef='action-' + str(n), nativeRef='java-' + str(n),
                      duration=-1 if kind == 'mp' and type == 'ISInventoryTransferAction' else 100,
                      durationBefore=100, durationAfter=100, effectiveDuration=100, transactionDuration=100, started=started, progress=started, token='body' if role != 'tail' else 'tail', nativeMethods=True,
                      finishes=[dict(phase=phase, succeeded=True, at=performed) for phase in (('perform',) if kind == 'mp' else ('perform', 'complete'))] if performed else [],
                      receipts=[], startedAt=at, transaction=n, transactionDone=True, transactionRejected=False)
        if performed: record['performedAt'] = performed
        records.append(record); return record
    prepare = add('prepare', types[0], 1, 1, 10)
    body = add('body', types[1], 2, 15, 25 if mask or not enabled or keep else None, True)
    if not mask: body.update(readStartProgress=.99546, readMaxProgress=.99547)
    cleanup = add('cleanup', types[2], 3, 26, 35)
    tail = add('tail', 'ISReadABook', 4, 40, 80)
    if not mask and enabled:
        retired = copy.deepcopy(cleanup)
        retired.update(started=False, progress=False, finishes=[], receipts=[], transaction=False, uuid=False)
        for key in ('startedAt', 'performedAt', 'nativeRef', 'transactionDone', 'transactionRejected',
                    'effectiveDuration', 'transactionDuration', 'durationAfter'):
            retired.pop(key, None)
        records[2] = retired
        if not keep:
            cleanup.update(sequence=5, token='owned-return', actionRef='action-5', nativeRef='java-5', transaction=5)
            records.append(cleanup)
        else: cleanup = retired
    receipts = []
    if kind == 'mp':
        for record in (prepare, cleanup):
            if record['type'] == 'ISInventoryTransferAction': continue
            for state in ('started', 'completed'):
                value = dict(case=case, state=state, transaction=record['sequence'], kind=record['type'],
                             token='12345678-1234-1234-1234-123456789012', player=7, at=10,
                             actionRef=record['actionRef'], nativeRef=record['nativeRef'])
                record['receipts'].append(value); receipts.append(value)
    checkpoint = copy.deepcopy(base); checkpoint['maskWorn'] = False
    boundary = dict(requested=enabled, allowed=enabled, at=20, preparation=1, body=2, current=2,
                    preparationAbsent=True, preparationPaid=True, currentProgress=True, tailRetained=True, before=copy.deepcopy(checkpoint))
    if not mask:
        checkpoint['borrowedContainer'] = 'root'; boundary['before'] = copy.deepcopy(checkpoint)
        if enabled: boundary['operationState'] = dict(borrowings=[dict(id=3, fullType='Base.BookFirstAid1', state='active')])
    if enabled and not mask:
        target = cleanup if keep else body
        boundary['ui'] = dict(source='ActionQueuePanel.List', input='programmatic-press-release', header=not keep,
                              target=target['sequence'], actionRef=target['actionRef'], item=3, previewAllowed=True,
                              pressed=True, pressCaptured=True, released=True, gestureCleared=True, feedback=False,
                              x=380, y=80, at=20, bodyCurrent=keep, returnAbsent=keep,
                              bodyRef=body['actionRef'], nativeRef=body['nativeRef'])
    tail_snapshot = copy.deepcopy(final)
    row = dict(event='case', suite='cleanup-cancel', actor='client1', kind=kind, mode=mode, status='passed', id=case, ids=ids,
               baseline=copy.deepcopy(base), authorityBaseline=copy.deepcopy(base), checkpoint=checkpoint, boundary=boundary,
               records=records, idleEvidence=dict(case=case, since=90, at=1590, empty=True, snapshot=copy.deepcopy(final)), bodyTerminal=copy.deepcopy(final) if not mask else False, tailSnapshot=tail_snapshot, client=copy.deepcopy(final), server=copy.deepcopy(final), nativeMethodsUnchanged=True,
               outcome=dict(cleanupRestored=True, tailCompleted=True, authoritative=True, cancelled=enabled,
                            normalNativeControl=not enabled, cleanupBeforeTail=True, originalEquipmentBeforeTail=True))
    selection = dict(suite='cleanup-cancel', cases=a.CASES, kind=kind, mode=mode, languages=['EN'], clients=1, mods=a.MODS,
                     options={'mp_host': True} if kind == 'mp' else {})
    return row, selection, receipts


class CleanupCancelChecks(unittest.TestCase):
    def check(self, row, selection, receipts):
        return a.check_case(row, row['id'], selection, row['ids'], row['baseline'], row['checkpoint'], row['server'], receipts)

    def test_exact_native_controls_and_toolkit_sp_host(self):
        for case in a.CASES:
            for mode in ('native', 'toolkit'):
                for kind in ('sp', 'mp'):
                    row, selection, receipts = evidence(case, mode, kind)
                    with self.subTest(case=case, mode=mode, kind=kind): self.assertEqual([], self.check(row, selection, receipts))

    def test_reject_missing_preparation_effect_and_cleanup_order(self):
        changes = {
            'not paid': lambda r: r['boundary'].update(preparationPaid=False),
            'still queued': lambda r: r['boundary'].update(preparationAbsent=False),
            'no progress': lambda r: r['boundary'].update(currentProgress=False),
            'lost tail': lambda r: r['boundary'].update(tailRetained=False),
            'wrong prep': lambda r: r['boundary'].update(preparation=99),
            'denied cancel': lambda r: r['boundary'].update(allowed=False),
            'cleanup after tail': lambda r: r['records'][2].update(performedAt=50),
            'wrong cleanup token': lambda r: r['records'][0].update(token='foreign'),
            'tail shared token': lambda r: r['records'][3].update(token='body'),
            'cleanup omitted': lambda r: r['records'][2].pop('performedAt'),
            'duplicate cleanup': lambda r: r['records'].append(copy.deepcopy(r['records'][2])),
            'instant action': lambda r: r['records'][0].update(duration=1),
            'effective instant action': lambda r: r['records'][0].update(effectiveDuration=1),
            'wrong native bracket': lambda r: r['records'][0].update(durationBefore=50),
            'changed lifecycle': lambda r: r.update(nativeMethodsUnchanged=False),
            'failed native effect': lambda r: r['records'][0]['finishes'][0].update(succeeded=False),
            'wrong exact prep item': lambda r: r['records'][0].update(item=999),
            'wrong exact meal item': lambda r: r['records'][1].update(item=999),
            'wrong exact cleanup item': lambda r: r['records'][2].update(item=999),
            'wrong exact tail item': lambda r: r['records'][3].update(item=999),
            'foreign terminal actor': lambda r: r['records'][0]['receipts'][-1].update(player=999),
            'foreign receipt': lambda r: r['records'][0]['receipts'][-1].update(token='ffffffff-1234-1234-1234-123456789012'),
            'rejected receipt': lambda r: r['records'][0]['receipts'][-1].update(state='rejected'),
            'mask not restored before tail': lambda r: r['tailSnapshot'].update(maskWorn=False),
            'body skipped': lambda r: r['records'][1].update(started=False),
            'portion duplicated': lambda r: r['client']['food'].update(hunger=-.2),
            'tail incomplete': lambda r: r['client'].update(book=219),
            'mask lost authority': lambda r: r['server'].update(maskWorn=False),
            'extra identity': lambda r: r['client']['items'].append(dict(id=999, type='Base.Mask', container='root')),
        }
        for name, change in changes.items():
            row, selection, receipts = evidence(a.CASES[0]); receipts = copy.deepcopy(receipts); change(row)
            with self.subTest(name=name): self.assertTrue(self.check(row, selection, receipts))

    def test_only_exact_unstarted_borrowed_return_can_be_replaced(self):
        changes = {
            'missing retired return': lambda r: r['records'].pop(2),
            'retired return started': lambda r: r['records'][2].update(started=True),
            'retired return progressed': lambda r: r['records'][2].update(progress=True),
            'retired start timestamp': lambda r: r['records'][2].update(startedAt=25),
            'retired native action': lambda r: r['records'][2].update(nativeRef='java-3'),
            'retired transaction': lambda r: r['records'][2].update(transaction=3),
            'retired completed transaction': lambda r: r['records'][2].update(transactionDone=True),
            'retired receipt': lambda r: r['records'][2]['receipts'].append({'state': 'completed'}),
            'retired callback': lambda r: r['records'][2]['finishes'].append({'phase': 'perform', 'succeeded': True, 'at': 30}),
            'retired effect': lambda r: r['records'][2].update(performedAt=30),
            'retired foreign token': lambda r: r['records'][2].update(token='foreign'),
            'retired wrong item': lambda r: r['records'][2].update(item=999),
            'retired foreign type': lambda r: r['records'][2].update(type='ForeignTransfer'),
            'same action identity': lambda r: r['records'][4].update(actionRef=r['records'][2]['actionRef']),
            'return body token': lambda r: r['records'][4].update(token='body'),
            'return tail token': lambda r: r['records'][4].update(token='tail'),
            'return no token': lambda r: r['records'][4].update(token=False),
            'return observed before tail was queued': lambda r: r['records'][4].update(sequence=3),
            'second return effect': lambda r: r['records'].append(copy.deepcopy(r['records'][4])),
        }
        for name, change in changes.items():
            for kind in ('sp', 'mp'):
                row, selection, receipts = evidence(a.CASES[1], kind=kind); change(row)
                with self.subTest(name=name, kind=kind): self.assertTrue(self.check(row, selection, receipts))
        for case, mode in ((a.CASES[0], 'toolkit'), (a.CASES[1], 'native')):
            row, selection, receipts = evidence(case, mode)
            extra = copy.deepcopy(row['records'][2]); extra.update(started=False, progress=False, finishes=[])
            extra.pop('performedAt'); extra.pop('startedAt'); row['records'].append(extra)
            with self.subTest(case=case, mode=mode): self.assertTrue(self.check(row, selection, receipts))

    def test_requires_exact_successful_native_callback_pairs(self):
        changes = {
            'all callbacks missing': lambda r: [x.update(finishes=[]) for x in r['records']],
            'perform missing': lambda r: r['records'][0]['finishes'].pop(0),
            'complete missing': lambda r: r['records'][0]['finishes'].pop(),
            'perform duplicated': lambda r: r['records'][0]['finishes'].insert(0, copy.deepcopy(r['records'][0]['finishes'][0])),
            'wrong phase': lambda r: r['records'][0]['finishes'][0].update(phase='stop'),
            'failed complete': lambda r: r['records'][0]['finishes'][1].update(succeeded=False),
            'perform time after paid effect': lambda r: r['records'][0]['finishes'][0].update(at=11),
            'complete time before paid effect': lambda r: r['records'][0]['finishes'][1].update(at=9),
            'callback before native start': lambda r: r['records'][0].update(startedAt=11),
        }
        for case in a.CASES:
            for mode in ('native', 'toolkit'):
                for name, change in changes.items():
                    row, selection, receipts = evidence(case, mode, 'sp'); change(row)
                    with self.subTest(case=case, mode=mode, name=name): self.assertTrue(self.check(row, selection, receipts))
        for case in a.CASES:
            for mode in ('native', 'toolkit'):
                row, selection, receipts = evidence(case, mode)
                for record in row['records']:
                    if not record.get('performedAt'): continue
                    damaged = copy.deepcopy(row)
                    damaged['records'][row['records'].index(record)]['finishes'] = []
                    with self.subTest(case=case, mode=mode, role=record['role']):
                        self.assertTrue(self.check(damaged, selection, receipts))
        row, selection, receipts = evidence(a.CASES[0], kind='mp')
        row['records'][0]['finishes'].append(dict(phase='complete', succeeded=True, at=11))
        self.assertTrue(self.check(row, selection, receipts))
        row, selection, receipts = evidence(a.CASES[0], kind='sp')
        row['records'][0]['finishes'][1]['at'] = 11
        self.assertEqual([], self.check(row, selection, receipts))
        row['records'][0]['performedAt'] = 11
        self.assertEqual([], self.check(row, selection, receipts))

    def test_transfer_constructor_time_survives_late_native_allocation_observation(self):
        try:
            from lupa.lua51 import LuaRuntime, LuaError
        except ImportError:
            self.skipTest('Lupa Lua5.1 is required for fixture source regression')
        lua = LuaRuntime(unpack_returned_tuples=True)
        source = Path(__file__).resolve().parent / 'native_queue/cleanup-cancel/shared/QueueCleanupCancel.lua'
        fixture = lua.execute(source.read_text())
        action = lua.eval('''function()
            local item={};local value={Type='ISInventoryTransferAction',item=item,maxTime=120.00208854675293,
                queueList={{items={item},time=120}}}
            function value:adjustMaxTime(time)return time*(120.00208854675293/120)end
            return value
        end''')()
        original = fixture.constructorDuration(action)
        self.assertEqual(120, original)
        self.assertAlmostEqual(action.maxTime, action.adjustMaxTime(action, original), places=10)
        self.assertGreater(action.adjustMaxTime(action, action.maxTime) - action.maxTime, .002)
        self.assertEqual(120, action.queueList[1].time)
        action.queueList[1]['items'][1] = lua.table()
        with self.assertRaises(LuaError): fixture.constructorDuration(action)

    def test_host_prebaseline_resolves_exact_items_and_native_local_equipment(self):
        try:
            from lupa.lua51 import LuaRuntime
        except ImportError:
            self.skipTest('Lupa Lua5.1 is required for fixture source regression')
        lua = LuaRuntime(unpack_returned_tuples=True)
        source = Path(__file__).resolve().parent / 'native_queue/cleanup-cancel/shared/QueueCleanupCancel.lua'
        lua.globals().F = lua.execute(source.read_text())
        lua.execute(r"""
            local client,server=false,true
            isClient=function()return client end;isServer=function()return server end
            Perks={Woodwork='wood',Doctor='doctor'};CharacterStat={HUNGER='hunger'};ItemTag={CAN_EAT='eat'}
            package.preload.QueueEnergyPlacement=function()return function()end end
            local serial,writes=100,0
            local function list(values)
                return{values=values,size=function(self)return #self.values end,get=function(self,i)return self.values[i+1]end}
            end
            local container,item
            container=function()
                return{values={},getItems=function(self)return list(self.values)end,getContainingItem=function(self)return self.owner end,
                    AddItem=function(self,kind)local value=item(kind,self);self.values[#self.values+1]=value;return value end,
                    setExplored=function()end}
            end
            item=function(kind,owner,id)
                serial=serial+1
                local value={kind=kind,container=owner,id=id or serial,pages=0,active=false,uses=40}
                function value:getID()return self.id end
                function value:getFullType()return self.kind end
                function value:getContainer()return self.container end
                function value:getNumberOfPages()return 220 end
                function value:getAlreadyReadPages()return self.pages end
                function value:setAlreadyReadPages(n)writes=writes+1;self.pages=n end
                function value:getBodyLocation()return 'base:maskeyes' end
                function value:canBeEquipped()return 'base:back' end
                function value:hasTag()return false end
                function value:setUsedDelta(n)writes=writes+1;self.delta=n end
                function value:setActivated(v)writes=writes+1;self.active=v end
                function value:isActivated()return self.active end
                function value:getHungChange()return -.4 end
                function value:getBaseHunger()return -.4 end
                function value:getCurrentUses()return self.uses end
                if kind=='Base.Bag_Schoolbag'then value.contents=container();value.contents.owner=value;function value:getItemContainer()return self.contents end end
                return value
            end
            instanceof=function(value,class)return class=='InventoryContainer'and value.contents~=nil end
            local function player()
                local p={inventory=container(),worn={},cache={},levels={},handSends=0}
                function p:getInventory()return self.inventory end
                function p:getOnlineID()return 7 end
                function p:getX()return 10 end;function p:getY()return 20 end;function p:getZ()return 0 end
                function p:setGodMod()end;function p:setGhostMode()end;function p:setAutoDrink()end
                function p:getWornItems()
                    local rows={};for location,value in pairs(self.worn)do local slot=location;local worn=value
                        rows[#rows+1]={getItem=function()return worn end,getLocation=function()return slot end}end
                    return list(rows)
                end
                function p:setWornItem(location,value)writes=writes+1;self.worn[location]=value end
                function p:removeWornItem(value)writes=writes+1;for key,v in pairs(self.worn)do if v==value then self.worn[key]=nil end end end
                function p:getWornItem(location)return self.worn[location]end
                function p:isEquippedClothing(value)for _,v in pairs(self.worn)do if v==value then return true end end;return false end
                function p:setPrimaryHandItem(value)writes=writes+1;self.primary=value end
                function p:setSecondaryHandItem(value)writes=writes+1;self.secondary=value end
                function p:getPrimaryHandItem()return self.primary end;function p:getSecondaryHandItem()return self.secondary end
                function p:setAlreadyReadPages(kind,n)writes=writes+1;self.cache[kind]=n end
                function p:getAlreadyReadPages(kind)return self.cache[kind]or 0 end
                function p:getXp()return{setXPToLevel=function(_,perk,n)writes=writes+1;self.levels[perk]=n end}end
                function p:setPerkLevelDebug(perk,n)writes=writes+1;self.levels[perk]=n end
                function p:getStats()return{set=function()end}end
                function p:updateHandEquips()self.handSends=self.handSends+1 end
                return p
            end
            sendClothing=function()end;sendEquip=function()end
            for _,case in ipairs(F.cases)do
                client,server=false,true
                local authority=player();local sent={}
                sendAddItemToContainer=function(owner,value)
                    assert(owner==authority.inventory,'nested child must travel only within its serialized root bag')
                    assert(not sent[value.id],'root seed sent twice');sent[value.id]=true
                end
                local prepared=F.prepare(authority,case)
                if prepared.borrowed then assert(not sent[prepared.borrowed.id]and sent[prepared.bag.id])end
                local localPlayer=player()
                local function copy(from,to)
                    for _,value in ipairs(from.values)do
                        local cloned=item(value.kind,to,value.id);to.values[#to.values+1]=cloned
                        if value.contents then copy(value.contents,cloned.contents)end
                    end
                end
                copy(authority.inventory,localPlayer.inventory)
                client,server=true,false;writes=0
                local missingId=prepared.borrowed and prepared.borrowed.id or prepared.mask.id
                local missing=F.find(localPlayer,missingId);local owner=missing.container
                for i,value in ipairs(owner.values)do if value==missing then table.remove(owner.values,i);break end end
                local state,detail=F.resolve(localPlayer,prepared.ids)
                assert(not state and detail.reason=='exact seeded items not replicated'and detail.missing[1].id==missingId)
                assert(writes==0,'partial replication must not start local fixture setup')
                owner.values[#owner.values+1]=missing
                state,detail=F.resolve(localPlayer,prepared.ids)
                assert(state and not detail,'exact replicated Host items must resolve despite ignored hands/default pages')
                assert(not F.baselineDifference(state,F.snapshot(state))and localPlayer.levels.wood==0)
                assert(state.book.pages==219 and localPlayer.cache['Base.BookCarpentry1']==219)
                if state.borrowed then
                    assert(state.borrowed.pages==219 and localPlayer.cache['Base.BookFirstAid1']==219 and localPlayer.levels.doctor==0)
                    assert(localPlayer.primary==state.torch and localPlayer.secondary==state.secondary and state.torch.active)
                    assert(localPlayer.worn['base:back']==state.bag and localPlayer.handSends==1)
                    local oldBag,oldBook=state.bag,state.borrowed
                    local liveBag=item(oldBag.kind,localPlayer.inventory,oldBag.id)
                    local liveBook=item(oldBook.kind,liveBag.contents,oldBook.id);liveBook.pages=219
                    liveBag.contents.values={liveBook}
                    for i,value in ipairs(localPlayer.inventory.values)do if value==oldBag then localPlayer.inventory.values[i]=liveBag end end
                    assert(F.refresh(state)and state.bag==liveBag and state.source==liveBag.contents and state.borrowed==liveBook)
                    assert(F.sourceMatches(state,oldBag.contents),'old replica endpoint must retain exact root bag owner identity')
                    oldBag.kind='Base.ForeignBag';assert(not F.sourceMatches(state,oldBag.contents));oldBag.kind=liveBag.kind
                    oldBag.id=999;assert(not F.sourceMatches(state,oldBag.contents));oldBag.id=liveBag.id
                    oldBag.container=container();assert(not F.sourceMatches(state,oldBag.contents));oldBag.container=localPlayer.inventory
                    liveBook.pages=220;localPlayer.cache[liveBook.kind]=220
                    assert(F.snapshot(state).borrowed.pages==220 and oldBook.pages==219,'snapshot must read the current exact replica')
                    liveBook.kind='Base.ForeignBook'
                    local valid,why=F.refresh(state);assert(not valid and why.actualType=='Base.ForeignBook')
                    liveBook.kind=oldBook.kind;liveBag.contents.values={}
                    valid,why=F.refresh(state);assert(not valid and why.id==oldBook.id,'missing exact ID cannot fall back to stale replica')
                    liveBag.contents.values={liveBook};assert(F.refresh(state));liveBook.pages=219;localPlayer.cache[liveBook.kind]=219
                    localPlayer.primary=nil
                else assert(localPlayer.worn['base:maskeyes']==state.mask);localPlayer.worn['base:maskeyes']=nil end
                local before=writes;state,detail=F.resolve(localPlayer,prepared.ids)
                assert(not state and detail.reason=='baseline differs'and writes==before,'later mismatch must diagnose, never re-seed gameplay')
            end
        """)

    def test_native_callbacks_keep_exact_action_identity_across_item_replicas(self):
        try:
            from lupa.lua51 import LuaRuntime, LuaError
        except ImportError:
            self.skipTest('Lupa Lua5.1 is required for actual observer source regression')
        lua = LuaRuntime(unpack_returned_tuples=True)
        root = Path(__file__).resolve().parent / 'native_queue/cleanup-cancel'
        lua.globals().F = lua.execute((root / 'shared/QueueCleanupCancel.lua').read_text())
        source = (root / 'client/ZZQueueCleanupCancel.lua').read_text()
        observer = source[source.index('local function classify(action)'):source.index('local function intact()')]
        callbacks = source[source.index('local function recordBegin(action,step)'):source.index('local function duration(action,row)')]
        make = lua.execute("""
            return function(observer,callbacks)
                local setup="local state,action=...;local byAction,records,classes={},{},{};local serial,tokenSerial=0,0;local tokenIds={};local prep,body,tail;local clock=0;local function now()clock=clock+1;return clock end;local function itemID(a)return a.item and a.item:getID()or false end;"
                return assert(loadstring(setup..observer..callbacks..";return register,recordBegin,recordFinish,records"))
            end
        """)(observer, callbacks)
        state, action, replacement = lua.execute("""
            isClient=function()return false end
            local function item(id,kind)return{getID=function()return id end,getFullType=function()return kind end}end
            local first=item(3,'Base.BookFirstAid1');local second=item(3,'Base.BookFirstAid1')
            local state={player={},borrowed=first,ids={items={borrowed=3},baseline={items={{id=3,type='Base.BookFirstAid1'}}}}}
            local action=setmetatable({Type='ISReadABook',character=state.player,item=first,maxTime=100,adjustMaxTime=function(_,n)return n end},{})
            return state,action,second
        """)
        register, begin, finish, records = make(state, action)
        row = register(action)
        action.item = replacement
        self.assertTrue(begin(action, 'perform'))
        finish(action, 'perform', True)
        self.assertEqual(1, len(records))
        self.assertEqual(1, len(row.finishes))
        self.assertTrue(row.finishes[1].succeeded)
        self.assertEqual(3, row.item)
        new_action = lua.eval('function(a,i)return setmetatable({Type=a.Type,character=a.character,item=i,maxTime=100,adjustMaxTime=a.adjustMaxTime},{})end')(action, replacement)
        self.assertIsNotNone(register(new_action))
        self.assertEqual(2, len(records), 'distinct native actions must remain distinct evidence rows')
        action.item = lua.eval("function()return{getID=function()return 3 end,getFullType=function()return 'Base.ForeignBook'end}end")()
        with self.assertRaises(LuaError): register(action)
        action.item = None
        with self.assertRaises(LuaError): register(action)

    def test_long_native_reader_allows_float_drift_but_not_duration_mutation(self):
        row, selection, receipts = evidence(a.CASES[0])
        tail = row['records'][3]
        tail.update(duration=79200, durationBefore=79200.07553100586, durationAfter=79200, effectiveDuration=79200)
        self.assertEqual([], self.check(row, selection, receipts))
        tail['durationAfter'] = 79000
        self.assertTrue(self.check(row, selection, receipts))
        tail.update(durationAfter=79200, effectiveDuration=79199)
        self.assertTrue(self.check(row, selection, receipts))

    def test_p4_requires_confirmed_pickup_active_read_and_paid_page_boundary(self):
        changes = {
            'unpaid transaction': lambda r: r['records'][0].update(transactionDone=False),
            'changed native transaction duration': lambda r: r['records'][0].update(transactionDuration=99),
            'rejected pickup': lambda r: r['records'][0].update(transactionRejected=True),
            'body never ran': lambda r: r['records'][1].update(started=False),
            'wrong active reading boundary': lambda r: r['boundary'].update(current=1),
            'initial positive progress only': lambda r: r['records'][1].update(readMaxProgress=.99546),
            'body completed despite cancellation': lambda r: r['records'][1].update(performedAt=25),
            'paid pages rolled back': lambda r: r['client']['borrowed'].update(pages=218),
            'paid pages replayed': lambda r: r['server']['borrowed'].update(pages=220),
            'character cache diverged': lambda r: r['server']['borrowed'].update(characterPages=218),
            'wrong ledger episode': lambda r: r['boundary']['operationState']['borrowings'][0].update(id=999),
            'unconfirmed ledger episode': lambda r: r['boundary']['operationState']['borrowings'][0].update(state='pending'),
            'missing ledger episode': lambda r: r['boundary'].pop('operationState'),
            'wrong return container': lambda r: r['server'].update(borrowedContainer='root'),
            'return after tail': lambda r: r['tailSnapshot'].update(borrowedContainer='root'),
            'false early hand restoration claim': lambda r: r['outcome'].update(originalEquipmentBeforeTail=False),
            'final activation missing': lambda r: r['client'].update(torchActive=False),
            'wrong restored hand': lambda r: r['client'].update(primary=3),
        }
        for name, change in changes.items():
            row, selection, receipts = evidence(a.CASES[1]); change(row)
            with self.subTest(name=name): self.assertTrue(self.check(row, selection, receipts))

    def test_p4_owned_return_before_tail_keeps_native_idle_hand_restoration(self):
        row, selection, receipts = evidence(a.CASES[1])
        row['tailSnapshot'].update(primary=False, torchActive=False)
        row['outcome']['originalEquipmentBeforeTail'] = False
        self.assertTrue(a.owned_cleanup_before_tail(row['tailSnapshot'], row['ids']))
        self.assertFalse(a.restored(row['tailSnapshot'], row['ids']))
        self.assertTrue(a.restored(row['client'], row['ids']))
        self.assertTrue(a.restored(row['server'], row['ids']))
        self.assertEqual([], self.check(row, selection, receipts))
        row['server']['secondary'] = False
        self.assertTrue(self.check(row, selection, receipts))

    def test_raw_authority_gate_does_not_trust_emitted_case_alone(self):
        rows = [evidence(case) for case in a.CASES]; selection = rows[0][1]
        setup = dict(event='setup', suite='cleanup-cancel', cases=a.CASES, queueEnabled=True, nativeDurations=True)
        completed = dict(event='complete', suite='cleanup-cancel', cases=a.CASES, performed=len(a.CASES), skipped=0, failed=0)
        def event(row): return '[QUEUE_CHECK] ' + json.dumps(row)
        def raw(name, value): return a.PREFIX + name + ' ' + json.dumps(value)
        client = [event(setup)]; server = []
        for row, _, receipts in rows:
            client += [raw('P4_IDLE', row['idleEvidence']), raw('BASELINE', row['baseline']), raw('BOUNDARY', row['boundary']), raw('TAIL_STARTED', row['tailSnapshot']),
                       *[raw('NATIVE_STATE', r) for r in receipts], event(row)]
            if row['bodyTerminal']: client.append(raw('BODY_SETTLED', row['bodyTerminal']))
            server += [raw('PREPARED', row['ids']), raw('BASELINE_CONFIRMED', row['authorityBaseline']), raw('CHECKPOINT', row['checkpoint']), raw('VERIFY', row['server'])]
        client += [event(completed), raw('COMPLETE', {'cases': a.CASES})]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / 'client1-launch.log').write_text('\n'.join(client)); (root / 'server-launch.log').write_text('\n'.join(server))
            self.assertEqual([], a.verify(root, selection, {})['issues'])
            for marker in ('BOUNDARY', 'TAIL_STARTED', 'BODY_SETTLED', 'P4_IDLE'):
                damaged = [line for line in client if not line.startswith(a.PREFIX + marker + ' ')]
                (root / 'client1-launch.log').write_text('\n'.join(damaged))
                self.assertTrue(a.verify(root, selection, {})['issues'], marker)
            changed_tail = copy.deepcopy(rows[0][0]['tailSnapshot']); changed_tail['primary'] = 999
            damaged = [raw('TAIL_STARTED', changed_tail) if line == raw('TAIL_STARTED', rows[0][0]['tailSnapshot']) else line for line in client]
            (root / 'client1-launch.log').write_text('\n'.join(damaged))
            self.assertTrue(a.verify(root, selection, {})['issues'])
            (root / 'client1-launch.log').write_text('\n'.join(client))
            no_ack = [line for line in server if not line.startswith(a.PREFIX + 'BASELINE_CONFIRMED ')]
            (root / 'server-launch.log').write_text('\n'.join(no_ack))
            self.assertTrue(a.verify(root, selection, {})['issues'])
            wrong_ack = [line.replace('\"primary\": 4', '\"primary\": false') if line.startswith(a.PREFIX + 'BASELINE_CONFIRMED ') else line for line in server]
            (root / 'server-launch.log').write_text('\n'.join(wrong_ack))
            self.assertTrue(a.verify(root, selection, {})['issues'])
            (root / 'server-launch.log').write_text('\n'.join(server[:-1]))
            self.assertTrue(a.verify(root, selection, {})['issues'])

    def test_keep_return_requires_real_panel_and_no_late_native_return(self):
        changes = {
            'fake API cancellation': lambda r: r['boundary']['ui'].update(source='ActionQueue.cancel'),
            'no release': lambda r: r['boundary']['ui'].update(released=False),
            'no captured press': lambda r: r['boundary']['ui'].update(pressCaptured=False),
            'wrong UI action': lambda r: r['boundary']['ui'].update(actionRef='foreign'),
            'whole group click': lambda r: r['boundary']['ui'].update(header=True),
            'stopped active body': lambda r: r['boundary']['ui'].update(bodyCurrent=False),
            'replaced active native reader': lambda r: r['boundary']['ui'].update(nativeRef='replacement'),
            'return remained queued': lambda r: r['boundary']['ui'].update(returnAbsent=False),
            'cancelled body callback': lambda r: r['records'][1].update(finishes=[]),
            'body incomplete pages': lambda r: r['bodyTerminal']['borrowed'].update(pages=219),
            'retired return ran': lambda r: r['records'][2].update(started=True, performedAt=30),
            'revived return': lambda r: r['records'].append(copy.deepcopy(r['records'][2])),
            'wrong exact book': lambda r: r['records'][1].update(item=999),
            'duplicate exact book': lambda r: r['client']['items'].append(copy.deepcopy(r['client']['items'][2])),
            'returned at body completion': lambda r: r['bodyTerminal'].update(borrowedContainer='bag'),
            'returned after body': lambda r: r['tailSnapshot'].update(borrowedContainer='bag'),
            'foreign return callback': lambda r: r['records'][2].update(type='ForeignTransfer'),
            'returned after tail': lambda r: r['idleEvidence']['snapshot'].update(borrowedContainer='bag'),
            'returned after idle': lambda r: r['server'].update(borrowedContainer='bag'),
            'late identity container': lambda r: r['server']['items'][2].update(container='bag:2'),
            'no P4 idle': lambda r: r['idleEvidence'].update(empty=False),
            'short P4 idle': lambda r: r['idleEvidence'].update(at=1589),
            'before tail complete': lambda r: r['idleEvidence'].update(since=79, at=1579),
            'hands unrestored': lambda r: r['server'].update(primary=3),
        }
        for kind in ('sp', 'mp'):
            for name, change in changes.items():
                row, selection, receipts = evidence('p4-keep-return', kind=kind); change(row)
                with self.subTest(kind=kind, name=name): self.assertTrue(self.check(row, selection, receipts))
        row, selection, receipts = evidence('p4-keep-return', mode='native')
        row['server']['borrowedContainer'] = 'root'
        self.assertTrue(self.check(row, selection, receipts), 'native-off control must actually return its borrowed book')

    def test_canonical_p4_only_subsets_do_not_repeat_mask(self):
        _, selection, _ = evidence('p4-keep-return')
        for cases in (['p4-after-pickup', 'p4-keep-return'], ['p4-after-pickup'], ['p4-keep-return']):
            selection['cases'] = cases; a.validate(selection)
        for cases in ([], ['p4-keep-return', 'p4-after-pickup'], ['p4-after-pickup'] * 2, ['unknown']):
            selection['cases'] = cases
            with self.subTest(cases=cases), self.assertRaises(ValueError): a.validate(selection)

    def test_p4_subset_has_exact_raw_evidence_without_a_mask_rerun(self):
        rows = [evidence(case) for case in a.CASES[1:]]; selection = rows[0][1]; selection['cases'] = a.CASES[1:]
        event = lambda row: '[QUEUE_CHECK] ' + json.dumps(row)
        raw = lambda name, value: a.PREFIX + name + ' ' + json.dumps(value)
        client = [event(dict(event='setup', suite='cleanup-cancel', cases=selection['cases'], queueEnabled=True, nativeDurations=True))]
        server = []
        for row, _, receipts in rows:
            client += [raw('BASELINE', row['baseline']), raw('BOUNDARY', row['boundary']), raw('TAIL_STARTED', row['tailSnapshot']),
                       raw('BODY_SETTLED', row['bodyTerminal']), raw('P4_IDLE', row['idleEvidence']),
                       *[raw('NATIVE_STATE', receipt) for receipt in receipts], event(row)]
            server += [raw('PREPARED', row['ids']), raw('BASELINE_CONFIRMED', row['authorityBaseline']),
                       raw('CHECKPOINT', row['checkpoint']), raw('VERIFY', row['server'])]
        client += [event(dict(event='complete', suite='cleanup-cancel', cases=selection['cases'], performed=2, skipped=0, failed=0)),
                   raw('COMPLETE', {'cases': selection['cases']})]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / 'client1-launch.log').write_text('\n'.join(client)); (root / 'server-launch.log').write_text('\n'.join(server))
            result = a.verify(root, selection, {})
            self.assertEqual([], result['issues'])
            self.assertEqual(selection['cases'], [outcome['case'] for outcome in result['outcomes']])

    def test_selected_pack_and_native_control_are_explicit(self):
        _, selection, _ = evidence(a.CASES[0]); a.validate(selection)
        selection['mods'] = selection['mods'][:-1]
        with self.assertRaises(ValueError): a.validate(selection)


if __name__ == '__main__': unittest.main()
