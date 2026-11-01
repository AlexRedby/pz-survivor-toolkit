-- Actual installed CleanUI admission callbacks and native ModOptions; UI,
-- physical replicas, frame clock and N's observation port are controlled doubles.
-- A stale aggregate below is an explicit dependency control, not evidence of a
-- naturally stale multiplayer UI or of Smart Deposit routing/native transfers.
assert(type(CleanUIInventoryTransferHandlerSource)=='string','required installed CleanUI transfer handler missing')
assert(type(CleanUIInventoryPageSource)=='string','required installed CleanUI page missing')
assert(type(CleanUIInventoryModOptionsSource)=='string','required installed CleanUI option getters missing')
assert(type(NativeActionRoot)=='string','required native ModOptions root missing')
local input=assert(io.open(NativeActionRoot..'/client/PZAPI/ModOptions.lua','r'))
local modOptionsSource=input:read('*a');input:close()
input=assert(io.open(ProjectRoot..'/tests/native_queue/warehouse-workload/client/WarehouseWorkloadAffinity.lua','r'))
local affinitySource=input:read('*a');input:close()
local function load(source,env,name)
 local chunk=assert(loadstring(source,'@'..name));setfenv(chunk,env);return chunk()
end
local function pageMethod(name)
 return assert(CleanUIInventoryPageSource:match('(function ISInventoryPage:'..name..'%b().-)\nend'),
  'installed page method missing: '..name)..'\nend'
end
local function getter(name)
 return assert(CleanUIInventoryModOptionsSource:match('(function '..name..'%b().-)\nend'),
  'installed CleanUI getter missing: '..name)..'\nend'
end
local optionConstants=assert(CleanUIInventoryModOptionsSource:match('local MOD_ID = [^\n]+'))..'\n'
 ..assert(CleanUIInventoryModOptionsSource:match('local TRANSFER_BUTTON_LAYOUT_ID = [^\n]+'))..'\n'
