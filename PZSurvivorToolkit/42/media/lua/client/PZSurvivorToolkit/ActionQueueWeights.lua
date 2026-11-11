local Weights = {}
PZSurvivorToolkit.ActionQueueWeights = Weights

local MAX_FLOAT, MIN_NORMAL, MIN_FLOAT, ROUND_SLACK = 3.4028234663852886e38, 1.1754943508222875e-38, 1.401298464324817e-45, 0.000001
local function finite(value) return type(value)=="number" and value==value and value>-math.huge and value<math.huge end
local function weight(value) return type(value)=="number" and value==value and value>=0 and value<=MAX_FLOAT end
local function method(value,name) return value and type(value[name])=="function" end
-- Outward slack covers each native float operation, including subnormal results.
local function up(value)
    if not weight(value) then return end
    value=value+value*ROUND_SLACK+MIN_FLOAT
    if weight(value) then return value end
end
local function plus(left,right) return left and right and up(left+right) or nil end
local function times(left,right) return left and right and up(left*right) or nil end
local function entries(container)
    if not instanceof(container,"ItemContainer") or not method(container,"getItems") then return end
    local items=container:getItems()
    if not method(items,"size") or not method(items,"get") then return end
    local count=items:size()
    if not finite(count) or count<0 or count%1~=0 then return end
    return items,count
end
local fluidWeight
local function free(value,seen,probe,direct)
    if not instanceof(value,"InventoryItem") and not instanceof(value,"ItemContainer") or seen[value] then return false end
    seen[value]=true
    if probe and instanceof(value,"InventoryItem") and (type(getClassSimpleName)~="function"
        or not probe.classes[getClassSimpleName(value)]) then probe.invalid=true;return false end
    if instanceof(value,"Food") and (not method(value,"haveExtraItems") or value:haveExtraItems()) then return false end
    if instanceof(value,"InventoryContainer") then
        local safe=method(value,"getInventory") and free(value:getInventory(),seen,probe) or false
        if not safe or not probe then return safe end
        -- Native InventoryContainer U is clamped raw plus child U sum plus
        -- fluid amount. Children were sign-checked in this same walk: avoid
        -- recursively recalculating each nested owner's contents again.
        if not method(value,"getActualWeightUnmodded") or not weight(value:getActualWeightUnmodded())
            or not fluidWeight(value) then probe.invalid=true;return false end
        return true
    elseif instanceof(value,"ItemContainer") then
        local items,count=entries(value)
        if not items then return false end
        if probe and value==probe.root then
            -- Native ArrayList.size() is a Java int. For N<=2^31-1, summing
            -- nonnegative native floats in double has gamma_N<2.4e-7; one
            -- existing up() covers that error. No per-item float pad is needed.
            if count>2147483647 then probe.invalid=true;return false end
            probe.count=count
        end
        for i=0,count-1 do
            local item=items:get(i)
            local valid=free(item,seen,probe,probe and value==probe.root)
            if not valid then return false end
            if probe and value==probe.root then
                if not method(item,"getAttachedSlot") or not method(item,"isFakeEquipped") then probe.invalid=true;return false end
                local equipped=probe.actor:isEquipped(item)
                local mode=item:getAttachedSlot()>-1 and not equipped and "getHotbarEquippedWeight"
                    or (equipped or item:isFakeEquipped(probe.actor)) and "getEquippedWeight" or "getUnequippedWeight"
                if mode=="getHotbarEquippedWeight" and instanceof(item,"InventoryContainer") then probe.invalid=true;return false end
                if not method(item,mode) then probe.invalid=true;return false end
                local term=item[mode](item)
                if not weight(term) then probe.invalid=true;return false end
                -- N*MAX_FLOAT is below double overflow, and every positive
                -- float term is double-normal. Guard/pad the total once below.
                probe.total=probe.total+term
            end
        end
    elseif probe and not direct then
        -- Non-root leaves supply container contents through U, irrespective of
        -- their actor mode. Direct root leaves use their current-mode read below.
        if not method(value,"getUnequippedWeight") then probe.invalid=true;return false end
        local exact=value:getUnequippedWeight()
        if not weight(exact) then probe.invalid=true;return false end
        return true,exact
    end
    return true
end
function Weights.factoryFree(value) return free(value,{}) end

