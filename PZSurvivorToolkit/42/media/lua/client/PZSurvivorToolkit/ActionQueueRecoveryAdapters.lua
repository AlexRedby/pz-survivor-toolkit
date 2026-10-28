-- Recovery stores constructor intent, never an executable canceled action or its token.
require "TimedActions/ISReadABook"
require "TimedActions/WalkToTimedAction"
require "RadioCom/ISRadioAction"
require "TimedActions/ISDeviceMediaAction"
require "TimedActions/ISDeviceBatteryAction"
require "TimedActions/ISTrimBeard"
require "PZSurvivorToolkit/ActionQueueOperations"
local Proof = require "PZSurvivorToolkit/SourceProof"
local Toolkit = PZSurvivorToolkit
local Grooming = Toolkit.ActionQueueGrooming
local recoverTrim = Grooming and Grooming.canRecoverTrim
local Recovery = {}
Toolkit.ActionQueueRecoveryAdapters = Recovery
local pins = {}
local enqueueRead,plainRecord,copy
local base=ISBaseTimedAction
local lifecycle = {"new", "begin", "create", "adjustMaxTime", "isValid", "isValidStart", "waitToStart", "start", "update",
    "stop", "perform", "complete", "getDuration", "serverStart", "serverStop", "animEvent", "forceComplete", "forceStop",
    "forceCancel", "invoke", "interruptWaitToStart"}
local own = {
    read = {"isValid", "isUsingTimeout", "update", "doHaloText", "checkMultiplier", "checkLevel", "start", "stop", "perform",
        "startLoadingPrintMediaTextures", "displayPrintMedia", "revealPrintMediaLocationsOnMap", "complete", "animEvent",
        "isBook", "serverStart", "getDuration", "new"},
    walk = {"isValid", "update", "start", "stop", "perform", "setOnComplete", "new"},
}
local files = {read = "ISReadABook.lua", walk = "WalkToTimedAction.lua"}
local classes = {read = ISReadABook, walk = ISWalkToTimedAction}
local modes = {ToggleOnOff=true, SetVolume=true, SetChannel=true, MuteVolume=true, UnMuteVolume=true,
    MuteMicrophone=true, TogglePlayMedia=true}
local function finite(value) return type(value)=="number" and value==value and value>-math.huge and value<math.huge end
local function integer(value) return finite(value) and value%1==0 end
local function pinned(path, value, mod)
    local key = (mod or "")..":"..path
    if pins[key] == nil then pins[key] = Proof.matches(path,value,mod,true) end
    return pins[key]
end
local function clearCallbacks(action)
    return not action.onStartFunc and not action.onCompleteFunc and not action.onCancelFunc and not action.onFailFunc
        and not action.additionalTest and not action.additionalContext and not action.retriggerLastAction
        and not action._isAddingActions and not action.toolkitQueueLinked
end
local function nativeClass(action, kind)
    local class = classes[kind]
    if _G[kind=="read" and "ISReadABook" or "ISWalkToTimedAction"]~=class or getmetatable(action)~=class
        or action.Type~=class.Type or not clearCallbacks(action) or ISBaseTimedAction~=base
        or not pinned("media/lua/shared/TimedActions/ISBaseTimedAction.lua",3104185167)
        or not pinned(kind=="read" and "media/lua/shared/TimedActions/ISReadABook.lua"
            or "media/lua/client/TimedActions/WalkToTimedAction.lua",kind=="read" and 422821682 or 2037641019) then return false end
    local baseSeen={}
    for name,callback in pairs(base) do
        if type(callback)=="function" and name~="derive" then
            if baseSeen[callback] then return false end
            baseSeen[callback]=true
            if not Proof.closure(callback,"ISBaseTimedAction.lua") then
                local policy=Toolkit.ActionQueuePolicy
                if (name~="begin" and name~="stop") or not Proof.closure(callback,"ActionQueue.lua")
                    or not policy or not policy.matchesNative(action) then return false end
            end
        end
    end
    if not Proof.closure(base.new,"ISBaseTimedAction.lua") then return false end
    -- Kahlua rawget searches ancestors; only this own-field pass proves
    -- child ownership and distinguishes inherited lifecycle callbacks.
    local methods={}
    for name,callback in pairs(class) do if type(callback)=="function" then methods[name]=callback end end
    local seen = {}
    for _, name in ipairs(own[kind]) do
        local callback=methods[name]
        if type(callback)~="function" or seen[callback] or action[name]~=callback then return false end
        seen[callback]=true
        if not Proof.closure(callback,files[kind]) then
            local policy=Toolkit.ActionQueuePolicy
            local allowed=false
            if kind=="read" and name=="animEvent" and Proof.closure(callback,"MPFastForward_ReadFix.lua") then
                allowed=pinned("media/lua/server/MPFastForward_ReadFix.lua",598888215,"MPFastForward")
            elseif kind=="read" and name=="complete" and Proof.closure(callback,"CustomLightSwitch_ReadFix.lua") then
                -- This exact wrapper always delegates native completion; its
                -- additional recipe/sync/halo branch belongs only to this magazine.
                allowed=instanceof(action.item,"InventoryItem") and action.item:getFullType()~="Base.Mag_LightSwitch"
                    and pinned("media/lua/shared/TimedActions/CustomLightSwitch_ReadFix.lua",3025062156,"CustomLightSwitch")
            end
            if not allowed or not policy or not policy.matchesNative(action) then return false end
        end
    end
    for name,callback in pairs(methods) do
        if name~="derive" and not seen[callback] then return false end
    end
    for _,name in ipairs(lifecycle) do
        local callback=class[name]
        if action[name]~=callback then return false end
        if callback and not methods[name] and not Proof.closure(callback,"ISBaseTimedAction.lua") then
            local policy=Toolkit.ActionQueuePolicy
            if (name~="begin" and name~="stop") or not Proof.closure(callback,"ActionQueue.lua")
                or not policy or not policy.matchesNative(action) then return false end
        end
    end
    for name,callback in pairs(action) do if type(callback)=="function" and callback~=class[name] then return false end end
    return true
