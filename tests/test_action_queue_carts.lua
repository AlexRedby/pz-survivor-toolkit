-- Client Lua files auto-load even when their optional mod is absent.
do
    local previousRequire,previousMods,previousToolkit=require,getActivatedMods,PZSurvivorToolkit
    local previousCore,previousClass,previousTransfer,previousEvents=SaucedCarts,ISCartTransferAction,ISInventoryTransferAction,Events
    local constructor,perform,transferItem=function() end,function() end,function() end
    local transfer={new=constructor,perform=perform,transferItem=transferItem}
    local add=function() error('absent cart mod must not install event hooks') end
    require=function() error('absent cart mod must return before require') end
    getActivatedMods=function() return {contains=function(_,id) assert(id=='SaucedCarts');return false end} end
    PZSurvivorToolkit,SaucedCarts,ISCartTransferAction,ISInventoryTransferAction={},nil,nil,transfer
    Events={OnGameStart={Add=add}}
    assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCarts.lua'))()
    assert(not PZSurvivorToolkit.ActionQueueCarts and not SaucedCarts and not ISCartTransferAction)
    assert(ISInventoryTransferAction==transfer and transfer.new==constructor and transfer.perform==perform and transfer.transferItem==transferItem)
    assert(Events.OnGameStart.Add==add,'absent cart mod replaced a native event hook')
    require,getActivatedMods,PZSurvivorToolkit=previousRequire,previousMods,previousToolkit
    SaucedCarts,ISCartTransferAction,ISInventoryTransferAction,Events=previousCore,previousClass,previousTransfer,previousEvents
end
if not NativeActionRoot or not SaucedCartsSource then
    print('Cart action queue contracts SKIP (pass native action and SaucedCarts source roots).'); return
end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
getActivatedMods=function() return {contains=function(_,id) return id=='SaucedCarts' end} end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r','') end
    local file=assert(io.open(path));local value=file:read('*a');file:close();return value:gsub('\r','')
end
local function source(value,path) return assert(loadstring(value,'@'..path))() end
local clientRoot=SaucedCartsSource:gsub('/shared/SaucedCarts/?$','/client/SaucedCarts')
local p,inv=f.player,f.player.inventory
p.class='IsoPlayer';p.isLocalPlayer=function() return true end;p.isDraggingCorpse=function() return false end
local client,server=false,false
isClient=function() return client end;isServer=function() return server end
local vanillaConstructor,vanillaPerform,vanillaTransferItem=ISInventoryTransferAction.new,ISInventoryTransferAction.perform,ISInventoryTransferAction.transferItem
local vanillaMethods={};for _,name in ipairs({'isValid','start','perform','stop'}) do vanillaMethods[name]=ISInventoryTransferAction[name] end
local fixtureOrigins={}
local nativeFilename=NativeFilenameOfClosure or function(callback) return debug.getinfo(callback,'S').source:gsub('^@','') end
getFilenameOfClosure=function(callback)
    if callback==vanillaConstructor or callback==vanillaPerform or callback==vanillaTransferItem then return NativeActionRoot..'/client/TimedActions/ISInventoryTransferAction.lua' end
    if fixtureOrigins[callback] then return fixtureOrigins[callback] end
    return nativeFilename(callback)
end
getCore=function() return {getGameMode=function() return 'Sandbox' end} end
getTimestampMs=function() return 100 end
CharacterTrait={DEXTROUS='DEXTROUS',ALL_THUMBS='ALL_THUMBS'}
p.hasTrait=function() return false end;p.isWearingAwkwardGloves=function() return false end
p.getVehicle=function() return nil end;p.tooDarkToRead=function() return false end;p.setIsFarming=function() end
p.getCharacterActions=function() return {contains=function() return false end} end
ISLogSystem={logAction=function() end}
local nativeInstanceof=instanceof
instanceof=function(value,kind)
    return nativeInstanceof(value,kind) or kind=='InventoryItem' and type(value)=='table' and value.class=='InventoryContainer'
