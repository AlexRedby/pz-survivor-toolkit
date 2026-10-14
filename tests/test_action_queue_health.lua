if not NativeActionRoot then print('Health queue native contracts SKIP.');return end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
f.native('shared/ISBaseObject.lua')
ISHealthPanel={}
local file=assert(io.open(NativeActionRoot..'/client/XpSystem/ISUI/ISHealthPanel.lua'))
local source=file:read('*a'):gsub('\r','');file:close()
local first=assert(source:find('HealthPanelAction = ISBaseTimedAction:derive',1,true))
local last=assert(source:find('ISHealthPanel.ReceiveMedicalCheckRequest',first,true))
assert(loadstring(source:sub(first,last-1),'@media/lua/client/XpSystem/ISUI/ISHealthPanel.lua'))()
getFilenameOfClosure=function(callback) return debug.getinfo(callback,'S').source:gsub('^@','') end
getGameFilesInput=function()
    local reader=assert(io.open(NativeActionRoot..'/client/XpSystem/ISUI/ISHealthPanel.lua'))
    return {readLine=function() local line=reader:read('*l');return line and line:gsub('\r$','') end,close=function()reader:close()end}
end
local nativeReader = getGameFilesInput
local function loadChildren()
    for _,name in ipairs({'ISApplyBandage','ISDisinfect','ISStitch','ISSplint','ISRemoveGlass','ISRemoveBullet','ISCleanBurn',
        'ISComfreyCataplasm','ISGarlicCataplasm','ISPlantainCataplasm'}) do
        local path=NativeActionRoot..'/shared/TimedActions/'..name..'.lua'
        local reader=assert(io.open(path));local text=reader:read('*a');reader:close()
        assert(loadstring(text,'@'..path))()
    end
end
loadChildren()
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
ISInventoryPaneContextMenu.getContainers=function() return list({f.player.inventory}) end
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
panel.getDoctor=function() return f.player end
local function part()
    return setmetatable({covered=false,HasInjury=function() return true end,bandaged=function(self) return self.covered end,
        getSplintFactor=function() return 0 end,getFractureTime=function() return 0 end,getBurnTime=function() return 0 end},
        {__index=function() return function() return false end end})
end
local function request(body,kind,arg)
    panel:doBodyPartContextMenu(body,0,0)
    for _,option in ipairs(context.options) do
        if option.target and option.target.Type==kind then
            return HealthPanelAction:new(f.player,option.target,arg)
        end
    end
    error('native menu did not expose '..kind)
end
local body=part()
local disinfect=request(body,'HDisinfect','Base.Disinfectant')
local cover=request(body,'HApplyBandage','Base.Bandage')
disinfect.toolkitQueueOperation={};cover.toolkitQueueOperation={}
local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
local q=f.queue(head,disinfect,cover)
assert(health.inspect(disinfect) and health.inspect(cover),'native private handlers captured through producer')
assert(policy.moveReason(q,cover,disinfect)=='move_dependent')
assert(policy.moveReason(q,disinfect,cover,true)=='move_dependent')
assert(policy.cancelOperationReason(q,cover)=='operation_dependent')
assert(disinfect:isValid());body.covered=true;assert(not disinfect:isValid());body.covered=false
local independent=request(part(),'HApplyBandage','Base.Bandage');independent.toolkitQueueOperation={}
q=f.queue(head,disinfect,independent)
assert(not policy.moveReason(q,independent,disinfect) and not policy.moveReason(q,disinfect,independent,true))
assert(not policy.cancelOperationReason(q,independent),'independent waiting medical operation can cancel')
local sameSupply=request(part(),'HDisinfect','Base.Disinfectant');sameSupply.toolkitQueueOperation={}
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
removeGlass.toolkitQueueOperation={}
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
    for i=1,100 do
        local key,value=debug.getupvalue(ISHealthPanel.doBodyPartContextMenu,i)
        if not key then break end
        if key==name then return value end
    end
    error('missing native private handler '..name)
end
local function freshHealth(change)
    f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    f.native('shared/ISBaseObject.lua')
    ISHealthPanel={}
    assert(loadstring(source:sub(first,last-1),'@media/lua/client/XpSystem/ISUI/ISHealthPanel.lua'))()
    loadChildren()
    getGameFilesInput=nativeReader
    local class=privateHandler('HDisinfect')
    local parent=getmetatable(class).__index
    local restore=change and change(class,parent)
    f.project('ActionQueueOperations');f.project('ActionQueueDefinitions');f.project('ActionQueuePolicy')
    local adapter=f.project('ActionQueueHealth')
    setmetatable(panel,{__index=ISHealthPanel});panel.character=f.player
    f.player.inventory.getItems=function() return list({alcohol,bandage}) end
    ISInventoryPaneContextMenu.getContainers=function() return list({f.player.inventory}) end
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
