if not NativeActionRoot then print('Item edit adapters SKIP (pass --native-action-root).');return end
next = nil -- PZ Kahlua has no global next; capacity checks must work without it.
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
    f.native('client/TimedActions/WalkToTimedAction.lua')
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
    local scripts={}
    ScriptManager={instance={getItem=function(_,fullType)return scripts[fullType]end}}
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
        getTotalWeightOfItemsOnFloor=function()return 0 end,getX=function()return 0 end,getY=function()return 0 end,getZ=function()return 0 end}
    f.player.getCurrentSquare=function()return square end
    ISLogSystem={logAction=function()end};ItemPicker={updateOverlaySprite=function()end}
    local baseInstanceof=instanceof
    instanceof=function(value,kind)return baseInstanceof(value,kind)or type(value)=='table'and
        (kind=='IsoGameCharacter'and value.class=='IsoPlayer'or kind=='IsoObject'and value.class=='IsoThumpable'
        or kind=='InventoryItem'and (value.class=='Food'or value.class=='HandWeapon'or value.class=='InventoryContainer'))end
    getClassSimpleName=function(value)return value.class end
    local knownItems={}
    local bag
    local function container(owner)
        local c={class='ItemContainer',owner=owner,temperature=1}
        c.getTemperature=function(self)return self.temperature end
        c.getCustomTemperature=function(self)return self.customTemperature or 0 end
        c.getOutermostContainer=function(self)
            return self.owner and self.owner:getContainer():getOutermostContainer()or self
        end
        for _,name in ipairs({'isFridge','isFreezer','isStove','isMicrowave','isTemperatureChanging'})do
            c[name]=function(self)return self[name..'Flag']or false end
        end
        c.getContainingItem=function(self)return self.owner end;c.getType=function(self)return self.owner and 'bag'or 'none'end
        c.getParent=function(self)return not self.owner and f.player or nil end
        c.getVehiclePart=function()end
        c.isInCharacterInventory=function()return true end;c.isExistYet=function()return true end
        c.getAcceptItemFunction=function()end;c.getOnlyAcceptCategory=function()end
        c.getCapacityWeight=function(self)return self.load or 0 end;c.getEffectiveCapacity=function(self)return self.capacity or 50 end;c.getMaxWeight=function()return 50 end
        c.isVehicleSeat=function()return false end;c.contains=function(self,item)return item.container==self end
        c.getItemById=function(self,id)for _,item in ipairs(knownItems)do if item.id==id and item.container==self then return item end end end
        c.getItems=function(self)
            local items={}
            if not self.owner and self:isInCharacterInventory() and bag then items[#items+1]=bag end
            for _,item in ipairs(knownItems)do if item.container==self then items[#items+1]=item end end
            return {size=function()return #items end,get=function(_,index)return items[index+1]end}
        end
        c.hasRoomFor=function()return true end;c.isRemoveItemAllowed=function()return true end;c.isItemAllowed=function()return true end
        c.isInside=function()return false end;c.getPutSound=function()end
        c.setDrawDirty=function()end;c.setHasBeenLooted=function()end
        c.getFirstTagEvalRecurse=function()end;c.getFirstTypeEvalRecurse=function()end
        c.DoRemoveItem=function(_,item)item.container=nil end;c.AddItem=function(self,item)item.container=self;return item end
        return c
    end
    local root=container();f.player.inventory=root
    bag=f.item('Base.Bag_Schoolbag');bag.class='InventoryContainer';bag.getContainer=function()return root end
    bag.getMaxItemSize=function(self)return self.maxItemSize or 0 end
    bag.getWorldItem=function()end;bag.getFluidContainer=function()end;bag.getActualWeightUnmodded=function()return 1 end
    bag.getAttachedSlot=function()return -1 end;bag.isFakeEquipped=function()return false end
    local bagInventory=container(bag);bag.getInventory=function()return bagInventory end
    local function item()
        local value=f.item('Base.WaterBottle');value.container=bagInventory
        value.getContainer=function(self)return self.container end;value.getWorldItem=function()end
        value.isOnGroundOrInsideBagOnSquare=function()return false end
        value.getIsCraftingConsumed=function(self)return self.consumed or false end
        value.getEquipParent=function()end;value.getAttachedSlot=function()return -1 end
        value.isFakeEquipped=function()return false end;value.getAmmoType=function()end
        value.getType=function()return 'WaterBottle'end;value.getActualWeight=function()return 1 end
        value.getUnequippedWeight=function()return 1 end;value.getWeight=function()return 1 end
        value.isFavorite=function()return false end;value.setJobDelta=function()end
        value.getFluidContainer=function(self)return self.fluid end;value.getEatType=function()return 'bottle'end
        value.syncItemFields=function()end
        knownItems[#knownItems+1]=value
        return value
    end
    bag.getUnequippedWeight=function()
        local total=1
        for _,entry in ipairs(knownItems)do if entry.container==bagInventory then total=total+entry:getUnequippedWeight()end end
        return total
    end
    local water=item()
    local function food()
        local value=item();value.class='Food';value.fluid=nil;value.container=root;value.hunger=-0.4;value.base=-0.4
        value.getFullType=function()return 'Base.Cereal'end;value.getType=function()return 'Cereal'end
        value.getEatType=function()return 'EatBox'end;value.getCustomEatSound=function()end
        value.getHungChange=function(self)return self.hunger end
        value.getHungerChange=function(self)return self.hunger*(self:isCooked()and 1.3 or 1)end
        value.getBaseHunger=function(self)return self.base end
        value.getActualWeightUnmodded=function(self)return self.actualWeight or 1 end
        value.getExtraItems=function(self)return self.extras end
        value.hasTag=function(self,tag)return self.tags and self.tags[tag]or false end
        value.heat=1;value.getHeat=function(self)return self.heat end
        value.isCooked=function(self)return self.cooked or false end
        value.isCookable=function(self)return self.cookable or false end
        value.isFertilized=function(self)return self.fertilized or false end
        value.getEatTime=function()return 0 end;value.getUses=function()return 1 end
        value.isDisappearOnUse=function()return true end
        for _,name in ipairs({'getReplaceOnUse','getReplaceOnUseFullType','getOnEat','getOnCooked','getReplaceOnCooked','getReplaceOnRotten','getRequireInHandOrInventory','getCustomMenuOption'})do value[name]=function()end end
        for _,name in ipairs({'isCustomWeight','haveExtraItems','isKeepOnDeplete','isTainted','isAlcoholic','isBurnt','isRotten','isbDangerousUncooked'})do value[name]=function()return false end end
        value.getPoisonPower=function()return 0 end;value.getReduceInfectionPower=function()return 0 end
        local script={isCantEat=function()return false end,getOpeningRecipe=function()end,getOnBreak=function()end,
            getReplaceOnUse=function()end,getReplaceOnDeplete=function()end,
            getHungerChange=function()return -.4 end,getActualWeight=function()return 1 end}
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
    local function world()
        local c=container();local parent={class='IsoObject'}
        local tile={x=1,y=0,z=0,present=true}
        tile.getX=function(self)return self.x end;tile.getY=function(self)return self.y end;tile.getZ=function(self)return self.z end
        tile.getObjects=function(self)return {contains=function(_,value)return self.present and value==parent end}end
        parent.square,parent.container=tile,c
        parent.getSquare=function(self)return self.square end
        parent.getContainerCount=function()return 1 end;parent.getContainerByIndex=function(self)return self.container end
        for _,name in ipairs({'isDoor','isDoorFrame','isWindowN','isWindowW','isBarricaded','isLocked','isLockedByKey','isLockedByPadlock'})do
            parent[name]=function(self)return self[name..'Flag']or false end
        end
        parent.getLockedByCode=function(self)return self.code or 0 end
        c.parent,c.square,c.kind=parent,tile,'crate'
        c.getParent=function(self)return self.parent end;c.getSourceGrid=function(self)return self.square end
        c.getVehiclePart=function(self)return self.vehiclePart end;c.getType=function(self)return self.kind end
        c.isInCharacterInventory=function()return false end
        return c,parent,tile
    end
    return {f=f,adapters=adapters,model=model,policy=policy,root=root,bag=bag,bagInventory=bagInventory,water=water,fluid=fluid,world=world,container=container,
        properties=properties,scripts=scripts,item=item,food=food,utensil=utensil,eat=eat,damage=damage,transfer=transfer,drink=drink,runTransfer=runTransfer,drinks=function()return drinks end}
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
    -- Partial eating must keep ReplaceOnUse dormant at every projected step.
    -- The empty container is neither created nor substituted for the original ID.
    local function replacementFood(s,custom)
        local food=s.food();food.base=-.15;food.hunger=-.15
        food.getReplaceOnUse=function()return 'Base.TinCanEmpty'end
        food.getReplaceOnUseFullType=function()return 'Base.TinCanEmpty'end
        local script=food:getScriptItem()
        script.getReplaceOnUse=function()return 'Base.TinCanEmpty'end
        script.hunger=-.15;script.weight=.8
        script.getHungerChange=function(self)return self.hunger end
        script.getActualWeight=function(self)return self.weight end
        local output={weight=.2,getActualWeight=function(self)return self.weight end}
        s.scripts['Base.TinCanEmpty']=output
        if custom then
            food.isCustomWeight=function()return true end
            food.weight,food.actualWeight=.8,.8
            food.getWeight=function(self)return self.weight end
            food.getActualWeight=function(self)return self.actualWeight end
            food.getUnequippedWeight=food.getActualWeight
        end
        return food,script,output
    end
    for _,client in ipairs({false,true})do
    for _,custom in ipairs({false,true})do
        local s=setup();isClient=function()return client end
        local food=replacementFood(s,custom);local half,quarter=s.eat(food,.5),s.eat(food,.25)
        local function entry(action,kind)return {action=action,edit=assert(s.adapters[kind or 'food'](action))}end
        local a,b=entry(half),entry(quarter);local resource=a.edit.resources[1]
        local minimum=.15*.5+.01+2*.00001
        assert(resource.facts.item==food and resource.key==food:getID()and #a.edit.resources==2
            and resource.requires[2].field=='foodLower'and resource.requires[2].above==minimum,
            'partial replacement food retains its original exact ID and requires a safe native tail')
        assert(resource.effects[1].deplete.amount==.15*.5+.00001
            and resource.effects[2].deplete.amount==.15*.5-.00001,
            'partial replacement support must retain the existing conservative original-food debit')
        local returning=s.transfer(food,s.root,s.bagInventory);local tail=entry(returning,'transfer')
        assert(s.model.evaluate({a,b,tail}).status=='allowed','partial can half then quarter leaves original can food for return')
        assert(s.model.evaluate({b,a,tail}).status=='allowed','partial replacement original portions commute safely')
        a.snapshotOnly=true
        assert(s.model.evaluate({a,b,tail}).status=='allowed','cancelling a partial portion preserves the exact original food')
        a.snapshotOnly=nil
        local whole=entry(s.eat(food,1))
        assert(s.model.evaluate({whole}).status=='denied','full consumption must not activate an unmodelled empty-container replacement')
        assert(s.model.evaluate({a,entry(s.eat(food,.5)),tail}).status=='denied',
            'a preceding portion can make a later replacement-bearing action consume the native tail')
        assert(s.model.evaluate({a,b,whole}).status=='denied','a full tail action remains protected after safe partial portions')
        whole.snapshotOnly=true
        assert(s.model.evaluate({a,b,whole,tail}).status=='allowed',
            'a snapshot-only cancelled full action leaves safe partial consumption and return')
        food.container=s.bagInventory
        local pickup=s.transfer(food,s.bagInventory,s.root);local first=entry(pickup,'transfer')
        a,b,tail=entry(half),entry(quarter),entry(returning,'transfer')
        assert(s.model.evaluate({first,a,b,tail}).status=='allowed','partial replacement food supports exact pickup and tail return')
        assert(s.model.evaluate({a,first,tail}).status=='denied','partial replacement food cannot be eaten before its pickup')
        s.water.container=s.root;local head=s.drink();head.action={}
        local q=s.f.queue(head,pickup,half,quarter,returning)
        for attempt=1,3 do
            assert(s.policy.evaluateMove(q,quarter,half,false).allowed,'Policy repeatedly reorders safe partial container-food portions')
            assert(s.policy.evaluateCancel(q,half).allowed,'Policy repeatedly cancels safe partial container-food consumption')
        end
        assert(not s.policy.evaluateCancel(q,pickup).allowed,'Policy retains the partial food pickup dependency')
        assert(food.hunger==-.15 and food.base==-.15 and half.item==food and quarter.item==food
            and half.percentage==.5 and quarter.percentage==.25,'inspection preserves original container food and captured fractions')
        assert(not custom or food.weight==.8 and food.actualWeight==.8,'inspection preserves both custom-weight fields')
        food.container=s.root
        for _,case in ipairs({{minimum+.000001,'allowed'},{minimum,'denied'},{minimum-.000001,'denied'},{.01,'denied'}})do
            food.hunger=-case[1]
            assert(s.model.evaluate({entry(half)}).status==case[2],
                'native tail threshold and float slack must be strict for each replacement-bearing action')
        end
        local tiny=s.eat(food,1e-300)
        for _,case in ipairs({{.01003,'allowed'},{.01002,'denied'},{.00999,'denied'}})do
            food.hunger=-case[1]
            assert(s.model.evaluate({entry(tiny)}).status==case[2],
                'an underflow-sized request cannot bypass replacement protection around the native .01 tail')
        end
    end
    end
    -- Capacity scans cover the whole projected prefix, including food outside
    -- the selected transfers' item component. An edit contract is conditional;
    -- its existence alone cannot certify a dormant consumption replacement.
    for _,client in ipairs({false,true})do
    for _,custom in ipairs({false,true})do
    for _,case in ipairs({{'full',{1},false},{'two-halves',{.5,.5},false},{'safe-partials',{.5,.25},true}})do
        local s=setup();isClient=function()return client end
        local food=replacementFood(s,custom);local eats,entries={},{}
        for _,portion in ipairs(case[2])do
            local action=s.eat(food,portion);eats[#eats+1]=action
            entries[#entries+1]={action=action,edit=assert(s.adapters.food(action))}
        end
        local itemA,itemB=s.item(),s.item();itemA.container=s.root;itemB.container=s.root
        local transferA=s.transfer(itemA,s.root,s.bagInventory)
        local transferB=s.transfer(itemB,s.root,s.bagInventory)
        local head=s.f.action(ISReadABook,{item=s.item()});head.action={}
        local q=#eats==1 and s.f.queue(head,eats[1],transferA,transferB)
            or s.f.queue(head,eats[1],eats[2],transferA,transferB)
        assert((s.model.evaluate(entries).status=='allowed')==case[3],
            'capacity fixture must independently prove or deny its native food sequence: '..case[1])
        local decision=s.policy.evaluateMove(q,transferB,transferA,false)
        assert(decision.allowed==case[3],
            'unrelated transfer reorder must certify every replacement-food step in its capacity prefix: '..case[1])
        -- Cancellation projects the removed food as snapshot-only. The full
        -- action's effect must not be retained as an uncertified capacity step.
        assert(s.policy.evaluateCancel(q,eats[1]).allowed,
            'cancelled replacement food leaves a certified capacity prefix for unrelated transfers: '..case[1])
        assert(food.hunger==-.15 and itemA.container==s.root and itemB.container==s.root,
            'capacity inspection must not execute eating or transfers')
    end
    for _,state in ipairs({'active','started','operation-started'})do
        local s=setup();isClient=function()return client end
        local food=replacementFood(s,custom);food.hunger=-.12
        local eating=s.eat(food,.5)
        assert(s.adapters.food(eating),'in-flight fixture amount would permit the pending partial action')
        local itemA,itemB=s.item(),s.item();itemA.container=s.root;itemB.container=s.root
        local transferA=s.transfer(itemA,s.root,s.bagInventory)
        local transferB=s.transfer(itemB,s.root,s.bagInventory)
        local q
        if state=='active'then
            eating.action={};q=s.f.queue(eating,transferA,transferB)
        else
            local head=s.f.action(ISReadABook,{item=s.item()});head.action={}
            q=s.f.queue(head,eating,transferA,transferB)
            if state=='started'then eating.started=true else eating.toolkitQueueOperation.toolkitStarted=true end
        end
        assert(not s.policy.evaluateMove(q,transferB,transferA,false).allowed,
            'capacity proof must not reproject an in-flight replacement-food step from its partially reflected live state: '..state)
        assert(food.hunger==-.12,'in-flight capacity inspection must preserve the live partial amount')
    end
    do
        local s=setup();isClient=function()return client end
        local food=replacementFood(s,custom);food.container=s.bagInventory
        local half,quarter=s.eat(food,.5),s.eat(food,.25)
        local pickup=s.transfer(food,s.bagInventory,s.root)
        local returning=s.transfer(food,s.root,s.bagInventory)
        local itemA,itemB=s.item(),s.item();itemA.container=s.root;itemB.container=s.root
        local transferA=s.transfer(itemA,s.root,s.bagInventory)
        local transferB=s.transfer(itemB,s.root,s.bagInventory)
        local head=s.f.action(ISReadABook,{item=s.item()});head.action={}
        local q=s.f.queue(head,pickup,half,quarter,returning,transferA,transferB)
        assert(s.policy.evaluateMove(q,transferB,transferA,false).allowed,
            'capacity food proof includes the required carried pickup and surviving original-food return')
        assert(not s.policy.evaluateCancel(q,pickup).allowed,
            'capacity proof cannot cancel a pickup required by retained replacement-food portions')
        assert(not s.policy.evaluateMove(q,returning,half,false).allowed,
            'capacity proof cannot return replacement food to its bag before retained eating')
        assert(s.policy.evaluateCancel(q,returning).allowed,
            'cancelling a tail return leaves the same safe partial-food capacity prefix')
    end
    end
    end
    local s=setup();local food,script,output=replacementFood(s);local action=s.eat(food,.5)
    -- Both instance and script metadata may declare the replacement independently.
    local itemReplacement=food.getReplaceOnUse;food.getReplaceOnUse=function()end
    assert(s.adapters.food(action),'a script-declared replacement receives the partial-survival requirement')
    food.getReplaceOnUse=itemReplacement
    local scriptReplacement=script.getReplaceOnUse;script.getReplaceOnUse=function()end
    assert(s.adapters.food(action),'an instance-declared replacement receives the same partial-survival requirement')
    script.getReplaceOnUse=scriptReplacement
    for _,value in ipairs({'',false,0,{}})do
        food.getReplaceOnUseFullType=function()return value end
        assert(not s.adapters.food(action),'malformed replacement full type stays protected')
    end
    food.getReplaceOnUseFullType=function()end
    assert(not s.adapters.food(action),'missing replacement full type stays protected')
    food.getReplaceOnUseFullType=function()return 'Base.UnknownContainer'end
    assert(not s.adapters.food(action),'unresolved replacement script stays protected')
    food.getReplaceOnUseFullType=function()return 'Base.TinCanEmpty'end
    for _,value in ipairs({true,false,'-.15',{},0,.15,math.huge,-math.huge,0/0})do
        script.hunger=value;assert(not s.adapters.food(action),'replacement weight proof requires finite negative native script hunger')
    end
    script.hunger=nil;assert(not s.adapters.food(action),'missing script hunger cannot prove partial replacement weight')
    script.hunger=-.15
    for _,target in ipairs({script,output})do
        for _,value in ipairs({false,'0.2',{},-.1,math.huge,-math.huge,0/0})do
            target.weight=value;assert(not s.adapters.food(action),'invalid source/output weight cannot prove safe partial food weight')
        end
        target.weight=nil;assert(not s.adapters.food(action),'missing source/output weight cannot prove safe partial food weight')
        target.weight=target==script and .8 or .2
    end
    output.weight=.800001
    assert(not s.adapters.food(action),'heavier replacement can make partially eaten food gain weight')
    output.weight=.8;assert(s.adapters.food(action),'equal source/output script weights preserve the transfer bound')
    output.weight=0;assert(s.adapters.food(action),'zero empty-container script weight preserves the transfer bound')
    output.weight=.2
    local previousExtras=food.haveExtraItems;food.haveExtraItems=function()return true end
    assert(not s.adapters.food(action),'evolved food weight is outside the audited native weight formula')
    food.haveExtraItems=previousExtras
    for _,spec in ipairs({{'getOnEat','custom.callback'},{'getOnCooked','custom.callback'},
        {'getReplaceOnRotten','Base.Rotten'},{'isTainted',true},{'getPoisonPower',1}})do
        local name,value=spec[1],spec[2];local previous=food[name];food[name]=function()return value end
        assert(not s.adapters.food(action),'partial output permission cannot bypass unknown food effects: '..name)
        food[name]=previous
    end
    script.getReplaceOnDeplete=function()return 'Base.TinCanEmpty'end
    assert(not s.adapters.food(action),'ReplaceOnDeplete remains outside the partial ReplaceOnUse contract')
    script.getReplaceOnDeplete=function()end
    local manager=ScriptManager;ScriptManager=nil
    assert(not s.adapters.food(action),'missing script manager cannot resolve replacement weight')
    ScriptManager={};assert(not s.adapters.food(action),'missing script manager instance cannot resolve replacement weight')
    ScriptManager=manager
    local helper=ISEatFoodAction.isEatingRemaining;ISEatFoodAction.isEatingRemaining=function()error('foreign partial helper must not execute')end
    assert(not s.adapters.food(action),'partial replacement permission retains native helper proof')
    ISEatFoodAction.isEatingRemaining=helper
    assert(s.adapters.food(action),'restoring the exact native helper restores partial replacement permission')
    for _,client in ipairs({false,true})do
        local s=setup();isClient=function()return client end
        local food,script,output=replacementFood(s,true);local action=s.eat(food,.5)
        -- Custom no-extra weight bypasses the script hunger/weight branch. It
        -- still resolves the empty shell, but inspection never creates it.
        script.getHungerChange=function()error('custom weight must not consult script hunger')end
        script.getActualWeight=function()error('custom weight must not consult script weight')end
        assert(s.adapters.food(action),'custom no-extra replacement follows its distinct native weight branch')
        for _,field in ipairs({'weight','actualWeight'})do
            for _,value in ipairs({false,'0.8',{},-.1,.199999,math.huge,-math.huge,0/0})do
                food[field]=value
                assert(not s.adapters.food(action),'invalid custom live weight must fail closed: '..field)
            end
            food[field]=nil
            assert(not s.adapters.food(action),'missing custom live weight must fail closed: '..field)
            food[field]=.8
        end
        for _,value in ipairs({false,'0.2',{},-.1,.800001,math.huge,-math.huge,0/0})do
            output.weight=value
            assert(not s.adapters.food(action),'custom empty shell must be finite, nonnegative and bounded by both live weights')
        end
        output.weight=nil;assert(not s.adapters.food(action),'custom empty shell weight cannot be missing')
        output.weight=.8;assert(s.adapters.food(action),'custom weight can equal its empty shell')
        output.weight=0;assert(s.adapters.food(action),'custom weight permits a zero-weight empty shell')
        output.weight=.2
        food.haveExtraItems=function()return true end
        assert(not s.adapters.food(action),'custom evolved extras retain their separate native weight and callback barrier')
        food.haveExtraItems=function()return false end
        for _,name in ipairs({'getOnEat','getOnCooked'})do
            food[name]=function()return 'custom.callback'end
            assert(not s.adapters.food(action),'custom weight cannot authorize an unaudited callback: '..name)
            food[name]=function()end
        end
        local complete=ISEatFoodAction.complete
        ISEatFoodAction.complete=function()error('foreign custom-weight effect must not execute')end
        assert(not s.adapters.food(action),'custom partial food retains live native effect identity proof')
        ISEatFoodAction.complete=complete
        assert(s.adapters.food(action),'restoring the exact native effect restores custom partial permission')
    end
    do
        local s=setup('ISEatFoodAction.lua');local food=replacementFood(s,true)
        assert(not s.adapters.food(s.eat(food,.5)),'custom partial food cannot bypass changed native source proof')
    end
end
do
    local function evolvedFood(s)
        local food=s.food();food.hunger=-.06;food.base=-.06;food.actualWeight=.5
        food.haveExtraItems=function()return true end
        food.extraTypes={'Base.Tomato'}
        food.extras={size=function()return #food.extraTypes end,get=function(_,index)return food.extraTypes[index+1]end}
        food.getReplaceOnUse=function()return 'Base.Bowl'end
        food.getReplaceOnUseFullType=food.getReplaceOnUse
        local script=food:getScriptItem()
        script.getReplaceOnUse=food.getReplaceOnUse
        script.getHungerChange=function()error('evolved weight does not use the base script hunger')end
        script.getActualWeight=function()error('evolved weight uses live unmodded base weight')end
        local extra={weight=.2,hunger=-12,kind='base:food'}
        extra.getItemType=function(self)return self.kind end
        extra.getHungerChange=function(self)return self.hunger end
        extra.getActualWeight=function(self)return self.weight end
        extra.getLuaCreate=function(self)return self.onCreate end
        extra.getItemConfig=function(self)return self.config end
        extra.getItemConfigKey=function(self)return self.configKey end
        extra.hasComponents=function(self)return self.components or false end
        extra.getReplaceOnUse=function(self)return self.replacement end
        s.scripts['Base.Tomato']=extra
        s.scripts['Base.Bowl']={getActualWeight=function()return .5 end}
        return food,extra
    end
    for _,client in ipairs({false,true})do
    for _,custom in ipairs({false,true})do
        local s=setup();isClient=function()return client end
        local food,extra=evolvedFood(s)
        food.isCustomWeight=function()return custom end
        local quarter,another=s.eat(food,.25),s.eat(food,.25)
        local whole=s.eat(food,1)
        local returning,pickup=s.transfer(food,s.root,s.bagInventory),s.transfer(food,s.bagInventory,s.root)
        local function impure()error('inspection must not materialize evolved ingredient prototypes')end
        food.getWeight,food.getActualWeight,food.getUnequippedWeight,food.getExtraItemsWeight=impure,impure,impure,impure
        InventoryItemFactory={CreateItem=impure}
        local function entry(action)return {action=action,edit=assert(s.adapters.food(action))}end
        assert(s.model.evaluate({entry(quarter),entry(another)}).status=='allowed')
        assert(s.model.evaluate({entry(whole)}).status=='denied','full evolved consumption cannot activate its bowl replacement')
        assert(s.model.evaluate({entry(s.eat(food,.5)),entry(s.eat(food,.5))}).status=='denied',
            'every evolved portion must preserve the strict native tail')
        s.water.container=s.root
        local anchor=s.drink();anchor.action={}
        local q=s.f.queue(anchor,quarter,another,whole)
        assert(s.policy.evaluateCancel(q,whole).allowed,'pending full evolved consumption can be removed')
        q=s.f.queue(anchor,quarter,another)
        assert(s.policy.evaluateMove(q,quarter,another,true).allowed,'safe evolved original portions can reorder without weight reads')
        assert(s.policy.evaluateCancel(q,quarter).allowed,'safe pending evolved portions can cancel without weight reads')
        assert(s.adapters.transfer(returning),
            'reviewed evolved return uses pure upper weight before bag admission')
        food.container=s.bagInventory
        assert(s.adapters.transfer(pickup),
            'reviewed evolved pickup receives the same exact location proof')
        food.container=s.root
        local a,b=s.item(),s.item();a.container=s.root;b.container=s.root
        local transferA,transferB=s.transfer(a,s.root,s.bagInventory),s.transfer(b,s.root,s.bagInventory)
        s.root.getCapacityWeight=impure
        s.bagInventory.getCapacityWeight=function()if food.container==s.bagInventory then impure()end;return 0 end
        q=s.f.queue(anchor,quarter,transferA,transferB)
        assert(s.policy.evaluateMove(q,transferB,transferA,false).allowed,
            'global capacity prefix admits surviving evolved food using pure current bounds')
        for _,location in ipairs({s.root,s.bagInventory})do
            food.container=location
            q=s.f.queue(anchor,transferA,transferB)
            assert(s.policy.evaluateMove(q,transferB,transferA,false).allowed,
                'untouched reviewed extras use pure container loads without native factory reads')
        end
        -- The interval's upper bound may charge incoming space, but must never
        -- be subtracted as a supposedly confirmed SP release.
        food.container=s.bagInventory
        a.getUnequippedWeight=function()return .4 end;b.getUnequippedWeight=function()return .4 end
        s.bagInventory.capacity=.9
        q=s.f.queue(anchor,pickup,transferA,transferB)
        local tight=s.policy.evaluateMove(q,transferB,transferA,false)
        assert(not tight.allowed and tight.reason=='container_capacity',
            'an evolved upper bound cannot become source release credit in SP or Host')
        s.bagInventory.capacity=50
        assert(s.policy.evaluateMove(q,transferB,transferA,false).allowed,
            'the same pure evolved transfer prefix remains editable with sufficient real capacity')
        food.container=s.root
        for _,spec in ipairs({{'kind','base:normal'},{'hunger',0},{'hunger',math.huge},{'hunger',0/0},
            {'weight',-.1},{'weight',3.4028234663852886e38},{'weight',math.huge},{'weight',0/0},
            {'onCreate','callback'},{'config',{}},{'configKey','custom'},{'components',true},{'replacement','Base.Bowl'}})do
            local field,value=spec[1],spec[2];local previous=extra[field];extra[field]=value
            assert(not s.adapters.food(quarter),'unknown evolved ingredient metadata stays protected: '..field)
            extra[field]=previous
        end
        for _,types in ipairs({{}, {'Base.Unknown'}, {'Base.Tomato','Base.Tomato','Base.Tomato','Base.Tomato','Base.Tomato','Base.Tomato','Base.Tomato'}})do
            food.extraTypes=types;assert(not s.adapters.food(quarter),'unbounded or unresolved extra lists stay protected')
        end
        food.extraTypes={'Base.Tomato'}
        for _,weight in ipairs({.49999,math.huge,0/0})do
            food.actualWeight=weight;assert(not s.adapters.food(quarter),'evolved live base must be finite and at least its shell')
        end
        food.actualWeight=.5
        assert(s.adapters.food(quarter),'restoring reviewed native ingredient metadata restores pure partial proof')
        assert(food.hunger==-.06 and food.base==-.06 and food.container==s.root and quarter.percentage==.25,
            'all evolved inspections preserve captured portions, nutrition and location')
    end
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
do
    for _,client in ipairs({false,true})do
        local s=setup();isClient=function()return client end
        local storage,parent,tile=s.world();local food=s.food();food.container=storage
        local pickup,eating,returning=s.transfer(food,storage,s.root),s.eat(food,.5),s.transfer(food,s.root,storage)
        local a,b,c=assert(s.adapters.transfer(pickup)),assert(s.adapters.food(eating)),assert(s.adapters.transfer(returning))
        assert(s.model.evaluate({{action=returning,edit=c},{action=pickup,edit=a},{action=eating,edit=b}}).status=='allowed')
        s.water.container=s.root;local anchor=s.drink();anchor.action={}
        local q=s.f.queue(anchor,pickup,eating,returning)
        assert(s.policy.evaluateMove(q,returning,pickup,false).allowed,'adjacent ordinary world return can precede its pickup as a no-op')
        assert(not s.policy.evaluateMove(q,pickup,eating,true).allowed and not s.policy.evaluateCancel(q,pickup).allowed,
            'world food retains exact root-location pickup prerequisite')
        assert(s.policy.evaluateCancel(q,returning).allowed,'explicit world return can be cancelled without cancelling the food')
        local independent=s.item();independent.container=storage
        local secondPickup=s.transfer(independent,storage,s.root)
        local separate=s.f.queue(anchor,pickup,secondPickup)
        assert(s.policy.evaluateMove(separate,secondPickup,pickup,false).allowed,
            'different exact items sharing the same anchored world container remain independently movable')
        q=s.f.queue(anchor,pickup,eating,returning)
        storage.load=49.5
        local tight=s.policy.evaluateMove(q,returning,pickup,false)
        assert(not tight.allowed and tight.reason=='container_capacity','world destination cannot spend the future pickup release')
        storage.load=0
        -- Hot items remain protected even when their world endpoint is cold;
        -- a cold carried item cannot return through an unproven thermal path.
        food.cookable=true;food.heat=2
        assert(not s.adapters.transfer(pickup)and not s.adapters.transfer(returning)and not s.adapters.food(eating))
        food.container=s.root;food.heat=1;storage.customTemperature=2
        assert(s.adapters.food(eating)and not s.adapters.transfer(returning),'carried food cannot open a custom-temperature world path')
        storage.customTemperature=0;food.container=storage
        assert(s.adapters.transfer(pickup)and s.adapters.transfer(returning)and s.adapters.food(eating),
            'constant-cold ordinary world storage admits cold cookable pickup/food/return')
        food.cookable=false
        food.isFavorite=function()return true end
        assert(s.adapters.transfer(pickup)and not s.adapters.transfer(returning),'native favorite outbound refusal is not modeled as success')
        food.isFavorite=function()return false end
        for _,kind in ipairs({'floor','proximityInv','twistInv_corpses','TradeUI','stove','microwave','fridge','freezer','clothingrack'})do
            storage.kind=kind;assert(not s.adapters.worldContainer(storage,s.f.player),'special world storage must remain protected: '..kind)
        end
        storage.kind='crate'
        for _,class in ipairs({'IsoDeadBody','IsoMannequin','IsoStove','IsoWorldInventoryObject','ForeignObject'})do
            parent.class=class;assert(not s.adapters.worldContainer(storage,s.f.player),'unknown/special parent must stay protected: '..class)
        end
        parent.class='IsoThumpable';assert(s.adapters.worldContainer(storage,s.f.player))
        for _,name in ipairs({'isDoor','isDoorFrame','isWindowN','isWindowW','isBarricaded','isLocked','isLockedByKey','isLockedByPadlock'})do
            parent[name..'Flag']=true;assert(not s.adapters.worldContainer(storage,s.f.player));parent[name..'Flag']=nil
        end
        parent.code=123;assert(not s.adapters.worldContainer(storage,s.f.player));parent.code=nil
        tile.present=false;assert(not s.adapters.transfer(pickup),'removed parent is rejected even while isExistYet and square pointers survive');tile.present=true
        storage.square={};assert(not s.adapters.transfer(pickup));storage.square=tile
        parent.container={};assert(not s.adapters.transfer(pickup));parent.container=storage
        storage.vehiclePart={};assert(not s.adapters.transfer(pickup));storage.vehiclePart=nil
        tile.x=5;assert(not s.adapters.transfer(pickup),'distant loaded storage is not adjacent');tile.x=1
        tile.z=1;assert(not s.adapters.transfer(pickup));tile.z=0
        storage.getAcceptItemFunction=function()return 'ForeignAccept'end;assert(not s.adapters.transfer(pickup));storage.getAcceptItemFunction=function()end
        storage.getOnlyAcceptCategory=function()return 'Food'end;assert(not s.adapters.transfer(pickup));storage.getOnlyAcceptCategory=function()end
        local otherStorage=s.world();assert(not s.adapters.transfer(s.transfer(food,storage,otherStorage)),'world-to-world transfers remain protected')
        assert(food.container==storage and food.hunger==-.4,'world inspection must not execute or mutate anything')
        local walk=s.f.action(ISWalkToTimedAction);q=s.f.queue(anchor,pickup,eating,walk,returning)
        assert(not s.policy.evaluateMove(q,returning,pickup,false).allowed,'world transfer must not cross native walking dependencies')
    end
    print('World storage edit contracts: anchored adjacent endpoints, exact pickup/return, capacity, favorite/cookable restrictions, missing objects and movement barriers passed.')
end
do
    local function worldBag(s,parent)
        local owner=s.item();owner.class='InventoryContainer';owner.container=parent
        owner.getFullType=function()return 'Base.Bag_Schoolbag'end
        owner.getType=function()return 'Bag_Schoolbag'end
        owner.getMaxItemSize=function(self)return self.maximum or 0 end
        local inventory=s.container(owner)
        inventory.isInCharacterInventory=function()return false end
        owner.getInventory=function()return inventory end
        return owner,inventory
    end
    local s=setup();local storage,parent,tile=s.world()
    local outer,outerInventory=worldBag(s,storage)
    local inner,inventory=worldBag(s,outerInventory)
    local food=s.food();food.container=inventory
    local chain=assert(s.adapters.worldContainer(inventory,s.f.player))
    assert(#chain==3 and chain[1]==inventory and chain[2]==outerInventory and chain[3]==storage,
        'SP world ancestry must preserve every exact container in destination-first order')
    local pickup,eating,returning=s.transfer(food,inventory,s.root),s.eat(food,.5),s.transfer(food,s.root,inventory)
    for _,action in ipairs({pickup,eating,returning})do
        local contract=assert(s.policy.inspect(action));assert(contract.edit,'nested world SP contract missing')
    end
    local footprint=s.policy.inspect(pickup)
    assert(footprint.containerOwners[outer:getID()]and footprint.containerOwners[inner:getID()]
        and footprint.targets[parent]and footprint.positions[s.f.player],
        'both owner identities, world anchor and movement join the dependency footprint')
    s.water.container=s.root;local anchor=s.drink();anchor.action={}
    local q=s.f.queue(anchor,pickup,eating,returning)
    assert(s.policy.evaluateMove(q,returning,pickup,false).allowed,'SP can reorder a proven nested-world return before pickup')
    assert(s.policy.evaluateCancel(q,returning).allowed,'pending explicit nested-world return can be cancelled')
    assert(not s.policy.evaluateCancel(q,pickup).allowed and not s.policy.evaluateMove(q,pickup,eating,true).allowed,
        'nested-world pickup remains required by eating')
    for _,container in ipairs({inventory,outerInventory,storage})do
        container.load=49.5
        local decision=s.policy.evaluateMove(q,returning,pickup,false)
        assert(not decision.allowed and decision.reason=='container_capacity',
            'a full ancestor cannot spend the future pickup release')
        container.load=0
    end
    inner.maximum=.5;assert(not s.adapters.transfer(returning),'immediate destination bag size remains mandatory');inner.maximum=0
    local independent=s.item();independent.container=s.root
    local incoming=s.transfer(independent,s.root,inventory)
    inventory.load=49.5
    local credit=s.policy.evaluateMove(s.f.queue(anchor,incoming,pickup),incoming,pickup,true)
    assert(not credit.allowed and credit.reason=='container_capacity',
        'a source-world bag with nil parent must never receive carried SP release credit')
    inventory.load=0
    local methods={}
    for _,name in ipairs({'isValid','start','perform','stop'})do methods[name]=ISInventoryTransferAction[name]end
    local helpersUnchanged=true
    assert(s.policy.adoptTransferMethods(methods,methods,function()return helpersUnchanged end))
    assert(s.policy.isOrdinaryTransfer(pickup)and s.adapters.transfer(pickup),
        'approved transfer-method adoption retains the exact SP nested endpoint scope')
    helpersUnchanged=false
    assert(not s.policy.isOrdinaryTransfer(pickup)and not s.adapters.transfer(pickup),
        'nested proof does not bypass a changed adopted helper')
    helpersUnchanged=true
    -- Another pending owner mutation is outside the leaf transfer proof.
    local moveOwner=s.transfer(outer,storage,s.root)
    assert(not s.adapters.transfer(moveOwner))
    local coupled=s.f.queue(anchor,moveOwner,pickup,eating,returning)
    assert(not s.policy.evaluateMove(coupled,returning,moveOwner,false).allowed,
        'a pending bag move is not independent of its nested item transfers')
    local walk=s.f.action(ISWalkToTimedAction)
    assert(not s.policy.evaluateMove(s.f.queue(anchor,pickup,walk,returning),returning,pickup,false).allowed,
        'nested world endpoint cannot move across walking')
    isClient=function()return true end
    assert(not s.adapters.worldContainer(inventory,s.f.player)and not s.adapters.transfer(pickup)
        and not s.adapters.food(eating)and not s.adapters.transfer(returning),
        'Host must not promise a nested-world ContainerID that native packets cannot encode')
    assert(s.adapters.worldContainer(storage,s.f.player),'direct ordinary world Host endpoints remain supported')
    isClient=function()return false end
    local function rejected(message)
        assert(not s.adapters.worldContainer(inventory,s.f.player)and not s.adapters.transfer(pickup),message)
    end
    outer.container=nil;rejected('detached outer owner');outer.container=storage
    local original=storage.getItemById
    storage.getItemById=function()return {}end;rejected('same-ID replacement cannot substitute owner reference');storage.getItemById=original
    inner.container=inventory;rejected('owner cycle');inner.container=outerInventory
    inner.getInventory=function()return {}end;rejected('owner no longer owns exact inner inventory');inner.getInventory=function()return inventory end
    inner.getWorldItem=function()return {}end;rejected('owner has a competing world item');inner.getWorldItem=function()end
    inner.consumed=true;rejected('consumed owner');inner.consumed=nil
    inner.getAttachedSlot=function()return 0 end;rejected('attached owner');inner.getAttachedSlot=function()return -1 end
    inventory.getAcceptItemFunction=function()return 'Unknown'end;rejected('unknown nested accept callback');inventory.getAcceptItemFunction=function()end
    outerInventory.getOnlyAcceptCategory=function()return 'Food'end;rejected('unknown ancestor category restriction');outerInventory.getOnlyAcceptCategory=function()end
    inventory.getVehiclePart=function()return {}end;rejected('nested vehicle endpoint');inventory.getVehiclePart=function()end
    inventory.getParent=function()return parent end;rejected('conflicting direct parent');inventory.getParent=function()end
    tile.present=false;rejected('removed world anchor despite surviving pointers');tile.present=true
    assert(s.adapters.transfer(pickup)and food.container==inventory and food.hunger==-.4,
        'restored ancestry revalidates without executing transfers or food effects')
    food.cookable=true
    assert(s.adapters.food(eating)and s.adapters.transfer(pickup)and s.adapters.transfer(returning),
        'cold SP nested-world cookable proof follows its exact outer crate')
    inventory.customTemperature=4;outerInventory.temperature=4
    assert(s.adapters.food(eating)and s.adapters.transfer(returning),
        'native heating ignores every inner bag temperature')
    storage.customTemperature=1
    assert(not s.adapters.food(eating)and not s.adapters.transfer(returning),
        'even a currently cold custom world temperature retains protection')
    storage.customTemperature=0;inventory.customTemperature=0;outerInventory.temperature=1
    local nativeOutermost=inventory.getOutermostContainer
    inventory.getOutermostContainer=function()return s.root end
    assert(not s.adapters.food(eating)and not s.adapters.transfer(pickup),'native outermost must match the validated world chain')
    inventory.getOutermostContainer=nativeOutermost
    inner.container=inventory
    inventory.getOutermostContainer=function()error('must not recurse into an unvalidated cycle')end
    assert(not s.adapters.food(eating)and not s.adapters.transfer(pickup),'reject owner cycles before native recursion')
    inner.container=outerInventory;inventory.getOutermostContainer=nativeOutermost
    isClient=function()return true end
    assert(not s.adapters.food(eating)and not s.adapters.transfer(returning),'cold proof does not bypass Host world-bag exclusion')
    isClient=function()return false end;food.cookable=false
    -- The legacy active path finishes the native step, then settles cleanup;
    -- it must not turn pending-only projection into an early/duplicate effect.
    s.f.project('ActionQueueLabels')
    local completions=0
    ISTimedActionQueue.onCompleted=function(queue,action)
        assert(queue.current==action and queue.queue[1]==action)
        completions=completions+1;table.remove(queue.queue,1);queue.current=queue.queue[1]
    end
    ISInventoryPaneContextMenu.getContainers=function()return {contains=function(_,value)return value==inventory end}end
    ISInventoryTransferUtil={newInventoryTransferAction=function(player,item,source,destination)
        return s.transfer(item,source,destination)
    end}
    PZSurvivorToolkit.BulkActions.guardTransfer=function()end
    local api=s.f.project('ActionQueue')
    local spare=s.item();spare.container=outerInventory
    local waiting=s.transfer(spare,outerInventory,s.root)
    local token={toolkitStarted=true};pickup.toolkitQueueOperation=token;waiting.toolkitQueueOperation=token
    returning.toolkitQueueOperation=token;returning.allowMissingItems=true
    local tail=s.drink();q=s.f.queue(pickup,waiting,returning,tail)
    pickup.started=true
    pickup.action={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end,
        stopTimedActionAnim=function()end,setLoopedAction=function()end,setTime=function()end}
    assert(not s.adapters.transfer(pickup),'active native step has no projected pending-edit contract')
    assert(not s.policy.evaluateMove(q,pickup,tail,true).allowed,'active nested pickup cannot be reordered')
    s.f.player.getFullName=function()return 'Queue Test'end
    food.setChef=function(self,name)self.chef=name end
    local picked,returned=0,0
    local rootAdd,bagAdd=s.root.AddItem,inventory.AddItem
    s.root.AddItem=function(self,item)picked=picked+1;return rootAdd(self,item)end
    inventory.AddItem=function(self,item)returned=returned+1;return bagAdd(self,item)end
    local originalList=pickup.queueList
    local cancelled,reason=api.cancelOperation(q,pickup)
    assert(cancelled,'reviewed active nested transfer can finish its current native step: '..tostring(reason))
    assert(q.toolkitGroupCancel and not q.toolkitCancel and pickup.queueList==originalList
        and #q.queue==4 and food.container==inventory and picked==0 and returned==0,
        'cancelling active pickup cannot stop it, rewrite its list, move items or drop the pending tail early')
    pickup:perform()
    assert(picked==1 and returned==0 and food.container==s.root and food.hunger==-.4
        and spare.container==outerInventory and completions==1 and #q.queue==2 and q.queue[2]==tail,
        'native pickup commits once; cancelled waiting pickup is not executed and independent tail survives')
    local cleanup=q.queue[1]
    assert(cleanup~=returning and cleanup.Type=='ISInventoryTransferAction'and cleanup.item==food
        and cleanup.srcContainer==s.root and cleanup.destContainer==inventory and cleanup.allowMissingItems,
        'settlement creates one native cleanup return to the exact discoverable nested source')
    cleanup.action={stopTimedActionAnim=function()end,setLoopedAction=function()end,setTime=function()end}
    cleanup:perform()
    assert(picked==1 and returned==1 and food.container==inventory and food.hunger==-.4
        and completions==2 and #q.queue==1 and q.current==tail and not tail.toolkitQueueOperation.toolkitCancelled,
        'native cleanup returns the original once and preserves the unrelated operation')
    print('SP nested world bags: exact owner chain, each ancestor capacity, membership loss, owner/movement barriers and Host exclusion passed.')
end
do
    for _,client in ipairs({false,true})do
        local s=setup();isClient=function()return client end
        local storage,parent=s.world();local food=s.food();food.cookable=true;food.container=storage
        food.getReplaceOnCooked=function()return {isEmpty=function()return false end}end
        local pickup,eating,returning=s.transfer(food,storage,s.root),s.eat(food,.5),s.transfer(food,s.root,storage)
        assert(s.adapters.transfer(pickup)and s.adapters.food(eating)and s.adapters.transfer(returning),
            'cold native cooking replacement stays dormant across ordinary world endpoints')
        s.water.container=s.root;local anchor=s.drink();anchor.action={}
        local q=s.f.queue(anchor,pickup,eating,returning)
        assert(s.policy.evaluateMove(q,returning,pickup,false).allowed)
        for _,field in ipairs({'isFridge','isFreezer','isStove','isMicrowave','isTemperatureChanging'})do
            storage[field..'Flag']=true
            assert(not s.adapters.transfer(pickup)and not s.adapters.transfer(returning)and not s.adapters.food(eating),
                'thermal world classification is a live guard independent of its crate type: '..field)
            storage[field..'Flag']=false
        end
        for _,value in ipairs({-1,.5,1,2,math.huge,0/0})do
            storage.customTemperature=value
            assert(not s.adapters.transfer(pickup)and not s.adapters.food(eating),'nonzero/invalid custom temperature remains protected')
        end
        storage.customTemperature=0
        for _,value in ipairs({-1,1.7,math.huge,0/0})do
            food.heat=value
            assert(not s.adapters.transfer(pickup)and not s.adapters.food(eating),'hot/invalid food heat cannot certify world edits')
        end
        food.heat=1
        s.root.temperature=2
        assert(not s.adapters.transfer(pickup)and not s.adapters.food(eating),'both actor and world ambient must be cold')
        s.root.temperature=1
        food.fertilized=true
        assert(not s.adapters.transfer(pickup)and not s.adapters.food(eating),'cold egg hatching lies outside the cooking heat gate')
        food.fertilized=false
        food.getReplaceOnRotten=function()return 'Base.OtherFood'end
        assert(not s.adapters.transfer(pickup)and not s.adapters.food(eating),'rotting replacement is not protected by cold ambient')
        food.getReplaceOnRotten=function()end
        food.tags={[ItemTag.ALREADY_COOKED]=true}
        assert(not s.adapters.transfer(pickup)and not s.adapters.food(eating),'cold ALREADY_COOKED mutation remains protected')
        food.tags=nil
        local a,b=s.item(),s.item();a.container=s.root;b.container=s.root
        local first,second=s.transfer(a,s.root,s.bagInventory),s.transfer(b,s.root,s.bagInventory)
        food.container=s.root
        local prefix=s.f.queue(anchor,returning,first,second)
        assert(s.policy.evaluateMove(prefix,second,first,false).allowed,'independent transfer prefix admits a proven cold world return')
        for _,change in ipairs({'world-heat','food-heat','fertilized','rotting-replacement','already-cooked'})do
            if change=='world-heat'then storage.customTemperature=2
            elseif change=='food-heat'then food.heat=2
            elseif change=='fertilized'then food.fertilized=true
            elseif change=='rotting-replacement'then food.getReplaceOnRotten=function()return 'Base.OtherFood'end
            else food.tags={[ItemTag.ALREADY_COOKED]=true}end
            local decision=s.policy.evaluateMove(prefix,second,first,false)
            assert(not decision.allowed and decision.reason=='container_capacity',
                'global capacity prefix cannot bypass the cold proof outside its selected food component: '..change)
            storage.customTemperature=0;food.heat=1;food.fertilized=false;food.tags=nil;food.getReplaceOnRotten=function()end
        end
        local unknown=s.f.action(ISBaseTimedAction,{object=parent})
        assert(not s.policy.evaluateMove(s.f.queue(anchor,pickup,unknown,returning),returning,pickup,false).allowed,
            'unmodeled world-anchor mutations retain their barrier')
        assert(food.container==s.root and food.hunger==-.4,'thermal inspection executes no native consumption or transfer')
    end
    print('Cold cookable world edits: constant ambient, native outermost, dormant replacements, state/callback barriers and global capacity prefix passed.')
end
print('Food edit adapters: original portions, cold cookable state, dormant cooked replacements and surviving ordinary/custom-weight partial use replacements, depletion/location/fullness dependencies, pending cancellation and callback guards passed.')
