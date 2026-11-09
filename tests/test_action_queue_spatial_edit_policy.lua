assert(NativeActionRoot,'spatial edit policy requires --game or --native-action-root')
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
f.native('shared/RadioCom/ISRadioAction.lua')
f.native('client/TimedActions/WalkToTimedAction.lua')
f.native('shared/TimedActions/ISEquipWeaponAction.lua')
local function sourceText(path)
    if NativeReadText then return NativeReadText(path)end
    local file=assert(io.open(path));local text=file:read('*a');file:close();return text
end
local function reader(text)
    text=text:gsub('\r','');local position=1
    return {close=function()end,readLine=function()
        if position>#text then return end
        local boundary=text:find('\n',position,true)or #text+1
        local line=text:sub(position,boundary-1);position=boundary+1;return line
    end}
end
getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
local directFirstLine=NativeFirstLineOfClosure or function(callback)return debug.getinfo(callback,'S').linedefined+1 end
local metadataHook
getFirstLineOfClosure=function(callback)
    if metadataHook then metadataHook()end
    return directFirstLine(callback)
end
local reads,modReads=0,0
getGameFilesInput=function(path)
    reads=reads+1;return reader(sourceText(NativeActionRoot..'/'..path:gsub('^media/lua/','')))
end
getModFileReader=function(mod,path)
    assert(mod=='PZSurvivorToolkit');modReads=modReads+1
    return reader(sourceText(ProjectRoot..'/PZSurvivorToolkit/42/'..path))
end
isClient,isServer=function()return false end,function()return false end
local previousRequire=require;local modules={}
require=function(name)
    if name=='PZSurvivorToolkit/ActionQueueEditModel'or name=='PZSurvivorToolkit/ActionQueueEditAdapters'
        or name=='PZSurvivorToolkit/ActionQueueEditTransition'then
        if not modules[name]then modules[name]=f.project(name:match('/([^/]+)$'))end
        return modules[name]
    end
    return previousRequire(name)
end
local operations=f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
luautils={}
local utilities=sourceText(NativeActionRoot..'/shared/luautils.lua'):gsub('\r','')
assert(loadstring(assert(utilities:match('(function luautils.walkAdj%(.-\nend)'))..'\n'..
    assert(utilities:match('(luautils.getCorrectSquareForWall = function.-\nend)')),
    '@'..NativeActionRoot..'/shared/luautils.lua'))()
local actor=f.player
actor.class='IsoPlayer';actor.isLocalPlayer=function()return true end
actor.isDraggingCorpse=function()return false end
actor.isEquipped=function()return false end
actor.x,actor.y=.5,.5
local geometryCalls=0
local function geometry(value)geometryCalls=geometryCalls+1;return value end
actor.getX=function()return geometry(actor.x)end;actor.getY=function()return geometry(actor.y)end
actor.getSquare=function()return geometry(actor.square)end
actor.getCurrentSquare=function()return geometry(actor.currentSquare)end
IsoFlagType={collideW='collideW',collideN='collideN'}
local squares={}
local function coordinate(x,y,z)return x..':'..y..':'..z end
local cell={getGridSquare=function(_,x,y,z)return squares[coordinate(x,y,z)]end}
getCell=function()return cell end
local function square(x,y,z)
    local value={class='IsoGridSquare',x=x,y=y,z=z or 0,reachable=true}
    value.getX=function(self)return geometry(self.x)end;value.getY=function(self)return geometry(self.y)end
    value.getZ=function(self)return geometry(self.z)end
    value.has=function(self,flag)return geometry(self[flag]==true)end
    value.canReachTo=function(self,target)return geometry(self.reachable and target.reachable)end
    squares[coordinate(x,y,z or 0)]=value;return value
end
local origin=square(0,0);local target=square(1,0);local otherTarget=square(0,1)
actor.square,actor.currentSquare=origin,origin
-- Source fixtures model the callback-free Java bridge explicitly. Only its
-- original function identities receive the native-class certificate. The JVM
-- suite separately verifies the implementation against native method handles.
local bridgeCalls=0
local function spatialNoMovement(player,destination,excluded,targetObject)
    bridgeCalls=bridgeCalls+1
    if player~=actor or player.class~='IsoPlayer'or not player.square or not destination
        or destination.class~='IsoGridSquare'or player.square.class~='IsoGridSquare'
        or not rawequal(player.square,player.currentSquare)or math.floor(player.x)~=player.square.x
        or math.floor(player.y)~=player.square.y or player.playerMoving or player.justMoved or player.path
        or player.pathfindRunning then return false end
    if targetObject~=nil and(targetObject.class~='IsoObject'and targetObject.class~='IsoRadio'
        and targetObject.class~='IsoTelevision'or targetObject.gone
        or not rawequal(targetObject.square,destination))then return false end
    local function loaded(value)
        return value and squares[coordinate(value.x,value.y,value.z)]==value
    end
    if not loaded(player.square)or not loaded(destination)then return false end
    for _,value in ipairs(excluded or{})do if value==player.square then return false end end
    local corrected=destination
    if destination.collideW and player.x<destination.x then
        corrected=squares[coordinate(destination.x+1,destination.y,destination.z)]
    elseif destination.collideN and player.y<destination.y then
        corrected=squares[coordinate(destination.x,destination.y+1,destination.z)]
    end
    local near=loaded(corrected)and math.abs(corrected.x+.5-player.x)<=1.6
        and math.abs(corrected.y+.5-player.y)<=1.6 and player.square.z==corrected.z
        and player.square.reachable and corrected.reachable
    return near
