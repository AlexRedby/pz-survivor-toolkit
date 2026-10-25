if not NativeActionRoot then print('Drink fluid boundary SKIP (pass --native-action-root).');return end
local originalRawget=rawget
local function ownRawget(owner,key)
    for name,value in pairs(owner)do if name==key then return value end end
end
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
    rawget=originalRawget
    local nativeDerive=options.nativeDerive or options.kahluaRawget
    local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    if nativeDerive then
        f.native('shared/ISBaseObject.lua')
        f.native('shared/TimedActions/ISBaseTimedAction.lua')
    end
    f.native('shared/TimedActions/ISDrinkFluidAction.lua')
    if options.kahluaRawget then
        -- B42.21 KahluaTableImpl.rawget follows its metatable when a key is absent.
        -- Its iterator (and pairs) still enumerates only the table's own keys.
        rawget=function(owner,key)
            local value=ownRawget(owner,key)
            if value~=nil then return value end
            local parent=getmetatable(owner)
            if type(parent)=='table'then return rawget(parent,key)end
        end
    end
    local nativeValid,nativeUpdate=ISDrinkFluidAction.isValid,ISDrinkFluidAction.updateEat
    local nativeComplete,nativeDuration=ISDrinkFluidAction.complete,ISDrinkFluidAction.getDuration
    getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    getGameFilesInput=function(path)
        local text=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
        if options.changed and path:find(options.changed,1,true)then text=text..'-- changed\n'end
        return reader(text)
    end
    local fullnessReads=0
    getModFileReader=function(_,path)
        if path=='media/lua/shared/PZSurvivorToolkit/DrinkFluidAction.lua'then fullnessReads=fullnessReads+1 end
        local text=read(ProjectRoot..'/PZSurvivorToolkit/42/'..path)
        if options.changed and path:find(options.changed,1,true)then text=text..'-- changed\n'end
        return reader(text)
    end
    local savedRequire=require
    require=function(module)
        if module=='PZSurvivorToolkit/DrinkFluidAction' then
            if not options.nativeStart then return assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/'..module..'.lua'))() end
            return
        end
        return savedRequire(module)
    end
    if options.alias then ISDrinkFluidAction.complete=ISDrinkFluidAction.update end
    if options.missing then ISDrinkFluidAction.updateEat=nil end
    if options.inheritedMissing then
        ISBaseTimedAction.updateEat=ISDrinkFluidAction.updateEat
        ISDrinkFluidAction.updateEat=nil
        assert(rawget(ISDrinkFluidAction,'updateEat')==ISBaseTimedAction.updateEat,
            'Kahlua inherited method must remain visible to rawget')
    end
    if options.inheritedTiming then
        ISBaseObject.getJobDelta=ISBaseTimedAction.getJobDelta
        ISBaseTimedAction.getJobDelta=nil
        assert(rawget(ISBaseTimedAction,'getJobDelta')==ISBaseObject.getJobDelta,
            'Kahlua inherited timing must remain visible to rawget')
    end
    if options.foreign then ISDrinkFluidAction.start=function()end end
    if options.foreignTiming then ISBaseTimedAction[options.foreignTiming]=function()return 460 end end
    local client,server=options.client or false,options.server or false
    isClient=function()return client end;isServer=function()return server end
    Fluid={Water={}};MoodleType={FOOD_EATEN=1,UNHAPPY=2,DRUNK=3}
    local originalInstanceof=instanceof
    instanceof=function(value,name)
        return originalInstanceof(value,name)or type(value)=='table'and
            (name=='InventoryItem'and(value.class=='ComboItem'or value.class=='InventoryContainer')
                or name=='IsoGameCharacter'and value.class=='IsoPlayer')
    end
    getClassSimpleName=function(value)return value.class end
    local player=f.player;player.class='IsoPlayer'
    player.isEquipped=function()return false end
    player.getMoodles=function()return {getMoodleLevel=function(_,kind)
        return options.create and (kind==MoodleType.UNHAPPY and 1 or kind==MoodleType.DRUNK and 2) or 0
    end}end
    player.getTimedActionTimeModifier=function()return options.create and .8 or 1 end
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
        value.getEatType=function()return options.popcan and 'popcan' or nil end
        value.syncItemFields=function(self)self.syncs=(self.syncs or 0)+1 end
        objects[#objects+1]=value;return value
    end
    local function fluid(owner)
        local value={class='FluidContainer',owner=owner,amount=options.amount or 1,capacity=1}
        value.getOwner=function(self)return self.owner end;value.getAmount=function(self)return self.amount end
        value.getCapacity=function(self)return self.capacity end
        value.getFilledRatio=function(self)return self.amount/self.capacity end
        value.getCustomDrinkSound=function()return ''end
        value.isEmpty=function(self)return self.amount==0 end
        value.isPureFluid=function(self,kind)return kind==Fluid.Water and self.amount>0 and not self.mixed end
        value.isTainted=function(self)return self.tainted or false end;value.isPoisonous=function(self)return self.poisonous or false end
        local properties={getThirstChange=function()return -.5 end}
        for _,name in ipairs({'getFatigueChange','getHungerChange','getStressChange','getUnhappyChange','getCalories','getCarbohydrates',
            'getLipids','getProteins','getAlcohol','getPoison','getFluReduction','getPainReduction','getEnduranceChange','getFoodSicknessChange'})do
            properties[name]=function()return 0 end
        end
        value.getProperties=function()return properties end
        owner.fluid=value;return value
    end
    local bottle=item();local contents=fluid(bottle)
    local effects,total=0,0
    player.DrinkFluid=function(_,value,ratio,useUtensil)
        assert(useUtensil==false)
        effects=effects+1
        local fluid=value:getFluidContainer()
        local consumed=fluid.amount*ratio;total=total+consumed
        local remaining=fluid.amount-consumed
        fluid.amount=remaining<.0001 and 0 or remaining -- native FluidInstance pruning threshold
    end
    local API=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/DrinkFluidCompletion.lua'))()
    if nativeDerive and not options.inheritedMissing and not options.inheritedTiming then
        if options.kahluaRawget then
            assert(rawget(ISDrinkFluidAction,'__index')==ISBaseTimedAction,
                'Kahlua rawget sees inherited dispatch before the native constructor')
        end
        assert(ownRawget(ISDrinkFluidAction,'__index')==nil,'actual native derive must leave the child dispatch unset before first:new')
        assert(API.authorizes(ISDrinkFluidAction,'isValid',ISDrinkFluidAction.isValid),
            'owned callbacks must be recognized before the first native constructor')
        local previous=ISDrinkFluidAction.start
        local replacement=function(action)return previous(action)end
        ISDrinkFluidAction.start=replacement
        assert(API.adoptStart(previous,replacement,function()return true end),
            'reviewed start adoption must succeed before the first native drink exists')
        assert(ownRawget(ISDrinkFluidAction,'__index')==nil,'adoption must not mutate native class dispatch')
    end
    local action=ISDrinkFluidAction:new(player,bottle,options.percentage or 1)
    if nativeDerive then assert(ownRawget(ISDrinkFluidAction,'__index')==ISDrinkFluidAction,
        'the actual native constructor establishes exact instance dispatch')end
    local native={class='LuaTimedActionNew',delta=0,started=true}
    native.getTable=function()return action end;native.getJobDelta=function(self)return self.delta end
    native.isStarted=function(self)return self.started end;native.finished=function(self)return self.delta>=1 end
    action.action=native;actions[native]=true
    if options.create then
        LuaTimedActionNew={new=function(luaAction,character)
            assert(luaAction==action and character==player);return native
        end}
        action:create() -- actual native create -> adjustMaxTime, including moodles and modifier
        assert(action.maxTime==690,'native adjusted duration must reach the action unchanged')
    end
    local s={API=API,action=action,native=native,item=bottle,fluid=contents,actions=actions,root=root,
        nativeValid=nativeValid,nativeUpdate=nativeUpdate,nativeComplete=nativeComplete,nativeDuration=nativeDuration,itemFactory=item,fluidFactory=fluid}
    s.fullnessReads=function()return fullnessReads end
    s.effects=function()return effects,total end
    s.prune=function(nativeOnly)
        -- Actual BaseAction float: maxTime460, multiplier.8, tick575 current459.9975586.
        native.delta=.999994695186615
        if nativeOnly then nativeUpdate(action,native.delta) else action:updateEat(native.delta) end
        assert(contents.amount==0 and not native:finished(),'native Lua update prunes before native finished')
    end
    return s
end
local function authorized(s)
    return s.API.authorizes(ISDrinkFluidAction,'isValid',ISDrinkFluidAction.isValid)
        and s.API.authorizes(ISDrinkFluidAction,'updateEat',ISDrinkFluidAction.updateEat)
end
-- First reproduce the unchanged native failure, using native constructor/update/isValid.
do local s=setup();s.prune(true);assert(not s.nativeValid(s.action)and not s.action:isValid(),'native pre-finished prune invalidates the drink') end
for _,options in ipairs({{changed='ISDrinkFluidAction.lua'},{changed='ISBaseTimedAction.lua'},{changed='DrinkFluidAction.lua'},
    {alias=true},{missing=true},{kahluaRawget=true,inheritedMissing=true},{kahluaRawget=true,inheritedTiming=true},{foreign=true},{foreignTiming='create'},{foreignTiming='adjustMaxTime'},{foreignTiming='getDuration'}})do
    local s=setup(options)
    assert(not authorized(s)and ISDrinkFluidAction.isValid==s.nativeValid,
        'unsupported sources/own bindings must not install repair')
    local ready,reason=s.API.authorizes(ISDrinkFluidAction,'isValid',ISDrinkFluidAction.isValid)
    assert(ready==false and type(reason)=='string'and reason:match('^initial'),
        'rejected initialization exposes its read-only reason without changing authorization')
end
for _,options in ipairs({{}, {amount=.00015,percentage=.5}, {nativeStart=true}, {popcan=true}, {create=true}, {nativeDerive=true}, {kahluaRawget=true}, {kahluaRawget=true,create=true}})do
    local s=setup(options);local a=s.action
    assert(authorized(s)and ISDrinkFluidAction.complete==s.nativeComplete and ISDrinkFluidAction.getDuration==s.nativeDuration)
    assert(not s.API.authorizes(ISDrinkFluidAction,'start',ISDrinkFluidAction.start),'only owned wrappers are authorized')
    local duration=a.maxTime;assert(a:getDuration()==duration and a:isValid())
    s.prune();assert(not s.nativeValid(a)and a:isValid(),'own positive-to-pruned-zero remains valid')
    local effects,total=s.effects();assert(effects==1 and total>0)
    a:updateEat(s.native.delta);assert(a:isValid()and s.effects()==effects,'zero ticks never replay consumption')
    s.native.delta=1;assert(a:isValid())
    assert(a:complete()==true and a:complete()==true and s.effects()==effects and a.maxTime==duration,
        'native completion is idempotent at zero, keeps duration and consumes once')
    s.actions[s.native]=nil;assert(not a:isValid(),'completed/removed native identity expires')
end
do
    local s=setup({nativeDerive=true});s.prune()
    rawset(ISDrinkFluidAction,'__index',nil)
    assert(s.API.authorizes(ISDrinkFluidAction,'isValid',ISDrinkFluidAction.isValid),
        'class-level source ownership recognizes native preconstruction dispatch')
    assert(not ISDrinkFluidAction.isValid(s.action),
        'an actual action still requires exact self dispatch before zero evidence is accepted')
end
for _,change in ipairs({'drink','timing'})do
    local s=setup({kahluaRawget=true});s.prune();assert(s.action:isValid())
    if change=='drink'then
        ISBaseTimedAction.updateEat=ISDrinkFluidAction.updateEat
        ISDrinkFluidAction.updateEat=nil
        assert(rawget(ISDrinkFluidAction,'updateEat')==ISBaseTimedAction.updateEat)
    else
        ISBaseObject.getJobDelta=ISBaseTimedAction.getJobDelta
        ISBaseTimedAction.getJobDelta=nil
        assert(rawget(ISBaseTimedAction,'getJobDelta')==ISBaseObject.getJobDelta)
    end
    assert(not authorized(s)and not s.action:isValid(),
        'inherited same callback cannot replace a required owned member: '..change)
end
do
    local s=setup({kahluaRawget=true});s.prune()
    rawset(ISDrinkFluidAction,'__index',nil)
    assert(rawget(ISDrinkFluidAction,'__index')==ISBaseTimedAction)
    assert(s.API.authorizes(ISDrinkFluidAction,'isValid',ISDrinkFluidAction.isValid)
        and not ISDrinkFluidAction.isValid(s.action),
        'Kahlua inherited dispatch is acceptable before construction, never for an existing action')
end
for _,field in ipairs({'item','character','fluidContainer','action','toolkitDrinkFluidEvidence'})do
    local s=setup({kahluaRawget=true});s.prune();assert(s.action:isValid())
    local value=ownRawget(s.action,field)
    assert(value~=nil,'owned fixture field missing: '..field)
    ISDrinkFluidAction[field]=value;rawset(s.action,field,nil)
    assert(rawget(s.action,field)==value,'Kahlua inherited action field must stay visible to rawget')
    assert(not s.action:isValid(),'inherited state cannot replace owned action evidence: '..field)
end
for _,nativeStart in ipairs({false,true})do
    local s=setup({nativeStart=nativeStart});local a=s.action
    local expected=nativeStart and 0 or 1
    assert(s.fullnessReads()==expected,'only an owned fullness callback needs one initial source pin')
    assert(a:isValid());s.native.delta=.5;a:updateEat(.5);assert(a:isValid())
    s.prune();assert(a:isValid());s.native.delta=1;assert(a:complete())
    assert(s.fullnessReads()==expected,'progress, validation and completion never reread the captured fullness source')
end
do
    local s=setup({create=true});s.prune()
    local begin,stop=ISBaseTimedAction.begin,ISBaseTimedAction.stop
    ISBaseTimedAction.begin=function(action)return begin(action)end
    ISBaseTimedAction.stop=function(action)return stop(action)end
    assert(authorized(s)and s.action:isValid(),'later queue begin/stop wrappers leave captured native timing provenance intact')
end
do
    local s=setup({percentage=.5});s.native.delta=.5;s.action:updateEat(.5)
    assert(s.fluid.amount==.75 and s.action:isValid()and s.effects()==1,'ordinary partial drinking stays native')
    s.native.delta=1;s.action:complete();assert(s.fluid.amount==.5 and s.effects()==2)
end
do
    local s=setup();s.fluid.amount=0
    assert(not s.action:isValid());s.action:updateEat(.999994695186615)
    assert(not s.action:isValid(),'external empty cannot manufacture evidence')
end
for _,field in ipairs({'mixed','tainted','poisonous'})do
    local s=setup();s.fluid[field]=true;s.prune()
    assert(not s.action:isValid(),'unsafe water remains invalid: '..field)
end
for _,change in ipairs({'missing','replacement','owner','location','world','subclass','duration','percentage','startRatio','endRatio',
    'targetConsumedRatio','capacity','tainted','poisonous','restart','rewind','stopped','table','pending','helper','create','adjustMaxTime','baseDuration','callback','instance','alias','start'})do
    local s=setup();s.prune();assert(s.action:isValid())
    if change=='missing'then s.item.fluid=nil
    elseif change=='replacement'then s.fluidFactory(s.item)
    elseif change=='owner'then s.fluid.owner=s.itemFactory()
    elseif change=='location'then s.item.location=nil
    elseif change=='world'then s.item.world={getFluidContainer=function()return s.fluid end}
    elseif change=='subclass'then s.item.class='Food'
    elseif change=='duration'then s.action.maxTime=461
    elseif change=='percentage'then s.action.percentage=.5
    elseif change=='startRatio'then s.action.startRatio=.9
    elseif change=='endRatio'then s.action.endRatio=.1
    elseif change=='targetConsumedRatio'then s.action.targetConsumedRatio=.5
    elseif change=='capacity'then s.fluid.capacity=2
    elseif change=='tainted'then s.fluid.tainted=true
    elseif change=='poisonous'then s.fluid.poisonous=true
    elseif change=='restart'then
        local old=s.native;s.native={class='LuaTimedActionNew',delta=old.delta,isStarted=old.isStarted,
            getTable=old.getTable,getJobDelta=old.getJobDelta,started=true};s.action.action=s.native;s.actions[s.native]=true
    elseif change=='rewind'then s.native.delta=.999999;assert(s.action:isValid());s.native.delta=.999995
    elseif change=='stopped'then s.actions[s.native]=nil
    elseif change=='table'then s.native.getTable=function()return {}end
    elseif change=='pending'then s.native.started=false
    elseif change=='helper'then ISBaseTimedAction.getJobDelta=function()return 1 end
    elseif change=='create'then ISBaseTimedAction.create=function()end
    elseif change=='adjustMaxTime'then ISBaseTimedAction.adjustMaxTime=function()return 460 end
    elseif change=='baseDuration'then ISBaseTimedAction.getDuration=function()return 460 end
    elseif change=='callback'then s.action.onCompleteFunc=function()error('must not execute')end
    elseif change=='instance'then s.action.updateEat=false
    elseif change=='alias'then ISDrinkFluidAction.complete=ISDrinkFluidAction.update
    else ISDrinkFluidAction.start=function()end end
    assert(not s.action:isValid(),'changed/stale state retains native invalidity: '..change)
end
do
    local s=setup();s.prune();s.action:updateEat(.25)
    assert(not s.action:isValid(),'a mismatched update cannot retain prior evidence')
end
do
    local s=setup({client=true});assert(s.action:isValid());local calls=s.effects();s.fluid.amount=0
    assert(s.action:isValid()and s.effects()==calls,'client authoritative zero before Done remains valid without effects')
    s.native.delta=.1;assert(s.action:isValid());s.native.delta=.05;assert(not s.action:isValid(),'client progress must stay monotone')
    local pending=setup({client=true});pending.native.started=false;assert(pending.action:isValid())
    pending.fluid.amount=0;pending.native.started=true;assert(not pending.action:isValid(),'pending positive cannot authorize external zero')
end
for _,change in ipairs({'component','callback','duration','owner'})do
    local s=setup({client=true});assert(s.action:isValid());s.fluid.amount=0
    if change=='component'then s.fluidFactory(s.item)
    elseif change=='callback'then s.action.onCancelFunc=function()end
    elseif change=='duration'then s.action.maxTime=461
    else s.fluid.owner=s.itemFactory()end
    assert(not s.action:isValid(),'client evidence remains exact: '..change)
end
do
    local s=setup({server=true});s.prune()
    assert(not s.action:isValid()and s.effects()==1,'server delegates native effects and never creates zero evidence')
end
for _,change in ipairs({'start','timing','dispatch','extra'})do
    local s=setup();local calls=s.effects()
    if change=='start'then ISDrinkFluidAction.start=function()end
    elseif change=='timing'then ISBaseTimedAction.adjustMaxTime=function()return 460 end
    elseif change=='dispatch'then ISDrinkFluidAction.__index={}
    else ISDrinkFluidAction.fixtureUnknown=function()end end
    local ready,reason=s.API.authorizes(ISDrinkFluidAction,'isValid',ISDrinkFluidAction.isValid)
    local expected=change=='start'and 'drink-binding:start'or change=='timing'and 'base-binding:adjustMaxTime'
        or change=='dispatch'and 'drink-dispatch'or 'drink-extra:fixtureUnknown'
    assert(ready==false and reason:sub(1,#expected)==expected and s.effects()==calls,
        'live rejection reports the exact unchanged guard without executing fluid effects: '..change)
end
do
    local s=setup();local old=ISDrinkFluidAction.start;local alive=true
    local replacement=function(action)return old(action)end
    ISDrinkFluidAction.start=replacement
    assert(not authorized(s))
    assert(not s.API.adoptStart(function()end,replacement,function()return true end))
    assert(not s.API.adoptStart(old,function()end,function()return true end))
    assert(s.API.adoptStart(old,replacement,function()return alive end)and authorized(s),'reviewed installed start is adopted')
    s.prune();assert(s.action:isValid());alive=false
    assert(not authorized(s)and not s.action:isValid(),'adopted start predecessor guard stays live')
end
do
    local s=setup();local old=ISDrinkFluidAction.start
    local replacement=function(action)return old(action)end
    ISDrinkFluidAction.start=replacement
    assert(s.API.adoptStart(old,replacement,function()return true end));s.prune()
    ISDrinkFluidAction.start=old
    assert(not authorized(s)and not s.action:isValid(),'replacement identity stays live after adoption')
end
rawget=originalRawget
TestDrinkFluidBoundaryPassed=true
print('Drink fluid boundary: native pre-finished prune reproduced; SP, tiny half, client acknowledgement, unchanged effects/duration/completion, source/identity/stale guards, Kahlua own-member checks and start adoption passed.')
