"""Explicit source-backed Lua 5.1 checks for the test-only furniture integration.

Run with a selected FurniturePushPull mod root; never launches a game or edits it.
"""
import argparse
import hashlib
import json
from pathlib import Path


FURNITURE_SOURCES = {
    '42/media/lua/client/FurniturePushPull/FurniturePushPull_Client.lua':
        'fbf2407235f513d68968f64609e96019f94b540b32e635b92a3d603b4a0f7d4c',
    '42/media/lua/server/FurniturePushPull/FurniturePushPull_Server.lua':
        '547c6e486d36527f42e8182fb1b637a93cd973bdfdfbaa01bb93bd4dc875aaef',
    '42/media/lua/shared/FurniturePushPull/FurniturePushPull_Actions.lua':
        '0e1f376fccee350f02154feccc9e135b6dfbbf9f68146931840243013d2ed5d8',
    '42/media/lua/shared/FurniturePushPull/FurniturePushPull_Core.lua':
        '8125a4f3cfd9d62c2a2ed3d8b4bd9225a8c8b6d944a4bae675386f510aeacf65',
}
CORE = '42/media/lua/shared/FurniturePushPull/FurniturePushPull_Core.lua'
ACTIONS = '42/media/lua/shared/FurniturePushPull/FurniturePushPull_Actions.lua'
HERE = Path(__file__).resolve().parent


def source_receipt(furniture_root):
    """Fail closed on any absent/changed source before loading the integration."""
    root = Path(furniture_root)
    receipt = {}
    for relative, expected in FURNITURE_SOURCES.items():
        path = root / relative
        if not path.is_file():
            raise ValueError('Missing selected FurniturePushPull source: ' + relative)
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError('Unreviewed FurniturePushPull source: ' + relative)
        receipt[relative] = actual
    return receipt


PRELUDE = r'''
client, server = false, false
function require() return true end
function isClient() return client end
function isServer() return server end
function getText(value) return value end
ISBaseTimedAction = {}
function ISBaseTimedAction:derive(name)
    local value = {}; value.__index = value
    return setmetatable(value, {__index = self})
end
'''

# Only engine/geometry boundaries are doubles. Core's local capture/detach/
# restore and its exported SP/server movement functions execute from real source.
WORLD = r'''
function list(values)
    local result = {values=values or {}}
    function result:size() return #self.values end
    function result:get(index) return self.values[index+1] end
    return result
end
function container(kind)
    local c={kind=kind or 'bin',items=list(),explored=false}
    function c:getType() return self.kind end
    function c:getItems() return self.items end
    function c:isExplored() return self.explored end
    function c:contains(item)
        for _, value in ipairs(self.items.values) do if value==item then return true end end
        return false
    end
    function c:AddItem(item) self.items.values[#self.items.values+1]=item; item.owner=self end
    c.AddItemBlind=c.AddItem
    function c:Remove(item)
        for index=#self.items.values,1,-1 do
            if self.items.values[index]==item then table.remove(self.items.values,index); item.owner=nil end
        end
    end
    function c:setDirty() end
    function c:setDrawDirty() end
    return c
end
function square(x)
    return {getX=function()return x end,getY=function()return 0 end,getZ=function()return 0 end}
end
sourceSquare,destination=square(1),square(2)
local sprite={getName=function()return 'fixture_bin' end}
function object(c,sq)
    local result={containers={c},square=sq}
    function result:getSquare() return self.square end
    function result:getSprite() return sprite end
    function result:getContainerCount() return #self.containers end
    function result:getContainerByIndex(i) return self.containers[i+1] end
    function result:getOverlaySprite() return nil end
    function result:setOverlaySprite() end
    return result
end
originalItem={id=1729,getContainer=function(self)return self.owner end}
sourceContainer=container()
source=object(sourceContainer,sourceSquare)
members={{object=source,square=sourceSquare,sprite=sprite}}
actor={}
ensureCalls,pickupCalls,sendCalls,overlayCalls=0,0,0,0
function lootDemandEnsure(c,character)
    assert(character==actor)
    ensureCalls=ensureCalls+1
    if not c.explored then c:AddItem(originalItem); c.explored=true end
    return true
end
props={spriteName='fixture_bin'}
function pickup()
    pickupCalls=pickupCalls+1
    assert(sourceContainer.explored,'pickup before authoritative ensure')
    assert(sourceContainer:getItems():size()==0,'capture did not detach newly generated item')
    source.square=nil
    return {temporaryMoveable=true}
end
function place()
    placedContainer=container();placedContainer.explored=true
    placed=object(placedContainer,destination)
    return true
end
function props:pickUpMoveableInternal() return pickup() end
function props:pickUpMoveable() return pickup() end
function props:findOnSquare() return source,nil end
ISMoveableSpriteProps={new=function()
    return {placeMoveableInternal=function()return place()end,placeMoveable=function()return place()end}
end}
FurniturePushPull.getMoveableData=function()return props end
FurniturePushPull.getFurnitureMembers=function()return members end
FurniturePushPull.findObject=function(x)if x==2 then return placed else return source end end
FurniturePushPull.getSquare=function(x)if x==1 then return sourceSquare else return destination end end
FurniturePushPull.validateServerMove=function()return {enduranceCost=0}end
FurniturePushPull.applyEndurance=function()end
FurniturePushPull.playMoveFeedback=function()end
ItemPickerJava={updateOverlaySprite=function()overlayCalls=overlayCalls+1 end}
function sendItemsInContainer(o,c)
    assert(o==placed and c==placedContainer)
    assert(c:contains(originalItem),'replicated snapshot lost original contents')
    sendCalls=sendCalls+1
end
function sendServerCommand()end
'''


