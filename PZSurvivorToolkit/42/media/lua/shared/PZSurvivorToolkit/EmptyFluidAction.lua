-- Complete the native empty action after its own zero/pruning or authoritative client sync.
-- No fluid effect is replayed here; native progress, duration and completion remain in charge.
require "Fluids/ISFluidEmptyAction"
require "Fluids/ISFluidContainer"
require "Fluids/ISFluidUtil"
local Proof = require "PZSurvivorToolkit/SourceProof"
local API = {}
PZSurvivorToolkit = PZSurvivorToolkit or {}
PZSurvivorToolkit.EmptyFluidAction = API
local empty, wrapper, util, base = ISFluidEmptyAction, ISFluidContainer, ISFluidUtil, ISBaseTimedAction
local matches, closure, ownedField = Proof.matches, Proof.closure, Proof.own
local markerKey, token = "toolkitEmptyFluidEvidence", {}
local required = {
    {empty,"ISFluidEmptyAction.lua",{"isValid","update","serverStart","animEvent","getDuration","updateEmpty","start","stop","perform","complete","new"}},
    {wrapper,"ISFluidContainer.lua",{"new","initFromObject","copy","isItem","isResource","getFluidResource","isIsoPanel","resetObject","isValid","getFluidContainer","getOwner","getFluidObject","sync"}},
    {util,"ISFluidUtil.lua",{"validateContainer","doWalkTo","getContainerOwner","getTransferActionTimePerLiter","getMinTransferActionTime","getLuaFluidContainer"}},
}
local snapshots = {}
local function finite(value) return type(value)=="number" and value==value and value>-math.huge and value<math.huge end
local function method(value,name) return value and type(value[name])=="function" end
local function snapshot(owner,filename,names)
    if type(owner)~="table" then return false end
    local methods,seen={},{}
    for _,name in ipairs(names) do if type(ownedField(owner,name))~="function" then return false end end
    for name,callback in pairs(owner) do
        if type(callback)=="function" and name~="derive" then
            if seen[callback] or not closure(callback,filename) then return false end
            methods[name],seen[callback]=callback,true
        end
    end
    snapshots[owner]=methods
    return true
end
local supported = type(matches)=="function" and type(closure)=="function" and type(base)=="table"
    and matches("media/lua/shared/Fluids/ISFluidEmptyAction.lua",4049618573,nil,true)
    and matches("media/lua/shared/Fluids/ISFluidContainer.lua",2954809783,nil,true)
    and matches("media/lua/shared/Fluids/ISFluidUtil.lua",299578700,nil,true)
    and matches("media/lua/shared/TimedActions/ISBaseTimedAction.lua",3104185167,nil,true)
if supported then
    for _,entry in ipairs(required) do
        if not snapshot(entry[1],entry[2],entry[3]) then supported=false;break end
    end
end
local nativeValid=supported and snapshots[empty].isValid
local nativeUpdate=supported and snapshots[empty].updateEmpty
local baseDelta=supported and ownedField(base,"getJobDelta")
local valid,update
local function live()
    if not supported or ISFluidEmptyAction~=empty or ISFluidContainer~=wrapper or ISFluidUtil~=util
        or ISBaseTimedAction~=base or Proof.matches~=matches or Proof.closure~=closure or Proof.own~=ownedField
        or ownedField(empty,"__index")~=empty or ownedField(wrapper,"__index")~=wrapper
        or ownedField(base,"getJobDelta")~=baseDelta or not closure(baseDelta,"ISBaseTimedAction.lua") then return false end
    for _,entry in ipairs(required) do
        local owner,filename=entry[1],entry[2]
        for name,callback in pairs(snapshots[owner]) do
            local expected=owner==empty and (name=="isValid" and valid or name=="updateEmpty" and update) or callback
            if ownedField(owner,name)~=expected or not closure(callback,filename) then return false end
        end
        for name,callback in pairs(owner) do
            if type(callback)=="function" and name~="derive" and not snapshots[owner][name] then return false end
        end
    end
    return true
end
local function clear(action) if type(action)=="table" then rawset(action,markerKey,nil) end end
local function carried(container,player)
    local root,seen=player:getInventory(),{}
    while instanceof(container,"ItemContainer") and not seen[container] do
        seen[container]=true
        local kind=container:getType()
        if kind=="floor" or kind=="proximityInv" or kind=="twistInv_corpses" or kind=="TradeUI"
            or not container:isExistYet() or container:getAcceptItemFunction()~=nil or container:getOnlyAcceptCategory()~=nil then return false end
        if container==root then return container:getParent()==player end
        local owner=container:getContainingItem()
        if not instanceof(owner,"InventoryContainer") or owner:getInventory()~=container then return false end
        local parent=owner:getContainer()
        if not instanceof(parent,"ItemContainer") or not parent:contains(owner) or parent:getItemById(owner:getID())~=owner then return false end
        container=parent
    end
    return false
