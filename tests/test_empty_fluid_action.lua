if not NativeActionRoot then print('Empty fluid repair SKIP (pass --native-action-root).');return end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r','') end
    local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
local function reader(text)
    local cursor=1
    return {close=function()end,readLine=function()
        if cursor>#text then return end
        local boundary=text:find('\n',cursor,true)or #text+1
        local line=text:sub(cursor,boundary-1);cursor=boundary+1;return line
    end}
end
local function setup(options)
    options=options or {}
    local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    f.native('shared/Fluids/ISFluidContainer.lua');f.native('shared/Fluids/ISFluidUtil.lua');f.native('shared/Fluids/ISFluidEmptyAction.lua')
    local nativeValid,nativeUpdate=ISFluidEmptyAction.isValid,ISFluidEmptyAction.updateEmpty
    local nativeComplete,nativeDuration=ISFluidEmptyAction.complete,ISFluidEmptyAction.getDuration
    getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    getGameFilesInput=function(path)
        local text=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
        if options.changed and path:find(options.changed,1,true)then text=text..'-- changed\n'end
        return reader(text)
    end
    if options.alias then ISFluidEmptyAction.complete=ISFluidEmptyAction.update end
    if options.missing then ISFluidContainer.sync=nil end
    if options.foreign then ISFluidUtil.getContainerOwner=function()end end
    local client,server=options.client or false,options.server or false
    isClient=function()return client end;isServer=function()return server end
    getPlayer=function()return f.player end
    Fluid={Water={}};Metabolics={LightDomestic=1,HeavyDomestic=2,MediumWork=3}
    FluidUtil={getTransferActionTimePerLiter=function()return 40 end,getMinTransferActionTime=function()return 20 end}
    local originalInstanceof=instanceof
    instanceof=function(value,name)
        return originalInstanceof(value,name)or type(value)=='table'and
            (name=='InventoryItem'and(value.class=='ComboItem'or value.class=='InventoryContainer')
                or name=='IsoGameCharacter'and value.class=='IsoPlayer')
    end
    getClassSimpleName=function(value)return value.class end
    local player=f.player;player.class='IsoPlayer'
    player.isEquipped=function()return false end;player.setMetabolicTarget=function()end
    local objects={};local root={class='ItemContainer'};player.inventory=root
    root.getParent=function()return player end;root.getType=function()return 'none'end
    root.isExistYet=function()return true end;root.getAcceptItemFunction=function()end;root.getOnlyAcceptCategory=function()end
    root.getContainingItem=function()end
    root.contains=function(self,item)return item.location==self end
    root.getItemById=function(self,id)for _,item in ipairs(objects)do if item.id==id and item.location==self then return item end end end
    root.containsID=function(self,id)return self:getItemById(id)~=nil end
    local actions={}
    player.getCharacterActions=function()return {contains=function(_,native)return actions[native]==true end}end
    local function item()
        local value={class='ComboItem',id=#objects+1,location=root}
        value.getID=function(self)return self.id end;value.getContainer=function(self)return self.location end
        value.getFluidContainer=function(self)return self.fluid end
        value.getWorldItem=function(self)return self.world end;value.getIsCraftingConsumed=function(self)return self.consumed or false end
        value.getEquipParent=function()end;value.getAttachedSlot=function()return -1 end
        value.isInPlayerInventory=function(self)return self.location~=nil end
        value.syncItemFields=function(self)self.syncs=(self.syncs or 0)+1 end
        value.setJobType=function()end;value.setJobDelta=function()end
        objects[#objects+1]=value
        return value
    end
    local function fluid(owner)
        local value={class='FluidContainer',owner=owner,amount=1,capacity=1,adjustments=0,empties=0}
        value.getOwner=function(self)return self.owner end;value.getAmount=function(self)return self.amount end
        value.getCapacity=function(self)return self.capacity end;value.getTransferRate=function()return 1 end
        value.isEmpty=function(self)return self.amount==0 end
        value.canPlayerEmpty=function(self)return not self.cannotEmpty end
        value.isPureFluid=function(self,kind)return kind==Fluid.Water and self.amount>0 and not self.mixed end
        value.isTainted=function(self)return self.tainted or false end;value.isPoisonous=function(self)return self.poisonous or false end
        local properties={getThirstChange=function()return -.5 end}
        for _,name in ipairs({'getFatigueChange','getHungerChange','getStressChange','getUnhappyChange','getCalories','getCarbohydrates',
            'getLipids','getProteins','getAlcohol','getPoison','getFluReduction','getPainReduction','getEnduranceChange','getFoodSicknessChange'})do
            properties[name]=function()return 0 end
        end
        value.getProperties=function()return properties end
        value.adjustAmount=function(self,target)
            self.adjustments=self.adjustments+1
            if self.amount==0 then return end
            target=math.max(0,math.min(self.capacity,target))
            self.amount=target<.0001 and 0 or target -- native per-instance zero pruning
        end
        value.Empty=function(self)self.empties=self.empties+1;self.amount=0 end
        owner.fluid=value;return value
    end
    local bottle=item();local contents=fluid(bottle)
    local API=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/EmptyFluidAction.lua'))()
    local action=ISFluidEmptyAction:new(player,contents)
    local native={class='LuaTimedActionNew',delta=0,started=true}
    native.getTable=function()return action end;native.getJobDelta=function(self)return self.delta end
    native.isStarted=function(self)return self.started end;native.finished=function(self)return self.delta>=1 end
    action.action=native;actions[native]=true
    local s={f=f,API=API,action=action,native=native,item=bottle,fluid=contents,actions=actions,root=root,
        nativeValid=nativeValid,nativeUpdate=nativeUpdate,nativeComplete=nativeComplete,nativeDuration=nativeDuration,itemFactory=item,fluidFactory=fluid}
    s.prune=function()
        -- Actual BaseAction float result for maxTime40 after 50 multiplier0.8 updates.
        native.delta=.9999995231628418
        action:update()
        assert(contents.amount==0 and native.delta<1,'native Lua update must prune before the native timer finishes')
    end
    s.mode=function(c,srv)client,server=c,srv end
    return s
end
local function authorized(s)
    return s.API.authorizes(ISFluidEmptyAction,'isValid',ISFluidEmptyAction.isValid)
        and s.API.authorizes(ISFluidEmptyAction,'updateEmpty',ISFluidEmptyAction.updateEmpty)
end
for _,options in ipairs({{changed='ISFluidEmptyAction.lua'},{changed='ISFluidContainer.lua'},{changed='ISFluidUtil.lua'},
    {changed='ISBaseTimedAction.lua'},{alias=true},{missing=true},{foreign=true}})do
    local s=setup(options)
    assert(not authorized(s)and ISFluidEmptyAction.isValid==s.nativeValid and ISFluidEmptyAction.updateEmpty==s.nativeUpdate,
        'unsupported sources/own bindings must not install the repair')
end
do
    local s=setup();local a=s.action
    assert(authorized(s)and ISFluidEmptyAction.complete==s.nativeComplete and ISFluidEmptyAction.getDuration==s.nativeDuration)
    local duration=a.maxTime;assert(duration==40 and a:getDuration()==duration and a:isValid())
    s.prune()
    assert(not s.nativeValid(a)and a:isValid(),'only own positive->zero progress extends native validity')
    local calls=s.fluid.adjustments
    assert(a:isValid()and s.fluid.adjustments==calls,'validity never replays fluid effects')
    -- A paused/slow tick can revisit zero before time catches up; keep exact own evidence.
    a:update();assert(a:isValid()and s.fluid.adjustments==calls+1)
    s.native.delta=1;assert(a:isValid(),'finished timer still belongs to the live native action')
    assert(a:complete()==true and s.fluid.amount==0 and s.fluid.empties==1 and a.maxTime==duration,
        'native completion remains exact zero, once, with native duration')
    s.actions[s.native]=nil
    assert(not a:isValid(),'removed/stopped native action cannot reuse its old evidence')
end
do
    local s=setup();s.fluid.amount=0
    assert(not s.action:isValid(),'external empty before own update remains invalid')
    s.action:updateEmpty(.9999995)
    assert(not s.action:isValid(),'already-empty update cannot manufacture own-zero evidence')
end
for _,field in ipairs({'mixed','tainted','poisonous'})do
    local s=setup();s.fluid[field]=true;s.prune()
    assert(not s.action:isValid(),'unsafe fluid cannot grant post-pruning validity: '..field)
end
do
    local s=setup();local bag=s.itemFactory();bag.class='InventoryContainer'
    local inside=setmetatable({class='ItemContainer'},{__index=s.root})
    inside.getParent=function()end;inside.getType=function()return 'bag'end
    inside.getContainingItem=function()return bag end;bag.getInventory=function()return inside end
    s.item.location=inside;s.prune()
    assert(s.action:isValid(),'same carried bag ownership supports own-zero validity')
    bag.location=nil
    assert(not s.action:isValid(),'missing bag owner invalidates its nested own-zero evidence')
end
for _,change in ipairs({'missing','replacement','owner','location','permission','wrapper','captured','duration','restart','rewind','stopped','helper','callback'})do
    local s=setup();s.prune()
    if change=='missing'then s.item.fluid=nil
    elseif change=='replacement'then s.fluidFactory(s.item)
    elseif change=='owner'then s.fluid.owner=s.itemFactory()
    elseif change=='location'then s.item.location=nil
    elseif change=='permission'then s.fluid.cannotEmpty=true
    elseif change=='wrapper'then s.action.container=ISFluidContainer:new(s.fluid)
    elseif change=='captured'then s.action.amount=.5
    elseif change=='duration'then s.action.maxTime=41
    elseif change=='restart'then
        local old=s.native;s.native={class='LuaTimedActionNew',delta=old.delta,isStarted=old.isStarted,
            getTable=old.getTable,getJobDelta=old.getJobDelta,started=true};s.action.action=s.native;s.actions[s.native]=true
    elseif change=='rewind'then s.native.delta=.5
    elseif change=='stopped'then s.actions[s.native]=nil
    elseif change=='helper'then ISFluidContainer.sync=function()end
    else s.action.onCompleteFunc=function()error('must not execute')end end
    assert(not s.action:isValid(),'changed/stale state must retain native invalidity: '..change)
end
do
    local s=setup();local calls=0
    ISFluidContainer.__index=function()calls=calls+1;error('foreign dispatch')end
    assert(not authorized(s)and calls==0,'authorizes must reject foreign wrapper dispatch without lookup')
end
do
    local s=setup();s.prune();s.action.container.getOwner=false
    assert(not pcall(function()return s.action:isValid()end),'own nonfunction shadow retains native failure, never repaired validity')
end
do
    local s=setup({client=true});assert(s.action:isValid())
    local adjustments=s.fluid.adjustments;s.fluid.amount=0 -- authoritative update before the completion acknowledgement
    assert(s.action:isValid()and s.fluid.adjustments==adjustments,'active client positive identity survives authoritative zero without consumption')
    s.actions[s.native]=nil;assert(not s.action:isValid(),'client removed identity expires')
    local pending=setup({client=true});pending.native.started=false
    assert(pending.action:isValid());pending.fluid.amount=0;pending.native.started=true
    assert(not pending.action:isValid(),'pending positive observation cannot authorize externally empty start')
end
for _,change in ipairs({'component','wrapper','permission','callback'})do
    local s=setup({client=true});assert(s.action:isValid());s.fluid.amount=0
    if change=='component'then s.fluidFactory(s.item)
    elseif change=='wrapper'then s.action.container=ISFluidContainer:new(s.fluid)
    elseif change=='permission'then s.fluid.cannotEmpty=true
    else s.action.onCancelFunc=function()error('must not execute')end end
    assert(not s.action:isValid(),'client replicated-zero evidence stays tied to exact live inputs: '..change)
end
do
    local s=setup({server=true});assert(authorized(s))
    s.action.netAction={getProgress=function()return .9999995231628418 end}
    s.action:animEvent('emptyFluid',nil)
    assert(s.fluid.amount==0 and s.fluid.adjustments==1 and not s.action:isValid(),
        'server animation remains a single native update; no fabricated client/SP evidence')
end
print('Empty fluid repair: pinned native constructor/update/validity, float self-pruning, active client zero sync, stale/external/missing/helper barriers and unchanged completion/duration passed.')
