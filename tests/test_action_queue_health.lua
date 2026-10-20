if not NativeActionRoot then print('Health queue native contracts SKIP.');return end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
f.native('shared/ISBaseObject.lua')
ISHealthPanel={}
local file=assert(io.open(NativeActionRoot..'/client/XpSystem/ISUI/ISHealthPanel.lua'))
local source=file:read('*a'):gsub('\r','');file:close()
local first=assert(source:find('HealthPanelAction = ISBaseTimedAction:derive',1,true))
local last=assert(source:find('ISHealthPanel.ReceiveMedicalCheckRequest',first,true))
local nativeHandlers
local function loadPanel()
    nativeHandlers=assert(loadstring(source:sub(first,last-1)..'\nreturn {HDisinfect=HDisinfect}',
        '@media/lua/client/XpSystem/ISUI/ISHealthPanel.lua'))()
    for _,range in ipairs({{'function ISHealthPanel.setBodyPartActionForPlayer','function ISHealthPanel:setBodyPartAction'},
        {'function ISHealthPanel.DidPatientMove','function ISHealthPanel:onGainJoypadFocus'},
        {'function ISHealthPanel:getDoctor','function ISHealthPanel:getDamagedParts'}}) do
        local from=assert(source:find(range[1],1,true));local to=assert(source:find(range[2],from,true))
        assert(loadstring(source:sub(from,to-1),'@media/lua/client/XpSystem/ISUI/ISHealthPanel.lua'))()
    end
end
loadPanel()
getFilenameOfClosure=function(callback) return debug.getinfo(callback,'S').source:gsub('^@','') end
getGameFilesInput=function(path)
    local reader=assert(io.open(NativeActionRoot..'/'..path:gsub('^media/lua/','')))
    return {readLine=function() local line=reader:read('*l');return line and line:gsub('\r$','') end,close=function()reader:close()end}
end
local nativeReader = getGameFilesInput
isClient=function()return false end
getScriptManager=function()return {FindItem=function()return {
    getReplaceOnUse=function()end,getReplaceOnDeplete=function()end,getOnBreak=function()end} end} end
local function doctor(player)
    player.class='IsoPlayer';player.parts={}
    player.getSquare=function()return {} end
    player.getX=function(self)return self.x or 0 end;player.getY=function(self)return self.y or 0 end
    player.getZ=function()return 0 end;player.getVehicle=function()end
    player.getBodyDamage=function(self)return {getBodyPart=function(_,kind)return self.parts[kind] end} end
    player.isDriving=function()return false end
    player.isLocalPlayer=function()return false end
    player.getCharacterGender=function()return 'male' end
end
doctor(f.player)
local function loadChildren()
    for _,name in ipairs({'ISApplyBandage','ISDisinfect','ISStitch','ISSplint','ISRemoveGlass','ISRemoveBullet','ISCleanBurn',
        'ISComfreyCataplasm','ISGarlicCataplasm','ISPlantainCataplasm'}) do
        local path=NativeActionRoot..'/shared/TimedActions/'..name..'.lua'
        local reader=assert(io.open(path));local text=reader:read('*a');reader:close()
        assert(loadstring(text,'@'..path))()
    end