end
local function probe(kind, character, item)
    return setmetatable({Type=classes[kind].Type,character=character,item=item},classes[kind])
end
local function itemIntent(record,item)
    if not instanceof(item,"InventoryItem") or not integer(item:getID()) or type(item:getFullType())~="string"
        or not instanceof(item:getContainer(),"ItemContainer") then return false end
    record.itemId,record.itemType,record.container=item:getID(),item:getFullType(),item:getContainer()
    return record.container:getItemById(record.itemId)==item and item:getContainer()==record.container
end
local function pageBook(item,character,active)
    if not instanceof(item,"InventoryItem") or not finite(item:getNumberOfPages()) or item:getNumberOfPages()<=0
        or item:getIsCraftingConsumed() or item:getFullType()=="Base.Mag_LightSwitch" then return false end
    local pages=character:getAlreadyReadPages(item:getFullType())
    if not finite(pages) or pages<0 or pages>=item:getNumberOfPages() then return false end
    -- Only skill books have an audited continuously persisted active resume here.
    -- Generic literature may reveal maps or pay its effects at completion.
    return not active or SkillBook and SkillBook[item:getSkillTrained()]~=nil
end
local function target(record,device,data)
    if not (instanceof(device,"IsoTelevision") or instanceof(device,"IsoRadio")) or not instanceof(data,"DeviceData")
        or device:getObjectIndex()<0 or not device:getSquare() or device:getDeviceData()~=data
        or data:getParent()~=device or not data:isIsoDevice() or data:isVehicleDevice() then return false end
    record.device,record.data,record.square=device,data,device:getSquare()
    return true
end
local function liveTarget(record)
    local device,data=record.device,record.data
    return device and data and device:getSquare()==record.square and device:getObjectIndex()>=0
        and device:getDeviceData()==data and data:getParent()==device and data:isIsoDevice() and not data:isVehicleDevice()
        and record.square:getObjects():contains(device)
end
local function radioTrusted(action)
    local adapters=Toolkit.ActionQueueEditAdapters
    return adapters and adapters.radioCallbacksTrusted and adapters.radioCallbacksTrusted(action)
end
local function mediaTrusted(action)
    local media=Toolkit.ActionQueueMedia
    return media and media.isInstalled and media.isInstalled()
        and (action.isRemove and media.matchesEject(action) or not action.isRemove and media.matches(action))
end
local function transferTrusted(action)
    local adapters=Toolkit.ActionQueueItemEditAdapters
    return adapters and adapters.transfer and adapters.transfer(action)~=nil
end
local function trimTrusted(action)
    return Grooming and Toolkit.ActionQueueGrooming==Grooming and Grooming.canRecoverTrim==recoverTrim
        and type(recoverTrim)=="function" and Proof.closure(recoverTrim,"ActionQueueGrooming.lua")
        and recoverTrim(action)==true
