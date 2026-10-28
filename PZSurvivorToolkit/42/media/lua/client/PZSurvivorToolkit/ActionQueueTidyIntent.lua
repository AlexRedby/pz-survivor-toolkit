require "Hotbar/ISHotbar"
require "PZSurvivorToolkit/ActionQueueAcknowledgements"
local Settlement = require "PZSurvivorToolkit/ActionQueueSettlement"
local Proof = require "PZSurvivorToolkit/SourceProof"
local proofClosure = Proof and Proof.closure
local Intent = {}
PZSurvivorToolkit.ActionQueueTidyIntent = Intent
local states, watching = setmetatable({}, {__mode='k'}), setmetatable({}, {__mode='k'})
local transfers=setmetatable({}, {__mode='k'})
local mergeOriginal,mergeObserver
local mergeListeners={}
local transferEvent
local scope, guard, wrappedUI, installed
local serial=0
local function pack(...) return {n=select('#',...),...} end
local function identity(item) return item and {id=item:getID(),kind=item:getFullType()} or false end
local function same(item, ref) return item and ref and item:getID()==ref.id and item:getFullType()==ref.kind or not item and not ref end
local function resolve(player, ref)
    if not ref then return false end
    local item=player:getInventory():getItemById(ref.id)
    if same(item,ref) and item:getContainer()==player:getInventory() then return item end
end
local function clear(player)
    local value=states[player]
    if value then for action in pairs(value.pending) do watching[action]=nil end end
    for action in pairs(transfers) do if action.character==player then transfers[action]=nil end end
    states[player]=nil
end
local function state(player)
    local queue=ISTimedActionQueue.getTimedActionQueue(player)
    local value=states[player]
    if not value or value.queue~=queue then clear(player);value={queue=queue,pending={},pickups={},returnIntents={},hands={},worn={},attached={},activation={},versions={},idle=0};states[player]=value end
    return value
end
-- A committed return waiver is deliberate inventory intent. Its publication
-- comes from Settlement's private earned-loan proof, never from a copied flag.
function Intent.canKeepReturn(action)
    if not guard then return P4TidyUpMeister == nil end
    local player=action and action.character
    local queue=player and ISTimedActionQueue.queues[player]
    return player and not player:isDead() and getSpecificPlayer(player:getPlayerNum())==player
        and queue and queue.character==player and getmetatable(action)==ISInventoryTransferAction
        and action.srcContainer==player:getInventory() and action.destContainer~=action.srcContainer
        and guard() and guard(action) or false
end
function Intent.keepReturn(action,handle)
    if not guard then return P4TidyUpMeister == nil end
    if not Intent.canKeepReturn(action) or type(Settlement.returnRetention)~='function' then return false end
    local retained=Settlement.returnRetention(handle,action)
    local player=action.character
    local queue=ISTimedActionQueue.queues[player]
    local inventory=player:getInventory()
    if not retained or retained.character~=player or retained.queue~=queue
        or retained.generation~=(queue.toolkitOperationGeneration or 0)
        or retained.source~=inventory or retained.source~=action.srcContainer
        or retained.destination~=action.destContainer or retained.item~=action.item
        or not instanceof(retained.item,'InventoryItem') or retained.item:getContainer()~=inventory
        or inventory:getItemById(retained.item:getID())~=retained.item then return false end
    local owner=retained.owner
    if owner and (type(owner.id)~='number' or type(owner.fullType)~='string') then return false end
    local value=state(player)
    value.returnIntents[retained.item:getID()]={item=identity(retained.item),source=inventory,destination=retained.destination,
        generation=retained.generation,owner=owner and {id=owner.id,kind=owner.fullType} or nil}
    return true