end
local function context(action)
    if not live() or type(action)~="table" or getmetatable(action)~=empty or action.Type~=empty.Type
        or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc or action.onFailFunc
        or action.additionalTest or action.retriggerLastAction then return end
    for name,callback in pairs(snapshots[empty]) do
        local expected=name=="isValid" and valid or name=="updateEmpty" and update or callback
        if action[name]~=expected then return end
    end
    if action.getJobDelta~=baseDelta then return end
    for name,callback in pairs(action) do
        if type(callback)=="function" and not snapshots[empty][name] then return end
    end
    local box=ownedField(action,"container")
    -- Check dispatch before any inherited lookup; never call a foreign wrapper getter.
    if type(box)~="table" or getmetatable(box)~=wrapper then return end
    for name,callback in pairs(snapshots[wrapper]) do if box[name]~=callback then return end end
    for _,callback in pairs(box) do if type(callback)=="function" then return end end
    if box.Type~=wrapper.Type or box.isFluidResource~=false or box.fluidResource~=nil
        or box.isInventoryItem~=true or box.isoPanel~=false then return end
    local fluid=ownedField(box,"fluidContainer")
    if not instanceof(fluid,"FluidContainer") or action.containerObject~=fluid then return end
    local item,player=fluid:getOwner(),ownedField(action,"character")
    if not instanceof(item,"ComboItem") or type(getClassSimpleName)~="function" or getClassSimpleName(item)~="ComboItem"
        or not instanceof(player,"IsoPlayer") or item:getFluidContainer()~=fluid or item:getWorldItem()
        or item:getIsCraftingConsumed() or player:isEquipped(item) or item:getEquipParent() or item:getAttachedSlot()>=0 then return end
    local id,location=item:getID(),item:getContainer()
    if not finite(id) or id%1~=0 or not instanceof(location,"ItemContainer") or not location:contains(item)
        or location:getItemById(id)~=item or not carried(location,player) then return end
    if not finite(action.amount) or action.amount<=0 or not finite(action.maxTime) or action.maxTime<=0
        or not fluid:canPlayerEmpty() then return end
    return {box=box,fluid=fluid,item=item,player=player,location=location,amount=action.amount,maxTime=action.maxTime}
end
local zeroProperties={"getFatigueChange","getHungerChange","getStressChange","getUnhappyChange","getCalories","getCarbohydrates",
    "getLipids","getProteins","getAlcohol","getPoison","getFluReduction","getPainReduction","getEnduranceChange","getFoodSicknessChange"}
local function cleanWater(fluid)
    if not Fluid or not Fluid.Water or not fluid:isPureFluid(Fluid.Water) or fluid:isTainted() or fluid:isPoisonous() then return false end
    local amount,capacity=fluid:getAmount(),fluid:getCapacity()
    if not finite(amount) or amount<=0 or not finite(capacity) or capacity<=0 or amount>capacity then return false end
    local properties=fluid:getProperties()
    for _,name in ipairs(zeroProperties) do if properties[name](properties)~=0 then return false end end
    local thirst=properties:getThirstChange()
    return finite(thirst) and thirst<=0
end
local function active(action,state)
    local native=ownedField(action,"action")
    if not instanceof(native,"LuaTimedActionNew") or not method(native,"getTable") or native:getTable()~=action
        or not native:isStarted() or not state.player:getCharacterActions():contains(native) then return end
    local delta=native:getJobDelta()
    if not finite(delta) or delta<0 or delta>1 then return end
    return native,delta
end
local function same(left,right)
    return left and right and left.box==right.box and left.fluid==right.fluid and left.item==right.item
        and left.player==right.player and left.location==right.location and left.amount==right.amount and left.maxTime==right.maxTime
end
local function record(action,state,native,delta,client)
    state.token,state.native,state.delta,state.client=token,native,delta,client
    rawset(action,markerKey,state)
end
update=function(action,delta)
    local previous=type(action)=="table" and ownedField(action,markerKey)
    local before=context(action)
    local native,progress
    if before and not isClient() and not isServer() and finite(delta) and delta>=0 and delta<=1
        and cleanWater(before.fluid) then
        native,progress=active(action,before)
        if delta~=progress then native=nil end
    end
    clear(action)
    nativeUpdate(action,delta)
    local after=context(action)
    if native and same(before,after) and before.fluid:isEmpty() and before.fluid:getAmount()==0 then
        record(action,before,native,progress,false)
    elseif previous and previous.token==token and not previous.client and same(previous,after)
        and not isClient() and not isServer() and after.fluid:isEmpty() and after.fluid:getAmount()==0 then
        -- Paused/slow ticks may revisit the same already-empty native update.
        -- Retain only this same live action's evidence, never a fresh empty input.
        local current,now=active(action,after)
        if current==previous.native and now>=previous.delta then record(action,after,current,now,false) end
    end
end
valid=function(action)
    local result=nativeValid(action)
    local state=context(action)
    local native,delta
    if state then native,delta=active(action,state) end
    if result then
        clear(action)
        -- The client never updates fluid itself. Remember its own positive active
        -- state before authoritative empty replication can precede the Done packet.
        if isClient() and not isServer() and native and cleanWater(state.fluid) then record(action,state,native,delta,true) end
        return result
    end
    local evidence=type(action)=="table" and ownedField(action,markerKey)
    if not native or not evidence or evidence.token~=token or evidence.native~=native or not same(evidence,state)
        or delta<evidence.delta or evidence.client~=(isClient() and not isServer())
        or not state.fluid:isEmpty() or state.fluid:getAmount()~=0 then clear(action);return result end
    -- Native validation still owns existence/reachability and emptying permission.
    if not util.validateContainer(state.box) or not state.fluid:canPlayerEmpty() then clear(action);return result end
    return true
end
function API.authorizes(owner,name,callback)
    return live() and owner==empty and ((name=="isValid" and callback==valid) or (name=="updateEmpty" and callback==update))
end
if supported then empty.isValid,empty.updateEmpty=valid,update end
return API