end
local function capture(action,active)
    if type(action)~="table" or not instanceof(action.character,"IsoPlayer") or not clearCallbacks(action) then return nil,"unsupported" end
    local record={version=1,character=action.character}
    if action.Type=="ISQueueActionsAction" and not active and not action.action then
        local operations=Toolkit.ActionQueueOperations
        local command=action.toolkitQueueCommand
        if operations and operations.isCommand(action) and command.callback==enqueueRead
            and plainRecord(command.snapshot,action.character) and command.snapshot.kind=="read" then return copy(command.snapshot) end
        local approach=Toolkit.ActionQueueApproach
        local intent=approach and approach.capture(action)
        if intent then record.kind,record.approach="approach",intent;return record end
        return nil,"unsupported"
    end
    if action.Type=="ISReadABook" then
        if not active and (action.action or action.started) then return nil,"active" end
        if not nativeClass(action,"read") or not itemIntent(record,action.item)
            or not pageBook(action.item,action.character,active) then return nil,"unsupported" end
        if action.ignoreHandsWounds~=true or action.forceProgressBar~=true or action.caloriesModifier~=0.5 then return nil,"unsupported" end
        record.kind,record.active="read",active==true
    else
        if active or action.action or action.started then return nil,"active" end
        if action.Type=="ISTrimBeard" then
            if not trimTrusted(action) or not itemIntent(record,action.item) then return nil,"unsupported" end
            record.kind,record.beardStyle,record.singleton="trim",action.beardStyle,true
        elseif action.Type=="ISWalkToTimedAction" then
            if not nativeClass(action,"walk") or not instanceof(action.location,"IsoGridSquare") or action.maxTime~=-1
                or action.stopOnWalk~=false or action.stopOnRun~=false or action.allowedWhileDraggingCorpses~=true then return nil,"unsupported" end
            record.kind,record.square="walk",action.location
            record.x,record.y,record.z=action.location:getX(),action.location:getY(),action.location:getZ()
        elseif action.Type=="ISRadioAction" then
            if not radioTrusted(action) or not modes[action.mode] or action.maxTime~=30
                or not target(record,action.device,action.deviceData) then return nil,"unsupported" end
            local mode,value=action.mode,action.secondaryItem
            if (mode=="SetVolume" or mode=="UnMuteVolume") and not finite(value)
                or mode=="SetChannel" and (not integer(value) or value < -2147483648 or value > 2147483647)
                or mode=="MuteMicrophone" and type(value)~="boolean" then return nil,"unsupported" end
            if mode=="ToggleOnOff" and (not instanceof(record.device,"IsoTelevision") or record.data:getIsBatteryPowered()~=false) then return nil,"unsupported" end
            record.kind,record.mode="radio",mode
            if mode=="SetVolume" or mode=="UnMuteVolume" or mode=="SetChannel" or mode=="MuteMicrophone" then record.value=value end
        elseif action.Type=="ISDeviceMediaAction" then
            if not mediaTrusted(action) or not target(record,action.deviceData:getParent(),action.deviceData)
                or not instanceof(record.device,"IsoTelevision") or action.parameter~=record.square
                or record.square:getDeviceData()~=record.data then return nil,"unsupported" end
            record.kind="media"
            record.remove=action.isRemove
            if record.remove then
                record.mediaIndex=record.data:hasMedia() and record.data:getMediaIndex() or false
                if record.mediaIndex~=false and (not integer(record.mediaIndex) or record.mediaIndex<0) then return nil,"unsupported" end
            else
                local tape=action.secondaryItem
                if not itemIntent(record,tape) or not tape:isRecordedMedia() or tape:getMediaType()~=1 then return nil,"unsupported" end
                record.mediaIndex=tape:getRecordedMediaIndex()
                if not integer(record.mediaIndex) or record.mediaIndex<0 then return nil,"unsupported" end
            end
        elseif action.Type=="ISInventoryTransferAction" then
            if not transferTrusted(action) or not itemIntent(record,action.item) or action.onCompleteFunc
                or action.srcContainer:getContainingItem() or action.destContainer:getContainingItem()
                or not finite(action.maxTime) or action.transactionId~=0 then return nil,"unsupported" end
            record.kind,record.source,record.destination="transfer",action.srcContainer,action.destContainer
            record.allowMissing=action.allowMissingItems
        else return nil,"unsupported" end
    end
    return record
end
function Recovery.capture(action,active)
    local ok,record,reason=pcall(capture,action,active==true)
    if ok then return record,reason end
    return nil,"unavailable"