end
local function spatialApiMatches(callback)return rawequal(callback,spatialNoMovement)end
toolkitQueueSpatialApiMatches,toolkitQueueSpatialNoMovement=spatialApiMatches,spatialNoMovement
getClassSimpleName=function(value)
    if rawequal(value,spatialApiMatches)or rawequal(value,spatialNoMovement)then return 'LuaJavaInvoker'end
    return type(value)=='function'and'LuaClosure'or type(value)=='table'and value.class or nil
end
local approach=f.project('ActionQueueApproach');assert(approach.install())
local policy=f.project('ActionQueuePolicy')
assert(policy.observeActiveResourceCandidate==nil,'rejected eager active-resource API must remain absent')
f.project('ActionQueueLabels');local Queue=f.project('ActionQueue')
local settlement=assert(PZSurvivorToolkit.ActionQueueSettlement)
local effects,routes=0,0
AdjacentFreeTileFinder={Find=function()routes=routes+1;error('edit inspection executed native route selection')end}
local function device(kind,location)
    local object={class=kind or 'IsoTelevision',square=location or target}
    local data={class='DeviceData',on=true,volume=.5,channel=200,mic=false}
    object.getObjectIndex=function(self)return self.gone and -1 or 0 end
    object.getSquare=function(self)return self.square end;object.getDeviceData=function()return data end
    data.getParent=function()return object end
    data.isIsoDevice=function()return true end;data.isVehicleDevice=function()return false end
    data.getIsTurnedOn=function()return data.on end;data.getPower=function()return 1 end
    data.getDeviceVolume=function()return data.volume end;data.getChannel=function()return data.channel end
    data.getMicIsMuted=function()return data.mic end
    data.getMinChannelRange=function()return 100 end;data.getMaxChannelRange=function()return 1000 end
    data.getIsBatteryPowered=function()return false end;data.canBePoweredHere=function()return true end
    data.getMediaType=function()return 1 end;data.hasMedia=function()return data.media==true end
    data.setDeviceVolume=function(_,value)effects=effects+1;data.volume=value end
    data.setChannel=function(_,value)effects=effects+1;data.channel=value end
    data.setMicIsMuted=function(_,value)effects=effects+1;data.mic=value end
    return object,data
end
local tv,tvData=device();local radio,radioData=device('IsoRadio')
local independent=device('IsoRadio',otherTarget)
local function book()
    local item=f.item('Base.BookCarpentry1')
    item.getUnequippedWeight=function()return .1 end;item.getIsCraftingConsumed=function()return false end
    item.getType=function()return 'BookCarpentry1'end
    return f.action(ISReadABook,{item=item})