local function list(values)return {size=function()return #values end,get=function(_,i)return values[i+1]end}end
local function container(kind)
 local c={values={},kind=kind}
 function c:getItems()return list(self.values)end
 function c:getItemById(id)for _,item in ipairs(self.values)do if item.id==id then return item end end end
 function c:getType()return self.kind end
 function c:isItemAllowed()return self.allowed~=false end
 function c:getOnlyAcceptCategory()return self.allowed==false and'none'or nil end
 function c:getCapacity()return self.allowed==false and 0 or 100 end
 function c:hasRoomFor()return true end
 function c:isInCharacterInventory()return false end
 return c
end
local function item(id,ft,category,c)
 local value={id=id,ft=ft,category=category,container=c}
 function value:getID()return self.id end
 function value:getFullType()return self.ft end
 function value:getDisplayCategory()return self.category end
 function value:getContainer()return self.container end
 function value:getUnequippedWeight()return 1 end
 function value:isFavorite()return self.favorite==true end
 function value:isEquipped()return self.equipped==true end
 function value:setDisplayCategory()error('affinity observation must not prepare native categories')end
 c.values[#c.values+1]=value;return value
end
local function ids(c)local out={};for _,value in ipairs(c.values)do out[#out+1]=value.id end;table.sort(out);return out end
local function fixture(kind,fresh)
 local w={now=1000,captures={},observations=0,refreshes=0,highlights=0,frames={}}
 local root,physical,aggregate=container('inventorymale'),container('crate'),container('proximityInv')
 local old=item(101,'Base.Bandage','FirstAid',root);local new=item(102,'Base.Screwdriver','Tool',root)
 -- The peer owns the removed old stock; the new stock is physically in crate3.
 local peer=container('inventorymale');local oldStock=item(201,'Base.Bandage','FirstAid',peer)
 local newStock=item(202,'Base.Screwdriver','Tool',physical)
 aggregate.values={fresh and newStock or oldStock}
 local player={getInventory=function()return root end,getPlayerNum=function()return 0 end,
  getUsername=function()return w.role or'client1'end}
 local function page(visible,c,onCharacter)
  local p={visible=visible,player=0,onCharacter=onCharacter,inventoryPane={inventory=c}}
  function p:getIsVisible()return self.visible end
  function p:refreshBackpacks()w.refreshes=w.refreshes+1;error('test must not manufacture discovery')end
  function p.inventoryPane:refreshContainer()w.refreshes=w.refreshes+1;error('test must not manufacture hidden refresh')end
  function p.inventoryPane:setItemsToHighlight()w.highlights=w.highlights+1 end
  return p
 end
 local personal,loot=page(true,root,true),page(false,aggregate,false)
 loot.backpacks={{inventory=physical}}
 local env=setmetatable({PZAPI={},ISInventoryPage={},
  getText=function(text)return text end,isGamePaused=function()return false end,
  getFileWriter=function()error('fixture options must not persist settings')end,
  getFileReader=function()error('fixture options must not reload settings')end,
  getPlayerHotbar=function()end,getSpecificPlayer=function(n)assert(n==0);return player end,
  getPlayerInventory=function(n)assert(n==0);return personal end,
  getPlayerLoot=function(n)assert(n==0);return loot end,
  getTimestampMs=function()return w.now end,
  Events={OnPostUIDraw={Add=function(fn)w.frames[#w.frames+1]=fn end}},
  ISInventoryTransferAction={new=function(_,who,value,from,to)assert(who==player and from==root and to==physical);return {item=value}end},
  ISTimedActionQueue={add=function(action)w.captures[#w.captures+1]={items={action.item},target=physical}end}},{__index=_G})
 load(modOptionsSource,env,'PZAPI/ModOptions.lua')
 local options=env.PZAPI.ModOptions:create('CleanUI')
 local method=options:addComboBox('transferMethod','method');method:addItem('single');method:addItem('nearby',true)
 local layout=options:addComboBox('transferButtonLayout','layout');layout:addItem('menu',true);layout:addItem('split')
 method.element={selected=2};layout.element={selected=1}
 load(optionConstants
  ..getter('CleanUI_getTransferMethod')..'\n'..getter('CleanUI_getTransferButtonLayout'),env,'ISUI/CleanUI_ModOptions.lua')
 load(CleanUIInventoryTransferHandlerSource,env,'ISUI/ISInventoryPageTransferHandler.lua')
 for _,name in ipairs({'onTransferByNameClick','onTransferByCategoryClick','cleanUIClearQuickTransferHighlights'})do
  load(pageMethod(name),env,'ISUI/ISInventoryPage.lua')
 end
 setmetatable(personal,{__index=env.ISInventoryPage})
 local function button(callback)return {target=personal,onclick=callback,visible=true,getIsVisible=function(self)return self.visible end}end
 personal.transferByNameButton=button(personal.onTransferByNameClick)
 personal.transferByCategoryButton=button(personal.onTransferByCategoryClick)
 function personal.inventoryPane:transferItemsByWeight(values,target)
  assert(self==personal.inventoryPane and(target==aggregate or target==physical),'actual CleanUI handler used another admission target')
  local admitted={};for _,value in ipairs(values)do admitted[#admitted+1]=value end
  w.captures[#w.captures+1]={items=admitted,target=target}
 end
 local phase={oldCandidateId=101,newCandidateId=102,affinityKind=kind,oldCategory='FirstAid',newCategory='Tool'}
 local run={player=player,phase=phase,state={stores={container('crate'),container('crate'),physical}},actions={},owned={[101]=true,[102]=true}}
 local N={aggregate=function(p)assert(p==player);return aggregate end,idle=function()return true end}
 function N.aggregateObservation(observed)
  assert(observed==run);w.observations=w.observations+1
  local actual,expected=ids(aggregate),ids(physical)
  return {actualIds=actual,expectedIds=expected,fresh=#actual==1 and actual[1]==expected[1]}
 end
 function N.observe(observed)
  assert(observed==run)
  -- This port supplies synthetic action observations from captured admission;
  -- its chosen destination makes no assertion about the real routing layer.
  for _,capture in ipairs(w.captures)do for _,value in ipairs(capture.items)do
   local action={Type='ISInventoryTransferAction',item=value,srcContainer=root,destContainer=physical}
   if w.actionOverride then w.actionOverride(action)end
   run.actions[action]={step='personal-quick'}
  end end
 end
 env.require=function(name)assert(name=='WarehouseWorkloadNative','unexpected affinity dependency: '..name);return N end
 local A=load(affinitySource,env,'WarehouseWorkloadAffinity.lua')
 function w.frame()for _,fn in ipairs(w.frames)do fn()end end
 w.A=A;w.run=run;w.root=root;w.physical=physical;w.aggregate=aggregate;w.old=old;w.new=new
 w.personal=personal;w.loot=loot;w.method=method;w.layout=layout;w.env=env;w.oldStock=oldStock;w.newStock=newStock
 w.saved=A.save();A.configure();A.begin(run)
 return w
end
local function reject(f,pattern)
 local ok,problem=pcall(f);assert(not ok,'invalid affinity input accepted')
 if pattern then assert(tostring(problem):find(pattern,1,true),'unexpected rejection: '..tostring(problem))end
end
for _,method in ipairs({'1','2'})do for _,kind in ipairs({'type','category'})do
 local w=fixture(kind,true);w.run.phase.transferMethod=method;w.A.configure(method)
 w.run.phase.items={{id=w.newStock.id,cat='Tool'}}
 w.loot.inventoryPane.inventory=w.physical;w.newStock.category='NativeTool'
 local proof=w.A.dispatch(w.run)
 assert(proof.targetMode=='physical'and proof.oldEligible and proof.newEligible and proof.targetCapacity==100
  and proof.physicalBefore[1].id==w.newStock.id and proof.physicalAfter[1].rawCategory=='NativeTool')
 assert((kind=='type'and proof.selectedId==w.new.id and #w.captures==1)
  or(kind=='category'and proof.selectedId==nil and #w.captures==0),'physical callback admission differs')
 assert(not w.A.done(w.run),'physical callback bypassed post-callback settling')
 if kind=='type'then table.remove(w.root.values,2)end
 w.now=1500;w.frame();w.frame();w.frame()
 assert(w.A.done(w.run)and proof.completionFrames==3 and proof.completionMs==500)
end end
for _,kind in ipairs({'type','category'})do for _,fresh in ipairs({true,false})do
 local blocked=fixture(kind,fresh);blocked.aggregate.allowed=false
 local receipt=blocked.A.dispatch(blocked.run)
 assert(#blocked.captures==0 and receipt.selectedId==nil and receipt.dispatched
  and not receipt.oldEligible and not receipt.newEligible and not receipt.targetOldAllowed and not receipt.targetNewAllowed
  and receipt.physicalOldAllowed and receipt.physicalNewAllowed and receipt.physicalOldEligible and receipt.physicalNewEligible
  and receipt.targetOnlyAcceptCategory=='none'and receipt.targetCapacity==0,'blocked aggregate bypassed native eligibility')
 assert(not blocked.A.done(blocked.run),'no-op callback completed without post-callback observation')
 blocked.now=1500;blocked.frame();blocked.frame();assert(not blocked.A.done(blocked.run),'two callback frames passed completion')
 blocked.now=1499;blocked.frame();assert(not blocked.A.done(blocked.run),'callback frames bypassed settle interval')
 blocked.now=1500;assert(blocked.A.done(blocked.run)and receipt.completionFrames==3 and receipt.completionMs==500)
 assert(#blocked.root.values==2 and blocked.refreshes==0 and not blocked.loot.visible,'blocked callback changed source/visibility')
 local w=fixture(kind,fresh);local A,run=w.A,w.run
 assert(w.saved.transferMethod==2 and w.saved.transferButtonLayout==1)
 assert(w.method:getValue()==1 and w.method.element.selected==1 and w.layout:getValue()==2 and w.layout.element.selected==2,
  'fixture bypassed actual native combobox setValue')
 assert(not A.ready(run));w.now=1500;w.frame();w.frame();assert(not A.ready(run),'two UI frames passed settle gate')
 w.now=1499;w.frame();assert(not A.ready(run),'three UI frames bypassed 500ms gate')
 w.now=1500;assert(A.ready(run),'three ordinary UI callback opportunities and 500ms did not settle')
 local proof=A.proof(run)
 assert(proof.naturalFrames==3 and proof.settledMs==500 and proof.forcedRefresh==false
  and proof.aggregate.fresh==fresh and proof.personalVisible and proof.lootHidden)
 local stock=fresh and w.newStock or w.oldStock
 assert(#proof.aggregate.items==1 and proof.aggregate.items[1].id==stock.id
  and proof.aggregate.items[1].ft==stock.ft and proof.aggregate.items[1].rawCategory==stock.category,
  'aggregate proof did not retain actual read-only type/category identity')
 assert(run.affinity.samples[1].items[1].id==stock.id
  and run.affinity.samples[1].items[1].rawCategory==stock.category,'natural sample omitted physical aggregate metadata')
 for i=1,30 do A.ready(run)end
 assert(#run.affinity.samples==16,'unbounded affinity observation samples')
 local selected=fresh and w.new or w.old
 -- A matching protected original remains ineligible under real CleanUI rules.
 local original=item(999,selected.ft,selected.category,w.root);original.favorite=true
 local receipt=A.dispatch(run)
 assert(#w.captures==1 and #w.captures[1].items==1 and w.captures[1].items[1]==selected
  and receipt.selectedId==selected.id and receipt.oldCandidateId==101 and receipt.newCandidateId==102,
  'installed CleanUI callback admitted the wrong physical candidate ID')
 assert(receipt.oldEligible==true and receipt.newEligible==true,
  'candidate eligibility was not independently verified through the actual CleanUI predicate')
 assert(receipt.callback==(kind=='type'and'onTransferByNameClick'or'onTransferByCategoryClick')
  and receipt.physicalOld==0 and receipt.physicalNew==1 and receipt.hiddenAfter and w.highlights==2,
  'installed page callback/highlight path or physical controls changed')
 assert(receipt.before.items[1].id==stock.id and receipt.after.items[1].id==stock.id
  and receipt.before.items[1].rawCategory==stock.category,'quick receipt fabricated aggregate metadata')
 assert(not A.done(run),'observed admission was mistaken for native transfer completion')
 table.remove(w.root.values,fresh and 2 or 1);assert(A.done(run),'one departed candidate did not satisfy completion boundary')
 w.root.values={original};assert(not A.done(run),'both departed candidates passed completion boundary')
 local restored=A.restore(w.saved)
 assert(restored.transferMethod.actual==2 and restored.transferButtonLayout.actual==1
  and w.method.element.selected==2 and w.layout.element.selected==1,'saved native options were not restored')
 local frames=run.affinity.frames;w.frame();assert(run.affinity.frames==frames,'restored fixture kept watching UI frames')
 assert(w.refreshes==0 and not w.loot.visible,'source-backed control manufactured hidden discovery or visibility')
end end
for _,kind in ipairs({'type','category'})do
 local w=fixture(kind,true)
 item(999,'Base.Screwdriver','Tool',w.root)
 reject(function()w.A.dispatch(w.run)end,'original/unowned')
 assert(#w.captures==0,'unowned original was admitted before refusal')
 local drift=fixture(kind,true)
 local button=kind=='type'and drift.personal.transferByNameButton or drift.personal.transferByCategoryButton
 button.onclick=function()error('replaced toolbar callback executed')end
 reject(function()drift.A.dispatch(drift.run)end,'binding differs')
 assert(#drift.captures==0,'drifted toolbar callback reached admission')
end
for _,name in ipairs({'old','new'})do
 local eligibility=fixture('type',true);eligibility[name].favorite=true
 reject(function()eligibility.A.dispatch(eligibility.run)end,'candidate protection differs')
 assert(#eligibility.captures==0,'ineligible control candidate was hidden behind a fabricated eligibility receipt')
end
local mutations={
 function(w)w.personal.visible=false end,
 function(w)w.loot.visible=true end,
 function(w)w.personal.inventoryPane.inventory=container('inventorymale')end,
 function(w)w.loot.inventoryPane.inventory=w.physical end,
 function(w)w.method:setValue(2)end,
 function(w)w.layout:setValue(1)end,
 function(w)w.personal.transferByNameButton.onclick=function()error('drifted callback executed')end end,
 function(w)w.personal.transferByNameButton.target=w.loot end,
 function(w)w.personal.transferByNameButton.visible=false end,
 function(w)item(203,'Base.Bandage','FirstAid',w.physical)end,
 function(w)item(204,'Base.Screwdriver','Tool',w.physical)end,
}
for _,mutate in ipairs(mutations)do
 local w=fixture('type',true);mutate(w);reject(function()w.A.dispatch(w.run)end)
 assert(#w.captures==0 and w.refreshes==0,'rejected control executed a callback or forced discovery')
end
for _,changeAction in ipairs({
 function(action)action.item={getID=function()return 999 end}end,
 function(action)action.srcContainer=container('foreign')end,
 function(action)action.destContainer=container('foreign')end,
})do
 local w=fixture('type',true);w.actionOverride=changeAction
 reject(function()w.A.dispatch(w.run)end)
 assert(#w.captures==1 and w.captures[1].items[1]==w.new,'observation rejection changed actual CleanUI admission')
end
local invisible=fixture('type',true);invisible.personal.visible=false
for i=1,4 do invisible.frame()end
assert(invisible.run.affinity.frames==0,'hidden personal page counted UI settle opportunities')
local observer=fixture('category',true);observer.role='client2';observer.root.values={}
observer.A.begin(observer.run)
assert(observer.run.affinity.oldCategory=='FirstAid'and observer.run.affinity.newCategory=='Tool',
 'observer setup required access to another client root inventory')
observer.run.phase.newCategory='FirstAid'
reject(function()observer.A.begin(observer.run)end,'categories missing/identical')
local changed=fixture('category',true);changed.new.category='Changed'
changed.run.affinity=nil
assert(changed.A.begin(changed.run)==nil and changed.run.affinity==nil and changed.new.category=='Changed',
 'unprepared visible source was repaired or bound instead of waiting for normal UI preparation')
local readOnly=fixture('category',true)
readOnly.A.ready(readOnly.run);readOnly.newStock.category='NativeUnpreparedTool'
readOnly.A.ready(readOnly.run)
local observed=readOnly.A.proof(readOnly.run)
assert(observed.aggregate.items[1].rawCategory=='NativeUnpreparedTool'
 and observed.samples[1].items[1].rawCategory=='Tool'and observed.samples[2].items[1].rawCategory=='NativeUnpreparedTool'
 and readOnly.newStock.category=='NativeUnpreparedTool'and readOnly.new.category=='Tool',
 'read-only proof repaired live category state or rewrote historical samples')
reject(function()readOnly.A.dispatch(readOnly.run)end,'physical stock does not distinguish affinity')
readOnly.newStock.category=nil
assert(readOnly.A.proof(readOnly.run).aggregate.items[1].rawCategory=='Other'and readOnly.newStock.category==nil,
 'raw nil category was prepared rather than recorded with the real handler fallback')
-- Aggregate membership alone cannot determine category affinity. Read the
-- actual retained object's category, even when it differs from seed metadata.
local categoryControl=fixture('category',false);categoryControl.oldStock.category='Tool'
local categoryReceipt=categoryControl.A.dispatch(categoryControl.run)
assert(categoryReceipt.selectedId==categoryControl.new.id and categoryReceipt.before.items[1].id==categoryControl.oldStock.id
 and categoryReceipt.before.items[1].rawCategory=='Tool'and not categoryReceipt.before.fresh,
 'category admission was inferred from stale ID/seed metadata instead of the actual installed predicate')

-- Offline controlled category-preparation boundary, not multiplayer/native proof.
-- Use the installed toolbar callback/handler and real Toolkit wrappers/rules;
-- only panes, physical replicas, presentation helpers and action sinks are doubles.
do
 local function preparationFixture(method)
  local boot,start,modules={},{},{}
  local admitted,queued={},{}
  local source,target=container('inventorymale'),container('crate')
  function target:isEmpty()return #self.values==0 end
  function target:hasRoomFor()return true end
  local script={getFullName=function()return 'Base.Screwdriver'end,
   getDisplayCategory=function()return 'ToolWeapon'end,
   DoParam=function()error('inventory preparation must not mutate ScriptItem categories')end}
  local function screwdriver(id,c)
   local value=item(id,'Base.Screwdriver','ToolWeapon',c)
   value.originalCategory=value.category
   function value:getScriptItem()return script end
   function value:hasModData()return false end
   function value:isFluidContainer()return false end
   function value:getUnequippedWeight()return 1 end
   function value:setDisplayCategory(category)self.category=category end
   return value
  end
  local candidate,stock=screwdriver(301,source),screwdriver(302,target)
  local paneClass={prerender=function()end,restoreSelection=function()end}
  function paneClass:refreshContainer()
   self.refreshes=(self.refreshes or 0)+1
   self.itemslist={};self:restoreSelection({})
  end
  function paneClass:transferItemsByWeight(values,destination)
   assert(destination==target,'single callback selected a nonphysical destination')
   for _,value in ipairs(values)do admitted[#admitted+1]=value:getID()end
  end
  local function page(c,onCharacter)
   return {player=0,onCharacter=onCharacter,visible=onCharacter,getIsVisible=function(self)return self.visible end,
    backpacks={{inventory=c}},
    inventoryPane=setmetatable({inventory=c,mode='details',items={},selected={}}, {__index=paneClass})}
  end
  local personal,loot=page(source,true),page(target,false)
  local player={getPlayerNum=function()return 0 end}
  local env=setmetatable({PZSurvivorToolkit={Settings={inventoryFilters=function()return true end}},
   ISInventoryPane=paneClass,ISInventoryPage={},ItemBodyLocation={},
   table=setmetatable({wipe=function(values)for key in pairs(values)do values[key]=nil end end},{__index=table}),
   CleanUI_Clean_ISInventoryPane=false,CleanUI_Vanilla_ISInventoryPane=false,
   CleanUI_RegisterInventoryUiToggleCallback=false,ISInventoryCommonHandler_SortMenu=false,
   getFileReader=false,getAllItems=false,
   Events={OnGameBoot={Add=function(fn)boot[#boot+1]=fn end},
    OnGameStart={Add=function(fn)start[#start+1]=fn end},OnCreatePlayer={Add=function()end}},
   getPlayerInventory=function()return personal end,getPlayerLoot=function()return loot end,
   getSpecificPlayer=function()return player end,getPlayerHotbar=function()end,
   isGamePaused=function()return false end,CleanUI_getTransferMethod=function()return method end,
   ISTimedActionQueue={add=function(action)
    assert(action.srcContainer==source and action.destContainer==target,
     'nearby callback selected incorrect physical containers')
    queued[#queued+1]=action.item:getID()
   end},ISInventoryTransferAction={new=function(_,who,value,from,to)
    assert(who==player);return {item=value,srcContainer=from,destContainer=to}
   end}}, {__index=_G})
  local presentation={
   ['ISUI/ISInventoryPane']=paneClass,['PZSurvivorToolkit/Settings']={},
   ['PZSurvivorToolkit/UIStyle']={},['PZSurvivorToolkit/TagVisuals']={},
   ['PZSurvivorToolkit/TagRulePicker']={},['PZSurvivorToolkit/TagFilterPresetsMenu']={},
   ['PZSurvivorToolkit/InventoryRows']={captureAnchor=function()end,restoreAnchor=function()end,restoreSelection=function()end},
   ['PZSurvivorToolkit/InventoryCategoryGroups']={split=function()return false end},
   ['PZSurvivorToolkit/InventoryOrder']={prioritize=function()return false end},
   ['PZSurvivorToolkit/InventorySearch']={forPane=function()end},
   ['PZSurvivorToolkit/ItemTags']={enabled=function()return false end}}
  local real={['PZSurvivorToolkit/InventoryClasses']='client',
   ['PZSurvivorToolkit/InventoryMembership']='shared',
   ['PZSurvivorToolkit/ItemCategories']='shared',['PZSurvivorToolkit/ItemCategoryRules']='shared',
   ['PZSurvivorToolkit/ItemCategoryData']='shared',['PZSurvivorToolkit/LegacyItemCategories']='shared'}
  env.require=function(name)
   if presentation[name]then return presentation[name]end
   if modules[name]then return modules[name]end
   if real[name]then
    local path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/'..real[name]..'/'..name..'.lua'
    local chunk=assert(loadfile(path));setfenv(chunk,env);modules[name]=chunk();return modules[name]
   end
   error('unexpected preparation fixture dependency: '..name)
  end
  load(CleanUIInventoryTransferHandlerSource,env,'ISUI/ISInventoryPageTransferHandler.lua')
  for _,name in ipairs({'onTransferByNameClick','onTransferByCategoryClick','cleanUIClearQuickTransferHighlights'})do
   load(pageMethod(name),env,'ISUI/ISInventoryPage.lua')
  end
  setmetatable(personal,{__index=env.ISInventoryPage})
  for _,name in ipairs({'ToolkitItemCategories','PZSurvivorToolkit/InventoryFilter'})do
   local chunk=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..name..'.lua'))
   setfenv(chunk,env);chunk()
  end
  for _,fn in ipairs(boot)do fn()end
  for _,fn in ipairs(start)do fn()end
  personal.inventoryPane:refreshContainer()
  assert(candidate.category=='toolElectrical'and stock.category=='ToolWeapon',
   'fixture did not establish the real prepared-source/raw-target boundary')
  assert(not candidate:isFavorite()and not candidate:isEquipped()
   and env.ISInventoryPageTransferHandler.canTransferItem(candidate,target,player)
   and env.ISInventoryPageTransferHandler.canPlaceItemInContainer(candidate,target,0,player),
   'physical destination/protection controls did not allow the candidate')
  return {personal=personal,loot=loot,candidate=candidate,stock=stock,script=script,admitted=admitted,queued=queued}
 end
 local function exactIds(w,method,expected)
  local actual=method=='1'and w.admitted or w.queued
  local unused=method=='1'and w.queued or w.admitted
  assert(#actual==#expected and #unused==0,'unexpected admitted/queued item IDs')
  for index,id in ipairs(expected)do assert(actual[index]==id,'callback selected another physical item ID')end
  assert(w.script:getDisplayCategory()=='ToolWeapon'and w.candidate.originalCategory=='ToolWeapon'
   and w.stock.originalCategory=='ToolWeapon','preparation changed original/script categories')
 end
 for _,method in ipairs({'1','2'})do
  local category=preparationFixture(method)
  category.personal:onTransferByCategoryClick()
  exactIds(category,method,{})
  assert(category.stock.category=='ToolWeapon'and not category.loot.inventoryPane.refreshes and not category.loot:getIsVisible(),
   'category callback/observation prepared the raw physical target')
  local sameType=preparationFixture(method)
  sameType.personal:onTransferByNameClick()
  exactIds(sameType,method,{301})
  assert(sameType.stock.category=='ToolWeapon','same-type control repaired the target category')
  local refreshed=preparationFixture(method)
  refreshed.loot.inventoryPane:refreshContainer()
  assert(refreshed.stock.category=='toolElectrical','normal target refresh did not prepare the real category')
  refreshed.personal:onTransferByCategoryClick()
  exactIds(refreshed,method,{301})
 end
 print('PASS offline category boundary: real CleanUI callbacks/Toolkit wrappers reject raw physical target categories for methods 1/2; same-type and normal target-refresh controls admit exact ID 301')
end
print('PASS warehouse affinity: installed CleanUI type/category callbacks, native option snapshot/setValue/restore, exact admission IDs and guarded observations; stale aggregate is a controlled dependency demonstration only')