end
local function keptReturn(player,value,action)
    local retained=action.item and value.returnIntents[action.item:getID()]
    if not retained or retained.generation~=(value.queue.toolkitOperationGeneration or 0)
        or retained.source~=player:getInventory() or action.srcContainer~=retained.source
        or resolve(player,retained.item)~=action.item then return false end
    local groups=action.queueList
    if type(groups)~='table' or #groups~=1 or type(groups[1].items)~='table'
        or #groups[1].items~=1 then return false end
    local member=groups[1].items[1]
    local adapters=PZSurvivorToolkit.ActionQueueItemEditAdapters
    if member~=action.item and not (adapters and type(adapters.matchesTransferMember)=='function'
        and adapters.matchesTransferMember(action,member)) then return false end
    local destination=retained.destination
    if retained.owner then
        local holder=player:getInventory():getItemById(retained.owner.id)
        if not same(holder,retained.owner) then return false end
        if type(holder.getInventory)=='function' then destination=holder:getInventory()
        elseif type(holder.getItemContainer)=='function' then destination=holder:getItemContainer()
        else return false end
        local policy=PZSurvivorToolkit.ActionQueuePolicy
        if policy and type(policy.isCarriedContainer)=='function' then
            if not policy.isCarriedContainer(destination,player) then return false end
        elseif holder:getContainer()~=player:getInventory() then return false end
    end
    return action.destContainer==destination
end
local blockedReturnBinding
local function blockedReturnMethods()
    local checker,hint=Settlement.returnRestorationBlocked,Settlement.hasActiveBlockedReturn
    if PZSurvivorToolkit.ActionQueueSettlement~=Settlement or not Proof or Proof.closure~=proofClosure
        or type(proofClosure)~='function'or type(checker)~='function' or type(hint)~='function'
        or not proofClosure(checker,'ActionQueueSettlement.lua')or not proofClosure(hint,'ActionQueueSettlement.lua')then return end
    if not blockedReturnBinding then blockedReturnBinding={checker=checker,hint=hint}end
    if checker==blockedReturnBinding.checker and hint==blockedReturnBinding.hint then return blockedReturnBinding end
end
local function blockedReturn(action)
    local methods=blockedReturnMethods()
    if not methods then return false end
    local ok,result=pcall(methods.checker,action)
    return ok and result==true
end
local function mayHaveBlockedReturn(player)
    if not PZSurvivorToolkit.Settings.actionQueue()then return false end
    local methods=blockedReturnMethods()
    if not methods then return false end
    local ok,present=pcall(methods.hint,player)
    -- Active current-generation debt only enables read-only buffering. Every
    -- suppressed action still needs the separate exact episode proof.
    return ok and present==true
end

local function consumeKeptReturns(value,consumed)
    local count=0
    for id in pairs(consumed)do
        if value.returnIntents[id]then value.returnIntents[id]=nil;count=count+1 end
    end
    return count
end
local function confirm(record)
    local action,player=record.executor or record.action,record.player
    if not record.accepted or not record.finished or not record.effect or not guard(action) then return end
    local item=resolve(player,record.item)
    if not item or not Settlement.confirmEffect(record.proof, true) then return end
    local value=state(player)
    local function remember(group,slot,ref)
        local key=group..':'..tostring(slot)
        if (value.versions[key] or 0)<=record.serial then value[group][slot]=ref;value.versions[key]=record.serial end
    end
    local function hand(slot,ref) remember('hands',slot,ref) end
    if record.kind=='grab' then value.pickups[record.item.id]=record.item
    elseif record.kind=='equip' then
        if action.twoHands then
            hand('primary',record.item);hand('secondary',record.item)
        else
            local slot=action.primary and 'primary' or 'secondary'
            hand(slot,record.item)
            if record.clearedOpposite then hand(action.primary and 'secondary' or 'primary',false) end
        end
    elseif record.kind=='unequip' then
        for slot,ref in pairs(record.beforeHands) do if same(item,ref) then hand(slot,false) end end
        if record.beforeWorn then remember('worn',record.location,false) end
        value.pickups[record.item.id]=record.item
    elseif record.kind=='wear' then
        local location=item:IsClothing() and item:getBodyLocation() or item:canBeEquipped()
        remember('worn',location,record.item)
    elseif record.kind=='attach' then
        remember('attached',action.slot,record.item)
    end
    if record.kind=='equip' and item:canBeActivated() then value.activation[record.item.id]={item=record.item,activated=record.activated} end
    value.pending[record.action],watching[record.action]=nil,nil
end
local function captureBefore(action,record)
    local primary,secondary=action.character:getPrimaryHandItem(),action.character:getSecondaryHandItem()
    record.oppositeBefore=identity(primary)
    if action.primary then record.oppositeBefore=identity(secondary) end
    if record.kind=='unequip' then
        record.beforeHands={primary=identity(primary),secondary=identity(secondary)}
        local item=action.item
        record.location=item:IsClothing() and item:getBodyLocation() or item:canBeEquipped()
        record.beforeWorn=record.location and same(action.character:getWornItem(record.location),record.item)
    end
