-- Offline engine boundary for the source-backed composition test. All Toolkit
-- policy, receipt, observer and begin/stop implementations are loaded unchanged.
return function(client,options)
    options=options or {}
    local p4Enabled=options.p4~=false
    local p4Selected=options.p4Selected
    if p4Selected==nil then p4Selected=p4Enabled end
    -- Native Kahlua globals are a plain table. A fallback __index would make
    -- the real SourceProof binding watcher reject this modeled environment.
    local env={}
    for name,value in pairs(_G)do env[name]=value end
    env._G=env
    local function text(path)
        if NativeReadText then return NativeReadText(path):gsub('\r','') end
        local file=assert(io.open(path),'missing source: '..path)
        local source=file:read('*a');file:close();return source:gsub('\r','')
    end
    local function exists(path)
        if NativeFileExists then return NativeFileExists(path) end
        local file=io.open(path);if file then file:close();return true end;return false
    end
    local function execute(source,path)
        local chunk=assert(loadstring(source:gsub('(%d+%.%d+)f','%1'),'@'..path))
        setfenv(chunk,env);return chunk()
    end
    local function reader(source)
        local position=1
        return {close=function()end,readLine=function()
            if position>#source then return end
            local boundary=source:find('\n',position,true)or #source+1
            local value=source:sub(position,boundary-1);position=boundary+1;return value
        end}
    end
    local roots=ToolkitLuaRoots or {ToolkitLuaRoot or ProjectRoot..'/PZSurvivorToolkit/42/media/lua'}
    local function toolkitPath(module)
        for index=#roots,1,-1 do
            for _,branch in ipairs({'client','shared'})do
                local path=roots[index]..'/'..branch..'/'..module..'.lua'
                if exists(path)then return path end
            end
        end
    end
    local loaded,loading={},{}
    local unrelated={ActionQueueCraft=true,ActionQueueGenerators=true,ActionQueueFire=true,ActionQueueWorld=true,
        ActionQueueHealth=true,ActionQueueFitness=true,ActionQueueAnimalStops=true,ActionQueueReading=true,
        ActionQueueMedia=true,ActionQueueRecovery=true}
    local p4={['P4TidyUpMeister']={P4TidySource,'client/P4TidyUpMeister.lua'},
        ['TimedActions/P4RestoreAction']={P4RestoreSource,'shared/TimedActions/P4RestoreAction.lua'},
        ['TimedActions/P4RestoreFloorAction']={P4RestoreFloorSource,'shared/TimedActions/P4RestoreFloorAction.lua'}}
    for _,entry in pairs(p4)do
        if not entry[1]and NativeP4TidySource then entry[1]=text(NativeP4TidySource..'/media/lua/'..entry[2])end
    end
    env.getGameFilesInput=function(path)
        if options.cleanUIContextSource and path=='media/lua/client/ISUI/ISInventoryPaneContextMenu.lua'then
            return reader(options.cleanUIContextSource)
        end
        return reader(text(NativeActionRoot..'/'..path:gsub('^media/lua/','')))
    end
    env.getModFileReader=function(id,path)
        if id=='P4TidyUpMeister'then
            for _,entry in pairs(p4)do if path=='media/lua/'..entry[2]then return reader(assert(entry[1]))end end
        elseif id=='PZSurvivorToolkit'then
            local module=path:match('^media/lua/[^/]+/(.*)%.lua$')
            local actual=module and toolkitPath(module)
            if actual then return reader(text(actual))end
        elseif id=='CleanUI'and options.cleanUISelectorSource and path=='media/lua/client/ISUI/ISInventoryPane.lua'then
            return reader(options.cleanUISelectorSource)
        elseif id=='CleanUI'and options.cleanUIContextSource and path=='media/lua/client/ISUI/ISInventoryPaneContextMenu.lua'then
            return reader(options.cleanUIContextSource)
        end
    end
    env.require=function(module)
        if loaded[module]~=nil then return loaded[module]end
        if loading[module]then return end
        -- Optional integrations do not participate in the native borrowing path.
        if unrelated[module:match('^PZSurvivorToolkit/(.*)$')]then return end
        local path=module:match('^PZSurvivorToolkit/')and toolkitPath(module)
        local selected=p4[module]
        if selected and not p4Enabled then error('fixture module unavailable: '..module,0)end
        if not path and not selected and (module:match('^TimedActions/')or module:match('^Fluids/')or module=='RadioCom/ISRadioAction')then
            for _,branch in ipairs({'shared','client'})do
                local candidate=NativeActionRoot..'/'..branch..'/'..module..'.lua'
                if exists(candidate)then path=candidate;break end
            end
        end
        if not path and not selected then return end -- Unrelated native UI is outside this fixture.
        loading[module]=true
        local result
        if selected then
            local ok,value=pcall(execute,assert(selected[1]),'media/lua/'..selected[2])
            if not ok then env.sourceFailure=tostring(value);error(value,0)end
            result=value
        else result=execute(text(path),path)end
        loading[module]=nil;loaded[module]=result or true;return result
    end
    local function native(path)
        local actual=NativeActionRoot..'/'..path
        local result=execute(text(actual),actual)
        local module=path:match('^[^/]+/(.*)%.lua$');loaded[module]=result or true
        return result
    end
    local function nativeFunction(path,signature,inputSource)
        local actual=inputSource and 'media/lua/'..path or NativeActionRoot..'/'..path
        local source=inputSource or text(actual)
        local first=assert(source:find(signature,1,true),'missing native producer '..signature)
        local last=assert(source:find('\nend',first,true),'unterminated native producer '..signature)
        local _,lines=source:sub(1,first-1):gsub('\n','\n')
        execute(string.rep('\n',lines)..source:sub(first,last+3),actual)
    end
    local function list(values)
        return {class='ArrayList',values=values,size=function()return #values end,
            get=function(_,i)return values[i+1]end,isEmpty=function()return #values==0 end,
            contains=function(_,value)for _,member in ipairs(values)do if member==value then return true end end return false end}
    end
    local function derive(self,name)
        local class={Type=name,derive=derive};class.__index=class
        return setmetatable(class,{__index=self})
    end
    env.ISBaseObject={derive=derive}
    env.PZSurvivorToolkit={Settings={actionQueue=function()return options.queue~=false end}}
    loaded['PZSurvivorToolkit/Settings']=env.PZSurvivorToolkit.Settings
    env.toolkitLuaMetatableMatches=assert(loadfile(ProjectRoot..'/tests/support/source_binding.lua'))()
    local nativeFilename=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source:gsub('^@','')end
    env.getFilenameOfClosure=function(callback)
        if options.metadataHook then options.metadataHook(env,callback)end
        return nativeFilename(callback)
    end
    env.getFirstLineOfClosure=NativeFirstLineOfClosure or function(callback)
        -- Native Kahlua reports the first instruction, rather than the function
        -- declaration. Lua debug active lines provide that same source role.
        local first
        for line in pairs(debug.getinfo(callback,'L').activelines or {})do
            if not first or line<first then first=line end
        end
        return first or debug.getinfo(callback,'S').linedefined
    end
    env.instanceof=function(value,kind)
        return type(value)=='table'and (value.class==kind or kind=='InventoryItem'and value.item==true
            or kind=='IsoGameCharacter'and value.class=='IsoPlayer')
    end
    local containsTransferID
    env.getClassSimpleName=function(value)
        -- Retain the canonical native containment seam when the fixture installs
        -- its actor/item class labels. Ordinary Lua callbacks stay distinct.
        if value==containsTransferID then return 'LuaJavaInvoker' end
        return type(value)=='table'and value.class or 'KahluaClosure'
    end
    env.table=setmetatable({wipe=function(value)for key in pairs(value)do value[key]=nil end end},{__index=table})
    env.Events={};local events={}
    setmetatable(env.Events,{__index=function(owner,name)
        local callbacks={};events[name]=callbacks
        local event={Add=function(callback)callbacks[#callbacks+1]=callback end,Remove=function()end}
        rawset(owner,name,event);return event
    end})
    env.Hook=setmetatable({}, {__index=function()return {Add=function()end}end})
    for _,name in ipairs({'ClimbState', 'ClimbDownState', 'ForceOpenState', 'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
        'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'})do env[name]={instance=function()return {}end}end
    env.ISInventoryPage={};env.ISInventoryPaneContextMenu={};env.ISInventoryPane={getActualUniqueItems=function(items)return items end,getActualItems=function(items)return items end}
    env.ISContextMenu={};env.ISButton={};env.ISCraftingUI={};env.ISWorldObjectContextMenu={}
    env.LootSorter={}
    env.getText=function(value)return value end;env.getTextOrNull=env.getText
    env.isClient=function()return client==true end;env.isServer=function()return false end;env.isMultiplayer=env.isClient
    env.getActivatedMods=function()
        if options.modProbe then options.modProbe(env)end
        return {contains=function(_,id)return p4Selected and id=='P4TidyUpMeister'end}
    end
    env.getGameVersion=function()return '42.21'end
    local timestamp=100
    env.getTimestampMs=function()return timestamp end;env.getTimestamp=function()return timestamp end
    env.getGameTime=function()return {getMinutesPerDay=function()return 60 end,getMultiplier=function()return 1 end}end
    env.getCore=function()return {getGameMode=function()return 'Sandbox'end,getGoodHighlitedColor=function()return {}end}end
    env.getSandboxOptions=function()return {getOptionByName=function()return {getValue=function()return 0.1 end}end}end
    env.getDebug=function()return false end;env.isDebugEnabled=env.getDebug
    env.ISLogSystem={logAction=function()end};env.DebugType={Action={warn=function(_,message)error(message)end}}
    env.ItemContainer={floatingPointCorrection=function(value)return value end,
        chainContainsContainingItem=function(container,id)
            if id==-1 then return false end
            local seen={}
            while container and not seen[container]do
                seen[container]=true
                if container.id==id then return true end
                local owner=container:getContainingItem()
                if not owner then return false end
                if owner:getID()==id then return true end
                container=owner:getContainer()
            end
            return false
        end}
    containsTransferID=env.ItemContainer.chainContainsContainingItem
    env.CharacterTrait=setmetatable({}, {__index=function(_,key)return key end})
    env.CharacterStat={BOREDOM='boredom',UNHAPPINESS='unhappiness',STRESS='stress'}
    env.ItemTag=setmetatable({}, {__index=function(_,key)return key end})
    env.ItemBodyLocation=setmetatable({}, {__index=function(_,key)return key end})
    env.MoodleType={UNHAPPY=1,DRUNK=2};env.BodyPartType={Hand_L=1,ForeArm_R=2,ToIndex=function(x)return x end,FromIndex=function(x)return x end}
    env.Metabolics={LightWork=1};env.CharacterActionAnims={Read='Read'};env.SkillBook={};env.SandboxVars={};env.ArrayList={new=function()return list({})end}
    env.ISTradingUI={GetUIForPlayer=function()end};env.getServerOptions=function()return {getInteger=function()return 0 end}end
    env.PZAPI={ModOptions={create=function()return {addTickBox=function()return {value=false}end,
        addComboBox=function()return {addItem=function()end}end}end}}
    env.LuaEventManager={AddEvent=function()end}
    local allocated,transactions,effects,engineTrace={},{},{},{}
    env.LuaTimedActionNew={new=function(action,character)
        assert(action.toolkitQueueOperation and action.toolkitQueueOperation.toolkitStarted,
            'full Queue.begin must publish its started token before native allocation')
        local queue=env.ISTimedActionQueue.queues[character]
        local state=env.PZSurvivorToolkit.ActionQueueSettlement.operationState(action)
        engineTrace[#engineTrace+1]={event='native-allocation',action=action,current=queue.current,
            queueSize=#queue.queue,borrowings=state and #state.borrowings or 0}
        local value={owner=action,started=false,removed=false,forced=false,stopped=false}
        function value:isStarted()return self.started end
        function value:finished()return self.removed end
        function value:isForceComplete()return self.forced end
        function value:hasStalled()return false end
        function value:getTable()return action end
        function value:getJobDelta()return 0 end
        function value:forceComplete()self.forced=true end
        function value:forceStop()self.stopped=true end
        function value:setJobDelta()end
        function value:resetJobDelta()end
        for _,method in ipairs({'restoreWeaponType','setTime','setCurrentTime','setLoopedAction','setActionAnim','setAnimVariable','setOverrideHandModelsObject',
            'stopTimedActionAnim','setWaitForFinished'})do value[method]=function()end end
        function value:reset()self.forced=false end
        allocated[#allocated+1]=value;return value
    end}
    env.isItemTransactionConsistent=function(_,_,destination)return destination.room~=false end
    env.createItemTransaction=function(character,items,source,destination)
        local id=#transactions+1
        transactions[id]={items=items,source=source,destination=destination,status='pending'}
        return id
    end
    env.isItemTransactionDone=function(id)return transactions[id]and transactions[id].status=='done'or false end
    env.isItemTransactionRejected=function(id)return transactions[id]and transactions[id].status=='rejected'or false end
    env.getItemTransactionDuration=function()return 1 end
    env.removeItemTransaction=function(id,cancelled)
        engineTrace[#engineTrace+1]={event='transaction-remove',id=id,cancelled=cancelled}
        if transactions[id]then transactions[id].removed=cancelled and 'cancelled'or 'completed'end
    end
    local function square(x)
        return {getX=function()return x end,getY=function()return 0 end,getZ=function()return 0 end,
            DistToProper=function(self,other)return math.abs(x-other:getX())end,canReachTo=function()return true end,
            TreatAsSolidFloor=function()return true end,isSolid=function()return false end,isSolidTrans=function()return false end,
            getTotalWeightOfItemsOnFloor=function()return 0 end}
    end
    local origin,target,adjacent=square(0),square(4),square(3)
    local player={class='IsoPlayer',square=origin}
    for _,name in ipairs({'isDead','isAsleep','isPlayerMoving','pressedMovement','pressedCancelAction','isDraggingCorpse','isFarming',
        'hasTimedActions','hasTrait','isSitting','isWearingAwkwardGloves','isTimedActionInstant','isEquipped','isEquippedClothing',
        'shouldBeTurning','isSittingOnFurniture','isRunning','isSprinting','isAiming'})do player[name]=function()return false end end
    player.isLocalPlayer=function()return true end;player.getPlayerNum=function()return 0 end
    player.getOnlineID=function()return 1 end
    player.getInventory=function(self)return self.inventory end;player.getCurrentSquare=function(self)return self.square end;player.getSquare=player.getCurrentSquare
    player.getX=function(self)return self.square:getX()end;player.getY=function()return 0 end;player.getZ=player.getY
    player.getVehicle=function()end;player.getPerkLevel=function()return 0 end
    player.getOverlaySprite=function()end
    player.getPathFindBehavior2=function()return {reset=function()end,cancel=function()end}end
    player.getAlreadyReadPages=function()return 0 end
    player.getStats=function()return {get=function()return 0 end,set=function()end}end
    player.ReadLiterature=function(self,item)self.readItem=item;self.readCount=(self.readCount or 0)+1 end
    player.getPrimaryHandItem=function(self)return self.primary end;player.getSecondaryHandItem=function(self)return self.secondary end
    player.setPrimaryHandItem=function(self,item)self.primary=item end;player.setSecondaryHandItem=function(self,item)self.secondary=item end
    player.getClothingItem_Back=function()end
    player.getWornItems=function()return {getItem=function()end,size=function()return 0 end}end
    player.getAttachedItems=function()return {getItem=function()end,size=function()return 0 end}end
    player.getModData=function()return {P4TidyUpMeister={doNotReequip=false}}end
    player.getMoodles=function()return {getMoodleLevel=function()return 0 end}end
    player.getBodyDamage=function()return {getBodyPart=function()return {getPain=function()return 0 end}end}end
    player.getTimedActionTimeModifier=function()return 1 end
    player.getCharacterActions=function()local live={};for _,action in ipairs(allocated)do if not action.removed then live[#live+1]=action end end;return list(live)end
    player.StartAction=function()end;player.getTimedActionToRetrigger=function()end
    for _,name in ipairs({'setTimedActionToRetrigger','setIsFarming','clearVariable','reportEvent','setMetabolicTarget','setReading','StopAllActionQueue','playSound','removeAttachedItem','setPath2'})do player[name]=function()end end
    player.setIsFarming=function()engineTrace[#engineTrace+1]={event='native-base-cleanup'}end
    player.getEmitter=function()return {isPlaying=function()return false end,playSound=function()return 1 end,
        stopSound=function()end,stopOrTriggerSound=function()end}end
    env.getSpecificPlayer=function()return player end
    local allItems={}
    local function container(kind,parent)
        local value={class='ItemContainer',kind=kind,parent=parent,available=true,room=true}
        value.getType=function(self)return self.kind end;value.getParent=function(self)return self.parent end
        value.getContainingItem=function(self)return self.owner end;value.isExistYet=function(self)return self.available end
        value.isInCharacterInventory=function(self,character)return self==character.inventory or self.owner and self.owner.container==character.inventory or false end
        value.contains=function(self,item)return item.container==self end
        value.containsID=function(self,id)for _,item in ipairs(allItems)do if item.id==id and item.container==self then return true end end;return false end
        value.getItemById=function(self,id)for _,item in ipairs(allItems)do if item.id==id and item.container==self then return item end end end
        value.getItemWithID=value.getItemById
        value.getItems=function(self)local items={};for _,item in ipairs(allItems)do if item.container==self then items[#items+1]=item end end;return list(items)end
        value.getOutermostContainer=function(self)return self.owner and self.owner.container:getOutermostContainer()or self end
        for _,name in ipairs({'getAcceptItemFunction','getOnlyAcceptCategory','getVehiclePart','getOpenSound','getTakeSound','getPutSound','getContainerPosition','getFreezerPosition'})do value[name]=function()end end
        for _,name in ipairs({'isRemoveItemAllowed','isItemAllowed'})do value[name]=function()return true end end
        value.hasRoomFor=function(self)return self.room end
        value.isInside=function()return false end;value.isVehicleSeat=function()return false end
        value.getCapacityWeight=function()return 0 end;value.getMaxWeight=function()return 100 end
        value.getEffectiveCapacity=value.getMaxWeight;value.getCapacity=value.getMaxWeight
        value.setDrawDirty=function()end;value.setHasBeenLooted=function()end
        value.DoRemoveItem=function(self,item)assert(item.container==self);item.container=nil end
        value.AddItem=function(self,item)
            assert(item.container==nil);item.container=self
            effects[#effects+1]={item=item,destination=self};return item
        end
        return value
    end
    local inventory=container('none',player);player.inventory=inventory
    local world={class='IsoObject',getSquare=function()return target end,getObjectIndex=function()return 0 end,getOverlaySprite=function()end}
    local source=container(options.carried and 'bag'or 'shelves',world)
    if options.carried then source.parent=nil end
    local bag
    if options.carried then
        bag={class='InventoryContainer',item=true,id=9001,container=inventory}
        bag.getID=function(self)return self.id end;bag.getFullType=function()return 'Base.Bag_Schoolbag'end
        bag.getContainer=function(self)return self.container end;bag.getInventory=function()return source end
        bag.getItemContainer=bag.getInventory;bag.getWeight=function()return 1 end
        bag.getActualWeight=bag.getWeight;bag.getUnequippedWeight=bag.getWeight
        bag.getWeightReduction=function()return 0 end;bag.isEquipped=function()return false end
        bag.getName=function()return 'Carried test bag'end;bag.getDisplayName=bag.getName
        bag.getIsCraftingConsumed=function()return false end;bag.getWorldItem=function()end
        source.owner=bag;allItems[#allItems+1]=bag
    end
    env.getCell=function()return {getGridSquare=function(_,x)if x==0 then return origin elseif x==4 then return target elseif x==3 then return adjacent end end}end
    env.AdjacentFreeTileFinder={Find=function()return adjacent end}
    env.getPlayerLoot=function()return {selectButtonForContainer=function()end,setForceSelectedContainer=function()end}end
    env.getPlayerInventory=function()return {inventory=inventory,refreshBackpacks=function()end}end
    env.getPlayerHotbar=function()end
    env.ItemPicker={updateOverlaySprite=function()end}
    env.sendServerCommand=function()end;env.sendSyncPlayerFields=function()end;env.syncItemFields=function()end
    env.round=function(value)return value end
    env.luautils={}
    native('shared/ISBaseObject.lua')
    native('shared/TimedActions/ISBaseTimedAction.lua')
    native('client/TimedActions/ISTimedActionQueue.lua')
    native('client/TimedActions/ISQueueActionsAction.lua')
    native('shared/TimedActions/ISReadABook.lua')
    native('shared/TimedActions/ISWringClothing.lua')
    native('client/TimedActions/ISInventoryTransferAction.lua')
    native('shared/TimedActions/ISInventoryTransferUtil.lua')
    native('shared/TimedActions/ISTransferAction.lua')
    for _,name in ipairs({'ISEquipWeaponAction','ISUnequipAction','ISWearClothing','ISClothingExtraAction','ISAttachItemHotbar'})do
        native('shared/TimedActions/'..name..'.lua')
    end
    native('client/TimedActions/ISDetachItemHotbar.lua')
    native('client/TimedActions/WalkToTimedAction.lua')
    -- Keep real UI ancestry even for the native fallback. A one-function plain
    -- table would hide binding failures and incorrectly allow ancestry removal.
    env.getTextManager=function()return {getFontHeight=function()return 14 end}end
    env.UIFont={Small=1}
    native('client/ISUI/ISUIElement.lua');native('client/ISUI/ISPanel.lua')
    if options.cleanUISelectorSource then
        execute(options.cleanUISelectorCompiledSource or options.cleanUISelectorSource,'media/lua/client/ISUI/ISInventoryPane.lua')
        -- UI extensions may add unrelated own metadata. Cross the generic
        -- binding budget while retaining every real method and native ancestor.
        local count=0;for _ in pairs(env.ISInventoryPane)do count=count+1 end
        for index=count+1,129 do env.ISInventoryPane['fixtureBindingField'..index]=index end
    else
        native('client/ISUI/ISInventoryPane.lua')
    end
    nativeFunction('shared/luautils.lua','function luautils.walkToContainer(')
    nativeFunction('shared/luautils.lua','function luautils.haveToBeTransfered(')
    if options.cleanUIContextSource then
        -- Execute the actual complete selected chunk to retain its private
        -- transfer helpers. Its tooltip declarations need only these UI doubles.
        env.getTextManager=function()return {getFontHeight=function()return 14 end}end
        env.UIFont={Small=1};env.ISToolTip=env.ISBaseObject
        execute(options.cleanUIContextSource,'media/lua/client/ISUI/ISInventoryPaneContextMenu.lua')
    else
        for _,signature in ipairs({'function ISInventoryPaneContextMenu.transferIfNeeded(',
            'ISInventoryPaneContextMenu.onLiteratureItems = function(', 'ISInventoryPaneContextMenu.readItem = function(',
            'ISInventoryPaneContextMenu.onWringClothing = function(', 'ISInventoryPaneContextMenu.OnPrimaryWeapon = function(',
            'ISInventoryPaneContextMenu.OnSecondWeapon = function(', 'ISInventoryPaneContextMenu.OnTwoHandsEquip = function(',
            'ISInventoryPaneContextMenu.equipWeapon = function('})do
            nativeFunction('client/ISUI/ISInventoryPaneContextMenu.lua',signature)
        end
    end
    for _,signature in ipairs({'function ISCraftingUI.ReturnItemToOriginalContainer(', 'function ISCraftingUI.ReturnItemToContainer('})do
        nativeFunction('client/ISUI/ISCraftingUI.lua',signature)
    end
    env.ISInventoryPaneContextMenu.getContainers=function()return list({source,inventory})end
    local function book(id,location)
        local value={class='Literature',item=true,id=id,container=location or source}
        value.getContainer=function(self)return self.container end;value.getID=function(self)return self.id end
        value.getFullType=function()return 'Base.Book'end;value.getType=function()return 'Book'end;value.getCategory=function()return 'Literature'end
        value.getWeight=function()return .05 end;value.getActualWeight=value.getWeight;value.getUnequippedWeight=value.getWeight
        value.getSkillTrained=function()return 'None'end;value.getLvlSkillTrained=function()return -1 end
        value.getNumberOfPages=function()return 1 end;value.getAlreadyReadPages=function()return 0 end
        value.getLearnedRecipes=function()return list({})end
        value.setJobDelta=function()end;value.setJobType=function()end;value.setAlreadyReadPages=function()end
        value.getJobType=function()return 'Transfer'end;value.getName=function()return 'Book'end;value.getDisplayName=value.getName
        for _,name in ipairs({'isFavorite','getIsCraftingConsumed','hasTag','isHumanCorpse','hasModData','IsClothing','canBeActivated','isForceDropHeavyItem','isOnGroundOrInsideBagOnSquare'})do value[name]=function()return false end end
        value.getWorldItem=function()end;value.getEquipParent=function()end;value.getReadType=function()end
        value.getAttachedSlot=function()return -1 end
        value.isRequiresEquippedBothHands=function()return false end;value.IsInventoryContainer=function()return false end
        value.getEquipSound=function()end;value.getCurrentUsesFloat=function()return 1 end
        value.canBeEquipped=function()end
        allItems[#allItems+1]=value;return value
    end
    local function garment(id, location)
        local value=book(id, location)
        value.class,value.wetness='Clothing',80
        value.getFullType=function()return 'Base.Shirt_Denim'end
        value.getType=function()return 'Shirt_Denim'end
        value.getCategory=function()return 'Clothing'end
        value.IsClothing=function()return true end
        value.getWetness=function(self)return self.wetness end
        value.setWetness=function(self,wetness)self.wetness=wetness end
        value.getBodyLocation=function()return 'Torso'end
        value.getClothingItem=function()return {}end
        return value
    end
    if options.readProducer=='transferIfNeeded' then
        -- Preserve the real same-file native closure while changing its role
        -- before Operations captures the existing producer wrapper.
        env.ISInventoryPaneContextMenu.readItem=env.ISInventoryPaneContextMenu.transferIfNeeded
    end
    if options.primaryProducer=='OnSecondWeapon'then
        -- Genuine same-file closure, incorrect public callback role.
        env.ISInventoryPaneContextMenu.OnPrimaryWeapon=env.ISInventoryPaneContextMenu.OnSecondWeapon
    end
    if options.razor then
        if bag then bag.isBroken=function()return false end;bag.hasTag=function()return false end;bag.getType=function()return 'Bag_Schoolbag'end end
        native('client/ISUI/ISPanelJoypad.lua')
        native('client/ISUI/ISUI3DModel.lua')
        native('client/XpSystem/ISUI/ISCharacterScreen.lua')
        native('shared/TimedActions/ISTrimBeard.lua')
        nativeFunction('client/ISUI/ISWorldObjectContextMenu.lua','function ISWorldObjectContextMenu.transferIfNeeded(')
        nativeFunction('client/ISUI/ISWorldObjectContextMenu.lua','ISWorldObjectContextMenu.equip = function(')
        inventory.getFirstEvalRecurse=function(_,predicate)
            for _,item in ipairs(allItems)do
                if (item.container==inventory or options.carried and item.container==source)and predicate(item)then return item end
            end
        end
        local visual={beard='LongScruffy'}
        visual.setBeardModel=function(self,value)self.beard=value end
        player.getHumanVisual=function()return visual end
        player.resetModel=function()end;player.resetBeardGrowingTime=function()end
        env.sendHumanVisual=function()end;env.triggerEvent=function()end
    end
    if options.ackFirst then env.require('PZSurvivorToolkit/ActionQueueAcknowledgements')end
    env.require('PZSurvivorToolkit/ActionQueueOperations')
    env.require('PZSurvivorToolkit/ActionQueueDefinitions')
    env.require('PZSurvivorToolkit/ActionQueuePolicy')
    env.require('PZSurvivorToolkit/ActionQueue')
    local compat=env.require('PZSurvivorToolkit/ActionQueueCompat')
    assert(compat.isInstalled('P4TidyUpMeister')==p4Enabled,'selected P4 provider differs from fixture: '..tostring(env.sourceFailure))
    if options.razor then
        env.require('PZSurvivorToolkit/ActionQueueTidyIntent')
        local razor=env.require('PZSurvivorToolkit/ActionQueueRazorRestoration')
        assert(razor.install(),'qualification razor installation failed')
    end
    local queue=env.ISTimedActionQueue.getTimedActionQueue(player)
    local function phase(action,name)
        -- Model the Java LuaTimedActionNew lifecycle bridge, not its individual
        -- listeners. Queue's unchanged begin/stop wrappers still own all order.
        local lifecycle=env.PZSurvivorToolkit.ActionQueueLifecycle
        local observed=lifecycle.begin(action,name)
        local result={pcall(function()if action[name]then return action[name](action)end end)}
        lifecycle.finish(action,name,result[1]and result[2]~=false)
        if not result[1]then error(result[2],0)end
        return observed,result[2]~=false,result[2]
    end
    local function remove(action)
        assert(action.action,'Java removal requires an actual allocated native episode')
        action.action.removed=true
    end
    local function dispatch(action,name)
        local observed=phase(action,name)
        if name=='perform'then
            if not client then
                phase(action,'complete')
            end
            remove(action)
            if client and options.canonicalBodyReplacement and not options.replacedBody
                and action.Type=='ISInventoryTransferAction'and action.destContainer==inventory then
                options.replacedBody=true
                local old=action.item;local canonical={}
                for key,value in pairs(old)do canonical[key]=value end
                assert(old.container==inventory,'server replacement requires an earned physical root item')
                old.container=nil;canonical.container=inventory;allItems[#allItems+1]=canonical
                action.item=canonical
                for _,body in ipairs(queue.queue)do
                    if body.Type=='ISWringClothing'and body.item==old then body.item=canonical end
                end
                engineTrace[#engineTrace+1]={event='server-canonical-replacement',id=canonical.id}
                if options.guardLostAtReplacement then
                    env.PZSurvivorToolkit.ActionQueueRestoration.observeNative=function()return false end
                end
            end
            queue:tick()
        end
        return observed
    end
    local function acknowledge(action,state)
        assert(client and action.toolkitNativeTransaction and action.toolkitNativeKind)
        for _,callback in ipairs(events.OnServerCommand or {})do
            callback('PZSurvivorToolkitActions','State',{protocol=1,player=player:getOnlineID(),
                transaction=action.toolkitNativeTransaction,kind=action.toolkitNativeKind,
                token='00000000-0000-0000-0000-000000000001',state=state})
        end
    end
    local nativeTransaction=90
    local function start(action,lateStarted)
        action.action.started=true
        if client and (action.Type=='ISEquipWeaponAction'or action.Type=='ISWringClothing')then
            -- Model the Java acknowledgement bridge, without replacing the
            -- native equip callbacks or the actual Lua receipt consumer.
            nativeTransaction=nativeTransaction+1
            action.toolkitNativeTransaction,action.toolkitNativeKind=nativeTransaction,action.Type
            if not lateStarted then acknowledge(action,'started')end
        end
        action:start()
    end
    local function deliver(action)
        if not client then return end
        -- Java/server delivery is modeled explicitly, outside every Lua observer.
        local request=assert(transactions[action.transactionId],'native client start submitted no transaction')
        assert(request.status=='pending');request.status='done'
        for _,item in ipairs(request.items)do request.source:DoRemoveItem(item);request.destination:AddItem(item)end
    end
    local function stop(action,wait)
        assert(action.action.stopped,'native stop delivery requires an actual forceStop request')
        dispatch(action,'stop')
        -- Java removes the stopped native action; it never dispatches perform
        -- or complete for this body. Host terminal delivery is a separate event.
        remove(action)
        if client and not wait then acknowledge(action,'canceled')end
        queue:tick()
    end
    local function tool(id,fullType,location)
        local value=book(id,location)
        value.class='ComboItem'
        value.getFullType=function()return fullType end
        value.getType=function()return fullType:match('[^.]+$')end
        value.getCategory=function()return 'Item'end
        value.isBroken=function()return false end
        value.getStaticModel=function()return 'DisposableRazor'end
        value.hasTag=function(_,tag)return fullType=='Base.Razor'and tag==env.ItemTag.RAZOR end
        return value
    end
    return {env=env,player=player,queue=queue,source=source,inventory=inventory,book=book,garment=garment,list=list,tool=tool,
        dispatch=dispatch,phase=phase,remove=remove,start=start,deliver=deliver,stop=stop,transactions=transactions,events=events,adjacent=adjacent,
        effects=effects,engineTrace=engineTrace,bag=bag,acknowledge=acknowledge,
        setQueueEnabled=function(value)options.queue=value end,
        advance=function(milliseconds)
            assert(type(milliseconds)=='number'and milliseconds>=0,'clock advance must be nonnegative')
            timestamp=timestamp+milliseconds
        end,
        setModProbe=function(callback)options.modProbe=callback end}
end