-- Fresh plain Food prototypes have a script hunger /100 -> *100 -> /script
-- hunger weight ratio. Reject subnormal/overflow inputs before bounding those
-- float operations; never invoke InventoryItemFactory or virtual Food weight.
function Weights.extraFood(item)
    if not instanceof(item,"Food") or not method(item,"haveExtraItems") or not item:haveExtraItems()
        or not method(item,"getExtraItems") or not method(item,"getActualWeightUnmodded")
        or not method(item,"getHungChange") or not method(item,"getBaseHunger")
        or not method(item,"getReplaceOnUse") or not method(item,"getReplaceOnUseFullType")
        or not ScriptManager or not ScriptManager.instance then return end
    local raw,hunger,base=item:getActualWeightUnmodded(),item:getHungChange(),item:getBaseHunger()
    if not weight(raw) or not finite(hunger) or not finite(base) or base>=0 or hunger>0 or hunger<base then return end
    local shell=0
    if item:getReplaceOnUse()~=nil then
        local kind=item:getReplaceOnUseFullType()
        if type(kind)~="string" or kind=="" then return end
        local script=ScriptManager.instance:getItem(kind)
        if not method(script,"getActualWeight") then return end
        shell=script:getActualWeight()
    end
    if not weight(shell) or raw<shell then return end
    local extras=item:getExtraItems()
    if not method(extras,"size") or not method(extras,"get") then return end
    local count=extras:size()
    if not finite(count) or count%1~=0 or count<1 or count>6 then return end
    local ceiling=MAX_FLOAT/(count+2)
    if raw>ceiling then return end
    local extraUpper=0
    for i=0,count-1 do
        local kind=extras:get(i)
        if type(kind)~="string" or kind=="" then return end
        local script=ScriptManager.instance:getItem(kind)
        for _,name in ipairs({"getItemType","getLuaCreate","getItemConfig","getItemConfigKey","hasComponents",
            "getReplaceOnUse","getHungerChange","getActualWeight"}) do if not method(script,name) then return end end
        if tostring(script:getItemType())~="base:food" or script:getLuaCreate() or script:getItemConfig()
            or script:getItemConfigKey() or script:hasComponents() or script:getReplaceOnUse() then return end
        local h,w=script:getHungerChange(),script:getActualWeight()
        if not finite(h) or h>-100*MIN_NORMAL or h<-MAX_FLOAT/2 or not weight(w) or w>ceiling then return end
        -- Three rounded operations precede the prototype's final weight.
        local prototype=times(w,1.000001)
        extraUpper=plus(extraUpper,prototype)
        if not extraUpper then return end
    end
    extraUpper=times(extraUpper,0.6000000238418579) -- native float 0.6
    local slope=extraUpper and plus(raw,extraUpper)
    slope=slope and up(slope-shell)
    local ratio=up(hunger/base)
    local upper=slope and ratio and plus(times(slope,ratio),shell)
    if not upper then return end
    return upper,0,{raw=raw,shell=shell,extraUpper=extraUpper,count=count}
end

fluidWeight=function(item)
    if not method(item,"getFluidContainer") then return end
    local fluid=item:getFluidContainer()
    if not fluid then return 0 end
    if not instanceof(fluid,"FluidContainer") or not method(fluid,"getOwner") or fluid:getOwner()~=item
        or not method(fluid,"getAmount") then return end
    local amount=fluid:getAmount()
    if weight(amount) then return amount end
end
local function carried(container,actor)
    if not instanceof(actor,"IsoPlayer") or not method(actor,"getInventory") then return false end
    local root,seen=actor:getInventory(),{}
    while instanceof(container,"ItemContainer") and not seen[container] do
        seen[container]=true
        if not method(container,"getAcceptItemFunction") or container:getAcceptItemFunction()~=nil
            or not method(container,"getOnlyAcceptCategory") or container:getOnlyAcceptCategory()~=nil then return false end
        if container==root then return method(container,"getParent") and container:getParent()==actor end
        if not method(container,"getContainingItem") then return false end
        local owner=container:getContainingItem()
        if not instanceof(owner,"InventoryContainer") or not method(owner,"getInventory") or owner:getInventory()~=container
            or not method(owner,"getWorldItem") or owner:getWorldItem()~=nil or not method(owner,"getContainer") then return false end
        container=owner:getContainer()
    end
    return false
end

-- Generic equipped weight reads the loaded Java multiplier. The Lua globals
-- table may have changed since ZomboidGlobals.Load, so measure a real existing
-- native witness instead of assuming that table still equals the Java field.
local witnessClasses={ComboItem=true,Food=true,HandWeapon=true,Key=true,KeyRing=true,Literature=true,MapItem=true}
local function multiplierUpper(raw,equipped)
    if weight(raw) and raw>=MIN_NORMAL and weight(equipped) then
        local rounded=up(equipped)
        if rounded then return up(rounded/raw) end
    end