end
loadChildren()
local inventoryContextOverride
local function loadContainers()
    local reader=assert(io.open(inventoryContextOverride or NativeActionRoot..'/client/ISUI/ISInventoryPaneContextMenu.lua'))
    local text=reader:read('*a'):gsub('\r','');reader:close()
    local first=assert(text:find('ISInventoryPaneContextMenu.getContainers = function',1,true))
    local last=assert(text:find('ISInventoryPaneContextMenu.addFixerSubOption',first,true))
    assert(loadstring(text:sub(first,last-1),'@media/lua/client/ISUI/ISInventoryPaneContextMenu.lua'))()
    for _,range in ipairs({{'function ISInventoryPaneContextMenu.transferIfNeeded','ISInventoryPaneContextMenu.onEjectMagazine'},
        {'ISInventoryPaneContextMenu.onApplyBandage = function','-- look for any damaged body part'}}) do
        local from=assert(text:find(range[1],1,true));local to=assert(text:find(range[2],from,true))
        local prefix=''
        if inventoryContextOverride and range[1]=='function ISInventoryPaneContextMenu.transferIfNeeded' then
            prefix=text:sub(1,assert(text:find('local CleanUI_reportedEvolvedRecipeRenameErrors',1,true))-1)
            local helperFrom=assert(text:find('ISInventoryPaneContextMenu.cleanUILogTimedActionFix = function',1,true))
            local helperTo=assert(text:find('ISInventoryPaneContextMenu.cleanUIResetStaleEatingRetrigger',helperFrom,true))
            prefix=prefix..text:sub(helperFrom,helperTo-1)
        end
        assert(loadstring(prefix..text:sub(from,to-1),'@media/lua/client/ISUI/ISInventoryPaneContextMenu.lua'))()
    end
    for _,path in ipairs({'client/TimedActions/ISInventoryTransferAction.lua','shared/luautils.lua','shared/TimedActions/ISInventoryTransferUtil.lua'}) do
        local reader=assert(io.open(NativeActionRoot..'/'..path));local value=reader:read('*a');reader:close()
        assert(loadstring(value,'@media/lua/'..path))()
    end
    ArrayList={new=function()
        local values={};return {add=function(_,item)values[#values+1]=item end,size=function()return #values end,get=function(_,i)return values[i+1] end,
            contains=function(_,item)for _,value in ipairs(values)do if value==item then return true end end;return false end}
    end}
    getPlayerInventory=function()return {inventoryPane={inventoryPage={backpacks={{inventory=f.player.inventory}}}}} end
    getPlayerLoot=function()return {inventoryPane={inventoryPage={backpacks={}}}} end
end
loadContainers()
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
local policy=f.project('ActionQueuePolicy')
local health=f.project('ActionQueueHealth')
local function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
local alcohol,bandage=f.item('Base.Disinfectant'),f.item('Base.Bandage')
for _,item in ipairs({alcohol,bandage}) do
    item.IsInventoryContainer=function() return false end
    item.getType=function() return item==alcohol and 'Disinfectant' or 'Bandage' end
    item.getName=function() return item:getFullType() end
    item.getBandagePower=function() return item==bandage and 1 or 0 end
    item.getAlcoholPower=function() return item==alcohol and 4 or 0 end
    item.IsDrainable=function() return item==alcohol end
    item.hasComponent=function() return false end
    item.hasTag=function() return false end
end
ComponentType={FluidContainer=1};ItemTag={REMOVE_GLASS='remove_glass'}
BodyPartType={Hand_L='Hand_L',Hand_R='Hand_R',Foot_L='Foot_L',Foot_R='Foot_R',Head='Head',Neck='Neck'}
f.player.inventory.getItems=function() return list({alcohol,bandage}) end
local context={options={}}
function context:addOption(name,target,callback,...)
    local option={name=name,target=target,onSelect=callback,args={...}}
    self.options[#self.options+1]=option;return option
end
context.getNew=function(self) return self end
context.addSubMenu=function() end
context.isEmpty=function() return false end
context.getIsVisible=function() return true end
context.setVisible=function() end
ISContextMenu.get=function() context.options={};return context end
JoypadState={players={}}
local panel=setmetatable({character=f.player},{__index=ISHealthPanel})
panel.getAbsoluteX=function() return 0 end;panel.getAbsoluteY=panel.getAbsoluteX
local function part()
    local index=#f.player.parts+1
    local kind={getBandageModel=function()return 'Base.Bandage_Test'..index end,
        getBiteWoundModel=function()return 'Base.Bite_Test'..index end,
        getScratchWoundModel=function()return 'Base.Scratch_Test'..index end,
        getCutWoundModel=function()return 'Base.Cut_Test'..index end}
    local value=setmetatable({class='BodyPart',covered=false,getType=function()return kind end,getIndex=function()return index end,
        HasInjury=function() return true end,bandaged=function(self) return self.covered end,
        getSplintFactor=function() return 0 end,getFractureTime=function() return 0 end,getBurnTime=function() return 0 end},
        {__index=function() return function() return false end end})
    f.player.parts[index]=value;f.player.parts[kind]=value;return value
end
local function request(body,kind,...)
    panel:doBodyPartContextMenu(body,0,0)
    for _,option in ipairs(context.options) do
        if option.target and option.target.Type==kind then
            return HealthPanelAction:new(f.player,option.target,...)
        end
    end
    error('native menu did not expose '..kind)
end
local body=part()
local disinfect=request(body,'HDisinfect','Base.Disinfectant')
local cover=request(body,'HApplyBandage','Base.Bandage')
local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
local q=f.queue(head,disinfect,cover)
assert(health.inspect(disinfect) and health.inspect(cover),'native private handlers captured through producer')
assert(health.inspect(cover).outputTypes['Base.Bandage_Test1'] and health.inspect(cover).outputTypes['Base.Bandage_Test1_Blood']
    and health.inspect(cover).itemTypes['Base.Scratch_Test1'],'native visual clothing effects retain finite type dependencies')
assert(policy.moveReason(q,cover,disinfect)=='move_craft_inputs')
assert(policy.moveReason(q,disinfect,cover,true)=='move_craft_inputs')
assert(not policy.cancelOperationReason(q,cover),'canceling a final unstarted bandage cannot change preceding disinfection')
assert(policy.cancelOperationReason(q,disinfect)=='operation_dependent','the following treatment remains a protected dependency')
assert(disinfect:isValid());body.covered=true;assert(not disinfect:isValid());body.covered=false
local independent=request(part(),'HApplyBandage','Base.Bandage')
q=f.queue(head,disinfect,independent)
assert(not policy.moveReason(q,independent,disinfect) and not policy.moveReason(q,disinfect,independent,true))
assert(not policy.cancelOperationReason(q,independent),'independent waiting medical operation can cancel')
local visualSupply=request(part(),'HApplyBandage','Base.Bandage_Test1')
q=f.queue(head,cover,visualSupply)
local visualReason=policy.moveReason(q,visualSupply,cover)
assert(visualReason=='move_craft_inputs','future visual clothing cannot cross its medical producer: '..tostring(visualReason))
local sameSupply=request(part(),'HDisinfect','Base.Disinfectant')
q=f.queue(head,disinfect,sameSupply)
assert(policy.moveReason(q,sameSupply,disinfect)=='move_craft_inputs','late item selection keeps shared supply ordered')
local valid=disinfect.handler.isValid
disinfect.handler.isValid=function() error('must not execute during policy') end
assert(policy.moveReason(q,disinfect,sameSupply,true)=='move_dependent')
disinfect.handler.isValid=valid
local forged=HealthPanelAction:new(f.player,{Type='HDisinfect',bodyPart=body,panel=panel},'Base.Disinfectant')
forged.toolkitQueueOperation={};q=f.queue(head,forged,independent)
assert(policy.moveReason(q,forged,independent,true)=='move_dependent','handler name does not grant permission')
print('Health native menu/handler contracts: same wound and dynamic supplies protected; independent targets and unknown handlers passed.')

-- Native bare-hands removal uses add(), but still belongs before the unrelated tail.
local glassBody=part();glassBody.haveGlass=function()return true end
local removeGlass=request(glassBody,'HRemoveGlass','Hands')
q=f.queue(removeGlass,head)
Perks={Doctor=1};isMultiplayer=function()return false end
f.player.getPerkLevel=function()return 0 end
f.player.getX=function()return 0 end;f.player.getY=f.player.getX
f.player.setIsFarming=function()end
ISLogSystem={logAction=function()end}
q.onCompleted=function(self,action)
    if PZSurvivorToolkit.ActionQueueOperations.deferCompletion(self,action) then return end
    table.remove(self.queue,1);self.current=self.queue[1]
end
removeGlass:perform()
assert(#q.queue==2 and q.current.Type=='ISRemoveGlass' and q.queue[2]==head)
assert(q.current.toolkitQueueOperation==removeGlass.toolkitQueueOperation,'generated child retains medical intent')
-- Capture the clinical child before native removal can advance the expansion parent.
do
    local lifecycle=f.project('ActionQueueLifecycle')
    local client,actions=isClient,f.player.getCharacterActions
    local toIndex=BodyPartType.ToIndex;BodyPartType.ToIndex=function()return 5 end
    local username=f.player.getUsername;f.player.getUsername=function()return 'fixture doctor' end
    local callbacks=0
    for _,mp in ipairs({false,true}) do
        isClient=function()return mp end
        for _,kind in ipairs({'HRemoveGlass','HApplyBandage'}) do
            local wound=part();wound.haveGlass=function()return true end
            local parent=request(wound,kind,kind=='HRemoveGlass' and 'Hands' or 'Base.Bandage')
            local owner=f.queue(parent,head)
            local removed=false;parent.action={}
            f.player.getCharacterActions=function()return {contains=function()return not removed end}end
            owner.onCompleted=function(self,action)
                if lifecycle.current(f.player)==action then
                    assert(not PZSurvivorToolkit.ActionQueueOperations.deferCompletion(self,action),
                        'migrated medicine acquired the legacy Operations completion scope')
                    callbacks=callbacks+1
                end
                if lifecycle.deferCompletion(self,action) then return end
                table.remove(self.queue,1);self.current=self.queue[1]
            end
            assert(health.inspect(parent) and lifecycle.begin(parent,'perform'))
            parent:perform();lifecycle.finish(parent,'perform',true)
            local child=owner.queue[2]
            assert(owner.current==parent and #owner.queue==3 and owner.queue[3]==head
                and child.Type==(kind=='HRemoveGlass' and 'ISRemoveGlass' or 'ISApplyBandage')
                and child.toolkitQueueOperation==parent.toolkitQueueOperation and health.inspect(child)
                and not child.action,'medical child started before its exact contract was captured')
            assert(lifecycle.flush(owner)=='waiting','medical expansion advanced before native removal/completion')
            if not mp then
                -- The Java complete boundary also runs when the Lua parent has no complete method.
                assert(parent.complete==nil and lifecycle.begin(parent,'complete'))
                lifecycle.finish(parent,'complete',true)
                assert(lifecycle.flush(owner)=='waiting','SP medical expansion ignored native removal')
            end
            removed=true
            assert(lifecycle.flush(owner)=='completed' and owner.current==child and owner.queue[2]==head
                and lifecycle.flush(owner)==nil,'medical expansion lost child-before-tail order or advanced twice')
        end
    end
    assert(callbacks==4,'medical native-scope assertions did not run in SP and Host')
    isClient=client;f.player.getCharacterActions=actions;BodyPartType.ToIndex=toIndex
    f.player.getUsername=username
end
-- A later producer replacement cannot keep the audited handler permissions.
local producer=ISHealthPanel.doBodyPartContextMenu
ISHealthPanel.doBodyPartContextMenu=function()end
assert(not health.inspect(disinfect))
ISHealthPanel.doBodyPartContextMenu=producer
local new,perform=HealthPanelAction.new,HealthPanelAction.perform
getGameFilesInput=function()return nil end
f.project('ActionQueueHealth')
assert(HealthPanelAction.new==new and HealthPanelAction.perform==perform,'unavailable source does not install hooks')
getGameFilesInput=function()return {readLine=function()return nil end,close=function()end} end
f.project('ActionQueueHealth')
assert(HealthPanelAction.new==new and HealthPanelAction.perform==perform,'unreviewed source does not install hooks')

-- Private helpers modified before the first menu capture must never become the trusted snapshot.
local function privateHandler(name)
    return assert(nativeHandlers[name],'missing native private handler '..name)
end
local pruneHealth,clearHealth
local function freshHealth(change,queueRuntime)
    f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    f.native('shared/ISBaseObject.lua')
    ISHealthPanel={}
    loadPanel();doctor(f.player)
    loadChildren()
    loadContainers()
    getGameFilesInput=nativeReader
    local class=privateHandler('HDisinfect')
    local parent=getmetatable(class).__index
    local restore=change and change(class,parent)
    f.project('ActionQueueOperations');f.project('ActionQueueDefinitions');f.project('ActionQueuePolicy')
    if queueRuntime then f.project('ActionQueueLabels');f.project('ActionQueue') end
    if queueRuntime then
        Events.OnTick.Add=function(callback)pruneHealth=callback end
        Events.OnMainMenuEnter={Add=function(callback)clearHealth=callback end}
    end
    local adapter=f.project('ActionQueueHealth')
    setmetatable(panel,{__index=ISHealthPanel});panel.character=f.player
    f.player.inventory.getItems=function() return list({alcohol,bandage}) end
    ISContextMenu.get=function() context.options={};return context end
    return adapter,class,parent,restore
end
local adapter,class,parent,restore=freshHealth(function(class)
    class.getItemOfType=function() return bandage end
    return function() class.getItemOfType=nil end
end)
local altered=request(part(),'HDisinfect','Base.Disinfectant')
assert(altered.handler:getItemOfType({},'Base.Disinfectant')==bandage)
assert(not adapter.inspect(altered),'a foreign first-resolved item selector cannot claim the clicked input type')
restore()
assert(adapter.inspect(request(part(),'HDisinfect','Base.Disinfectant')),'native helper restoration permits a fresh capture')
adapter,class,parent,restore=freshHealth(function(class,parent)
    local original=parent.new
    parent.new=function(self,...) return original(self,...) end
    return function() parent.new=original end
end)
altered=request(part(),'HDisinfect','Base.Disinfectant')
assert(not adapter.inspect(altered),'explicit BaseHandler.new is checked even when native HDisinfect.new shadows it')
restore()
local verified=request(part(),'HDisinfect','Base.Disinfectant')
assert(adapter.inspect(verified),'native parent restoration permits a fresh capture')
local original=parent.new
parent.new=function(self,...) return original(self,...) end
assert(verified.handler.new==class.new and not adapter.inspect(verified),'a later masked parent-helper replacement revokes the contract')
parent.new=original
assert(adapter.inspect(verified),'restoring the exact parent helper retains the audited contract')
print('Health private helper trust: pre-capture selectors, masked parent constructors and late parent replacements stay protected.')

-- Parent contracts include the exact downstream native class, constructor, lifecycle and helpers.
local child=ISDisinfect
local childNew,childPerform,childHelper=child.new,child.perform,child.stopSound
child.new=function() error('unverified child constructor') end
assert(not adapter.inspect(verified),'a changed child constructor makes its native parent opaque')
child.new=childNew
assert(adapter.inspect(verified))
child.perform=function() error('unverified child lifecycle') end
assert(not adapter.inspect(verified),'a changed child lifecycle cannot borrow parent resources')
child.perform=childPerform
child.stopSound=function() error('unverified child helper') end
assert(not adapter.inspect(verified),'a changed child helper cannot borrow parent resources')
child.stopSound=childHelper
ISDisinfect=setmetatable({Type='ISDisinfect',new=childNew},{__index=child})
assert(not adapter.inspect(verified),'a replacement child class with the same Type remains opaque')
ISDisinfect=child
assert(adapter.inspect(verified),'restoring the exact child class restores the audited parent')
adapter,class,parent=freshHealth(function() ISDisinfect.new=function() error('foreign initial child constructor') end end)
assert(not adapter.inspect(request(part(),'HDisinfect','Base.Disinfectant')),'a foreign initial child constructor is not snapshotted as native')
adapter,class,parent=freshHealth(function() ISDisinfect=nil end)
assert(not adapter.inspect(request(part(),'HDisinfect','Base.Disinfectant')),'an unavailable child class keeps the parent opaque')
print('Health child bindings: native classes remain supported; unavailable/foreign initial and late constructors/classes/lifecycle/helpers stay protected.')

adapter=freshHealth(function()
    getGameFilesInput=function(path)
        if path:find('/ISDisinfect.lua',1,true) then return {readLine=function()end,close=function()end} end
        return nativeReader(path)
    end
end)
assert(not adapter.inspect(request(part(),'HDisinfect','Base.Disinfectant')),'changed downstream source revokes private-parent permission')

adapter=freshHealth()
policy=PZSurvivorToolkit.ActionQueuePolicy
Perks={Doctor=1};isMultiplayer=function()return false end
BodyPartType.ToIndex=function()return 5 end
f.player.getPerkLevel=function()return 2 end
f.player.getDisplayName=function()return 'Doctor' end
f.player.setIsFarming=function()end
f.player.inventory.getItemById=function(self,id)
    for _,item in ipairs(self.items) do if item:getID()==id then return item end end
end
f.player.inventory.items={}
f.player.inventory.getItems=function(self)return list(self.items) end
f.player.inventory.contains=function(self,value)
    for _,item in ipairs(self.items) do if item==value or type(value)=='string' and item:getType()==value then return true end end
    return false
end
f.player.inventory.containsID=function(self,id)return self:getItemById(id)~=nil end
local function supply(kind)
    local item=f.item(kind)
    item.getType=function()return kind:match('[^.]+$') end
    item.getName=function()return kind end
    item.IsInventoryContainer=function()return false end
    item.getBandagePower=function()return kind=='Base.Bandage' and 4 or 0 end
    item.getAlcoholPower=function()return kind=='Base.Disinfectant' and 4 or 0 end
    item.IsDrainable=function()return kind=='Base.Disinfectant' or kind=='Base.Thread' end
    item.hasComponent=function()return false end
    item.hasTag=function()return false end
    item.isCanBandage=function()return kind=='Base.Bandage' end
    item.isHumanCorpse=function()return false end
    item.getCurrentUsesFloat=function()return 1 end
    item.setJobDelta=function()end
    f.player.inventory.items[#f.player.inventory.items+1]=item
    return item
end
local supplies={}
for _,kind in ipairs({'Bandage','Disinfectant','Needle','Thread','SutureNeedle','SutureNeedleHolder','Splint',
    'RippedSheets','Plank','Tweezers','ComfreyCataplasm','WildGarlicCataplasm','PlantainCataplasm'}) do
    supplies[kind]=supply('Base.'..kind)
end
instanceItem=function(kind)
    local item=supply(kind);table.remove(f.player.inventory.items)
    return item
end
local function wound(mode)
    local body=part()
    body.covered=mode=='HRemoveBandage'
    body.stitched=function()return mode=='HRemoveStitch' end
    body.getSplintFactor=function()return mode=='HRemoveSplint' and 1 or 0 end
    body.getFractureTime=function()return mode=='HSplint' and 5 or 0 end
    body.isDeepWounded=function()return mode=='HStitch' end
    body.haveGlass=function()return mode=='HRemoveGlass' end
    body.haveBullet=function()return mode=='HRemoveBullet' end
    body.isNeedBurnWash=function()return mode=='HCleanBurn' end
    body.getPlantainFactor=function()return 0 end;body.getComfreyFactor=body.getPlantainFactor;body.getGarlicFactor=body.getPlantainFactor
    body.manipulatingUsername=function()end
    body.getBandageType=function()return 'Base.Bandage' end
    body.getSplintItem=function()return 'Base.Splint' end
    return body
end
local clinicalWound=wound
do
    local function drop(body, items)
        local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
        local queue=f.queue(head)
        panel:dropItemsOnBodyPart(body,items)
        return queue.queue[2],queue,head
    end
    local menu=ISContextMenu.get
    ISContextMenu.get=function()error('drop must never open or simulate a menu')end
    local body=wound('HSplint')
    local pending,q,head=drop(body,{supplies.Splint})
    assert(pending and pending.handler.Type=='HSplint' and adapter.inspect(pending) and pending:isValid(),
        'first drop before any native splint menu capture enqueues the audited fallback')
    assert(adapter.inspect(pending).items[supplies.Splint:getID()],'fallback binds the exact dropped ready-made splint')
    table.remove(q.queue,1);q.current=pending
    q.onCompleted=function(self,current)
        if PZSurvivorToolkit.ActionQueueOperations.deferCompletion(self,current) then return end
        table.remove(self.queue,1);self.current=self.queue[1]
    end
    table.insert(q.queue,head);pending:perform()
    assert(q.current.Type=='ISSplint' and q.current.plank==supplies.Splint and q.current.rippedSheet==nil
        and adapter.inspect(q.current) and q.queue[2]==head,'first drop expands to the exact child before its tail')
    local handmade=drop(wound('HSplint'),{supplies.RippedSheets,supplies.Plank})
    assert(handmade and handmade:isValid() and handmade.args[1]=='Base.RippedSheets' and handmade.args[2]=='Base.Plank')
    for _,kind in ipairs({'TreeBranch','TreeBranch2','WoodenStick','WoodenStick2'}) do
        local material=supply('Base.'..kind)
        local pending=drop(wound('HSplint'),{supplies.RippedSheets,material})
        assert(pending and pending:isValid() and pending.args[2]==material:getFullType()
            and adapter.inspect(pending).items[material:getID()],'drop retains native splint material '..kind)
    end
    local original=supplies.Splint.getBandagePower
    supplies.Splint.getBandagePower=function()return 4 end
    local priority,priorityQueue=drop(wound('HSplint'),{supplies.Splint})
    assert(priority.handler.Type=='HApplyBandage' and #priorityQueue.queue==2,'original earlier handlers keep drop priority')
    supplies.Splint.getBandagePower=original
    for _,mode in ipairs({'no-fracture','stitched','already-splinted','head','upper-torso','lower-torso'}) do
        local body=wound('HSplint')
        if mode=='no-fracture' then body.getFractureTime=function()return 0 end end
        if mode=='stitched' then body.stitched=function()return true end end
        if mode=='already-splinted' then body.getSplintFactor=function()return 1 end end
        local kind=mode=='head' and BodyPartType.Head or mode=='upper-torso' and 'Torso_Upper' or mode=='lower-torso' and 'Torso_Lower'
        if kind then BodyPartType.Torso_Upper='Torso_Upper';BodyPartType.Torso_Lower='Torso_Lower';body.getType=function()return kind end end
        local pending=drop(body,{supplies.Splint})
        assert(not pending or not pending:isValid(),'illegal '..mode..' drop cannot treat a fracture')
    end
    assert(not drop(wound('HSplint'),{supplies.Plank}),'a missing dropped sheet is not borrowed from unrelated inventory')
    local exact=drop(wound('HSplint'),{supplies.Splint})
    local oldItems=f.player.inventory.items
    f.player.inventory.items={};supply('Base.Splint')
    assert(not exact:isValid(),'a different ready-made splint cannot replace the lost dropped ID')
    f.player.inventory.items=oldItems
    local setting=PZSurvivorToolkit.Settings.actionQueue
    PZSurvivorToolkit.Settings.actionQueue=function()return false end
    local disabled=drop(wound('HSplint'),{supplies.Splint})
    assert(disabled and disabled:isValid(),'normal first splint drop works with queue editing disabled')
    PZSurvivorToolkit.Settings.actionQueue=setting
    ISContextMenu.get=menu
end
print('Health first drop: ready-made and handmade splints, exact supplies, native priority, clinical legality and queue-off behavior passed.')
local function expanded(mode,...)
    local body=wound(mode)
    local parent=request(body,mode,...)
    local tail=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
    local queue=f.queue(parent,tail)
    queue.onCompleted=function(self,current)
        if PZSurvivorToolkit.ActionQueueOperations.deferCompletion(self,current) then return end
        table.remove(self.queue,1);self.current=self.queue[1]
    end
    parent:perform()
    assert(queue.queue[#queue.queue]==tail,'native expansion retains the unrelated tail')
    assert(queue.current~=parent and adapter.inspect(queue.current),'native '..mode..' child retains its contract')
    local contract,visual=adapter.inspect(queue.current),body:getType():getBandageModel()
    assert(contract.outputTypes[visual] and contract.itemTypes[visual],'expanded treatment retains native visual inventory effects')
    return queue.current,parent,queue,body
end
local cases={
    {'HApplyBandage','Base.Bandage'}, {'HRemoveBandage'}, {'HDisinfect','Base.Disinfectant'},
    {'HStitch','Base.Needle','Base.Thread'}, {'HStitch','Base.SutureNeedle','Base.SutureNeedle'}, {'HRemoveStitch'},
    {'HSplint','Base.RippedSheets','Base.Plank'}, {'HSplint',false,'Base.Splint'}, {'HRemoveSplint'},
    {'HRemoveGlass','Base.Tweezers'}, {'HRemoveGlass','Hands'}, {'HRemoveBullet','Base.Tweezers'},
    {'HCleanBurn','Base.Bandage'}, {'HApplyComfrey','Base.ComfreyCataplasm'},
    {'HApplyGarlic','Base.WildGarlicCataplasm'}, {'HApplyPlantain','Base.PlantainCataplasm'},
}
for _,case in ipairs(cases) do
    local second=case[2];if second==false then second=nil end
    local child,parent,queue=expanded(case[1],second,case[3])
    local contract=assert(policy.inspect(child))
    assert(contract.interrupt=='audited-stop' and not adapter.canSkip(child),'available native clinical mode is stoppable')
    if case[1]=='HStitch' then
        assert(contract.items[supplies[case[2]:match('[^.]+$')]:getID()],'hidden needle remains an exact input')
    end
    if child.Type=='ISStitch' then
        assert(contract.dynamicInputsByType.SutureNeedleHolder,'runtime holder remains a dependency')
        assert(policy.inspect(parent).dynamicInputsByType.SutureNeedleHolder,'parent includes holder duration dependency for stitch apply and removal')
    end
    local foreign=f.action(getmetatable(child),{otherPlayer=child.otherPlayer,bodyPart=child.bodyPart,item=child.item})
    assert(not policy.inspect(foreign),'a matching class without native parent ownership stays opaque')
    local doIt=child.doIt;child.doIt=not doIt
    assert(not policy.inspect(child),'changing the captured clinical mode revokes editing')
    child.doIt=doIt;assert(policy.inspect(child))
end
print('Health expansion: all 16 native clinical branches retain exact parent resources and modes; foreign children stay opaque.')

local opaque=request(wound('HDisinfect'),'HDisinfect','Base.Disinfectant')
local selector=opaque.handler.getItemOfType
opaque.handler.getItemOfType=function(self,...)return selector(self,...)end
local tail=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
local unknown=f.queue(opaque,tail)
unknown.onCompleted=function(self,current)table.remove(self.queue,1);self.current=self.queue[1]end
opaque:perform()
assert(unknown.current.Type=='ISDisinfect' and not policy.inspect(unknown.current)
    and not adapter.canPreserveStop(unknown.current),'an opaque private producer cannot issue audited child or stop ownership')

local child,parent,queue,body=expanded('HStitch','Base.Needle','Base.Thread')
local book=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
local inventory=f.player.inventory
inventory.class='ItemContainer';inventory.getParent=function()end;inventory.getContainingItem=function()end;inventory.getType=function()return 'inventory' end
local holder=f.action(ISInventoryTransferAction,{item=supplies.SutureNeedleHolder,srcContainer=inventory,destContainer=inventory})
queue=f.queue(book,child,holder)
assert(policy.moveReason(queue,child,holder,true)=='move_craft_inputs','late holder type forbids crossing its transfer')
assert(policy.cancelOperationReason(queue,child)=='operation_dependent','holder-dependent operation cannot silently alter later use')
local original=ISHealthPanel.DidPatientMove
ISHealthPanel.DidPatientMove=function()error('foreign helper must not run during policy')end
assert(not policy.inspect(child) and not adapter.canPreserveStop(child),'changed global helper revokes editing and stop preservation')
ISHealthPanel.DidPatientMove=original
assert(policy.inspect(child))
local getter=ISInventoryPaneContextMenu.getContainers
ISInventoryPaneContextMenu.getContainers=function()error('untrusted selector must not execute during inspection')end
assert(not policy.inspect(child) and not adapter.canPreserveStop(child),'changed item selector revokes both permissions')
ISInventoryPaneContextMenu.getContainers=getter
child.doctor={};assert(not policy.inspect(child),'mutated doctor cannot borrow the captured parent contract');child.doctor=f.player
local token=child.toolkitQueueOperation;child.toolkitQueueOperation=book.toolkitQueueOperation
assert(not policy.inspect(child) and not adapter.canPreserveStop(child),'changed operation ownership must not invalidate another token')
child.toolkitQueueOperation=token
local fields=child.item;child.item=supplies.Bandage;assert(not policy.inspect(child));child.item=fields
local other=wound('HApplyBandage')
local independent=request(other,'HApplyBandage','Base.Bandage')
queue=f.queue(book,child,independent)
assert(not policy.moveReason(queue,child,independent,true),'distinct wounds and supplies can cross after expansion')
queue=f.queue(book,child,request(body,'HDisinfect','Base.Disinfectant'))
assert(policy.moveReason(queue,child,queue.queue[3],true)=='move_craft_inputs','expanded child retains same-wound visual dependencies')

child,parent,queue,body=expanded('HDisinfect','Base.Disinfectant')
local alcohol=supplies.Disinfectant
local amount,concentration=0.5,0.7
alcohol.hasComponent=function()return true end
alcohol.getFluidContainer=function()return {getAmount=function()return amount end,getProperties=function()return {getAlcohol=function()return amount*concentration end} end} end
assert(not adapter.canSkip(child))
amount=0;assert(adapter.canSkip(child),'empty retained fluid ID is not enough for disinfecting')
amount=0.5;concentration=0.1;assert(adapter.canSkip(child),'diluted retained bottle cannot disinfect')
concentration=0.7;assert(not adapter.canSkip(child))
isClient=function()return true end
child.action={isStarted=function()return true end}
amount=0;inventory.containsID=function()return true end
assert(not adapter.canSkip(child),'an already-started MP child keeps native authority and cleanup after a fluid update')
assert(adapter.canPreserveStop(child),'an authoritative denial retains the unrelated tail even before its reason replicates')
child.action=nil;isClient=function()return false end;amount=0.5

local function remoteParent()
    local patient={isDead=function()return false end,getPlayerNum=function()return 1 end}
    doctor(patient);patient.getBodyDamageRemote=patient.getBodyDamage
    local part=wound('HApplyBandage');patient.parts[part:getType()]=part
    panel.character, panel.otherPlayer=patient,f.player
    local parent=request(part,'HApplyBandage','Base.Bandage')
    return parent,patient
end
parent,patient=remoteParent()
assert(adapter.inspect(parent) and not adapter.canSkip(parent),'a real doctor/patient pair is supported')
local token=parent.toolkitQueueOperation;parent.toolkitQueueOperation={}
assert(not adapter.inspect(parent) and not adapter.canPreserveStop(parent),'parent ownership is sealed before queue insertion')
parent.toolkitQueueOperation=token
panel.otherPlayer=nil

assert(not adapter.inspect(parent) and adapter.canSkip(parent),'closing the remote panel cannot switch doctors')
panel.otherPlayer=f.player;patient.x=0.6
assert(adapter.canSkip(parent),'patient movement skips only its owned medical request')
patient.x=0;f.player.x=3
assert(adapter.canSkip(parent),'doctor leaving patient range invalidates the medical request')
f.player.x=0;patient.getSquare=function()end
assert(adapter.canSkip(parent),'removed patient cannot be treated')
patient.getSquare=function()return {} end
local vehicle={};patient.getVehicle=function()return vehicle end;f.player.getVehicle=function()return vehicle end
patient.x=10;assert(not adapter.canSkip(parent),'same-vehicle native movement exception remains supported')
f.player.getVehicle=function()end;patient.getVehicle=function()end;patient.x=0
patient.isDead=function()return true end;assert(adapter.canSkip(parent),'dead patient cannot receive queued treatment')
patient.isDead=function()return false end
panel.character=f.player
assert(adapter.canSkip(parent),'reassigned panel cannot redirect a queued request')
panel.otherPlayer=nil

BodyPartType.getDisplayName=function(kind)return 'Part '..kind:getBandageModel() end
getItemTex=function(kind)return 'texture:'..kind end
getTexture=function(path)return path end
local display=request(wound('HRemoveGlass'),'HRemoveGlass','Hands')
local description=PZSurvivorToolkit.ActionQueueDefinitions.describe(display)
assert(description.signature=='ContextMenu_Remove_Glass' and description.target:find('Doctor / Part ',1,true),'pending medical presentation names the actual treatment and patient/body part')
assert(description.icon()=='texture:Base.Bandage','medical requests retain a dedicated medical icon without a selected item')

-- Rebuild against the actual queue stop wrapper, installed before medical class capture.
local oldFresh=freshHealth
adapter=oldFresh(nil,true);policy=PZSurvivorToolkit.ActionQueuePolicy
Perks={Doctor=1};f.player.getPerkLevel=function()return 2 end;f.player.setIsFarming=function()end
f.player.getCharacterActions=function()return {contains=function()return false end} end
f.player.isTimedActionInstant=function()return true end
f.player.setTimedActionToRetrigger=function()end;f.player.StartAction=function()end
LuaTimedActionNew={new=function()return {isStarted=function()return false end} end}
ISMedicalCheckAction={getHealthWindowForPlayer=function()end}
f.player.inventory.items={}
local bandage=supply('Base.Bandage')
f.player.inventory.items={bandage}
f.player.inventory.getItems=function(self)return list(self.items) end
f.player.inventory.getItemById=function(self,id)for _,item in ipairs(self.items)do if item:getID()==id then return item end end end
local wound=wound('HApplyBandage')
parent=request(wound,'HApplyBandage','Base.Bandage')
book=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')});book.begin=function()end
queue=f.queue(parent,book)
parent:perform();child=queue.current
assert(child.Type=='ISApplyBandage' and policy.inspect(child),'real queue expansion captures before starting the child')
child.action={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
f.player.inventory.items={}
assert(not child:isValid(),'missing exact bandage stops before native consumption')
child:stop()
assert(queue.toolkitCancelStopped and queue.queue[2]==book,'native stop preserves the unrelated tail')
queue:tick()
assert(queue.current==book and #queue.queue==1,'native queue resumes the original tail after medical stop')
bandage=supply('Base.Bandage')
parent=request(wound,'HApplyBandage','Base.Bandage')
book=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')});book.begin=function()end
queue=f.queue(parent,book)
parent.action={isStarted=function()return false end}
f.player.inventory.items={}
assert(not parent:isValid(),'missing future supply invalidates the native parent before starting')
queue:tick()
assert(queue.current==book and #queue.queue==1,'Java removal without stop skips only the never-started medical operation')
bandage=supply('Base.Bandage')
parent=request(wound,'HApplyBandage','Base.Bandage')
book=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')});book.begin=function()end
queue=f.queue(parent,book);parent:perform();child=queue.current
child.action={isStarted=function()return false end}
f.player.inventory.items={}
queue:tick()
assert(queue.current==book and #queue.queue==1,'an expanded child invalidated while waiting also preserves the original tail')
local nativeWarnings=0
DebugType={Action={warn=function()nativeWarnings=nativeWarnings+1 end}}
for _,mode in ipairs({'started','foreign-token'}) do
    bandage=supply('Base.Bandage');parent=request(wound,'HApplyBandage','Base.Bandage')
    book=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')});book.begin=function()end
    queue=f.queue(parent,book);parent:perform();child=queue.current
    child.action={isStarted=function()return mode=='started' end}
    if mode=='foreign-token' then child.toolkitQueueOperation=book.toolkitQueueOperation end
    f.player.inventory.items={};queue:tick()
    assert(queue.current==nil and #queue.queue==0,'unstarted recovery cannot bypass native handling of '..mode)
end
assert(nativeWarnings==2,'both ineligible recovery cases retain the native reset path')
-- Medical handlers can borrow from a root bag that is absent from the UI's equipped-container list.
local inventory=f.player.inventory
inventory.class='ItemContainer';inventory.getParent=function()end;inventory.getContainingItem=function()end;inventory.getType=function()return 'inventory' end
local owner=f.item('Base.Bag_Schoolbag');owner.class='InventoryContainer'
local bag={class='ItemContainer',getType=function()return 'bag' end,getContainingItem=function()return owner end,
    getParent=function()end,isExistYet=function()return true end}
assert(policy.isCarriedContainer(bag,f.player),'an unequipped carried bag remains a valid return destination')
local bandage=supply('Base.Bandage');bandage.getIsCraftingConsumed=function()return false end
parent=request(wound,'HApplyBandage','Base.Bandage')
book=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')});book.begin=function()end
queue=f.queue(parent,book);parent:perform();child=queue.current
child.toolkitQueueOperation.toolkitPickups={[bandage]=bag}
child.action={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
PZSurvivorToolkit.BulkActions.guardTransfer=function()end
child.action.forceStop=function()end
ISInventoryTransferUtil={newInventoryTransferAction=function(character,item,source,destination)
    return f.action(ISInventoryTransferAction,{item=item,srcContainer=source,destContainer=destination,maxTime=1})
end}
assert(PZSurvivorToolkit.ActionQueue.cancelOperation(queue,child),'active owned medical cancellation remains available')
child:stop();queue:tick()
assert(queue.current.Type=='ISInventoryTransferAction' and queue.current.item==bandage
    and queue.current.destContainer==bag and queue.queue[2]==book,'cancellation schedules the exact borrowed item return before the original tail')
do
    local consumed=false
    local priorItems=inventory.items
    local pendingBandage=supply('Base.Bandage')
    pendingBandage.getContainer=function()return bag end
    pendingBandage.getIsCraftingConsumed=function()return consumed end
    local borrowed=supply('Base.Tweezers');borrowed.getIsCraftingConsumed=function()return false end
    owner.IsInventoryContainer=function()return true end
    owner.getInventory=function()return bag end
    bag.getItems=function()return list({pendingBandage}) end
    inventory.items={owner,borrowed}
    local inventoryUI=getPlayerInventory
    getPlayerInventory=function()return {inventoryPane={inventoryPage={backpacks={{inventory=inventory},{inventory=bag}}}}} end
    local body=part()
    local pending=request(body,'HApplyBandage','Base.Bandage')
    local tail=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')});tail.begin=function()end
    local q=f.queue(pending,tail);pending:perform();getPlayerInventory=inventoryUI
    local preparation=q.current
    assert(preparation.Type=='ISInventoryTransferAction' and preparation.item==pendingBandage
        and preparation.srcContainer==bag and preparation.destContainer==inventory,'native medical expansion captures its carried-bag preparation')
    assert(policy.inspect(preparation) and adapter.canPreserveStop(preparation),'captured native preparation retains its contract')
    preparation.toolkitQueueOperation.toolkitPickups={[borrowed]=bag}
    consumed=true
    assert(not preparation:isValid() and adapter.canSkip(preparation),'native consumed-item rejection skips preparation while its patient remains available')
    local token=preparation.toolkitQueueOperation
    preparation.toolkitQueueOperation=tail.toolkitQueueOperation
    assert(not adapter.canSkip(preparation) and not adapter.canPreserveStop(preparation),'changed preparation token cannot borrow group cleanup')
    preparation.toolkitQueueOperation=token;preparation.srcContainer=inventory
    assert(not adapter.canSkip(preparation) and not adapter.canPreserveStop(preparation),'changed preparation source cannot borrow group cleanup')
    preparation.srcContainer=bag
    preparation.action={isStarted=function()return false end}
    q:tick()
    assert(token.toolkitCancelled and not body.covered and q.current.Type=='ISInventoryTransferAction'
        and q.current.item==borrowed and q.current.destContainer==bag and q.queue[2]==tail,
        'never-started native preparation rejection keeps borrowed returns and the unrelated tail')
    inventory.items=priorItems;ISTimedActionQueue.queues[f.player]=queue
end
owner.getContainer=function()return {} end
assert(not policy.isCarriedContainer(bag,f.player),'a removed or foreign bag cannot borrow the carried-return permission')
local pending=request(wound,'HApplyBandage','Base.Bandage')
table.insert(queue.queue,pending);pruneHealth();assert(adapter.inspect(pending),'queued ownership survives pruning')
queue:removeFromQueue(pending);pruneHealth();assert(not adapter.inspect(pending),'removed ownership is released even while its Lua action remains referenced')
do
    clearHealth()
    local priorQueue=queue
    local tracked={}
    queue=f.queue(book)
    for i=1,64 do
        tracked[i]=request(wound,'HApplyBandage','Base.Bandage')
        table.insert(queue.queue,tracked[i])
    end
    local unrelatedOwner={}
    local unrelated={queue={book}}
    ISTimedActionQueue.queues[unrelatedOwner]=unrelated
    local scans,visits,foreignScans=0,0,0
    local nativeIpairs,nativeNext=ipairs,next
    ipairs=function(values)
        local iterator,state,index=nativeIpairs(values)
        if values==unrelated.queue then foreignScans=foreignScans+1 end
        if values~=queue.queue then return iterator,state,index end
        scans=scans+1
        return function(...)
            local key,value=iterator(...)
            if key then visits=visits+1 end
            return key,value
        end,state,index
    end
    next=nil -- Kahlua has no next global.
    pruneHealth()
    next,ipairs=nativeNext,nativeIpairs
    assert(scans==1 and visits==#queue.queue and foreignScans==0,
        'medical pruning must visit its live queue once and skip unrelated player queues')
    for _,action in ipairs(tracked) do assert(adapter.inspect(action),'linear pruning lost queued medical ownership') end
    local oldQueue=queue
    queue=f.queue(book,tracked[1])
    pruneHealth()
    assert(oldQueue.queue[2]==tracked[1] and adapter.inspect(tracked[1]) and not adapter.inspect(tracked[2]),
        'queue replacement must retain only actions in the current registered queue')
    table.remove(queue.queue,2);pruneHealth()
    assert(not adapter.inspect(tracked[1]),'completed medical action retained ownership after the next tick')
    local changedOwner=request(wound,'HApplyBandage','Base.Bandage')
    table.insert(queue.queue,changedOwner)
    changedOwner.character=unrelatedOwner
    pruneHealth();changedOwner.character=f.player
    assert(not adapter.inspect(changedOwner),'medical pruning must resolve the action current character queue')
    scans,visits=0,0;ipairs=function(values)
        if values==queue.queue then scans=scans+1 end
        return nativeIpairs(values)
    end
    pruneHealth();ipairs=nativeIpairs
    assert(scans==0,'empty medical registry must not scan the queue')
    ISTimedActionQueue.queues[unrelatedOwner]=nil
    queue=priorQueue;ISTimedActionQueue.queues[f.player]=queue
end
pending=request(wound,'HApplyBandage','Base.Bandage');table.insert(queue.queue,pending)
clearHealth();assert(not adapter.inspect(pending),'main menu releases all medical ownership records')
local online
getPlayerByOnlineID=function()return online end
adapter=freshHealth()
parent,patient=remoteParent();patient.getOnlineID=function()return 17 end;online=patient
isClient=function()return true end
assert(adapter.inspect(parent) and not adapter.canSkip(parent),'remote patient identity resolves through the native online registry')
online={};assert(adapter.canSkip(parent),'a recreated player with the same online ID cannot inherit queued treatment')
patient.isLocalPlayer=function()return true end
patient.getBodyDamageRemote=function()error('a local coop patient uses live local body damage')end
assert(adapter.inspect(parent) and not adapter.canSkip(parent),'another local coop player retains its actual body parts')
isClient=function()return false end
print('Health runtime guards: hidden tools, fluid state, panel/actor identity, moving/removed patients, same-car exception and native stop preserve exact tail.')

do
    adapter=freshHealth(nil,true);policy=PZSurvivorToolkit.ActionQueuePolicy
    local actor=f.player
    Perks={Doctor=1};CharacterTrait={DEXTROUS=1,ALL_THUMBS=2}
    getTimestampMs=function()return 0 end;getCore=function()return {getGameMode=function()return 'Sandbox' end}end
    actor.getPerkLevel=function()return 2 end;actor.hasTrait=function()return false end
    actor.isWearingAwkwardGloves=function()return false end;actor.setIsFarming=function()end
    local inventory=actor.inventory
    inventory.class='ItemContainer';inventory.items={}
    inventory.getType=function()return 'inventory' end;inventory.getParent=function()end;inventory.getContainingItem=function()end
    inventory.isInCharacterInventory=function()return true end;inventory.isVehicleSeat=function()return false end
    inventory.getItems=function(self)return list(self.items)end
    inventory.getItemById=function(self,id)for _,item in ipairs(self.items)do if item:getID()==id then return item end end end
    inventory.contains=function(self,value)for _,item in ipairs(self.items)do if item==value then return true end end;return false end
    inventory.containsID=function(self,id)return self:getItemById(id)~=nil end
    local function bandage()
        local item=supply('Base.Bandage')
        item.getActualWeight=function()return 0.1 end;item.isFavorite=function()return false end
        item.getIsCraftingConsumed=function()return false end
        return item
    end
    local function direct(item,body,selected)
        local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')});head.begin=function()end
        local q=f.queue(head)
        if selected then ISInventoryPaneContextMenu.onApplyBandage({item},body,0)
        else ISInventoryPaneContextMenu.applyBandage(item,body,0)end
        return q.queue[#q.queue],q,head
    end
    ISInventoryPane.getActualItems=function(items)return items end
    local item,body=bandage(),clinicalWound('HApplyBandage')
    local child,q,head=direct(item,body,true)
    assert(child.Type=='ISApplyBandage' and child.item==item and child.otherPlayer==actor and child.doIt,
        'actual native inventory menu delegates to the self-bandage producer')
    assert(adapter.inspect(child) and adapter.inspect(child).items[item:getID()] and adapter.patient(child)==actor,
        'native inventory producer binds its exact selected item and self patient')
    assert(not policy.cancelOperationReason(q,child),'independent waiting inventory bandage can cancel')
    local other=direct(bandage(),clinicalWound('HApplyBandage'))
    q=f.queue(head,child,other)
    assert(not policy.moveReason(q,child,other,true),'independent inventory bandages can reorder')
    local same=direct(item,clinicalWound('HApplyBandage'));q=f.queue(head,child,same)
    assert(policy.moveReason(q,child,same,true)=='move_shared_item','same exact bandage cannot cross its other queued use')
    same=direct(bandage(),body);q=f.queue(head,child,same)
    assert(policy.moveReason(q,child,same,true)=='move_craft_inputs','inventory bandages on the same wound retain their visual/body dependencies')
    body.covered=true;body.HasInjury=function()return false end
    assert(adapter.inspect(child) and not adapter.canSkip(child),'inventory bandage retains native covered/healthy-body semantics')
    body.covered=false
    local foreign=ISApplyBandage:new(actor,actor,item,body,true)
    assert(not adapter.inspect(foreign),'a bare matching constructor is not an inventory producer proof')
    for _,field in ipairs({'character','otherPlayer','bodyPart','item','toolkitQueueOperation','onCompleteFunc'})do
        local saved=child[field]
        child[field]=field=='onCompleteFunc' and function()end or {}
        assert(not adapter.inspect(child),'changed direct '..field..' revokes the exact producer proof')
        child[field]=saved
    end
    local nativeProducer=ISInventoryPaneContextMenu.applyBandage
    ISInventoryPaneContextMenu.applyBandage=function()error('foreign producer must not run during policy')end
    assert(not adapter.inspect(child) and not adapter.canPreserveStop(child),'changed inventory producer revokes queued rights')
    ISInventoryPaneContextMenu.applyBandage=nativeProducer
    for _,binding in ipairs({{ISInventoryPaneContextMenu,'transferIfNeeded'},{luautils,'haveToBeTransfered'},
        {luautils,'walkToContainer'},{ISInventoryTransferUtil,'newInventoryTransferAction'},
        {ISInventoryTransferUtil,'isCharacterGrabbingCorpseItem'},{ISInventoryTransferUtil,'isPlayerCharacter'},
        {ISInventoryTransferUtil,'isPlayerGrabbingCorpseItem'}})do
        local owner,name=binding[1],binding[2];local saved=owner[name]
        owner[name]=function()error('foreign inventory helper must not execute during inspection')end
        assert(not adapter.inspect(child) and not adapter.canPreserveStop(child),'changed inventory helper '..name..' revokes rights')
        owner[name]=saved
    end
    local lookup=getSpecificPlayer;getSpecificPlayer=function()return {}end
    assert(not adapter.inspect(child),'changed actor resolver revokes inventory ownership');getSpecificPlayer=lookup
    assert(adapter.inspect(child),'restoring native helper identities restores the original proof')
    local originalNew=ISApplyBandage.new
    ISApplyBandage.new=function(self,...)return originalNew(self,...)end
    assert(not adapter.inspect(direct(bandage(),clinicalWound('HApplyBandage'))),'modified producer constructor stays opaque')
    ISApplyBandage.new=originalNew
    inventory.items={item}
    item.getContainer=function()return inventory end
    inventory.items={}
    assert(adapter.canSkip(child),'a different supply cannot replace the exact inventory-bandage ID')
    inventory.items={item}
    local owner=f.item('Base.Bag_Schoolbag');owner.class='InventoryContainer'
    local bag={class='ItemContainer',items={},getType=function()return 'bag'end,getContainingItem=function()return owner end,
        getParent=function()end,isInCharacterInventory=function()return true end,isVehicleSeat=function()return false end}
    bag.contains=function(self,value)for _,item in ipairs(self.items)do if item==value then return true end end;return false end
    bag.getItems=function(self)return list(self.items)end;owner.IsInventoryContainer=function()return true end
    owner.getInventory=function()return bag end;owner.getWorldItem=function()end
    local borrowed=bandage();borrowed.getContainer=function()return bag end;bag.items={borrowed};inventory.items={owner}
    local treatment=clinicalWound('HApplyBandage')
    child,q,head=direct(borrowed,treatment)
    local preparation=q.queue[2]
    assert(#q.queue==3 and preparation.Type=='ISInventoryTransferAction' and preparation.item==borrowed
        and preparation.srcContainer==bag and preparation.destContainer==inventory and adapter.inspect(child),
        'actual inventory producer retains its carried-bag transfer and exact clinical child')
    assert(preparation.toolkitQueueOperation==child.toolkitQueueOperation and adapter.canPreserveStop(preparation),
        'inventory pickup and bandage are one cancellable medical intent')
    assert(policy.cancelReason(q,child)=='dependent' and not policy.cancelOperationReason(q,child),
        'a bandage child cannot be removed independently of its carried-bag preparation')
    local source=preparation.srcContainer;preparation.srcContainer=inventory
    assert(not adapter.canPreserveStop(preparation),'changed inventory pickup source cannot borrow medical cleanup')
    preparation.srcContainer=source
    assert(PZSurvivorToolkit.ActionQueue.cancelOperation(q,child) and #q.queue==1 and q.queue[1]==head,
        'waiting inventory cancellation removes pickup and clinical work while preserving the unrelated head')
    print('Inventory bandage: real producer/menu, exact actor/body/item/helpers, native clinical semantics, grouped carried pickup, cancel and reorder passed.')
end

do
    local approved={}
    local carts={isTransfer=function()return false end,isReturn=function()return false end,
        isTransferConstructor=function(callback)return approved[callback]==true end}
    adapter=freshHealth(function()PZSurvivorToolkit.ActionQueueCarts=carts end)
    local nativeConstructor=ISInventoryTransferAction.new
    Perks={Doctor=1};f.player.getPerkLevel=function()return 2 end
    f.player.inventory.class='ItemContainer';f.player.inventory.items={}
    f.player.inventory.getType=function()return 'inventory'end
    local item=supply('Base.Bandage');local body=clinicalWound('HApplyBandage')
    local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')});local q=f.queue(head)
    ISInventoryPaneContextMenu.applyBandage(item,body,0)
    local child=q.queue[2]
    assert(child and adapter.inspect(child),'unchanged native constructor remains supported before delayed Carts approval')
    local knownWrapper=function(self,...)return nativeConstructor(self,...)end
    ISInventoryTransferAction.new=knownWrapper
    assert(not adapter.inspect(child),'a delayed unapproved constructor cannot inherit direct medical proof')
    approved[knownWrapper]=true
    assert(not adapter.inspect(child),'approving only the current wrapper cannot hide an unapproved predecessor')
    approved[nativeConstructor]=true;approved[knownWrapper]=nil
    assert(not adapter.inspect(child),'approving only the predecessor cannot authorize a foreign replacement')
    approved[knownWrapper]=true
    assert(adapter.inspect(child),'later approval of both predecessor and current wrapper retains the direct medical proof')
    local nativeAPI=carts.isTransferConstructor
    carts.isTransferConstructor=function()return true end
    assert(not adapter.inspect(child),'replacing the delayed Carts API cannot grant medical rights');carts.isTransferConstructor=nativeAPI
    PZSurvivorToolkit.ActionQueueCarts={isTransferConstructor=nativeAPI}
    assert(not adapter.inspect(child),'a replacement Carts table cannot inherit the saved proof');PZSurvivorToolkit.ActionQueueCarts=carts
    ISInventoryTransferAction.new=function(self,...)return knownWrapper(self,...)end
    assert(not adapter.inspect(child),'an unapproved later wrapper remains opaque despite a valid earlier chain')
    ISInventoryTransferAction.new=knownWrapper
    assert(adapter.inspect(child),'restoring the approved constructor restores the original medical proof')
    adapter=freshHealth()
    Perks={Doctor=1};f.player.getPerkLevel=function()return 2 end
    f.player.inventory.class='ItemContainer';f.player.inventory.items={};f.player.inventory.getType=function()return 'inventory'end
    item=supply('Base.Bandage');body=clinicalWound('HApplyBandage');q=f.queue(f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')}))
    ISInventoryPaneContextMenu.applyBandage(item,body,0);child=q.queue[2]
    assert(adapter.inspect(child),'native constructor without Carts is supported')
    local original=ISInventoryTransferAction.new;ISInventoryTransferAction.new=function(self,...)return original(self,...)end
    assert(not adapter.inspect(child),'a foreign constructor without a Carts API is opaque without throwing')
    ISInventoryTransferAction.new=original
    print('Inventory delayed Carts: unchanged native constructor, approved predecessor/current chain and foreign constructor/table/API rejection passed.')
end

if NativeWishlistWorkshopRoot then
    inventoryContextOverride=NativeWishlistWorkshopRoot..'/3437629766/mods/CleanUI/42.19/media/lua/client/ISUI/ISInventoryPaneContextMenu.lua'
    local function cleanReader(path)
        if path=='media/lua/client/ISUI/ISInventoryPaneContextMenu.lua' then
            local reader=assert(io.open(inventoryContextOverride))
            return {readLine=function()local line=reader:read('*l');return line and line:gsub('\r$','')end,close=function()reader:close()end}
        end
        return nativeReader(path)
    end
    adapter=freshHealth(function()getGameFilesInput=cleanReader end);policy=PZSurvivorToolkit.ActionQueuePolicy
    Perks={Doctor=1};f.player.getPerkLevel=function()return 2 end
    f.player.getTimedActionToRetrigger=function()return 'stale' end
    local reset=0;f.player.setTimedActionToRetrigger=function()reset=reset+1 end
    local inv=f.player.inventory;inv.class='ItemContainer';inv.items={}
    inv.getType=function()return 'inventory'end;inv.getParent=function()end;inv.getContainingItem=function()end
    inv.isInCharacterInventory=function()return true end;inv.isVehicleSeat=function()return false end
    inv.contains=function(self,item)for _,value in ipairs(self.items)do if value==item then return true end end;return false end
    inv.getItemById=function(self,id)for _,value in ipairs(self.items)do if value:getID()==id then return value end end end
    local item=supply('Base.Bandage');local body=clinicalWound('HApplyBandage')
    local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')});local q=f.queue(head)
    ISInventoryPaneContextMenu.applyBandage(item,body,0)
    local child=q.queue[2]
    assert(reset==1 and child and adapter.inspect(child),'reviewed CleanUI source keeps native self-bandage and stale-retrigger cleanup')
    for _,name in ipairs({'cleanUIResetStaleTimedActionRetrigger','cleanUILogTimedActionFix'})do
        local saved=ISInventoryPaneContextMenu[name]
        ISInventoryPaneContextMenu[name]=function()error('foreign CleanUI callback must not execute during policy')end
        assert(not adapter.inspect(child) and not adapter.canPreserveStop(child),'changed CleanUI '..name..' revokes direct producer proof')
        ISInventoryPaneContextMenu[name]=saved
    end
    inventoryContextOverride=nil
    ISInventoryPaneContextMenu.cleanUIResetStaleTimedActionRetrigger=nil
    ISInventoryPaneContextMenu.cleanUILogTimedActionFix=nil
    print('CleanUI inventory bandage: actual reviewed override retains native behavior and guards both mutable cleanup helpers.')
end

if NativeWishlistWorkshopRoot then
    local path=NativeWishlistWorkshopRoot..'/3710913197/mods/MiniHealthPlus/42.20/media/lua/client/MiniHealthPlus/MiniHealthTreatments.lua'
    local reader=assert(io.open(path));local miniSource=reader:read('*a');reader:close()
    local miniRoot=NativeWishlistWorkshopRoot..'/3710913197/mods/MiniHealthPlus/42.20/'
    local function loadMini()
        SandboxVars={MHP={EnableReplaceBandage=true}}
        assert(loadfile(miniRoot..'media/lua/shared/MHP_Sandbox.lua'))()
        TwisTonFire_MHP={handle={player=f.player,playerIndex=0}}
        assert(loadstring(miniSource,'@media/lua/client/MiniHealthPlus/MiniHealthTreatments.lua'))()
        return TwisTonFire_MHP.MiniHealthTreatment
    end
    getModFileReader=function(id,file)
        assert(id=='MiniHealthPlus')
        local file=assert(io.open(miniRoot..file))
        return {readLine=function()return file:read('*l')end,close=function()file:close()end}
    end
    adapter=freshHealth(nil,true);policy=PZSurvivorToolkit.ActionQueuePolicy
    local treatment=loadMini()
    adapter.installMiniHealth()
    Perks={Doctor=1};f.player.getPerkLevel=function()return 2 end;f.player.setIsFarming=function()end
    f.player.hasTrait=function()return false end;f.player.isWearingAwkwardGloves=function()return false end
    f.player.inventory.class='ItemContainer';f.player.inventory.getType=function()return 'inventory'end
    f.player.inventory.getParent=function()end;f.player.inventory.getContainingItem=function()end
    f.player.inventory.isInCharacterInventory=function()return true end;f.player.inventory.isVehicleSeat=function()return false end
    f.player.inventory.isExistYet=function()return true end;f.player.inventory.hasRoomFor=function()return true end
    f.player.inventory.isItemAllowed=function()return true end;f.player.inventory.isInside=function()return false end
    f.player.inventory.items={}
    f.player.inventory.getItems=function(self)return list(self.items)end
    f.player.inventory.getItemById=function(self,id)for _,item in ipairs(self.items)do if item:getID()==id then return item end end end
    f.player.inventory.contains=function(self,value)
        for _,item in ipairs(self.items)do if item==value or type(value)=='string' and item:getType()==value then return true end end
        return false
    end
    f.player.inventory.containsID=function(self,id)return self:getItemById(id)~=nil end
    for _,kind in ipairs({'Bandage','Disinfectant','Needle','Thread','SutureNeedle','SutureNeedleHolder','Splint',
        'RippedSheets','Plank','Tweezers','ComfreyCataplasm','WildGarlicCataplasm','PlantainCataplasm'}) do
        supplies[kind]=supply('Base.'..kind)
    end
    local function miniRequest(body,kind,...)
        body.getDeepWoundTime=function()return 0 end;body.getBandageLife=function()return 0 end
        context.options={};treatment:doBodyPartContextMenu(body,context)
        for _,option in ipairs(context.options)do
            if option.target and option.target.Type==kind then
                return HealthPanelAction:new(f.player,option.target,...)
            end
        end
        error('MiniHealthPlus menu did not expose '..kind)
    end
    for _,case in ipairs(cases)do
        local body=clinicalWound(case[1])
        local arg=case[2];if arg==false then arg=nil end
        local pending=miniRequest(body,case[1],arg,case[3])
        assert(adapter.inspect(pending),'reviewed MHP '..case[1]..' shares the native contract')
        local tail=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
        local q=f.queue(pending,tail)
        q.onCompleted=function(self,current)
            if PZSurvivorToolkit.ActionQueueOperations.deferCompletion(self,current)then return end
            table.remove(self.queue,1);self.current=self.queue[1]
        end
        pending:perform()
        assert(q.current~=pending and adapter.inspect(q.current) and q.queue[#q.queue]==tail,
            'MHP '..case[1]..' child keeps the shared audited contract and original tail')
    end
    local body=clinicalWound('HApplyBandage')
    local pending=miniRequest(body,'HApplyBandage','Base.Bandage')
    local actor=f.player
    actor.getDisplayName=function()return "Doctor" end
    BodyPartType.getDisplayName=function()return "Forearm" end
    assert(adapter.patient(pending)==actor and PZSurvivorToolkit.ActionQueueDefinitions.describe(pending).target=="Doctor / Forearm",
        "MiniHealthPlus presentation uses the captured patient without calling unknown getters: "..tostring(PZSurvivorToolkit.ActionQueueDefinitions.describe(pending).target))
    local nextActor={isDead=function()return false end,getPlayerNum=function()return 1 end};doctor(nextActor)
    TwisTonFire_MHP.handle.player=nextActor
    assert(pending.handler:getDoctor()==actor and pending.handler:getPatient()==actor and adapter.inspect(pending)
        and not adapter.canSkip(pending),'shared MHP handle changes cannot redirect an existing menu request')
    local getter=pending.handler.getDoctor
    pending.handler.getDoctor=function()return nextActor end
    assert(not adapter.inspect(pending),'an unknown per-handler getter revokes MHP permissions')
    pending.handler.getDoctor=getter
    pending.handler.toolkitHealthActor=nextActor
    assert(not adapter.inspect(pending),'mutating the captured MHP actor revokes the action proof')
    pending.handler.toolkitHealthActor=actor;TwisTonFire_MHP.handle.player=actor
    local base=getmetatable(getmetatable(pending.handler)).__index
    local nativeGetter=base.getDoctor;base.getDoctor=function()return actor end
    assert(not adapter.inspect(pending),'a changed MHP prototype getter stays opaque despite its instance binding')
    base.getDoctor=nativeGetter
    local callback=treatment.checkContainerItems;treatment.checkContainerItems=function()end
    assert(not adapter.inspect(pending),'a changed MHP inventory helper revokes existing proofs')
    treatment.checkContainerItems=callback
    assert(adapter.inspect(pending));treatment.restoreOwnContextMenu();assert(adapter.inspect(pending),'mod restore retains the owned producer wrapper')
    local q=f.queue(pending)
    q.onCompleted=function(self,current)
        if PZSurvivorToolkit.ActionQueueOperations.deferCompletion(self,current)then return end
        table.remove(self.queue,1);self.current=self.queue[1]
    end
    pending:perform();local child=q.current
    body.getFractureTime=function()return 10 end
    assert(adapter.canSkip(child),'MHP child retains its fracture-only wound exclusion')
    body.getFractureTime=function()return 0 end
    local function replaceRequest(body,itemType)
        return miniRequest(body,'HReplaceBandage',itemType or 'Base.Bandage')
    end
    local function expandReplacement(fromBag)
        local body=clinicalWound('HRemoveBandage')
        local item=supply('Base.Bandage');item.getIsCraftingConsumed=function()return false end
        f.player.inventory.items={item}
        local bag
        if fromBag then
            local owner=f.item('Base.Bag_Schoolbag');owner.class='InventoryContainer'
            bag={class='ItemContainer',getType=function()return 'bag'end,getContainingItem=function()return owner end,
                getParent=function()end,isInCharacterInventory=function()return true end,isVehicleSeat=function()return false end}
            owner.IsInventoryContainer=function()return true end;owner.getInventory=function()return bag end
            owner.getWorldItem=function()end
            bag.getItems=function()return list({item})end
            bag.isExistYet=function()return true end;bag.isRemoveItemAllowed=function()return true end
            bag.contains=function(_,value)return item:getContainer()==bag and value==item end
            bag.getItemById=function(_,id)return item:getContainer()==bag and item:getID()==id and item or nil end
            item.getContainer=function()return bag end;item.getActualWeight=function()return 0.1 end;item.isFavorite=function()return false end
            f.player.inventory.items={owner}
        end
        local oldUI=getPlayerInventory
        if bag then getPlayerInventory=function()return {inventoryPane={inventoryPage={backpacks={{inventory=f.player.inventory},{inventory=bag}}}}}end end
        local pending=replaceRequest(body)
        local tail=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')});tail.begin=function()end
        local q=f.queue(pending,tail)
        q.onCompleted=function(self,current)
            if PZSurvivorToolkit.ActionQueueOperations.deferCompletion(self,current)then return end
            table.remove(self.queue,1);self.current=self.queue[1]
        end
        pending:perform();getPlayerInventory=oldUI
        return q.queue[1],q.queue[#q.queue-1],pending,q,body,item,tail,bag
    end
    local dirty=clinicalWound('HRemoveBandage')
    local replacement=replaceRequest(dirty)
    assert(adapter.inspect(replacement) and replacement:isValid(),'native MHP dirty-bandage replacement receives a supported parent contract')
    local waitingHead=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
    local waitingOther=f.action(ISReadABook,{item=f.item('Base.BookElectrician1')})
    local waitingQueue=f.queue(waitingHead,replacement,waitingOther)
    assert(not policy.cancelOperationReason(waitingQueue,replacement) and not policy.moveReason(waitingQueue,replacement,waitingOther,true),
        'independent waiting replacement supports whole-operation cancellation and reorder')
    local sameWound=miniRequest(dirty,'HRemoveBandage')
    waitingQueue=f.queue(waitingHead,replacement,sameWound)
    assert(policy.moveReason(waitingQueue,replacement,sameWound,true)=='move_craft_inputs','replacement cannot cross another treatment on its wound')
    local sameSupply=miniRequest(clinicalWound('HApplyBandage'),'HApplyBandage','Base.Bandage')
    waitingQueue=f.queue(waitingHead,replacement,sameSupply)
    assert(policy.moveReason(waitingQueue,replacement,sameSupply,true)=='move_craft_inputs','replacement retains its future dynamic supply dependency')
    for _,field in ipairs({'character','toolkitQueueOperation'})do
        local saved=replacement[field];replacement[field]={}
        assert(not adapter.inspect(replacement),'mutated replacement '..field..' revokes parent proof');replacement[field]=saved
    end
    local selectedType=replacement.args[1];replacement.args[1]='Base.RippedSheets'
    assert(not adapter.inspect(replacement),'replacement cannot redirect its selected supply type');replacement.args[1]=selectedType
    local part=replacement.handler.bodyPart;replacement.handler.bodyPart=clinicalWound('HRemoveBandage')
    assert(not adapter.inspect(replacement),'replacement cannot redirect its body part');replacement.handler.bodyPart=part
    local prototype=getmetatable(replacement.handler);local nativePerform=prototype.perform
    prototype.perform=function()error('untrusted replacement prototype must not execute under rights')end
    assert(not adapter.inspect(replacement),'replacement prototype mutation revokes rights');prototype.perform=nativePerform
    local sandbox=MHP_SB_IsReplaceBandageEnabled
    MHP_SB_IsReplaceBandageEnabled=function()error('foreign sandbox getter must not execute during inspection')end
    assert(not adapter.inspect(replacement),'a foreign replace-bandage sandbox callback revokes rights before execution')
    MHP_SB_IsReplaceBandageEnabled=sandbox
    local sandboxBool=MHP_SB_GetBool;MHP_SB_GetBool=function()error('foreign sandbox helper must not execute during inspection')end
    assert(not adapter.inspect(replacement),'a foreign sandbox dependency revokes replace rights');MHP_SB_GetBool=sandboxBool
    local remove,apply,pending,q,body,item,tail,bag=expandReplacement(false)
    assert(remove.Type=='ISApplyBandage' and remove.doIt==false and remove.item==nil
        and apply.Type=='ISApplyBandage' and apply.doIt==true and apply.item==item and #q.queue==3,
        'native MHP replacement expands removal then exact fresh-bandage application before the tail')
    assert(adapter.inspect(remove) and adapter.inspect(apply) and remove.toolkitQueueOperation==apply.toolkitQueueOperation
        and pending.toolkitQueueOperation==apply.toolkitQueueOperation,'replacement stages retain one shared medical intent')
    assert(not adapter.canSkip(remove),'replacement removal remains valid while the selected fresh supply and dirty bandage are present')
    assert(policy.cancelReason(q,apply)=='dependent','a future replacement child cannot cancel independently of removal')
    local prior=f.player.inventory.items;f.player.inventory.items={}
    assert(adapter.canSkip(remove),'missing selected fresh bandage invalidates removal before a wound is exposed')
    f.player.inventory.items=prior
    body.covered=false
    assert(adapter.inspect(apply) and not adapter.canSkip(apply),'completed removal does not invalidate its existing future apply proof')
    assert(adapter.canSkip(remove),'already completed removal cannot repeat')
    local stale=apply.bodyPart;apply.bodyPart=clinicalWound('HApplyBandage')
    assert(not adapter.inspect(apply),'changed replacement child cannot treat a different wound');apply.bodyPart=stale
    remove,apply,pending,q,body,item,tail,bag=expandReplacement(true)
    local preparation=q.queue[2]
    assert(#q.queue==4 and preparation.Type=='ISInventoryTransferAction' and preparation.item==item
        and preparation.srcContainer==bag and preparation.destContainer==f.player.inventory
        and preparation.toolkitQueueOperation==remove.toolkitQueueOperation and adapter.canPreserveStop(preparation),
        'native replacement preserves its exact carried-bag pickup between removal and application')
    assert(not adapter.canSkip(remove),'fresh material remains available in its original carried bag before removal')
    local otherOwner=f.item('Base.Bag_DuffelBag');otherOwner.class='InventoryContainer'
    local otherBag={class='ItemContainer',getType=function()return 'bag'end,getContainingItem=function()return otherOwner end,
        getItemById=function(_,id)return id==item:getID() and item or nil end}
    item.getContainer=function()return otherBag end
    assert(adapter.canSkip(remove),'relocating fresh material to another carried bag must invalidate removal before the old pickup silently skips')
    item.getContainer=function()return bag end
    body.covered=false
    assert(adapter.inspect(apply),'carried replacement apply stays supported after removal')
    local prior=f.player.inventory.items;f.player.inventory.items={}
    assert(adapter.canSkip(apply),'lost fresh material cannot be replaced by the removed dirty bandage')
    f.player.inventory.items=prior
    -- At each stage, cancelling the remaining waiting group keeps completed body effects and the unrelated tail.
    for _,stage in ipairs({'parent','remove','pickup','apply'})do
        local current,after,parent,q,body,item,tail,bag=expandReplacement(stage=='pickup')
        if stage=='parent' then q=f.queue(waitingHead,parent,tail)
        else
            if stage=='pickup' then table.remove(q.queue,1);body.covered=false
            elseif stage=='apply' then table.remove(q.queue,1);body.covered=false end
            table.insert(q.queue,1,waitingHead);q.current=waitingHead
        end
        local target=q.queue[2]
        assert(PZSurvivorToolkit.ActionQueue.cancelOperation(q,target),'whole replacement can cancel remaining '..stage..' stage')
        assert(#q.queue==2 and q.queue[1]==waitingHead and q.queue[2]==tail,'cancel '..stage..' removes future replacement work and preserves unrelated queue')
        assert(body.covered==(stage=='parent' or stage=='remove'),'cancel '..stage..' never rolls back completed bandage removal')
    end
    for _,stage in ipairs({'remove','pickup','apply'})do
        local remove,apply,parent,q,body,item,tail=expandReplacement(stage=='pickup')
        if stage~='remove' then table.remove(q.queue,1);body.covered=false end
        q.current=q.queue[1];q.onCompleted=nil
        f.player.getCharacterActions=function()return {contains=function()return false end}end
        f.player.setIsFarming=function()end
        local current=q.current
        current.action={isStarted=function()return true end,finished=function()return false end,
            isForceComplete=function()return false end,forceStop=function()end}
        assert(PZSurvivorToolkit.ActionQueue.cancelOperation(q,current),'active replacement '..stage..' stage retains group cancellation')
        if stage=='pickup' then q:onCompleted(current)
        else current:stop();q:tick()end
        assert(q.current==tail and #q.queue==1 and current.toolkitQueueOperation.toolkitCancelled,
            'active '..stage..' cancellation removes all remaining replacement stages and resumes the unrelated tail')
        assert(body.covered==(stage=='remove'),'active '..stage..' cancellation never undoes completed removal')
    end
    local oldReader=getModFileReader
    adapter=freshHealth();treatment=loadMini()
    getModFileReader=function()return {readLine=function()end,close=function()end}end
    local original=treatment.doBodyPartContextMenu;adapter.installMiniHealth()
    assert(treatment.doBodyPartContextMenu==original,'unreviewed MHP source never installs producer hooks')
    getModFileReader=oldReader
    print('MiniHealthPlus contracts: 16 native branches, stable actor/helper proofs and two-phase replacement with exact material and group cancellation passed.')
else print('MiniHealthPlus native contracts SKIP (pass --wishlist-workshop-root).')end
