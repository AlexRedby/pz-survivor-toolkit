require "Hotbar/ISHotbar"
local Intent = {}
PZSurvivorToolkit.ActionQueueTidyIntent = Intent
local states, watching = setmetatable({}, {__mode='k'}), setmetatable({}, {__mode='k'})
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
    states[player]=nil
end
local function state(player)
    local queue=ISTimedActionQueue.getTimedActionQueue(player)
    local value=states[player]
    if not value or value.queue~=queue then clear(player);value={queue=queue,pending={},pickups={},hands={},worn={},attached={},activation={},versions={},idle=0};states[player]=value end
    return value
end
local function confirm(record)
    local action,player=record.action,record.action.character
    if not record.accepted or not record.effect or not guard(action) then return end
    local item=resolve(player,record.item)
    if not item then return end
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
    value.pending[action],watching[action]=nil,nil
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
function Intent.start(action)
    local record=watching[action]
    if record and guard(action) then captureBefore(action,record);record.started=true end
end
function Intent.begin(action,phase)
    local record=watching[action]
    if not record then
        local value=action and states[action.character]
        if not value or getmetatable(action)~=ISInventoryTransferAction or not guard(action) then return false end
        return action.srcContainer==action.character:getInventory() and action.destContainer~=action.srcContainer
    end
    if (phase=='complete' or isClient() and phase=='perform') and not (isClient() and record.started) then
        captureBefore(action,record)
    end
    return true
end
function Intent.finish(action,phase,succeeded)
    -- Inventory transfers apply their effects in perform(), including in SP.
    if phase~='complete' and not (phase=='perform' and (isClient() or getmetatable(action)==ISInventoryTransferAction)) then return end
    local record=watching[action]
    local player=action.character
    if not record then
        local value=states[player]
        if value and succeeded and getmetatable(action)==ISInventoryTransferAction and guard(action)
            and action.srcContainer==player:getInventory() and action.destContainer~=action.srcContainer
            and not resolve(player,identity(action.item)) then
            local ref=identity(action.item)
            value.pickups[ref.id]=nil
            for _,group in ipairs({'hands','worn','attached'}) do
                for slot,wanted in pairs(value[group]) do if same(action.item,wanted) then value[group][slot]=nil end end
            end
        end
        return
    end
    record.finished=true
    if record.kind=='equip' then
        record.clearedOpposite=record.oppositeBefore and not (action.primary and player:getSecondaryHandItem() or not action.primary and player:getPrimaryHandItem())
    end
    local item=succeeded and resolve(player,record.item)
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
    local record={action=action,item=identity(action.item),kind=scope.kind,serial=serial}
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
                state(action.character).pending[action]=record
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
        for _,entry in ipairs(helpers) do if entry.owner[entry.name]~=entry.callback then return false end end
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
                local queue=ISTimedActionQueue.getTimedActionQueue(candidate.character)
                record.enqueued=queue:indexOf(candidate)~=-1 or record.finished
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
    if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function() states=setmetatable({}, {__mode='k'});watching=setmetatable({}, {__mode='k'}) end) end
end
function Intent.update(player,callback,...)
    local value=states[player]
    if not value then return callback(...) end
    if player:isDead() or ISTimedActionQueue.queues[player]~=value.queue or not guard() then
        clear(player);return callback(...)
    end
    for action,record in pairs(value.pending) do
        if value.queue:indexOf(action)==-1 then
            value.pending[action],watching[action]=nil,nil
        end
    end
    for id,ref in pairs(value.pickups) do if not resolve(player,ref) then value.pickups[id]=nil end end
    local empty=#value.queue.queue==0 and not player:hasTimedActions()
    value.idle=empty and value.idle+1 or 0
    local phase=not value.restoring and value.idle>=2
    if not phase then
        local results=pack(callback(...))
        if value.restoring and value.idle>=2 and #value.queue.queue==0 then clear(player) end
        return unpack(results,1,results.n)
    end
    -- P4 constructs its whole restore batch synchronously; keep its order and native executor.
    local add,actions=ISTimedActionQueue.add,{}
    ISTimedActionQueue.add=function(action) actions[#actions+1]=action;return value.queue end
    local results=pack(pcall(callback,...));ISTimedActionQueue.add=add
    if not results[1] then error(results[2],0) end
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
    value.restoring,value.idle=true,0
    return unpack(results,2,results.n)
end
return Intent
