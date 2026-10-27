-- Execute the complete shipped UI and timed action; only Java/UI objects are doubles.
if not NativeActionRoot then print('Native makeup queue contracts SKIP (requires --game).');return end
next=nil -- Native Kahlua has pairs, but no global next.
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r','')end
    local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
local function reader(text)
    local offset=1
    return {close=function()end,readLine=function()
        if offset>#text then return end
        local stop=text:find('\n',offset,true)or #text+1
        local line=text:sub(offset,stop-1);offset=stop+1;return line
    end}
end
local function list(values)
    return {class='ArrayList',size=function()return #values end,get=function(_,index)return values[index+1]end,
        isEmpty=function()return #values==0 end,contains=function(_,value)
            for _,entry in ipairs(values)do if entry==value then return true end end;return false
        end}
end
local function setup(options)
    options=options or{}
    local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    local savedRequire=require
    getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    getGameFilesInput=function(path)
        local actual=NativeActionRoot..'/'..path:gsub('^media/lua/','')
        if path:find('^media/scripts/')then actual=NativeActionRoot:gsub('/media/lua/?$','')..'/'..path end
        local text=read(actual)
        if options.changedSource and path:find(options.changedSource,1,true)then text=text..'-- foreign source\n'end
        return reader(text)
    end
    getTextManager=function()return{getFontHeight=function()return 16 end}end
    UIFont={Small=1,Medium=2};JoypadState={players={}}
    Events.OnPlayerDeath={Add=function()end};Events.OnClothingUpdated={Add=function()end}
    ISCollapsableWindowJoypad=ISBaseObject:derive('ISCollapsableWindowJoypad')
    function ISCollapsableWindowJoypad:new(_,_,width,height)
        self.__index=self;return setmetatable({width=width,height=height},self)
    end
    function ISCollapsableWindowJoypad:setResizable()end
    function ISCollapsableWindowJoypad:removeFromUIManager()self.closed=true end
    function ISCollapsableWindowJoypad:prerender()end
    function ISCollapsableWindowJoypad:drawRectBorder()end
    function ISCollapsableWindowJoypad:drawTextureScaled()end
    ISUIElement=ISBaseObject:derive('ISUIElement')
    function ISUIElement:new(x,y,width,height)
        self.__index=self;return setmetatable({x=x,y=y,width=width,height=height},self)
    end
    local client=options.client==true
    isClient=function()return client end;isServer=function()return false end
    ISLogSystem={logAction=function()end}
    f.native('shared/Definitions/MakeUpDefinitions.lua')
    f.native('shared/TimedActions/ISApplyMakeUp.lua')
    f.native('shared/RadioCom/ISRadioAction.lua')
    f.native('client/ISUI/ISUI3DModel.lua')
    f.native('client/ISUI/ISMakeUpUI.lua')
    local nativeSelect,nativeApply=ISMakeUpUI.onSelectMakeUp,ISMakeUpUI.onApplyMakeUp
    local player=f.player;player.class='IsoPlayer';player.natives={};player.worn={};player.writes=0
    local inventory=player.inventory;inventory.class='ItemContainer';inventory.values={};inventory.writes=0
    function inventory:AddItem(item)self.writes=self.writes+1;self.values[#self.values+1]=item;item.container=self;return item end
    function inventory:Remove(item)
        self.writes=self.writes+1
        for i,value in ipairs(self.values)do if value==item then table.remove(self.values,i);item.container=nil;return end end
    end
    function inventory:contains(item)return list(self.values):contains(item)end
    function inventory:getItems()return list(self.values)end
    function inventory:getItemById(id)for _,item in ipairs(self.values)do if item:getID()==id then return item end end end
    function inventory:getParent()return player end
    function inventory:getContainingItem()return nil end
    function inventory:getType()return 'inventorymale'end
    function inventory:getCapacityWeight()return 0 end
    function inventory:getEffectiveCapacity()return 50 end
    function inventory:getAcceptItemFunction()end
    function inventory:getOnlyAcceptCategory()end
    function player:getDescriptor()return{}end
    function player:isLocalPlayer()return true end
    function player:isDraggingCorpse()return false end
    function player:isFarming()return false end
    function player:setIsFarming()end
    function player:setTimedActionToRetrigger(value)self.retrigger=value end
    function player:getTimedActionToRetrigger()return self.retrigger end
    function player:getCharacterActions()return list(self.natives)end
    function player:StartAction(value)self.natives[#self.natives+1]=value;value.lua:start()end
    function player:getWornItem(slot)return self.worn[slot]end
    function player:setWornItem(slot,item)self.writes=self.writes+1;self.worn[slot]=item end
    function player:removeWornItem(item)
        self.writes=self.writes+1
        for slot,value in pairs(self.worn)do if value==item then self.worn[slot]=nil end end
    end
    function player:getWornItems()
        local values={};for _,value in pairs(self.worn)do values[#values+1]={getItem=function()return value end}end
        return list(values)
    end
    local nativeInstanceof=instanceof
    instanceof=function(value,name)
        return type(value)=='table'and((value.class=='IsoPlayer'and name=='IsoGameCharacter')
            or((value.class=='Clothing'or value.class=='DrainableComboItem')and name=='InventoryItem'))or nativeInstanceof(value,name)
    end
    LuaTimedActionNew={new=function(action)return {lua=action,isStarted=function()return true end,
        getTable=function()return action end,hasStalled=function()return false end,getJobDelta=function()return 0 end}end}
    local packets,events={},{}
    for _,name in ipairs({'sendAddItemToContainer','sendRemoveItemFromContainer','sendClothing','sendItemStats'})do
        _G[name]=function(...)packets[#packets+1]={name=name,args={...}}end
    end
    triggerEvent=function(name,actor)
        assert(actor==player,'preview facade escaped into a native clothing event')
        events[#events+1]=name
    end
    luautils={stringStarts=function(text,prefix)return text:sub(1,#prefix)==prefix end}
    local scriptText=read(NativeActionRoot:gsub('/media/lua/?$','')..'/media/scripts/generated/items/clothing.txt')
    local locations,scripts={},{}
    ItemType={CLOTHING={}}
    for name,body in scriptText:gmatch('item%s+(MakeUp_[%w_]+)%s*{(.-)}')do
        local slot=assert(body:match('BodyLocation%s*=%s*([%w_:]+)'))
        if not locations[slot]then
            local suffix=slot:match('makeup_(.*)')
            local translation=({fullface='FullFace',eyes='Eyes',eyesshadow='EyesShadow',lips='Lips'})[suffix]
            locations[slot]={getTranslationName=function()return'MakeUp'..assert(translation)end}
        end
        scripts['Base.'..name]={class='Item',slot=locations[slot],getBodyLocation=function(self)return self.slot end,
            getLuaCreate=function()return options.luaCreate end,getFullName=function()return'Base.'..name end,
            getItemConfigKey=function()return options.itemConfigKey end,getItemConfig=function()return options.itemConfig end,
            getItemType=function()return options.itemType or ItemType.CLOTHING end,
            hasComponents=function()return options.outputComponents==true end,getObsolete=function()return options.obsolete==true end,
            getReplaceOnUse=function()return options.outputReplacement end,getReplaceOnDeplete=function()end,
            getActualWeight=function()return options.outputWeight or 1 end,
            getType=function()return name end}
    end
    ItemBodyLocation={MAKE_UP_FULL_FACE=locations['base:makeup_fullface'],MAKE_UP_EYES=locations['base:makeup_eyes'],
        MAKE_UP_EYES_SHADOW=locations['base:makeup_eyesshadow'],MAKE_UP_LIPS=locations['base:makeup_lips']}
    ScriptManager={instance={class='ScriptManager',getItem=function(_,kind)return scripts[kind]end,
        getScriptItem=function(_,kind)return scripts[kind]end,FindItem=function(_,kind)return scripts[kind]end}}
    getScriptManager=function()return ScriptManager.instance end
    local made,visuals=0,0
    instanceItem=function(kind)
        if options.factoryError then error('native factory failure')end
        if options.factoryObserver then options.factoryObserver()end
        local script=assert(scripts[kind],'unknown native script '..tostring(kind));made=made+1
        local item={class='Clothing',id=1000+made,kind=kind,slot=script.slot}
        function item:getID()return self.id end
        function item:getFullType()return self.kind end
        function item:getType()return self.kind:match('%.(.+)')end
        function item:getBodyLocation()return self.slot end
        function item:getContainer()return self.container end
        function item:getScriptItem()return script end
        function item:getWorldItem()return self.world end
        function item:hasComponents()return self.components==true end
        function item:getVisual()
            visuals=visuals+1;self.visualCalls=(self.visualCalls or 0)+1
            if self.visualCalls<=(options.visualDelay or 0)then return nil end
            self.visual=self.visual or{};return self.visual
        end
        return item
    end
    local kit=f.item('Base.MakeupEyes');kit.uses=5;kit.container=inventory;kit.class='DrainableComboItem'
    function kit:getMakeUpType()return'All'end
    function kit:getContainer()return self.container end
    function kit:Use()self.uses=self.uses-1 end
    function kit:getCurrentUses()return self.uses end
    function kit:getUseDelta()return self.uses end
    function kit:getWorldItem()return self.world end
    function kit:hasComponents()return self.components==true end
    function kit:getReplaceOnDeplete()return self.replacement end
    function kit:getWeightEmpty()return self.emptyWeight or 0 end
    function kit:getActualWeight()return self.weight or 0.1 end
    function player:getPrimaryHandItem()return self.primary end
    function player:getSecondaryHandItem()return self.secondary end
    inventory.values[1]=kit
    local views={};local bridgeOK=true
    toolkitMakeupAvatarPreview=function(java,actor,preview)
        assert(actor==player and java and preview,'bridge received foreign ownership')
        views[#views+1]={java=java,actor=actor,preview=preview};return bridgeOK
    end
    toolkitMakeupAvatarPreviewSupported=function()return not options.unsupportedBridge end
    local javaGlobals={}
    getClassSimpleName=function(value)return javaGlobals[value]and'LuaJavaInvoker'or type(value)=='table'and value.class or'LuaClosure'end
    for _,name in ipairs({'getClassSimpleName','instanceof','isClient','getSpecificPlayer','getScriptManager','instanceItem',
        'toolkitMakeupAvatarPreviewSupported','toolkitMakeupAvatarPreview'})do javaGlobals[_G[name]]=true end
    f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
    local makeup,policy,move
    if not options.unpatched then
        move=f.project('ActionQueueMakeupMove')
        require=function(module)
            if module=='PZSurvivorToolkit/ActionQueueMakeup'then return makeup end
            if module=='PZSurvivorToolkit/ActionQueueMakeupMove'then return move end
            if module=='PZSurvivorToolkit/ActionQueueOperations'then return PZSurvivorToolkit.ActionQueueOperations end
            return savedRequire(module)
        end
        makeup=f.project('ActionQueueMakeup')
        policy=f.project('ActionQueuePolicy')
        local installed=makeup.installUI()
        if options.rejectInstall then assert(not installed,'unsupported native source/bridge installed preview wrappers')
        else assert(installed,'native UI/bridge installation refused')end
    end
    local function combo()
        return {options={},selected=1,clear=function(self)self.options={}end,
            addOption=function(self,label)self.options[#self.options+1]={text=label}end,
            addOptionWithData=function(self,label,data)self.options[#self.options+1]={text=label,data=data}end,
            setWidthToOptions=function()end}
    end
    local function ui()
        local window=ISMakeUpUI:new(1,1,kit,player)
        window.add={enable=false};window.remove={enable=false};window.location=combo();window.comboMakeup=combo();window.removeMakeupCombo=combo()
        window.avatarX,window.avatarY,window.avatarWidth,window.avatarHeight=0,0,128,128
        window.avatarPanel=ISUI3DModel:new(0,0,128,128)
        window.avatarPanel.javaObject={setCharacter=function(self,actor)assert(actor==player);self.actor=actor end,
            getCharacter=function(self)return self.actor end,setZoom=function()end,setYOffset=function()end,setXOffset=function()end}
        window:initLocationCombo();window:initRemoveMakeUpCombo();return window
    end
    local function select(window,kind)
        for _,definition in ipairs(MakeUpDefinitions.makeup)do
            if definition.item==kind then window.comboMakeup.options={{data=definition}};window.comboMakeup.selected=1;window:onSelectMakeUp();return end
        end
        error('native makeup definition missing '..kind)
    end
    local function worn(kind)
        local item=instanceItem(kind);inventory.values[#inventory.values+1]=item;item.container=inventory;player.worn[item.slot]=item;return item
    end
    local function waiting()
        local head=f.action(ISBaseTimedAction,{Type='IndependentHead'});head.action={}
        local queue=f.queue(head);local window=ui();select(window,'Base.MakeUp_LipsRed');window:prerender();window:onApplyMakeUp()
        assert(#queue.queue==2,'native multiplayer callback did not append exactly one body')
        return queue,queue.queue[2],window
    end
    return{f=f,player=player,inventory=inventory,kit=kit,ui=ui,select=select,worn=worn,waiting=waiting,
        makeup=makeup,policy=policy,move=move,scripts=scripts,packets=packets,events=events,views=views,options=options,
        nativeSelect=nativeSelect,nativeApply=nativeApply,visuals=function()return visuals end,factories=function()return made end,
        bridge=function(value)bridgeOK=value end,mode=function(value)client=value end}
end

local baseline=setup({unpatched=true});local original=baseline.worn('Base.MakeUp_LipsBlue')
local window=baseline.ui();baseline.select(window,'Base.MakeUp_LipsRed')
assert(baseline.player.worn[original.slot]==window.makeUpSelected and baseline.player.writes>0,
    'stock native selection no longer reproduces unpaid real-character preview')

local value=setup();original=value.worn('Base.MakeUp_LipsBlue');window=value.ui()
local writes,inventoryWrites=value.player.writes,value.inventory.writes
value.select(window,'Base.MakeUp_LipsRed');local first=window.makeUpSelected
assert(first and value.player.worn[original.slot]==original and value.player.writes==writes
    and value.inventory.writes==inventoryWrites and value.kit.uses==5 and #value.packets==0,
    'preview mutated worn items, inventory, kit or network before Apply')
assert(value.visuals()==1 and window.character==value.player,'preview visual was not initialized once or facade leaked')
window:updateAvatar()
assert(#value.events==1 and value.player.writes==writes,'native avatar update escaped the real actor or changed worn state')
window:prerender();assert(#value.views==1 and value.views[1].preview==first,'native avatar render did not overlay isolated preview')
value.select(window,'Base.MakeUp_Crow');local second=window.makeUpSelected
assert(second~=first and value.player.worn[original.slot]==original and value.player.writes==writes,
    'cross-location preview changed real worn state')
value.select(window,'Base.MakeUp_LipsRed');assert(value.player.worn[original.slot]==original and value.player.writes==writes)
local external=value.worn('Base.MakeUp_LipsBlack');window:close()
assert(value.player.worn[original.slot]==external and value.player.writes==writes,'close resurrected a stale previous cosmetic')
for _,method in ipairs({'reinit','onSelectLocation'})do
    window=value.ui();value.select(window,'Base.MakeUp_LipsRed');window:prerender()
    assert(window.add.enable,'ready preview did not enable Apply before '..method)
    window[method](window);window:prerender();window:updateAvatar()
    assert(not window.makeUpSelected and not window.previousMakeUp and value.player.worn[original.slot]==external
        and value.player.writes==writes and not window.add.enable,
        method..' restored stale actor cosmetics or left empty Apply enabled')
end
window=value.ui();value.select(window,'Base.MakeUp_LipsRed');value.bridge(false);window:prerender()
assert(not window.add.enable and value.player.writes==writes,'failed preview bridge fell back to real actor or left Apply enabled')

-- A missing async clothing asset remains detached and becomes usable once ready.
value=setup({visualDelay=2});window=value.ui();value.select(window,'Base.MakeUp_LipsRed')
assert(value.visuals()==1 and value.factories()==1 and not window.add.enable,'unready preview enabled Apply on selection')
window:updateAvatar();window:prerender()
assert(value.visuals()==2 and not window.add.enable and #value.views==0,'unready asset reached the renderer or enabled Apply')
window:prerender()
assert(value.visuals()==3 and window.add.enable and #value.views==1,'ready asset failed to re-enable its isolated preview')
local detached=window.makeUpSelected
window:prerender();window:updateAvatar();window:prerender()
assert(value.visuals()==3 and value.factories()==1 and window.makeUpSelected==detached and #value.views==3
    and value.player.writes==0 and value.inventory.writes==0 and value.kit.uses==5 and #value.packets==0,
    'ready preview reinitialized visuals, reconstructed items or changed real state on later frames')

-- Single-player preserves the native immediate commit and cost timing.
value=setup();original=value.worn('Base.MakeUp_LipsBlue');window=value.ui();value.select(window,'Base.MakeUp_LipsRed')
local preview=window.makeUpSelected;window:prerender();window:onApplyMakeUp()
assert(value.player.worn[original.slot]==preview and value.inventory:contains(preview)and not value.inventory:contains(original)
    and value.kit.uses==4 and #value.packets==0 and not ISTimedActionQueue.queues[value.player],
    'single-player Apply changed native immediate inventory/worn/cost timing')
value=setup();original=value.worn('Base.MakeUp_LipsBlue');window=value.ui();value.select(window,'Base.MakeUp_LipsRed')
preview=window.makeUpSelected;external=value.worn('Base.MakeUp_LipsBlack');window:prerender();window:onApplyMakeUp()
assert(value.player.worn[original.slot]==preview and value.inventory:contains(original)and not value.inventory:contains(external)
    and value.kit.uses==4,'single-player Apply removed a stale preview-time item instead of the current worn item')

-- Multiplayer stays unpaid until the actual complete callback, and only its owned UI receipt is editable.
value=setup({client=true});original=value.worn('Base.MakeUp_LipsBlue')
local queue,body=value.waiting();local policy=value.policy
assert(not body.action and value.kit.uses==5 and value.player.worn[original.slot]==original and #value.packets==0)
local contract=assert(policy.inspect(body),'owned native UI action has no reviewed contract')
assert(contract.cancelWaiting and contract.interrupt=='finish-step','waiting UI receipt lost atomic body policy')
assert(policy.evaluateCancel(queue,body).allowed,'owned unpaid waiting makeup cannot be cancelled')
local readerAction=value.f.action(ISReadABook,{item=value.f.item('Base.BookCarpentry1')})
ISTimedActionQueue.add(readerAction)
assert(not policy.evaluateMove(queue,body,readerAction,true).allowed,'cosmetic output/order received speculative reorder permission')
body:forceCancel();queue:removeFromQueue(body)
assert(value.kit.uses==5 and value.player.worn[original.slot]==original and #value.packets==0
    and queue.queue[2]==readerAction,'waiting cancellation paid or removed the independent reader')
local arbitrary=ISApplyMakeUp:new(value.player,value.kit,'Base.MakeUp_LipsRed');ISTimedActionQueue.add(arbitrary)
local arbitraryContract=policy.inspect(arbitrary)
assert(not arbitraryContract or not arbitraryContract.cancelWaiting,'reconstructed native class instance inherited UI ownership')
queue,body=value.waiting()
local copied=ISApplyMakeUp:new(value.player,value.kit,'Base.MakeUp_LipsRed')
for key,entry in pairs(body)do copied[key]=entry end
queue.queue[2]=copied
local copiedContract=policy.inspect(copied)
assert(not copiedContract or not copiedContract.cancelWaiting,'copied action fields reconstructed a sealed UI receipt')
queue,body,window=value.waiting();assert(body:complete()==true and value.kit.uses==4 and #value.packets==4,
    'unchanged native complete did not deliver exactly its original cost and outputs')
assert(value.player.worn[original.slot]:getFullType()=='Base.MakeUp_LipsRed'and not value.inventory:contains(original))
external=value.worn('Base.MakeUp_LipsBlack');writes=value.player.writes;window:close()
assert(value.player.worn[original.slot]==external and value.player.writes==writes and #value.packets==4,
    'closing an already paid multiplayer window resurrected stale preview-time worn state')

for _,change in ipairs({'native','token','started','cancelled','generation','queue','queue-actor','duplicate','shared-token',
    'actor','kit','type','duration','callback','instance','class','extra-helper','ui','bridge'})do
    value=setup({client=true});queue,body,window=value.waiting()
    if change=='native'then body.action={}
    elseif change=='token'then body.toolkitQueueOperation={}
    elseif change=='started'then body.toolkitQueueOperation.toolkitStarted=true
    elseif change=='cancelled'then body.toolkitQueueOperation.toolkitCancelled=true
    elseif change=='generation'then queue.toolkitOperationGeneration=(queue.toolkitOperationGeneration or 0)+1
    elseif change=='queue'then value.f.queue(queue.current,body)
    elseif change=='queue-actor'then queue.character={getPlayerNum=function()return 1 end}
    elseif change=='duplicate'then queue.queue[3]=body
    elseif change=='shared-token'then queue.queue[3]=value.f.action(ISBaseTimedAction,{toolkitQueueOperation=body.toolkitQueueOperation})
    elseif change=='actor'then body.character={}
    elseif change=='kit'then body.item=value.f.item('Base.MakeupEyes')
    elseif change=='type'then body.type='Base.MakeUp_Crow'
    elseif change=='duration'then body.maxTime=100
    elseif change=='callback'then body.onCompleteFunc=function()error('must never execute during policy inspection')end
    elseif change=='instance'then body.complete=function()end
    elseif change=='class'then ISApplyMakeUp.complete=function()end
    elseif change=='extra-helper'then ISApplyMakeUp.unreviewedHelper=function()end
    elseif change=='ui'then ISMakeUpUI.onApplyMakeUp=function()end
    elseif change=='bridge'then toolkitMakeupAvatarPreview=function()return true end end
    local inspected=value.policy.inspect(body)
    assert(not inspected or not inspected.cancelWaiting,change..' retained waiting cancellation after ownership changed')
    assert(not value.policy.evaluateCancel(queue,body).allowed,change..' received a cancellation decision')
    assert(not value.policy.evaluateMove(queue,body,body,false).allowed,change..' received a move decision')
end

-- A pending deletion executes no body or UI callback. Later passive state changes
-- do not turn an otherwise owned zero-effect cancellation into a dependency.
for _,change in ipairs({'not-carried','ui-instance','avatar-instance','closed','lua-create','config-key','config','definitions'})do
    value=setup({client=true});queue,body,window=value.waiting()
    if change=='not-carried'then value.kit.container=nil
    elseif change=='ui-instance'then window.onApplyMakeUp=function()error('must never execute during cancellation')end
    elseif change=='avatar-instance'then window.avatarPanel.setCharacter=function()error('must never execute during cancellation')end
    elseif change=='closed'then window:close()
    elseif change=='lua-create'then value.options.luaCreate='Unknown.Callback'
    elseif change=='config-key'then value.options.itemConfigKey='Unknown.Config'
    elseif change=='config'then value.options.itemConfig={}
    elseif change=='definitions'then
        for _,definition in ipairs(MakeUpDefinitions.makeup)do if definition.item==body.type then definition.makeuptypes.All=nil end end
    end
    assert(value.policy.evaluateCancel(queue,body).allowed,change..' blocked safe deletion of an already owned unpaid body')
    body:forceCancel();queue:removeFromQueue(body)
    assert(value.kit.uses==5 and #value.packets==0 and value.player.writes==0,change..' executed effects during waiting deletion')
end

value=setup();window=value.ui();value.options.factoryError=true
local ok,message=pcall(value.select,window,'Base.MakeUp_LipsRed')
assert(not ok and tostring(message):find('native factory failure',1,true)and window.character==value.player,
    'native factory exception leaked the temporary actor facade')
for _,source in ipairs({'ISMakeUpUI.lua','ISUI3DModel.lua','ISApplyMakeUp.lua','MakeUpDefinitions.lua'})do
    value=setup({changedSource=source,rejectInstall=true})
    assert(ISMakeUpUI.onSelectMakeUp==value.nativeSelect and ISMakeUpUI.onApplyMakeUp==value.nativeApply,
        'unreviewed source received owned UI wrappers: '..source)
end
value=setup({unsupportedBridge=true,rejectInstall=true})
assert(ISMakeUpUI.onSelectMakeUp==value.nativeSelect,'unsupported Java preview API installed UI wrappers')
-- Once native preview state exists, retain its restoration ownership when a
-- later selection becomes supported; a detached receipt cannot adopt it.
for _,applySelection in ipairs({false,true})do
    value=setup({client=true,luaCreate='Unknown.Callback'});original=value.worn('Base.MakeUp_LipsBlue');window=value.ui()
    queue=value.f.queue(value.f.action(ISBaseTimedAction,{Type='IndependentHead',action={}}))
    value.options.factoryObserver=function()
        assert(window.character==value.player,'native preview state was adopted by the detached selector')
    end
    value.select(window,'Base.MakeUp_LipsRed')
    assert(value.player.worn[original.slot]==window.makeUpSelected and window.previousMakeUp==original,
        'unsupported selector did not establish native restoration state')
    value.options.luaCreate=nil
    value.select(window,'Base.MakeUp_LipsBlack');window:prerender()
    assert(value.player.worn[original.slot]==window.makeUpSelected and window.previousMakeUp==original and #value.views==0,
        'supported selection lost or adopted existing native preview ownership')
    if applySelection then
        window:onApplyMakeUp();body=queue.queue[2]
        local protected=body and value.policy.inspect(body)
        assert(body and(not protected or not protected.cancelWaiting)and not value.policy.evaluateCancel(queue,body).allowed,
            'native-to-supported selector transition granted a detached pending receipt')
    else
        window:close()
        assert(value.player.worn[original.slot]==original and value.kit.uses==5 and #value.packets==0,
            'closing a native-to-supported selection failed to restore the original worn item')
    end
end
for _,change in ipairs({'lua-create','config-key','config'})do
    local options={client=true}
    if change=='lua-create'then options.luaCreate='Unknown.Callback'
    elseif change=='config-key'then options.itemConfigKey='Unknown.Config'
    else options.itemConfig={}end
    value=setup(options);window=value.ui()
    local factories=0
    options.factoryObserver=function()
        factories=factories+1;assert(window.character==value.player,'unsupported factory observed the temporary preview facade')
    end
    queue=value.f.queue(value.f.action(ISBaseTimedAction,{Type='IndependentHead',action={}}))
    value.select(window,'Base.MakeUp_LipsRed');window:prerender();window:onApplyMakeUp()
    body=queue.queue[2];assert(body and factories==1 and #value.views==0,'unsupported cosmetic lost its native UI path')
    local protected=value.policy.inspect(body)
    assert(not protected or not protected.cancelWaiting,change..' granted an owned UI receipt to unsupported cosmetic scripts')
    assert(not value.policy.evaluateCancel(queue,body).allowed,change..' admitted unreviewed native producer state')
end
for _,change in ipairs({'run-with','operations-module','instanceof','slot','bridge','unsupported-bridge','avatar-instance','disabled'})do
    value=setup({client=true});window=value.ui()
    queue=value.f.queue(value.f.action(ISBaseTimedAction,{Type='IndependentHead',action={}}))
    value.select(window,'Base.MakeUp_LipsRed');window:prerender()
    local function foreign()error('foreign '..change..' binding executed')end
    if change=='run-with'then PZSurvivorToolkit.ActionQueueOperations.runWith=foreign
    elseif change=='operations-module'then PZSurvivorToolkit.ActionQueueOperations={runWith=foreign}
    elseif change=='instanceof'then instanceof=foreign
    elseif change=='slot'then ItemBodyLocation.MAKE_UP_LIPS={}
    elseif change=='bridge'then toolkitMakeupAvatarPreview=foreign
    elseif change=='avatar-instance'then window.avatarPanel.setCharacter=foreign
    elseif change=='unsupported-bridge'then value.options.unsupportedBridge=true
    elseif change=='disabled'then PZSurvivorToolkit.Settings.actionQueue=function()return false end end
    window:prerender();window:updateAvatar()
    window:onApplyMakeUp()
    assert(#queue.queue==1 and not window.add.enable and value.kit.uses==5 and #value.packets==0
        and value.player.writes==0 and value.inventory.writes==0,
        change..' executed a foreign producer or fell back to a real actor preview')
end
-- The current snapshot can support moves only when every earlier declarative
-- footprint preserves it. These checks execute the shipped helper and policy.
local function movable()
    local s=setup({client=true})
    local old=s.worn('Base.MakeUp_LipsBlue')
    local q,a=s.waiting()
    local head=s.f.action(ISReadABook,{item=s.f.item('Base.BookCarpentry1')})
    q.queue[1],q.current=head,head
    local tail=s.f.action(ISReadABook,{item=s.f.item('Base.BookCarpentry2')})
    q.queue[3]=tail
    return s,q,a,old,head,tail
end
local function inspectMove(s,a)
    local result={items={},itemTypes={},targets={[s.player]=true},hands=s.player,equipment=s.player,
        knownInputs=false,unknownOutputs=true,cancelWaiting=true,cancelOperation=true}
    local ok=s.move.apply(a,result,s.policy,{contracts={},items={}})
    return ok,result
end
value,queue,body,original=movable()
local beforeFactories,beforeVisuals=value.factories(),value.visuals()
writes,inventoryWrites=value.player.writes,value.inventory.writes
local allowed,footprint=inspectMove(value,body)
assert(allowed and footprint.knownInputs and not footprint.unknownOutputs
    and footprint.items[value.kit:getID()]and footprint.items[original:getID()]
    and footprint.itemTypes[value.kit:getFullType()]and footprint.outputTypes[body.type],
    'pure native makeup move proof omitted exact kit/worn/output resources')
assert(not footprint.capacityNonIncreasing and value.factories()==beforeFactories and value.visuals()==beforeVisuals
    and value.player.writes==writes and value.inventory.writes==inventoryWrites and value.kit.uses==5 and #value.packets==0,
    'move inspection allocated, initialized visuals, changed state or credited speculative capacity')
for _,slot in ipairs({ItemBodyLocation.MAKE_UP_FULL_FACE,ItemBodyLocation.MAKE_UP_EYES,ItemBodyLocation.MAKE_UP_EYES_SHADOW})do
    local kind=slot==ItemBodyLocation.MAKE_UP_FULL_FACE and'Base.MakeUp_CamoFullFace1'
        or slot==ItemBodyLocation.MAKE_UP_EYES and'Base.MakeUp_Crow'or'Base.MakeUp_EyesShadowWhite'
    local item=value.worn(kind);allowed,footprint=inspectMove(value,body)
    assert(allowed and footprint.items[item:getID()],'another worn cosmetic slot was omitted')
end

for _,change in ipairs({'one-use','replacement','weight-empty','nan-weight','held-kit','secondary-kit','kit-components','kit-class',
    'kit-world','kit-nested','kit-duplicate','kit-id','output-components','output-type','obsolete','output-replacement',
    'output-weight','lua-create','config-key','config','old-held','old-components','old-script-components','old-class',
    'old-location','old-duplicate','other-slot-held','root-callback','root-category','definitions','item-type-binding',
    'locations-binding','global-binding','policy-binding'})do
    value,queue,body,original=movable()
    -- Bind the policy once before replacing an entry point.
    assert(inspectMove(value,body))
    if change=='one-use'then value.kit.uses=1
    elseif change=='replacement'then value.kit.replacement='Base.Unknown'
    elseif change=='weight-empty'then value.kit.emptyWeight=0.01
    elseif change=='nan-weight'then value.kit.weight=0/0
    elseif change=='held-kit'then value.player.primary=value.kit
    elseif change=='secondary-kit'then value.player.secondary=value.kit
    elseif change=='kit-components'then value.kit.components=true
    elseif change=='kit-class'then value.kit.class='ForeignKit'
    elseif change=='kit-world'then value.kit.world={}
    elseif change=='kit-nested'then value.kit.container={}
    elseif change=='kit-duplicate'then value.inventory.values[#value.inventory.values+1]=value.kit
    elseif change=='kit-id'then value.kit.id=0
    elseif change=='output-components'then value.options.outputComponents=true
    elseif change=='output-type'then value.options.itemType={}
    elseif change=='obsolete'then value.options.obsolete=true
    elseif change=='output-replacement'then value.options.outputReplacement='Base.Unknown'
    elseif change=='output-weight'then value.options.outputWeight=math.huge
    elseif change=='lua-create'then value.options.luaCreate='Unknown.Callback'
    elseif change=='config-key'then value.options.itemConfigKey='Unknown.Config'
    elseif change=='config'then value.options.itemConfig={}
    elseif change=='old-held'then value.player.primary=original
    elseif change=='old-components'then original.components=true
    elseif change=='old-script-components'then original:getScriptItem().hasComponents=function()return true end
    elseif change=='old-class'then original.class='ForeignClothing'
    elseif change=='old-location'then original.container={}
    elseif change=='old-duplicate'then value.inventory.values[#value.inventory.values+1]=original
    elseif change=='other-slot-held'then value.player.secondary=value.worn('Base.MakeUp_Crow')
    elseif change=='root-callback'then value.inventory.getAcceptItemFunction=function()return'Unknown.Callback'end
    elseif change=='root-category'then value.inventory.getOnlyAcceptCategory=function()return'Appearance'end
    elseif change=='definitions'then
        for _,definition in ipairs(MakeUpDefinitions.makeup)do if definition.item==body.type then definition.makeuptypes.All=nil end end
    elseif change=='item-type-binding'then ItemType={CLOTHING=ItemType.CLOTHING}
    elseif change=='locations-binding'then ItemBodyLocation={}
    elseif change=='global-binding'then getScriptManager=function()error('foreign manager executed')end
    elseif change=='policy-binding'then value.policy.inspect=function()error('foreign inspector executed')end end
    allowed,footprint=inspectMove(value,body)
    assert(not allowed and footprint.pendingMoveBlocker and footprint.cancelWaiting and footprint.cancelOperation
        and footprint.knownInputs==false and footprint.unknownOutputs==true,
        change..' granted move proof or changed cancellation policy')
    for _ in pairs(footprint.items)do error(change..' leaked staged input resources')end
    assert(value.kit.uses==(change=='one-use'and 1 or 5)and #value.packets==0,'denied inspection consumed or sent state')
    if change=='one-use'or change=='replacement'or change=='held-kit'or change=='output-components'or change=='old-held'then
        assert(value.policy.evaluateCancel(queue,body).allowed,change..' disabled owned zero-effect waiting deletion')
    end
end

value,queue,body=movable();value.kit.uses=1
local legacy={items={[876]=true},itemTypes={['Base.Legacy']=true},outputTypes={['Base.LegacyOutput']=true},
    cancelWaiting=true,cancelOperation=true,knownInputs=false,unknownOutputs=true}
assert(not value.move.apply(body,legacy,value.policy,{contracts={},items={}})
    and legacy.items[876]and legacy.itemTypes['Base.Legacy']and legacy.outputTypes['Base.LegacyOutput']
    and not legacy.items[value.kit:getID()]and not legacy.outputTypes[body.type],
    'failed move proof changed the pre-existing legacy resource footprint')

-- A reader/radio name is not an exception: inspect predecessor contracts and
-- refuse any resource/actor writer, including an unchanged queued prefix.
for _,change in ipairs({'unknown','unknown-inputs','unknown-outputs','same-actor','false-actor','hands','equipment','shared-kit',
    'old-consumer','container-owner','type-selector','short-selector','output-type','appearance','queue-mutation','recursive'})do
    value,queue,body,original=movable()
    local previous=value.f.action(ISBaseTimedAction,{Type='MakeupPrefixProbe'})
    local c={items={},itemTypes={},targets={}}
    if change=='unknown'then c=nil
    elseif change=='unknown-inputs'then c.knownInputs=false
    elseif change=='unknown-outputs'then c.unknownOutputs=true
    elseif change=='same-actor'or change=='appearance'then c.targets[value.player]=true
    elseif change=='false-actor'then c.targets[value.player]=false
    elseif change=='hands'then c.hands=value.player
    elseif change=='equipment'then c.equipment=value.player
    elseif change=='shared-kit'then c.items[value.kit:getID()]=true
    elseif change=='old-consumer'then c.items[original:getID()]=true
    elseif change=='container-owner'then c.containerOwners={[original:getID()]=true}
    elseif change=='type-selector'then c.dynamicInputs={[value.kit:getFullType()]=true}
    elseif change=='short-selector'then c.dynamicInputsByType={MakeupEyes=true}
    elseif change=='output-type'then c.outputTypes={[original:getFullType()]=true}end
    PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('test.makeup-prefix',{
        types={'MakeupPrefixProbe'},matches=function(a)return a==previous end,inspect=function()
            if change=='queue-mutation'then queue.queue[1]=value.f.action(ISBaseTimedAction,{Type='Foreign'})end
            if change=='recursive'then
                local nested={items={},itemTypes={}}
                assert(not value.move.apply(body,nested,value.policy,{contracts={},makeupMovePrefix={queue=queue,index=2}}),
                    'same-index recursive makeup inspection was admitted')
                return nil
            end
            return c
        end})
    queue.queue[1],queue.current=previous,previous
    allowed,footprint=inspectMove(value,body)
    assert(not allowed and footprint.pendingMoveBlocker,'unmodeled prefix '..change..' preserved snapshot proof')
end

-- The actual shipped radio constructor has a disjoint declarative footprint.
value,queue,body=movable()
local device={getDeviceData=function()return{}end}
local radio=ISRadioAction:new('ToggleOnOff',value.player,device);radio.toolkitQueueOperation={}
queue.queue[1],queue.current=radio,radio
assert(inspectMove(value,body),'independent native radio was rejected by a type whitelist')

value,queue,body,original=movable()
local head,tail=queue.queue[1],queue.queue[3]
assert(value.policy.evaluateMove(queue,body,tail,true).allowed,'owned pending makeup cannot cross an independent pending reader')
queue.queue[2],queue.queue[3]=tail,body
assert(value.policy.evaluateMove(queue,body,tail,false).allowed,'owned pending makeup cannot move before an independent pending reader')
head.action={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
local decision=value.policy.evaluateMove(queue,body,head,false)
assert(decision.allowed and decision.preempt,'owned pending makeup cannot be promoted before the current independent reader')
queue.queue[2],queue.queue[3]=body,tail
decision=value.policy.evaluateMove(queue,head,body,true)
assert(decision.allowed and decision.demote,'lowering the current reader cannot promote owned pending makeup')
radio=ISRadioAction:new('ToggleOnOff',value.player,device);radio.toolkitQueueOperation={};queue.queue[3]=radio
assert(value.policy.evaluateMove(queue,body,radio,true).allowed,'owned pending makeup cannot cross disjoint native radio')
local transfer=value.f.action(ISInventoryTransferAction,{item=value.f.item('Base.Bandage'),
    srcContainer=value.inventory,destContainer=value.inventory})
queue.queue[3]=transfer
decision=value.policy.evaluateMove(queue,body,transfer,true)
assert(not decision.allowed and decision.reason=='container_capacity','makeup bypassed conservative transfer capacity ordering')
for _,change in ipairs({'shared-kit','old-consumer','output-consumer','appearance','unsupported'})do
    value,queue,body,original=movable()
    local crossed=value.f.action(ISBaseTimedAction,{Type='MakeupCrossProbe'})
    local c={items={},itemTypes={},targets={}}
    if change=='shared-kit'then c.items[value.kit:getID()]=true
    elseif change=='old-consumer'then c.items[original:getID()]=true
    elseif change=='output-consumer'then c.itemTypes[body.type]=true
    elseif change=='appearance'then c.targets[value.player]=true
    else c.knownInputs=false end
    PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('test.makeup-cross',{
        types={'MakeupCrossProbe'},matches=function(a)return a==crossed end,inspect=function()return c end})
    queue.queue[3]=crossed
    assert(not value.policy.evaluateMove(queue,body,crossed,true).allowed,
        change..' crossed the makeup body despite a resource dependency')
end
print('Native makeup preview isolation, SP/MP cost timing, owned waiting receipts and pure move footprint tests passed.')
