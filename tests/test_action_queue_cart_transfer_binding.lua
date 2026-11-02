local cartInputs={
    {path='shared/SaucedCarts/Core.lua',name='CartBindingCoreSource',text=CartBindingCoreSource},
    {path='shared/SaucedCarts/CartData.lua',name='CartBindingDataSource',text=CartBindingDataSource},
    {path='shared/SaucedCarts/Network.lua',name='CartBindingNetworkSource',text=CartBindingNetworkSource},
    {path='shared/SaucedCarts/TimedActions/ISCartTransferAction.lua',name='CartBindingActionSource',text=CartBindingActionSource},
    {path='shared/SaucedCarts/CartTransferInterceptor.lua',name='CartBindingInterceptorSource',text=CartBindingInterceptorSource},
    {path='client/SaucedCarts/Restrictions/TransferRestrictions.lua',name='CartBindingRestrictionsSource',text=CartBindingRestrictionsSource},
    {path='client/SaucedCarts/CartState/VisualUpdateQueue.lua',name='CartBindingVisualSource',text=CartBindingVisualSource},
}
local missing=not NativeActionRoot and 'Native action sources unavailable; pass --game or --native-action-root.'or nil
local allBound=true
for _,input in ipairs(cartInputs)do if type(input.text)~='string'then allBound=false;break end end
if not SaucedCartsSource then
    for _,input in ipairs(cartInputs)do
        if type(input.text)~='string'then missing='SaucedCarts source unavailable: '..input.name;break end
    end
end
if missing then
    if TestCoverage then TestCoverage('native-branch-contract','skipped',missing)end
    return