end

local fields={version=true,character=true,kind=true,approach=true,itemId=true,itemType=true,container=true,active=true,
    device=true,data=true,square=true,x=true,y=true,z=true,mode=true,value=true,remove=true,mediaIndex=true,
    source=true,destination=true,allowMissing=true,beardStyle=true,singleton=true}
plainRecord=function(record,character)
    if type(record)~="table" or getmetatable(record) or record.version~=1 or record.character~=character then return false end
    for key in pairs(record) do if not fields[key] then return false end end
    return true
end
local function array(records)
    if type(records)~="table" or getmetatable(records) then return false end
    local count=0
    for key in pairs(records) do if not integer(key) or key<1 or key>#records then return false end;count=count+1 end
    return count==#records
end
local function localPlayer(character)
    return instanceof(character,"IsoPlayer") and getSpecificPlayer(character:getPlayerNum())==character
        and not character:isDead() and not character:isAsleep()
end
copy=function(record)
    local result={}
    for key,value in pairs(record) do result[key]=value end
    return result
end
-- Native reading construction calls getDuration(), which writes saved pages.
-- Keep that constructor at execution, after real preparation, rather than during planning.
enqueueRead=function(character,record)
    if not localPlayer(character) then return end
    local root=character:getInventory()
    local item=root:getItemById(record.itemId)
    if not item or item:getFullType()~=record.itemType or item:getContainer()~=root
        or not pageBook(item,character,record.active) or not nativeClass(probe("read",character,item),"read") then return end
    ISTimedActionQueue.add(ISReadABook:new(character,item))
end
-- Mirror getItemById's item-before-descendants traversal. The first recursive
-- match can hide a later direct child, so a flat direct-item map is insufficient.
-- Each projection owns its index; no inventory identity survives into Restore.
local function inventoryIndex(container,requested,remaining)
    local first,visiting={},{}
    local function visit(current)
        if visiting[current] then error("cyclic inventory") end
        visiting[current]=true
        local values=current:getItems()
        for index=0,values:size()-1 do
            local item=values:get(index)
            local id=item:getID()
            if requested[id] and first[id]==nil then
                first[id]=item;remaining=remaining-1
            end
            if remaining==0 then break end
            if instanceof(item,"InventoryContainer") then
                local nested=item:getItemContainer()
                if nested then visit(nested) end
            end
            -- Later duplicates cannot change any first match already found.
            if remaining==0 then break end
        end
        visiting[current]=nil
    end
    visit(container)
    return first
