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
    f.native('client/Vehicles/TimedActions/ISPathFindAction.lua')
    f.native('shared/TimedActions/ISOpenCloseDoor.lua')
    f.native('shared/TimedActions/ISOpenCloseWindow.lua')
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
    function inventory:getVehiclePart()return self.part end
    function inventory:isExistYet()return not self.gone end
    function inventory:getSourceGrid()return self.square end
    function inventory:isInCharacterInventory(actor)return actor==player end
    local function recursive(container,id)
        for _,item in ipairs(container.values)do
            if item:getID()==id then return item end
            if item.class=='InventoryContainer'then local found=recursive(item:getInventory(),id);if found then return found end end
        end
    end
    function inventory:getItemWithIDRecursiv(id)return recursive(self,id)end
    local squares={}
    local function square(x,y,z)
        local key=x..','..y..','..z
        if squares[key]then return squares[key]end
        local s={class='IsoGridSquare',x=x,y=y,z=z,objects={},special={},worlds={}}
        function s:getX()return self.x end;function s:getY()return self.y end;function s:getZ()return self.z end
        function s:getObjects()return list(self.objects)end
        function s:getSpecialObjects()return list(self.special)end
        function s:getWorldObjects()return list(self.worlds)end
        function s:getStaticMovingObjects()return list({})end
        function s:isBlockedTo(other)return self.blocked==true end
        squares[key]=s;return s
    end
    local cell={class='IsoCell',getGridSquare=function(_,x,y,z)return squares[x..','..y..','..z]end}
    getCell=function()return cell end;getVehicleById=function()error('unexpected vehicle resolution')end
    SafeHouse={isSafehouseAllowLoot=function()return not options.lootDenied end}
    player.square=square(10,10,0)
    function player:getCurrentSquare()return self.square end
    function player:canAccessContainer(container)return not container.locked end
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
        local worn=list(values);worn.class='WornItems'
        function worn:contains(item)for _,entry in ipairs(values)do if entry:getItem()==item then return true end end;return false end
        return worn
    end
    local nativeInstanceof=instanceof
    instanceof=function(value,name)
        return type(value)=='table'and((value.class=='IsoPlayer'and name=='IsoGameCharacter')
            or((value.class=='Clothing'or value.class=='DrainableComboItem'or value.class=='InventoryContainer')and name=='InventoryItem')
            or((value.class=='IsoWorldInventoryObject'or value.class=='IsoDoor'or value.class=='IsoWindow')and name=='IsoObject'))or nativeInstanceof(value,name)
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
    ItemType={CLOTHING={},CONTAINER={},DRAINABLE={}}
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
    local kitKind=options.kitKind or'Base.MakeupEyes'
    local kitScript={class='Item',getFullName=function()return kitKind end,getItemType=function()return ItemType.DRAINABLE end,
        hasComponents=function(self)return self.components==true end,getObsolete=function(self)return self.obsolete==true end,
        getLuaCreate=function(self)return self.luaCreate end,getItemConfigKey=function(self)return self.configKey end,
        getItemConfig=function(self)return self.config end,getReplaceOnUse=function(self)return self.replaceOnUse end,
        getReplaceOnDeplete=function(self)return self.replaceOnDeplete end,getActualWeight=function()return 0.1 end,
        isDisappearOnUse=function(self)return self.disappear~=false end}
    scripts[kitKind]=kitScript
    local kit=f.item(kitKind);kit.uses=options.kitUses or 5;kit.container=inventory;kit.class='DrainableComboItem'
    function kit:getMakeUpType()return options.kitMakeupType or'All'end
    function kit:getScriptItem()return self.script or kitScript end
    function kit:getReplaceOnUse()return self.replaceOnUse end
    function kit:getLuaCreate()return self:getScriptItem():getLuaCreate()end
    function kit:isDisappearOnUse()return self:getScriptItem():isDisappearOnUse()end
    function kit:isKeepOnDeplete()return not self:isDisappearOnUse()end
    function kit:getAttachedSlot()return self.attachedSlot or -1 end
    function kit:getAttachedToModel()return self.attachedToModel end
    function kit:getAttachedSlotType()return self.attachedSlotType end
    function kit:getEquipParent()return self.equipParent end
    function kit:isActivated()return self.activated==true end
    function kit:getIsCraftingConsumed()return self.craftingConsumed==true end
    function kit:isUseWhileEquiped()return self.useWhileEquipped==true end
    function kit:isUseWhileUnequiped()return self.useWhileUnequipped==true end
    function player:isEquipped(item)
        if self.primary==item or self.secondary==item then return true end
        for _,worn in pairs(self.worn)do if worn==item then return true end end
        return false
    end
    function kit:getContainer()return self.container end
    function kit:getOutermostContainer()
        local c=self.container
        if c and c:getType()=='floor'then return nil end
        while c and c:getContainingItem()and c:getContainingItem():getContainer()do
            local parent=c:getContainingItem():getContainer()
            -- InventoryItem stops at a ground bag before its UI floor alias.
            if parent:getType()=='floor'then break end
            c=parent
        end
        return c
    end
    function kit:Use()self.uses=self.uses-1 end
    function kit:getCurrentUses()return self.uses end
    function kit:getUses()return self.uses end
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
    for _,name in ipairs({'getClassSimpleName','instanceof','isClient','isServer','getCell','getVehicleById',
        'getSpecificPlayer','getScriptManager','instanceItem',
        'toolkitMakeupAvatarPreviewSupported','toolkitMakeupAvatarPreview'})do javaGlobals[_G[name]]=true end
    javaGlobals[SafeHouse.isSafehouseAllowLoot]=true
    f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
    local makeup,policy,move,access,supplyUse
    if not options.unpatched then
        access=f.project('ItemAccess')
        require=function(module)
            if module=='PZSurvivorToolkit/ActionQueueMakeup'then return makeup end
            if module=='PZSurvivorToolkit/ActionQueueMakeupMove'then return move end
            if module=='PZSurvivorToolkit/ItemAccess'then return access end
            if module=='PZSurvivorToolkit/MakeupSupplyUse'then return supplyUse end
            if module=='PZSurvivorToolkit/ActionQueueOperations'then return PZSurvivorToolkit.ActionQueueOperations end
            return savedRequire(module)
        end
        supplyUse=f.project('MakeupSupplyUse')
        move=f.project('ActionQueueMakeupMove')
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
    local function bag(parent)
        parent=parent or inventory
        local kind='Base.Bag_Schoolbag'
        if not scripts[kind]then
            scripts[kind]={class='Item',getFullName=function()return kind end,getItemType=function()return ItemType.CONTAINER end,
                hasComponents=function(self)return self.components==true end,getObsolete=function()return false end,
                getLuaCreate=function(self)return self.luaCreate end,getItemConfigKey=function(self)return self.configKey end,
                getItemConfig=function(self)return self.config end,getReplaceOnUse=function()end,getReplaceOnDeplete=function()end,
                getActualWeight=function()return 1 end}
        end
        local item=f.item(kind);item.class='InventoryContainer';item.container=parent
        local contents={class='ItemContainer',values={},owner=item,kind='none'}
        function contents:getItems()return list(self.values)end
        function contents:getContainingItem()return self.owner end
        function contents:getParent()return self.parent end
        function contents:getType()return self.kind end
        function contents:getAcceptItemFunction()return self.accept end
        function contents:getOnlyAcceptCategory()return self.category end
        function contents:getVehiclePart()return self.part end
        function contents:isExistYet()return not self.gone end
        function contents:getSourceGrid()return self.square end
        function contents:isInCharacterInventory(actor)
            local current=self
            while current and current~=inventory do local holder=current:getContainingItem();current=holder and holder:getContainer()end
            return current==inventory and actor==player
        end
        function contents:getItemWithIDRecursiv(id)return recursive(self,id)end
        function contents:getItemById(id)for _,member in ipairs(self.values)do if member:getID()==id then return member end end end
        function item:getInventory()return self.contents end
        function item:getScriptItem()return scripts[kind]end
        function item:getContainer()return self.container end
        function item:getWorldItem()return self.world end
        function item:hasComponents()return self.components==true end
        item.contents=contents
        parent.values[#parent.values+1]=item
        return item,contents
    end
    local function waiting()
        local head=f.action(ISBaseTimedAction,{Type='IndependentHead'});head.action={}
        local queue=f.queue(head);local window=ui();select(window,options.outputKind or'Base.MakeUp_LipsRed');window:prerender();window:onApplyMakeUp()
        assert(#queue.queue==2,'native multiplayer callback did not append exactly one body')
        return queue,queue.queue[2],window
    end
    local function worldSource(kind)
        for x=8,13 do for y=8,12 do square(x,y,0)end end
        local s=square(11,10,0)
        local source,object,owner
        if kind=='bag'then
            owner,source=bag()
            for i,item in ipairs(inventory.values)do if item==owner then table.remove(inventory.values,i);break end end
            owner.container=nil
            object={class='IsoWorldInventoryObject',item=owner,square=s}
            function object:getItem()return self.item end
            function object:getWorldObjectIndex()
                for i,v in ipairs(self.square.worlds)do if v==self then return i-1 end end;return -1
            end
            owner.world=object;s.worlds[1]=object
        else
            source={class='ItemContainer',values={},kind=kind or'crate',square=s}
            local _,template=bag();inventory.values[#inventory.values]=nil
            for _,name in ipairs({'getItems','getContainingItem','getParent','getType','getAcceptItemFunction',
                'getOnlyAcceptCategory','getItemById','getVehiclePart','isExistYet','getSourceGrid',
                'isInCharacterInventory','getItemWithIDRecursiv'})do
                -- A native crate is an ordinary ItemContainer, with world parent.
                source[name]=template[name]
            end
            object={class='IsoObject',square=s,containers={source}}
            source.parent=object
            function object:getContainerCount()return #self.containers end
            function object:getContainerByIndex(i)return self.containers[i+1]end
        end
        function object:getSquare()return self.square end
        function object:hasComponents()return self.components==true end
        s.objects[#s.objects+1]=object
        for i,item in ipairs(inventory.values)do if item==kit then table.remove(inventory.values,i);break end end
        source.values[#source.values+1]=kit;kit.container=source
        local door={class='IsoDoor',square=square(10,11,0),getSquare=function(self)return self.square end}
        door.square.objects[#door.square.objects+1]=door;door.square.special[#door.square.special+1]=door
        return source,object,owner,door
    end
    return{f=f,player=player,inventory=inventory,kit=kit,ui=ui,select=select,worn=worn,bag=bag,waiting=waiting,
        makeup=makeup,policy=policy,move=move,access=access,supplyUse=supplyUse,worldSource=worldSource,square=square,squares=squares,
        scripts=scripts,packets=packets,events=events,views=views,options=options,
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
local function movable(options)
    local s=setup(options or{client=true})
    local old=s.worn(options and options.oldKind or'Base.MakeUp_LipsBlue')
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
local function carried(s,nested)
    local outer,source=s.bag()
    local inner
    s.player.worn.back=outer
    if nested then inner,source=s.bag(source)end
    for i,item in ipairs(s.inventory.values)do if item==s.kit then table.remove(s.inventory.values,i);break end end
    source.values[#source.values+1]=s.kit;s.kit.container=source
    return outer,inner,source
end
value,queue,body,original=movable()
local beforeFactories,beforeVisuals=value.factories(),value.visuals()
writes,inventoryWrites=value.player.writes,value.inventory.writes
local allowed,footprint=inspectMove(value,body)
assert(allowed and footprint.knownInputs and not footprint.unknownOutputs
    and footprint.items[value.kit:getID()]and footprint.items[original:getID()]
    and footprint.itemTypes[value.kit:getFullType()]and footprint.outputTypes[body.type],
    'pure native makeup move proof omitted exact kit/worn/output resources')
assert(footprint.containers[value.inventory],'root input footprint omitted its exact container')
assert(not footprint.positions[value.player],'root supplies acquired a world-position dependency')
assert(not footprint.capacityNonIncreasing and value.factories()==beforeFactories and value.visuals()==beforeVisuals
    and value.player.writes==writes and value.inventory.writes==inventoryWrites and value.kit.uses==5 and #value.packets==0,
    'move inspection allocated, initialized visuals, changed state or credited speculative capacity')
for _,slot in ipairs({ItemBodyLocation.MAKE_UP_FULL_FACE,ItemBodyLocation.MAKE_UP_EYES,ItemBodyLocation.MAKE_UP_EYES_SHADOW})do
    local kind=slot==ItemBodyLocation.MAKE_UP_FULL_FACE and'Base.MakeUp_CamoFullFace1'
        or slot==ItemBodyLocation.MAKE_UP_EYES and'Base.MakeUp_Crow'or'Base.MakeUp_EyesShadowWhite'
    local item=value.worn(kind);allowed,footprint=inspectMove(value,body)
    assert(allowed and footprint.items[item:getID()],'another worn cosmetic slot was omitted')
end

for _,nested in ipairs({false,true})do
    value,queue,body,original=movable()
    local outer,inner,source=carried(value,nested)
    beforeFactories,beforeVisuals=value.factories(),value.visuals()
    writes,inventoryWrites=value.player.writes,value.inventory.writes
    allowed,footprint=inspectMove(value,body)
    assert(allowed and footprint.items[value.kit:getID()]and footprint.items[outer:getID()]
        and footprint.containerOwners[outer:getID()]and footprint.itemTypes[outer:getFullType()]
        and footprint.containers[source]and footprint.containers[value.inventory]
        and(not inner or footprint.items[inner:getID()]and footprint.containerOwners[inner:getID()]
            and footprint.containers[outer:getInventory()]),'carried kit lost exact ancestor/container resources')
    assert(value.factories()==beforeFactories and value.visuals()==beforeVisuals and value.player.writes==writes
        and value.inventory.writes==inventoryWrites and value.kit.uses==5 and value.kit:getContainer()==source
        and source.values[#source.values]==value.kit and #value.packets==0,
        'carried move inspection allocated or changed source, inventory, wear, cost or packets')
    local head,tail=queue.queue[1],queue.queue[3]
    assert(value.policy.evaluateMove(queue,body,tail,true).allowed,'carried makeup could not move later across independent reader')
    queue.queue[2],queue.queue[3]=tail,body
    assert(value.policy.evaluateMove(queue,body,tail,false).allowed,'carried makeup could not move earlier across independent reader')
    head.action={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
    local promoted=value.policy.evaluateMove(queue,body,head,false)
    assert(promoted.allowed and promoted.preempt,'carried makeup could not be promoted before active independent reader')
    body.action={}
    assert(not value.policy.evaluateMove(queue,body,tail,false).allowed,'allocated carried makeup became movable')
end

for _,kind in ipairs({'crate','shelf','bag'})do
    value,queue,body,original=movable()
    local source,object,owner,door=value.worldSource(kind)
    beforeFactories,beforeVisuals=value.factories(),value.visuals()
    writes,inventoryWrites=value.player.writes,value.inventory.writes
    allowed,footprint=inspectMove(value,body)
    assert(allowed and footprint.positions[value.player]and footprint.targets[object]
        and footprint.targets[object:getSquare()]and footprint.targets[value.player:getCurrentSquare()]
        and footprint.targets[door]and footprint.targets[door:getSquare()]and footprint.containers[source]
        and(not owner or footprint.items[owner:getID()]and footprint.containerOwners[owner:getID()]),
        kind..' omitted world position, anchored source, nearby topology or bag owner resources')
    assert(value.factories()==beforeFactories and value.visuals()==beforeVisuals and value.player.writes==writes
        and value.inventory.writes==inventoryWrites and value.kit:getContainer()==source and value.kit.uses==5 and #value.packets==0,
        kind..' inspection changed output/visual/inventory/source/cost/network state')
    local head,tail=queue.queue[1],queue.queue[3]
    assert(value.policy.evaluateMove(queue,body,tail,true).allowed,kind..' makeup could not cross independent reader later')
    queue.queue[2],queue.queue[3]=tail,body
    assert(value.policy.evaluateMove(queue,body,tail,false).allowed,kind..' makeup could not cross independent reader earlier')
    head.action={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
    local decision=value.policy.evaluateMove(queue,body,head,false)
    assert(decision.allowed and decision.preempt,kind..' makeup could not promote before active independent reader')
end

-- Native/CleanUI refresh populates its per-player synthetic floor with the
-- exact world bag. AddItem changes bag.container without clearing worldItem.
local nativePage=read(NativeActionRoot..'/client/ISUI/ISInventoryPage.lua')
assert(nativePage:find('ItemContainer.new("floor", nil, nil)',1,true)
    and nativePage:find('floorContainer:AddItem(o:getItem())',1,true),'native floor view producer changed')
local function floorAlias(s,owner)
    local placeholder,floor=s.bag();s.inventory.values[#s.inventory.values]=nil
    floor.owner=nil;floor.kind='floor';floor.values={owner};owner.container=floor
    ISInventoryPage.floorContainer={[s.player:getPlayerNum()+1]=floor}
    ISInventoryPage.GetFloorContainer=function()error('inspection allocated/read floor via UI callback')end
    return floor
end
local function finalMove(topology)
    local s,q,a,old=movable({client=true,kitKind='Base.MakeupEyeshadow',kitMakeupType='Eyes',kitUses=1,
        outputKind='Base.MakeUp_Crow',oldKind='Base.MakeUp_RedStripes1'})
    local source,outer=s.inventory,nil
    if topology=='worn-bag'or topology=='nested-bag'then
        outer,_,source=carried(s,topology=='nested-bag')
    elseif topology=='crate'or topology=='world-bag'or topology=='nested-world-crate'or topology=='nested-world-bag'then
        local object
        source,object,outer=s.worldSource(topology:find('bag',1,true)and'bag'or'crate')
        if outer then floorAlias(s,outer)end
        if topology:find('nested',1,true)then
            local inner,contents=s.bag(source)
            for i,item in ipairs(source.values)do if item==s.kit then table.remove(source.values,i);break end end
            contents.values[1]=s.kit;s.kit.container=contents;source=contents
        end
    end
    return s,q,a,old,source,outer
end
for _,topology in ipairs({'root','worn-bag','nested-bag','crate','world-bag'})do
    value,queue,body,original=finalMove(topology)
    beforeFactories,beforeVisuals=value.factories(),value.visuals()
    writes,inventoryWrites=value.player.writes,value.inventory.writes
    allowed,footprint=inspectMove(value,body)
    assert(allowed and footprint.knownInputs and not footprint.unknownOutputs and footprint.items[value.kit:getID()]
        and not footprint.capacityNonIncreasing and value.kit:getUses()==1 and value.kit:getCurrentUses()==1,
        topology..' exact native final-use input was rejected or incorrectly credited capacity release')
    assert(value.factories()==beforeFactories and value.visuals()==beforeVisuals and value.player.writes==writes
        and value.inventory.writes==inventoryWrites and value.kit.uses==1 and #value.packets==0,
        topology..' final-use inspection paid, allocated or changed state')
    local head,tail=queue.queue[1],queue.queue[3]
    assert(value.policy.evaluateMove(queue,body,tail,true).allowed,topology..' final-use body cannot move later')
    queue.queue[2],queue.queue[3]=tail,body
    assert(value.policy.evaluateMove(queue,body,tail,false).allowed,topology..' final-use body cannot move earlier')
    head.action={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
    local decision=value.policy.evaluateMove(queue,body,head,false)
    assert(decision.allowed and decision.preempt,topology..' final-use body cannot promote before active reader')
    local transfer=value.f.action(ISInventoryTransferAction,{item=value.f.item('Base.Bandage'),
        srcContainer=value.inventory,destContainer=value.inventory})
    queue.queue[2],queue.queue[3]=body,transfer
    decision=value.policy.evaluateMove(queue,body,transfer,true)
    assert(not decision.allowed and decision.reason=='container_capacity',topology..' spent final-use weight release on a transfer')
    queue.queue[3]=tail
    body.action={}
    assert(not value.policy.evaluateMove(queue,body,tail,false).allowed,topology..' allocated final-use body became movable')
end
for _,topology in ipairs({'nested-world-crate','nested-world-bag'})do
    value,queue,body=finalMove(topology)
    allowed,footprint=inspectMove(value,body)
    assert(not allowed and footprint.cancelWaiting and footprint.cancelOperation and footprint.items[value.kit:getID()]==nil,
        topology..' admitted a final-use source without native removal sender routing')
    assert(value.policy.evaluateCancel(queue,body).allowed,topology..' blocked zero-effect pending deletion')
end
local function holdKit(s,hand)
    local other=s.f.item('Base.Pencil');other.container=s.inventory;other.equipParent=hand~='both'and s.player or nil
    function other:getContainer()return self.container end
    function other:getWorldItem()return self.world end
    function other:getEquipParent()return self.equipParent end
    s.inventory.values[#s.inventory.values+1]=other
    s.player.primary=hand=='secondary'and other or s.kit
    s.player.secondary=hand=='primary'and other or s.kit
    s.kit.equipParent=s.player
    return other
end
-- Native root depletion clears only matching hand references. Inspection must
-- preserve both exact hands and every existing resource/capacity dependency.
for _,uses in ipairs({1,5})do for _,hand in ipairs({'primary','secondary','both'})do
    value,queue,body=finalMove('root');value.kit.uses=uses
    local other=holdKit(value,hand)
    local primary,secondary=value.player.primary,value.player.secondary
    beforeFactories,beforeVisuals=value.factories(),value.visuals()
    writes,inventoryWrites=value.player.writes,value.inventory.writes
    allowed,footprint=inspectMove(value,body)
    assert(allowed and footprint.knownInputs and not footprint.unknownOutputs and footprint.items[value.kit:getID()]
        and footprint.hands==value.player and footprint.equipment==value.player and not footprint.capacityNonIncreasing,
        hand..' held root kit '..uses..' lost complete actor/input ordering or spent capacity release')
    assert(value.player.primary==primary and value.player.secondary==secondary and value.kit.equipParent==value.player
        and value.kit:getContainer()==value.inventory and value.kit.uses==uses and value.inventory:contains(other)
        and value.factories()==beforeFactories and value.visuals()==beforeVisuals and value.player.writes==writes
        and value.inventory.writes==inventoryWrites and #value.packets==0,
        hand..' held kit inspection mutated a hand, paid a cost or changed physical inventory')
    local head,tail=queue.queue[1],queue.queue[3]
    assert(value.policy.evaluateMove(queue,body,tail,true).allowed,'held root makeup cannot move later')
    queue.queue[2],queue.queue[3]=tail,body
    assert(value.policy.evaluateMove(queue,body,tail,false).allowed,'held root makeup cannot move earlier')
    head.action={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
    local decision=value.policy.evaluateMove(queue,body,head,false)
    assert(decision.allowed and decision.preempt,'held root makeup cannot promote before active reader')
    local transfer=value.f.action(ISInventoryTransferAction,{item=other,srcContainer=value.inventory,destContainer=value.inventory})
    queue.queue[2],queue.queue[3]=body,transfer
    decision=value.policy.evaluateMove(queue,body,transfer,true)
    assert(not decision.allowed and decision.reason=='container_capacity','held makeup spent removal capacity on transfer')
    queue.queue[3]=tail
    assert(value.policy.evaluateCancel(queue,body).allowed,'held root makeup lost unpaid cancellation')
    body.action={}
    assert(not value.policy.evaluateMove(queue,body,tail,false).allowed,'allocated held makeup became movable')
end end
-- EquipPacket carries both hands and resolves their IDs directly in actor
-- root. Even an untouched other hand must survive that exact native lookup.
for _,uses in ipairs({1,5})do for _,hand in ipairs({'primary','secondary'})do
for _,change in ipairs({'nested','world','world-alias','missing-root','duplicate-id','root-proxy','stale-equip-parent'})do
    value,queue,body=finalMove('root');value.kit.uses=uses
    local other=holdKit(value,hand)
    local function removeOther()
        for i,item in ipairs(value.inventory.values)do if item==other then table.remove(value.inventory.values,i);return end end
    end
    if change=='nested'then
        local bag,contents=value.bag();removeOther();other.container=contents;contents.values[#contents.values+1]=other
    elseif change=='world'then removeOther();other.container=nil;other.world={}
    elseif change=='world-alias'then other.world={}
    elseif change=='missing-root'then removeOther()
    elseif change=='duplicate-id'or change=='root-proxy'then
        if change=='root-proxy'then removeOther()end
        local duplicate=value.f.item('Base.Pencil');duplicate.id=other:getID()
        value.inventory.values[#value.inventory.values+1]=duplicate
    elseif change=='stale-equip-parent'then other.equipParent={}end
    local primary,secondary=value.player.primary,value.player.secondary
    allowed,footprint=inspectMove(value,body)
    assert(not allowed and footprint.knownInputs==false and footprint.unknownOutputs and footprint.cancelWaiting and footprint.cancelOperation,
        change..' other hand admitted held '..hand..' kit '..uses)
    for _ in pairs(footprint.items)do error(change..' other hand leaked staged held-kit resources')end
    assert(value.kit.uses==uses and value.player.primary==primary and value.player.secondary==secondary and #value.packets==0,
        change..' other-hand rejection consumed or changed equipment')
    assert(value.policy.evaluateCancel(queue,body).allowed,change..' other hand disabled unpaid waiting cancellation')
end end end
for _,uses in ipairs({1,5})do
for _,change in ipairs({'missing-equip-parent','foreign-equip-parent','worn','attached-slot','attached-model','attached-type',
    'activated','crafting','auto-equipped','auto-unequipped','components','replacement','script-components','script-create',
    'root-callback','root-category','duplicate','foreign-class','held-helper','depletion-helper',
    'worn-bag','nested-bag','crate','world-bag'})do
    local topology=(change=='worn-bag'or change=='nested-bag'or change=='crate'or change=='world-bag')and change or'root'
    value,queue,body=finalMove(topology);value.kit.uses=uses
    holdKit(value,'primary')
    local script=value.kit:getScriptItem()
    if change=='missing-equip-parent'then value.kit.equipParent=nil
    elseif change=='foreign-equip-parent'then value.kit.equipParent={}
    elseif change=='worn'then value.player.worn[ItemBodyLocation.MAKE_UP_EYES]=value.kit
    elseif change=='attached-slot'then value.kit.attachedSlot=0
    elseif change=='attached-model'then value.kit.attachedToModel='Back'
    elseif change=='attached-type'then value.kit.attachedSlotType='BeltLeft'
    elseif change=='activated'then value.kit.activated=true
    elseif change=='crafting'then value.kit.craftingConsumed=true
    elseif change=='auto-equipped'then value.kit.useWhileEquipped=true
    elseif change=='auto-unequipped'then value.kit.useWhileUnequipped=true
    elseif change=='components'then value.kit.components=true
    elseif change=='replacement'then value.kit.replacement='Base.Unknown'
    elseif change=='script-components'then script.components=true
    elseif change=='script-create'then script.luaCreate='Unknown.Callback'
    elseif change=='root-callback'then value.inventory.getAcceptItemFunction=function()return'Unknown.Callback'end
    elseif change=='root-category'then value.inventory.getOnlyAcceptCategory=function()return'Appearance'end
    elseif change=='duplicate'then value.inventory.values[#value.inventory.values+1]=value.kit
    elseif change=='foreign-class'then value.kit.class='ForeignKit'
    elseif change=='held-helper'then value.supplyUse.supportsHeld=function()error('foreign held helper executed')end
    elseif change=='depletion-helper'then value.supplyUse.supportsDepletion=function()error('foreign depletion helper executed')end end
    allowed,footprint=inspectMove(value,body)
    assert(not allowed and footprint.knownInputs==false and footprint.unknownOutputs and footprint.cancelWaiting and footprint.cancelOperation,
        change..' admitted held kit '..uses..' or changed its cancellation contract')
    for _ in pairs(footprint.items)do error(change..' leaked staged held-kit inputs')end
    assert(value.kit.uses==uses and value.player.primary==value.kit and #value.packets==0,
        change..' denied inspection consumed or unequipped the held kit')
    assert(value.policy.evaluateCancel(queue,body).allowed,change..' blocked unpaid held-kit cancellation')
end end
for _,change in ipairs({'zero','negative','fractional','keep-zero','live-replacement','script-replacement','script-use-replacement',
    'lua-create','config','config-key','components','script-components','script-type','script-owner','script-obsolete',
    'attached-slot','attached-model','attached-type','equip-parent','held','equipped','activated','crafting','final-helper'})do
    value,queue,body=finalMove('root')
    assert(inspectMove(value,body))
    local script=value.kit:getScriptItem()
    if change=='zero'then value.kit.uses=0
    elseif change=='negative'then value.kit.uses=-1
    elseif change=='fractional'then value.kit.uses=0.5
    elseif change=='keep-zero'then script.disappear=false
    elseif change=='live-replacement'then value.kit.replacement='Base.Unknown'
    elseif change=='script-replacement'then script.replaceOnDeplete='Base.Unknown'
    elseif change=='script-use-replacement'then script.replaceOnUse='Base.Unknown'
    elseif change=='lua-create'then script.luaCreate='Unknown.Callback'
    elseif change=='config'then script.config={}
    elseif change=='config-key'then script.configKey='Unknown.Config'
    elseif change=='components'then value.kit.components=true
    elseif change=='script-components'then script.components=true
    elseif change=='script-type'then script.getItemType=function()return ItemType.CLOTHING end
    elseif change=='script-owner'then value.kit.script={}
    elseif change=='script-obsolete'then script.obsolete=true
    elseif change=='attached-slot'then value.kit.attachedSlot=0
    elseif change=='attached-model'then value.kit.attachedToModel='Back'
    elseif change=='attached-type'then value.kit.attachedSlotType='BeltLeft'
    elseif change=='equip-parent'then value.kit.equipParent=value.player
    elseif change=='held'then value.player.primary=value.kit
    elseif change=='equipped'then value.player.worn.back=value.kit
    elseif change=='activated'then value.kit.activated=true
    elseif change=='crafting'then value.kit.craftingConsumed=true
    elseif change=='final-helper'then value.supplyUse.supportsDepletion=function()error('foreign final-use helper executed')end end
    allowed,footprint=inspectMove(value,body)
    assert(not allowed and footprint.knownInputs==false and footprint.cancelWaiting and footprint.cancelOperation,
        change..' admitted an unproven final-use input or changed pending cancellation')
    assert(value.policy.evaluateCancel(queue,body).allowed,change..' blocked owned unpaid waiting cancellation')
end
value,queue,body=movable()
local floorSource,floorObject,floorOwner=value.worldSource('bag')
local floor=floorAlias(value,floorOwner)
assert(value.kit:getOutermostContainer()==floorSource and value.access.locate(value.kit,value.player).x==floorObject:getSquare():getX(),
    'native item outermost lookup followed synthetic floor instead of physical ground bag')
beforeFactories,beforeVisuals=value.factories(),value.visuals()
allowed,footprint=inspectMove(value,body)
assert(allowed and not footprint.containers[floor]and not footprint.targets[floor]
    and footprint.containers[floorSource]and footprint.items[floorOwner:getID()]
    and value.factories()==beforeFactories and value.visuals()==beforeVisuals
    and floorOwner:getContainer()==floor and floor.values[1]==floorOwner and value.kit.uses==5 and #value.packets==0,
    'exact native floor-cache view rejected physical ground bag or inspection modified/staged its synthetic cache')
assert(value.policy.evaluateMove(queue,body,queue.queue[3],true).allowed,'native floor-view bag cannot move later across reader')

for _,change in ipairs({'missing-cache','wrong-slot','alien-floor','cache-metatable','inherited-cache','page-change',
    'stale-membership','duplicate-ref','duplicate-id','foreign-class','not-floor','parent','holder','vehicle','source-grid',
    'accept','category','world-link','world-list','location'})do
    value,queue,body=movable()
    local source,object,owner=value.worldSource('bag')
    floor=floorAlias(value,owner)
    assert(inspectMove(value,body))
    if change=='missing-cache'then ISInventoryPage.floorContainer=nil
    elseif change=='wrong-slot'then ISInventoryPage.floorContainer={[value.player:getPlayerNum()+2]=floor}
    elseif change=='alien-floor'then
        local placeholder,alien=value.bag();value.inventory.values[#value.inventory.values]=nil
        alien.owner=nil;alien.kind='floor';alien.values={owner};owner.container=alien
    elseif change=='cache-metatable'then setmetatable(ISInventoryPage.floorContainer,{__index=function()error('foreign cache getter executed')end})
    elseif change=='inherited-cache'then
        local cached=ISInventoryPage.floorContainer;ISInventoryPage.floorContainer=nil
        setmetatable(ISInventoryPage,{__index={floorContainer=cached}})
    elseif change=='page-change'then ISInventoryPage={floorContainer=ISInventoryPage.floorContainer}
    elseif change=='stale-membership'then floor.values={}
    elseif change=='duplicate-ref'then floor.values[2]=owner
    elseif change=='duplicate-id'then local duplicate=value.f.item('Base.Pencil');duplicate.id=owner:getID();floor.values[2]=duplicate
    elseif change=='foreign-class'then floor.class='ForeignFloor'
    elseif change=='not-floor'then floor.kind='crate'
    elseif change=='parent'then floor.parent={}
    elseif change=='holder'then floor.owner=owner
    elseif change=='vehicle'then floor.part={}
    elseif change=='source-grid'then floor.square=object:getSquare()
    elseif change=='accept'then floor.accept='Unknown.Callback'
    elseif change=='category'then floor.category='Appearance'
    elseif change=='world-link'then owner.world=nil
    elseif change=='world-list'then object:getSquare().worlds={}
    elseif change=='location'then value.player.square=value.square(8,10,0)end
    allowed,footprint=inspectMove(value,body)
    assert(not allowed and footprint.pendingMoveBlocker and footprint.containers==nil and footprint.positions==nil
        and footprint.cancelWaiting and footprint.cancelOperation and value.kit.uses==5 and #value.packets==0,
        change..' admitted an unproven floor-cache alias or leaked effects/staged resources')
end

for _,kind in ipairs({'crate','bag'})do
    value,queue,body=movable()
    local source,object=value.worldSource(kind)
    value.player.square=object:getSquare();value.player.square.blocked=true
    assert(inspectMove(value,body),kind..' same-square supply called a non-applicable edge blockage probe')
    value.player.square.blocked=false
    local inner,contents=value.bag(source)
    for i,item in ipairs(source.values)do if item==value.kit then table.remove(source.values,i);break end end
    contents.values[#contents.values+1]=value.kit;value.kit.container=contents
    allowed,footprint=inspectMove(value,body)
    assert(allowed and footprint.items[inner:getID()]and footprint.containerOwners[inner:getID()]
        and footprint.containers[source]and footprint.containers[contents],kind..' nested world supply lost exact bag ancestry')
    assert(value.policy.evaluateMove(queue,body,queue.queue[3],true).allowed,kind..' nested world supply cannot cross independent reader')
    local kinds={'ancestor-lost','ancestor-callback','ancestor-components','ancestor-cycle'}
    for _,change in ipairs(kinds)do
        value,queue,body=movable();source,object=value.worldSource(kind)
        inner,contents=value.bag(source)
        for i,item in ipairs(source.values)do if item==value.kit then table.remove(source.values,i);break end end
        contents.values[#contents.values+1]=value.kit;value.kit.container=contents
        assert(inspectMove(value,body))
        if change=='ancestor-lost'then source.values={}
        elseif change=='ancestor-callback'then contents.accept='Unknown.Callback'
        elseif change=='ancestor-components'then inner.components=true
        else inner.container=contents;contents.values[#contents.values+1]=inner end
        allowed,footprint=inspectMove(value,body)
        assert(not allowed and footprint.positions==nil and footprint.containers==nil,
            kind..' '..change..' admitted invalid world ancestry or leaked partial facts')
    end
end

for _,where in ipairs({'prefix','crossed'})do for _,kind in ipairs({'crate','bag'})do
    for _,change in ipairs({'approach','door-target','origin-target','source-target','native-door','native-window','future-builder'})do
        value,queue,body=movable()
        local source,object,owner,door=value.worldSource(kind)
        local other,c
        if change=='approach'then other=ISPathFindAction:pathToLocationF(value.player,20,20,0)
        elseif change=='native-door'then other=ISOpenCloseDoor:new(value.player,door)
        elseif change=='native-window'then other=ISOpenCloseWindow:new(value.player,door)
        else
            other=value.f.action(ISBaseTimedAction,{Type='MakeupWorldProbe'})
            c={items={},itemTypes={},targets={}}
            if change=='door-target'then c.targets[door]=true
            elseif change=='origin-target'then c.targets[value.player:getCurrentSquare()]=true
            elseif change=='source-target'then c.targets[object]=true
            else c.knownInputs=false;c.unknownOutputs=true end
            PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('test.makeup-world-probe',{
                types={'MakeupWorldProbe'},matches=function(a)return a==other end,inspect=function()return c end})
        end
        other.toolkitQueueOperation={}
        if where=='prefix'then
            queue.queue[1],queue.current=other,other
            assert(not inspectMove(value,body),kind..' earlier '..change..' preserved world access proof')
        else
            queue.queue[3]=other
            assert(not value.policy.evaluateMove(queue,body,other,true).allowed,kind..' crossed '..change..' world dependency')
        end
    end
end end

for _,kind in ipairs({'crate','bag'})do for _,change in ipairs({'blocked','reverse-blocked','diagonal','far','z',
    'stale-square','missing-object','duplicate-object','moved-object','safehouse','safehouse-binding','access-binding',
    'adapter-binding','cell-binding','vehicle-binding','server-binding','source-vehicle','source-gone','source-lock',
    'source-callback','source-category','trade','kit-lost','world-item-backref','world-bag-backref','world-index',
    'world-list','crate-backref','crate-components','world-components'})do
    value,queue,body=movable()
    local source,object,owner,door=value.worldSource(kind)
    assert(inspectMove(value,body))
    local s=object:getSquare()
    if change=='blocked'then value.player.square.blocked=true
    elseif change=='reverse-blocked'then s.blocked=true
    elseif change=='diagonal'then value.player.square=value.square(10,9,0)
    elseif change=='far'then value.player.square=value.square(9,10,0)
    elseif change=='z'then value.player.square=value.square(10,10,1)
    elseif change=='stale-square'then value.squares[s:getX()..','..s:getY()..','..s:getZ()]=nil
    elseif change=='missing-object'then s.objects={}
    elseif change=='duplicate-object'then s.objects[#s.objects+1]=object
    elseif change=='moved-object'then object.square=value.square(12,10,0)
    elseif change=='safehouse'then value.options.lootDenied=true
    elseif change=='safehouse-binding'then SafeHouse.isSafehouseAllowLoot=function()error('foreign safehouse callback executed')end
    elseif change=='access-binding'then value.access.admit=function()error('foreign item admission executed')end
    elseif change=='adapter-binding'then PZSurvivorToolkit.ActionQueueItemEditAdapters.worldContainer=function()error('foreign world anchor executed')end
    elseif change=='cell-binding'then getCell=function()error('foreign cell getter executed')end
    elseif change=='vehicle-binding'then getVehicleById=function()error('foreign vehicle getter executed')end
    elseif change=='server-binding'then isServer=function()error('foreign server getter executed')end
    elseif change=='source-vehicle'then source.part={}
    elseif change=='source-gone'then source.gone=true
    elseif change=='source-lock'then source.locked=true
    elseif change=='source-callback'then source.accept='Unknown.Callback'
    elseif change=='source-category'then source.category='Appearance'
    elseif change=='trade'then source.kind='TradeUI'
    elseif change=='kit-lost'then source.values={}
    elseif change=='world-item-backref'then if owner then object.item=value.kit else source.parent=nil end
    elseif change=='world-bag-backref'then if owner then owner.world={}else source.square=value.square(12,10,0)end
    elseif change=='world-index'then if owner then object.getWorldObjectIndex=function()return -1 end else source.owner={}end
    elseif change=='world-list'then if owner then s.worlds={}else object.containers={}end
    elseif change=='crate-backref'then if owner then owner.contents={}else object.containers[1]={}end
    elseif change=='crate-components'then if owner then owner.components=true else object.components=true end end
    if change=='world-components'then object.components=true end
    allowed,footprint=inspectMove(value,body)
    assert(not allowed and footprint.pendingMoveBlocker and footprint.cancelWaiting and footprint.cancelOperation
        and footprint.knownInputs==false and footprint.unknownOutputs==true and footprint.positions==nil
        and footprint.containerOwners==nil and footprint.containers==nil,
        kind..' '..change..' admitted stale/inaccessible world source or leaked partial spatial/ancestry maps')
    assert(not footprint.targets[object]and not footprint.targets[door],kind..' '..change..' leaked staged topology targets')
    for _ in pairs(footprint.items)do error(kind..' '..change..' leaked staged item IDs')end
    assert(value.kit.uses==5 and #value.packets==0,kind..' '..change..' changed payment/network during refusal')
    if change=='safehouse'or change=='source-lock'or change=='missing-object'then
        assert(value.policy.evaluateCancel(queue,body).allowed,kind..' '..change..' blocked owned zero-effect waiting deletion')
    end
end end

for _,change in ipairs({'kit-lost','outer-lost','outer-duplicate','outer-duplicate-id','inner-duplicate','cycle',
    'owner-backref','inventory-backref','parent','foreign-root','world','ground','floor','proximity','corpse',
    'source-callback','ancestor-callback','category','bag-components','bag-script-components','bag-lua-create',
    'bag-config','bag-config-key','bag-class','bag-held','helper-binding','deep-chain'})do
    value,queue,body,original=movable()
    local outer,inner,source=carried(value,true)
    assert(inspectMove(value,body))
    if change=='kit-lost'then source.values={}
    elseif change=='outer-lost'then
        for i,item in ipairs(value.inventory.values)do if item==outer then table.remove(value.inventory.values,i);break end end
    elseif change=='outer-duplicate'then value.inventory.values[#value.inventory.values+1]=outer
    elseif change=='outer-duplicate-id'then
        local duplicate=value.f.item('Base.Pencil');duplicate.id=outer:getID();value.inventory.values[#value.inventory.values+1]=duplicate
    elseif change=='inner-duplicate'then outer:getInventory().values[#outer:getInventory().values+1]=inner
    elseif change=='cycle'then outer.container=source;source.values[#source.values+1]=outer
    elseif change=='owner-backref'then source.owner=outer
    elseif change=='inventory-backref'then inner.contents={}
    elseif change=='parent'then source.parent={class='IsoObject'}
    elseif change=='foreign-root'then outer.container={class='ItemContainer',getAcceptItemFunction=function()end,
        getOnlyAcceptCategory=function()end,getType=function()return'inventorymale'end,getParent=function()return{}end,
        getItems=function()return list({outer})end,getItemById=function()return outer end}
    elseif change=='world'then outer.world={}
    elseif change=='ground'then outer.container=nil;outer.world={}
    elseif change=='floor'then source.kind='floor'
    elseif change=='proximity'then source.kind='proximityInv'
    elseif change=='corpse'then source.kind='twistInv_corpses'
    elseif change=='source-callback'then source.accept='Unknown.Callback'
    elseif change=='ancestor-callback'then outer:getInventory().accept='Unknown.Callback'
    elseif change=='category'then source.category='Appearance'
    elseif change=='bag-components'then outer.components=true
    elseif change=='bag-script-components'then outer:getScriptItem().components=true
    elseif change=='bag-lua-create'then outer:getScriptItem().luaCreate='Unknown.Callback'
    elseif change=='bag-config'then outer:getScriptItem().config={}
    elseif change=='bag-config-key'then outer:getScriptItem().configKey='Unknown.Config'
    elseif change=='bag-class'then outer.class='ForeignContainer'
    elseif change=='bag-held'then value.player.primary=outer
    elseif change=='helper-binding'then value.policy.addContainerResources=function()error('foreign container helper executed')end
    elseif change=='deep-chain'then
        for i=1,33 do local bag,contents=value.bag(source);source=contents end
        source.values[#source.values+1]=value.kit;value.kit.container=source
    end
    allowed,footprint=inspectMove(value,body)
    assert(not allowed and footprint.knownInputs==false and footprint.unknownOutputs and footprint.cancelWaiting
        and footprint.cancelOperation and footprint.containers==nil and footprint.containerOwners==nil,
        change..' admitted malformed carried ancestry or leaked staged resources/cancellation state')
    for _ in pairs(footprint.items)do error(change..' leaked staged ancestor IDs')end
    assert(value.kit.uses==5 and #value.packets==0,'denied carried inspection changed cost/packets')
    assert(value.policy.evaluateCancel(queue,body).allowed,change..' blocked zero-effect owned waiting deletion')
end

for _,count in ipairs({32,33})do
    value,queue,body=movable()
    local source=value.inventory
    for i=1,count-1 do local bag,contents=value.bag(source);source=contents end
    for i,item in ipairs(value.inventory.values)do if item==value.kit then table.remove(value.inventory.values,i);break end end
    source.values[#source.values+1]=value.kit;value.kit.container=source
    assert(inspectMove(value,body)==(count==32),'carried depth bound must include root: '..count)
end

-- Earlier effects may invalidate the current bag snapshot without being the
-- action being crossed. Later ancestor consumers remain ordinary dependencies.
for _,where in ipairs({'prefix','crossed'})do
    local changes={'ancestor-use','ancestor-type','ancestor-container','ancestor-transfer','capacity'}
    if where=='prefix'then changes[#changes+1]='exact-container'end
    for _,change in ipairs(changes)do
    value,queue,body=movable()
    local outer,inner,source=carried(value,true)
    local other=value.f.action(ISBaseTimedAction,{Type='MakeupAncestorProbe'})
    local c={items={},itemTypes={},targets={},containerOwners={}}
    if change=='ancestor-use'then c.items[outer:getID()]=true
    elseif change=='ancestor-type'then c.dynamicInputs={[outer:getFullType()]=true}
    elseif change=='ancestor-container'then c.containerOwners[inner:getID()]=true
    elseif change=='exact-container'then c.containers={[source]=true}
    elseif change=='ancestor-transfer'then
        other=value.f.action(ISInventoryTransferAction,{item=outer,srcContainer=value.inventory,destContainer=value.inventory})
    else
        other=value.f.action(ISInventoryTransferAction,{item=value.f.item('Base.Pencil'),srcContainer=source,destContainer=value.inventory})
    end
    if change~='capacity'and change~='ancestor-transfer'then
        PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('test.makeup-ancestor',{
            types={'MakeupAncestorProbe'},matches=function(a)return a==other end,inspect=function()return c end})
    end
    if where=='prefix'then
        queue.queue[1],queue.current=other,other
        assert(not inspectMove(value,body),'earlier '..change..' preserved carried snapshot proof')
    else
        queue.queue[3]=other
        assert(not value.policy.evaluateMove(queue,body,other,true).allowed,'makeup crossed '..change..' affecting carried ancestry')
    end
end end

for _,change in ipairs({'zero-use','replacement','weight-empty','nan-weight','held-kit','secondary-kit','kit-components','kit-class',
    'kit-world','kit-nested','kit-duplicate','kit-id','output-components','output-type','obsolete','output-replacement',
    'output-weight','lua-create','config-key','config','old-held','old-components','old-script-components','old-class',
    'old-location','old-duplicate','other-slot-held','root-callback','root-category','definitions','item-type-binding',
    'locations-binding','global-binding','policy-binding'})do
    value,queue,body,original=movable()
    -- Bind the policy once before replacing an entry point.
    assert(inspectMove(value,body))
    if change=='zero-use'then value.kit.uses=0
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
    assert(value.kit.uses==(change=='zero-use'and 0 or 5)and #value.packets==0,'denied inspection consumed or sent state')
    if change=='zero-use'or change=='replacement'or change=='held-kit'or change=='output-components'or change=='old-held'then
        assert(value.policy.evaluateCancel(queue,body).allowed,change..' disabled owned zero-effect waiting deletion')
    end
end

value,queue,body=movable();value.kit.uses=0
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
