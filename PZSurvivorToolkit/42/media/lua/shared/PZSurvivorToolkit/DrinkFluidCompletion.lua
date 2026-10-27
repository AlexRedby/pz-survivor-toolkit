-- Keep the native drink alive when its own water update prunes the final trace
-- before the native timer finishes. Completion and fluid effects stay native.
require "TimedActions/ISDrinkFluidAction"
require "PZSurvivorToolkit/DrinkFluidAction"
local Proof = require "PZSurvivorToolkit/SourceProof"
local API = {}
PZSurvivorToolkit = PZSurvivorToolkit or {}
PZSurvivorToolkit.DrinkFluidCompletion = API
local drink,base = ISDrinkFluidAction,ISBaseTimedAction
local matches,closure = Proof.matches,Proof.closure
local token,markerKey = {},"toolkitDrinkFluidEvidence"
-- Kahlua rawget follows the metatable; pairs enumerates only owned members.
local function ownMembers(owner)
    local values={}
    for name,value in pairs(owner) do values[name]=value end
    return values
end
local function ownValue(owner,key)
    for name,value in pairs(owner) do if name==key then return value end end
end
local names = {"isValidStart","waitToStart","isValid","update","serverStart","animEvent","start","stop","perform","complete","updateEat","getDuration","new"}
local methods,timing = {},{}
local timingNames={"getJobDelta","getDuration","adjustMaxTime","create"}
local function finite(value) return type(value)=="number" and value==value and value>-math.huge and value<math.huge end
local function guarded(guard) local ok,result=pcall(guard);return ok and result==true end
local fullnessPinned
local function origin(name,callback)
    if closure(callback,"ISDrinkFluidAction.lua") then return true end
    if name~="isValidStart" or not closure(callback,"DrinkFluidAction.lua") then return false end
    -- Loaded closure identities stay live below; rereading its source on every
    -- progress tick cannot strengthen the initial source proof.
    if fullnessPinned==nil then
        fullnessPinned=matches("media/lua/shared/PZSurvivorToolkit/DrinkFluidAction.lua",3238429308,"PZSurvivorToolkit",true)
    end
    return fullnessPinned
end
local unsupported,supported
local function rejectInitial(reason) supported=false;unsupported=unsupported or reason end
supported = type(matches)=="function" and type(closure)=="function" and type(drink)=="table" and type(base)=="table"
if not supported then unsupported="initial-prerequisites"
elseif not matches("media/lua/shared/TimedActions/ISDrinkFluidAction.lua",3564665289,nil,true) then rejectInitial("initial-source:drink")
elseif not matches("media/lua/shared/TimedActions/ISBaseTimedAction.lua",3104185167,nil,true) then rejectInitial("initial-source:base") end
if supported then
    local initialBase,initialDrink=ownMembers(base),ownMembers(drink)
    local seenTiming={}
    for _,name in ipairs(timingNames) do
        local callback=initialBase[name]
        if not closure(callback,"ISBaseTimedAction.lua") then rejectInitial("initial-base-origin:"..name)
        elseif seenTiming[callback] then rejectInitial("initial-base-alias:"..name) end
        if callback then seenTiming[callback]=true end
        timing[name]=callback
    end
    for _,name in ipairs(names) do if type(initialDrink[name])~="function" then rejectInitial("initial-missing:"..name) end end
    local seen={}
    for name,callback in pairs(initialDrink) do
        if type(callback)=="function" and name~="derive" then
            if seen[callback] then rejectInitial("initial-drink-alias:"..name)
            elseif not origin(name,callback) then rejectInitial("initial-drink-origin:"..name) end
            seen[callback],methods[name]=true,callback
        end
    end
end
local nativeValid,nativeUpdate=methods.isValid,methods.updateEat
local baseDelta=ownValue(base,"getJobDelta")
local valid,update,adoptedStart,startGuard
local function rejected(reason,callback)
    if type(callback)=="function" and type(getFilenameOfClosure)=="function" then
        local ok,filename=pcall(getFilenameOfClosure,callback)
        if ok and type(filename)=="string" then reason=reason.."@"..filename end
    end
    return false,reason