end
local function queued(object,mode,value)
    local q=ISTimedActionQueue.queues[actor];local before=#q.queue;local action
    operations.run(function()
        assert(luautils.walkAdj(actor,object:getSquare(),true))
        action=ISRadioAction:new(mode or 'SetVolume',actor,object,value or .25)
        ISTimedActionQueue.add(action)
    end)
    local preparation=q.queue[before+1]
    assert(#q.queue==before+2 and approach.isAction(preparation))
    assert(preparation.toolkitQueueOperation==action.toolkitQueueOperation,'actual captured producer must remain one operation')
    return action,preparation
end
local function scene(object,lastValue)
    actor.x,actor.y,actor.square,actor.currentSquare=.5,.5,origin,origin
    actor.playerMoving,actor.moving,actor.justMoved,actor.path,actor.pathfindRunning=false,false,false,nil,false
    origin.reachable,target.reachable=true,true
    tv.square,radio.square=target,target;tv.gone,radio.gone=nil,nil
    local head,tail=book(),book();local q=f.queue(head)
    local first,firstPreparation=queued(object)
    local last,lastPreparation=queued(object,'SetVolume',lastValue or .75)
    ISTimedActionQueue.add(tail)
    return q,first,last,firstPreparation,lastPreparation,head,tail
end
local function unchanged(q,first,last,head,tail)
    assert(q.queue[1]==head and q.queue[#q.queue]==tail)
    assert(not first.action and not last.action and not first.started and not last.started)
    assert(tvData.volume==.5 and radioData.volume==.5 and effects==0 and routes==0 and geometryCalls==0,
        'policy/source preparation must not execute native actions, helpers or effects')
end
local function downstreamConsumers(q,object)
    local tail=table.remove(q.queue)
    ISTimedActionQueue.add(ISRadioAction:new('MuteVolume',actor,object,true))
    ISTimedActionQueue.add(ISRadioAction:new('UnMuteVolume',actor,object,.25))
    ISTimedActionQueue.add(tail)
end
-- Match the full TV producer bank: only the two volume callbacks are scoped;
-- mute/unmute/channel and native media ejection still share the device resource.
do
    f.native('shared/TimedActions/ISDeviceBatteryAction.lua')
    f.native('shared/TimedActions/ISDeviceMediaAction.lua')
    local media=f.project('ActionQueueMedia');assert(media.install())
    target.getDeviceData=function()return tvData end
    tvData.media=true
    local q,first,last,firstPreparation,lastPreparation,head,tail=scene(tv,.25)
    q.queue[#q.queue]=nil
    local function body(mode,value)
        local action=ISRadioAction:new(mode,actor,tv,value);ISTimedActionQueue.add(action);return action
    end
    local mute=body('MuteVolume',true)
    local unmute=body('UnMuteVolume',.25)
    local channel=body('SetChannel',300)
    local eject=ISDeviceMediaAction:new(actor,true,nil,target);ISTimedActionQueue.add(eject)
    ISTimedActionQueue.add(tail)
    assert(policy.evaluateCancel(q,last,true).allowed,'full TV resource component rejected redundant group cancellation')
    assert(policy.evaluateMove(q,eject,channel).allowed,'native media/property pair independence was lost')
    assert(Queue.move(q,eject,channel)and Queue.cancelOperation(q,last))
    local expected={head,firstPreparation,first,mute,unmute,eject,channel,tail}
    assert(#q.queue==#expected)
    for i,action in ipairs(expected)do assert(q.queue[i]==action,'full TV physical queue differs at '..i)end
    assert(q:indexOf(lastPreparation)==-1 and tvData.media==true)
    unchanged(q,first,last,head,tail);tvData.media=false
end
-- Same-device projected effects must remain available with the real native
-- preparation/body shape, rather than only for isolated setter constructors.
do
    local q,first,last,firstPreparation,lastPreparation,head,tail=scene(tv,.25)
    local decision=policy.evaluateCancel(q,last,true)
    assert(decision.allowed,'redundant native TV operation cancellation: '..tostring(decision.reason))
    assert(decision.first==4 and decision.last==5,'cancellation must include its exact pending preparation/body group')
    unchanged(q,first,last,head,tail)
    assert(Queue.cancelOperation(q,last))
    assert(#q.queue==4 and q.queue[2]==firstPreparation and q.queue[3]==first and q.queue[4]==tail)
    assert(q:indexOf(last)==-1 and q:indexOf(lastPreparation)==-1)
    assert(not last.action and not lastPreparation.action,'cancelled operation must never allocate/replay')
end
do
    local q,first,last,firstPreparation,lastPreparation,head,tail=scene(radio)
    local decision=policy.evaluateMove(q,last,first)
    assert(decision.allowed,'same-property native radio reorder: '..tostring(decision.reason))
    unchanged(q,first,last,head,tail)
    assert(Queue.move(q,last,first))
    assert(q.queue[2]==lastPreparation and q.queue[3]==last and q.queue[4]==firstPreparation and q.queue[5]==first)
    assert(q.queue[6]==tail and effects==0 and routes==0,'atomic move must preserve the unrelated tail without effects')
end
-- Different device resources still retain the actor-position dependency.
do
    local q,first,last,_,_,head,tail=scene(tv)
    q.queue[#q.queue]=nil;local extra=queued(independent,'SetChannel',300);ISTimedActionQueue.add(tail)
    assert(policy.evaluateMove(q,last,first).allowed and policy.evaluateCancel(q,last,true).allowed)
    assert(q:indexOf(extra)>0);unchanged(q,first,last,head,tail)
end
-- The public body-facing cancel delegates to whole-operation cancellation for
-- an unstarted cancelWaiting body, so it must never orphan its preparation.
do
    local q,first,last,_,preparation,head,tail=scene(tv)
    local decision=policy.evaluateCancel(q,last,false)
    assert(decision.allowed and decision.first==4 and decision.last==5,'body-facing cancel must include its preparation')
    unchanged(q,first,last,head,tail)
    assert(Queue.cancel(q,last)and q:indexOf(preparation)==-1 and q:indexOf(last)==-1)
    assert(q.queue[1]==head and q.queue[#q.queue]==tail and #q.queue==4,'body-facing cancel damaged unrelated operations')
end
-- A completed native walk can leave its animation movement latch set while
-- the local actor is stationary and reading; that latch is not locomotion.
do
    local q,first,last=scene(tv)
    actor.moving=true
    assert(policy.evaluateMove(q,last,first).allowed and policy.evaluateCancel(q,last,true).allowed)
end
-- Actual movement/unavailable geometry remains opaque to the projected edit.
for _,change in ipairs({'far-actor','far-target','unreachable','unloaded','deleted','moved-device',
    'stale-current-square','stale-actor-tile','manual-motion','just-moved','path-running',
    'wall-correction-unloaded','excluded-current','foreign-helper'})do
  for _,dependent in ipairs({false,true})do
    local q,first,last,_,preparation,head,tail=scene(tv)
    if dependent then downstreamConsumers(q,tv)end
    local originalHelper=luautils.getCorrectSquareForWall;local foreignCalls=0
    if change=='far-actor'then actor.x=20
    elseif change=='far-target'then target.x=20
    elseif change=='unreachable'then origin.reachable=false
    elseif change=='unloaded'then squares[coordinate(1,0,0)]=nil
    elseif change=='deleted'then tv.gone=true
    elseif change=='moved-device'then tv.square=otherTarget
    elseif change=='stale-current-square'then actor.currentSquare=otherTarget
    elseif change=='stale-actor-tile'then actor.x=1.2
    elseif change=='manual-motion'then actor.playerMoving=true
    elseif change=='just-moved'then actor.justMoved=true
    elseif change=='path-running'then actor.pathfindRunning=true
    elseif change=='wall-correction-unloaded'then target.collideW=true
    elseif change=='excluded-current'then
        local args=preparation.toolkitQueueCommand.snapshot.args;args.n=4;args[4]={origin}
    else luautils.getCorrectSquareForWall=function()foreignCalls=foreignCalls+1;error('foreign route helper executed')end end
    assert(not policy.evaluateMove(q,last,first).allowed,'unsafe spatial move accepted '..change)
    local savedBridge=toolkitQueueSpatialNoMovement;toolkitQueueSpatialNoMovement=nil
    local legacy=policy.evaluateCancel(q,last,true);toolkitQueueSpatialNoMovement=savedBridge
    local decision=policy.evaluateCancel(q,last,true)
    if dependent then
        assert(not legacy.allowed,'unsafe cancellation negative needs a real downstream legacy dependency '..change)
        assert(not decision.allowed,'unsafe spatial cancellation accepted '..change)
    else
        assert(decision.allowed==legacy.allowed and decision.reason==legacy.reason,
            'initially ineligible spatial request changed safe legacy cancellation '..change)
    end
    assert(foreignCalls==0 and effects==0 and routes==0)
    luautils.getCorrectSquareForWall=originalHelper;target.x=1;target.collideW=nil;squares[coordinate(1,0,0)]=target
    unchanged(q,first,last,head,tail)
  end
end
-- An earlier unclassified action or genuine native walk could change the
-- actor's eventual position. Current adjacency cannot prove those prefixes.
for _,kind in ipairs({'pending-walk','current-walk','unknown-prefix'})do
    local q,first,last,_,_,head,tail=scene(tv)
    local prefix
    if kind=='unknown-prefix'then prefix=f.action(ISBaseTimedAction,{})
    else prefix=f.action(ISWalkToTimedAction,{location=otherTarget})end
    if kind=='current-walk'then q.queue[1]=prefix;q.current=prefix
    else table.insert(q.queue,2,prefix)end
    assert(not policy.evaluateMove(q,last,first).allowed,'position-changing prefix accepted '..kind)
    local savedBridge=toolkitQueueSpatialNoMovement;toolkitQueueSpatialNoMovement=nil
    local legacy=policy.evaluateCancel(q,last,true);toolkitQueueSpatialNoMovement=savedBridge
    local cancellation=policy.evaluateCancel(q,last,true)
    assert(cancellation.allowed==legacy.allowed and cancellation.reason==legacy.reason,
        'position-changing prefix changed legacy pending removal authority '..kind)
    assert(q:indexOf(tail)>0 and effects==0 and routes==0)
end
-- Provisional no-movement approval must not wash native device prerequisites.
for _,mode in ipairs({'ToggleOnOff','TogglePlayMedia','AddHeadphones'})do
    local q,first,last=scene(radio)
    last.mode=mode
    assert(not policy.evaluateMove(q,last,first).allowed,'unsupported body acquired spatial permission '..mode)
end
for _,change in ipairs({'foreign-body','foreign-preparation','wrong-actor','split-operation','started-preparation','cancelled-token'})do
    local q,first,last,_,preparation=scene(tv);local calls=0
    local foreign=function()calls=calls+1;error('foreign action callback executed')end
    if change=='foreign-body'then last.isValid=foreign
    elseif change=='foreign-preparation'then preparation.perform=foreign
    elseif change=='wrong-actor'then preparation.toolkitQueueCommand.snapshot.args[1]={}
    elseif change=='split-operation'then preparation.toolkitQueueOperation={}
    elseif change=='started-preparation'then preparation.started=true
    else preparation.toolkitQueueOperation.toolkitCancelled=true end
    if change=='split-operation'then
        local savedBridge=toolkitQueueSpatialNoMovement;toolkitQueueSpatialNoMovement=nil
        local legacy=policy.evaluateMove(q,last,first);toolkitQueueSpatialNoMovement=savedBridge
        local decision=policy.evaluateMove(q,last,first)
        assert(decision.allowed==legacy.allowed and decision.reason==legacy.reason,
            'split operation changed the existing direct-body permission')
        assert(preparation.toolkitQueueOperation~=last.toolkitQueueOperation and not preparation.started)
    else assert(not policy.evaluateMove(q,last,first).allowed,'changed preparation/body authority accepted '..change)end
    assert(calls==0 and effects==0 and routes==0,'policy executed a foreign callback '..change)
end
for _,change in ipairs({'missing-helper','changed-helper','missing-checker','changed-checker','changed-classifier'})do
    local q,first,last=scene(tv);local classifier=getClassSimpleName;local calls=0
    local foreign=function()calls=calls+1;error('foreign bridge/checker executed')end
    if change=='missing-helper'then toolkitQueueSpatialNoMovement=nil
    elseif change=='changed-helper'then toolkitQueueSpatialNoMovement=foreign
    elseif change=='missing-checker'then toolkitQueueSpatialApiMatches=nil
    elseif change=='changed-checker'then toolkitQueueSpatialApiMatches=foreign
    else getClassSimpleName=foreign end
    assert(not policy.evaluateMove(q,last,first).allowed,'changed bridge authority accepted '..change)
    assert(calls==0,'policy executed replaced bridge/checker '..change)
    toolkitQueueSpatialNoMovement,toolkitQueueSpatialApiMatches=spatialNoMovement,spatialApiMatches
    getClassSimpleName=classifier
end
do
    local q,first,last=scene(tv)
    tvData.on=false
    assert(not policy.evaluateMove(q,last,first).allowed,'spatial preparation bypassed device power prerequisite')
    tvData.on=true
end
-- Diagnostics run after evaluation: public mutation must recheck geometry.
do
    local q,first,last,_,_,head,tail=scene(tv);local record=policy.record
    policy.record=function()actor.x=20 end
    assert(not Queue.move(q,last,first),'late actor movement escaped final application check')
    policy.record=record;actor.x=.5;unchanged(q,first,last,head,tail)
    q,first,last,_,_,head,tail=scene(tv)
    downstreamConsumers(q,tv)
    policy.record=function()target.reachable=false end
    assert(not Queue.cancelOperation(q,last),'late target unavailability escaped final application check')
    policy.record=record;target.reachable=true;unchanged(q,first,last,head,tail)
end
-- Commit callbacks run after evaluation and need their own fresh proof.
do
    local q,first,last,firstPreparation,lastPreparation,head,tail=scene(tv)
    local evaluate,settings=policy.evaluateMove,PZSurvivorToolkit.Settings.actionQueue
    local evaluations,mutations,commitCallback=0,0,false
    -- Observe completion without changing the real evaluator's result. The
    -- stable Settings callback changes geometry only after its second proof,
    -- during Queue.move's final callback-bearing snapshot check.
    policy.evaluateMove=function(...)
        local decision=evaluate(...);evaluations=evaluations+1
        if evaluations==2 and decision.allowed then commitCallback=true end
        return decision
    end
    PZSurvivorToolkit.Settings.actionQueue=function()
        if commitCallback then commitCallback=false;actor.x=20;mutations=mutations+1 end
        return settings()
    end
    local completed,moved,reason=pcall(Queue.move,q,last,first)
    policy.evaluateMove,PZSurvivorToolkit.Settings.actionQueue=evaluate,settings
    assert(completed,reason)
    assert(mutations==1 and not moved,'final Settings callback escaped the move commit proof')
    assert(q.queue[2]==firstPreparation and q.queue[3]==first and q.queue[4]==lastPreparation and q.queue[5]==last,
        'late commit geometry mutation reordered the pending operation')
    unchanged(q,first,last,head,tail);actor.x=.5
end
-- Source metadata can reenter while contracts are being prepared. Even an
-- equivalent effect in a later standalone action changes the inspected queue.
do
    local q,first,last=scene(tv,.25);downstreamConsumers(q,tv)
    local mute=q.queue[6];assert(mute.mode=='MuteVolume')
    local called=false
    metadataHook=function()
        metadataHook=nil;called=true;mute.mode='SetVolume';mute.secondaryItem=0
    end
    local decision=policy.evaluateCancel(q,last,true);metadataHook=nil
    assert(called and not decision.allowed and decision.reason=='unavailable',
        'equivalent later setter mutation escaped source-preparation queue watch')
    assert(mute.mode=='SetVolume'and mute.secondaryItem==0 and effects==0 and routes==0)
end
do
    local q,first,last,_,_,head,tail=scene(tv,.25);local replacement
    metadataHook=function()metadataHook=nil;replacement=book();q.queue[#q.queue]=replacement end
    local decision=policy.evaluateMove(q,last,first);metadataHook=nil
    assert(replacement and replacement~=tail and not decision.allowed and decision.reason=='unavailable',
        'unrelated queue-tail replacement escaped source-preparation queue watch')
    assert(q.queue[1]==head and q.queue[#q.queue]==replacement and effects==0 and routes==0)
end
do
    local q,first,last,firstPreparation,lastPreparation,head,tail=scene(tv,.25)
    local observed=bridgeCalls;local moved=false
    metadataHook=function()
        if bridgeCalls>observed then metadataHook=nil;actor.x=20;moved=true end
    end
    local decision=policy.evaluateMove(q,last,first);metadataHook=nil
    -- The next preparation may reject during early eligibility and fall back
    -- before a final proof is consumed. Both paths must conservatively deny.
    assert(moved and not decision.allowed and type(decision.reason)=='string',
        'near-to-far change after initial eligibility escaped spatial guards')
    assert(q.queue[2]==firstPreparation and q.queue[3]==first and q.queue[4]==lastPreparation and q.queue[5]==last)
    unchanged(q,first,last,head,tail);actor.x=.5
end
-- An incomplete spatial model may use the original cancellation authority.
-- Its source-shape guard must survive that fallback without imposing a new
-- geometry requirement on independently safe legacy cancellation.
for _,foreign in ipairs({false,true})do
    local q,first,last,firstPreparation,lastPreparation,head,tail=scene(tv,.25)
    local evaluate,forceCancel=policy.evaluateCancel,last.forceCancel
    local evaluations,foreignCalls,changed=0,0,false
    policy.evaluateCancel=function(...)
        evaluations=evaluations+1
        if evaluations==2 then
            local observed=bridgeCalls
            metadataHook=function()
                if bridgeCalls>observed then
                    metadataHook=nil;actor.x=20;changed=true
                    if foreign then last.forceCancel=function()foreignCalls=foreignCalls+1 end end
                end
            end
        end
        return evaluate(...)
    end
    local completed,cancelled,reason=pcall(Queue.cancelOperation,q,last)
    policy.evaluateCancel=evaluate;metadataHook=nil;last.forceCancel=forceCancel
    assert(completed,reason)
    assert(changed and evaluations==2,'fallback audit did not reach second-evaluation preparation metadata')
    assert(foreignCalls==0,'source-mutated forceCancel ran after spatial model fallback')
    if foreign then
        assert(not cancelled and reason=='unavailable','source mutation escaped retained fallback shape guard')
        assert(q.queue[2]==firstPreparation and q.queue[3]==first and q.queue[4]==lastPreparation and q.queue[5]==last,
            'source-mutated pending operation was removed during fallback')
    else
        assert(cancelled and #q.queue==4 and q.queue[2]==firstPreparation and q.queue[3]==first,
            'geometry-only fallback lost independently safe legacy cancellation')
        assert(q:indexOf(lastPreparation)==-1 and q:indexOf(last)==-1)
    end
    unchanged(q,first,last,head,tail);actor.x=.5
end
-- Provisional spatial edits are query-local, including caller-owned diagnostic
-- contexts and successful advisory/reason entrypoints.
for _,entrypoint in ipairs({'previewMove','evaluateMove','moveReason'})do
    local q,first,last,firstPreparation,lastPreparation=scene(tv,.25)
    local context={contracts={},items={}}
    if entrypoint=='moveReason'then
        assert(policy.moveReason(q,last,first,false,context)==nil,'positive raw spatial reason was denied')
    else
        local decision=policy[entrypoint](q,last,first,false,context)
        assert(decision.reason==nil and(entrypoint~='evaluateMove'or decision.allowed),
            'positive spatial decision was denied before checking context isolation')
    end
    for _,preparation in ipairs({firstPreparation,lastPreparation})do
        local cached=assert(context.contracts[preparation],'diagnostic context did not receive the inspected preparation')
        cached=assert(cached[1],'diagnostic context did not retain the ordinary preparation contract')
        assert(cached.edit==nil,'provisional preparation edit escaped through caller-owned context')
        local ordinary=assert(policy.inspect(preparation),'owned preparation lost its ordinary inspection contract')
        assert(ordinary.edit==nil,'provisional preparation edit escaped into ordinary inspection')
    end
end
f.project('ActionQueueReading')
-- The common active route retains the native/stateless guards. Original
-- returns stay intact; these source fixtures do not attest transfer outcomes.
do
    local inventory=actor.inventory
    actor.inventory={class='ItemContainer',getType=function()return 'inventory'end,
        getParent=function()return actor end,getContainingItem=function()end,getAcceptItemFunction=function()end}
    local function activeScene(borrowed)
        local q,first,last,firstPreparation,lastPreparation,head,tail=scene(tv)
        tail.item.getFullType=function()return 'Base.BookCooking1'end
        for _,action in ipairs({head,tail})do
            action.item.getNumberOfPages=function()return 100 end
            action.item.getAlreadyReadPages=function()return 37 end
            action.item.getEquipParent=function()end;action.item.getAttachedSlot=function()return -1 end
        end
        head.toolkitQueueOperation.toolkitStarted=true
        settlement.track(head,'body')
        head.action={isStarted=function()return true end,finished=function()return false end,
            isForceComplete=function()return false end,forceStop=function(self)self.stopped=true end};head.started=true
        local returning
        if borrowed then
            local owner={class='IsoObject'}
            local shelf={class='ItemContainer',getType=function()return 'crate'end,
                getContainingItem=function()end,getAcceptItemFunction=function()end,getParent=function()return owner end}
            returning=f.action(ISInventoryTransferAction,{item=head.item,srcContainer=actor.inventory,
                destContainer=shelf,allowMissingItems=true,maxTime=31,
                queueList={{items={head.item},time=31,type=head.item:getFullType()}}})
            returning.toolkitQueueOperation=head.toolkitQueueOperation;table.insert(q.queue,2,returning)
        end
        return q,first,last,firstPreparation,lastPreparation,head,tail,returning
    end
    local function retained(q,head,returning,item,source,destination)
        assert(q.current==head and q.queue[1]==head and head.item:getAlreadyReadPages()==37)
        assert(q:indexOf(returning)>1 and returning.item==item and returning.srcContainer==source
            and returning.destContainer==destination and returning.toolkitQueueOperation==head.toolkitQueueOperation,
            'common active edit changed the original return item/endpoints/owner')
        assert(not returning.action and not returning.started,'common active edit executed the retained native return')
        assert(effects==0 and routes==0 and geometryCalls==0,'native-stateless route executed actions or Lua geometry')
    end
    for _,demote in ipairs({false,true})do
        local q,first,last,firstPreparation,lastPreparation,head,tail,returning=activeScene(true)
        downstreamConsumers(q,tv)
        local item,source,destination=returning.item,returning.srcContainer,returning.destContainer
        local action,targetAction,after=first,head,false
        if demote then action,targetAction,after=head,last,true end
        local nativeBridgeReads=bridgeCalls
        local decision=policy.evaluateMove(q,action,targetAction,after)
        assert(bridgeCalls==nativeBridgeReads,
            'native-stateless decision inspected unnecessary geometry')
        assert(decision.allowed and decision.commonActiveEdit==true and decision.commonActiveEditRoute=='native-stateless'
            and not decision.spatialValidated,
            'eligible borrowed reader edit missed native-stateless route: '..tostring(decision.reason))
        assert(decision.preempt and (decision.demote==true)==demote,'native-stateless route lost preempt/demotion semantics')
        retained(q,head,returning,item,source,destination)
        assert(Queue.move(q,action,targetAction,after),'eligible common active move failed at commit')
        assert(q.toolkitResume==(demote and last or first)and q.toolkitCancel==head,'native-stateless route lost native stop/resume anchor')
        if demote then
            assert(q.queue[2]==firstPreparation and q.queue[3]==first and q.queue[4]==lastPreparation
                and q.queue[5]==last and q.queue[6]==returning,'demotion detached original return')
        else
            assert(q.queue[2]==firstPreparation and q.queue[3]==first and q.queue[4]==returning
                and q.queue[5]==lastPreparation and q.queue[6]==last,'promotion detached original return')
        end
        retained(q,head,returning,item,source,destination)
    end
    do
        local q,first,_,_,_,head=activeScene(false)
        local decision=policy.evaluateMove(q,first,head)
        assert(decision.allowed and decision.commonActiveEdit==true,
            'eligible root reader did not use native-stateless route')
        assert(not q.toolkitCancel and not q.toolkitResume and effects==0 and routes==0)
    end
    -- Suffix device prerequisites keep the same state/order after the two
    -- independent adjacent blocks commute. They need no speculative replay.
    do
        local q,first,last,_,_,head,tail,returning=activeScene(true)
        downstreamConsumers(q,tv)
        local mute,unmute=q.queue[#q.queue-2],q.queue[#q.queue-1]
        assert(mute.mode=='MuteVolume'and unmute.mode=='UnMuteVolume')
        local decision=policy.evaluateMove(q,first,head)
        assert(decision.allowed and decision.commonActiveEdit,'independent adjacent swap rejected unchanged suffix')
        assert(Queue.move(q,first,head))
        assert(q.queue[#q.queue]==tail and q:indexOf(last)<q:indexOf(mute))
        assert(q.queue[#q.queue-2]==mute and q.queue[#q.queue-1]==unmute
            and mute.mode=='MuteVolume'and unmute.mode=='UnMuteVolume',
            'adjacent active edit altered same-device suffix order/prerequisites')
    end
    for _,change in ipairs({'reader-callback','device-callback','equipment','far'})do
        local q,first,last,_,_,head=activeScene(true)
        local calls=0;local foreign=function()calls=calls+1;error('unsupported active callback executed')end
        if change=='reader-callback'then head.onCancelFunc=foreign
        elseif change=='device-callback'then first.onCompleteFunc=foreign
        elseif change=='equipment'then
            local equipment=f.action(ISEquipWeaponAction,{item=head.item})
            equipment.toolkitQueueOperation=first.toolkitQueueOperation
            table.insert(q.queue,q:indexOf(first)+1,equipment)
        else actor.x=20 end
        local framework=PZSurvivorToolkit.ActionQueueEditModel;PZSurvivorToolkit.ActionQueueEditModel=nil
        local legacy=policy.evaluateMove(q,first,head);PZSurvivorToolkit.ActionQueueEditModel=framework
        local decision=policy.evaluateMove(q,first,head)
        if change=='far'then
            assert(decision.allowed==legacy.allowed and decision.reason==legacy.reason,
                'initially far active edit changed legacy authority')
        else assert(not decision.allowed and not decision.commonActiveEdit,
            'unsupported active callbacks/equipment were accepted: '..change)end
        assert(calls==0 and effects==0 and routes==0)
    end
    actor.inventory=inventory
end
-- Active observation can describe a genuine adjacent native device preparation
-- without granting a new edit permission or forecasting a route. The same
-- private no-movement pair proof must survive the real cleanup observation.
do
    local inventory=actor.inventory
    actor.inventory={class='ItemContainer',getType=function()return 'inventory'end,
        getParent=function()return actor end,getContainingItem=function()end,getAcceptItemFunction=function()end}
    local settlement=assert(PZSurvivorToolkit.ActionQueueSettlement)
    local function activeScene()
        local q,first,_,preparation,_,head,tail=scene(tv)
        -- Keep exactly one real native preparation/body pair and a reader of a
        -- different full type, whose native page progress is independent.
        table.remove(q.queue,5);table.remove(q.queue,4)
        tail.item.getFullType=function()return 'Base.BookCooking1'end
        for _,action in ipairs({head,tail})do
            action.item.getNumberOfPages=function()return 100 end
            action.item.getAlreadyReadPages=function()return 37 end
        end
        head.action={isStarted=function()return true end,finished=function()return false end,
            isForceComplete=function()return false end}
        head.started=true
        settlement.track(head,'body')
        return q,first,preparation,head,tail
    end
    local function observe(q,first,resolveNoMovement)
        local before={unpack(q.queue)};local native=q.current.action
        local forbidden={[ISReadABook.isValid]=true,[ISRadioAction.isValid]=true,
            [ISReadABook.start]=true,[ISRadioAction.start]=true}
        debug.sethook(function(event)
            if event=='call'and forbidden[debug.getinfo(2,'f').func]then error('active observation executed a native action')end
        end,'c')
        local ok,result=pcall(policy.observeActiveEdit,q,{kind='move',action=first,target=q.current,resolveNoMovement=resolveNoMovement})
        debug.sethook()
        assert(ok,result)
        assert(#q.queue==#before and q.current==before[1]and q.current.action==native)
        for index,action in ipairs(before)do assert(q.queue[index]==action,'active observation changed queue membership')end
        assert(not q.toolkitCancel and not q.toolkitResume and effects==0 and routes==0 and geometryCalls==0)
        return result
    end
    local q,first,preparation,head=activeScene()
    local before=policy.evaluateMove(q,first,head)
    local ledger=settlement.observeEditCleanup(q,head)
    assert(ledger.status=='observed'and #ledger.borrowings==0,'root reader must use the actual empty earned-loan ledger')
    local result=observe(q,first)
    assert(result.status=='observed'and result.projection.status=='deferred'
        and result.projection.reason=='edit_native_resolution'and #result.nativeNoMovement==0,
        'default active observation must retain its typed native phase')
    for _,flag in ipairs({false,'true',1,{}})do
        result=observe(q,first,flag)
        if flag==false then
            assert(result.status=='observed'and result.projection.status=='deferred'and #result.nativeNoMovement==0)
        else assert(result.status=='unhandled'and result.nativeNoMovement==nil,'malformed no-movement opt-in was accepted')end
    end
    for _,field in ipairs({'after','resolveNoMovement'})do
        local calls=0
        local intent={kind='move',action=first,target=head,whole=false}
        if field=='resolveNoMovement'then intent.after=false end
        setmetatable(intent,{__metatable=false,__index=function(_,key)
            calls=calls+1;error('unsupported intent getter executed: '..key)
        end})
        local list,native=q.queue,head.action
        local before={unpack(list)}
        local ok,rejected=pcall(policy.observeActiveEdit,q,intent)
        assert(ok and rejected.status=='unhandled'and rejected.nativeNoMovement==nil and calls==0,
            'masked intent metatable reached '..field..' before plain-input validation')
        assert(q.queue==list and #list==#before and q.current==head and head.action==native
            and head.started and native:isStarted()and not native:finished()and not native:isForceComplete()
            and not q.toolkitCancel and not q.toolkitResume,'masked intent changed the native reader/queue')
        for index,action in ipairs(before)do assert(list[index]==action,'masked intent changed queue membership')end
    end
    result=observe(q,first,true)
    assert(result.status=='observed'and result.allowed==nil and result.projection.status=='allowed',
        'adjacent native preparation must close the active observer effect gap')
    assert(result.nativeNoMovement and #result.nativeNoMovement==1 and result.nativeNoMovement[1]==preparation,
        'active observation must report only the exact accepted native preparation')
    local after=policy.evaluateMove(q,first,head)
    assert(after.allowed==before.allowed and after.reason==before.reason
        and after.commonActiveEdit==before.commonActiveEdit,
        'diagnostic observation changed the independent active edit decision')
    q,first,preparation=activeScene()
    local tail=table.remove(q.queue)
    local second,secondPreparation=queued(radio,'SetVolume',.4)
    ISTimedActionQueue.add(tail)
    result=observe(q,first,true)
    assert(result.projection.status=='allowed'and #result.nativeNoMovement==2
        and result.nativeNoMovement[1]==preparation and result.nativeNoMovement[2]==secondPreparation,
        'each adjacent native pair needs its own exact no-movement proof')
    local getter=actor.getInventory;local initial=bridgeCalls;local changed=false
    actor.getInventory=function(self)
        if not changed and bridgeCalls>=initial+2 then changed=true;tv.square=otherTarget end
        return getter(self)
    end
    result=observe(q,first,true)
    actor.getInventory=getter
    assert(changed and result.status=='unhandled'and result.reason=='unavailable'and result.nativeNoMovement==nil,
        'the first pair lease was lost when the later pair captured its proof')
    for _,change in ipairs({'far','unknown-geometry','args3-false'})do
        q,first,preparation=activeScene()
        if change=='far'then actor.x=20
        elseif change=='unknown-geometry'then squares[coordinate(1,0,0)]=nil
        else preparation.toolkitQueueCommand.snapshot.args[3]=false end
        result=observe(q,first,true)
        assert(result.status=='observed'and result.projection.status=='deferred'
            and result.projection.reason=='edit_native_resolution'
            and(not result.nativeNoMovement or #result.nativeNoMovement==0),
            'unsupported no-movement facts must retain the native phase: '..change)
        squares[coordinate(1,0,0)]=target
    end
    for _,change in ipairs({'helper','target','geometry'})do
        q,first=activeScene()
        local getter=actor.getInventory;local initial=bridgeCalls;local changed=false
        actor.getInventory=function(self)
            if not changed and bridgeCalls>initial then
                changed=true
                if change=='helper'then toolkitQueueSpatialNoMovement=nil
                elseif change=='target'then tv.square=otherTarget
                else actor.x=20 end
            end
            return getter(self)
        end
        result=observe(q,first,true)
        actor.getInventory=getter;toolkitQueueSpatialNoMovement=spatialNoMovement
        assert(changed and result.status=='unhandled'and result.reason=='unavailable'
            and result.nativeNoMovement==nil,'cleanup-time mutation escaped the joint spatial proof: '..change)
    end
    actor.inventory=inventory
end
-- Production demotion keeps native per-row ordering: deny an earlier
-- shared-item conflict before inspecting a later unrelated unknown contract.
do
    local inspections=0
    PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('fixture.late-demotion-unknown',{
        types={'FixtureLateDemotionUnknown'},matches=function()return true end,
        inspect=function()inspections=inspections+1;return{knownInputs=false,items={},itemTypes={},targets={}}end,
    })
    local head=book()
    head.action={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
    local shared=f.action(ISEquipWeaponAction,{item=head.item})
    local later=f.action(ISBaseTimedAction,{Type='FixtureLateDemotionUnknown'})
    local q=f.queue(head,shared,later)
    local decision=policy.evaluateMove(q,head,later,true)
    assert(not decision.allowed and decision.reason=='move_shared_item'and decision.blocker==head
        and decision.resource==head.item:getID(),'demotion changed the first native pair denial')
    assert(inspections==0,'demotion inspected a later unknown source before its earlier native pair conflict')
    assert(q.queue[1]==head and q.queue[2]==shared and q.queue[3]==later and not q.toolkitCancel and not q.toolkitResume)
end
local sourceReads,candidateReads=reads,modReads
do
    local q,first,last=scene(tv)
    for _=1,3 do assert(policy.evaluateMove(q,last,first).allowed and policy.evaluateCancel(q,last,true).allowed)end
end
assert(reads==sourceReads,'warm spatial policy decisions must not repeat native source IO')
assert(modReads==candidateReads,'warm spatial policy decisions must not repeat candidate source IO')
assert(effects==0 and routes==0 and geometryCalls==0 and bridgeCalls>0)
print('Spatial edit policy: captured native device groups, atomic edits, prerequisite/position guards, stale geometry and callback-free inspection passed.')
if TestCoverage then TestCoverage('source-contract','passed')end
