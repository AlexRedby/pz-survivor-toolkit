if not NativeActionRoot then print('Item edit adapters SKIP (pass --native-action-root).');return end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r','') end
    local f=assert(io.open(path));local s=f:read('*a');f:close();return s:gsub('\r','')
end
local function reader(text)
    local position=1
    return {close=function()end,readLine=function()
        if position>#text then return end
        local boundary=text:find('\n',position,true)or #text+1
        local line=text:sub(position,boundary-1);position=boundary+1;return line
    end}
end
local function setup(changed,foreignMerge,alias,missing)
    local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    f.native('shared/TimedActions/ISTransferAction.lua');f.native('shared/TimedActions/ISDrinkFluidAction.lua')
    f.native('shared/TimedActions/ISEatFoodAction.lua')
    f.native('shared/RadioCom/ISRadioAction.lua')
    if alias=='drink-native' then ISDrinkFluidAction.complete=ISDrinkFluidAction.isValid
    elseif alias=='drink-base' then ISDrinkFluidAction.complete=ISBaseTimedAction.perform
    elseif alias=='base' then ISBaseTimedAction.perform=ISBaseTimedAction.stop end
    isClient,isServer=function()return false end,function()return false end
    isDebugEnabled=function()return false end
    getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    getGameFilesInput=function(path)
        local text=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
        if changed and path:find(changed,1,true)then text=text..'-- changed source\n'end
        return reader(text)
    end
    getModFileReader=function(_,path)return reader(read(ProjectRoot..'/PZSurvivorToolkit/42/'..path))end
    getTimestampMs=function()return 1 end;getCore=function()return {getGameMode=function()return 'Sandbox'end}end
    CharacterTrait={DEXTROUS=1,ALL_THUMBS=2};MoodleType={FOOD_EATEN=1};Fluid={Water={}}
    ItemTag={SMOKABLE='smokable',SPOON='spoon',FORK='fork',ALREADY_COOKED='alreadycooked'}
    ItemContainer={floatingPointCorrection=function(value)return math.floor(value*100+0.5)/100 end}
    round=function(value)return value end
    f.player.class='IsoPlayer'
    f.player.hasTrait=function()return false end;f.player.isWearingAwkwardGloves=function()return false end
    f.player.isEquipped=function()return false end;f.player.removeAttachedItem=function()end
    f.player.setIsFarming=function()end;f.player.getVehicle=function()end
    f.player.getOverlaySprite=function()end
    f.player.getMoodles=function()return {getMoodleLevel=function()return 0 end}end
    local damage={timer=0}
    damage.getHealthFromFoodTimer=function(self)return self.timer end
    damage.getStandardHealthFromFoodTime=function()return 1800 end
    f.player.getBodyDamage=function()return damage end
    f.player.getEmitter=function()return {isPlaying=function()return false end,playSound=function()return 1 end}end
    local square={TreatAsSolidFloor=function()return true end,isSolid=function()return false end,isSolidTrans=function()return false end,
        getTotalWeightOfItemsOnFloor=function()return 0 end}
    f.player.getCurrentSquare=function()return square end
    ISLogSystem={logAction=function()end};ItemPicker={updateOverlaySprite=function()end}
    local baseInstanceof=instanceof
    instanceof=function(value,kind)return baseInstanceof(value,kind)or type(value)=='table'and
        (kind=='IsoGameCharacter'and value.class=='IsoPlayer'or kind=='InventoryItem'and (value.class=='Food'or value.class=='HandWeapon'))end
    local knownItems={}
    local function container(owner)
        local c={class='ItemContainer',owner=owner,temperature=1}
        c.getTemperature=function(self)return self.temperature end
        c.getContainingItem=function(self)return self.owner end;c.getType=function(self)return self.owner and 'bag'or 'none'end
        c.getParent=function(self)return not self.owner and f.player or nil end
        c.isInCharacterInventory=function()return true end;c.isExistYet=function()return true end
        c.getAcceptItemFunction=function()end;c.getOnlyAcceptCategory=function()end
        c.getCapacityWeight=function(self)return self.load or 0 end;c.getEffectiveCapacity=function(self)return self.capacity or 50 end;c.getMaxWeight=function()return 50 end
        c.isVehicleSeat=function()return false end;c.contains=function(self,item)return item.container==self end
        c.getItemById=function(self,id)for _,item in ipairs(knownItems)do if item.id==id and item.container==self then return item end end end
        c.hasRoomFor=function()return true end;c.isRemoveItemAllowed=function()return true end;c.isItemAllowed=function()return true end
        c.isInside=function()return false end;c.getPutSound=function()end
        c.setDrawDirty=function()end;c.setHasBeenLooted=function()end
        c.getFirstTagEvalRecurse=function()end;c.getFirstTypeEvalRecurse=function()end
        c.DoRemoveItem=function(_,item)item.container=nil end;c.AddItem=function(self,item)item.container=self;return item end
        return c
    end
    local root=container();f.player.inventory=root
    local bag=f.item('Base.Bag_Schoolbag');bag.class='InventoryContainer';bag.getContainer=function()return root end
    bag.getMaxItemSize=function(self)return self.maxItemSize or 0 end
    local bagInventory=container(bag);bag.getInventory=function()return bagInventory end
    local function item()
        local value=f.item('Base.WaterBottle');value.container=bagInventory
        value.getContainer=function(self)return self.container end;value.getWorldItem=function()end
        value.isOnGroundOrInsideBagOnSquare=function()return false end
        value.getIsCraftingConsumed=function(self)return self.consumed or false end
        value.getEquipParent=function()end;value.getAttachedSlot=function()return -1 end
        value.getType=function()return 'WaterBottle'end;value.getActualWeight=function()return 1 end
        value.getUnequippedWeight=function()return 1 end;value.getWeight=function()return 1 end
        value.isFavorite=function()return false end;value.setJobDelta=function()end
        value.getFluidContainer=function(self)return self.fluid end;value.getEatType=function()return 'bottle'end
        value.syncItemFields=function()end
        knownItems[#knownItems+1]=value
        return value
    end
    local water=item()
    local function food()
        local value=item();value.class='Food';value.fluid=nil;value.container=root;value.hunger=-0.4;value.base=-0.4
        value.getFullType=function()return 'Base.Cereal'end;value.getType=function()return 'Cereal'end
        value.getEatType=function()return 'EatBox'end;value.getCustomEatSound=function()end
        value.getHungChange=function(self)return self.hunger end
        value.getHungerChange=function(self)return self.hunger*(self:isCooked()and 1.3 or 1)end
        value.getBaseHunger=function(self)return self.base end
        value.hasTag=function(self,tag)return self.tags and self.tags[tag]or false end
        value.heat=1;value.getHeat=function(self)return self.heat end
        value.isCooked=function(self)return self.cooked or false end
        value.isCookable=function(self)return self.cookable or false end
        value.isFertilized=function(self)return self.fertilized or false end
        value.getEatTime=function()return 0 end;value.getUses=function()return 1 end
        value.isDisappearOnUse=function()return true end
        for _,name in ipairs({'getReplaceOnUse','getOnEat','getOnCooked','getReplaceOnCooked','getReplaceOnRotten','getRequireInHandOrInventory','getCustomMenuOption'})do value[name]=function()end end
        for _,name in ipairs({'isKeepOnDeplete','isTainted','isAlcoholic','isBurnt','isRotten','isbDangerousUncooked'})do value[name]=function()return false end end
        value.getPoisonPower=function()return 0 end;value.getReduceInfectionPower=function()return 0 end
        local script={isCantEat=function()return false end,getOpeningRecipe=function()end,getOnBreak=function()end,
            getReplaceOnUse=function()end,getReplaceOnDeplete=function()end}
        value.getScriptItem=function()return script end
        return value
    end
    local function utensil(kind,location)
        local value=item();value.class='HandWeapon';value.container=location or root;value.utensil=kind
        value.getType=function()return kind end;value.getFullType=function()return 'Base.'..kind end
        value.hasTag=function(self,tag)return self.utensil=='Spoon'and tag==ItemTag.SPOON or self.utensil=='Fork'and tag==ItemTag.FORK end
        value.isBroken=function(self)return self.broken or false end
        return value
    end
    -- The real native Lua constructor supplies predicateNotBroken. Keep the
    -- inventory fixture explicit: root entries precede the one carried bag.
    local function carriedMatch(predicate)
        for _,location in ipairs({root,bagInventory})do
            for _,value in ipairs(knownItems)do
                if value.container==location and predicate(value)then return value end
            end
        end
    end
    root.getFirstTagEvalRecurse=function(_,tag,predicate)
        return carriedMatch(function(value)return value.hasTag and value:hasTag(tag)and predicate(value)end)
    end
    root.getFirstTypeEvalRecurse=function(_,kind,predicate)
        return carriedMatch(function(value)return value:getFullType()==kind and predicate(value)end)
    end
    local properties={getThirstChange=function()return -0.1 end}
    for _,name in ipairs({'getFatigueChange','getHungerChange','getStressChange','getUnhappyChange','getCalories','getCarbohydrates',
        'getLipids','getProteins','getAlcohol','getPoison','getFluReduction','getPainReduction','getEnduranceChange','getFoodSicknessChange'})do
        properties[name]=function()return 0 end
    end
    local fluid={class='FluidContainer',amount=2,capacity=4}
    fluid.getOwner=function()return water end;fluid.getAmount=function(self)return self.amount end;fluid.getCapacity=function(self)return self.capacity end
    fluid.getFilledRatio=function(self)return self.amount/self.capacity end;fluid.getProperties=function()return properties end
    fluid.isPureFluid=function(self,kind)return kind==Fluid.Water and not self.mixed end
    fluid.isTainted=function(self)return self.tainted or false end;fluid.isPoisonous=function(self)return self.poisonous or false end
    fluid.isEmpty=function(self)return self.amount<=0 end;fluid.getCustomDrinkSound=function()return ''end
    water.fluid=fluid
    local drinks=0
    f.player.DrinkFluid=function(_,value,delta,useUtensil)
        assert(value==water and useUtensil==false);drinks=drinks+1
        fluid.amount=fluid.amount*(1-math.max(0,math.min(1,delta)))
        -- Java FluidContainer.removeFluidInstanceIfEmpty uses PZMath.equal's
        -- strict absolute tolerance, rather than retaining every positive double.
        if math.abs(fluid.amount)<0.0001 then fluid.amount=0 end
    end
    if missing then
        local owner=assert(_G[missing.owner])
        assert(type(rawget(owner,missing.name))=='function','fixture must remove a native own method')
        owner[missing.name]=nil
        if missing.inherited then assert(type(owner[missing.name])=='function','fixture must retain an inherited fallback')end
    end
    if foreignMerge then ISInventoryTransferAction.canMergeAction=function()error('foreign preloaded merge must not execute')end end
    f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
    local adapters=f.project('ActionQueueItemEditAdapters');local model=f.project('ActionQueueEditModel')
    local radio=f.project('ActionQueueEditAdapters')
    local previousRequire=require
    require=function(name)
        if name=='PZSurvivorToolkit/ActionQueueItemEditAdapters'then return adapters end
        if name=='PZSurvivorToolkit/ActionQueueEditModel'then return model end
        if name=='PZSurvivorToolkit/ActionQueueEditAdapters'then return radio end
        return previousRequire(name)
    end
    local policy=f.project('ActionQueuePolicy')
    local function transfer(value,source,destination)
        local action=ISInventoryTransferAction:new(f.player,value or water,source or bagInventory,destination or root)
        action.toolkitQueueOperation={};return action
    end
    local function drink(percentage)
        local action=ISDrinkFluidAction:new(f.player,water,percentage or 0.5);action.toolkitQueueOperation={};return action
    end
    local function eat(value,percentage)
        local action=ISEatFoodAction:new(f.player,value,percentage or 0.5);action.toolkitQueueOperation={};return action
    end
    local function runTransfer(action)
        local q=f.queue(action);q.onCompleted=function()end
        action.action={stopTimedActionAnim=function()end,setLoopedAction=function()end,setTime=function()end}
        assert(action:isValid());action:perform();action.action=nil
    end
    return {f=f,adapters=adapters,model=model,policy=policy,root=root,bag=bag,bagInventory=bagInventory,water=water,fluid=fluid,
        properties=properties,item=item,food=food,utensil=utensil,eat=eat,damage=damage,transfer=transfer,drink=drink,runTransfer=runTransfer,drinks=function()return drinks end}
end
do
    local s=setup();local pickup=s.transfer();local restore=s.transfer(nil,s.root,s.bagInventory)
    local a,b=assert(s.adapters.transfer(pickup)),assert(s.adapters.transfer(restore))
    assert(a.capacity=='external'and a.resources[1].facts.item==s.water and a.resources[1].facts.fluid==s.fluid)
    assert(s.model.evaluate({{action=pickup,edit=a},{action=restore,edit=b}}).status=='allowed')
    assert(s.model.evaluate({{action=restore,edit=b},{action=pickup,edit=a}}).status=='allowed','destination no-op can precede pickup')
    assert(s.water.container==s.bagInventory and s.fluid.amount==2,'inspection must not mutate native state')
    s.runTransfer(restore);assert(s.water.container==s.bagInventory,'actual native return is an idempotent no-op')
    s.runTransfer(pickup);assert(s.water.container==s.root,'actual native pickup executes after the no-op')
    local duplicate=s.transfer();assert(s.adapters.transfer(duplicate));s.runTransfer(duplicate)
    assert(s.water.container==s.root,'redundant actual native pickup does not duplicate or move item')
    local other=s.item();s.water.container=other
    assert(not s.adapters.transfer(s.transfer()),'third-location missing source is not an unconditional move')
end
do
    for _,amount in ipairs({0.00015,0.0002,0.000075})do
        local s=setup();s.water.container=s.root;s.fluid.amount=amount
        local first,second=s.drink(),s.drink()
        local a,b=assert(s.adapters.drink(first)),assert(s.adapters.drink(second))
        assert(a.resources[2].effects[1].set==0,'pruned/boundary endpoints cannot promise remaining water')
        assert(s.model.evaluate({{action=first,edit=a},{action=second,edit=b}}).status=='denied',
            'native epsilon pruning must block a downstream nonempty requirement')
        assert(first:complete())
        if amount~=0.0002 then
            assert(s.fluid.amount==0 and not second:isValid(),'actual native complete prunes the modeled tiny remainder')
        end
    end
    local s=setup();s.water.container=s.root;s.fluid.amount=0.001
    local first,second=s.drink(),s.drink()
    assert(s.model.evaluate({{action=first,edit=assert(s.adapters.drink(first))},
        {action=second,edit=assert(s.adapters.drink(second))}}).status=='allowed',
        'endpoints safely above pruning keep SP captured-ratio continuation')
end
do
    local s=setup();local pickup=s.transfer();local drink=s.drink();local a,b=s.adapters.transfer(pickup),s.adapters.drink(drink)
    assert(a and b and b.capacity=='external')
    assert(s.model.evaluate({{action=pickup,edit=a},{action=drink,edit=b}}).status=='allowed')
    assert(s.model.evaluate({{action=drink,edit=b},{action=pickup,edit=a}}).status=='denied','drinking still requires native direct root location')
    s.runTransfer(pickup)
    s.fluid.amount=1.5
    assert(drink:complete());assert(math.abs(s.fluid.amount-1)<0.000001,'SP native drink consumes to captured end ratio, not a fresh percentage')
    local next=s.drink();assert(s.adapters.drink(next))
    local before=s.fluid.amount;assert(next:complete()and s.fluid.amount<before)
    assert(s.drinks()==2)
    local half=s.drink();local first=s.adapters.drink(half)
    isClient=function()return true end
    local host=s.adapters.drink(half);assert(host and host.resources[2].effects[1].set==0)
    assert(host.resources[2].effects[2].scale==0.5)
    assert(s.model.evaluate({{action=half,edit=host},{action=next,edit=host}}).status=='denied','Host uncertain consumption cannot promise a second drink')
    isClient=function()return false end
    assert(first)
end
do
    local s=setup()
    s.f.project('ActionQueueLabels');s.f.project('ActionQueue')
    local head=s.f.action(ISReadABook,{item=s.item()})
    local pickup,restore=s.transfer(),s.transfer(nil,s.root,s.bagInventory)
    assert(s.adapters.transfer(pickup),'actual Queue begin/stop installation retains transfer source proof')
    local q=s.f.queue(head,pickup,restore)
    assert(s.policy.evaluateMove(q,restore,pickup).allowed,'actual policy permits native idempotent return before pickup')
    local drink=s.drink()
    q=s.f.queue(head,pickup,drink,restore)
    assert(s.adapters.drink(drink),'actual Queue inherited hooks retain water source proof')
    assert(not s.policy.evaluateCancel(q,pickup,true).allowed,'removing required pickup cannot leave drinking in the bag')
    q=s.f.queue(head,pickup,restore)
    s.root.load,s.root.capacity=50,50
    local decision=s.policy.evaluateMove(q,restore,pickup)
    assert(not decision.allowed and decision.reason=='container_capacity','external capacity gate remains mandatory after successful location proof')
    assert(s.policy.evaluateCancel(q,restore,true).allowed,'canceling a tail return does not revalidate an unchanged over-capacity prefix')
    s.root.load=nil
    for _,name in ipairs({'begin','stop','perform'})do
        local previous=ISBaseTimedAction[name];ISBaseTimedAction[name]=function()error('foreign base helper must not execute')end
        assert(not s.adapters.transfer(pickup)and not s.adapters.drink(drink),'direct base calls retain live helper trust')
        ISBaseTimedAction[name]=previous
    end
end
do
    local s=setup(nil,true)
    assert(not s.adapters.transfer(s.transfer()),'owned merge wrapper cannot hide an unreviewed captured delegate')
end
for _,alias in ipairs({'drink-native','drink-base','base'})do
    local s=setup(nil,nil,alias)
    assert(not s.adapters.drink(s.drink()),'preloaded native/base method aliases cannot acquire a consumption effect: '..alias)
end
for _,missing in ipairs({
    {owner='ISInventoryTransferAction',name='transferItem',adapter='transfer'},
    {owner='ISTransferAction',name='transferItem',adapter='transfer'},
    {owner='ISTransferAction',name='removeItemOnCharacter',adapter='transfer'},
    {owner='ISDrinkFluidAction',name='complete',adapter='drink'},
    {owner='ISDrinkFluidAction',name='updateEat',adapter='drink'},
    {owner='ISInventoryTransferAction',name='start',adapter='transfer',inherited=true},
    {owner='ISDrinkFluidAction',name='perform',adapter='drink',inherited=true},
    {owner='ISDrinkFluidAction',name='isValid',adapter='drink',inherited=true},
    {owner='ISBaseTimedAction',name='perform',adapter='transfer'},
    {owner='ISBaseTimedAction',name='adjustMaxTime',adapter='drink'},
    {owner='ISBaseTimedAction',name='create',adapter='transfer'},
})do
    local s=setup(nil,nil,nil,missing)
    local action=missing.adapter=='transfer'and s.transfer()or s.drink()
    assert(not s.adapters[missing.adapter](action),'preloaded deletion cannot acquire effects: '..missing.owner..'.'..missing.name)
end
do
    local s=setup();local restore=s.transfer(nil,s.root,s.bagInventory)
    s.bag.maxItemSize=0.5
    assert(not s.adapters.transfer(restore),'native bag maximum item weight is an independent transfer prerequisite')
    s.bag.maxItemSize=1
    assert(s.adapters.transfer(restore),'maximum item weight is inclusive')
end
do
    local s=setup();local action=s.transfer()
    for _,field in ipairs({'isValid','start','perform','transferItem','checkQueueList'})do
        local previous=ISInventoryTransferAction[field];ISInventoryTransferAction[field]=function()error('must not execute changed helper')end
        assert(not s.adapters.transfer(action));ISInventoryTransferAction[field]=previous
    end
    local previous=ISTransferAction.transferItem;ISTransferAction.transferItem=function()error('must not execute changed lowlevel helper')end
    assert(not s.adapters.transfer(action));ISTransferAction.transferItem=previous
    for _,field in ipairs({'action','started','transactionId'})do
        local original=action[field];action[field]=field=='transactionId'and 1 or true
        assert(not s.adapters.transfer(action));action[field]=original
    end
    action.queueList[1].items[2]=s.item();assert(not s.adapters.transfer(action));action.queueList[1].items[2]=nil
    action.queueList[1].items[3]=s.item();assert(not s.adapters.transfer(action));action.queueList[1].items[3]=nil
    action.queueList.extra=true;assert(not s.adapters.transfer(action));action.queueList.extra=nil
    action.queueList[1].extra=true;assert(not s.adapters.transfer(action));action.queueList[1].extra=nil
    action.queueList[2]=action.queueList[1];assert(not s.adapters.transfer(action));action.queueList[2]=nil
    s.water.consumed=true;assert(not s.adapters.transfer(action));s.water.consumed=false
    s.bag.getContainer=function()return s.bagInventory end;assert(not s.adapters.transfer(action))
    s.bag.getContainer=function()return s.root end
    local drink=s.drink()
    for _,field in ipairs({'percentage','startRatio','endRatio','targetConsumedRatio','consumedRatio'})do
        local original=drink[field];drink[field]=0/0;assert(not s.adapters.drink(drink));drink[field]=original
    end
    drink.targetConsumedRatio=drink.targetConsumedRatio+0.0000001
    assert(not s.adapters.drink(drink),'captured native target fields require exact constructor agreement')
    drink.targetConsumedRatio=drink.startRatio-drink.endRatio
    for _,field in ipairs({'mixed','tainted','poisonous'})do s.fluid[field]=true;assert(not s.adapters.drink(drink));s.fluid[field]=nil end
    local original=s.properties.getCalories;s.properties.getCalories=function()return 1 end
    assert(not s.adapters.drink(drink));s.properties.getCalories=original
    drink.useUtensil=true;assert(not s.adapters.drink(drink));drink.useUtensil=false
    drink.fluidContainer={};assert(not s.adapters.drink(drink))
    assert(s.drinks()==0 and s.fluid.amount==2,'failed inspection cannot execute native consumption')
end
do
    local s=setup();local action=s.transfer();local previous,replacement={},{}
    local live=true
    local function guard()return live end
    for _,name in ipairs({'isValid','start','perform','stop'})do
        local callback=ISInventoryTransferAction[name];previous[name]=callback
        replacement[name]=function(...)return callback(...)end
        ISInventoryTransferAction[name]=replacement[name]
    end
    assert(not s.adapters.transfer(action),'an installed wrapper alone has no edit permission')
    assert(s.policy.adoptTransferMethods(previous,replacement,guard))
    assert(s.adapters.transfer(action),'successful Policy adoption bridges the exact approved method chain')
    local native=ISTransferAction.transferItem
    local wrapped=function(...)return native(...)end
    ISTransferAction.transferItem=wrapped
    assert(not s.adapters.transfer(action))
    assert(s.policy.adoptTransferItemHelper(native,wrapped,guard)and s.adapters.transfer(action),'approved lowlevel delegate retains transfer proof')
    live=false;assert(not s.adapters.transfer(action),'an older delegate guard cannot be dropped by later adoption')
    live=true
    s.policy.installContracts()
    local starts={[ISEatFoodAction]=ISEatFoodAction.start,[ISDrinkFluidAction]=ISDrinkFluidAction.start}
    for owner,callback in pairs(starts)do owner.start=function(...)return callback(...)end end
    assert(s.policy.adoptConsumeStarts(starts,guard))
    assert(s.adapters.drink(s.drink()),'approved native drink start wrapper retains water contract')
    live=false;assert(not s.adapters.drink(s.drink()))
end
for _,source in ipairs({'ISInventoryTransferAction.lua','ISTransferAction.lua','ISBaseTimedAction.lua'})do
    local s=setup(source);assert(not s.adapters.transfer(s.transfer()),'changed source cannot prove transfer: '..source)
end
if NativeWishlistWorkshopRoot then
    local s=setup()
    local path=NativeWishlistWorkshopRoot..'/2769706949/mods/P4TidyUpMeister/42.20/media/lua/client/P4TidyUpMeister.lua'
    local source=read(path)
    local proof=require('PZSurvivorToolkit/SourceProof')
    local modReader=getModFileReader
    getModFileReader=function(id,file)
        if id=='P4TidyUpMeister'and file=='media/lua/client/P4TidyUpMeister.lua'then return reader(source)end
        return modReader(id,file)
    end
    assert(proof.matches('media/lua/client/P4TidyUpMeister.lua',389269229,'P4TidyUpMeister',true),'actual selected P4 source must match its pin')
    local previousOffset,previousTransfer=ISTransferAction.GetDropItemOffset,ISTransferAction.transferItem
    local private={restoreFloor={},debugLog=function()end,itemLabel=function()return 'water'end,
        registerActionPolicy=function()end,registerWornItemReplacement=function()end}
    local offset=assert(source:match('(P4TidyUpMeister%.ISTransferAction_GetDropItemOffset =.-\nend)'))
    local transfer=assert(source:match('(P4TidyUpMeister%.ISTransferAction_transferItem =.-\nend)'))
    local public=assert(source:match('(_G%.P4TidyUpMeister = %b{})'))
    -- Preserve the upstream lexical owner: public compatibility API does not
    -- expose the private captured delegates used by these pinned wrappers.
    assert(loadstring('local P4TidyUpMeister = ...\n'..public..'\n'..offset..'\n'..transfer,'@P4TidyUpMeister.lua'))(private)
    local owner=P4TidyUpMeister
    local registerAction,registerWorn=owner.registerActionPolicy,owner.registerWornItemReplacement
    assert(owner.ISTransferAction_GetDropItemOffset==nil and owner.ISTransferAction_transferItem==nil,
        'selected source keeps captured delegates private')
    local replacementOffset,replacementTransfer=ISTransferAction.GetDropItemOffset,ISTransferAction.transferItem
    local action=s.transfer()
    assert(not s.adapters.transfer(action),'real unadopted P4 lowlevel pair revokes the native transfer contract')
    local function guard()
        return P4TidyUpMeister==owner and owner.registerActionPolicy==registerAction
            and owner.registerWornItemReplacement==registerWorn and ISTransferAction.GetDropItemOffset==replacementOffset
            and ISTransferAction.transferItem==replacementTransfer
    end
    assert(s.policy.adoptTransferItemHelper(previousTransfer,replacementTransfer,guard,previousOffset,replacementOffset))
    assert(s.adapters.transfer(action),'both actual selected P4 wrappers are explicitly adopted together')
    s.runTransfer(action);assert(s.water:getContainer()==s.root,'actual native non-floor move still executes through the P4 transfer wrapper')
    local pending=s.transfer(nil,s.root,s.bagInventory)
    for _,field in ipairs({'registerActionPolicy','registerWornItemReplacement'})do
        local previous=owner[field];owner[field]=function()error('changed public registration helper must not execute')end
        assert(not s.adapters.transfer(pending),'changed P4 public helper revokes the whole pair: '..field)
        owner[field]=previous
    end
    ISTransferAction.transferItem=function()error('unapproved transfer replacement must not execute')end
    assert(not s.adapters.transfer(pending),'late replacement of the adopted transfer remains forbidden')
    ISTransferAction.transferItem=replacementTransfer
    ISTransferAction.GetDropItemOffset=function()error('unapproved replacement must not execute')end
    assert(not s.adapters.transfer(pending),'late replacement of the adopted offset remains forbidden')
    ISTransferAction.GetDropItemOffset=replacementOffset
    P4TidyUpMeister={}
    assert(not s.adapters.transfer(pending),'a replaced P4 owner cannot reuse its old proof')
    P4TidyUpMeister=owner
    assert(s.adapters.transfer(pending),'restoring the exact public owner/helpers restores the proof')
else print('Actual selected P4 transfer/offset pair SKIP (pass --wishlist-workshop-root).')end
do
    -- Execute the live fixture's observer around actual native queue completion
    -- and transfer perform(), including Host's replacement InventoryItem proxy.
    local source=read(ProjectRoot..'/tests/native_queue/fluid/client/ZZFluidQueue.lua')
    local observerSource=assert(source:match('(local function observeReturn.-)\nlocal function enqueueEditedBottle'))
    local observeReturn=assert(loadstring(observerSource..'\nreturn observeReturn'))()
    for _,mode in ipairs({'normal','noop','missing','wrong-type','lookup-error','missing-before'})do
        local s=setup();local currentBottle=s.water
        local returning=s.transfer(nil,s.root,s.bagInventory)
        local anchor=s.f.action(ISBaseTimedAction)
        local q=s.f.queue(anchor,returning)
        s.bag.getItemContainer=function()return s.bagInventory end
        s.root.getItemById=function(_,id)
            if mode=='lookup-error'then error('unavailable inventory snapshot')end
            if id==s.bag:getID()then return s.bag end
            if id==s.water:getID()then return currentBottle end
        end
        local evidence={returnObservationFailed=false}
        observeReturn(q,returning,s.f.player,s.water,s.bag,evidence)
        s.water.container=mode=='noop'and s.bagInventory or s.root
        if mode=='missing-before'then currentBottle=nil end
        returning.isValidStart=function()return true end
        returning.begin=function(self)self.started=true end -- Java action dispatch boundary
        q:onCompleted(anchor)
        assert(q.current==returning and q.queue[1]==returning,'observer must delegate the native handoff even with no readable endpoint')
        local replacement=s.item();replacement.id=s.water.id;replacement.container=s.bagInventory
        if mode=='wrong-type'then replacement.getFullType=function()return 'Base.Unrelated'end end
        currentBottle=replacement
        if mode=='missing'then currentBottle=nil end
        s.water.container=nil -- stale Host proxy no longer belongs to either inventory
        isClient=function()return true end
        removeItemTransaction=function()end
        returning.action={stopTimedActionAnim=function()end,setLoopedAction=function()end,setWaitForFinished=function()end}
        returning:perform()
        assert(q.current==nil and #q.queue==0 and returning.started==false and returning.transactionId==0,
            'observational failures must never interrupt actual native transfer completion')
        assert(evidence.returnCompleted==true,'the observer must retain actual native completion')
        if mode=='normal'or mode=='noop'then
            assert(not evidence.returnObservationFailed and evidence.returnBoundaryObserved)
            assert(evidence.returnBefore==(mode=='noop'and 'bag'or 'root')and evidence.returnAfter=='bag',
                'boundaries must use the current exact bottle ID, not its stale Host proxy')
        else
            assert(evidence.returnObservationFailed and (evidence.returnBefore=='unknown'or evidence.returnAfter=='unknown'),
                'missing, mismatched or unreadable current identity must fail evidence rather than certify a no-op')
        end
    end
end
do
    local s=setup('ISDrinkFluidAction.lua');assert(not s.adapters.drink(s.drink()))
end
print('Item edit adapters: native idempotent transfers, captured SP water ratios, conservative Host intervals, source/helper and location guards passed.')
-- Food uses original-food portions and shares existence with transfers. These
-- checks execute native constructors/completion and the real policy, never Eat
-- from inspection or a synthetic whole-item conflict rule.
do
    local s=setup();local food=s.food();local half,quarter=s.eat(food,.5),s.eat(food,.25)
    local function entry(action)return {action=action,edit=assert(s.adapters.food(action))}end
    local a,b=entry(half),entry(quarter)
    assert(s.model.evaluate({a,b}).status=='allowed')
    assert(s.model.evaluate({b,a}).status=='allowed','different original portions can change order')
    a.snapshotOnly=true;assert(s.model.evaluate({b,a}).status=='allowed','cancelling a portion leaves more food')
    a.snapshotOnly=nil
    local whole=entry(s.eat(food,1))
    assert(s.model.evaluate({whole,b}).status=='denied','whole-food consumption cannot precede a dependent portion')
    local returning=s.transfer(food,s.root,s.bagInventory)
    assert(s.model.evaluate({whole,{action=returning,edit=assert(s.adapters.transfer(returning))}}).status=='denied',
        'native removal invalidates downstream exact-item transfers')
    assert(s.model.evaluate({b,{action=returning,edit=assert(s.adapters.transfer(returning))}}).status=='allowed')
    food.container=s.bagInventory
    local pickup=s.transfer(food,s.bagInventory,s.root)
    assert(s.model.evaluate({{action=pickup,edit=assert(s.adapters.transfer(pickup))},entry(quarter)}).status=='allowed')
    assert(s.model.evaluate({entry(quarter),{action=pickup,edit=assert(s.adapters.transfer(pickup))}}).status=='denied')
    food.container=s.root
    -- Inspection cannot consume or update hunger. Real native complete is still the effect owner.
    local effects=0
    s.f.player.Eat=function(_,exact,portion,utensil)
        assert(exact==food and portion==.25 and utensil==false);effects=effects+1
    end
    assert(s.adapters.food(quarter));assert(effects==0)
    assert(quarter:complete());assert(effects==1)
    s.water.container=s.root
    local anchor=s.drink();anchor.action={}
    local q=s.f.queue(anchor,half,quarter)
    assert(not s.policy.evaluateMove(q,half,quarter,true).reason,'actual policy uses resource proof for same-item portions')
    assert(not s.policy.evaluateCancel(q,half).reason,'ordinary pending food can be cancelled')
end
do
    -- Cookable food keeps the same original-food depletion contract while its
    -- native outermost carried inventory and residual heat cannot cook or burn it.
    for _,cooked in ipairs({false,true})do
        local s=setup();local food=s.food();food.cookable=true;food.cooked=cooked
        food.base=cooked and -.3 or -.24;food.hunger=food.base
        local half,quarter=s.eat(food,.5),s.eat(food,.25)
        local function entry(action,kind)return {action=action,edit=assert(s.adapters[kind or 'food'](action))}end
        local a,b=entry(half),entry(quarter)
        local debit=-food.base*.5;local margin=.00001
        assert(a.edit.resources[1].effects[1].deplete.amount==debit+margin
            and a.edit.resources[1].effects[1].deplete.minimum==.01+margin
            and a.edit.resources[1].effects[2].deplete.amount==debit-margin
            and a.edit.resources[1].effects[2].deplete.minimum==.01-margin,
            'cookable food retains the raw original-food debit and native tail uncertainty')
        local multiplier=cooked and 33800 or 13000
        assert(a.edit.resources[2].effects[1].delta==multiplier*(debit+.01+margin)+1
            and a.edit.resources[2].effects[2].cap==11000,
            'cooked and raw food retain their exact conservative fullness bounds')
        assert(s.model.evaluate({a,b}).status==(cooked and 'denied'or 'allowed'),
            'a large cooked first portion conservatively fills the actor before the second native action')
        assert(s.model.evaluate({b,a}).status=='allowed','cold cookable original portions can change order')
        local returning=s.transfer(food,s.root,s.bagInventory)
        local tail=entry(returning,'transfer')
        assert(s.model.evaluate({b,tail}).status=='allowed','a surviving cookable portion can return to its carried bag')
        local whole=entry(s.eat(food,1))
        assert(s.model.evaluate({whole,tail}).status=='denied','whole cookable consumption removes the exact transferred item')
        whole.snapshotOnly=true
        assert(s.model.evaluate({whole,tail}).status=='allowed','cancelling whole cookable consumption retains transfer existence')
        food.container=s.bagInventory
        s.bagInventory.temperature=math.huge
        local pickup=s.transfer(food,s.bagInventory,s.root)
        local first=entry(pickup,'transfer')
        a,b,tail=entry(half),entry(quarter),entry(returning,'transfer')
        assert(s.model.evaluate({first,b,tail}).status=='allowed',
            'native outermost inventory ignores even a hot nested carried bag temperature')
        assert(s.model.evaluate({b,first,tail}).status=='denied','cookable food still needs direct root inventory before eating')
        first.snapshotOnly=true
        assert(s.model.evaluate({first,b}).status=='denied','cancelling a required cookable pickup cannot certify eating from its bag')
        s.water.container=s.root;local head=s.drink();head.action={}
        local q=s.f.queue(head,pickup,half,quarter,returning)
        assert(s.policy.evaluateMove(q,quarter,half,false).allowed,'Policy reorders cold raw/cooked captured portions after pickup')
        assert(s.policy.evaluateCancel(q,quarter).allowed,'Policy cancels a pending cold raw/cooked portion')
        assert(not s.policy.evaluateCancel(q,pickup).allowed,'Policy preserves the required cookable pickup')
        assert(food.hunger==food.base and half.percentage==.5 and quarter.percentage==.25,
            'cookable inspection never changes hunger, temperature or captured portions')
    end
end
do
    local s=setup();local food=s.food();food.cookable=true;local action=s.eat(food,.5)
    for _,boundary in ipairs({0,1,1.3,1.6})do
        food.heat=boundary;s.root.temperature=boundary
        assert(s.adapters.food(action),'finite cold/warm heat and outer inventory boundaries are inclusive')
    end
    for _,field in ipairs({'heat','temperature'})do
        for _,value in ipairs({-.000001,1.600001,math.huge,-math.huge,0/0,'1',false,{}})do
            food.heat=1;s.root.temperature=1
            if field=='heat'then food.heat=value else s.root.temperature=value end
            assert(not s.adapters.food(action),'unknown or cooking-capable native thermal state is protected: '..field)
        end
        food.heat=1;s.root.temperature=1
        if field=='heat'then food.heat=nil else s.root.temperature=nil end
        assert(not s.adapters.food(action),'missing native thermal state must fail closed: '..field)
    end
    food.heat=1;s.root.temperature=1
    food.tags={[ItemTag.ALREADY_COOKED]=true}
    assert(not s.adapters.food(action),'an uncooked ALREADY_COOKED item changes state on native update even while cold')
    food.cooked=true
    assert(s.adapters.food(action),'a consistent already-cooked item has stable cold native state')
    food.fertilized=true
    assert(not s.adapters.food(action),'fertilized food may hatch during native update independently of cooking')
    food.fertilized=false;food.tags=nil
    food.isbDangerousUncooked=function()return true end
    assert(s.adapters.food(action),'already cooked dangerous-raw food is safe inside the cold contract')
    food.cooked=false
    assert(not s.adapters.food(action),'dangerous raw cookable food remains protected')
    food.cooked=true
    for _,spec in ipairs({{'getOnCooked','custom.callback'},
        {'getOnEat','custom.callback'},{'getReplaceOnRotten','Base.Rotten'},{'isRotten',true},{'isBurnt',true},
        {'getPoisonPower',1},{'isTainted',true}})do
        local name,value=spec[1],spec[2];local previous=food[name];food[name]=function()return value end
        assert(not s.adapters.food(action),'cold cookable food cannot bypass existing hazard/effect guard: '..name)
        food[name]=previous
    end
    food.container=s.bagInventory;s.root.temperature=2
    local pickup=s.transfer(food,s.bagInventory,s.root)
    assert(s.adapters.transfer(pickup)and not s.adapters.food(action),
        'a carried transfer alone cannot certify cold food against a hot outer root inventory')
    s.water.container=s.root;local head=s.drink();head.action={}
    local q=s.f.queue(head,pickup,action)
    assert(not s.policy.evaluateMove(q,action,pickup,false).allowed,'Policy does not use an unmodelled hot food consumer to cross its pickup')
    s.root.temperature=1
    local before=ISEatFoodAction.isEatingRemaining
    ISEatFoodAction.isEatingRemaining=function()error('modified cookable helper must never execute')end
    assert(not s.adapters.food(action),'cold cookable support retains live native helper proof')
    ISEatFoodAction.isEatingRemaining=before
    assert(s.adapters.food(action),'restoring the exact helper restores the cold cookable contract')
end
do
    -- ReplaceOnCooked is dormant only while the ordinary cookable item stays
    -- cold. It must not replace exact-item identity or change original portions.
    for _,cooked in ipairs({false,true})do
        local s=setup();local food=s.food();food.cookable=true;food.cooked=cooked;food.base=-.1;food.hunger=-.1
        local outputs={isEmpty=function()return false end,size=function()return 1 end,
            get=function()error('inspection must not materialize dormant cooked replacements')end}
        food.getReplaceOnCooked=function()return outputs end
        local half,quarter=s.eat(food,.5),s.eat(food,.25)
        local function entry(action,kind)return {action=action,edit=assert(s.adapters[kind or 'food'](action))}end
        local a,b=entry(half),entry(quarter);local resource=a.edit.resources[1]
        assert(resource.key==food:getID()and resource.facts.item==food and #a.edit.resources==2,
            'dormant cooked outputs retain only the exact original food and actor resources')
        assert(resource.effects[1].deplete.amount==.05+.00001
            and resource.effects[2].deplete.amount==.05-.00001
            and a.edit.resources[2].effects[1].delta==(cooked and 33800 or 13000)*(.05+.01+.00001)+1,
            'dormant cooked outputs preserve the existing raw debit and raw/cooked fullness bound')
        local returning=s.transfer(food,s.root,s.bagInventory);local tail=entry(returning,'transfer')
        assert(s.model.evaluate({a,b,tail}).status=='allowed','cold replacement food retains the .025 original-food tail')
        assert(s.model.evaluate({b,a,tail}).status=='allowed','dormant replacement food portions commute before returning')
        a.snapshotOnly=true
        assert(s.model.evaluate({a,b,tail}).status=='allowed','cancelling a replacement-food portion preserves the original item')
        a.snapshotOnly=nil
        local whole=entry(s.eat(food,1))
        assert(s.model.evaluate({whole,tail}).status=='denied','eating the whole original food cannot promise its later transfer')
        assert(s.model.evaluate({whole,b}).status=='denied','cooked outputs do not rescue a depleted exact original food')
        food.container=s.bagInventory
        local pickup=s.transfer(food,s.bagInventory,s.root);local first=entry(pickup,'transfer')
        a,b,tail=entry(half),entry(quarter),entry(returning,'transfer')
        assert(s.model.evaluate({first,b,a,tail}).status=='allowed','cold replacement food supports carried pickup and return')
        assert(s.model.evaluate({b,first,tail}).status=='denied','dormant replacement food still requires direct root before eating')
        first.snapshotOnly=true
        assert(s.model.evaluate({first,b}).status=='denied','cancelling its pickup cannot make replacement food reachable for eating')
        s.water.container=s.root;local head=s.drink();head.action={}
        local q=s.f.queue(head,pickup,half,quarter,returning)
        assert(s.policy.evaluateMove(q,quarter,half,false).allowed,'Policy moves cold replacement-food original portions')
        assert(s.policy.evaluateCancel(q,half).allowed,'Policy cancels an ordinary cold replacement-food portion')
        assert(not s.policy.evaluateCancel(q,pickup).allowed,'Policy retains the required replacement-food pickup')
        assert(food.hunger==-.1 and food.base==-.1 and food:getReplaceOnCooked()==outputs
            and half.item==food and quarter.item==food and half.percentage==.5 and quarter.percentage==.25,
            'inspection preserves dormant replacement configuration, exact food and captured fractions')
        food.heat=1.600001
        assert(not s.adapters.food(half),'hot replacement food cannot use the dormant output exception')
        food.heat=1;s.root.temperature=1.600001
        assert(not s.adapters.food(half),'a hot outer inventory can activate cooked replacements later')
        s.root.temperature=1;food.cookable=false
        assert(not s.adapters.food(half),'noncookable cooked-output metadata has no audited dormant transition contract')
        food.cookable=true;food.fertilized=true
        assert(not s.adapters.food(half),'replacement output permission cannot bypass native hatch protection')
        food.fertilized=false
        if not cooked then
            food.tags={[ItemTag.ALREADY_COOKED]=true}
            assert(not s.adapters.food(half),'replacement output permission cannot bypass forced native cooked state')
            food.tags=nil
            food.isbDangerousUncooked=function()return true end
            assert(not s.adapters.food(half),'dormant replacement metadata does not make dangerous raw food safe')
            food.isbDangerousUncooked=function()return false end
        end
        for _,spec in ipairs({{'getOnCooked','custom.callback'},{'getOnEat','custom.callback'},
            {'getReplaceOnUse','Base.Bowl'},{'getReplaceOnRotten','Base.Rotten'},
            {'getPoisonPower',1},{'isTainted',true},{'isRotten',true},{'isBurnt',true}})do
            local name,value=spec[1],spec[2];local previous=food[name];food[name]=function()return value end
            assert(not s.adapters.food(half),'dormant cooked output permission preserves existing effect guard: '..name)
            food[name]=previous
        end
        local script=food:getScriptItem();local previous=script.getReplaceOnDeplete
        script.getReplaceOnDeplete=function()return 'Base.Bowl'end
        assert(not s.adapters.food(half),'dormant cooked outputs cannot authorize a depletion replacement')
        script.getReplaceOnDeplete=previous
        local native=ISEatFoodAction.isEatingRemaining
        ISEatFoodAction.isEatingRemaining=function()error('unreviewed replacement-food helper must not execute')end
        assert(not s.adapters.food(half),'cold replacement support retains native helper identity proof')
        ISEatFoodAction.isEatingRemaining=native
        assert(s.adapters.food(half),'restoring the exact native helper restores the dormant replacement contract')
    end
end
do
    -- EatSmart and other native producers capture arbitrary fractions of the
    -- original food. Reordering does not recalculate their nutrition target.
    for _,client in ipairs({false,true})do
        local s=setup();isClient=function()return client end
        PZMath={clamp_01=function(value)return math.max(0,math.min(1,value))end}
        local food=s.food();food.hunger=-.2
        local small,quarter,last=s.eat(food,.1875),s.eat(food,.25),s.eat(food,.1)
        local function entry(action)return {action=action,edit=assert(s.adapters.food(action))}end
        local a,b,c=entry(small),entry(quarter),entry(last)
        local returning=s.transfer(food,s.root,s.bagInventory)
        local transfer={action=returning,edit=assert(s.adapters.transfer(returning))}
        assert(s.model.evaluate({a,b,transfer}).status=='allowed',
            'partially eaten food retains .025 after original-food .1875 and .25 portions')
        assert(s.model.evaluate({b,a,transfer}).status=='allowed','captured original fractions commute before the native tail')
        assert(s.model.evaluate({a,b,c,transfer}).status=='denied',
            'a further original .1 portion consumes the tail and invalidates the exact-item transfer')
        c.snapshotOnly=true
        assert(s.model.evaluate({a,b,c,transfer}).status=='allowed','cancelling the pending portion preserves the item')
        s.water.container=s.root
        local anchor=s.drink();anchor.action={}
        local q=s.f.queue(anchor,small,quarter,returning)
        assert(s.policy.evaluateMove(q,small,quarter,true).allowed,'policy can reorder non-menu original-food fractions')
        assert(s.policy.evaluateCancel(q,small).allowed,'policy can cancel an arbitrary pending native fraction')
        assert(small.percentage==.1875 and quarter.percentage==.25 and food.hunger==-.2,
            'inspection and editing decisions preserve the captured fraction and food')
        -- Crossing .01 may remove the entire food; uncertainty at the exact
        -- boundary must not certify a downstream consumer or transfer.
        for _,case in ipairs({{.0851,'allowed',false},{.085,'denied'},{.0849,'denied',true}})do
            food.hunger=-case[1]
            if case[3]~=nil then assert(small:isEatingRemaining(food)==case[3])end
            -- The transfer contract snapshots the same live food amount.
            transfer.edit=assert(s.adapters.transfer(returning))
            assert(s.model.evaluate({entry(small),transfer}).status==case[2],
                'arbitrary fraction must retain the conservative native .01 tail boundary')
        end
    end
end
do
    local s=setup();local food=s.food();local action=s.eat(food,.5)
    for _,portion in ipairs({.1875,1/3,.999,1e-300,1})do
        action.percentage=portion
        assert(s.adapters.food(action),'every finite native fraction in (0,1] has the same audited effect owner')
    end
    action.percentage=1e-300 -- Java float conversion may underflow to zero.
    local returning=s.transfer(food,s.root,s.bagInventory)
    local function afterTiny()
        return s.model.evaluate({{action=action,edit=assert(s.adapters.food(action))},
            {action=returning,edit=assert(s.adapters.transfer(returning))}}).status
    end
    assert(afterTiny()=='allowed','underflow-sized percentage retains a comfortably nonempty food')
    food.hunger=-.010005
    assert(afterTiny()=='denied','float/tail uncertainty must not promise survival just above .01')
    food.hunger=-.009995
    assert(afterTiny()=='denied','native tail can consume sub-.01 food even when its float percentage is zero')
    food.hunger=-.4
    for _,portion in ipairs({0,-.1,1.000001,math.huge,-math.huge,0/0,'0.25',false,{}})do
        action.percentage=portion
        assert(not s.adapters.food(action),'malformed or out-of-range native food fraction must stay protected')
    end
    action.percentage=nil
    assert(not s.adapters.food(action),'a missing captured fraction is not a constructor default during inspection')
end
do
    local s=setup();local food=s.food();local a=s.eat(food,.25)
    local function project(...)
        local entries={};for _,action in ipairs({...})do entries[#entries+1]={action=action,edit=assert(s.adapters.food(action))}end
        return s.model.evaluate(entries)
    end
    food.hunger=-.11
    assert(project(a,s.eat(food,.25)).status=='denied','near-empty native tail cannot promise another portion')
    s.damage.timer=3600
    assert(project(a).status=='allowed','native fullness threshold is strict and checked before eating')
    assert(project(a,s.eat(food,.25)).status=='denied')
    s.damage.timer=3601
    assert(project(a).status=='denied','already full actor cannot start eating')
    s.damage.timer=-.5
    assert(project(a).status=='allowed','native timer decay may overshoot zero')
    s.damage.timer=11001;assert(not s.adapters.food(a),'do not invent a reduction of an above-cap external timer')
    s.damage.timer=3500;s.water.container=s.root
    local drink=s.drink()
    local decision=s.model.evaluate({{action=a,edit=assert(s.adapters.food(a))},{action=drink,edit=assert(s.adapters.drink(drink))}})
    assert(decision.status=='denied'and decision.field=='foodTimerUpper','native water shares the changing fullness prerequisite')
    s.damage.timer=0;food.hunger=-.4
    s.properties.getHungerChange=function()return -.1 end
    local mixed=s.drink();local anchor=s.f.action(ISReadABook,{item=s.item()})
    local q=s.f.queue(anchor,mixed,a)
    assert(not s.policy.evaluateMove(q,a,mixed,false).allowed,'unmodelled nutritious drinking cannot hide actor fullness effects')
    s.properties.getHungerChange=function()return 0 end
    for _,spec in ipairs({
        {'getOnEat','custom.callback'},{'getReplaceOnUse','Base.Bowl'},{'getUses',2},
        {'getRequireInHandOrInventory',{}},{'isKeepOnDeplete',true},{'isDisappearOnUse',false},
        {'isTainted',true},{'getPoisonPower',1},{'isAlcoholic',true},{'getReduceInfectionPower',1},
        {'isRotten',true},{'isBurnt',true},{'isbDangerousUncooked',true},{'hasTag',true},
        {'getOnCooked','custom.callback'},{'getReplaceOnRotten','Base.Rotten'}})do
        local name,value=spec[1],spec[2];local before=food[name];food[name]=function()return value end
        assert(not s.adapters.food(a),'unknown food effects must be protected: '..name);food[name]=before
    end
    for _,name in ipairs({'complete','serverStop','getRequiredItem','isEatingRemaining'})do
        local before=ISEatFoodAction[name];ISEatFoodAction[name]=function()error('foreign callback must never execute')end
        assert(not s.adapters.food(a));ISEatFoodAction[name]=before
    end
    a.action={};assert(not s.adapters.food(a));a.action=nil
    a.spoon={};assert(s.adapters.food(a),'unused carried cutlery does not block ordinary food')
    local previous=food.getEatType;food.getEatType=function()return 'Can'end
    assert(not s.adapters.food(a));food.getEatType=previous;a.spoon=nil
    a.onCompleteFunc=function()error('unknown callback')end;assert(not s.adapters.food(a))
end
do
    local s=setup('ISEatFoodAction.lua');assert(not s.adapters.food(s.eat(s.food())))
    for _,name in ipairs({'complete','serverStop','getRequiredItem','isEatingRemaining'})do
        s=setup(nil,nil,nil,{owner='ISEatFoodAction',name=name})
        assert(not s.adapters.food(s.eat(s.food())),'deleted native food effect/helper cannot inherit permission: '..name)
        assert(s.adapters.drink(s.drink()),'unknown food callbacks do not revoke unrelated native water contracts')
    end
end
-- These use the installed native constructor and getSecondItem/getDuration,
-- while the production adapter and Policy own every edit decision.
do
    for _,kind in ipairs({'Can','Candrink','2hand','Plate','2handbowl','EatBox','2handforced','plate'})do
        local s=setup();local food=s.food();food.getEatType=function()return kind end
        local spoon=s.utensil('Spoon',s.bagInventory);local fork=s.utensil('Fork')
        local action=s.eat(food,.8)
        local selected=kind=='2handbowl'and spoon or (kind=='Can'or kind=='Candrink'or kind=='2hand'or kind=='Plate')and fork or nil
        assert(action.spoon==spoon and action.fork==fork,'the actual constructor captures both available utensils')
        assert(action:getSecondItem()==selected and action.useUtensil==(selected~=nil),'native EatType selection must stay exact: '..kind)
        local duration=action.maxTime
        assert(duration==(selected and 232 or 464),'native large-portion duration preserves the captured utensil benefit')
        local edit=assert(s.adapters.food(action));local resources=edit.resources
        if selected then
            local resource=assert(resources[3]);assert(resource.domain=='item'and resource.key==selected:getID()
                and resource.facts.item==selected and #resource.effects==0,'only the exact selected utensil is a read-only resource')
            assert(not resources[4],'unused captured cutlery must not become a resource')
        else
            assert(not resources[3],'animation-independent captured cutlery adds no item dependency')
        end
        local contract=assert(s.policy.inspect(action))
        assert(contract.items[food:getID()]and (not selected or contract.items[selected:getID()]))
        if selected~=fork then assert(not contract.items[fork:getID()],'unused fork is not a policy dependency')end
        if selected~=spoon then assert(not contract.items[spoon:getID()],'unused spoon is not a policy dependency')end
        if selected==spoon then
            assert(contract.containerOwners and contract.containerOwners[s.bag:getID()],'selected carried-bag ancestry is linked')
        end
        local calls=0;s.f.player.Eat=function(_,exact,portion,useUtensil)
            assert(exact==food and portion==.8 and useUtensil==(selected~=nil));calls=calls+1
        end
        assert(calls==0 and action.maxTime==duration and action.percentage==.8,'inspection preserves native captured duration and percentage')
        assert(action:complete()and calls==1,'real native completion retains its captured utensil boolean')
    end
end
do
    local s=setup();local food=s.food();food.getEatType=function()return '2handbowl'end
    local empty=s.eat(food,.5)
    assert(empty.fork==nil and empty.spoon==nil and empty.useUtensil==false and s.adapters.food(empty),
        'native empty captured references preserve ordinary utensil-free eating')
    local fork=s.utensil('Fork');local action=s.eat(food,.5)
    assert(action.fork==fork and action.spoon==nil and action.useUtensil==false)
    assert(s.adapters.food(action)and #s.adapters.food(action).resources==2,'a bowl cannot substitute its remembered fork for a missing spoon')
    local spoon=s.utensil('Spoon');food.getEatType=function()return 'Can'end
    fork.broken=true;action=s.eat(food,.5)
    assert(action.fork==nil and action.spoon==spoon and action.useUtensil==true,'native constructor skips broken forks and falls back to spoon')
    assert(s.adapters.food(action))
end
do
    local s=setup();local food=s.food();food.getEatType=function()return 'Can'end
    local fork=s.utensil('Fork',s.bagInventory);local action=s.eat(food,.25)
    local pickup=s.transfer(fork,s.bagInventory,s.root);local returning=s.transfer(fork,s.root,s.bagInventory)
    local function entry(value,adapter)return {action=value,edit=assert(s.adapters[adapter or 'food'](value))}end
    local eatEntry,pickupEntry,returnEntry=entry(action),entry(pickup,'transfer'),entry(returning,'transfer')
    assert(s.model.evaluate({eatEntry,pickupEntry,returnEntry}).status=='allowed','cutlery may remain in its captured carried bag when eating')
    assert(s.model.evaluate({pickupEntry,eatEntry,returnEntry}).status=='allowed','pickup to root preserves the exact selected cutlery')
    assert(s.model.evaluate({pickupEntry,returnEntry,eatEntry}).status=='allowed','putting the selected utensil back before eating preserves native behavior')
    pickupEntry.snapshotOnly=true
    assert(s.model.evaluate({pickupEntry,eatEntry}).status=='allowed','cancelling an unnecessary utensil pickup leaves valid carried cutlery')
    pickupEntry.snapshotOnly=nil
    s.water.container=s.root;local anchor=s.drink();anchor.action={}
    local q=s.f.queue(anchor,pickup,action,returning)
    assert(s.policy.evaluateMove(q,action,pickup,false).allowed,'Policy can move eating before a bag/root utensil transfer')
    assert(s.policy.evaluateMove(q,returning,action,false).allowed,'Policy can return cutlery before its captured eating action')
    assert(s.policy.evaluateCancel(q,pickup).allowed,'Policy can cancel the unnecessary cutlery pickup')
    assert(s.policy.evaluateCancel(q,action).allowed,'ordinary pending utensil eating remains cancellable')
    local other=s.utensil('Fork');local duration=action.maxTime
    s.runTransfer(pickup)
    s.root.getFirstTagEvalRecurse=function()error('inspection must never reselect cutlery')end
    s.root.getFirstTypeEvalRecurse=s.root.getFirstTagEvalRecurse
    local edit=assert(s.adapters.food(action))
    assert(edit.resources[3].facts.item==fork and action.fork==fork and action.fork~=other
        and action.maxTime==duration and action.useUtensil==true,'moving captured cutlery cannot switch to another available fork or recalculate duration')
end
do
    local s=setup();local food=s.food();food.getEatType=function()return 'Can'end
    local fork=s.utensil('Fork');local action=s.eat(food,.5)
    assert(s.adapters.food(action))
    for _,value in ipairs({false,0,'true',{}})do
        action.useUtensil=value;assert(not s.adapters.food(action),'selected cutlery requires the exact native boolean')
    end
    action.useUtensil=nil;assert(not s.adapters.food(action));action.useUtensil=true
    action.fork=nil;assert(not s.adapters.food(action),'a true boolean cannot invent a missing captured utensil');action.fork=fork
    food.getEatType=function()return '2handbowl'end;action.spoon=false
    assert(not s.adapters.food(action),'a false captured bowl-spoon reference cannot claim the native utensil benefit')
    action.spoon={};assert(not s.adapters.food(action),'a malformed captured bowl-spoon reference cannot claim the native utensil benefit')
    action.spoon=nil;food.getEatType=function()return 'Can'end
    for _,field in ipairs({'broken','consumed'})do
        fork[field]=true;assert(not s.adapters.food(action),'invalid selected utensil must fail closed: '..field);fork[field]=nil
    end
    local original=s.f.player.isEquipped;s.f.player.isEquipped=function(_,item)return item==fork end
    assert(not s.adapters.food(action),'selected equipped cutlery is outside the ordinary leaf contract');s.f.player.isEquipped=original
    original=fork.getEquipParent;fork.getEquipParent=function()return s.f.player end
    assert(not s.adapters.food(action),'an equip-parent reference cannot masquerade as loose cutlery');fork.getEquipParent=original
    fork.container=nil;assert(not s.adapters.food(action),'missing exact utensil cannot be replaced by the old reference');fork.container=s.root
    local foreign={class='ItemContainer',getType=function()return 'crate'end,isExistYet=function()return true end,
        getAcceptItemFunction=function()end,getOnlyAcceptCategory=function()end,getContainingItem=function()end}
    fork.container=foreign;assert(not s.adapters.food(action),'foreign-world cutlery is not carried ancestry');fork.container=s.root
    local lookup=s.root.getItemById;s.root.getItemById=function(_,id)if id==fork.id then return s.utensil('Fork')end;return lookup(s.root,id)end
    assert(not s.adapters.food(action),'the selected ID must resolve to the exact captured item');s.root.getItemById=lookup
    fork.class='InventoryItem';assert(not s.adapters.food(action),'arbitrary tagged inventory objects are not native HandWeapon cutlery');fork.class='HandWeapon'
    fork.id=.5;assert(not s.adapters.food(action),'malformed selected identity cannot enter the shared resource model')
end
do
    for _,mode in ipairs({'selected-tool','container-owner','unused-tool'})do
        local s=setup();local food=s.food();food.getEatType=function()return 'Can'end
        local fork=s.utensil('Fork',s.bagInventory);local spoon=s.utensil('Spoon')
        local action=s.eat(food,.25);local exact=mode=='selected-tool'and fork or mode=='container-owner'and s.bag or spoon
        local unknownClass=ISBaseTimedAction:derive('UnreviewedCutleryOperation')
        local unknown=s.f.action(unknownClass,{item=exact})
        PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('fixture.cutlery-operation',{
            types={'UnreviewedCutleryOperation'},matches=function(value)return value==unknown end,
            inspect=function()return {items={[exact:getID()]=true},itemTypes={},targets={},cancelWaiting=true}end,
        })
        s.water.container=s.root;local anchor=s.drink();anchor.action={}
        local q=s.f.queue(anchor,action,unknown)
        local decision=s.policy.evaluateCancel(q,action)
        if mode=='unused-tool'then
            assert(decision.allowed,'a known unrelated operation on unused remembered cutlery does not join the eating component')
        else
            assert(s.policy.cancelOperationReason(q,action)=='operation_shared_item'
                and not decision.allowed and decision.reason=='edit_unknown'and decision.blocker==unknown,
                'unmodeled selected-tool/container-owner effects retain exact dependency protection: '..mode)
        end
    end
end
print('Food edit adapters: original portions, cold cookable state and dormant cooked replacements, depletion/location/fullness dependencies, pending cancellation and callback guards passed.')
