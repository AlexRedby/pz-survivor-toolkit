-- Offline consumer/fixture checks. A pass does not establish Host replication.
local client=ProjectRoot..'/tests/native_queue/warehouse-workload/client/'
local product=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'
local clock=1000
local language='EN'
getText=function(key)return language..':'..key end
getTimestampMs=function()return clock end
local function list(values)
 local a={values=values or {}};function a:size()return #self.values end;function a:get(i)return self.values[i+1]end
 function a:add(item)self.values[#self.values+1]=item end;return a
end
ArrayList={new=function()return list()end}
local function item(id,name)
 local i={id=id,name=name or 'Bandage',cat='FirstAid'}
 function i:getID()return self.id end;function i:getFullType()return 'Base.'..self.name end
 function i:getName()return self.name end;function i:getDisplayCategory()return self.cat end;function i:getCategory()return self.cat end
 function i:getContainer()return self.container end;return i
end
local function container(values)
 local c={values=values or {}};for _,i in ipairs(c.values)do i.container=c end
 function c:getItems()return list(self.values)end
 function c:getItemById(id)for _,i in ipairs(self.values)do if i.id==id then return i end end end
 function c:getType()return 'crate'end;return c
end
local old,replacement=item(1,'old'),item(2,'new');replacement.resolvedCategory='BCMappedFirstAid';local source=container({old});local root=container({item(3,'Nails')});local aggregate=container({old});old.container=source
local player={square={},dir=0}
function player:getInventory()return root end;function player:getPlayerNum()return 0 end;function player:getUsername()return 'client1'end
function player:getCurrentSquare()return self.square end;function player:getDir()return self.dir end;function player:getJoypadBind()return -1 end
function player:hasTimedActions()return false end;function player:isTimedActionInstant()return false end
getSpecificPlayer=function()return player end
local stats={rows=0,discoveries=0}
luautils={findRootInventory=function(c)return c end,countItemsRecursive=function(v)return #v[1].values end}
local Pane={};Pane.__index=Pane
function Pane:refreshContainer()
 stats.rows=stats.rows+1;self.itemslist={};self.refreshContainerCount=(self.refreshContainerCount or 0)+1
 for _,i in ipairs(self.inventory.values)do self.itemslist[#self.itemslist+1]={name=i.name,cat=i.resolvedCategory or i.cat,items={i,i},count=2}end
 return 'rows',nil,41
end
local Page={};Page.__index=Page
function Page:getIsVisible()return self.visible end
function Page:setVisible(v)self.visible=v;return 'visible',nil,17 end
function Page:updateItemCount()self.totalItems=#self.inventory.values end
function Page:refreshBackpacks()
 stats.discoveries=stats.discoveries+1;aggregate.values={};for _,i in ipairs(source.values)do aggregate.values[#aggregate.values+1]=i end
 self.inventoryPane:refreshContainer();self:updateItemCount();return 'discovery',nil,31
end
function Page:update()if self.lastSquare~=player.square then self:refreshBackpacks()end end
local selections=0
function Page:onBackpackClick(button)
 selections=selections+1;self.inventory=button.inventory;self.inventoryPane.inventory=button.inventory
 self.inventoryPane:refreshContainer();self:updateItemCount()
end
local pane=setmetatable({inventory=aggregate,mode='details',selected={},items={}},Pane)
local loot=setmetatable({player=0,visible=true,inventory=aggregate,inventoryPane=pane,backpacks={{inventory=source}}},Page)
local inv=setmetatable({player=0,onCharacter=true,visible=true,inventory=root,inventoryPane=setmetatable({inventory=root,mode='details',selected={},items={}},Pane)},Page)
local aggregateButton={inventory=aggregate,target=loot,onclick=function(owner,button)Page.onBackpackClick(owner,button)end}
local sourceButton={inventory=source,target=loot,onclick=function(owner,button)Page.onBackpackClick(owner,button)end}
loot.backpacks={aggregateButton,sourceButton}
getPlayerLoot=function()return loot end;getPlayerInventory=function()return inv end
local callbacks={};local function event()return {Add=function(fn)callbacks[#callbacks+1]=fn end}end
Events={OnGameBoot=event(),OnGameStart=event()};ISMouseDrag={};PZSurvivorToolkit={};ISInventoryPage=Page
local Model={item=function(i)return {cat=i.cat,key=i.name..':'..i.cat}end}
local classes={onToggle=function()end}
local modules={['BetterContainers/Proximity']={GetItemContainer=function()return aggregate end},['PZSurvivorToolkit/ManifestModel']=Model,
 ['BetterContainers/Categorize/InventoryCategory']={get=function(i)return i.resolvedCategory or i.cat end},
 ['PZSurvivorToolkit/InventoryClasses']=classes,['PZSurvivorToolkit/ItemCategories']={prepareContainer=function()end},['BetterContainers/_Options']={}}
local originalRequire=require
require=function(name)return modules[name]or {}end
table.wipe=function(t)for key in pairs(t)do t[key]=nil end end
local Refresh=dofile(product..'PZSurvivorToolkit/InventoryRefresh.lua');Refresh.install()
local queue={queue={}};ISTimedActionQueue={getTimedActionQueue=function()return queue end,add=function(a)queue.queue[#queue.queue+1]=a end}
local N=dofile(client..'WarehouseWorkloadNative.lua')
loot:refreshBackpacks();local nativeClassRefresh=Pane.refreshContainer;local nativePaneRefresh=pane.refreshContainer
local run=N.startObservation(player,{items={{id=1},{id=2},{id=3}},mode='clean'});run.state={stores={source}}
assert(Pane.refreshContainer==nativeClassRefresh and pane.refreshContainer==nativePaneRefresh,'counter observation changed callback ownership')
local initialRows=stats.rows
local hidden=N.hide(run);assert(hidden.rowsPending and not hidden.visible,'fixture failed to establish actual installed gate')
assert(stats.rows==initialRows,'counter observation disabled InventoryRefresh gate')
-- A peer swaps equal-count physical contents while the observer is hidden.
source.values={replacement};replacement.container=source
assert(not N.aggregateProof(run),'stale equal-count aggregate was accepted')
player.square={};loot:update()
assert(stats.rows==initialRows,'movement rebuilt hidden native rows')
local fresh=assert(N.aggregateProof(run));assert(fresh.actualIds[1]==2 and fresh.expectedIds[1]==2)
local beforeDiagnostic={rows=stats.rows,discoveries=stats.discoveries,callback=Pane.refreshContainer,gate=pane.refreshContainer}
local diagnostic=N.diagnostics(run)
assert(diagnostic.aggregateIds[1]==2 and diagnostic.buttons[2].ownedSlot==1 and diagnostic.buttons[2].itemIds[1]==2)
assert(stats.rows==beforeDiagnostic.rows and stats.discoveries==beforeDiagnostic.discoveries and Pane.refreshContainer==beforeDiagnostic.callback and pane.refreshContainer==beforeDiagnostic.gate,'wait diagnostic mutated native discovery or callback ownership')
-- A native movement/transfer may auto-select a physical crate. The reopen
-- callback selects the intended aggregate only after its freshness proof.
loot.inventory=source;pane.inventory=source
local selectionBefore=selections
local reopened=N.reopen(run,assert(N.aggregateProof(run)));assert(reopened.nativeRows and reopened.rowIds[1]==2 and reopened.totalItems==1)
assert(selections==selectionBefore+1 and reopened.selectedBound and reopened.selectedKind=='aggregate'and loot.inventory==aggregate and pane.inventory==aggregate,'reopen did not use the installed aggregate button callback')
local category=reopened.groups[1]
assert(category.category=='FirstAid'and category.groupCategory=='BCMappedFirstAid'and category.expectedGroupCategory=='BCMappedFirstAid','raw identity was conflated with the installed BC row category')
assert(category.itemCategories[1].id==2 and category.itemCategories[1].rawCategory=='FirstAid'and category.itemCategories[1].modelCategory=='FirstAid'and category.itemCategories[1].resolvedCategory=='BCMappedFirstAid')
assert(category.rawLocalizedCategory=='EN:IGUI_ItemCat_FirstAid')
language='RU';N.hide(run);reopened=N.reopen(run,assert(N.aggregateProof(run)))
assert(reopened.groups[1].category=='FirstAid'and reopened.groups[1].groupCategory=='BCMappedFirstAid'and reopened.groups[1].rawLocalizedCategory=='RU:IGUI_ItemCat_FirstAid','locale changed physical/resolved category identity')
language='EN'
assert(not reopened.after.rowsPending and stats.rows>initialRows,'native setVisible callback failed to flush fresh rows')
-- Stale rendered identity remains an error even when counts match.
N.hide(run);local raw=Pane.refreshContainer
Pane.refreshContainer=function(self)raw(self);self.itemslist={{name='stale',cat=old.cat,items={old,old},count=2}}end
local ok=pcall(N.reopen,run,assert(N.aggregateProof(run)));assert(not ok,'same-count stale group row accepted')
Pane.refreshContainer=raw;loot:setVisible(false);loot:refreshBackpacks();N.reopen(run,assert(N.aggregateProof(run)))
-- Wrong or translated text is not an acceptable substitute for the exact BC
-- resolver ID, even when every physical row ID/count is otherwise current.
for _,wrong in ipairs({'WrongCategory','RU:IGUI_ItemCat_FirstAid'})do
 N.hide(run)
 Pane.refreshContainer=function(self)raw(self);self.itemslist[1].cat=wrong end
 local accepted,problem=pcall(N.reopen,run,assert(N.aggregateProof(run)))
 assert(not accepted and tostring(problem):find('observedGroup=',1,true)and tostring(problem):find('resolvedCategory=BCMappedFirstAid',1,true),'wrong group category passed or omitted raw diagnostic values')
 Pane.refreshContainer=raw;loot:setVisible(false);loot:refreshBackpacks();N.reopen(run,assert(N.aggregateProof(run)))
end
-- Reopening cannot manufacture a missing pre-open propagation proof, and an
-- unavailable or foreign target callback cannot produce a successful receipt.
N.hide(run);local selectionBefore=selections
assert(not pcall(N.reopen,run,nil)and selections==selectionBefore,'reopen selected before receiving the pre-open aggregate proof')
loot.backpacks={sourceButton}
assert(not pcall(N.reopen,run,assert(N.aggregateProof(run)))and selections==selectionBefore,'unavailable aggregate button was accepted')
loot.backpacks={aggregateButton,sourceButton};aggregateButton.target={}
assert(not pcall(N.reopen,run,assert(N.aggregateProof(run)))and selections==selectionBefore,'foreign aggregate button owner was accepted')
aggregateButton.target=loot;N.hide(run);N.reopen(run,assert(N.aggregateProof(run)))
run.step='hidden-loot';run.state.stores[5]=source;N.hide(run)
local physical=N.reopen(run,assert(N.aggregateProof(run)))
assert(physical.selectedBound and physical.selectedKind=='crate5'and loot.inventory==source and pane.inventory==source,'hidden-loot reopen did not select the exact physical crate5')
run.step='initial';N.hide(run);N.reopen(run,assert(N.aggregateProof(run)))
-- Native action callbacks and endpoints stay untouched during observation.
local function action(i,src,dst,kind,duration)
 local a={item=i,srcContainer=src,destContainer=dst,Type=kind or 'ISInventoryTransferAction',duration=duration or -1}
 function a:getDuration()return self.duration end;function a:isStarted()return true end;function a:getJobDelta()return .5 end
 return a
end
local a=action(replacement,source,root);run.step='peer-replace';queue.queue={a};queue.current=a
N.observe(run);assert(run.records[1].id==2 and run.records[1].progressSamples==1)
assert(N.actionProof(run)[1].sourceMethodsUnchanged)
local saved=a.perform;a.perform=function()end;assert(not pcall(N.observe,run),'changed native action callback accepted');a.perform=saved
queue.queue={};queue.current=nil
-- Hidden dispatch uses the live installed button for each UI mode, never a
-- synthesized direct call to the transfer executor.
run.state.stores[5]=source;run.phase.quickId=2;run.step='hidden-loot';loot.inventoryPane.inventory=source
local called=0
local function quick(owner)
 assert(owner==loot and not owner:getIsVisible());called=called+1;queue.queue={action(replacement,source,root)}
end
loot.onTransferByNameClick=quick;loot.transferByNameButton={target=loot,onclick=quick};loot.visible=false
local proof=N.quick(run);assert(proof.installedButton and proof.hiddenBefore and proof.hiddenAfter and called==1)
queue.queue={};run.actions={};run.records={};run.phase.mode='vanilla'
Page.lootAll=quick;loot.lootAll={target=loot,onclick=quick};proof=N.quick(run)
assert(proof.callback=='ISInventoryPage.lootAll'and called==2)
queue.queue={};loot.lootAll.onclick=function()end;assert(not pcall(N.quick,run),'foreign vanilla quick callback accepted')
loot.lootAll.onclick=quick
-- A foreign item enqueued by an ordinary UI callback must fail closed.
queue.queue={action(item(900),source,root)};assert(not pcall(N.observe,run),'foreign native action accepted');queue.queue={}

-- Actual recipe UI/material collection chooses the declared source identity and
-- observes the native recipe duration multiplier without editing action costs.
queue.queue={};queue.current=nil;run.actions={};run.records={};run.step='peer-craft'
local pack=item(4,'HotdogPack');local craftSource=container({pack});run.state.stores[4]=craftSource
run.phase.craftInputId=4;run.owned[4]=true;run.phase.mode='clean'
local recipe={getInputs=function()return list({{}})end,getName=function()return 'OpenHotdogPack'end,getTime=function()return 15 end}
getScriptManager=function()return {getCraftRecipe=function(_,name)assert(name=='OpenHotdogPack');return recipe end}end
local chosen,usedContainers,dispatchCount=nil,nil,0
local logic={setContainers=function(_,v)usedContainers=v end,setRecipe=function(_,v)assert(v==recipe)end,
 setManualSelectInputs=function(_,v)assert(v)end,clearManualInputs=function()end,
 setManualInputsFor=function(_,input,v)chosen=v:get(0);return true end,canPerformCurrentRecipe=function()return true end,
 getRecipeData=function()return {getAllInputItems=function()return list({pack})end}end}
local owner={quantityInput={setText=function(_,v)assert(v=='1')end},updateCraftAction=function()end}
local button={target=owner};owner.craftButton=button
button.onclick=function()
 dispatchCount=dispatchCount+1
 local native=action(nil,nil,nil,'ISHandcraftAction',recipe:getTime(player)*5)
 native.craftRecipe=recipe;native.onStartTarget=owner;native.onCompleteTarget=owner
 queue.queue={native};queue.current=native
end
function button:forceClick()self.onclick()end
local window={HandCraftPanel={logic=logic,craftActionPanel=owner},close=function()end};local opened=false
ISEntityUI={GetWindowInstance=function()return opened and window or nil end,OpenHandcraftWindow=function()opened=true end}
ISInventoryPaneContextMenu={getContainers=function()return list({root,craftSource})end}
N.craft(run)
assert(chosen==pack and usedContainers:get(1)==craftSource and dispatchCount==1,'native material picker lost exact shared input')
assert(run.craftDispatch.nativeDuration==75 and run.craftDispatch.recipeTime==15 and run.records[1].duration==75,'native craft baseline was accelerated')
queue.queue={};queue.current=nil;N.closeCraft(run);opened=false
local missing=ISInventoryPaneContextMenu.getContainers;ISInventoryPaneContextMenu.getContainers=function()return list({root})end
assert(not pcall(N.craft,run)and dispatchCount==1,'absent native source still dispatched crafting')
ISInventoryPaneContextMenu.getContainers=missing;opened=false

-- A later legitimate decorator remains owned by that installer. Counter
-- observations never replace or restore a foreign callback.
local decorated=function(self,...)return nativeClassRefresh(self,...)end
Pane.refreshContainer=decorated
local lateRun=N.startObservation(player,{items={}});N.hidden(lateRun)
assert(Pane.refreshContainer==decorated and pane.refreshContainer==nativePaneRefresh,'counter observation overwrote a later callback owner')
Pane.refreshContainer=nativeClassRefresh
local count=pane.refreshContainerCount;pane.refreshContainerCount=nil
assert(not pcall(N.startObservation,player,{items={}}),'missing native row-build counter was silently accepted')
pane.refreshContainerCount=count
-- Native placement waits for deferred animation movement to cease, then makes
-- exactly one placement and guards the resulting current square.
local U=dofile(client..'WarehouseWorkloadUI.lua');local placements=0
local pos={x=10.5,y=20.5,z=0,deferredX=.1,deferredY=0}
local square={getX=function()return math.floor(pos.x)end,getY=function()return math.floor(pos.y)end,getZ=function()return pos.z end}
function player:getSquare()return square end;function player:getCurrentSquare()return square end
function player:getX()return pos.x end;function player:getY()return pos.y end;function player:getZ()return pos.z end
function player:isPlayerMoving()return false end;function player:getPath2()return nil end
Vector2={new=function()return {}end}
function player:getDeferredMovement()return {getX=function()return pos.deferredX end,getY=function()return pos.deferredY end}end
function player:teleportTo(x,y,z)placements=placements+1;pos.x=math.floor(x);pos.y=math.floor(y);pos.z=z end
function player:setForceX(x)pos.x=x end;function player:setForceY(y)pos.y=y end;function player:setZ(z)pos.z=z end
local placement={began=clock,target={x=30.5,y=40.5,z=0,squareX=30,squareY=40,squareZ=0}}
assert(not U.place(player,placement,true));clock=clock+600;assert(not U.place(player,placement,true)and placements==0)
pos.deferredX=0;assert(not U.place(player,placement,true));clock=clock+499;assert(not U.place(player,placement,true)and placements==0)
clock=clock+1;assert(not U.place(player,placement,true)and placements==1);clock=clock+100
assert(U.place(player,placement,true).singlePlacement and placements==1);assert(U.place(player,placement,true)and placements==1)
-- Inventory restoration checks physical identity and endpoints recursively;
-- recreating the same ID or leaving one owned output behind is insufficient.
local originalItem=root.values[1]
function originalItem:isFavorite()return false end;function originalItem:getCondition()return 10 end;function originalItem:getUnequippedWeight()return .1 end
function player:getPrimaryHandItem()return originalItem end;function player:getSecondaryHandItem()return nil end
function player:getWornItems()return list({})end
instanceof=function()return false end
local originals=U.original(player);assert(U.originalProof(player,originals).identity)
local sameId=item(originalItem.id,'Nails');sameId.isFavorite=originalItem.isFavorite;sameId.getCondition=originalItem.getCondition;sameId.getUnequippedWeight=originalItem.getUnequippedWeight;sameId.container=root
root.values={sameId};assert(not pcall(U.originalProof,player,originals),'same-ID replacement of an original item was accepted')
root.values={originalItem,replacement};assert(not pcall(U.originalProof,player,originals),'owned residue was accepted as original inventory')
root.values={originalItem};assert(U.originalProof(player,originals).equipment)
-- Drive the actual runner through both initial phases. Server-seeded physical
-- replicas and BC discovery are independent readiness conditions: the setup
-- refresh must wait for replicas, occur once, and never retry a stale aggregate.
do
 local stamp,nativeReady,aggregateReady=0,false,false
 local tick,command;local sent,emitted,hides,reopens={},{},0,0
 local waits,waitLines={},{}
 local fixturePlayer={getUsername=function()return 'client1'end,getPlayerNum=function()return 0 end,getSquare=function()return {}end}
 local function page()
  local pane={inventory={},getX=function()return 0 end,getY=function()return 20 end,getWidth=function()return 400 end,getHeight=function()return 300 end}
  return {inventoryPane=pane,getX=function()return 0 end,getY=function()return 0 end,getWidth=function()return 400 end,getHeight=function()return 320 end,
   setNewContainer=function()end,refreshBackpacks=function()end}
 end
 local pages={page(),page()}
 local phase={token='session',index=1,mode='clean',phaseToken='session:1',items={},replacementSourceId=1,craftInputId=2}
 local ids={token='session',actorOrigin={x=10,y=10,z=0},crates={}}
 local state={stores={}}
 local fakeF={module='WarehouseWorkloadTest',modes={'clean','vanilla'},emit=function(event,row)emitted[#emitted+1]={event=event,row=row}end,
  resolve=function()return state end,attachPhase=function(_,p)phase=p end,
  native=function()if nativeReady then return {}end end,expected=function(_,step)return {[77]=step..':expected'}end,snapshot=function()return {source='native snapshot'}end,
  find=function()return nil,nil,0 end}
 local hidden={visible=false,rowsPending=true,nativeBuilds=0}
 local fakeN={idle=function()return true end,selectAggregate=function()return true end,startObservation=function()return {}end,
  observe=function()end,hidden=function()return hidden end,closeCraft=function()end,
  aggregateProof=function()if aggregateReady then return {actualIds={1,2}}end end,
  hide=function()assert(nativeReady,'setup discovery preceded native seed replicas');hides=hides+1;return hidden end,
  reopen=function()reopens=reopens+1;return {rowIds={1,2}}end,
  diagnostics=function()return {}end}
 local fakeU={pages=function()return pages end,normalize=function()end,save=function()return {}end,
  original=function()return {}end,originalProof=function()return {}end,position=function()return {}end,
  protect=function()end,place=function()return {}end,configure=function()end}
 local modules={QueueTestSelection={kind='mp',cases={'peer-edits'}},WarehouseWorkloadFixture=fakeF,
  WarehouseWorkloadUI=fakeU,WarehouseWorkloadNative=fakeN,QueueHealthEvents={encode=function(row)waits[#waits+1]=row;return '{}'end}}
 local env=setmetatable({require=function(name)return assert(modules[name],name)end,
  print=function(line)assert(line:find('[WAREHOUSE_WORKLOAD_WAIT] ',1,true)==1,'unexpected runner failure or accepted diagnostic lifecycle');waitLines[#waitLines+1]=line end,
  getTimestampMs=function()return stamp end,isClient=function()return true end,isIngameState=function()return true end,
  getPlayer=function()return fixturePlayer end,getPlayerInventory=function()return pages[1]end,getPlayerLoot=function()return pages[2]end,
  sendClientCommand=function(module,name,args)sent[#sent+1]={command=name,args=args}end,
  Events={OnTick={Add=function(fn)tick=fn end},OnServerCommand={Add=function(fn)command=fn end}}},{__index=_G})
 fixturePlayer.getInventory=function()return {}end
 local chunk=assert(loadfile(client..'ZZWarehouseWorkload.lua'));setfenv(chunk,env);chunk()
 local function step()stamp=stamp+200;tick()end
 local function untilCommand(name)
  local first=#sent
  for _=1,15 do step();if #sent>first and sent[#sent].command==name then return sent[#sent]end end
  error('runner did not request '..name)
 end
 untilCommand('Prepare');command(fakeF.module,'Prepared',{role='client1',ids=ids});untilCommand('Ready')
 for index=1,2 do
  phase={token='session',index=index,mode=fakeF.modes[index],phaseToken='session:'..index,items={},replacementSourceId=1,craftInputId=2}
  nativeReady=false;aggregateReady=false;command(fakeF.module,'Seeded',{phase=phase});step()
  local before=hides
  for _=1,3 do step()end
  assert(hides==before,'runner refreshed before native replicas became ready')
  stamp=stamp+5000;step()
  assert(#waits==index and waits[index].step=='initial'and not waits[index].nativeReady and not waits[index].aggregateReady,'initial diagnostic did not distinguish both readiness conditions')
  step();assert(#waits==index,'initial wait diagnostic repeated')
  nativeReady=true;step();assert(hides==before+1,'runner did not perform one seeded setup discovery')
  for _=1,3 do step()end
  assert(hides==before+1 and reopens==index-1,'runner retried setup refresh while aggregate was stale')
  aggregateReady=true;step();assert(reopens==index and hides==before+2,'runner did not proceed through native reopen and next-step hide')
  assert(sent[#sent].command=='Seen'and sent[#sent].args.index==index,'runner did not acknowledge the correct mode')
  if index==1 then
   nativeReady=false;aggregateReady=false
   command(fakeF.module,'Released',{token='session',index=1,ownedRemaining=0,removedIds={}});untilCommand('Ready')
  else
   -- The same once-only diagnostic resets for a working peer step. Native
   -- replicas can be current while the pre-open BC aggregate remains stale.
   nativeReady=true;aggregateReady=false
   command(fakeF.module,'Go',{phase=phase,step='peer-replace',actor='client2'});step()
   command(fakeF.module,'Observed',{phase=phase,step='peer-replace',receipt={}})
   local hiddenBefore,openBefore,eventsBefore=hides,reopens,#emitted
   stamp=stamp+5000;step()
   assert(#waits==3 and waits[3].step=='peer-replace'and waits[3].nativeReady and not waits[3].aggregateReady,'working observer wait omitted native/aggregate distinction or dispatch latch reset')
   assert(waits[3].expected[1].id==77 and waits[3].expected[1].endpoint=='peer-replace:expected'and waits[3].snapshot.source=='native snapshot','working wait used initial expectations or omitted native snapshot')
   for _=1,3 do step()end
   assert(#waits==3 and #waitLines==3,'working wait diagnostic repeated')
   assert(hides==hiddenBefore and reopens==openBefore and #emitted==eventsBefore,'working diagnostic refreshed, selected, reopened, or emitted accepted evidence')
  end
 end
end
require=originalRequire
print('PASS warehouse workload native client consumers and quiescent restoration (offline doubles only)')