end
local function container(owner)
    local value={class='ItemContainer',owner=owner,items={}}
    if owner then
        owner.inventory=value
        owner.getInventory=function(self)return self.inventory end
    end
    function value:getContainingItem() return self.owner end
    function value:getItems()
        local items=self.items
        return {size=function()return #items end,get=function(_,index)return items[index+1]end}
    end
    function value:getParent() return nil end
    function value:getType() return self==inv and 'inventory' or 'bag' end
    function value:contains(item) for _,v in ipairs(self.items) do if v==item then return true end end return false end
    function value:containsID(id) return self:getItemById(id)~=nil end
    function value:getItemById(id) for _,v in ipairs(self.items) do if v:getID()==id then return v end end end
    function value:AddItem(item) assert(not self:contains(item));self.items[#self.items+1]=item;item.container=self end
    function value:Remove(item) for i,v in ipairs(self.items) do if v==item then table.remove(self.items,i);item.container=nil;return end end end
    function value:hasRoomFor() return true end
    function value:isInCharacterInventory() return true end
    function value:isExistYet() return true end
    function value:isVehicleSeat() return false end
    function value:getCapacityWeight() return 0 end
    function value:getMaxWeight() return 50 end
    function value:getEffectiveCapacity() return 50 end
    function value:getAcceptItemFunction() return self.acceptFunction end
    function value:getOnlyAcceptCategory() return nil end
    return value
end
for key,value in pairs(container()) do inv[key]=value end
local function item(kind,where)
    local value=f.item(kind)
    value.getContainer=function(self) return self.container end
    value.getWorldItem=function(self) return self.world end
    value.getWeight=function() return 0.05 end;value.getActualWeight=value.getWeight;value.getUnequippedWeight=value.getWeight
    value.getType=function(self) return self:getFullType():match('%.(.+)$') end
    value.getIsCraftingConsumed=function(self) return self.consumed or false end
    value.isFavorite=function() return false end;value.isHumanCorpse=function() return false end
    value.setJobDelta=function() end
    value.getNumberOfPages=function() return 100 end;value.getAlreadyReadPages=function() return 99 end
    if where then where:AddItem(value) end
    return value
end
local function cart()
    local value=item('SaucedCarts.ShoppingCart',inv);value.class='InventoryContainer';value.cart=true
    value.inventory=container(value);value.getInventory=function(self) return self.inventory end
    return value,value.inventory
end
local cart1,inside1=cart();local cart2,inside2=cart()
local moves,flushes,refreshes,packets={},0,0,{}
SaucedCarts={isCart=function(value) return value and value.cart==true end,
    safeIsCart=function(value) return SaucedCarts.isCart(value) end,log=function() end,debug=function() end,
    performCartTransfer=function(character,value,src,dest)
        assert(character==p and src:contains(value),'SP transfer lost exact source ownership')
        src:Remove(value);dest:AddItem(value);moves[#moves+1]=value:getID();return true
    end,flushContainerResync=function() flushes=flushes+1 end,
    requestInventoryRefresh=function(character) assert(character==p);refreshes=refreshes+1 end,
    Network={sendToServer=function(character,command,args)
        assert(character==p and command=='cartTransfer');packets[#packets+1]=args
    end}}
fixtureOrigins[SaucedCarts.safeIsCart]=SaucedCartsSource..'/Core.lua';fixtureOrigins[SaucedCarts.isCart]=SaucedCartsSource..'/Core.lua'
fixtureOrigins[SaucedCarts.debug]=SaucedCartsSource..'/Core.lua'
for _,name in ipairs({'performCartTransfer','flushContainerResync','requestInventoryRefresh'}) do
    fixtureOrigins[SaucedCarts[name]]=SaucedCartsSource..'/CartTransferInterceptor.lua'
end
fixtureOrigins[SaucedCarts.Network.sendToServer]=SaucedCartsSource..'/Network.lua'
local cartPath=SaucedCartsSource..'/TimedActions/ISCartTransferAction.lua'
source(read(cartPath),cartPath)
local nativeMerge=ISCartTransferAction.canMergeAction
local interceptorPath=SaucedCartsSource..'/CartTransferInterceptor.lua'
local interceptor=read(interceptorPath)
local classify=assert(interceptor:match('(local function containerToCart%(container%).-\nend)'))..'\n'
    ..assert(interceptor:match('(local function classifyTransfer%(srcContainer, destContainer%).-\nend)'))
local hookStart=assert(interceptor:find('local function installInterception()',1,true))
local hookEnd=assert(interceptor:find('    -- MP clients only:',hookStart,true))
source('local interceptionInstalled=false\n'..classify..'\n'..interceptor:sub(hookStart,hookEnd-1)
    ..'end\ninstallInterception()',interceptorPath)
local initialConstructor,nativePerform=ISInventoryTransferAction.new,ISInventoryTransferAction.perform
local function transfer(value,src,dest,token)
    local action=ISInventoryTransferAction:new(p,value,src,dest,17)
    assert(getmetatable(action)==ISCartTransferAction and action.maxTime==17)
    action.toolkitQueueOperation=token or {};return action
end
local nail1,nail2,nail3=item('Base.Nails',inside1),item('Base.Nails',inside1),item('Base.Nails',inside1)
local batchToken={}
local pickup=transfer(nail1,inside1,inv,batchToken)
local same=transfer(nail2,inside1,inv,batchToken)
local separate=transfer(nail3,inside1,inv,{})
assert(nativeMerge(pickup,separate),'upstream baseline must reproduce cross-operation coalescing')
local baselineItems,baselineCount=ISCartTransferAction.collectBatch(pickup,{same,separate})
assert(#baselineItems==3 and baselineCount==2,'upstream baseline did not consume the following operation')
local starts={}
Events.OnGameStart.Add=function(callback) starts[#starts+1]=callback end
local restrictionPath=clientRoot..'/Restrictions/TransferRestrictions.lua'
local visualPath=clientRoot..'/CartState/VisualUpdateQueue.lua'
require=function(module)
    if module=='PZSurvivorToolkit/InventoryClasses' then return dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..module..'.lua')
    elseif module=='SaucedCarts/Restrictions/TransferRestrictions' then
        local hook=assert(read(restrictionPath):match('(local function initTransferActionHook%(%).-\nend)'))
        Events.OnGameStart.Add(source('local transferActionHookInitialized=false\n'..hook..'\nreturn initTransferActionHook',restrictionPath))
    elseif module=='SaucedCarts/CartState/VisualUpdateQueue' then
        local hook=assert(read(visualPath):match('(local function hookTransferAction%(%).-\nend)'))
        Events.OnGameStart.Add(source('local function getCartFromContainer(c) return c and c:getContainingItem() end\n'
            ..hook..'\nreturn hookTransferAction',visualPath))
    end
end
ISBaseTimedAction.begin=function(action)
    action.action={isStarted=function() return true end,finished=function() return false end,
        isForceComplete=function() return false end,forceStop=function(self) self.stopped=true end,
        forceComplete=function(self) self.completed=true end,getJobDelta=function() return 0 end}
end
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
local policy=f.project('ActionQueuePolicy');policy.installContracts()
local ops=PZSurvivorToolkit.ActionQueueOperations
starts={}
local carts=f.project('ActionQueueCarts');assert(carts.install() and #starts==2)
assert(carts.isTransferConstructor(initialConstructor),'initial reviewed interceptor was not approved')
starts[1]();local restrictionConstructor=ISInventoryTransferAction.new
assert(restrictionConstructor~=initialConstructor and carts.isTransferConstructor(initialConstructor)
    and carts.isTransferConstructor(restrictionConstructor),'actual restriction constructor delegation was not adopted')
starts[2]();assert(ISInventoryTransferAction.perform~=nativePerform and carts.isTransferConstructor(restrictionConstructor),
    'actual visual perform delegation was not adopted')
local latestConstructor=ISInventoryTransferAction.new
local latestPerform=ISInventoryTransferAction.perform
assert(getmetatable(ISInventoryTransferAction:new(p,nail1,inside1,inv,17))==ISCartTransferAction,
    'actual client hook failed to delegate cart construction')
local ordinaryOwner=item('Base.Bag',inv);ordinaryOwner.class='InventoryContainer'
local ordinaryBag=container(ordinaryOwner)
local ordinaryItem=item('Base.Nails',ordinaryBag)
local ordinary=ISInventoryTransferAction:new(p,ordinaryItem,ordinaryBag,inv,17)
assert(getmetatable(ordinary)==ISInventoryTransferAction and policy.inspect(ordinary),
    'actual client hooks lost native non-cart delegation/contract')
local changed={new=function() end,perform=latestPerform}
local expected={new=function() end,perform=latestPerform}
assert(not policy.adoptTransferHooks(expected,changed,function() return true end),
    'constructor adoption must reject an unexpected original reference')
assert(not ops.adoptReturnHooks(expected,changed,function() return true end),
    'return adoption must reject an unexpected original reference')
local inspected=assert(policy.inspect(pickup))
assert(inspected.items[nail1:getID()] and not inspected.items[cart1:getID()]
    and inspected.containerOwners[cart1:getID()] and inspected.preparationFinish,
    'cart owner must remain a container reference rather than a consumed transfer item')
assert(carts.involvesCart(pickup) and not carts.involvesCart(ordinary),'cart ancestry predicate misclassified direct cart/native bag transfers')
local function book()
    return f.action(ISReadABook,{item=item('Base.BookCarpentry1',inv)})
end
local head,waiting=book(),book()
local q=f.queue(head,pickup,waiting)
assert(not policy.moveReason(q,waiting,pickup) and not policy.moveReason(q,pickup,waiting,true),
    'independent waiting reading and cart transfer must reorder in both directions')
assert(not policy.cancelOperationReason(q,pickup),'independent waiting cart transfer must remain cancellable')
inside1.acceptFunction='foreign.acceptCartItem'
assert(policy.inspect(pickup).knownInputs==false and policy.moveReason(q,pickup,waiting)=='move_dependent'
    and policy.cancelOperationReason(q,pickup)=='operation_dependent',
    'unreviewed container acceptance callback retained cart controls beside reading')
inside1.acceptFunction=nil
local other=transfer(item('Base.Nails',inside2),inside2,inv)
q=f.queue(head,pickup,other)
assert(policy.moveReason(q,other,pickup)=='container_capacity' and policy.cancelOperationReason(q,other)=='container_capacity',
    'distinct carried carts must keep their unmodelled capacity effects ordered')
q=f.queue(head,pickup,same)
same.toolkitQueueOperation={}
assert(policy.moveReason(q,same,pickup)=='container_capacity' and policy.cancelOperationReason(q,same)=='container_capacity',
    'same-cart references must retain the capacity barrier without the actual override proof')
local conflicting=book();conflicting.item=nail1;q=f.queue(head,pickup,conflicting)
assert(policy.moveReason(q,conflicting,pickup)=='move_shared_item'
    and policy.cancelOperationReason(q,pickup)=='operation_shared_item','exact transferred item conflict was ignored')
local barrier=f.action(ISBaseTimedAction:derive('UnknownCartEffect'))
q=f.queue(head,pickup,barrier,waiting)
assert(policy.moveReason(q,waiting,pickup)=='move_dependent','unknown crossed effects must stay a barrier')
for _,field in ipairs({'onStartFunc','onCompleteFunc','onCancelFunc'}) do
    pickup[field]=function() end;assert(not policy.inspect(pickup),'foreign callback retained cart permission '..field);pickup[field]=nil
end
cart1.world={};assert(not policy.inspect(pickup),'ground cart container retained carried-transfer permission');cart1.world=nil
local oldContainer=cart1.container;cart1.container=nil
assert(not policy.inspect(pickup),'detached cart container retained carried-transfer permission');cart1.container=oldContainer
local oldSrc=pickup.srcContainer;pickup.srcContainer=container()
assert(not policy.inspect(pickup),'unowned source container retained cart permission');pickup.srcContainer=oldSrc
local oldDest=pickup.destContainer;pickup.destContainer=container()
assert(not policy.inspect(pickup),'world/unowned destination retained cart permission');pickup.destContainer=oldDest
local routedCart=pickup.cartItem;pickup.cartItem=cart2
assert(not policy.inspect(pickup),'a different carried cart ID retained exact route permission');pickup.cartItem=routedCart
local forgedCart,forgedInside=cart();inv:Remove(forgedCart);forgedCart.world={}
pickup.cartItem=forgedCart
assert(not policy.inspect(pickup),'world cart ID retained permission through unrelated carried endpoints');pickup.cartItem=routedCart
local between=transfer(item('Base.Nails',inside1),inside1,inside2)
assert(between.cartItem==cart2 and policy.inspect(between),'exact carried cart-to-cart route lost destination-first permission')
q=f.queue(head,between,waiting)
assert(not policy.moveReason(q,between,waiting,true) and not policy.moveReason(q,waiting,between)
    and not policy.cancelOperationReason(q,between),'waiting carried cart-to-cart cannot move/cancel beside independent reading')
between.direction='out'
assert(not policy.inspect(between),'wrong cart-to-cart direction retained permission');between.direction='in'
between.cartItem=cart1
assert(not policy.inspect(between),'source cart ID displaced native destination-cart routing')
ISInventoryTransferAction.new=function(...) return latestConstructor(...) end
assert(not policy.inspect(pickup) and not carts.isTransferConstructor(initialConstructor),
    'unknown current constructor retained transfer/constructor permission')
ISInventoryTransferAction.new=latestConstructor
local send=SaucedCarts.Network.sendToServer;SaucedCarts.Network.sendToServer=function() end
assert(not policy.inspect(pickup),'changed network sender retained cart permission');SaucedCarts.Network.sendToServer=send
local performMove=SaucedCarts.performCartTransfer;SaucedCarts.performCartTransfer=function() end
assert(not policy.inspect(pickup),'changed SP move helper retained cart permission');SaucedCarts.performCartTransfer=performMove
local isCart=SaucedCarts.isCart;SaucedCarts.isCart=function() return true end
assert(not policy.inspect(pickup),'replacing safeIsCart delegated validation retained cart permission');SaucedCarts.isCart=isCart
local classifySide=ISCartTransferAction.classifySide;ISCartTransferAction.classifySide=function() return 'inv' end
assert(not policy.inspect(pickup),'changed transfer-side serialization retained cart permission');ISCartTransferAction.classifySide=classifySide
local network=SaucedCarts.Network;SaucedCarts.Network={sendToServer=send}
assert(not policy.inspect(pickup),'replacement network owner retained cart permission');SaucedCarts.Network=network
local ancestry=carts.involvesCart;carts.involvesCart=function() return false end
assert(not policy.inspect(pickup) and not policy.inspect(ordinary) and not carts.isTransferConstructor(latestConstructor),
    'replacing the cart ancestry predicate retained transfer/constructor rights');carts.involvesCart=ancestry
assert(policy.inspect(pickup),'restored exact constructor/core/network helpers did not restore permission')
local nestedOwner=item('Base.Bag',inside1);nestedOwner.class='InventoryContainer'
local nestedInside=container(nestedOwner);local nestedItem=item('Base.Nails',nestedInside)
local nested=ISInventoryTransferAction:new(p,nestedItem,nestedInside,inv,17);nested.toolkitQueueOperation={}
assert(getmetatable(nested)==ISInventoryTransferAction and policy.inspect(nested) and carts.involvesCart(nested),
    'native bag-in-cart transfer lost its exact cart ancestor')
q=f.queue(head,nested,waiting)
assert(not policy.moveReason(q,nested,waiting,true),'native bag-in-cart transfer cannot move past independent reading')
ordinary.toolkitQueueOperation={};q=f.queue(head,nested,ordinary)
assert(policy.moveReason(q,nested,ordinary,true)=='container_capacity'
    and policy.moveReason(q,ordinary,nested)=='container_capacity'
    and policy.cancelOperationReason(q,nested)=='container_capacity',
    'native cart-ancestor capacity escaped conservative crossing/cancellation checks')
local cycleOwner=item('Base.Bag');cycleOwner.class='InventoryContainer'
local cycle=container(cycleOwner);cycleOwner.container=cycle
assert(not carts.involvesCart({srcContainer=cycle,destContainer=inv}),'cyclic containing-item ancestry did not terminate safely')
same.toolkitQueueOperation=batchToken
local values,count=ISCartTransferAction.collectBatch(pickup,{same,separate})
assert(#values==2 and count==1 and values[1]==nail1 and values[2]==nail2,
    'reviewed collectBatch crossed the operation token boundary')
q=f.queue(pickup,same,separate,waiting)
pickup:perform()
assert(#moves==2 and moves[1]==nail1:getID() and moves[2]==nail2:getID() and flushes==1 and refreshes==1
    and inv:contains(nail1) and inv:contains(nail2) and inside1:contains(nail3)
    and q.current==separate and q.queue[2]==waiting,'actual SP cart perform consumed the later operation or lost native effects/tail')
-- MP sends exact IDs and advances natively; pending actions with no receipt remain protected.
client=true
local mp=transfer(nail3,inside1,inv);q=f.queue(mp,waiting);mp:begin()
assert(policy.inspect(mp) and policy.cancelOperationReason(q,mp)=='operation_dependent',
    'MP cart transfer in flight must remain protected until an authoritative receipt exists')
mp:perform()
assert(#packets==1 and packets[1].itemId==nail3:getID() and #packets[1].itemIds==1
    and packets[1].cartId==cart1:getID() and inside1:contains(nail3) and not inv:contains(nail3)
    and q.current==waiting,'MP cart perform predicted server effects or lost native queue advancement')
client=false
-- An SP cancelled borrowed-item operation creates a real cart return before the unrelated book.
f.native('shared/TimedActions/ISInventoryTransferUtil.lua')
PZSurvivorToolkit.ActionQueueLabels={label=function() return 'fixture' end}
PZSurvivorToolkit.Settings.queueGroupCancel=function() return true end
local api=f.project('ActionQueue')
local borrowed=item('Base.BookFirstAid1',inside1)
local token={};local borrow=transfer(borrowed,inside1,inv,token)
q=f.queue(borrow);ops.adopt(borrow,token);borrow:perform()
assert(token.toolkitPickups[borrowed]==inside1 and inv:contains(borrowed),'actual cart pickup did not record its original source')
local using=f.action(ISReadABook,{item=borrowed});using.toolkitQueueOperation=token;using:begin()
local returnAction=transfer(borrowed,inv,inside1,token);returnAction:setAllowMissingItems(true)
local tail=book();q=f.queue(using,returnAction,tail)
ISInventoryPaneContextMenu.getContainers=function() return {contains=function(_,value) return value==inside1 or value==inv end} end
assert(carts.isReturn(returnAction) and not policy.cancelOperationReason(q,using),'verified SP cart return made borrowed operation uncancellable')
assert(api.cancelOperation(q,using) and token.toolkitCancelled)
ISBaseTimedAction.stop(using);q:tick()
local returned=q.current
assert(returned and returned.Type=='ISCartTransferAction' and returned.item==borrowed
    and returned.destContainer==inside1 and returned.allowMissingItems and carts.isReturn(returned)
    and returned.toolkitQueueOperation~=token and q.queue[2]==tail,'cancellation dropped the exact cart return or unrelated reading')
returned:perform()
assert(inside1:contains(borrowed) and not inv:contains(borrowed) and q.current==tail,
    'native SP cart return did not restore the exact borrowed item before unrelated reading')
-- Shared interception may wait for OnGameStart; adopt it before the actual client hooks in SP and MP.
local delayedHook=assert(interceptor:match('(local function installInterception%(%).-\nend)'))
local scenarios={{client=false},{client=true}}
if NativeWishlistWorkshopRoot then scenarios[#scenarios+1]={client=false,containers=true};scenarios[#scenarios+1]={client=true,containers=true} end
for _,scenario in ipairs(scenarios) do
    local mpMode=scenario.client;client=mpMode
    for name,value in pairs(vanillaMethods) do ISInventoryTransferAction[name]=value end
    ISInventoryTransferAction.new,ISInventoryTransferAction.perform,ISInventoryTransferAction.transferItem=
        vanillaConstructor,vanillaPerform,vanillaTransferItem
    source(read(cartPath),cartPath)
    f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
    local delayedPolicy=f.project('ActionQueuePolicy');delayedPolicy.installContracts()
    local delayedOps=PZSurvivorToolkit.ActionQueueOperations
    local compat,proximity,approvedPerform
    if scenario.containers then
        proximity={isLockedForPlayer=function() return false end,setTransferRunning=function() end,hasQueuedTransferAction=function() return false end}
        local captured={};for name,value in pairs(proximity) do captured[name]=value end
        local guard=function() for name,value in pairs(captured) do if proximity[name]~=value then return false end end return true end
        local savedRequire=require
        require=function(module) if module=='BetterContainers/Proximity' then return proximity end return savedRequire(module) end
        local path=NativeWishlistWorkshopRoot..'/3586216562/mods/BetterContainers/42.20/media/lua/client/BetterContainers/Proximity/Proximity_ISInventoryTransferAction.lua'
        local patch=source(read(path),path)
        local previous={};for name in pairs(vanillaMethods) do previous[name]=ISInventoryTransferAction[name] end
        patch.install();require=savedRequire
        local replacement={};for name in pairs(vanillaMethods) do replacement[name]=ISInventoryTransferAction[name] end
        assert(delayedPolicy.adoptTransferMethods(previous,replacement,guard) and delayedOps.adoptReturnMethods(previous,replacement,guard),
            'actual Better Containers transfer wrappers were not adopted before carts')
        approvedPerform=replacement.perform
        local compatPath=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'
        local query=assert(read(compatPath):match('(function Compat.isTransferPerform%(callback%).-\nend)'))
        compat=assert(loadstring('local reviewedTransferPerform,transferPerformGuard=...\nlocal Compat={}\n'
            ..query..'\nreturn Compat','@'..compatPath))(approvedPerform,guard)
        assert(compat.isTransferPerform(approvedPerform) and not compat.isTransferPerform(function() end),
            'Compat perform query approved a different callback')
        PZSurvivorToolkit.ActionQueueCompat=compat
    else PZSurvivorToolkit.ActionQueueCompat=nil end
    starts={}
    Events.OnGameStart.Add(source('local interceptionInstalled=false\n'..classify..'\n'..delayedHook
        ..'\nreturn installInterception',interceptorPath))
    local delayed=f.project('ActionQueueCarts')
    assert(delayed.install() and #starts==4 and ISInventoryTransferAction.new==vanillaConstructor
        and delayed.isTransferConstructor(vanillaConstructor), 'reviewed native initial constructor did not install a delayed observer')
    starts[1]();local sharedConstructor=ISInventoryTransferAction.new
    assert(sharedConstructor~=vanillaConstructor and not delayed.isTransferConstructor(sharedConstructor),
        'shared interceptor acquired permission before its observer validated the replacement')
    starts[2]()
    assert(delayed.isTransferConstructor(vanillaConstructor) and delayed.isTransferConstructor(sharedConstructor),
        'OnGameStart observer did not adopt the actual shared constructor')
    assert((ISInventoryTransferAction.transferItem~=vanillaTransferItem)==mpMode,
        'actual shared MP transferItem nudge wrapper was not exercised')
    starts[3]();starts[4]()
    local adoptedNew,adoptedPerform,adoptedHelper=ISInventoryTransferAction.new,
        ISInventoryTransferAction.perform,ISInventoryTransferAction.transferItem
    assert(delayed.isTransferConstructor(vanillaConstructor) and delayed.isTransferConstructor(sharedConstructor)
        and delayed.isTransferConstructor(adoptedNew), 'later client hooks lost the delayed constructor lineage')
    local ordinaryAfter=ISInventoryTransferAction:new(p,ordinaryItem,ordinaryBag,inv,17)
    assert(delayedPolicy.inspect(ordinaryAfter), 'shared/client adoption lost the native ordinary transfer contract')
    local cartAfter=ISInventoryTransferAction:new(p,nail3,inside1,inv,17)
    assert(delayedPolicy.inspect(cartAfter),'shared/client adoption lost the actual cart transfer contract')
    if compat then
        assert(adoptedPerform~=approvedPerform and delayed.isTransferConstructor(adoptedNew),
            'later SC visual hook revoked the historical approved Better Containers perform')
        local predicate=proximity.isLockedForPlayer
        proximity.isLockedForPlayer=function() return false end
        assert(not delayed.isTransferConstructor(adoptedNew) and not delayedPolicy.inspect(ordinaryAfter) and not delayedPolicy.inspect(cartAfter),
            'changed Better Containers dependency retained cart/native rights')
        proximity.isLockedForPlayer=predicate
        local query=compat.isTransferPerform
        compat.isTransferPerform=function() return true end
        assert(not delayed.isTransferConstructor(adoptedNew) and not delayedPolicy.inspect(ordinaryAfter) and not delayedPolicy.inspect(cartAfter),
            'replaced Compat perform query retained cart/native rights')
        compat.isTransferPerform=query
        PZSurvivorToolkit.ActionQueueCompat={isTransferPerform=query}
        assert(not delayed.isTransferConstructor(adoptedNew) and not delayedPolicy.inspect(ordinaryAfter) and not delayedPolicy.inspect(cartAfter),
            'replaced Compat owner retained cart/native rights')
        PZSurvivorToolkit.ActionQueueCompat=compat
        assert(delayed.isTransferConstructor(adoptedNew) and delayedPolicy.inspect(ordinaryAfter),
            'restoring exact Compat approval dependencies did not restore rights')
    end
    -- A helper mismatch must reject the entire adoption before updating either constructor or perform snapshot.
    local replacementNew=function(...) return adoptedNew(...) end
    local replacementPerform=function(...) return adoptedPerform(...) end
    local replacementHelper=function(...) return adoptedHelper(...) end
    ISInventoryTransferAction.new,ISInventoryTransferAction.perform,ISInventoryTransferAction.transferItem=
        replacementNew,replacementPerform,replacementHelper
    assert(not delayedPolicy.adoptTransferHooks({new=adoptedNew,perform=adoptedPerform,transferItem=function() end},
        {new=replacementNew,perform=replacementPerform,transferItem=replacementHelper},function() return true end),
        'wrong original transferItem helper was accepted')
    assert(not delayedPolicy.adoptTransferHooks({new=adoptedNew,perform=adoptedPerform,transferItem=adoptedHelper},
        {new=replacementNew,perform=replacementPerform,transferItem=adoptedHelper},function() return true end),
        'wrong replacement transferItem reference was accepted')
    ISInventoryTransferAction.new,ISInventoryTransferAction.perform,ISInventoryTransferAction.transferItem=
        adoptedNew,adoptedPerform,adoptedHelper
    assert(delayedPolicy.inspect(ordinaryAfter) and delayed.isTransferConstructor(adoptedNew),
        'rejected helper adoption partially mutated already approved constructor/perform/helper snapshots')
    ISInventoryTransferAction.transferItem=replacementHelper
    assert(not delayedPolicy.inspect(ordinaryAfter) and not delayed.isTransferConstructor(adoptedNew),
        'late helper replacement retained ordinary transfer/constructor permission')
    ISInventoryTransferAction.transferItem=adoptedHelper
    assert(delayedPolicy.inspect(ordinaryAfter),'restoring the exact shared helper did not restore permission')
    -- Return adoption still requires its exact current predecessor after delayed shared and client hooks.
    assert(not delayedOps.adoptReturnHooks({new=vanillaConstructor,perform=adoptedPerform},
        {new=adoptedNew,perform=adoptedPerform},function() return true end),'stale native predecessor acquired delayed return rights')
    if compat then
        source(read(cartPath),cartPath)
        ISInventoryTransferAction.new,ISInventoryTransferAction.perform,ISInventoryTransferAction.transferItem=
            vanillaConstructor,function() end,vanillaTransferItem
        local mergeBefore=ISCartTransferAction.canMergeAction
        local rejected=f.project('ActionQueueCarts')
        assert(not rejected.install() and ISCartTransferAction.canMergeAction==mergeBefore,
            'Compat approval of the exact BC callback accepted a different initial perform')
    end
end
client=false
PZSurvivorToolkit.ActionQueueCompat=nil
for name,value in pairs(vanillaMethods) do ISInventoryTransferAction[name]=value end
-- Disk source pins cannot approve already replaced runtime methods before adapter capture.
local coreMove,corePredicate,networkSend=SaucedCarts.performCartTransfer,SaucedCarts.isCart,SaucedCarts.Network.sendToServer
for _,changed in ipairs({'class','core','predicate','network','perform','helper'}) do
    source(read(cartPath),cartPath)
    ISInventoryTransferAction.new,ISInventoryTransferAction.perform,ISInventoryTransferAction.transferItem=
        vanillaConstructor,vanillaPerform,vanillaTransferItem
    f.project('ActionQueueOperations');f.project('ActionQueueDefinitions');f.project('ActionQueuePolicy')
    local mergeBefore=ISCartTransferAction.canMergeAction
    if changed=='class' then ISCartTransferAction.perform=function() end
    elseif changed=='core' then SaucedCarts.performCartTransfer=function() end
    elseif changed=='predicate' then SaucedCarts.isCart=function() return true end
    elseif changed=='network' then SaucedCarts.Network.sendToServer=function() end
    elseif changed=='perform' then ISInventoryTransferAction.perform=function() end
    elseif changed=='helper' then ISInventoryTransferAction.transferItem=function() end end
    local rejected=f.project('ActionQueueCarts')
    assert(not rejected.install() and ISCartTransferAction.canMergeAction==mergeBefore
        and not rejected.isTransferConstructor(vanillaConstructor),'preinstalled foreign callback was approved or mutated the class: '..changed)
    SaucedCarts.performCartTransfer,SaucedCarts.isCart,SaucedCarts.Network.sendToServer=coreMove,corePredicate,networkSend
end
-- The delayed shared observer may adopt only the reviewed constructor and optional MP nudge helper.
for _,changed in ipairs({'perform','missingHelper','foreignHelper'}) do
    source(read(cartPath),cartPath)
    ISInventoryTransferAction.new,ISInventoryTransferAction.perform,ISInventoryTransferAction.transferItem=
        vanillaConstructor,vanillaPerform,vanillaTransferItem
    f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
    local rejectedPolicy=f.project('ActionQueuePolicy');rejectedPolicy.installContracts()
    starts={}
    Events.OnGameStart.Add(source('local interceptionInstalled=false\n'..classify..'\n'..delayedHook
        ..'\nreturn installInterception',interceptorPath))
    local rejected=f.project('ActionQueueCarts');assert(rejected.install() and #starts==4)
    starts[1]()
    if changed=='perform' then ISInventoryTransferAction.perform=function() end
    elseif changed=='missingHelper' then ISInventoryTransferAction.transferItem=nil
    elseif changed=='foreignHelper' then ISInventoryTransferAction.transferItem=function() end end
    starts[2]()
    local ordinaryRejected=ISInventoryTransferAction:new(p,ordinaryItem,ordinaryBag,inv,17)
    assert(not rejected.isTransferConstructor(ISInventoryTransferAction.new) and not rejectedPolicy.inspect(ordinaryRejected),
        'delayed shared observer approved an unexpected runtime replacement: '..changed)
end
-- An unverified constructor cannot install the adapter or modify upstream merge behavior.
local delayedLatest=ISInventoryTransferAction.new
ISInventoryTransferAction.new=function(...) return delayedLatest(...) end
local mergeBefore=ISCartTransferAction.canMergeAction
local unverified=f.project('ActionQueueCarts')
assert(not unverified.install() and ISCartTransferAction.canMergeAction==mergeBefore
    and not unverified.isTransferConstructor(ISInventoryTransferAction.new),
    'unverified constructor installed permissions or altered upstream batching')
-- ContainerRestrictions changes unequip new/complete globally, but only the marked non-cart food mask is audited.
local restrictionsPath=SaucedCartsSource..'/ContainerRestrictions.lua'
local restrictionsSource=read(restrictionsPath)
local coreSource=read(SaucedCartsSource..'/Core.lua')
local compatPath=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'
local compatSource=read(compatPath)
local pinCode='local Proof=assert(loadfile(ProjectRoot..\'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua\'))();local sourceFiles={}\n'
    ..assert(compatSource:match('(local function verified%(id, files%).-\nend)'))..'\nlocal Compat={}\n'
    ..assert(compatSource:match('(function Compat.isCartMaskSource%(%).-\nend)'))..'\nreturn Compat'
local maskHookCode='local unequipHookInitialized=false\n'
    ..assert(restrictionsSource:match('(local function flushDistanceOnCreate%(character, item, label%).-\nend)'))..'\n'
    ..assert(restrictionsSource:match('(local function wrapUnequipNew%(%).-\nend)'))..'\n'
    ..assert(restrictionsSource:match('(local function initUnequipHook%(%).-\nend)'))..'\nreturn initUnequipHook'
for _,mode in ipairs({'valid','changed-source','foreign-helper','foreign-delegate','foreign-lifecycle','preinstalled'}) do
    -- Rebuild the fixture so the helper must observe native predecessors before the real OnGameStart hook.
    local maskFixture=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    local character=maskFixture.player
    ItemBodyLocation={};ISWearClothing={isStopOnWalk=function() return false end}
    maskFixture.native('shared/TimedActions/ISUnequipAction.lua')
    local removed=0
    character.removeWornItem=function() removed=removed+1 end
    character.getPrimaryHandItem,character.getSecondaryHandItem=function() end,function() end
    getPlayerHotbar,sendEquip,triggerEvent=function() end,function() end,function() end
    isForceDropHeavyItem=function() return false end
    local originalNew,originalComplete=ISUnequipAction.new,ISUnequipAction.complete
    fixtureOrigins[originalNew]=NativeActionRoot..'/shared/TimedActions/ISUnequipAction.lua'
    fixtureOrigins[originalComplete]=NativeActionRoot..'/shared/TimedActions/ISUnequipAction.lua'
    for name,callback in pairs(ISUnequipAction) do
        if type(callback)=='function' and name~='derive' then fixtureOrigins[callback]=NativeActionRoot..'/shared/TimedActions/ISUnequipAction.lua' end
    end
    for _,name in ipairs({'new','perform','transferItem'}) do
        fixtureOrigins[ISInventoryTransferAction[name]]=NativeActionRoot..'/client/TimedActions/ISInventoryTransferAction.lua'
    end
    -- The existing fake core is kept exact and guarded; execute the actual restricted unequip wrappers below.
    SaucedCarts.CartTypes={}
    local pendingStarts={};Events.OnGameStart.Add=function(callback) pendingStarts[#pendingStarts+1]=callback end
    local originalRequire=require
    require=function(module)
        if module=='SaucedCarts/Restrictions/TransferRestrictions' then
            local hook=assert(read(restrictionPath):match('(local function initTransferActionHook%(%).-\nend)'))
            Events.OnGameStart.Add(source('local transferActionHookInitialized=false\n'..hook..'\nreturn initTransferActionHook',restrictionPath))
        elseif module=='SaucedCarts/CartState/VisualUpdateQueue' then
            local hook=assert(read(visualPath):match('(local function hookTransferAction%(%).-\nend)'))
            Events.OnGameStart.Add(source('local function getCartFromContainer(c) return c and c:getContainingItem() end\n'..hook..'\nreturn hookTransferAction',visualPath))
        else return originalRequire(module) end
    end
    getModFileReader=function(id,path)
        assert(id=='SaucedCarts')
        local text=path=='media/lua/shared/SaucedCarts/Core.lua' and coreSource or restrictionsSource
        if mode=='changed-source' then text=text..'\n-- changed wrapper source\n' end
        local lines={};for line in text:gmatch('([^\n]*)\n') do lines[#lines+1]=line end
        local index=0;return {readLine=function() index=index+1;return lines[index] end,close=function() end}
    end
    local maskCompat=source(pinCode,compatPath)
    assert(maskCompat.isCartMaskSource()==(mode~='changed-source'),'mask wrapper source pin did not reject changed input')
    local debugBefore=SaucedCarts.debug
    if mode=='foreign-helper' then SaucedCarts.debug=function() end end
    PZSurvivorToolkit.ActionQueueCompat=maskCompat
    local owned
    PZSurvivorToolkit.BulkFood={isMaskRemoval=function(action) return action==owned end,
        isCommand=function() return false end,isEat=function() return false end}
    local maskFood=PZSurvivorToolkit.BulkFood
    source(read(cartPath),cartPath)
    source('local interceptionInstalled=false\n'..classify..'\n'..interceptor:sub(hookStart,hookEnd-1)..'end\ninstallInterception()',interceptorPath)
    maskFixture.project('ActionQueueOperations');maskFixture.project('ActionQueueDefinitions')
    local maskPolicy=maskFixture.project('ActionQueuePolicy')
    Events.OnGameStart.Add(source(maskHookCode,restrictionsPath))
    if mode=='foreign-lifecycle' then ISUnequipAction.start=function() error('foreign start') end end
    if mode=='foreign-delegate' then ISUnequipAction.complete=function() error('foreign predecessor') end end
    if mode=='preinstalled' then source(maskHookCode,restrictionsPath)() end
    local maskCarts=maskFixture.project('ActionQueueCarts');assert(maskCarts.install())
    for _,callback in ipairs(pendingStarts) do callback() end
    local mask=maskFixture.item('Base.Hat_GasMask_nofilter')
    mask.getCategory=function() return 'Clothing' end;mask.getWorldItem=function() end
    owned=ISUnequipAction:new(character,mask,50,'food')
    local foreign=ISUnequipAction:new(character,mask,50,'food')
    assert(owned.maxTimeInit==50 and owned.reason=='food','actual wrapper changed native constructor arguments')
    assert(not maskPolicy.inspect(foreign),'unmarked identical mask removal borrowed food ownership')
    local contract,adapter=maskPolicy.inspect(owned)
    if mode~='valid' then assert(not contract,'changed source or preinstalled helper acquired mask permission: '..mode)
    else
        assert(adapter=='compat.food-mask-unequip' and contract.preparationFinish and maskPolicy.preparationCanFinish(owned),
            'owned native mask removal did not regain preparation cancellation')
        character.getPrimaryHandItem=function(self) return self.primary end
        character.getSecondaryHandItem=function(self) return self.secondary end
        assert(maskCarts.isUnequipConstructor(originalNew) and maskCarts.isUnequipConstructor(ISUnequipAction.new)
            and maskCarts.isNonCartUnequip(owned) and maskCarts.isNonCartItem(mask) and maskCarts.equipmentSafe(character),
            'observed native delegate did not expose the exact non-cart equipment proof')
        for _,hand in ipairs({'primary','secondary'}) do
            character[hand]=cart(character:getInventory())
            assert(not maskCarts.equipmentSafe(character),'held cart acquired equipment proof: '..hand)
            character[hand]=nil
        end
        owned:complete();assert(removed==1,'actual non-cart wrapper did not delegate native completion exactly once')
        for _,name in ipairs({'new','complete','start','stop'}) do
            local method=ISUnequipAction[name];ISUnequipAction[name]=function() end
            assert(not maskPolicy.inspect(owned) and not maskCarts.isUnequipConstructor(ISUnequipAction.new),'changed unequip lifecycle retained equipment permission: '..name)
            ISUnequipAction[name]=method
        end
        for _,name in ipairs({'safeIsCart','isCart','debug'}) do
            local method=SaucedCarts[name];SaucedCarts[name]=function() return false end
            assert(not maskPolicy.inspect(owned) and not maskCarts.isNonCartItem(mask),'changed classification helper retained equipment permission: '..name)
            SaucedCarts[name]=method
        end
        local cartTypes=SaucedCarts.CartTypes;SaucedCarts.CartTypes={}
        assert(not maskPolicy.inspect(owned),'replacement cart registry retained mask permission');SaucedCarts.CartTypes=cartTypes
        setmetatable(cartTypes,{__index=function() end})
        assert(not maskPolicy.inspect(owned),'changed cart registry lookup retained mask permission');setmetatable(cartTypes,nil)
        cartTypes[mask:getFullType()]={}
        assert(not maskPolicy.inspect(owned),'registered cart type retained non-cart mask permission');cartTypes[mask:getFullType()]=nil
        local marking=maskFood.isMaskRemoval;maskFood.isMaskRemoval=function() return true end
        assert(not maskPolicy.inspect(owned),'replacement ownership predicate retained mask permission');maskFood.isMaskRemoval=marking
        owned.item.cart=true
        assert(not maskPolicy.inspect(owned),'cart classification retained ordinary mask permission');owned.item.cart=nil
        assert(maskPolicy.inspect(owned),'restored exact helpers did not restore mask permission')
    end
    SaucedCarts.debug=debugBefore
end
-- Capacity permissions require the actual early Java -> CapacityOverride transition, not filenames alone.
do
 local capacityPath=SaucedCartsSource..'/CapacityOverride.lua'
 local capacitySource=read(capacityPath)
 local dataPath=SaucedCartsSource..'/CartData.lua'
 local dataSource=read(dataPath)
 local preloader=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/000ToolkitCartCapacity.lua'
 local capacityPins='local Proof=assert(loadfile(ProjectRoot..\'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua\'))();local sourceFiles={}\n'
  ..assert(compatSource:match('(local function verified%(id, files%).-\nend)'))..'\nlocal Compat={}\n'
  ..assert(compatSource:match('(function Compat.isCartCapacitySource%(%).-\nend)'))..'\nreturn Compat'
 local function scenario(mode)
  local previousPlayer,previousInventory=p,inv
  local fixture=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
  p,inv=fixture.player,fixture.player.inventory
  p.class='IsoPlayer';p.hasTrait=function() return false end;p.getVehicle=function() end
  p.isWearingAwkwardGloves=function() return false end;p.tooDarkToRead=function() return false end
  p.isLocalPlayer=function() return true end;p.isDraggingCorpse=function() return false end
  p.getCharacterActions=function() return {contains=function() return false end} end
  client,server=false,false
  isClient=function() return client end;isServer=function() return server end
  instanceof=function(value,kind) return nativeInstanceof(value,kind)
   or kind=='InventoryItem' and type(value)=='table' and value.class=='InventoryContainer' end
  getFilenameOfClosure=function(callback)
   return fixtureOrigins[callback] or nativeFilename(callback)
  end
  local nativeMethods={
   getCapacity=function(c) return c.capacity or 50 end,
   getEffectiveCapacity=function(c) return c.capacity or 50 end,
   hasRoomFor=function(c,character,value) local weight=type(value)=='number' and value or value:getUnequippedWeight();return c:getCapacityWeight()+weight<=c:getEffectiveCapacity(character) end,
   getCapacityWeight=function(c) if c.load~=nil then return c.load end;local weight=0;for _,value in ipairs(c.items) do weight=weight+value:getUnequippedWeight() end;return weight end,
   getContainingItem=function(c) return c.owner end,getParent=function(c) return c.parent end,
   getType=function(c) return c==inv and 'inventory' or 'bag' end,
   getAcceptItemFunction=function(c) return c.acceptFunction end,
   getVehiclePart=function() end,isItemAllowed=function() return true end,
  }
  local java={};for _,callback in pairs(nativeMethods) do java[callback]=true end
  getClassSimpleName=function(callback) assert(callback~=nil,'Java class query received nil');return java[callback] and 'LuaJavaInvoker' or 'LuaClosure' end
  ItemContainer,InventoryContainer={class={}},{class={}}
  __classmetatables={[ItemContainer.class]={__index=nativeMethods},[InventoryContainer.class]={__index={getCapacity=function() return 50 end,getEffectiveCapacity=function() return 50 end}}}
  local function makeContainer(owner)
   local value=container(owner)
   for name in pairs(nativeMethods) do value[name]=nil end
   return setmetatable(value,{__index=function(_,name) return __classmetatables[ItemContainer.class].__index[name] end})
  end
  local rootMethods=container();for name,callback in pairs(rootMethods) do inv[name]=callback end
  for name in pairs(nativeMethods) do inv[name]=nil end
  setmetatable(inv,{__index=function(_,name) return __classmetatables[ItemContainer.class].__index[name] end})
  local function makeCart()
   local value=item('SaucedCarts.ShoppingCart',inv);value.class='InventoryContainer';value.cart=true
   value.inventory=makeContainer(value)
   value.getItemContainer=function(self) return self.inventory end;value.getInventory=value.getItemContainer
   value.getMaxItemSize=function() return 0 end
   return value,value.inventory
  end
  SaucedCarts={isCart=function(value) return value and value.cart==true end,
   safeIsCart=function(value) return SaucedCarts.isCart(value) end,debug=function() end,log=function() end,error=error,
   performCartTransfer=function() end,flushContainerResync=function() end,requestInventoryRefresh=function() end,
   Network={sendToServer=function() end}}
  for name,path in pairs({isCart='Core.lua',safeIsCart='Core.lua',debug='Core.lua',performCartTransfer='CartTransferInterceptor.lua',
   flushContainerResync='CartTransferInterceptor.lua',requestInventoryRefresh='CartTransferInterceptor.lua'}) do fixtureOrigins[SaucedCarts[name]]=SaucedCartsSource..'/'..path end
  fixtureOrigins[SaucedCarts.Network.sendToServer]=SaucedCartsSource..'/Network.lua'
  local callbacks={};Events.OnGameStart.Add=function(callback) callbacks[#callbacks+1]=callback end
  Events.OnServerStarted={Add=function() end}
  SandboxVars={SaucedCarts={CapacityMultiplier=100}}
  require=function() end
  source(dataSource,dataPath)
  local loaded=false
  require=function(module)
   if module=='SaucedCarts/CapacityOverride' and not loaded then
    loaded=true;source(capacitySource,capacityPath)
    if mode=='missing-wrapper' then nativeMethods.hasRoomFor=nil end
   end
  end
  if mode=='foreign-predecessor' then nativeMethods.getEffectiveCapacity=function() return 99999 end end
  if mode=='already-wrapped' then require('SaucedCarts/CapacityOverride') end
  if mode=='missing-metatable' then __classmetatables[ItemContainer.class]=nil end
  assert(loadfile(preloader))()
  if mode=='missing-metatable' then __classmetatables[ItemContainer.class]={__index=nativeMethods} end
  require('SaucedCarts/CapacityOverride')
  assert(SaucedCarts.CapacityOverride.isInitialized(),'actual upstream capacity hook failed')
  assert((type(PZSurvivorToolkit.cartCapacityMatches)=='function')==(mode=='valid' or mode=='changed-source'),'early proof accepted an unknown predecessor/late wrapper '..mode)
  getModFileReader=function(id,path)
   assert(id=='SaucedCarts');local text=path:match('CapacityOverride.lua$') and capacitySource or path:match('CartData.lua$') and dataSource or coreSource
   if mode=='changed-source' and path:match('CapacityOverride.lua$') then text=text..'\n-- changed capacity source\n' end
   local lines={};for line in text:gmatch('([^\n]*)\n') do lines[#lines+1]=line end
   local index=0;return {readLine=function() index=index+1;return lines[index] end,close=function() end}
  end
  local capacityCompat=source(capacityPins,compatPath);PZSurvivorToolkit.ActionQueueCompat=capacityCompat
  assert(capacityCompat.isCartCapacitySource()==(mode~='changed-source'),'capacity source pin failed '..mode)
  source(read(cartPath),cartPath)
  local base=ISInventoryTransferAction
  for name,callback in pairs(base) do if type(callback)=='function' and name~='derive' then fixtureOrigins[callback]=NativeActionRoot..'/client/TimedActions/ISInventoryTransferAction.lua' end end
  source('local interceptionInstalled=false\n'..classify..'\n'..interceptor:sub(hookStart,hookEnd-1)..'end\ninstallInterception()',interceptorPath)
  require=function(module)
   if module=='PZSurvivorToolkit/InventoryClasses' then return dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..module..'.lua')
   elseif module=='SaucedCarts/Restrictions/TransferRestrictions' then
    local hook=assert(read(restrictionPath):match('(local function initTransferActionHook%(%).-\nend)'))
    Events.OnGameStart.Add(source('local transferActionHookInitialized=false\n'..hook..'\nreturn initTransferActionHook',restrictionPath))
   elseif module=='SaucedCarts/CartState/VisualUpdateQueue' then
    local hook=assert(read(visualPath):match('(local function hookTransferAction%(%).-\nend)'))
    Events.OnGameStart.Add(source('local function getCartFromContainer(c) return c and c:getContainingItem() end\n'..hook..'\nreturn hookTransferAction',visualPath))
   end
  end
  fixture.project('ActionQueueOperations');fixture.project('ActionQueueDefinitions')
  local checkedPolicy=fixture.project('ActionQueuePolicy');checkedPolicy.installContracts()
  local checkedCarts=fixture.project('ActionQueueCarts');assert(checkedCarts.install())
  for _,callback in ipairs(callbacks) do callback() end
  local owner1,sourceContainer=makeCart();local owner2,destination=makeCart()
  local cargoA,cargoB,cargoC=item('Base.Nails',sourceContainer),item('Base.Nails',sourceContainer),item('Base.Nails',sourceContainer)
  local function action(value,from,to)
   local result=ISInventoryTransferAction:new(p,value,from,to,17);result.toolkitQueueOperation={};return result
  end
  local function reading() return fixture.action(ISReadABook,{item=item('Base.BookCarpentry1',inv)}) end
  local a,b=action(cargoA,sourceContainer,inv),action(cargoB,sourceContainer,inv)
  local head,tail=reading(),reading()
  local function positive(x,y)
   local queue=fixture.queue(head,x,y,tail)
   assert(not checkedPolicy.moveReason(queue,y,x) and not checkedPolicy.moveReason(queue,x,y,true),'verified cart transfers cannot reorder both ways '..mode)
   assert(not checkedPolicy.cancelOperationReason(queue,x) and not checkedPolicy.cancelOperationReason(queue,y),'verified independent cart cancellation rejected '..mode)
  end
  local function blocked(x,y,label)
   local queue=fixture.queue(head,x,y,tail)
   assert(checkedPolicy.moveReason(queue,y,x)=='container_capacity' and checkedPolicy.moveReason(queue,x,y,true)=='container_capacity',label..' allowed crossing')
   assert(checkedPolicy.cancelOperationReason(queue,x)=='container_capacity',label..' credited removed/cancelled work')
  end
  if mode~='valid' then
   assert(not checkedCarts.capacitySafe(inv) and not checkedCarts.capacitySafe(destination),'unproved capacity acquired safe status '..mode)
   blocked(a,b,mode)
  else
   assert(checkedCarts.capacitySafe(inv) and checkedCarts.capacitySafe(destination),'actual early capacity transition did not enable proof')
   assert(destination:getEffectiveCapacity(p)==50 and destination:hasRoomFor(p,cargoA),'actual cart capacity wrapper did not run')
   for _,mp in ipairs({false,true}) do
    client=mp
    positive(a,b)
    local other=action(cargoC,sourceContainer,destination);positive(a,other)
    local between=checkedPolicy.inspect(other)
    assert(between and other.direction=='in' and other.cartItem==owner2
     and between.containerOwners[owner1:getID()] and between.containerOwners[owner2:getID()]
     and not between.items[owner1:getID()] and not between.items[owner2:getID()],'cart-to-cart lost exact endpoint references')
    local duplicate=action(cargoA,sourceContainer,destination);local queue=fixture.queue(head,a,duplicate,tail)
    assert(checkedPolicy.moveReason(queue,duplicate,a)=='move_shared_item' and checkedPolicy.cancelOperationReason(queue,a)=='operation_shared_item','shared cargo lost dependency')
    local moveOwner=action(owner1,inv,inv);queue=fixture.queue(head,a,moveOwner,tail)
    assert(checkedPolicy.moveReason(queue,moveOwner,a) and checkedPolicy.cancelOperationReason(queue,a),'moving source cart owner lost dependency')
    moveOwner=action(owner2,inv,inv);queue=fixture.queue(head,other,moveOwner,tail)
    assert(checkedPolicy.moveReason(queue,moveOwner,other),'moving destination cart owner lost dependency')
    inv.capacity=0;blocked(a,b,'root capacity');inv.capacity=nil
    local data=SaucedCarts.CartTypes[owner2:getFullType()];local capacity=data.capacity;data.capacity=0
    blocked(a,other,'cart destination capacity');data.capacity=capacity
    local outerOwner=item('Base.Bag',destination);outerOwner.class='InventoryContainer';local outer=makeContainer(outerOwner)
    local innerOwner=item('Base.Bag',outer);innerOwner.class='InventoryContainer';local inner=makeContainer(innerOwner)
    local nested=action(cargoC,sourceContainer,inner)
    outer.capacity=0;blocked(a,nested,'ordinary ancestor capacity');outer.capacity=nil
    data.capacity=0;blocked(a,nested,'cart ancestor capacity');data.capacity=capacity
    local batch=action(cargoA,sourceContainer,destination);local follow=action(cargoC,sourceContainer,destination)
    local oldWeights={cargoA.getUnequippedWeight,cargoB.getUnequippedWeight,cargoC.getUnequippedWeight}
    for _,value in ipairs({cargoA,cargoB,cargoC}) do value.getUnequippedWeight=function() return 1 end end
    data.capacity=3;positive(batch,follow);batch.queueList={{items={cargoA,cargoB}}};blocked(batch,follow,'full batch capacity')
    batch.queueList=nil;data.capacity=capacity
    for index,value in ipairs({cargoA,cargoB,cargoC}) do value.getUnequippedWeight=oldWeights[index] end
    local incoming=item('Base.Thread',inv);local out=action(cargoA,sourceContainer,inv);local into=action(incoming,inv,sourceContainer)
    sourceContainer.load=50;blocked(out,into,'cart outgoing-space credit');sourceContainer.load=nil
    a.action={finished=function() return false end,isForceComplete=function() return false end,isStarted=function() return true end}
    queue=fixture.queue(a,tail)
    if mp then assert(not checkedPolicy.inspect(a).preparationFinish and checkedPolicy.cancelOperationReason(queue,a)=='operation_dependent','active MP cancellation opened without receipt') end
    a.action=nil
   end
   client=false
   local intoA,intoB=action(cargoA,sourceContainer,destination),action(cargoB,sourceContainer,destination)
   local function rejects(change,restore,label)
    change();assert(not checkedCarts.capacitySafe(destination),label..' retained capacity proof')
    local queue=fixture.queue(head,intoA,intoB,tail)
    assert(checkedPolicy.moveReason(queue,intoB,intoA) and checkedPolicy.moveReason(queue,intoA,intoB,true)
     and checkedPolicy.cancelOperationReason(queue,intoA),label..' retained reorder/cancel permission');restore()
    assert(checkedCarts.capacitySafe(destination),'restored '..label..' did not recover capacity proof')
   end
   for _,name in ipairs({'getCapacity','getEffectiveCapacity','hasRoomFor','getCapacityWeight','getContainingItem','getParent','getType','getAcceptItemFunction'}) do
    local previous=nativeMethods[name]
    rejects(function() nativeMethods[name]=function() return 0 end end,function() nativeMethods[name]=previous end,'changed native '..name)
   end
   local registry=SaucedCarts.CartTypes
   rejects(function() SaucedCarts.CartTypes={} end,function() SaucedCarts.CartTypes=registry end,'registry owner')
   rejects(function() setmetatable(registry,{__index=function() return {} end}) end,function() setmetatable(registry,nil) end,'registry metatable')
   local data=registry[owner2:getFullType()]
   rejects(function() setmetatable(data,{__index=function() return 50 end}) end,function() setmetatable(data,nil) end,'cart data metatable')
   for _,value in ipairs({-1,math.huge,'50',0/0}) do
    local capacity=data.capacity
    rejects(function() data.capacity=value end,function() data.capacity=capacity end,'invalid cart capacity')
   end
   for _,value in ipairs({-1,math.huge,'100',0/0}) do
    rejects(function() SandboxVars.SaucedCarts.CapacityMultiplier=value end,function() SandboxVars.SaucedCarts.CapacityMultiplier=100 end,'invalid capacity multiplier')
   end
   rejects(function() setmetatable(SandboxVars,{__index=function() return {} end}) end,function() setmetatable(SandboxVars,nil) end,'sandbox root metatable')
   local options=SandboxVars.SaucedCarts
   rejects(function() setmetatable(options,{__index=function() return 100 end}) end,function() setmetatable(options,nil) end,'sandbox options metatable')
   rejects(function() SandboxVars.SaucedCarts='unknown options' end,function() SandboxVars.SaucedCarts=options end,'sandbox options type')
   local getData=SaucedCarts.getCartData
   rejects(function() SaucedCarts.getCartData=function() return data end end,function() SaucedCarts.getCartData=getData end,'getCartData helper')
   local sourceQuery=capacityCompat.isCartCapacitySource
   rejects(function() capacityCompat.isCartCapacitySource=function() return true end end,function() capacityCompat.isCartCapacitySource=sourceQuery end,'capacity source query')
   local proof=PZSurvivorToolkit.cartCapacityMatches
   rejects(function() PZSurvivorToolkit.cartCapacityMatches=function() return true end end,function() PZSurvivorToolkit.cartCapacityMatches=proof end,'native transition proof')
   destination.acceptFunction='foreign.acceptCartItem'
   local queue=fixture.queue(head,a,action(cargoC,sourceContainer,destination),tail)
   assert(checkedPolicy.moveReason(queue,queue.queue[3],a)=='move_dependent' and checkedPolicy.cancelOperationReason(queue,queue.queue[3])=='operation_dependent','unknown cart acceptance callback acquired controls')
   destination.acceptFunction=nil
  end
  p,inv=previousPlayer,previousInventory
 end
 for _,mode in ipairs({'foreign-predecessor','already-wrapped','missing-metatable','missing-wrapper','changed-source','valid'}) do scenario(mode) end
end
print('Cart queue contracts passed: actual early capacity wrappers, carried cart-to-cart, conservative incoming bounds, ownership/helper guards, batching, SP returns and protected MP sends.')