end
local function multiplier(actor)
    if type(getClassSimpleName)~="function" or not method(actor,"getInventory") then return end
    local pending,seen={actor:getInventory()},{}
    while #pending>0 do
        local current=table.remove(pending)
        if seen[current] then return end
        seen[current]=true
        if instanceof(current,"ItemContainer") then
            local items,count=entries(current)
            if not items then return end
            for i=0,count-1 do pending[#pending+1]=items:get(i) end
        elseif instanceof(current,"InventoryContainer") then
            if not method(current,"getInventory") then return end
            pending[#pending+1]=current:getInventory()
        elseif instanceof(current,"InventoryItem") and witnessClasses[getClassSimpleName(current)]
            and Weights.factoryFree(current) and method(current,"getUnequippedWeight") and method(current,"getEquippedWeight") then
            local raw,equipped=current:getUnequippedWeight(),current:getEquippedWeight()
            local upper=multiplierUpper(raw,equipped)
            if upper then return upper end
        end
    end
end

local boundItem,boundContents
boundContents=function(container,context)
    if not instanceof(container,"ItemContainer") or context.seen[container] then return end
    context.seen[container]=true
    local items,count=entries(container)
    if not items then return end
    local total=0
    for i=0,count-1 do
        local value=boundItem(items:get(i),"unequipped",context)
        total=plus(total,value)
        if not total then return end
    end
    return total,0
end
boundItem=function(item,mode,context,direct)
    if not instanceof(item,"InventoryItem") or context.seen[item] then return end
    context.seen[item]=true
    if context.classes and (type(getClassSimpleName)~="function" or not context.classes[getClassSimpleName(item)]) then return end
    local getter=mode=="equipped" and "getEquippedWeight" or mode=="hotbar" and "getHotbarEquippedWeight" or "getUnequippedWeight"
    -- Container held contents use their own reduction, whereas native hotbar
    -- weight scales all contents by 0.7. A generic multiplier witness is not a
    -- nonincrease proof for this mode; keep this new authority unavailable.
    if context.probe and mode=="hotbar" and instanceof(item,"InventoryContainer") then context.probe.invalid=true;return end
    local safe,unequipped
    if context.probe then
        safe,unequipped=free(item,{},context.probe,direct)
        if context.probe.invalid then return end
    else safe=Weights.factoryFree(item) end
    if safe then
        if getter=="getUnequippedWeight" and unequipped~=nil then return unequipped,unequipped end
        if not method(item,getter) then return end
        local exact=item[getter](item)
        if weight(exact) then return exact,exact end
        return
    end
    local raw,contents
    if instanceof(item,"InventoryContainer") then
        if not method(item,"getInventory") or not method(item,"getActualWeightUnmodded") then return end
        raw=item:getActualWeightUnmodded()
        if not weight(raw) then return end
        contents=boundContents(item:getInventory(),context)
        contents=plus(contents,fluidWeight(item))
    elseif instanceof(item,"Food") then
        raw=Weights.extraFood(item)
        -- Ordinary Food contents use ammo first, otherwise its fluid amount.
        -- Extra-food ammo/world-fluid variants have no reviewed creation proof.
        if not raw or not method(item,"getAmmoType") or item:getAmmoType()~=nil
            or not method(item,"getWorldItem") or item:getWorldItem()~=nil then return end
        contents=fluidWeight(item)
    else return end
    if not contents then return end
    if mode=="unequipped" then return plus(raw,contents),0 end
    if mode=="equipped" and instanceof(item,"InventoryContainer") then
        if not method(item,"getWeightReduction") then return end
        local reduction=item:getWeightReduction()
        if not finite(reduction) or reduction%1~=0 or reduction<0 or reduction>100 then return end
        if context.multiplier==nil then context.multiplier=multiplier(context.actor) or false end
        if not context.multiplier then return end
        local retained=up(1-reduction/100)
        return plus(times(raw,context.multiplier),times(contents,retained)),0
    end
    local factor
    if mode=="hotbar" then
        if not ItemTag or not ItemTag.LIGHT_WHEN_ATTACHED or not method(item,"hasTag") then return end
        if not item:hasTag(ItemTag.LIGHT_WHEN_ATTACHED) then factor=0.699999988079071 end
    end
    if factor==nil then
        if context.multiplier==nil then context.multiplier=multiplier(context.actor) or false end
        factor=context.multiplier
    end
    if not factor then return end
    return times(plus(raw,contents),factor),0
end
function Weights.unequipped(item)
    return boundItem(item,"unequipped",{seen={}})
end
local capacityClasses={InventoryItem=true,ComboItem=true,HandWeapon=true,Clothing=true,DrainableComboItem=true,
 Food=true,Key=true,KeyRing=true,Literature=true,MapItem=true,InventoryContainer=true,WeaponPart=true,
 AlarmClock=true,AlarmClockClothing=true,Moveable=true,Radio=true}
local factoryFreeSource,extraFoodSource=Weights.factoryFree,Weights.extraFood
local shiftedCapacity
function Weights.capacity(container,actor,releasedDiscount)
    if not instanceof(container,"ItemContainer") then return end
    -- Native actor-owned capacity redirects to the actor's inventory. A
    -- mismatched container must not certify another, unscanned item tree.
    if method(container,"getParent") then
        local parent=container:getParent()
        if (instanceof(parent,"IsoGameCharacter") or instanceof(parent,"IsoPlayer"))
            and (not method(parent,"getInventory") or parent:getInventory()~=container) then return end
    end
    local probe
    if releasedDiscount~=nil then
        if not weight(releasedDiscount) or not instanceof(actor,"IsoPlayer")
            or container~=actor:getInventory() or not method(actor,"isEquipped")
            or Weights.factoryFree~=factoryFreeSource or Weights.extraFood~=extraFoodSource then return end
        probe={root=container,actor=actor,total=0,classes=capacityClasses}
    end
    local safe=probe and free(container,{},probe) or not probe and Weights.factoryFree(container)
    if probe and probe.invalid then return end
    if safe then
        if probe then
            local total=up(probe.total)
            if not total then return end
            -- This is a real-sum upper, so native fadd still needs its bound
            -- even when no current hand discount disappears.
            return shiftedCapacity(total,releasedDiscount,probe.count),0
        end
        if not method(container,"getCapacityWeight") then return end
        local exact=container:getCapacityWeight()
        if weight(exact) then return exact,exact end
        return
    end
    if not carried(container,actor) or not method(container,"getParent") then return end
    if container~=actor:getInventory() then
        if container:getParent()~=nil then return end
        return boundContents(container,{seen={},actor=actor})
    end
    local items,count=entries(container)
    if not items or not method(actor,"isEquipped") then return end
    local context,total={seen={[container]=true},actor=actor,classes=probe and capacityClasses,probe=probe},0
    for i=0,count-1 do
        local item=items:get(i)
        if not instanceof(item,"InventoryItem") or not method(item,"getAttachedSlot") or not method(item,"isFakeEquipped") then return end
        local equipped=actor:isEquipped(item)
        local mode=item:getAttachedSlot()>-1 and not equipped and "hotbar"
            or (equipped or item:isFakeEquipped(actor)) and "equipped" or "unequipped"
        total=plus(total,boundItem(item,mode,context,true))
        if not total then return end
    end
    if probe and releasedDiscount>0 then return shiftedCapacity(total,releasedDiscount,count),0 end
    return total,0
end
-- The caller has observed nonnegative root terms and supplies their outward
-- real-sum upper. N native binary32 additions can grow that sum by at most the
-- same per-operation normal/subnormal slack used by up(). No loop, size budget
-- or future space credit is introduced; overflow is an unavailable bound.
shiftedCapacity=function(current,delta,count)
    if not weight(current) or not weight(delta) or not finite(count) or count<0 or count%1~=0 then return end
    local factor=up((1+ROUND_SLACK)^count)
    local subnormal=times(count,MIN_FLOAT)
    return factor and plus(times(plus(current,delta),factor),times(subnormal,factor)) or nil
end
Weights.shiftedCapacity=shiftedCapacity
-- A qualified plain Clothing witness uses native U * float(m). The existing
-- outward ratio also covers its binary32 rounding, including subnormals. An
-- unseen incoming hotbar item may still use native 0.7f until Equip sync, so m
-- must not exceed that discount either. No mutable Lua globals value is trusted.
function Weights.nativeDiscountKnown(unequipped,equipped)
    local upper=multiplierUpper(unequipped,equipped)
    return upper~=nil and upper<=0.699999988079071
end
return Weights