end
local function live()
    if not supported then return false,unsupported end
    if ISDrinkFluidAction~=drink then return false,"global-drink" end
    if ISBaseTimedAction~=base then return false,"global-base" end
    if Proof.matches~=matches then return false,"proof-matches" end
    if Proof.closure~=closure then return false,"proof-closure" end
    -- Native derive leaves this unset until the first BaseTimedAction:new.
    -- Startup adoption may precede that constructor; foreign dispatch never may.
    local liveDrink,liveBase=ownMembers(drink),ownMembers(base)
    local dispatch=liveDrink.__index
    if dispatch~=nil and dispatch~=drink then return false,"drink-dispatch" end
    if liveBase.getJobDelta~=baseDelta then return rejected("base-binding:getJobDelta",liveBase.getJobDelta) end
    if not closure(baseDelta,"ISBaseTimedAction.lua") then return rejected("base-origin:getJobDelta",baseDelta) end
    if adoptedStart and not guarded(startGuard) then return false,"start-guard" end
    for _,name in ipairs(timingNames) do
        if liveBase[name]~=timing[name] then return rejected("base-binding:"..name,liveBase[name]) end
        if not closure(timing[name],"ISBaseTimedAction.lua") then return rejected("base-origin:"..name,timing[name]) end
    end
    local seen={}
    for name,callback in pairs(methods) do
        local expected=name=="isValid" and valid or name=="updateEat" and update
            or name=="start" and adoptedStart or callback
        if liveDrink[name]~=expected then return rejected("drink-binding:"..name,liveDrink[name]) end
        if not origin(name,callback) then return rejected("drink-origin:"..name,callback) end
    end
    for name,callback in pairs(liveDrink) do
        if type(callback)=="function" and name~="derive" then
            if not methods[name] then return rejected("drink-extra:"..name,callback) end
            if seen[callback] then return rejected("drink-alias:"..name,callback) end
            seen[callback]=true
        end
    end
    return true,nil,liveDrink
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
local tuple={"percentage","startRatio","endRatio","targetConsumedRatio","maxTime"}
local function context(action)
    local ready,_,liveDrink=live()
    if not ready or liveDrink.__index~=drink or type(action)~="table" or getmetatable(action)~=drink or action.Type~=drink.Type
        or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc or action.onFailFunc
        or action.additionalTest or action.retriggerLastAction or action.useUtensil~=false then return end
    for name,callback in pairs(methods) do
        local expected=name=="isValid" and valid or name=="updateEat" and update
            or name=="start" and adoptedStart or callback
        if action[name]~=expected then return end
    end
    for _,name in ipairs(timingNames) do
        if action[name]~=(name=="getDuration" and methods.getDuration or timing[name]) then return end
    end
    for _,callback in pairs(action) do if type(callback)=="function" then return end end
    local item,player,fluid=ownValue(action,"item"),ownValue(action,"character"),ownValue(action,"fluidContainer")
    if not instanceof(item,"ComboItem") or type(getClassSimpleName)~="function" or getClassSimpleName(item)~="ComboItem"
        or not instanceof(player,"IsoPlayer") or not instanceof(fluid,"FluidContainer")
        or fluid:getOwner()~=item or item:getFluidContainer()~=fluid or fluid:isTainted() or fluid:isPoisonous() or item:getWorldItem()
        or item:getIsCraftingConsumed() or player:isEquipped(item) or item:getEquipParent() or item:getAttachedSlot()>=0 then return end
    local id,location=item:getID(),item:getContainer()
    if not finite(id) or id%1~=0 or not instanceof(location,"ItemContainer") or not location:contains(item)
        or location:getItemById(id)~=item or not carried(location,player) then return end
    for _,name in ipairs(tuple) do if not finite(action[name]) then return end end
    if action.percentage<=0 or action.percentage>1 or action.startRatio<=0 or action.startRatio>1
        or action.endRatio~=action.startRatio*(1-action.percentage)
        or action.targetConsumedRatio~=action.startRatio-action.endRatio
        or action.maxTime<=0 then return end
    local capacity=fluid:getCapacity()
    if not finite(capacity) or capacity<=0 then return end
    local state={item=item,player=player,fluid=fluid,location=location,capacity=capacity}
    for _,name in ipairs(tuple) do state[name]=action[name] end
    return state
