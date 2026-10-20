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
    f.native('shared/RadioCom/ISRadioAction.lua')
    if alias=='drink-native' then ISDrinkFluidAction.complete=ISDrinkFluidAction.isValid
    elseif alias=='drink-base' then ISDrinkFluidAction.complete=ISBaseTimedAction.perform
    elseif alias=='base' then ISBaseTimedAction.perform=ISBaseTimedAction.stop end
    isClient,isServer=function()return false end,function()return false end
    getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    getGameFilesInput=function(path)
        local text=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
        if changed and path:find(changed,1,true)then text=text..'-- changed source\n'end
        return reader(text)
    end
    getModFileReader=function(_,path)return reader(read(ProjectRoot..'/PZSurvivorToolkit/42/'..path))end
    getTimestampMs=function()return 1 end;getCore=function()return {getGameMode=function()return 'Sandbox'end}end
    CharacterTrait={DEXTROUS=1,ALL_THUMBS=2};MoodleType={FOOD_EATEN=1};Fluid={Water={}}
    ItemContainer={floatingPointCorrection=function(value)return math.floor(value*100+0.5)/100 end}
    round=function(value)return value end
    f.player.class='IsoPlayer'
    f.player.hasTrait=function()return false end;f.player.isWearingAwkwardGloves=function()return false end
    f.player.isEquipped=function()return false end;f.player.removeAttachedItem=function()end
    f.player.setIsFarming=function()end;f.player.getVehicle=function()end
    f.player.getOverlaySprite=function()end
    f.player.getMoodles=function()return {getMoodleLevel=function()return 0 end}end
    f.player.getEmitter=function()return {isPlaying=function()return false end,playSound=function()return 1 end}end
    local square={TreatAsSolidFloor=function()return true end,isSolid=function()return false end,isSolidTrans=function()return false end,
        getTotalWeightOfItemsOnFloor=function()return 0 end}
    f.player.getCurrentSquare=function()return square end
    ISLogSystem={logAction=function()end};ItemPicker={updateOverlaySprite=function()end}
    local baseInstanceof=instanceof
    instanceof=function(value,kind)return baseInstanceof(value,kind)or type(value)=='table'and kind=='IsoGameCharacter'and value.class=='IsoPlayer'end
    local knownItems={}
    local function container(owner)
        local c={class='ItemContainer',owner=owner}
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
    local function runTransfer(action)
        local q=f.queue(action);q.onCompleted=function()end
        action.action={stopTimedActionAnim=function()end,setLoopedAction=function()end,setTime=function()end}
        assert(action:isValid());action:perform();action.action=nil
    end
    return {f=f,adapters=adapters,model=model,policy=policy,root=root,bag=bag,bagInventory=bagInventory,water=water,fluid=fluid,
        properties=properties,item=item,transfer=transfer,drink=drink,runTransfer=runTransfer,drinks=function()return drinks end}
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
    s.f.native('shared/TimedActions/ISEatFoodAction.lua');s.policy.installContracts()
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
    local s=setup('ISDrinkFluidAction.lua');assert(not s.adapters.drink(s.drink()))
end
print('Item edit adapters: native idempotent transfers, captured SP water ratios, conservative Host intervals, source/helper and location guards passed.')