end
local function read(path)
    local normalized=path:gsub('\\','/')
    for _,input in ipairs(cartInputs)do
        if normalized:sub(-#input.path)==input.path then
            input.read=true
            if type(input.text)=='string'then return input.text:gsub('\r','')end
            break
        end
    end
    if NativeReadText then return NativeReadText(path):gsub('\r','') end
    local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
local function reader(text)
    local position=1
    return {close=function()end,readLine=function()
        if position>#text then return nil end
        local boundary=text:find('\n',position,true)or #text+1
        local line=text:sub(position,boundary-1);position=boundary+1;return line
    end}
end
local function body(text,declaration)
    local first=assert(text:find(declaration,1,true),declaration)
    local last=assert(text:find('\nend',first,true),declaration)
    return text:sub(first,last+3)
end
local function source(text,path)return assert(loadstring(text,'@'..path))()end
local nativeFilename=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
-- Locked inputs can be mixed version/common files and need no physical root.
-- Filenames remain stable provenance labels for the actual bound source text.
local cartRoot=allBound and 'upstream/SaucedCarts/media/lua/shared/SaucedCarts'or SaucedCartsSource
local clientRoot=cartRoot:gsub('/shared/SaucedCarts/?$','/client/SaucedCarts')
local mediaRoot=cartRoot:gsub('/shared/SaucedCarts/?$','')
local function setup(options)
    options=options or {}
    local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    local calls,reads,callbacks={},0,0
    local forbidden,hook=false,nil
    local canonicalLines={}
    local function effect()callbacks=callbacks+1;error('Cart lease invoked a getter, guard, constructor or effect')end
    isClient,isServer=function()return false end,function()return false end
    getDebug=function()return false end;SandboxVars={SaucedCarts={}}
    getActivatedMods=function()return {contains=function(_,id)return id=='SaucedCarts'end}end
    getFilenameOfClosure=function(callback)
        assert(not forbidden,'metadata read after final Cart facts')
        reads=reads+1
        if hook then local visit=hook;hook=nil;visit()end
        return nativeFilename(callback)
    end
    getFirstLineOfClosure=not options.noLine and function(callback)
        assert(not forbidden,'first-line metadata read after final Cart facts')
        reads=reads+1
        if NativeFirstLineOfClosure then return NativeFirstLineOfClosure(callback)end
        return canonicalLines[callback]or debug.getinfo(callback,'S').linedefined
    end or nil
    getModFileReader=function(mod,path)
        assert(not forbidden,'source read after final Cart facts');assert(mod=='SaucedCarts')
        reads=reads+1
        local text=read(mediaRoot..'/'..path:gsub('^media/lua/',''))
        if options.changedSource and path:find(options.changedSource,1,true)then text=text..'--changed\n'end
        return reader(text)
    end
    local starts={}
    Events.OnGameStart.Add=function(callback)starts[#starts+1]=callback end
    local basicRequire=require
    require=function(name)
        if name:sub(1,12)=='SaucedCarts/'then return nil end
        return basicRequire(name)
    end
    SaucedCarts=nil
    for _,name in ipairs({'Core.lua','CartData.lua','Network.lua','TimedActions/ISCartTransferAction.lua'})do
        source(read(cartRoot..'/'..name),cartRoot..'/'..name)
    end
    canonicalLines[SaucedCarts.isCart]=295;canonicalLines[SaucedCarts.safeIsCart]=320
    canonicalLines[SaucedCarts.Network.getCartFromContainer]=175;canonicalLines[SaucedCarts.getCartData]=561
    if NativeFirstLineOfClosure then
        for callback,line in pairs(canonicalLines)do assert(NativeFirstLineOfClosure(callback)==line,'canonical native role line changed')end
    end
    if options.alias=='isCart'then SaucedCarts.isCart=SaucedCarts.safeIsCart
    elseif options.alias=='safeIsCart'then SaucedCarts.safeIsCart=SaucedCarts.isCart
    elseif options.alias=='getCartFromContainer'then SaucedCarts.Network.getCartFromContainer=SaucedCarts.Network.sendToServer
    elseif options.alias=='getCartData'then SaucedCarts.getCartData=SaucedCarts.getCartName end
    SaucedCarts.log=function()end -- Suppress unrelated initialization diagnostics.
    -- Only the reviewed transfer hook families run here. Full Core/CartData/
    -- Network definitions are real sources; their unrelated startup work is not.
    starts={}
    local interceptorPath=cartRoot..'/CartTransferInterceptor.lua'
    local interceptor=read(interceptorPath)
    for _,declaration in ipairs({'function SaucedCarts.performCartTransfer(',
        'function SaucedCarts.flushContainerResync(','function SaucedCarts.requestInventoryRefresh('})do
        source(body(interceptor,declaration),interceptorPath)
    end
    local installShared=source('local interceptionInstalled=false\n'
        ..body(interceptor,'local function containerToCart(')..'\n'
        ..body(interceptor,'local function classifyTransfer(')..'\n'
        ..body(interceptor,'local function installInterception(')..'\nreturn installInterception',interceptorPath)
    if options.lateShared then starts[#starts+1]=installShared else installShared()end
    local nativePerform=ISInventoryTransferAction.perform
    local compatApproved
    if options.approved then
        local globals=source('return {perform=function()end,isTransferPerform=function()return true end}',
            ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua')
        compatApproved=globals.perform
        ISInventoryTransferAction.perform=compatApproved
        PZSurvivorToolkit.ActionQueueCompat={isTransferPerform=globals.isTransferPerform}
    else PZSurvivorToolkit.ActionQueueCompat={}end
    local policyAdopt=function(previous,replacement,guard)
        calls[#calls+1]={previous=previous,replacement=replacement,guard=guard}
        if options.mutateAdoption then previous.perform=effect end
        return true
    end
    PZSurvivorToolkit.ActionQueuePolicy={adoptTransferHooks=policyAdopt}
    PZSurvivorToolkit.ActionQueueOperations={adoptReturnHooks=function(previous,replacement,guard)
        local last=calls[#calls];assert(last.previous==previous and last.replacement==replacement and last.guard==guard);return true
    end}
    PZSurvivorToolkit.ActionQueueDefinitions={registerBehavior=function()end}
    local registered
    PZSurvivorToolkit.ActionQueueItemEditAdapters={registerSourceFactory=function(owner,key,callback)
        assert(key=='transferBinding'and callback==owner.transferBinding);registered={owner=owner,callback=callback};return true
    end}
    local proof
    local restrictionPath=clientRoot..'/Restrictions/TransferRestrictions.lua'
    local visualPath=clientRoot..'/CartState/VisualUpdateQueue.lua'
    require=function(name)
        if name=='PZSurvivorToolkit/SourceProof'then
            if not proof then proof=basicRequire(name)end
            return proof
        elseif name=='SaucedCarts/Restrictions/TransferRestrictions'then
            local callback=source('local transferActionHookInitialized=false\n'
                ..body(read(restrictionPath),'local function initTransferActionHook(')..'\nreturn initTransferActionHook',restrictionPath)
            Events.OnGameStart.Add(callback)
        elseif name=='SaucedCarts/CartState/VisualUpdateQueue'then
            local text=read(visualPath)
            local callback=source(body(text,'local function getCartFromContainer(')..'\n'
                ..body(text,'local function hookTransferAction(')..'\nreturn hookTransferAction',visualPath)
            Events.OnGameStart.Add(callback)
        else return basicRequire(name)end
    end
    local carts=f.project('ActionQueueCarts')
    assert(registered and registered.owner==carts and registered.callback==carts.transferBinding,'source factory not registered at initialization')
    assert(carts.install())
    for _,callback in ipairs(starts)do callback()end
    assert(#calls==(options.lateShared and 3 or 2),'unexpected hook producer count')
    local guard=calls[1].guard
    for _,call in ipairs(calls)do assert(call.guard==guard,'guard identity changed between adoptions')end
    local item={getFullType=effect,getContainer=effect,getID=effect}
    local from={getContainingItem=effect,getParent=effect,getItems=effect,getType=effect}
    local to={getContainingItem=effect,getParent=effect,getItems=effect,getType=effect}
    local action=f.action(ISInventoryTransferAction,{item=item,srcContainer=from,destContainer=to})
    local facts={schema=2,item=item,source=from,destination=to,fullType='Base.Nails',
        sourceParentTypes={'inventory'},destinationParentTypes=false,primaryItemContainerKnown=true,
        destinationOwner={},destinationOwnerFullType='Base.Bag'}
    -- All post-install helpers that would execute native work have sentinels.
    getTimestampMs,createItemTransaction,removeItemTransaction=effect,effect,effect
    InventoryItemFactory={CreateItem=effect};instanceItem=effect
    return {carts=carts,action=action,guard=guard,facts=facts,calls=calls,proof=proof,
        core=SaucedCarts,network=SaucedCarts.Network,cartClass=ISCartTransferAction,
        policy=PZSurvivorToolkit.ActionQueuePolicy,operations=PZSurvivorToolkit.ActionQueueOperations,
        compat=PZSurvivorToolkit.ActionQueueCompat,effect=effect,nativePerform=nativePerform,approved=compatApproved,
        forbid=function()forbidden=true end,hook=function(value)hook=value end,
        counts=function()return callbacks,reads end}
end
local function lease(s)
    local validate=s.carts.transferBinding(s.guard,s.action)
    assert(type(validate)=='function','expected exact Cart source binding lease')
    return validate
end

for _,options in ipairs({{}, {lateShared=true}, {approved=true}})do
    local s=setup(options);local validate=lease(s)
    local count,reads=s.counts();assert(count==0)
    s.carts.status=s.effect;PZSurvivorToolkit.Settings.actionQueue=s.effect
    s.forbid();assert(validate(s.facts),'ordinary native facts lost Cart non-branch proof')
    local after,afterReads=s.counts();assert(after==0 and afterReads==reads,'post-facts Cart callbacks ran')
end

-- Private copies survive mutation of the original adopter argument tables.
do
    local s=setup();local validate=lease(s)
    for _,call in ipairs(s.calls)do call.previous.perform=s.effect;call.replacement.new=s.effect end
    s.forbid();assert(validate(s.facts)and s.counts()==0)
end

-- A guessed guard is never queried, and unrecorded/changed producer paths have
-- no source lease even when their original generic guard returns true.
do
    local s=setup();assert(s.carts.transferBinding(s.effect,s.action)==nil and s.counts()==0)
    s=setup({mutateAdoption=true});assert(s.carts.transferBinding(s.guard,s.action)==nil and s.counts()==0)
end
for _,file in ipairs({'Core.lua','Network.lua','VisualUpdateQueue.lua','TransferRestrictions.lua','CartTransferInterceptor.lua','CartData.lua'})do
    local s=setup({changedSource=file});assert(s.carts.transferBinding(s.guard,s.action)==nil and s.counts()==0,'changed source accepted: '..file)
end

-- A same-file role alias installed before capture is outside the qualifier:
-- source filename alone must never authorize a different helper body.
for _,role in ipairs({'isCart','safeIsCart','getCartFromContainer','getCartData'})do
    local s=setup({alias=role});s.core.debug=s.effect
    assert(s.carts.transferBinding(s.guard,s.action)==nil and s.counts()==0,'same-file pre-install role alias accepted: '..role)
end
do
    local s=setup({noLine=true});assert(s.carts.transferBinding(s.guard,s.action)==nil and s.counts()==0,'missing role accessor accepted')
end

-- Facts are values. Cart lookup, item/container getters, weights, status and
-- capacity are never called to decide these branches after the final native read.
for _,mode in ipairs({'item-cart','holder-cart','unknown-holder','unknown-primary','missing-known',
    'missing-primary-type','primary-source-cart','primary-destination-cart','wrong-schema','wrong-item','wrong-source',
    'missing-source-parents','missing-destination-parents','empty-parent-array','sparse-parent-array','named-parent-array',
    'parent-metatable','facts-metatable'})do
    local s=setup();local validate=lease(s);local facts=s.facts
    if mode=='item-cart'then facts.fullType='SaucedCarts.ShoppingCart'
    elseif mode=='holder-cart'then facts.destinationOwnerFullType='SaucedCarts.ShoppingCart'
    elseif mode=='unknown-holder'then facts.destinationOwnerFullType=nil
    elseif mode=='unknown-primary'then facts.primaryItem={getItemContainer=s.effect};facts.primaryItemContainerKnown=false
    elseif mode=='missing-known'then facts.primaryItemContainerKnown=nil
    elseif mode=='missing-primary-type'then facts.primaryItem={getItemContainer=s.effect}
    elseif mode=='primary-source-cart'or mode=='primary-destination-cart'then
        facts.primaryItem={getItemContainer=s.effect};facts.primaryFullType='SaucedCarts.ShoppingCart'
        facts.primaryItemContainer=mode=='primary-source-cart'and facts.source or facts.destination
    elseif mode=='wrong-schema'then facts.schema=1
    elseif mode=='wrong-item'then facts.item={}
    elseif mode=='wrong-source'then facts.source={}
    elseif mode=='missing-source-parents'then facts.sourceParentTypes=nil
    elseif mode=='missing-destination-parents'then facts.destinationParentTypes=nil
    elseif mode=='empty-parent-array'then facts.sourceParentTypes={}
    elseif mode=='sparse-parent-array'then facts.sourceParentTypes={[1]='inventory',[3]='crate'}
    elseif mode=='named-parent-array'then facts.sourceParentTypes={value='inventory'}
    elseif mode=='parent-metatable'then setmetatable(facts.sourceParentTypes,{__index=s.effect})
    elseif mode=='facts-metatable'then setmetatable(facts,{__index=s.effect})end
    s.forbid();assert(not validate(facts)and s.counts()==0,'unknown/cart facts accepted: '..mode)
end
for _,mode in ipairs({'unrelated-primary-cart','ordinary-primary-endpoint','ordinary-primary-leaf','world-destination'})do
    local s=setup();local validate=lease(s);local facts=s.facts
    if mode=='world-destination'then facts.destinationOwner=nil;facts.destinationOwnerFullType=nil;facts.destinationParentTypes={'crate'}
    else
        facts.primaryItem={getItemContainer=s.effect}
        facts.primaryFullType=mode=='unrelated-primary-cart'and 'SaucedCarts.ShoppingCart'or 'Base.Bag'
        if mode~='ordinary-primary-leaf'then facts.primaryItemContainer=mode=='ordinary-primary-endpoint'and facts.destination or {}end
    end
    s.forbid();assert(validate(facts)and s.counts()==0,'non-cart branch over-rejected: '..mode)
end

for _,mode in ipairs({'core-owner','network-owner','network-getcart','core-isCart','core-safeIsCart','network-send',
    'cart-registry','cart-key-added','cart-key-false','cart-registry-meta','cart-class','cart-method','transfer-new','transfer-perform',
    'transfer-item','source-field','item-field','carts-owner','factory','source-capture','source-matches','source-origin','filename','reader',
    'policy-adopter','return-adopter','compat-approval','first-line','core-getCartData'})do
    local s=setup({approved=mode=='compat-approval'});local validate=lease(s)
    if mode=='core-owner'then SaucedCarts={}
    elseif mode=='network-owner'then s.core.Network={}
    elseif mode=='network-getcart'then s.network.getCartFromContainer=s.effect
    elseif mode=='core-isCart'then s.core.isCart=s.effect
    elseif mode=='core-safeIsCart'then s.core.safeIsCart=s.effect
    elseif mode=='network-send'then s.network.sendToServer=s.effect
    elseif mode=='cart-registry'then s.core.CartTypes={}
    elseif mode=='cart-key-added'then s.core.CartTypes['Base.Nails']={}
    elseif mode=='cart-key-false'then s.core.CartTypes['Base.Nails']=false
    elseif mode=='cart-registry-meta'then setmetatable(s.core.CartTypes,{__index=s.effect})
    elseif mode=='cart-class'then ISCartTransferAction={}
    elseif mode=='cart-method'then s.cartClass.perform=s.effect
    elseif mode=='transfer-new'then ISInventoryTransferAction.new=s.effect
    elseif mode=='transfer-perform'then ISInventoryTransferAction.perform=s.effect
    elseif mode=='transfer-item'then ISInventoryTransferAction.transferItem=s.effect
    elseif mode=='source-field'then s.action.srcContainer={}
    elseif mode=='item-field'then s.action.item={}
    elseif mode=='carts-owner'then PZSurvivorToolkit.ActionQueueCarts={}
    elseif mode=='factory'then s.carts.transferBinding=s.effect
    elseif mode=='source-capture'then s.proof.captureBindings=s.effect
    elseif mode=='source-matches'then s.proof.matches=s.effect
    elseif mode=='source-origin'then s.proof.closure=s.effect
    elseif mode=='filename'then getFilenameOfClosure=s.effect
    elseif mode=='reader'then getModFileReader=s.effect
    elseif mode=='first-line'then getFirstLineOfClosure=s.effect
    elseif mode=='core-getCartData'then s.core.getCartData=s.effect
    elseif mode=='policy-adopter'then s.policy.adoptTransferHooks=s.effect
    elseif mode=='return-adopter'then s.operations.adoptReturnHooks=s.effect
    elseif mode=='compat-approval'then s.compat.isTransferPerform=s.effect end
    s.forbid();assert(not validate(s.facts)and s.counts()==0,'mutated Cart provenance survived: '..mode)
end
for _,mode in ipairs({'mutation','reentry','error'})do
    local s=setup();local nested
    s.hook(function()
        if mode=='mutation'then s.network.getCartFromContainer=s.effect
        elseif mode=='reentry'then nested=s.carts.transferBinding(s.guard,s.action)
        else error('metadata unavailable')end
    end)
    assert(s.carts.transferBinding(s.guard,s.action)==nil and nested==nil and s.counts()==0,'metadata/reentry survived: '..mode)
end
for _,input in ipairs(cartInputs)do assert(input.read,'declared Cart source was not consumed: '..input.name)end
print('Cart transfer binding PASS (actual sources, private adoption records, non-cart native facts, callback-free mutation/reentry).')
if TestCoverage then TestCoverage('native-branch-contract','passed')end