end
-- Read-only integration status for diagnostics; this grants no queue rights.
function Intent.status(action)
    if not guard then return false,'not_installed' end
    return guard(action)
end
function Intent.start(action)
    local record=watching[action]
    if record and guard(action) then captureBefore(action,record);record.started=true end
end
local function groupItems(action)
    local group=action.queueList and action.queueList[1]
    local refs={}
    for _,item in ipairs(group and group.items or {action.item}) do refs[#refs+1]=identity(item) end
    return refs
end
local function transfer(action)
    local batch=transfers[action]
    if not batch then batch={records={}};transfers[action]=batch end
    return batch
end
-- Observe the native merge before table.wipe destroys the child action's identity.
function Intent.observeTransfers(onMerged, canObserve, callbacks)
    if type(onMerged)=='function' then
        local present=false
        for _,listener in ipairs(mergeListeners) do if listener.callback==onMerged then present=true;break end end
        if not present then mergeListeners[#mergeListeners+1]={callback=onMerged,canObserve=canObserve,events=callbacks} end
    end
    if mergeObserver or type(ISInventoryTransferAction.checkQueueList)~='function' then return end
    mergeOriginal=ISInventoryTransferAction.checkQueueList
    mergeObserver=function(action,...)
        local original = guard and guard(action)
        local observation = original
        if not observation then
            for _,listener in ipairs(mergeListeners) do
                if not listener.failed and type(listener.canObserve)=='function' then
                    local ok,accepted=pcall(listener.canObserve,action)
                    if not ok then listener.failed=true
                    elseif accepted==true then observation=true end
                end
            end
        end
        if not observation then return mergeOriginal(action,...) end
        local queue=ISTimedActionQueue.getTimedActionQueue(action.character)
        local candidates={}
        for _,child in ipairs(queue.queue) do
            local record=watching[child]
            if original and child~=action and record and record.kind=='grab' and guard(child)
                and child.srcContainer==action.srcContainer and child.destContainer==action.destContainer then
                candidates[#candidates+1]=record
            end
        end
        transferEvent('merging',action)
        local result=pack(mergeOriginal(action,...))
        -- Observation cannot abort native perform and cause the same transfer to
        -- be retried. Quarantine a failed listener; never revive its proof here.
        for _,listener in ipairs(mergeListeners) do
            if not listener.failed then listener.failed=not pcall(listener.callback,action) end
        end
        for _,record in ipairs(candidates) do
            if queue:indexOf(record.action)==-1 then
                for _,group in ipairs(action.queueList or {}) do for _,item in ipairs(group.items) do
                    if same(item,record.item) then
                        record.executor=action;record.enqueued=true
                        transfer(action).records[record.item.id]=record
                    end
                end end
            end
        end
        local batch=transfers[action]
        -- MP calls this again AFTER consuming its group; retain that group's receipt.
        if original and batch and batch.attempted and not isClient() then batch.attempted=groupItems(action) end
        return unpack(result,1,result.n)
    end
    ISInventoryTransferAction.checkQueueList=mergeObserver
end
function Intent.isQueueObserver(previous,replacement)
    return previous==mergeOriginal and replacement==mergeObserver and replacement~=nil
end
transferEvent=function(event,action,...)
    local observed=false
    for _,listener in ipairs(mergeListeners) do
        local callback=listener.events and listener.events[event]
        if not listener.failed and type(callback)=='function' then
            local ok,result=pcall(callback,action,...)
            if not ok then listener.failed=true
            elseif result==true then observed=true end
        end
    end
    return observed
end
function Intent.begin(action,phase)
    local observing=phase=='perform' and transferEvent('begin',action) or false
    local record=watching[action]
    if phase=='perform' and getmetatable(action)==ISInventoryTransferAction and guard and guard(action)
        and (record or states[action.character] or transfers[action]) then
        local batch=transfer(action)
        if record and record.kind=='grab' then batch.records[record.item.id]=record end
        batch.attempted=groupItems(action)
        for _,ref in ipairs(batch.attempted) do
            local member=batch.records[ref.id]
            if member and not member.proof then member.proof=Settlement.captureEffect(action) end
        end
        return true
    end
    if not record then return observing end
    if phase=='perform' and not record.proof then record.proof=Settlement.captureEffect(action) end
    if (phase=='complete' or isClient() and phase=='perform') and not (isClient() and record.started) then
        captureBefore(action,record)
    end
    return true
end
local function observeEffect(record)
    local action,player=record.executor or record.action,record.player
    if record.kind=='equip' then
        record.clearedOpposite=record.oppositeBefore and not (action.primary and player:getSecondaryHandItem() or not action.primary and player:getPrimaryHandItem())
    end
    local item=resolve(player,record.item)
    if item then
        if record.kind=='grab' then record.effect=true
        elseif record.kind=='equip' then
            record.effect=action.twoHands and same(player:getPrimaryHandItem(),record.item) and same(player:getSecondaryHandItem(),record.item)
                or not action.twoHands and same(action.primary and player:getPrimaryHandItem() or player:getSecondaryHandItem(),record.item)
        elseif record.kind=='unequip' then
            record.effect=record.beforeHands and not same(player:getPrimaryHandItem(),record.item) and not same(player:getSecondaryHandItem(),record.item)
                and (not record.beforeWorn or not same(player:getWornItem(record.location),record.item))
        elseif record.kind=='wear' then
            local location=item:IsClothing() and item:getBodyLocation() or item:canBeEquipped()
            record.effect=same(player:getWornItem(location),record.item)
        elseif record.kind=='attach' then record.effect=same(player:getAttachedItems():getItem(action.slot),record.item) end
    end
    if record.kind=='equip' and item and item:canBeActivated() then record.activated=item:isActivated() end
end
function Intent.finish(action,phase,succeeded)
    if phase=='perform' then transferEvent('finish',action,succeeded) end
    -- Inventory transfers apply their effects in perform(), including in SP.
    if phase~='complete' and not (phase=='perform' and (isClient() or getmetatable(action)==ISInventoryTransferAction)) then return end
    local player=action.character
    local batch=transfers[action]
    if phase=='perform' and batch then
        local valid=succeeded and guard(action)
        local value=states[player]
        for _,ref in ipairs(batch.attempted or {}) do
            local record=batch.records[ref.id]
            if record and record.item.kind==ref.kind then
                record.proof=record.proof or Settlement.captureEffect(action)
                record.finished=true;record.effect=valid and resolve(player,ref)~=nil
                confirm(record)
                batch.records[ref.id]=nil
                if not valid or Settlement.effectState(record.proof, record.effect)=="unavailable" then
                    watching[record.action]=nil
                    if value then value.pending[record.action]=nil end
                end
            end
            if valid and value and action.srcContainer==player:getInventory() and action.destContainer~=action.srcContainer
                and not resolve(player,ref) then
                value.pickups[ref.id]=nil
                local retained=value.returnIntents[ref.id]
                if retained and retained.item.kind==ref.kind then value.returnIntents[ref.id]=nil end
                -- An already-finished intent belongs to this borrowing episode.
                -- A late receipt cannot protect a later automatic pickup of it.
                for pending,previous in pairs(value.pending) do
                    if previous.finished and previous.item.id==ref.id and previous.item.kind==ref.kind then
                        value.pending[pending],watching[pending]=nil,nil
                    end
                end
                for _,group in ipairs({'hands','worn','attached'}) do
                    for slot,wanted in pairs(value[group]) do if wanted and wanted.id==ref.id and wanted.kind==ref.kind then value[group][slot]=nil end end
                end
            end
        end
        batch.attempted=nil
        for id,record in pairs(batch.records) do
            local queued=false
            for _,group in ipairs(action.queueList or {}) do for _,item in ipairs(group.items) do
                if same(item,record.item) then queued=true end
            end end
            if not queued then
                batch.records[id],watching[record.action]=nil,nil
                if value then value.pending[record.action]=nil end
            end
        end
        return
    end
    local record=watching[action]
    if not record then return end
    record.finished=true
    record.proof=record.proof or Settlement.captureEffect(action)
    if succeeded then observeEffect(record) else record.failed=true end
    confirm(record)
end
local function capture(action)
    if not scope or action.character~=scope.player or not guard(action) or watching[action]
        or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc then return end
    local class=getmetatable(action)
    if scope.kind=='grab' then
        if class~=ISInventoryTransferAction or action.destContainer~=action.character:getInventory() then return end
    elseif class~=({equip=ISEquipWeaponAction,unequip=ISUnequipAction,wear=ISWearClothing,attach=ISAttachItemHotbar})[scope.kind] then return end
    if not instanceof(action.item,'InventoryItem') then return end
    serial=serial+1
    local record={action=action,player=action.character,item=identity(action.item),kind=scope.kind,serial=serial}
    watching[action]=record;scope.records[#scope.records+1]=record
end
local function wrap(owner,name,kind,hotbar)
    local callback=owner and owner[name]
    if type(callback)~='function' then return end
    local replacement
    replacement=function(...)
        local args=pack(...)
        if not guard() or owner[name]~=replacement and not (wrappedUI and wrappedUI(owner,name)) or hotbar and not args[6] then return callback(...) end
        local previous=scope
        scope={kind=kind,player=hotbar and args[1].chr or getSpecificPlayer(args[2]),records={}}
        local current=scope
        local result=pack(pcall(callback,...));scope=previous
        for i,record in ipairs(current.records) do
            if result[1] and record.enqueued and (kind~='equip' or i==#current.records) then
                local action=record.action;record.accepted=true
                state(record.player).pending[action]=record
                if record.finished then confirm(record) end
            else watching[record.action]=nil end
        end
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end
    owner[name]=replacement
end
function Intent.install(valid,approvedWrapper)
    if installed then return end
    installed=true
    wrappedUI=approvedWrapper
    local helpers={}
    for _,entry in ipairs({{ISInventoryPaneContextMenu,'equipWeapon'},{ISInventoryPaneContextMenu,'transferIfNeeded'},{ISInventoryPaneContextMenu,'unequipItem'},
        {ISInventoryPane,'getActualItems'},{ISInventoryTransferUtil,'newInventoryTransferAction'}}) do
        if entry[1] then helpers[#helpers+1]={owner=entry[1],name=entry[2],callback=entry[1][entry[2]]} end
    end
    guard=function(action)
        for _,entry in ipairs(helpers) do if entry.owner[entry.name]~=entry.callback then return false,'helper_changed',entry.name end end
        return valid(action)
    end
    for _,name in ipairs({'OnPrimaryWeapon','OnSecondWeapon','OnTwoHandsEquip'}) do wrap(ISInventoryPaneContextMenu,name,'equip') end
    for _,name in ipairs({'onGrabItems','onGrabOneItems','onGrabHalfItems'}) do wrap(ISInventoryPaneContextMenu,name,'grab') end
    wrap(ISInventoryPaneContextMenu,'onWearItems','wear')
    wrap(ISInventoryPaneContextMenu,'onUnEquip','unequip')
    wrap(ISHotbar,'attachItem','attach',true)
    local function enqueue(action,callback,...)
        capture(action)
        local results=pack(callback(...))
        if results[2] and results[2]~=action then capture(results[2]) end
        for _,candidate in ipairs({action,results[2]}) do
            local record=watching[candidate]
            if record then
                local queue=ISTimedActionQueue.getTimedActionQueue(record.player)
                record.enqueued=record.enqueued or queue:indexOf(candidate)~=-1 or record.finished
            end
        end
        return unpack(results,1,results.n)
    end
    local add=ISTimedActionQueue.add
    ISTimedActionQueue.add=function(action) return enqueue(action,add,action) end
    local addAfter=ISTimedActionQueue.addAfter
    ISTimedActionQueue.addAfter=function(previous,action) return enqueue(action,addAfter,previous,action) end
    local addToQueue=ISTimedActionQueue.addToQueue
    ISTimedActionQueue.addToQueue=function(queue,action) return enqueue(action,addToQueue,queue,action) end
    if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function() states=setmetatable({}, {__mode='k'});watching=setmetatable({}, {__mode='k'});transfers=setmetatable({}, {__mode='k'}) end) end
end
function Intent.update(player,callback,...)
    local activeBlocked=mayHaveBlockedReturn(player)
    local value=states[player]
    if not value then
        if not activeBlocked then return callback(...)end
        value=state(player)
    end
    if player:isDead() or ISTimedActionQueue.queues[player]~=value.queue or not guard() then
        clear(player);return callback(...)
    end
    local waiting=false
    for action,record in pairs(value.pending) do
        local executor=record.executor or action
        if record.finished and not record.failed and guard(executor)
            and (not record.effect or resolve(player,record.item)) then
            -- Only marked network work can wait for late replication. A native
            -- no-effect callback cannot acquire intent from a later unrelated item.
            local status=Settlement.effectState(record.proof, record.effect==true)
            if status=="waiting" and not record.effect then
                observeEffect(record)
                status=Settlement.effectState(record.proof, record.effect==true)
            end
            if status=="completed" then confirm(record)
            elseif status=="waiting" then waiting=true
            else value.pending[action],watching[action]=nil,nil end
        elseif record.finished or value.queue:indexOf(executor)==-1 then
            value.pending[action],watching[action]=nil,nil
        end
    end
    for action,batch in pairs(transfers) do
        if action.character==player and value.queue:indexOf(action)==-1 then transfers[action]=nil end
    end
    for id,ref in pairs(value.pickups) do if not resolve(player,ref) then value.pickups[id]=nil end end
    local keptPending=0
    for id,retained in pairs(value.returnIntents) do
        if retained.generation~=(value.queue.toolkitOperationGeneration or 0)
            or retained.source~=player:getInventory() or not resolve(player,retained.item) then value.returnIntents[id]=nil
        else keptPending=keptPending+1 end
    end
    local empty=#value.queue.queue==0 and not player:hasTimedActions()
    -- P4 may construct restoration on its first idle callback. Hold that idle
    -- boundary only; active native updates and action timers continue unchanged.
    if empty and waiting then return end
    value.idle=empty and value.idle+1 or 0
    local phase=not value.restoring and value.idle>=2
    -- A later failed loan can arrive before the previous Intent state retires.
    -- Observe its first idle callback even when explicit restoration is already
    -- complete, without applying the old hand/clothing overlays again.
    local fenceOnly=empty and (activeBlocked or keptPending>0) and not phase
    if not phase and not fenceOnly then
        local results=pack(callback(...))
        if value.restoring and value.idle>=2 and #value.queue.queue==0 then clear(player) end
        return unpack(results,1,results.n)
    end
    -- P4 constructs its whole restore batch synchronously; keep its order and native executor.
    local add,actions=ISTimedActionQueue.add,{}
    ISTimedActionQueue.add=function(action) actions[#actions+1]=action;return value.queue end
    local results=pack(pcall(callback,...));ISTimedActionQueue.add=add
    if not results[1] then error(results[2],0) end
    -- Reviewed P4 queueRestore retires its session before this synchronous
    -- batch; later OnPlayerUpdate calls only drain its restoring marker. Consume
    -- Keep after classifying a matching batch, never from an idle count, so a
    -- duplicate entry cannot escape and no-output callbacks retain the intent.
    local retainedReturns,retainedFloors,consumedKept={},{},{}
    for _,action in ipairs(actions)do
        if action.character==player and getmetatable(action)==ISInventoryTransferAction and guard(action)then
            local kept=keptReturn(player,value,action)
            if kept or activeBlocked and blockedReturn(action)then
                retainedReturns[action]=true
                if kept then consumedKept[action.item:getID()]=true end
                if type(action.destContainer.getType)=='function'and action.destContainer:getType()=='floor'then
                    retainedFloors[action.item:getID()]=action.item
                end
            end
        end
    end
    if fenceOnly then
        for _,action in ipairs(actions)do
            if not retainedReturns[action]and not (action.character==player and getmetatable(action)==P4RestoreFloorAction
                and action.item and guard(action)and retainedFloors[action.item:getID()]==action.item)then add(action)end
        end
        keptPending=keptPending-consumeKeptReturns(value,consumedKept)
        if value.restoring and value.idle>=2 and #value.queue.queue==0 and keptPending==0 then clear(player)end
        return unpack(results,2,results.n)
    end
    local primary,secondary=player:getPrimaryHandItem(),player:getSecondaryHandItem()
    local hands={primary=identity(primary),secondary=identity(secondary)}
    local override=false
    for slot,ref in pairs(value.hands) do
        if ref==false or resolve(player,ref) then override=true else value.hands={};override=false;break end
    end
    if override then
        for _,action in ipairs(actions) do
            if action.character==player and guard(action) then
                if getmetatable(action)==ISEquipWeaponAction then
                    if action.twoHands then hands.primary,hands.secondary=identity(action.item),identity(action.item)
                    else hands[action.primary and 'primary' or 'secondary']=identity(action.item) end
                elseif getmetatable(action)==ISUnequipAction then
                    for slot,ref in pairs(hands) do if same(action.item,ref) then hands[slot]=false end end
                end
            end
        end
        for slot,ref in pairs(value.hands) do hands[slot]=ref end
        for _,ref in pairs(hands) do if ref and not resolve(player,ref) then override=false;break end end
    end
    if not override then value.hands={} end
    local function keep(item)
        local ref=identity(item)
        if not ref or not resolve(player,ref) then return false end
        if same(item,value.pickups[ref.id]) then return true end
        for _,wanted in pairs(value.hands) do if same(item,wanted) then return true end end
        for _,wanted in pairs(value.worn) do if same(item,wanted) then return true end end
        for slot,wanted in pairs(value.attached) do if same(item,wanted) and same(player:getAttachedItems():getItem(slot),wanted) then return true end end
        return false
    end
    local worn={}
    for location,ref in pairs(value.worn) do if ref==false or resolve(player,ref) then worn[location]=ref end end
    local function wornLocation(item)
        if not item then return end
        if item.IsClothing and item:IsClothing() then return item:getBodyLocation() end
        return item.canBeEquipped and item:canBeEquipped()
    end
    local buffered={}
    for _,action in ipairs(actions) do
        local class=getmetatable(action)
        if action.character~=player or not guard(action) then buffered[#buffered+1]=action
        elseif retainedReturns[action] or class==P4RestoreFloorAction and action.item
            and retainedFloors[action.item:getID()]==action.item then
            -- A committed Keep or private undecided failed episode fences only
            -- this exact return and its paired floor placement; no retry is run.
        elseif override and (class==ISEquipWeaponAction or class==ISUnequipAction
            and (same(action.item,identity(primary)) or same(action.item,identity(secondary)))) then
            -- Rebuild the validated hand group with only the explicit slots overlaid.
        elseif (class==ISWearClothing or class==ISUnequipAction) and worn[wornLocation(action.item)]~=nil then
            -- Explicit clothing replaces P4's older snapshot at that location only.
        elseif (class==ISInventoryTransferAction and action.srcContainer==player:getInventory() or class==P4RestoreFloorAction) and keep(action.item) then
            -- The paired floor relocation must not survive a suppressed return.
        else buffered[#buffered+1]=action end
    end
    if override then
        for slot,ref in pairs(value.hands) do hands[slot]=ref end
        local wantedPrimary,wantedSecondary=resolve(player,hands.primary),resolve(player,hands.secondary)
        if (not hands.primary or wantedPrimary) and (not hands.secondary or wantedSecondary) then
            if wantedPrimary and wantedPrimary==wantedSecondary then
                if not same(primary,hands.primary) or not same(secondary,hands.secondary) then add(ISEquipWeaponAction:new(player,wantedPrimary,50,true,true)) end
            else
                for _,slot in ipairs({'primary','secondary'}) do
                    local actual,wanted=primary,wantedPrimary
                    if slot=='secondary' then actual,wanted=secondary,wantedSecondary end
                    if not same(actual,hands[slot]) then
                        if wanted then add(ISEquipWeaponAction:new(player,wanted,50,slot=='primary',false))
                        elseif actual then add(ISUnequipAction:new(player,actual,50)) end
                    end
                end
            end
        end
    end
    for location,ref in pairs(worn) do
        local actual=player:getWornItem(location)
        if not same(actual,ref) then
            if ref then add(ISWearClothing:new(player,resolve(player,ref),50))
            elseif actual then add(ISUnequipAction:new(player,actual,50)) end
        end
    end
    for _,entry in pairs(value.activation) do
        local item=resolve(player,entry.item)
        if override and item and (same(item,hands.primary) or same(item,hands.secondary)) and item:isActivated()~=entry.activated then
            add(P4RestoreAction:new(player,item,entry.activated))
        end
    end
    for _,action in ipairs(buffered) do
        local activation=action.item and value.activation[action.item:getID()]
        if not (override and getmetatable(action)==P4RestoreAction and guard(action)
            and (activation and same(action.item,activation.item) or not same(action.item,hands.primary) and not same(action.item,hands.secondary))) then add(action) end
    end
    consumeKeptReturns(value,consumedKept)
    value.restoring,value.idle=true,0
    return unpack(results,2,results.n)
end
return Intent
