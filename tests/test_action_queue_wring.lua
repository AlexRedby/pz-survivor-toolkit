-- Execute installed native Lua and registered Policy contracts. Clothing/actor
-- getters and sync transport are explicit models; this does not run a game.
if not NativeActionRoot then
 if TestCoverage then TestCoverage('source-contract','skipped','Wring contracts require --game or --native-action-root.')end
 return
end
-- Use the actual native derive hierarchy, including first-constructor __index.
NativeKahluaTableLookup=true
local function setup(changedSource,unusedBase)
 local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
 for _,path in ipairs({'shared/ISBaseObject.lua','shared/TimedActions/ISBaseTimedAction.lua',
  'client/TimedActions/ISTimedActionQueue.lua','client/TimedActions/ISQueueActionsAction.lua',
  'shared/TimedActions/ISReadABook.lua','client/TimedActions/ISInventoryTransferAction.lua'})do f.native(path)end
 f.native('client/TimedActions/WalkToTimedAction.lua')
 f.native('shared/TimedActions/ISInventoryTransferUtil.lua')
 f.native('shared/TimedActions/ISWringClothing.lua')
 f.native('shared/TimedActions/ISEatFoodAction.lua')
 f.native('shared/RadioCom/ISRadioAction.lua')
 for _,path in ipairs({'Fluids/ISFluidUtil.lua','Fluids/ISFluidContainer.lua','Fluids/ISFluidTransferAction.lua',
  'Fluids/ISFluidEmptyAction.lua','TimedActions/ISTransferAction.lua','TimedActions/ISDrinkFluidAction.lua'})do
  f.native('shared/'..path)
 end
 local nativeInstanceof=instanceof
 instanceof=function(value,name)
  return nativeInstanceof(value,name)or type(value)=='table'and (value.class=='Clothing'or value.class=='InventoryContainer')and name=='InventoryItem'
 end
 getClassSimpleName=function(value)return type(value)=='table'and value.class or 'Foreign'end
 getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
 getFirstLineOfClosure=NativeFirstLineOfClosure or function(callback)return debug.getinfo(callback,'S').linedefined+1 end
 getGameFilesInput=function(path)
  local filename=NativeActionRoot..'/'..path:gsub('^media/lua/','')
  local text
  if NativeReadText then text=NativeReadText(filename)
  else local input=assert(io.open(filename));text=input:read('*a');input:close()end
  text=text:gsub('\r','')
  if changedSource==true and path:find('ISWringClothing',1,true)then text=text..'-- changed native source\n'end
  local position=1
  return {close=function()end,readLine=function()
   if position>#text then return end
   local boundary=text:find('\n',position,true)or #text+1
   local line=text:sub(position,boundary-1);position=boundary+1;return line
  end}
 end
 getModFileReader=function(mod,path)
  assert(mod=='PZSurvivorToolkit')
  local filename=ProjectRoot..'/PZSurvivorToolkit/42/'..path
  local text
  if NativeReadText then text=NativeReadText(filename)
  else local input=assert(io.open(filename));text=input:read('*a');input:close()end
  text=text:gsub('\r','')
  if changedSource and path:find(changedSource==true and 'ISWringClothing' or changedSource,1,true)then text=text..'-- changed mod source\n'end
  local position=1
  return {close=function()end,readLine=function()
   if position>#text then return end
   local boundary=text:find('\n',position,true)or #text+1
   local line=text:sub(position,boundary-1);position=boundary+1;return line
  end}
 end
 local syncs=0
 syncItemFields=function(actor,item)assert(actor==f.player and item.class=='Clothing');syncs=syncs+1 end
 isClient,isServer=function()return false end,function()return false end
 f.player.class='IsoPlayer';f.player.getVehicle=function()end
 f.player.isLocalPlayer=function()return true end;f.player.isDraggingCorpse=function()return false end
 f.player.isEquipped=function()return false end;f.player.hasTrait=function()return false end
 f.player.isWearingAwkwardGloves=function()return false end
 getTimestampMs=function()return 1 end;getCore=function()return{getGameMode=function()return 'Sandbox'end}end
 CharacterTrait={DEXTROUS=1,ALL_THUMBS=2}
 local function list(values)return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
 local root={class='ItemContainer',items={},getType=function()return 'none'end,
  getParent=function()return f.player end,getContainingItem=function()end,
  getAcceptItemFunction=function()end,getOnlyAcceptCategory=function()end,
  getCapacityWeight=function(self)return self.load or 0 end,getEffectiveCapacity=function(self)return self.capacity or 100 end}
 root.getItemWithID=function(self,id)for _,item in ipairs(self.items)do if item:getID()==id then return item end end end
 root.getItemById=root.getItemWithID
 root.contains=function(self,item)return self:getItemWithID(item:getID())==item end
 root.isExistYet=function()return true end;root.isInCharacterInventory=function()return true end
 root.isVehicleSeat=function()return false end;root.getMaxWeight=function()return 100 end
 root.getItems=function(self)return list(self.items)end
 f.player.inventory=root
 local function clothing(location,wetness)
  local item=f.item('Base.ShirtDenim');item.class='Clothing';item.container=root;item.wetness=wetness or 90
  item.body=location or 'Shirt'
  item.getContainer=function(self)return self.container end
  item.wetnessReads=0
  item.getWetness=function(self)self.wetnessReads=self.wetnessReads+1;return self.wetness end
  item.setWetness=function(self,value)self.wetness=value end
  item.bodyReads=0;item.getBodyLocation=function(self)self.bodyReads=self.bodyReads+1;return self.body end
  item.isHumanCorpse=function()return false end
  item.getFluidContainer=function()end;item.getWorldItem=function()end;item.getIsCraftingConsumed=function()return false end
  item.getEquipParent=function()end;item.getAttachedSlot=function()return -1 end;item.getType=function()return 'ShirtDenim'end
  item.getUnequippedWeight=function(self)return 1+self.wetness/100 end;item.getActualWeight=item.getUnequippedWeight
  item.isFavorite=function()return false end
  root.items[#root.items+1]=item
  return item
 end
 local inheritedRequire=require;local modules={}
 require=function(name)
  if name=='PZSurvivorToolkit/ActionQueueEditModel'or name=='PZSurvivorToolkit/ActionQueueEditAdapters'
   or name=='PZSurvivorToolkit/ActionQueueWring'or name=='PZSurvivorToolkit/ActionQueueItemEditAdapters'then
   if not modules[name]then
    modules[name]=f.project(name:match('/([^/]+)$'))
   end
   return modules[name]
  end
  return inheritedRequire(name)
 end
 local operations=f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
 -- Load the actual native producer/helper bodies, not a transferIfNeeded stub.
 -- UI layout is irrelevant; native getActualItems is modeled as an exact list.
 local function nativeSource(path)
  if NativeReadText then return NativeReadText(NativeActionRoot..'/'..path):gsub('\r','')end
  local file=assert(io.open(NativeActionRoot..'/'..path));local text=file:read('*a');file:close();return text:gsub('\r','')
 end
 luautils={}
 local utilities=nativeSource('shared/luautils.lua')
 assert(loadstring(assert(utilities:match('(function luautils.walkToContainer%(.-\nend)'))..'\n'..
  assert(utilities:match('(function luautils.haveToBeTransfered%(.-\nend)'))..'\n'..
  assert(utilities:match('(luautils.getCorrectSquareForWall = function.-\nend)')),
  '@'..NativeActionRoot..'/shared/luautils.lua'))()
 local contextSource=nativeSource('client/ISUI/ISInventoryPaneContextMenu.lua')
 assert(loadstring(assert(contextSource:match('(function ISInventoryPaneContextMenu.transferIfNeeded%(.-\nend)'))..'\n'..
  assert(contextSource:match('(ISInventoryPaneContextMenu.onWringClothing = function.-\nend)')),
  '@'..NativeActionRoot..'/client/ISUI/ISInventoryPaneContextMenu.lua'))()
 ISInventoryPane.getActualItems=function(items)return items end
 local approach=f.project('ActionQueueApproach');assert(approach.install())
 local policy=f.project('ActionQueuePolicy')
 if unusedBase=='optional-engine'then
  ISBaseTimedAction.serverStart=ISBaseTimedAction.perform -- Even a same-file native callback was absent in this slot.
 elseif unusedBase=='missing-helper'then ISBaseTimedAction.setActionAnim=nil
 elseif unusedBase then
  ISBaseTimedAction.unrelatedUnusedHelper=function()error('unused base extension must not execute')end
  ISBaseTimedAction.overrideWeaponType=function()error('unused weapon helper must not execute')end
 end
 f.project('ActionQueueLabels');f.project('ActionQueue')
 local adapter=assert(modules['PZSurvivorToolkit/ActionQueueWring']);local installed=adapter.install()
 local origin=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
 assert(origin(ISBaseTimedAction.begin):match('ActionQueue.lua$')and origin(ISBaseTimedAction.stop):match('ActionQueue.lua$'),
  'fixture must install the actual owned native begin/stop boundaries')
 local function action(item)
  local value=ISWringClothing:new(f.player,item);value.toolkitQueueOperation={};return value
 end
 local function bag(item)
  local owner=f.item('Base.Bag_Schoolbag');owner.class='InventoryContainer';owner.container=root
  owner.getContainer=function(self)return self.container end
  owner.getFluidContainer=function()end;owner.getAmmoType=function()end;owner.isFavorite=function()return false end
  owner.getWorldItem=function()end;owner.getIsCraftingConsumed=function()return false end
  owner.getEquipParent=function()end;owner.getAttachedSlot=function()return -1 end
  owner.getType=function()return 'Bag_Schoolbag'end
  local inside={class='ItemContainer',items={item},load=item:getUnequippedWeight(),capacity=100}
  inside.getItems=root.getItems;inside.getItemWithID=root.getItemWithID;inside.getItemById=root.getItemById;inside.contains=root.contains
  inside.getType=function()return 'container'end;inside.getContainingItem=function()return owner end
  inside.getParent=function()end;inside.isExistYet=root.isExistYet;inside.getAcceptItemFunction=function(self)return self.filter end
  inside.getOnlyAcceptCategory=function()end;inside.isInCharacterInventory=root.isInCharacterInventory
  inside.isVehicleSeat=root.isVehicleSeat;inside.getMaxWeight=root.getMaxWeight
  inside.getCapacityWeight=root.getCapacityWeight;inside.getEffectiveCapacity=root.getEffectiveCapacity
  owner.getInventory=function()return inside end;owner.getUnequippedWeight=function()return 1+inside.load end
  owner.getActualWeight=owner.getUnequippedWeight;owner.getMaxItemSize=function()return 0 end
  for i=#root.items,1,-1 do if root.items[i]==item then table.remove(root.items,i)end end
  root.items[#root.items+1]=owner;item.container=inside
  return inside,owner
 end
 local function transfer(item,source,destination,token)
  local value=ISInventoryTransferAction:new(f.player,item,source,destination,10)
  value.toolkitQueueOperation=token or{};return value
 end
 return {f=f,operations=operations,approach=approach,root=root,clothing=clothing,action=action,adapter=adapter,policy=policy,installed=installed,bag=bag,transfer=transfer,
  definitions=PZSurvivorToolkit.ActionQueueDefinitions,model=PZSurvivorToolkit.ActionQueueEditModel,
  syncs=function()return syncs end}
end

for _,body in ipairs({'Shirt','Shoes'})do
 local s=setup();assert(s.installed)
 local item=s.clothing(body,90)
 local constructor,complete=ISWringClothing.new,ISWringClothing.complete
 local action=s.action(item)
 assert(action.maxTime==450 and action:isValid(),'native constructor and validity must execute unchanged')
 local reads=item.wetnessReads
 local contract,source=s.definitions.inspect(action)
 assert(item.wetnessReads==reads+1,'behavior matching read wetness/allocated the full contract twice')
 assert(source=='native.ISWringClothing'and contract and contract.items[item:getID()]and next(contract.targets)==nil)
 assert(contract.edit.capacity=='external'and contract.cancelWaiting and contract.interrupt=='finish-step')
 local cap=body=='Shoes'and 60 or 10
 assert(contract.edit.resources[1].facts.item==item and contract.edit.resources[1].facts.location==s.root)
 local follow=s.action(item)
 local result=s.model.evaluate({{action=action,edit=contract.edit},{action=follow,edit=s.adapter.inspect(follow).edit}})
 assert(result.status==(body=='Shoes'and 'allowed'or 'denied'),'native threshold/cap dependency was misprojected')
 assert(s.syncs()==0 and item:getWetness()==90,'permission inspection executed native completion')
 assert(action:complete()and item:getWetness()==cap and s.syncs()==1)
 assert(action:isValid()==(body=='Shoes'),'native shoe threshold must remain distinct from ordinary clothing')
 assert(ISWringClothing.new==constructor and ISWringClothing.complete==complete,'adapter replaced native execution')
end

-- B42 may expose ItemBodyLocation as an enum userdata, not the string used
-- by native ISWringClothing.complete. Preserve that exact vanilla predicate:
-- an enum-like Shoes value follows the ordinary cap instead of inventing 60.
do
 local tostringCalls=0
 local shoesLocation=setmetatable({}, {__tostring=function()tostringCalls=tostringCalls+1;return 'Shoes'end})
 assert(type(shoesLocation)~='string'and tostring(shoesLocation)=='Shoes')
 tostringCalls=0
 local s=setup();local item=s.clothing(shoesLocation,90);local action=s.action(item)
 local contract=assert(s.definitions.inspect(action))
 assert(contract.edit.resources[1].effects[1].cap==10,'enum-like body location incorrectly gained the string Shoes cap')
 assert(action:complete()and item:getWetness()==10 and not action:isValid()and s.syncs()==1,
  'actual native complete did not retain its string-only Shoes comparison')
 assert(tostringCalls==0,'adapter/native predicate must not coerce the body-location enum to a string')
end

-- Real Policy decisions consume registered exact contracts, not substituted
-- model descriptors. Reorder independent garments; protect the wetness producer.
do
 local s=setup();local f=s.f;assert(s.installed)
 local firstItem,secondItem=s.clothing('Shirt'),s.clothing('Pants')
 local first,second=s.action(firstItem),s.action(secondItem)
 local head=s.action(s.clothing('Shirt',95))
 head.action={isStarted=function()return true end,finished=function()return false end,
  isForceComplete=function()return false end,getTable=function()return head end}
 local same=s.action(head.item)
 local reads=head.item.wetnessReads
 head.item.getWetness=function()error('active effect value must not be observed')end
 local active=assert(s.definitions.inspect(head))
 assert(active.items[head.item:getID()]and next(active.targets)==nil and active.edit==nil
  and active.cancelWaiting==false and active.cancelOperation==false and active.interrupt=='finish-step')
 assert(head.item.wetnessReads==reads,'active footprint observed the in-flight wetness effect')
 local q=f.queue(head,first,second)
 assert(not s.policy.evaluateCancel(q,head,true).allowed,'active wring acquired cancellation authority')
 assert(not s.policy.evaluateMove(q,head,first).allowed,'active wring acquired move authority')
 assert(s.policy.evaluateMove(q,second,first).allowed,'independent pending wrings cannot share wetness by actor')
 assert(s.policy.evaluateCancel(q,first,true).allowed,'pending wring cancellation must preserve independent work')
 assert(q.queue[2]==first and q.queue[3]==second and s.syncs()==0,'decisions mutated native queue/effects')
 local duplicate=s.action(firstItem);q=f.queue(head,first,duplicate)
 local blocked=s.policy.evaluateMove(q,duplicate,first)
 assert(not blocked.allowed and blocked.reason=='edit_resource_amount','ordinary repeated wring must be rejected by the common wetness prerequisite')
 -- A pending cancellation can deliberately remove a redundant first wring;
 -- the retained action then sees the still-wet native item.
 assert(s.policy.evaluateCancel(q,first,true).allowed,'redundant wring must not invent a required producer')
 first.action={isStarted=function()return true end}
 local activeFirst=assert(s.definitions.inspect(first))
 assert(not activeFirst.edit and not activeFirst.cancelWaiting and not activeFirst.cancelOperation,
  'active wring acquired the pending contract')
 assert(not s.policy.evaluateCancel(q,first,true).allowed,'active wring acquired cancellation authority')
 q=f.queue(head,same)
 assert(not s.policy.evaluateMove(q,same,head).allowed,'in-flight same-item effects were treated as an independent forecast')
end

-- Native duration captures initial wetness. Natural drying before admission
-- does not justify rewriting maxTime or freezing a stale wetness forecast.
do
 local s=setup();local item=s.clothing('Shirt',90);local action=s.action(item)
 item.wetness=70
 local contract=assert(s.adapter.inspect(action))
 assert(action.maxTime==450 and contract.edit.resources[1].facts.wetness==70)
end
for _,change in ipairs({'foreign-item','bag','stale-item','wrong-wetness','callback','started','operation','flags','duration'})do
 local s=setup();local item=s.clothing();local action=s.action(item)
 if change=='foreign-item'then item.class='InventoryItem'
 elseif change=='bag'then item.container={class='ItemContainer'}
 elseif change=='stale-item'then s.root.items={s.clothing()};s.root.items[1].id=item.id
 elseif change=='wrong-wetness'then item.wetness=0/0
 elseif change=='callback'then action.onCompleteFunc=function()error('foreign callback must not execute')end
 elseif change=='started'then action.started=true
 elseif change=='operation'then action.toolkitQueueOperation.toolkitStarted=true
 elseif change=='flags'then action.forceProgressBar=false
 else action.maxTime=1000 end
 assert(not s.definitions.inspect(action),'unsupported pending wring acquired a contract: '..change)
 assert(s.syncs()==0,'rejected action executed an effect')
end
-- A source-correct callback returned through foreign lookup code is not
-- trusted provenance. Neither capture nor inspect may invoke that lookup.
do
 WringForeignLookupCalls=0
 local s=setup()
 local saved={};for key,value in pairs(ISBaseTimedAction)do saved[key]=value end
 ISBaseTimedAction.__index=function(_,key)WringForeignLookupCalls=WringForeignLookupCalls+1;return saved[key]end
 -- Load a fresh source owner after Queue hooks; installation must reject before
 -- looking up a single callback through the hostile native derive chain.
 local fresh=s.f.project('ActionQueueWring')
 assert(not fresh.install()and WringForeignLookupCalls==0,'install invoked foreign base __index before rejecting its chain')
end
for _,change in ipairs({'base-index','root-index','class-index','base-metatable','class-metatable','protected-class-metatable'})do
 local s=setup();assert(s.installed)
 local action=s.action(s.clothing())
 assert(getmetatable(ISWringClothing)==ISBaseTimedAction and getmetatable(ISBaseTimedAction)==ISBaseObject,
  'fixture does not use actual native ISBaseObject.derive hierarchy')
 local savedBase={};for key,value in pairs(ISBaseTimedAction)do savedBase[key]=value end
 local savedClass={};for key,value in pairs(ISWringClothing)do savedClass[key]=value end
 local calls=0
 local function foreign(_,key)
  calls=calls+1
  return savedClass[key]or savedBase[key]
 end
 if change=='base-index'then ISBaseTimedAction.__index=foreign
 elseif change=='root-index'then ISBaseObject.__index=foreign
 elseif change=='class-index'then ISWringClothing.__index=foreign
 elseif change=='base-metatable'then setmetatable(ISBaseTimedAction,{__index=foreign})
 elseif change=='class-metatable'then setmetatable(ISWringClothing,{__index=foreign})
 else setmetatable(ISWringClothing,{__index=foreign,__metatable=ISBaseTimedAction})end
 assert(not s.adapter.inspect(action)and not s.adapter.matches(action)and not s.adapter.callbacksTrusted(action),
  'changed native metatable/lookup chain retained wring authority: '..change)
 assert(calls==0 and s.syncs()==0,'inspection executed foreign inheritance code: '..change)
end

-- Unused base helpers are outside this family's call graph. Used helpers and
-- native engine slots, including previously absent callbacks, remain immutable.
for _,beforeInstall in ipairs({false,true})do
 local s=setup(false,beforeInstall);local item=s.clothing();local action=s.action(item)
 if not beforeInstall then
  ISBaseTimedAction.unrelatedUnusedHelper=function()error('unused base extension must not execute')end
  ISBaseTimedAction.overrideWeaponType=function()error('unused weapon helper must not execute')end
 end
 assert(s.installed and s.definitions.inspect(action),'unrelated base helper disabled wring provenance')
end
for _,change in ipairs({'optional-engine','missing-helper'})do
 local s=setup(false,change);local action=s.action(s.clothing())
 assert(not s.installed and not s.definitions.inspect(action),'changed native lookup slot was accepted during capture: '..change)
end
for _,name in ipairs({'setActionAnim','setAnimVariable','setOverrideHandModels','getJobDelta','create','adjustMaxTime',
 'forceCancel','isValidStart','isUsingTimeout','getDeltaModifiers','serverStart','serverStop','animEvent',
 'failedPathfind','succeededPathfind','timedActionPathfind'})do
 local s=setup();local action=s.action(s.clothing())
 ISBaseTimedAction[name]=function()error('changed used/engine callback must not execute')end
 assert(not s.definitions.inspect(action),'used or optional engine base slot was not protected: '..name)
 assert(s.syncs()==0)
end
for _,change in ipairs({'class-method','inherited-method','extra-method','global-sync','source'})do
 local s=setup(change=='source');local item=s.clothing();local action=s.action(item)
 if change=='class-method'then ISWringClothing.complete=function()error('foreign complete must not execute')end
 elseif change=='inherited-method'then ISBaseTimedAction.setActionAnim=function()error('foreign inherited helper must not execute')end
 elseif change=='extra-method'then ISWringClothing.foreign=function()error('foreign class method must not execute')end
 elseif change=='global-sync'then syncItemFields=function()error('foreign transport must not execute')end end
 assert(not s.definitions.inspect(action),'changed source/callback retained permission: '..change)
 assert(s.syncs()==0)
end
-- These were rejected as edit_unknown before the carried facts helper. The
-- whole visible fetch/body/optional-return group now projects real native
-- transfers; native completion and paid effects remain untouched by preview.
local function prepared(returning)
 local s=setup();local head=s.action(s.clothing('Shirt',95));head.action={}
 local item=s.clothing('Shirt',90);local source,owner=s.bag(item);local token={}
 local fetch=s.transfer(item,source,s.root,token);local body=s.action(item);body.toolkitQueueOperation=token
 local back=returning and s.transfer(item,s.root,source,token)or nil
 local tail=s.action(s.clothing('Pants',80))
 local q=back and s.f.queue(head,fetch,body,back,tail)or s.f.queue(head,fetch,body,tail)
 return s,q,head,item,source,owner,fetch,body,back,tail
end
for _,returning in ipairs({false,true})do
 local s,q,head,item,source,owner,fetch,body,back,tail=prepared(returning)
 local bodyContract=assert(s.adapter.inspect(body))
 local facts=bodyContract.edit.resources[1].facts
 assert(facts.item==item and facts.location==source and bodyContract.edit.resources[1].requires[1].equal==s.root)
 assert(bodyContract.containerOwners[owner:getID()]and bodyContract.itemTypes[owner:getFullType()])
 local transferContract=assert(s.definitions.inspect(fetch))
 assert(transferContract.edit.resources[1].facts.location==facts.location,'transfer and body disagree on live location')
 local reads,bodyReads=head.item.wetnessReads,head.item.bodyReads
 head.item.getWetness=function()error('active Wring must not read wetness for capacity')end
 head.item.getBodyLocation=function()error('active Wring must not read body location for capacity')end
 local before=item:getWetness();local context={}
 local decision=s.policy.evaluateMove(q,body,tail,true,context)
 assert(decision.allowed,'prepared Wring group move failed: '..tostring(decision.reason))
 assert(context.editFallback==nil,'prepared group escaped through legacy fallback instead of common projection')
 assert(decision.first==2 and decision.last==(back and 4 or 3),'move lost an operation preparation/return')
 assert(s.policy.evaluateCancel(q,body,true).allowed,'whole untouched prepared group must be cancellable')
 assert(head.item.wetnessReads==reads and head.item.bodyReads==bodyReads,'active capacity proof observed in-flight effects')
 local active=assert(s.adapter.inspect(head))
 assert(active.capacityNonIncreasing and not active.edit and not active.cancelOperation and not active.cancelWaiting)
 assert(item:getContainer()==source and item:getWetness()==before and s.syncs()==0 and q.queue[2]==fetch,
  'preview moved/changed/paid for a native item')
end

-- A physical bag location is a fact, not an assumed pickup. Missing or reordered
-- transfer effects cannot satisfy the root prerequisite, nor may a fetch alone
-- be dropped while its still-pending body is retained.
for _,change in ipairs({'missing-fetch','body-before-fetch','cancel-fetch'})do
 local s,q,head,item,source,owner,fetch,body,back,tail=prepared(false)
 local decision
 if change=='missing-fetch'then q=s.f.queue(head,body,tail);decision=s.policy.evaluateMove(q,body,tail,true)
 elseif change=='body-before-fetch'then q=s.f.queue(head,body,fetch,tail);decision=s.policy.evaluateMove(q,body,tail,true)
 else fetch.toolkitQueueOperation={};decision=s.policy.evaluateCancel(q,fetch,false)end
 assert(not decision.allowed,'unestablished native root location gained edit permission: '..change)
 assert(item:getContainer()==source and s.syncs()==0)
end

-- New bag permission proves the entire physical owner chain. The old root path
-- needs none of this metadata and remains cheap even when the helper is absent.
for _,change in ipairs({'orphan','replaced-owner','foreign-root','cycle','filter','dead-container','world','stale-item','nested-item','replaced-helper','helper-source'})do
 local s=setup(change=='helper-source'and 'ActionQueueItemEditAdapters.lua'or false)
 local item=s.clothing();local source,owner=s.bag(item);local action=s.action(item)
 if change=='orphan'then s.root.items={}
 elseif change=='replaced-owner'then
  local replacement=s.f.item(owner:getFullType());replacement.id=owner.id;s.root.items={replacement}
 elseif change=='foreign-root'then owner.container={class='ItemContainer',getItemWithID=function()return owner end}
 elseif change=='cycle'then owner.container=source;source.items[#source.items+1]=owner
 elseif change=='filter'then source.filter=function()error('custom filter must never execute')end
 elseif change=='dead-container'then source.isExistYet=function()return false end
 elseif change=='world'then source.getContainingItem=function()end
 elseif change=='stale-item'then
  local replacement=s.clothing();replacement.id=item.id;source.items={replacement}
 elseif change=='nested-item'then source.items={};source.getItemById=function()return item end
 elseif change=='replaced-helper'then
  PZSurvivorToolkit.ActionQueueItemEditAdapters.pendingCarriedItemLocation=function()error('replacement helper must not execute')end
 end
 assert(not s.definitions.inspect(action),'unsupported physical/source chain acquired a body contract: '..change)
 assert(s.syncs()==0)
 local rootItem=s.clothing();local rootAction=s.action(rootItem)
 s.root.getType=function()error('root body inspection must not traverse container metadata')end
 assert(s.adapter.inspect(rootAction),'bag helper rejection disabled ordinary root inspection: '..change)
end

do
 local s,q,head,item,source,owner,fetch,body,back,tail=prepared(true)
 -- Moving the source owner itself is an item dependency, not an unrelated read
 -- of the same actor or a shared bag-owner read between independent garments.
 local moveOwner=s.f.action(ISReadABook,{item=owner});moveOwner.toolkitQueueOperation={}
 local q2=s.f.queue(head,fetch,body,back,moveOwner,tail)
 assert(not s.policy.evaluateMove(q2,body,moveOwner,true).allowed,'bag owner mutation escaped the prepared component')
end

-- Keep the exact current wet transfer upper bound; drying cannot fund a later
-- transfer. SP may account only for its existing proven bag-source release;
-- Host retains the existing pessimistic source accounting.
for _,client in ipairs({false,true})do
 local s,q,head,item,source,owner,fetch,body,back,tail=prepared(true)
 isClient=function()return client end
 s.root.load=9;s.root.capacity=10
 local decision=s.policy.evaluateMove(q,body,tail,true)
 assert(not decision.allowed and decision.reason=='container_capacity','forecast drying granted future root capacity')
 s.root.load=0;s.root.capacity=100;source.capacity=source.load
 decision=s.policy.evaluateMove(q,body,tail,true)
 assert(not decision.allowed and decision.reason=='container_capacity','a full return bag gained drying-space credit')
end

-- A copied flag/source label, a foreign behavior inspector, or changed owner
-- pointers cannot authorize capacity traversal. Use the already cached tuple;
-- do not rerun a supposedly known inspector to bless a returned table.
for _,change in ipairs({'behavior','owner-inspector','source-pin','foreign-class'})do
 local s,q,head,item,source,owner,fetch,body,back,tail=prepared(false)
 if change=='behavior'then
  local entry=s.definitions.entries['native.ISWringClothing'];local previous=entry.behavior.inspect
  entry.behavior.inspect=function(action)return previous(action)end
 elseif change=='owner-inspector'then
  local previous=s.adapter.inspect;s.adapter.inspect=function(action)return previous(action)end
 elseif change=='source-pin'then
  local original=getModFileReader
  getModFileReader=function(mod,path)
   if path:find('ActionQueueWring.lua',1,true)then
    local lines={'foreign source'};return{readLine=function()return table.remove(lines,1)end,close=function()end}
   end
   return original(mod,path)
  end
 else body.onCompleteFunc=function()error('foreign callback must never execute')end end
 local decision=s.policy.evaluateMove(q,body,tail,true)
 assert(not decision.allowed,'unowned Wring descriptor granted capacity traversal: '..change)
 assert(s.syncs()==0)
end

-- Registry metadata can change after the captured inspector ran. Its lookup
-- shape must be rejected before even reading a callback-bearing inherited slot.
for _,change in ipairs({'registry-owner','entries','entry'})do
 local s,q,head,item,source,owner,fetch,body,back,tail=prepared(false)
 local calls=0;local saved=s.definitions.entries
 -- A native capacity getter is reached only after all descriptors were
 -- captured. Model registry replacement at that boundary, before a later
 -- Wring body is traversed; no ordinary Definitions lookup runs in between.
 local spare=s.clothing();local destination=s.bag(spare)
 local noise=s.transfer(spare,s.root,destination)
 q=s.f.queue(head,noise,fetch,body,tail)
 destination.getCapacityWeight=function(self)
  local function foreign(_,key)calls=calls+1;return saved[key]end
  if change=='registry-owner'then PZSurvivorToolkit.ActionQueueDefinitions=setmetatable({}, {__index=foreign})
  elseif change=='entries'then s.definitions.entries=setmetatable({}, {__index=foreign})
  else s.definitions.entries['native.ISWringClothing']=setmetatable({}, {__index=foreign})end
  return self.load
 end
 local decision=s.policy.evaluateMove(q,body,tail,true)
 assert(not decision.allowed and calls==0,'capacity authorization read hostile registry metadata: '..change)
 assert(s.syncs()==0)
end

-- Every nested carried owner participates, not just the innermost bag. Replaced
-- outer owners cannot retain permission through stale parent/container links.
do
 local s=setup();local item=s.clothing();local inner,innerOwner=s.bag(item)
 local outer,outerOwner=s.bag(innerOwner)
 local contract=assert(s.adapter.inspect(s.action(item)))
 assert(contract.edit.resources[1].facts.location==inner and contract.containerOwners[innerOwner:getID()]
  and contract.containerOwners[outerOwner:getID()],'nested owner proof lost a containing bag')
 local replacement=s.f.item(outerOwner:getFullType());replacement.id=outerOwner.id;s.root.items={replacement}
 assert(not s.adapter.inspect(s.action(item)),'replaced outermost carried owner retained permission')
end

-- Actual UI producer + Ops.run + installed Approach produce THREE pending
-- members: deferred native route, concrete fetch, native body. The route must
-- stay queued and source-bound, not be synchronously resolved or synthesized.
local function nativePrepared(returning,changedSource)
 local s=setup(changedSource);local head=s.action(s.clothing());head.action={}
 local q=s.f.queue(head);local item=s.clothing();local source,owner=s.bag(item)
 local before=#q.queue
 s.operations.run(function()ISInventoryPaneContextMenu.onWringClothing({item},s.f.player:getPlayerNum())end)
 local route,fetch,body=q.queue[before+1],q.queue[before+2],q.queue[before+3]
 assert(#q.queue==before+3 and route.Type=='ISQueueActionsAction'and fetch.Type=='ISInventoryTransferAction'
  and body.Type=='ISWringClothing'and s.approach.isContainer(route,source,s.f.player),
  'native transferIfNeeded/Approach must retain the actual route/fetch/body topology')
 assert(route.toolkitQueueOperation==fetch.toolkitQueueOperation and fetch.toolkitQueueOperation==body.toolkitQueueOperation)
 local back=returning and s.transfer(item,s.root,source,body.toolkitQueueOperation)or nil
 if back then ISTimedActionQueue.add(back)end
 local tail=s.action(s.clothing('Pants'));ISTimedActionQueue.add(tail)
 return s,q,head,item,source,owner,route,fetch,body,back,tail
end
for _,returning in ipairs({false,true})do
 local s,q,head,item,source,owner,route,fetch,body,back,tail=nativePrepared(returning)
 local command=route.toolkitQueueCommand
 local context={}
 local decision=s.policy.evaluateMove(q,body,tail,true,context)
 assert(decision.allowed and decision.spatialValidated and context.editFallback==nil,
  'genuine prepared Wring move failed: '..tostring(decision.reason))
 assert(decision.first==2 and decision.last==(returning and 5 or 4),'move lost a native prelude/return')
 assert(s.policy.evaluateCancel(q,body,true).allowed,'genuine unstarted prepared operation is not cancellable')
 local contract=assert(s.definitions.inspect(route))
 assert(not contract.edit and contract.positions[s.f.player], 'query-local carried lease leaked into ordinary inspection')
 assert(route.toolkitQueueCommand==command and not route.action and not route.started
  and q.queue[2]==route and item:getContainer()==source and s.syncs()==0,
  'inspection replaced/resolved the native route or paid an effect')
 -- The original native route still runs at its turn, expands to no children,
 -- and retains exact request/token/remaining native work. Model Java completion
 -- explicitly, not by running this callback during permission inspection.
 local count=#q.queue;local forced=0
 route.forceComplete=function()forced=forced+1 end
 q.current=route;table.remove(q.queue,1)
 route:start()
 assert(#q.queue==count-1 and q.queue[1]==route and q.queue[2]==fetch and forced==1,
  'native carried route did not retain its empty expansion boundary')
 assert(item:getContainer()==source and s.syncs()==0,'route prelude executed a transfer/body effect')
end
for _,change in ipairs({'not-carried','parent','helper','source','different-container','different-token','missing-fetch','too-large'})do
 local s,q,head,item,source,owner,route,fetch,body,back,tail=nativePrepared(false,change=='source'and 'ActionQueueApproach.lua'or false)
 if change=='not-carried'then source.isInCharacterInventory=function()return false end
 elseif change=='parent'then source.getParent=function()return {getSquare=function()error('world route must not execute')end}end
 elseif change=='helper'then
  PZSurvivorToolkit.ActionQueueItemEditAdapters.pendingCarriedContainer=function()error('foreign container helper must not execute')end
 elseif change=='different-container'then route.toolkitQueueCommand.snapshot.args[1]=s.root
 elseif change=='different-token'then fetch.toolkitQueueOperation={}
 elseif change=='missing-fetch'then table.remove(q.queue,3)
 else
  if change=='too-large'then for i=1,33 do ISTimedActionQueue.add(s.action(s.clothing()))end end
 end
 local decision=s.policy.evaluateMove(q,body,tail,true)
 assert(not decision.allowed,'uncertified genuine preparation escaped to legacy move permission: '..change)
 assert(item:getContainer()==source and s.syncs()==0)
end
-- A lease must recheck physical canonical ownership at the final boundary,
-- after ordinary inspections/source readers may have changed the live state.
for _,change in ipairs({'membership','owner','reparent','parent','carried','helper','request','token','actor','callback','descriptor','route-helper','primitive'})do
 local s,q,head,item,source,owner,route,fetch,body,back,tail=nativePrepared(false)
 local control=assert(s.approach.prepareCarriedContainerEditLease(route,source));assert(control())
 local check,edit=s.approach.prepareCarriedContainerEditLease(route,source);assert(check)
 local originalPcall=pcall
 if change=='membership'then s.root.items={}
 elseif change=='owner'then local replacement=s.f.item(owner:getFullType());replacement.id=owner.id;s.root.items={replacement}
 elseif change=='reparent'then local other=s.bag(s.clothing());owner.container=other;other.items[#other.items+1]=owner
 elseif change=='parent'then source.getParent=function()return {}end
 elseif change=='carried'then source.isInCharacterInventory=function()return false end
 elseif change=='helper'then PZSurvivorToolkit.ActionQueueItemEditAdapters.pendingCarriedContainer=function()error('foreign helper executed')end
 elseif change=='request'then route.toolkitQueueCommand.snapshot.args[1]=s.root
 elseif change=='token'then route.toolkitQueueOperation={}
 elseif change=='actor'then route.character={class='IsoPlayer'}
 elseif change=='callback'then route.toolkitQueueCommand.callback=function()error('foreign resolver executed')end
 elseif change=='descriptor'then edit.resources[1].facts.item=item
 elseif change=='route-helper'then luautils.walkToContainer=function()error('foreign route executed')end
 else pcall=function()error('foreign pcall executed')end end
 local valid=check();pcall=originalPcall
 assert(not valid,'stale carried preparation lease retained edit authority: '..change)
 assert(item:getContainer()==source and s.syncs()==0)
end

for _,change in ipairs({'cycle','duplicate-owner-id','wrong-fetch-actor','wrong-fetch-source'})do
 local s,q,head,item,source,owner,route,fetch,body,back,tail=nativePrepared(false)
 if change=='cycle'then owner.container=source;source.items[#source.items+1]=owner
 elseif change=='duplicate-owner-id'then
  local outer,outerOwner=s.bag(owner);owner.id=outerOwner.id
 elseif change=='wrong-fetch-actor'then fetch.character={class='IsoPlayer',getInventory=function()return s.root end}
 else fetch.srcContainer=s.root end
 assert(not s.approach.prepareCarriedContainerEditLease(route,source)or change=='wrong-fetch-actor'or change=='wrong-fetch-source',
  'malformed canonical carried chain acquired an edit lease: '..change)
 assert(not s.policy.evaluateMove(q,body,tail,true).allowed,'malformed route/fetch pairing acquired group authority: '..change)
 assert(item:getContainer()==source and s.syncs()==0)
end

if TestCoverage then TestCoverage('source-contract','passed')end
print('Wring pending contracts: installed native Lua, real Policy decisions, wetness caps, exact root/actor ownership and unchanged execution passed; canonical carried preparation and conservative capacity traversal; no active edits/recovery/outcome authority granted.')