def run_checks(furniture_root):
    receipt = source_receipt(furniture_root)
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError as error:
        raise RuntimeError('Source-backed furniture checks require Lupa with lua51 support') from error
    root = Path(furniture_root)
    core, actions = (root / CORE).read_text(), (root / ACTIONS).read_text()
    integration = (HERE / 'shared/LootDemandFurniture.lua').read_text()
    passed = []

    def runtime(world=False):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(PRELUDE)
        lua.execute(core)
        lua.execute(actions)
        if world:
            lua.execute(WORLD)
        return lua

    def check(name, body, world=False, setup=''):
        lua = runtime(world)
        if setup:
            lua.execute(setup)
        lua.execute(integration)
        lua.execute(body)
        passed.append(name)

    parity = '''
assert(result==true and pickupCalls==1)
assert(placedContainer:getItems():size()==1 and placedContainer:getItems():get(0)==originalItem)
assert(originalItem.id==1729 and originalItem.owner==placedContainer)
assert(sourceContainer:getItems():size()==0 and sourceContainer.explored)
assert(overlayCalls==1)
'''
    check('actual_core_server_capture_restore_and_replication',
        'server=true; result=FurniturePushPull.executeServerMove(actor,source,destination);'
        + parity + 'assert(ensureCalls==1 and sendCalls==1)', world=True)
    check('actual_core_sp_capture_restore',
        'result=FurniturePushPull.executeMove(actor,source,destination);'
        + parity + 'assert(ensureCalls==1 and sendCalls==0)', world=True)
    check('actual_shared_host_pull_completion', '''
server=true
local action={character=actor,sourceX=1,sourceY=0,sourceZ=0,spriteName='fixture_bin',
    destX=2,destY=0,destZ=0,isValid=function()return true end}
result=ISFurniturePullCommitAction.complete(action)
''' + parity + 'assert(ensureCalls==1 and sendCalls==1)', world=True)
    check('actual_shared_host_push_completion', '''
server=true
local action={character=actor,mode='push',sourceX=1,sourceY=0,sourceZ=0,spriteName='fixture_bin',
    destX=2,destY=0,destZ=0,isValid=function()return true end}
result=ISFurniturePushPullEffortAction.complete(action)
''' + parity + 'assert(ensureCalls==1 and sendCalls==1)', world=True)

    check('actual_shared_client_completion_does_not_capture_or_fill', """
client=true
local action={character=actor,mode='push',isValid=function()return true end}
assert(ISFurniturePushPullEffortAction.complete(action)==true)
assert(ISFurniturePullCommitAction.complete(action)==true)
assert(ensureCalls==0 and pickupCalls==0 and not sourceContainer.explored)
""", world=True)

    # Delegation probes replace only the exported operation, retaining the
    # actual source's group shape; they exercise wrapper contracts independently.
    capture_setup = '''
called=0
function original(...)
    called=called+1;received={n=select('#',...),...}
    return 'first',nil,'third',nil
end
FurniturePushPull.executeMove=original;FurniturePushPull.executeServerMove=original
'''
    for entry in ('executeMove', 'executeServerMove'):
        check(entry + '_preserves_arguments_and_multiple_returns', '''
local values={n=select('#',FurniturePushPull.ENTRY(actor,source,destination,'extra',nil)),
    FurniturePushPull.ENTRY(actor,source,destination,'extra',nil)}
assert(values.n==4 and values[1]=='first' and values[2]==nil and values[3]=='third' and values[4]==nil)
assert(received.n==5 and received[1]==actor and received[2]==source and received[3]==destination)
assert(received[4]=='extra' and received[5]==nil)
'''.replace('ENTRY', entry), world=True, setup=capture_setup)
        check(entry + '_client_does_not_fill', '''
client=true
FurniturePushPull.ENTRY(actor,source,destination)
assert(ensureCalls==0 and called==1 and not sourceContainer.explored)
'''.replace('ENTRY', entry), world=True, setup=capture_setup)
        check(entry + '_false_ensure_aborts_before_capture', '''
assert(FurniturePushPull.ENTRY(actor,source,destination)==false)
assert(called==0 and pickupCalls==0)
'''.replace('ENTRY', entry), world=True,
            setup=capture_setup + '\nlootDemandEnsure=function()return false end')
        check(entry + '_ensure_exception_aborts_and_propagates_identity', '''
local ok,err=pcall(FurniturePushPull.ENTRY,actor,source,destination)
assert(not ok and err==sentinel and called==0 and pickupCalls==0)
'''.replace('ENTRY', entry), world=True,
            setup=capture_setup + '\nsentinel={};lootDemandEnsure=function()error(sentinel)end')
        check(entry + '_original_exception_propagates_identity', '''
local ok,err=pcall(FurniturePushPull.ENTRY,actor,source,destination)
assert(not ok and err==sentinel and ensureCalls==1)
'''.replace('ENTRY', entry), world=True,
            setup='sentinel={};FurniturePushPull.' + entry + '=function()error(sentinel)end')

    check('all_member_containers_ensured_before_any_capture', '''
FurniturePushPull.executeServerMove(actor,source,destination)
assert(called==1 and #order==3 and order[1]==sourceContainer and order[2]==second and order[3]==third)
''', world=True, setup=capture_setup + '''
second,third=container(),container()
source.containers={sourceContainer,second}
local other=object(third,sourceSquare)
members[2]={object=other,square=sourceSquare}
order={}
lootDemandEnsure=function(c,character)assert(character==actor);order[#order+1]=c;return true end
FurniturePushPull.executeServerMove=function(...)
    assert(#order==3,'partial group reached capture');return original(...)
end
''')
    check('later_member_failure_does_not_move_partially_ensured_group', '''
assert(FurniturePushPull.executeServerMove(actor,source,destination)==false)
assert(sourceContainer.explored and called==0 and pickupCalls==0 and source.square==sourceSquare)
''', world=True, setup=capture_setup + '''
local other=object(container(),sourceSquare);members[2]={object=other,square=sourceSquare}
local firstEnsure=lootDemandEnsure
lootDemandEnsure=function(c,character)if c==sourceContainer then return firstEnsure(c,character)end;return false end
''')
    check('later_member_exception_does_not_move_partially_ensured_group', """
local ok,err=pcall(FurniturePushPull.executeServerMove,actor,source,destination)
assert(not ok and err==sentinel)
assert(sourceContainer.explored and called==0 and pickupCalls==0 and source.square==sourceSquare)
""", world=True, setup=capture_setup + """
local other=object(container(),sourceSquare);members[2]={object=other,square=sourceSquare}
local firstEnsure=lootDemandEnsure;sentinel={}
lootDemandEnsure=function(c,character)if c==sourceContainer then return firstEnsure(c,character)end;error(sentinel)end
""")
    check('ready_and_non_target_noop_keeps_original_result', """
sourceContainer.explored=true
assert(FurniturePushPull.executeServerMove(actor,source,destination)=='first')
assert(ensureCalls==1 and sourceContainer:getItems():size()==0 and called==1)
""", world=True, setup=capture_setup + """
sourceContainer.kind='other'
lootDemandEnsure=function(c,character)ensureCalls=ensureCalls+1;assert(character==actor);return true end
""")
    lua = runtime(world=True)
    lua.execute(integration)
    lua.execute('firstWrapper=FurniturePushPull.executeMove')
    lua.execute(integration)
    lua.execute('assert(FurniturePushPull.executeMove==firstWrapper and LootDemandFurniture.installed)')
    passed.append('integration_install_is_idempotent')
    lua = runtime()
    try:
        lua.execute(integration)
    except Exception as error:
        if 'requires the guarded core' not in str(error):
            raise
    else:
        raise AssertionError('Missing ensure bridge did not reject integration')
    assert not lua.eval('LootDemandFurniture.installed or false')
    passed.append('missing_bridge_fails_before_ready')
    return dict(checks=len(passed), passed=passed, sources=receipt, runtime='Lupa Lua 5.1',
        limits=['Engine pickup/place, Java containers, networking and geometry are doubles.',
                'Real selected Core capture/detach/restore and shared Host complete handlers execute.',
                'No game launch, live Host transport, multipart placement or timing is verified.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--furniture-root', required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(run_checks(args.furniture_root), indent=2))


if __name__ == '__main__':
    main()