end
local zeroProperties={"getFatigueChange","getHungerChange","getStressChange","getUnhappyChange","getCalories","getCarbohydrates",
    "getLipids","getProteins","getAlcohol","getPoison","getFluReduction","getPainReduction","getEnduranceChange","getFoodSicknessChange"}
local function water(fluid)
    if not Fluid or not Fluid.Water or not fluid:isPureFluid(Fluid.Water) or fluid:isTainted() or fluid:isPoisonous() then return false end
    local amount,capacity=fluid:getAmount(),fluid:getCapacity()
    if not finite(amount) or amount<=0 or not finite(capacity) or capacity<=0 or amount>capacity then return false end
    local properties=fluid:getProperties()
    for _,name in ipairs(zeroProperties) do if properties[name](properties)~=0 then return false end end
    local thirst=properties:getThirstChange()
    return finite(thirst) and thirst<=0
end
local function active(action,state)
    local native=ownValue(action,"action")
    if not instanceof(native,"LuaTimedActionNew") or native:getTable()~=action or not native:isStarted()
        or not state.player:getCharacterActions():contains(native) then return end
    local delta=native:getJobDelta()
    if not finite(delta) or delta<0 or delta>1 then return end
    return native,delta
end
local function same(left,right)
    if not left or not right or left.item~=right.item or left.player~=right.player or left.fluid~=right.fluid
        or left.location~=right.location or left.capacity~=right.capacity then return false end
    for _,name in ipairs(tuple) do if left[name]~=right[name] then return false end end
    return true
end
local function record(action,state,native,delta,client)
    state.token,state.native,state.delta,state.client=token,native,delta,client
    rawset(action,markerKey,state)
end
update=function(action,delta)
    local previous=type(action)=="table" and ownValue(action,markerKey)
    local before=context(action)
    local native,progress
    if before and not isClient() and not isServer() and finite(delta) and delta>=0 and delta<=1 and water(before.fluid) then
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
        local current,now=active(action,after)
        if current==previous.native and now>=previous.delta and delta==now then record(action,after,current,now,false) end
    end
end
valid=function(action)
    local result=nativeValid(action)
    local state=context(action)
    local native,delta
    if state then native,delta=active(action,state) end
    if result then
        clear(action)
        if isClient() and not isServer() and native and water(state.fluid) then record(action,state,native,delta,true) end
        return result
    end
    local evidence=type(action)=="table" and ownValue(action,markerKey)
    if not native or not evidence or evidence.token~=token or evidence.native~=native or not same(evidence,state)
        or delta<evidence.delta or evidence.client~=(isClient() and not isServer())
        or isServer() or not state.fluid:isEmpty() or state.fluid:getAmount()~=0 then clear(action);return result end
    evidence.delta=delta
    return true
end
function API.authorizes(owner,name,callback)
    local ready,reason=live()
    if not ready then return false,reason end
    if owner~=drink then return false,"owner" end
    if (name=="isValid" and callback==valid) or (name=="updateEat" and callback==update) then return true end
    return false,"callback:"..tostring(name)
end
function API.adoptStart(previous,replacement,guard)
    if not supported or adoptedStart or previous~=methods.start or type(replacement)~="function" or replacement==previous
        or ownValue(drink,"start")~=replacement or type(guard)~="function" or not guarded(guard) then return false end
    for name,callback in pairs(drink) do if name~="start" and callback==replacement then return false end end
    adoptedStart,startGuard=replacement,guard
    if live() then return true end
    adoptedStart,startGuard=nil,nil
    return false
end
if supported then drink.isValid,drink.updateEat=valid,update end
return API