end
local function project(records,character,construct)
    if not array(records) or not localPlayer(character) then return nil,"unavailable" end
    local root=character:getInventory()
    if not instanceof(root,"ItemContainer") then return nil,"unavailable" end
    local containers,containerSet,items,locations,devices,loads,incoming={root},{[root]=true},{},{},{},{},{}
    local requested,requestedCount={},0
    local function container(value)
        if not instanceof(value,"ItemContainer") or not value:isExistYet() then return false end
        if containerSet[value] then return true end
        containerSet[value]=true
        containers[#containers+1]=value
        return true
    end
    for _,record in ipairs(records) do
        if not plainRecord(record,character) then return nil,"unavailable" end
        if record.itemId~=nil then
            if not integer(record.itemId) or type(record.itemType)~="string" or not container(record.container) then return nil,"unavailable" end
            if not requested[record.itemId] then
                requested[record.itemId]=true;requestedCount=requestedCount+1
            end
        end
        if record.kind=="transfer" and (not container(record.source) or not container(record.destination)) then return nil,"unavailable" end
    end
    -- Native MP pickup can replace an item object. Resolve each distinct ID once,
    -- requiring one direct-root witness among the captured endpoints/current inventory.
    if requestedCount>0 then
        for _,candidate in ipairs(containers) do
            for id,found in pairs(inventoryIndex(candidate,requested,requestedCount)) do
                if found:getContainer()==candidate then
                    if items[id] and items[id]~=found then return nil,"unavailable" end
                    items[id],locations[id]=found,candidate
                end
            end
        end
    end
    for _,record in ipairs(records) do
        if record.itemId~=nil then
            local item=items[record.itemId]
            if not item or item:getID()~=record.itemId or item:getFullType()~=record.itemType
                or item:getIsCraftingConsumed() then return nil,"unavailable" end
        end
    end
    local function deviceState(record)
        if not liveTarget(record) then return end
        local state=devices[record.device]
        if not state then
            local data=record.data
            local on,power,volume,channel,mic=data:getIsTurnedOn(),data:getPower(),data:getDeviceVolume(),data:getChannel(),data:getMicIsMuted()
            local hasMedia=data:hasMedia()
            if type(on)~="boolean" or not finite(power) or not finite(volume) or volume<0 or volume>1
                or not integer(channel) or type(mic)~="boolean" or type(hasMedia)~="boolean" then return end
            local media=hasMedia and data:getMediaIndex() or false
            if media~=false and (not integer(media) or media<0) then return end
            state={on=on,power=power,volume=volume,channel=channel,mic=mic,media=media}
            devices[record.device]=state
        end
        return state
    end
    local function fits(destination,item)
        local weights=Toolkit.ActionQueueWeights
        if not weights or not weights.factoryFree(item) or not weights.factoryFree(destination) then return false end
        local weight=weights.unequipped(item)
        if not finite(weight) or weight<0 then return false end
        if not loads[destination] then
            local load=weights.capacity(destination,character)
            local capacity=destination:getEffectiveCapacity(character)
            if not finite(load) or load<0 or not finite(capacity) or capacity<0
                or destination:getAcceptItemFunction()~=nil or destination:getOnlyAcceptCategory()~=nil then return false end
            loads[destination]={load,capacity}
        end
        incoming[destination]=(incoming[destination] or 0)+weight
        -- Never spend space from a merely planned return or media debit.
        return loads[destination][1]+incoming[destination]+0.01<=loads[destination][2]
    end
    local actions={}
    local unmodeledRootOutput=false
    for _,record in ipairs(records) do
        local action
        if record.kind=="trim" then
            local item=items[record.itemId]
            if record.singleton~=true or type(record.beardStyle)~="string" or locations[record.itemId]~=root then return nil,"unavailable" end
            local candidate=setmetatable({Type="ISTrimBeard",character=character,item=item,
                beardStyle=record.beardStyle,maxTime=300},ISTrimBeard)
            if not trimTrusted(candidate) then return nil,"unsupported" end
            if construct then
                action=ISTrimBeard:new(character,record.beardStyle,item)
                if not trimTrusted(action) then return nil,"unsupported" end
            end
        elseif record.kind=="read" then
            local item=items[record.itemId]
            if locations[record.itemId]~=root or not pageBook(item,character,record.active)
                or not nativeClass(probe("read",character,item),"read") then return nil,"unavailable" end
            if not pinned("media/lua/client/TimedActions/ISQueueActionsAction.lua",687313299)
                or not Proof.closure(ISQueueActionsAction.new,"ISQueueActionsAction.lua")
                or not Proof.closure(base.new,"ISBaseTimedAction.lua") then return nil,"unsupported" end
            local operations=Toolkit.ActionQueueOperations
            if not operations.commandConstructionTrusted() then return nil,"unsupported" end
            if construct then
                action=operations.command(character,enqueueRead,copy(record))
                if not operations.isCommand(action) then return nil,"unsupported" end
            end
        elseif record.kind=="approach" then
            local approach=Toolkit.ActionQueueApproach
            if not approach or not approach.validate(character,record.approach) then return nil,"unavailable"end
            if construct then
                action=approach.rebuild(character,record.approach)
                if not action then return nil,"unavailable"end
            end
        elseif record.kind=="walk" then
            local square=record.square
            if not instanceof(square,"IsoGridSquare") or not integer(record.x) or not integer(record.y) or not integer(record.z)
                or square:getX()~=record.x or square:getY()~=record.y or square:getZ()~=record.z
                or getCell():getGridSquare(record.x,record.y,record.z)~=square or character:getVehicle() then return nil,"unavailable" end
            if not nativeClass(probe("walk",character),"walk") then return nil,"unsupported" end
            if construct then
                action=ISWalkToTimedAction:new(character,square)
                if not nativeClass(action,"walk") then return nil,"unsupported" end
            end
        elseif record.kind=="radio" then
            local state=deviceState(record)
            if not state or not modes[record.mode] then return nil,"unavailable" end
            local mode,value=record.mode,record.value
            if mode=="ToggleOnOff" then
                if not instanceof(record.device,"IsoTelevision") or record.data:getIsBatteryPowered()~=false
                    or record.data:canBePoweredHere()~=true then return nil,"unavailable" end
                state.on=not state.on
            else
                if not state.on or mode~="TogglePlayMedia" and state.power<=0 then return nil,"unavailable" end
                if mode=="TogglePlayMedia" then
                    if state.media==false then return nil,"unavailable" end
                elseif mode=="SetChannel" then
                    local minimum,maximum=record.data:getMinChannelRange(),record.data:getMaxChannelRange()
                    if not integer(value) or value < -2147483648 or value > 2147483647 or not finite(minimum)
                        or not finite(maximum) or value<minimum or value>maximum then return nil,"unavailable" end
                    state.channel=value
                elseif mode=="MuteMicrophone" then
                    if type(value)~="boolean" then return nil,"unavailable" end
                    state.mic=value
                elseif mode=="MuteVolume" then
                    if state.volume<=0 then return nil,"unavailable" end
                    state.volume=0
                else
                    if not finite(value) or mode=="UnMuteVolume" and state.volume>0 then return nil,"unavailable" end
                    state.volume=math.max(0,math.min(1,value))
                end
            end
            local candidate=setmetatable({character=character,mode=mode,device=record.device,deviceData=record.data,
                secondaryItem=value,stopOnWalk=false,stopOnRun=true,ignoreHandsWounds=true},ISRadioAction)
            if not radioTrusted(candidate) then return nil,"unsupported" end
            if construct then
                action=ISRadioAction:new(mode,character,record.device,value)
                if not radioTrusted(action) then return nil,"unsupported" end
            end
        elseif record.kind=="media" then
            local state=deviceState(record)
            if not state or not instanceof(record.device,"IsoTelevision") or record.square:getDeviceData()~=record.data
                or record.data:getMediaType()~=1 then return nil,"unavailable" end
            local tape
            if record.remove==true then
                if state.media==false or record.mediaIndex~=false and state.media~=record.mediaIndex
                    or record.mediaIndex==false and not state.inserted then return nil,"unavailable" end
                state.media,state.inserted=false,false
                -- Native ejection creates a new item. Its factory-free output weight
                -- is not proven here, so later pickups cannot spend that root capacity.
                unmodeledRootOutput=true
            elseif record.remove==false then
                tape=items[record.itemId]
                if state.media~=false or locations[record.itemId]~=root or not tape:isRecordedMedia() or tape:getMediaType()~=1
                    or tape:getRecordedMediaIndex()~=record.mediaIndex then return nil,"unavailable" end
                locations[record.itemId]=false
                state.media,state.inserted=record.mediaIndex,true
            else return nil,"unavailable" end
            local candidate=setmetatable({character=character,isRemove=record.remove,secondaryItem=tape,parameter=record.square,
                deviceData=record.data,maxTime=30,stopOnWalk=false,stopOnRun=true,ignoreHandsWounds=true},ISDeviceMediaAction)
            if not mediaTrusted(candidate) then return nil,"unsupported" end
            if construct then
                action=ISDeviceMediaAction:new(character,record.remove,tape,record.square)
                if not mediaTrusted(action) then return nil,"unsupported" end
            end
        elseif record.kind=="transfer" then
            local item=items[record.itemId]
            if locations[record.itemId]~=record.source or record.source==record.destination or record.source:getContainingItem()
                or record.destination:getContainingItem()
                or unmodeledRootOutput and record.destination==root then return nil,"unavailable" end
            local candidate=setmetatable({character=character,item=item,srcContainer=record.source,destContainer=record.destination,
                maxTime=0,started=false,transactionId=0,allowMissingItems=record.allowMissing,
                queueList={{items={item},time=0,type=record.itemType}}},ISInventoryTransferAction)
            if not transferTrusted(candidate) then return nil,"unsupported" end
            -- Recompute native duration from current state. A derived maxTime from
            -- the canceled instance is not an explicit user-selected time override.
            if construct then
                action=ISInventoryTransferAction:new(character,item,record.source,record.destination)
                action.allowMissingItems=record.allowMissing
                if not transferTrusted(action) then return nil,"unsupported" end
            end
            if not record.source:isRemoveItemAllowed(item) or not record.destination:isItemAllowed(item)
                or not fits(record.destination,item) then return nil,"unavailable" end
            locations[record.itemId]=record.destination
        else return nil,"unsupported" end
        if construct then actions[#actions+1]=action end
    end
    return construct and actions or true
end
function Recovery.validate(records,character)
    local ok,valid,reason=pcall(project,records,character,false)
    if ok then return valid,reason end
    return nil,"unavailable"
end
function Recovery.plan(records,character)
    local ok,actions,reason=pcall(project,records,character,true)
    if ok then return actions,reason end
    return nil,"unavailable"
end
return Recovery
