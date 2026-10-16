local root=assert(arg[1])
isClient=function()return false end
local function source(side,name) return assert(loadfile(root..'/'..side..'/'..name..'.lua'))() end
AllCases=source('shared','QueueHealthCases')
assert(#AllCases==28)
local TestSelection={kind='sp',mode='toolkit',cases={}}
for _,spec in ipairs(AllCases) do TestSelection.cases[#TestSelection.cases+1]=spec.id end
require=function(name)
 if name=='QueueTestSelection' then return TestSelection end
 if name=='QueueHealthCases' then return AllCases end
 error('unexpected selection dependency '..name)
end
Selection=source('shared','QueueHealthSelection');Cases=Selection.cases
local function select(kind,mode,ids)
 TestSelection.kind=kind;TestSelection.mode=mode;TestSelection.cases=ids
 local previous=require
 require=function(name) if name=='QueueTestSelection' then return TestSelection elseif name=='QueueHealthCases' then return AllCases end;return previous(name) end
 Selection=source('shared','QueueHealthSelection');Cases=Selection.cases
end

local id=0
isServer=function() return false end
BodyPartType={ForeArm_L=0}
local function values(items) return {size=function() return #items end,get=function(_,i) return items[i+1] end} end
function container()
 local result={items={}}
 function result:getItems() return values(self.items) end
 function result:Remove(item) for i,value in ipairs(self.items) do if value==item then table.remove(self.items,i);item.owner=nil;return end end end
 function result:setCapacity() end
 function result:AddItem(kind)
  if type(kind)=='table' then self.items[#self.items+1]=kind;kind.owner=self;return kind end
  id=id+1;local item={id=id,kind=kind,owner=self,uses=4,pages=100}
  function item:getID() return self.id end
  function item:getFullType() return self.kind end
  function item:getContainer() return self.owner end
  function item:setFavorite() end
  function item:getCurrentUses() return self.uses end
  if kind=='Base.Disinfectant' then item.fluid={amount=0.5,getAmount=function(self) return self.amount end};function item:getFluidContainer() return self.fluid end end
  function item:getNumberOfPages() return 100 end
  function item:setAlreadyReadPages(value) self.pages=value end
  function item:getAlreadyReadPages() return self.pages end
  if kind=='Base.Bag_Schoolbag' then item.inner=container();function item:getItemContainer() return self.inner end end
  self.items[#self.items+1]=item;return item
 end
 return result
end
instanceof=function(item,kind) return kind=='InventoryContainer' and item.inner~=nil end
function body()
 local result={}
 function result:RestoreToFullHealth() self.covered=false;self.stitch=false;self.shards=false;self.bullet=false;self.wash=false;self.splint=0;self.alcohol=0;self.comfrey=0;self.garlic=0;self.plantain=0;self.injured=false;self.deep=false;self.fracture=0;self.scratchFlag=false;self.scratchTime=0 end
 result:RestoreToFullHealth()
 function result:getIndex() return 0 end
 function result:getType() return {
  getBandageModel=function() return 'Base.Bandage_LeftLowerArm' end,
  getBiteWoundModel=function() return 'Base.Wound_LForearm_Bite_Male' end,
  getScratchWoundModel=function() return 'Base.Wound_LForearm_Scratch_Male' end,
  getCutWoundModel=function() return 'Base.Wound_LForearm_Laceration_Male' end} end
 function result:bitten() return false end
 function result:scratched() return self.scratchFlag end
 function result:isCut() return false end
 function result:getBiteTime() return 0 end
 function result:getScratchTime() return self.scratchTime end
 function result:getCutTime() return 0 end
 function result:bandaged() return self.covered end
 function result:stitched() return self.stitch end
 function result:haveGlass() return self.shards end
 function result:haveBullet() return self.bullet end
 function result:isNeedBurnWash() return self.wash end
 function result:getSplintFactor() return self.splint end
 function result:getAlcoholLevel() return self.alcohol end
 function result:getComfreyFactor() return self.comfrey end
 function result:getGarlicFactor() return self.garlic end
 function result:getPlantainFactor() return self.plantain end
 function result:HasInjury() return self.injured end
 function result:isDeepWounded() return self.deep end
 function result:getFractureTime() return self.fracture end
 function result:setScratched(value) self.injured=value;self.scratchFlag=value end
 function result:setScratchTime(value) self.scratchTime=value end
 function result:generateDeepWound() self.injured=true;self.deep=true end
 function result:setHaveGlass(value) self.shards=value end
 function result:setStitched(value) self.stitch=value end
 function result:setFractureTime(value) self.fracture=value;self.injured=value>0 end
 function result:setSplint(value,factor) self.splint=factor end
 function result:setSplintItem() end
 function result:generateDeepShardWound() self.injured=true;self.deep=true;self.shards=true end
 function result:setHaveBullet(value) self.bullet=value end
 function result:setBurnTime() end
 function result:setNeedBurnWash(value) self.wash=value end
 return result
end
function player(name)
 local current={name=name,inventory=container(),body=body(),worn={}}
 function current:getCharacterGender() return 'Male' end
 function current:getWornItems()
  local items=self.worn;return {size=function() return #items end,getItemByIndex=function(_,index) return items[index+1] end,
   remove=function(_,item) for i=#items,1,-1 do if items[i]==item then table.remove(items,i) end end end}
 end
 -- Native removeWornItem delegates to setWornItem(location,nil), which leaves multi-item BANDAGE/WOUND entries intact.
 function current:removeWornItem(item) end
 function current:resetModelNextFrame() self.modelReset=true end
 function current:onWornItemsChanged() self.wornChanged=true end
 function current:getUsername() return self.name end
 function current:getInventory() return self.inventory end
 function current:teleportTo(x,y,z) self.x,self.y,self.z=x,y,z end
 function current:setX(x) self.x=x end
 function current:setY(y) self.y=y end
 function current:setZ(z) self.z=z end
 function current:setLastX() end;function current:setLastY() end;function current:setLastZ() end
 function current:setCurrentSquareFromPosition() end
 function current:setAlreadyReadPages() end
 function current:getBodyDamage() local target=self.body;return {getBodyPart=function() return target end,SetBandaged=function(_,_,flag) target.covered=flag;if flag then target.scratchFlag=false end end,setBodyPartsLastState=function() end} end
 return current
end
function addVisual(actor,kind)
 local item=actor.inventory:AddItem(kind);actor.worn[#actor.worn+1]=item;return item
end
function fixtureVisuals(actor)
 local target=actor.body
 if target.covered then addVisual(actor,'Base.Bandage_LeftLowerArm');addVisual(actor,'Base.Bandage_LeftLowerArm') end
 if target.scratchFlag then addVisual(actor,'Base.Wound_LForearm_Scratch_Male') end
end
function removeVisual(actor,kind)
 for i=#actor.worn,1,-1 do local item=actor.worn[i]
  if item.kind==kind then actor:getWornItems():remove(item);item.owner:Remove(item);return end
 end
 error('expected native model missing '..kind)
end
function medicalVisualEffect(actor,handler)
 if handler=='HApplyBandage' then
  if actor.body.scratchFlag then removeVisual(actor,'Base.Wound_LForearm_Scratch_Male') end
  actor.body.covered=true;actor.body.scratchFlag=false
  addVisual(actor,'Base.Bandage_LeftLowerArm');addVisual(actor,'Base.Bandage_LeftLowerArm')
 elseif handler=='HRemoveBandage' then
  removeVisual(actor,'Base.Bandage_LeftLowerArm');removeVisual(actor,'Base.Bandage_LeftLowerArm');actor.body.covered=false
  if actor.body.scratchTime>0 then actor.body.scratchFlag=true;addVisual(actor,'Base.Wound_LForearm_Scratch_Male') end
 end
end
require=function(name)
 if name=='QueueHealthSelection' then return Selection end
 if name=='QueueHealthCases' then return AllCases end
 assert(name=='QueueEnergyPlacement')
 return function() return {getX=function() return 10 end,getY=function() return 10 end,getZ=function() return 0 end} end
end

AuthorityRequire=require
Authority=source('shared','QueueHealthAuthority')

local actor=player('sp');local identity=Authority.setup(actor)
local orphan=addVisual(actor,'Base.Bandage_LeftLowerArm');actor.inventory:Remove(orphan)
actor:removeWornItem(orphan);assert(#actor.worn==1,'mock lost native multi-item removeWornItem no-op semantics')
assert(Authority.setup(actor)==identity,'setup identity changed')
local function bad(fn) assert(not pcall(fn),'invalid authority transition accepted') end
bad(function() Authority.prepare(actor,'stitchApply') end)
local function books() for _,item in ipairs(actor.inventory.items) do if item.kind:find('Base.Book',1,true) then item.pages=100 end end end
local function byID(id)
 for _,item in ipairs(actor.inventory.items) do if item.id==id then return item end end
end
local prep=Authority.prepare(actor,'bandageApply');assert(#actor.worn==0 and actor.modelReset and actor.wornChanged,'fixture did not remove orphan through native worn collection/reset callbacks');fixtureVisuals(actor);Authority.baseline(actor,'bandageApply')
bad(function() Authority.prepare(actor,'bandageApply') end)
bad(function() Authority.mutate(actor,'bandageRemove','missing') end)
assert(not Authority.verify(actor,'bandageApply').ok,'unperformed native effect accepted')
local used=byID(prep.items.bandage);actor.inventory:Remove(used);medicalVisualEffect(actor,'HApplyBandage');books()
assert(Authority.verify(actor,'bandageApply').ok,'valid exact native apply receipt rejected')
bad(function() Authority.verify(actor,'bandageApply') end)
prep=Authority.prepare(actor,'bandageRemove')
assert(#actor.worn==0,'prior output inventory deletion left orphan bandage models worn before recreation')
fixtureVisuals(actor);Authority.baseline(actor,'bandageRemove');medicalVisualEffect(actor,'HRemoveBandage');actor.inventory:AddItem('Base.Bandage');books()
assert(Authority.verify(actor,'bandageRemove').ok,'valid exact removal output receipt rejected')
prep=Authority.prepare(actor,'disinfect');fixtureVisuals(actor);Authority.baseline(actor,'disinfect');local alcohol=byID(prep.items.alcohol);alcohol.fluid.amount=alcohol.fluid.amount-0.15;actor.body.alcohol=4;books()
assert(Authority.verify(actor,'disinfect').ok,'valid exact use receipt rejected')
-- A fresh authority copy allows independent negative checks without manufacturing completion state.

local actor=player('all');Authority.setup(actor)
for i,spec in ipairs(Cases) do
 if not spec.remote then
  local prep=Authority.prepare(actor,spec.id)
  assert(#actor.worn==0,'fixture reset retained prior worn cosmetic despite exact output cleanup')
  fixtureVisuals(actor);Authority.baseline(actor,spec.id)
  local priorVisuals={};for _,item in ipairs(actor.worn) do priorVisuals[#priorVisuals+1]=item end
  local function find(container,id)
   for _,item in ipairs(container.items) do
    if item.id==id then return item end
    if item.inner then local value=find(item.inner,id);if value then return value end end
   end
  end
  local cancelled=spec.cancel or (spec.guard and spec.guard~='helper') or spec.expanded
  if spec.guard=='missing' or spec.expanded=='missing' then
   Authority.mutate(actor,spec.id,'missing')
   assert(not find(actor.inventory,prep.items.bandage),'explicit missing ID remained')
   assert(not pcall(Authority.mutate,actor,spec.id,'missing'),'duplicate mutation accepted')
  elseif not cancelled then
   for _,entry in ipairs(spec.supply or {}) do
    local item=find(actor.inventory,prep.items[entry[1]])
    if entry[3]=='remove' then item.owner:Remove(item)
    elseif entry[3]=='use' then item.uses=item.uses-1
    elseif entry[3]=='fluid' then item.fluid.amount=item.fluid.amount-0.15 end
   end
   for kind,count in pairs(spec.output or {}) do for n=1,count do actor.inventory:AddItem(kind) end end
   local target=actor.body
   if spec.handler=='HApplyBandage' or spec.handler=='HRemoveBandage' then medicalVisualEffect(actor,spec.handler) end
   if spec.handler=='HApplyBandage' then target.covered=true
   elseif spec.handler=='HRemoveBandage' then target.covered=false
   elseif spec.handler=='HDisinfect' then target.alcohol=4
   elseif spec.handler=='HStitch' then target.stitch=true
   elseif spec.handler=='HRemoveStitch' then target.stitch=false
   elseif spec.handler=='HSplint' then target.splint=1
   elseif spec.handler=='HRemoveSplint' then target.splint=0
   elseif spec.handler=='HRemoveGlass' then target.shards=false
   elseif spec.handler=='HRemoveBullet' then target.bullet=false
   elseif spec.handler=='HCleanBurn' then target.wash=false
   elseif spec.handler=='HApplyComfrey' then target.comfrey=1
   elseif spec.handler=='HApplyGarlic' then target.garlic=1
   elseif spec.handler=='HApplyPlantain' then target.plantain=1 end
  end
  for _,item in ipairs(actor.inventory.items) do if item.kind:find('Base.Book',1,true) then item.pages=100 end end
  if spec.id=='bandageRemove' then
   local original=priorVisuals[1];assert(original.kind=='Base.Bandage_LeftLowerArm')
   actor.inventory:AddItem(original);actor.worn[#actor.worn+1]=original
   assert(not Authority.verify(actor,spec.id).ok,'one retained original bandage visual passed full native removal receipt')
   actor:getWornItems():remove(original);actor.inventory:Remove(original)
  end
  if spec.id=='bandageApply' then
   local extra=actor.inventory:AddItem('Base.Hammer')
   assert(not Authority.verify(actor,spec.id).ok,'unexpected ordinary item output was ignored');actor.inventory:Remove(extra)
   local front=find(actor.inventory,prep.front);actor.inventory:Remove(front)
   assert(not Authority.verify(actor,spec.id).ok,'deleted unrelated original ID was ignored');actor.inventory:AddItem(front)
   local third=addVisual(actor,'Base.Bandage_LeftLowerArm')
   assert(not Authority.verify(actor,spec.id).ok,'third native bandage visual passed exact count2 receipt');actor:getWornItems():remove(third);actor.inventory:Remove(third)
  end
  if spec.id=='expandedCancel' then
   local needle=find(actor.inventory,prep.items.needle);local original=needle:getContainer()
   original:Remove(needle);actor.inventory:AddItem(needle)
   assert(not Authority.verify(actor,spec.id).ok,'cancelled bag input retained in root passed exact return receipt')
   actor.inventory:Remove(needle);original:AddItem(needle)
  end
  local result=Authority.verify(actor,spec.id);assert(result.ok,result.error)
 end
end
for _,spec in ipairs(AllCases) do if spec.remote then assert(Authority.skip(actor,spec.id,Selection.skipReason(spec,'all')).ok) end end

local value=body();value.injured=true;value.deep=true;value.fracture=21
local receipt=Authority.readiness(value)
assert(receipt.injured and receipt.deep and receipt.fractured and not receipt.comfrey and Authority.clinicalReady(value,receipt),'fresh clinical categories differ')
value.injured=false;assert(not Authority.clinicalReady(value,receipt),'stale healthy remote snapshot passed injury readiness');value.injured=true
value.deep=false;assert(not Authority.clinicalReady(value,receipt),'stale non-deep remote snapshot passed readiness');value.deep=true
value.fracture=0;assert(not Authority.clinicalReady(value,receipt),'stale unfractured remote snapshot passed readiness');value.fracture=20
assert(Authority.clinicalReady(value,receipt),'decaying positive fracture timer blocked categorical readiness')
value.plantain=1;assert(not Authority.clinicalReady(value,receipt),'stale poultice presence passed readiness')
receipt=Authority.readiness(value);value.plantain=2;assert(Authority.clinicalReady(value,receipt),'changing positive poultice factor blocked categorical readiness')

print('PASS exact authority effects, medicine/item/body/book receipts and negative integrity checks')
local actor=player('bag-ui');local identity=Authority.setup(actor);local bag
for _,item in ipairs(actor.inventory.items) do if item.id==identity.items.bag then bag=item end end
local visible,refreshes=false,0
function actor:getPlayerNum() return 0 end
function actor:setSecondaryHandItem(value) self.secondary=value end
function actor:getSecondaryHandItem() return self.secondary end
getPlayerInventory=function()return {refreshBackpacks=function()refreshes=refreshes+1;visible=actor.secondary==bag end} end
ISInventoryPaneContextMenu={getContainers=function()return {contains=function(_,container)return visible and container==bag.inner end} end}
PZSurvivorToolkit={ActionQueuePolicy={isCarriedContainer=function(container,character)return character==actor and container==bag.inner and bag.owner==actor.inventory end}}
Authority.setBagHand(actor,bag,bag);assert(visible and actor.secondary==bag and refreshes==1,'native UI hand/refresh did not expose the carried bag')
Authority.setBagHand(actor,bag,nil);assert(not visible and not actor.secondary and refreshes==2,'native UI hand/refresh did not hide the carried bag')
getPlayerInventory=function()return {refreshBackpacks=function()end} end
assert(not pcall(Authority.setBagHand,actor,bag,bag),'stale native container getter accepted exposure')
bag.owner={};assert(not pcall(Authority.setBagHand,actor,bag,nil),'removed schoolbag accepted carried fixture setup')

ScenarioSource=assert(io.open(root..'/client/QueueHealthScenarios.lua')):read('*a')

require=function(name) if name=='QueueHealthSelection' then return Selection elseif name=='QueueHealthCases' then return AllCases elseif name=='QueueHealthAuthority' then return Authority end;return {} end
local actor=player('readiness');local identity=Authority.setup(actor)
function actor:getX() return self.x end;function actor:getY() return self.y end;function actor:getZ() return self.z end
local noSquare,moving,dark=false,false,false
function actor:getCurrentSquare()
 if noSquare then return nil end
 return {getX=function() return math.floor(actor.x) end,getY=function() return math.floor(actor.y) end,getZ=function() return actor.z end}
end
function actor:isPlayerMoving() return moving end;function actor:pressedMovement() return false end
function actor:tooDarkToRead() return dark end;function actor:isTimedActionInstant() return false end
getPlayer=function() return actor end
BodyPartType.FromIndex=function(index) return index end
Translator={getLanguage=function() return {name=function() return 'EN' end} end}
PZSurvivorToolkit={Settings={actionQueue=function() return true end},ActionQueue={},ActionQueuePolicy={setDiagnostics=function() end},ActionQueueOperations={}}
local now,entered=0,0;getTimestampMs=function() return now end
ISHealthPanel={new=function() entered=entered+1;error('REACHED_VERIFIED_PANEL_GATE') end}
local stages,prepared,baselines={},{},{}
local function send(command,args)
 if command=='Prepare' then prepared[args.phase]=Authority.prepare(actor,args.phase)
 elseif command=='Baseline' then fixtureVisuals(actor);baselines[args.phase]=Authority.baseline(actor,args.phase)
 else error('unexpected readiness command '..command) end
end
local scenario=assert(loadstring(ScenarioSource))()
scenario(function(name,fn,ready) stages[#stages+1]={fn=fn,ready=ready} end,function() return {} end,function() return true end,
 {kind='sp',language='EN',ids=function() return identity end,preparations=prepared,baselines=baselines,send=send})
stages[1].fn();local gate=stages[2].fn
assert(gate()==false and gate()==false,'request/one-time doctor positioning did not wait')
assert(gate()==false);now=499;assert(gate()==false and entered==0,'panel opened before 500ms stability')
actor.body.injured=false;assert(gate()==false and entered==0,'stale injury snapshot opened native panel')
actor.body.injured=true;now=500;assert(gate()==false)
noSquare=true;assert(gate()==false and entered==0,'missing patient square opened native panel');noSquare=false
now=1000;assert(gate()==false);moving=true;assert(gate()==false and entered==0,'moving patient opened native panel');moving=false
now=1500;assert(gate()==false);actor.x=actor.x+0.3;assert(gate()==false and entered==0,'uncentered patient opened native panel');actor.x=identity.spawn.x
now=2000;assert(gate()==false);dark=true;assert(gate()==false and entered==0,'dark reading sample retained readiness');dark=false
now=2500;assert(gate()==false);now=2999;assert(gate()==false and entered==0)
now=3000;assert(gate()==false,'native panel opened before delayed inventory baseline receipt');now=3001;local ok,problem=pcall(gate)
assert(not ok and tostring(problem):find('REACHED_VERIFIED_PANEL_GATE',1,true) and entered==1,'500ms valid categorical/position samples never reached panel gate')

print('PASS actual readiness gates and hidden carried bag helper')

require=AuthorityRequire
select('sp','toolkit',{'expandedCancel','missingChildSupply'})
Authority=source('shared','QueueHealthAuthority')

require=function(name) if name=='QueueHealthSelection' then return Selection elseif name=='QueueHealthAuthority' then return Authority elseif name=='QueueEnergyPlacement' then return AuthorityRequire(name) end;return {} end
local actor=player('bag-observer');local identity=Authority.setup(actor)
function actor:getPlayerNum() return 0 end
function actor:getX() return self.x end;function actor:getY() return self.y end;function actor:getZ() return self.z end
function actor:getCurrentSquare()return {getX=function()return math.floor(actor.x)end,getY=function()return math.floor(actor.y)end,getZ=function()return actor.z end}end
function actor:isPlayerMoving()return false end;function actor:pressedMovement()return false end
function actor:tooDarkToRead()return false end;function actor:isTimedActionInstant()return false end
function actor:getSecondaryHandItem()return self.secondary end;function actor:setSecondaryHandItem(value)self.secondary=value end
getPlayer=function()return actor end
local bag;for _,item in ipairs(actor.inventory.items)do if item.id==identity.items.bag then bag=item end end
local visible,observer,now,cancels,mutations=false,nil,0,0,0
getTimestampMs=function()return now end
local q={queue={}};function q:indexOf(target)for index,value in ipairs(self.queue)do if value==target then return index end end end
local parent,handler,prepared,baselines,receipts={},{},{},{},{}
ISReadABook={getDuration=function()end}
local ui={refreshBackpacks=function()visible=actor.secondary==bag end}
getPlayerInventory=function()return ui end
ISInventoryPaneContextMenu={getContainers=function()return {contains=function(_,container)return visible and container==bag.inner end}end,
 onLiteratureItems=function(items)q.queue[#q.queue+1]={Type='ISReadABook',item=items[1],getDuration=ISReadABook.getDuration,minutesPerPage=2.0}end}
PZSurvivorToolkit={Settings={actionQueue=function()return true end},
 ActionQueuePolicy={setDiagnostics=function()end,isCarriedContainer=function(container,character)return container==bag.inner and character==actor and bag.owner==actor.inventory end,
 inspect=function()return {targets={[actor.body]=true},dynamicInputsByType={SutureNeedleHolder=true}}end},
 ActionQueueDefinitions={describe=function()return {title='native',target='patient/body'}end},
 ActionQueueOperations={run=function(fn,...)return fn(...)end},
 ActionQueue={cancelOperation=function(queue,action)
  assert(action.Type=='ISInventoryTransferAction' and action.action:isStarted(),'cancel ran before native prep start')
  assert(not visible and bag.owner==actor.inventory,'cancel did not hide its carried return destination first');cancels=cancels+1;return true
 end}}
local context={hideAndChildren=function()end}
ISHealthPanel={new=function()return {initialise=function()end,doBodyPartContextMenu=function()
 context.options={{target={Type=handler},param1=handler=='HStitch' and 'Base.Needle' or 'Base.Bandage',param2=handler=='HStitch' and 'Base.Thread' or nil,
 onSelect=function()parent={Type='HealthPanelAction',toolkitQueueOperation={}};q.queue[#q.queue+1]=parent end}}
end}end}
getPlayerContextMenu=function()return context end
Events={OnPlayerUpdate={Add=function(callback)observer=callback end,Remove=function(callback)assert(observer==callback);observer=nil end}}
local function send(command,args)
 if command=='Prepare' then prepared[args.phase]=Authority.prepare(actor,args.phase);handler=args.phase=='expandedCancel' and 'HStitch' or 'HApplyBandage'
 elseif command=='Baseline' then fixtureVisuals(actor);baselines[args.phase]=Authority.baseline(actor,args.phase)
 elseif command=='Mutate' then mutations=mutations+1;Authority.mutate(actor,args.phase,args.mode)
 else error('unexpected observer selfcheck command '..command)end
end
local stages={}
assert(loadstring(ScenarioSource))()(function(name,fn,ready)stages[#stages+1]={fn=fn}end,function()return q end,function()return #q.queue==0 end,
 {kind='sp',language='EN',ids=function()return identity end,preparations=prepared,baselines=baselines,receipts=receipts,send=send})
stages[1].fn()
local function enqueue(index)
 local run=stages[index].fn
 assert(run()==false and run()==false and run()==false);now=now+500
 assert(run()==false);now=now+1;assert(run()==false)
 assert(visible and actor.secondary==bag and #q.queue==3,'bag not exposed before actual scenario menu producer')
 return run
end
local run=enqueue(2)
local started=false
local transfer={Type='ISInventoryTransferAction',toolkitQueueOperation=parent.toolkitQueueOperation,action={isStarted=function()return started end,finished=function()return false end}}
local clinical={Type='ISStitch',toolkitQueueOperation=parent.toolkitQueueOperation}
q.queue={transfer,clinical,q.queue[3]};observer(actor)
assert(visible and cancels==0,'unstarted prep hid bag or triggered expanded cancel')
started=true;observer(actor);assert(not visible and cancels==1,'started prep did not hide bag and trigger exact cancel')
q.queue={};assert(run()==false and run()==false,'expanded cancel observer did not record interception')
for _,item in ipairs(actor.inventory.items)do if item.kind:find('Base.Book',1,true)then item.pages=100 end end
assert(Authority.verify(actor,'expandedCancel').ok)
run=enqueue(3)
transfer={Type='ISInventoryTransferAction',toolkitQueueOperation=parent.toolkitQueueOperation,action={isStarted=function()return true end,finished=function()return false end}}
clinical={Type='ISApplyBandage',toolkitQueueOperation=parent.toolkitQueueOperation}
q.queue={transfer,clinical,q.queue[3]};observer(actor)
assert(not visible and mutations==1,'missing-child probe did not wait for hidden bag behind started native prep')
observer(actor);assert(mutations==1,'missing-child mutation repeated')

print('PASS actual scenario started-prep bag cancellation and missing-child observer')

-- Exact selection, skips and control receipts are exercised against the shipped code.
do
 require=AuthorityRequire
 select('mp','native',{'nativeStop','remoteRemoved'})
 local selected=Selection
 assert(#selected.cases==2 and selected.cases[1].id=='nativeStop' and selected.cases[2].id=='remoteRemoved')
 assert(not selected.skipReason(selected.cases[1],'client1'))
 assert(selected.skipReason(selected.cases[2],'client1') and not selected.skipReason(selected.cases[2],'client2'))
 for _,invalid in ipairs({{}, {'unknown'}, {'nativeStop','nativeStop'}}) do
  assert(not pcall(select,'sp','toolkit',invalid),'invalid medical selection accepted')
 end
 select('sp','native',{'waitingCancel','remoteRemoved'})
 Authority=source('shared','QueueHealthAuthority')
 local actor=player('skip')
 Authority.setup(actor)
 assert(not pcall(Authority.prepare,actor,'waitingCancel'),'queue-only control silently executed')
 assert(not pcall(Authority.skip,actor,'remoteRemoved','arbitrary'),'out-of-order skip accepted')
 assert(not pcall(Authority.skip,actor,'waitingCancel','arbitrary'),'invented skip reason accepted')
 assert(Authority.skip(actor,'waitingCancel',Selection.skipReason(Selection.cases[1],'skip')).ok)
 assert(Authority.skip(actor,'remoteRemoved',Selection.skipReason(Selection.cases[2],'skip')).ok)
 assert(not pcall(Authority.skip,actor,'remoteRemoved','duplicate'),'duplicate skip accepted')
 for _,mode in ipairs({'native','toolkit'}) do
  select('sp',mode,{'nativeStop'})
  Authority=source('shared','QueueHealthAuthority')
  local actor=player('tail-'..mode);Authority.setup(actor)
  local prep=Authority.prepare(actor,'nativeStop');fixtureVisuals(actor);Authority.baseline(actor,'nativeStop')
  for _,book in ipairs(actor.inventory.items) do if book.id==prep.front then book.pages=100 end end
  -- The real native stop may clear unrelated tail work; toolkit must retain it.
  if mode=='toolkit' then
   assert(not Authority.verify(actor,'nativeStop').ok,'toolkit accepted cancelled tail')
   for _,book in ipairs(actor.inventory.items) do if book.id==prep.tail then book.pages=100 end end
  end
  local result=Authority.verify(actor,'nativeStop');assert(result.ok,result.error)
  assert(result.outcome.tailCompleted==(mode=='toolkit') and result.outcome.tailPages==(mode=='toolkit' and 100 or 99))
 end
end
print('PASS exact ordered subsets; duplicate/unknown/empty selection and invented/out-of-order skips rejected; native observed tail differs while toolkit remains strict')

-- Execute actual native control producer and stop observer with toolkit APIs forbidden.
do
 require=AuthorityRequire
 select('sp','native',{'nativeStop'})
 Authority=source('shared','QueueHealthAuthority')
 local actor=player('native-control');local identity=Authority.setup(actor)
 function actor:getPlayerNum() return 0 end
 function actor:getX() return self.x end;function actor:getY() return self.y end;function actor:getZ() return self.z end
 function actor:getCurrentSquare()return {getX=function()return math.floor(actor.x)end,getY=function()return math.floor(actor.y)end,getZ=function()return actor.z end}end
 function actor:isPlayerMoving()return false end;function actor:pressedMovement()return false end
 function actor:tooDarkToRead()return false end;function actor:isTimedActionInstant()return false end
 getPlayer=function()return actor end
 local now,observer,stopped=0,nil,false
 getTimestampMs=function()return now end
 local q={queue={}};function q:indexOf(target)for i,value in ipairs(self.queue)do if value==target then return i end end end
 local prepared,baselines,receipts,skips={},{},{},{}
 local function forbidden()error('toolkit API used by native control')end
 PZSurvivorToolkit={Settings={actionQueue=function()return false end},ActionQueue={cancelOperation=forbidden},
  ActionQueuePolicy={inspect=forbidden,setDiagnostics=forbidden},ActionQueueOperations={run=forbidden}}
 ISReadABook={getDuration=function()end}
 ISInventoryPaneContextMenu={onLiteratureItems=function(items)q.queue[#q.queue+1]={Type='ISReadABook',item=items[1],getDuration=ISReadABook.getDuration,minutesPerPage=2.0}end}
 local context={hideAndChildren=function()end}
 ISHealthPanel={new=function()return {initialise=function()end,doBodyPartContextMenu=function()
  context.options={{target={Type='HDisinfect'},param1='Base.Disinfectant',onSelect=function()q.queue[#q.queue+1]={Type='HealthPanelAction'}end}}
 end}end}
 getPlayerContextMenu=function()return context end
 Events={OnPlayerUpdate={Add=function(callback)observer=callback end,Remove=function(callback)assert(observer==callback);observer=nil end}}
 require=function(name)
  if name=='QueueHealthSelection'then return Selection elseif name=='QueueHealthAuthority'then return Authority
  elseif name=='QueueEnergyPlacement'then return AuthorityRequire(name)end;return {}end
 local function send(command,args)
  if command=='Prepare'then prepared[args.phase]=Authority.prepare(actor,args.phase)
  elseif command=='Baseline'then fixtureVisuals(actor);baselines[args.phase]=Authority.baseline(actor,args.phase)
  elseif command=='Verify'then receipts[args.phase]=Authority.verify(actor,args.phase)
  else error('unexpected control command '..command)end
 end
 local stages={}
 source('client','QueueHealthScenarios')(function(name,fn,ready,id)stages[#stages+1]={fn=fn,id=id}end,
  function()return q end,function()return #q.queue==0 end,
  {kind='sp',language='EN',ids=function()return identity end,preparations=prepared,baselines=baselines,receipts=receipts,skips=skips,send=send})
 assert(#stages==3 and stages[2].id=='nativeStop')
 stages[1].fn()
 PZSurvivorToolkit.Settings.actionQueue=function()return true end
 assert(not pcall(stages[1].fn),'control with enabled queue passed setup')
 assert(not pcall(stages[2].fn),'control with enabled queue passed case mode gate')
 PZSurvivorToolkit.Settings.actionQueue=function()return false end
 local run=stages[2].fn
 assert(run()==false and run()==false and run()==false);now=500;assert(run()==false);now=501;assert(run()==false)
 assert(#q.queue==3 and q.queue[2].Type=='HealthPanelAction','control failed to use raw native menu and reading producer')
 local class={stop=function()end,complete=function()end}
 local child=setmetatable({Type='ISDisinfect',bodyPart=actor.body,action={isStarted=function()return true end,finished=function()return false end},
  forceStop=function()stopped=true;q.queue={}end},{__index=class})
 -- The audited native methods must be the actual inherited class methods.
 getmetatable(child).stop=class.stop;getmetatable(child).complete=class.complete
 q.queue={child,q.queue[3]}
 for _,book in ipairs(actor.inventory.items)do if book.id==prepared.nativeStop.front then book.pages=100 end end
 observer(actor);assert(stopped,'native child forceStop was not called')
 assert(run()==false and run()==false);now=1502;assert(run()==false)
 local result=run();assert(result.status=='passed' and result.outcome.tailCompleted==false,'native cleared tail was misreported')
end
print('PASS actual native menu/reading bypass toolkit run/policy/cancel; disabled setting enforced and real forceStop records cleared tail')

-- The small event writer produces valid JSON with real escaping and booleans.
local writer=source('shared','QueueHealthEvents')
print('EVENT_JSON '..writer.encode({event='case',id='nativeStop',status='passed',reason='quote" slash\\ newline\n',outcome={tailCompleted=false,tailPages=99},cases={'nativeStop','remoteRemoved'}}))

-- The server advances only the exact chosen cases, including an honest EN skip.
do
 require=AuthorityRequire
 select('mp','native',{'nativeStop','remoteRemoved'})
 isServer=function()return true end
 sendAddItemToContainer=function()end;sendRemoveItemFromContainer=function()end
 sendServerCommand=function()end;syncBodyPart=function()end
 local first,second=player('client1'),player('client2')
 local online={first,second}
 getOnlinePlayers=function()return {size=function()return #online end,get=function(_,i)return online[i+1]end}end
 Authority=source('shared','QueueHealthAuthority')
 Authority.setup(first);Authority.setup(second)
 assert(not pcall(Authority.finish,first),'server accepted missing selected cases')
 assert(not pcall(Authority.prepare,second,'nativeStop'),'inactive doctor prepared fixture')
 local function finishStop(actor)
  local prep=Authority.prepare(actor,'nativeStop');Authority.baseline(actor,'nativeStop')
  for _,item in ipairs(actor.inventory.items)do if item.id==prep.front then item.pages=100 end end
  assert(Authority.verify(actor,'nativeStop').ok)
 end
 finishStop(first)
 assert(not pcall(Authority.finish,first),'server counted missing selected remoteRemoved as pass')
 local reason=Selection.skipReason(Selection.cases[2],'client1')
 assert(Authority.skip(first,'remoteRemoved',reason).ok)
 Authority.finish(first)
 assert(Authority.session(second).active,'server did not activate second selected-case doctor')
 finishStop(second)
 local prep=Authority.prepare(second,'remoteRemoved');Authority.baseline(second,'remoteRemoved')
 online={second}
 for _,item in ipairs(second.inventory.items)do if item.id==prep.front then item.pages=100 end end
 local receipt=Authority.verify(second,'remoteRemoved');assert(receipt.ok and not receipt.outcome.tailCompleted,receipt.error)
 Authority.finish(second)
 isServer=function()return false end
end
print('PASS actual MP authority exact two-case sessions, inactive/out-of-order completion rejection, explicit EN skip and final disconnect receipt')

-- A native disconnect stall is observed before fixture cleanup, never counted as drained.
do
 require=AuthorityRequire
 select('mp','native',{'remoteRemoved'})
 isServer=function()return true end
 local patientActor,doctor=player('client1'),player('client2')
 local online={patientActor,doctor}
 getOnlinePlayers=function()return {size=function()return #online end,get=function(_,i)return online[i+1]end}end
 Authority=source('shared','QueueHealthAuthority')
 Authority.setup(patientActor);local identity=Authority.setup(doctor)
 Authority.skip(patientActor,'remoteRemoved',Selection.skipReason(Selection.cases[1],'client1'));Authority.finish(patientActor)
 for _,actor in ipairs({patientActor,doctor}) do
  function actor:getPlayerNum()return 0 end
  function actor:getX()return self.x end;function actor:getY()return self.y end;function actor:getZ()return self.z end
  function actor:getCurrentSquare()return {getX=function()return math.floor(actor.x)end,getY=function()return math.floor(actor.y)end,getZ=function()return actor.z end}end
  function actor:isPlayerMoving()return false end;function actor:pressedMovement()return false end
  function actor:tooDarkToRead()return false end;function actor:isTimedActionInstant()return false end
  function actor:startReceivingBodyDamageUpdates()end
  function actor:getBodyDamageRemote()return self:getBodyDamage()end
 end
 getPlayer=function()return doctor end
 local now,stops=0,0;getTimestampMs=function()return now end
 local q={queue={}};function q:indexOf(target)for i,value in ipairs(self.queue)do if value==target then return i end end end
 local prepared,baselines,receipts={},{},{}
 local function forbidden()error('toolkit API used by native disconnect observation')end
 PZSurvivorToolkit={Settings={actionQueue=function()return false end},ActionQueue={cancelOperation=forbidden},
  ActionQueuePolicy={inspect=forbidden,setDiagnostics=forbidden},ActionQueueOperations={run=forbidden}}
 ISReadABook={getDuration=function()end}
 ISInventoryPaneContextMenu={onLiteratureItems=function(items)q.queue[#q.queue+1]={Type='ISReadABook',item=items[1],getDuration=ISReadABook.getDuration,minutesPerPage=2.0}end}
 local context={hideAndChildren=function()end}
 ISHealthPanel={new=function()return {initialise=function()end,setOtherPlayer=function()end,doBodyPartContextMenu=function()
  context.options={{target={Type='HApplyBandage'},param1='Base.Bandage',onSelect=function()q.queue[#q.queue+1]={Type='HealthPanelAction'}end}}
 end}end}
 getPlayerContextMenu=function()return context end
 Events={OnPlayerUpdate={Add=function()end,Remove=function()end}}
 require=function(name)
  if name=='QueueHealthSelection'then return Selection elseif name=='QueueHealthAuthority'then return Authority
  elseif name=='QueueEnergyPlacement'then return AuthorityRequire(name)end;return {}end
 local verifies=0
 local function send(command,args)
  if command=='Prepare'then prepared[args.phase]=Authority.prepare(doctor,args.phase)
  elseif command=='Baseline'then baselines[args.phase]=Authority.baseline(doctor,args.phase)
  elseif command=='Verify'then verifies=verifies+1;receipts[args.phase]=Authority.verify(doctor,args.phase)
  else error('unexpected disconnect command '..command)end
 end
 local stages={}
 source('client','QueueHealthScenarios')(function(name,fn,ready,id)stages[#stages+1]={fn=fn,id=id}end,
  function()return q end,function()return #q.queue==0 end,
  {kind='mp',language='EN',ids=function()return identity end,preparations=prepared,baselines=baselines,receipts=receipts,skips={},send=send})
 stages[1].fn();local run=stages[2].fn
 assert(run()==false and run()==false and run()==false and run()==false);now=500;assert(run()==false);now=501;assert(run()==false)
 local prep=prepared.remoteRemoved
 assert(#q.queue==3 and q.queue[1].item.pages==98 and q.queue[3].item.pages==99,'disconnect fixture changed native reading budget')
 local front,tail=q.queue[1],q.queue[3];front.item.pages=100
 local class={stop=function()end,complete=function()end}
 local bandage
 for _,value in ipairs(doctor.inventory.items)do if value.id==prep.items.bandage then bandage=value end end
 local child=setmetatable({Type='ISApplyBandage',character=doctor,otherPlayer=patientActor,bodyPart=patientActor.body,item=bandage,doIt=true,
  action={isStarted=function()return true end,finished=function()return false end},forceStop=function()stops=stops+1;q.queue={};q.current=nil end},{__index=class})
 getmetatable(child).stop=class.stop;getmetatable(child).complete=class.complete
 q.current=child;q.queue={child,tail}
 online={doctor};now=502;assert(run()==false,'actual peer absence should begin bounded observation')
 now=60501;assert(run()==false and stops==0 and verifies==0,'native stall stopped or passed before60s')
 now=60502
 child.Type='ISDisinfect';assert(not pcall(run) and stops==0,'wrong current action was cleaned as fixture bandage');child.Type='ISApplyBandage'
 child.otherPlayer=doctor;assert(not pcall(run) and stops==0,'unrelated patient action was cleaned');child.otherPlayer=patientActor
 child.item={};assert(not pcall(run) and stops==0,'wrong bandage action was cleaned');child.item=bandage
 front.item.pages=99;assert(not pcall(run) and stops==0,'unfinished original front was accepted as stalled medical operation');front.item.pages=100
 tail.item.pages=100;assert(not pcall(run) and stops==0,'already changed original tail accepted as known stall');tail.item.pages=99
 assert(run()==false and stops==1 and verifies==0,'valid observed stall did not stop only its owned clinical child')
 assert(run()==false and stops==1);now=61503;assert(run()==false and verifies==1)
 local result=run();assert(result.status=='passed' and result.outcome.nativeStallObserved and result.outcome.nativeCurrentType=='ISApplyBandage')
 assert(result.outcome.queueDrained==false and result.outcome.cleanupQueueDrained==true and result.outcome.nativeObservationMs==60000)
 assert(result.outcome.nativeTailCompletedBeforeCleanup==false and result.outcome.tailCompleted==false and result.outcome.nativeCleanup)
 assert(result.outcome.body.bandaged==false and bandage.owner==doctor.inventory,'observational cleanup changed authoritative medical effect/resource')
 isServer=function()return false end
end
print('PASS actual native disconnect60s observation before owned cleanup; wrong action/patient/supply/front/tail rejected; exact authority receipts retained and pre-cleanup stall remains explicit')
