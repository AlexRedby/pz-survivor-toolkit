-- Real native producer and shared private group; actor/container effects are
-- explicit models. Native SP/Host effects belong to the grouped game bank.
if not NativeActionRoot then
 if TestCoverage then TestCoverage('source-contract','skipped','Prepared Equip requires native sources.')end
 return
end
NativeKahluaTableLookup=true
local setup=assert(loadfile(ProjectRoot..'/tests/support/queue_equip.lua'))()
local function fixture(host,borrowing)
 local s=setup(nil,true);s.mode(host,false)
 local f,actor,root=s.f,s.actor,s.root
 actor.isEquipped=function(self,item)return self.primary==item or self.secondary==item end
 actor.isLocalPlayer=function()return true end;actor.isDraggingCorpse=function()return false end
 actor.hasTrait=function()return false end;actor.isWearingAwkwardGloves=function()return false end
 CharacterTrait={DEXTROUS=1,ALL_THUMBS=2}
 getTimestampMs=function()return 1 end;getCore=function()return{getGameMode=function()return 'Sandbox'end}end
 actor.getVehicle=function()end;actor.getX=function()return 0 end;actor.getY=actor.getX;actor.getZ=actor.getX
 actor.getSquare=function()return {}end
 actor.getWornItems=function()return {size=function()return 0 end}end
 actor.getCharacterActions=function()return {contains=function()return false end}end
 local function list(items)
  local result={};for _,item in pairs(items)do result[#result+1]=item end
  return {size=function()return #result end,get=function(_,index)return result[index+1]end}
 end
 local function container(value,owner)
  value.items=value.items or{};value.class='ItemContainer'
  value.getItemWithID=function(self,id)return self.items[id]end
  value.getItemById=value.getItemWithID
  value.getItems=function(self)return list(self.items)end
  value.contains=function(self,item)return self.items[item:getID()]==item end
  value.getType=function()return 'container'end;value.isExistYet=function()return true end
  value.getContainingItem=function()return owner end;value.getParent=function()if not owner then return actor end end
  value.getAcceptItemFunction=function(self)return self.filter end;value.getOnlyAcceptCategory=function()end
  value.isInCharacterInventory=function()return true end;value.isVehicleSeat=function()return false end
  value.getMaxWeight=function()return 100 end;value.getCapacityWeight=function()return 0 end
  value.getEffectiveCapacity=value.getMaxWeight;value.getInventoryContainer=function()return owner end
  value.hasRoomFor=function(self)return not self.full end;value.isRemoveItemAllowed=function()return true end
  value.isItemAllowed=function()return true end;value.isInside=function()return false end
  return value
 end
 container(root)
 local target=s.item();local bag=f.item('Base.Bag_Schoolbag');bag.class='InventoryContainer';bag.container=root
 bag.getContainer=function(self)return self.container end
 root.items[bag:getID()]=bag
 local source=container({items={[target:getID()]=target}},bag);root.items[target:getID()]=nil;target.container=source
 bag.getInventory=function()return source end;bag.getMaxItemSize=function()return 0 end
 bag.getActualWeight=function()return 1 end;bag.getUnequippedWeight=bag.getActualWeight
 for _,item in ipairs({target,bag})do
  item.getActualWeight=function()return 1 end;item.getUnequippedWeight=item.getActualWeight
  item.getActualWeightUnmodded=item.getActualWeight;item.getFluidContainer=function()end
  item.getCondition=function()return 10 end;item.getFavorite=function()return false end
  item.isFavorite=function()return false end;item.isHumanCorpse=function()return false end
  item.getEquipParent=function()end
  item.getType=function()return 'Nails'end;item.getDisplayName=item.getType
 end
 for _,path in ipairs({'client/TimedActions/ISInventoryTransferAction.lua','client/TimedActions/ISQueueActionsAction.lua','client/TimedActions/WalkToTimedAction.lua',
  'shared/TimedActions/ISInventoryTransferUtil.lua'})do f.native(path)end
 local operations=f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
 require('PZSurvivorToolkit/ActionQueueItemEditAdapters')
 local adapters=assert(PZSurvivorToolkit.ActionQueueItemEditAdapters)
 local previous=require
 require=function(name)if name=='PZSurvivorToolkit/ActionQueueItemEditAdapters'then return adapters end;return previous(name)end
 luautils={}
 local text=s.sourceText('shared/luautils.lua')
 assert(loadstring(assert(text:match('(function luautils.walkToContainer%(.-\nend)'))..'\n'..
  assert(text:match('(function luautils.haveToBeTransfered%(.-\nend)'))..'\n'..
  assert(text:match('(luautils.getCorrectSquareForWall = function.-\nend)')),
  '@'..NativeActionRoot..'/shared/luautils.lua'))()
 text=s.sourceText('client/ISUI/ISInventoryPaneContextMenu.lua')
 assert(loadstring(assert(text:match('(function ISInventoryPaneContextMenu.transferIfNeeded%(.-\nend)'))..'\n'..
  assert(text:match('(ISInventoryPaneContextMenu.equipWeapon = function.-\nend)'))..'\n'..
  assert(text:match('(ISInventoryPaneContextMenu.OnPrimaryWeapon = function.-\nend)')),
  '@'..NativeActionRoot..'/client/ISUI/ISInventoryPaneContextMenu.lua'))()
 ISInventoryPane={getActualItems=function(items)return items end}
 local approach=f.project('ActionQueueApproach');assert(approach.install())
 local policy=f.project('ActionQueuePolicy');f.project('ActionQueueLabels');local api=f.project('ActionQueue')
 local front=f.action(ISReadABook,{item=s.item()});local q=f.queue(front)
 local ledger=PZSurvivorToolkit.ActionQueueSettlement
 assert(ledger.track(front,'body'));ledger.started(front);front.toolkitQueueOperation.toolkitStarted=true;front.action={}
 operations.run(function()ISInventoryPaneContextMenu.OnPrimaryWeapon({target},actor:getPlayerNum())end)
 local route,fetch,body=q.queue[2],q.queue[3],q.queue[4]
 assert(route and fetch and body and #q.queue==4,'real menu did not produce the complete prepared triplet')
 assert(route.Type=='ISQueueActionsAction'and fetch.Type=='ISInventoryTransferAction'and body.Type=='ISEquipWeaponAction')
 local other=s.action(s.item('HandWeapon'),false,false);ISTimedActionQueue.add(other)
 local tail=f.action(ISReadABook,{item=s.item()});ISTimedActionQueue.add(tail)
 local scope
 if borrowing then
  scope=ledger.deferred(actor,front.toolkitQueueOperation)
  for _,member in ipairs(q.queue)do assert(ledger.remember(scope,member,policy.inspect(member)))end
  assert(ledger.preparePickup(scope,fetch),'real prepared pickup registration failed')

 end
 return s,policy,api,q,route,fetch,body,other,tail,source,target,bag,ledger,adapters,scope
end
for _,host in ipairs({false,true})do
 local s,p,api,q,route,fetch,body,other,tail,source,item=fixture(host)
 local decision=p.evaluateMove(q,body,other,true)
 assert(decision.allowed and decision.nativeSchedule,'prepared menu move denied: '..tostring(decision.reason))
 assert(api.move(q,fetch,other,true)and q.queue[2]==other and q.queue[3]==route and q.queue[4]==fetch and q.queue[5]==body)
 assert(item:getContainer()==source and s.effects()==0,'pending group edit moved an item or ran a native effect')
 assert(api.cancel(q,fetch)and #q.queue==3 and q.queue[2]==other and q.queue[3]==tail,'fetch cancellation split the validated operation')
end
for _,host in ipairs({false,true})do
 local s,p,api,q,route,fetch,body,other=fixture(host,true)
 local decision=p.evaluateMove(q,body,other,true)
 assert(decision.allowed and decision.nativeSchedule,'prepared scope with an independent native Equip denied: '..tostring(decision.reason))
end
local function recordOf(action)
 for key,seal in pairs(action.toolkitQueueOperation)do
  if type(key)=='table'and type(seal)=='function'then return assert(seal(action.toolkitQueueOperation))end
 end
 error('missing actual operation record')
end
for _,host in ipairs({false,true})do
 local s,p,api,q,route,fetch,body=fixture(host,true)
 local borrowed=recordOf(fetch).borrowings[1].candidate
 assert(borrowed.phase=='prepare')
 assert(api.cancel(q,body),'public prepared cancellation failed with actual pickup bookkeeping')
 assert(borrowed.phase=='waived'and borrowed.waiverReason=='cancelled-before-start',
  'public cancellation left a never-started borrowing open')
end
-- Cancelling a never-started intent must release its live scope claims, so a
-- replacement request can be edited while the original reader still runs.
for _,host in ipairs({false,true})do
 local s,p,api,q,route,fetch,body,other,tail,source,item,bag,ledger,adapters,scope=fixture(host,true)
 assert(api.cancel(q,body))
 local prior={};for _,member in ipairs(q.queue)do prior[member]=true end
 PZSurvivorToolkit.ActionQueueOperations.run(function()ISInventoryPaneContextMenu.OnPrimaryWeapon({item},s.actor:getPlayerNum())end)
 local added={}
 for _,member in ipairs(q.queue)do if not prior[member]then
  added[#added+1]=member;assert(ledger.remember(scope,member,p.inspect(member)))
 end end
 assert(#added==3 and ledger.preparePickup(scope,added[2]))
 local decision=p.evaluateMove(q,added[3],other)
 assert(decision.allowed,'cancelled unstarted scope claim blocked replacement equipment: '..tostring(decision.reason))
 assert(api.move(q,added[3],other),'replacement group failed at public move')
 assert(api.cancel(q,added[2]),'replacement group failed at public cancellation')
 assert(item:getContainer()==source and s.effects()==0,'replacing cancelled intent changed native item state')
end
for _,fault in ipairs({'same-input','split','allocated','missing-owner','candidate-owner','outside-equipment-reader','unknown-reader','late-cleanup'})do
 local s,p,api,q,route,fetch,body,other,tail,source,item,bag,ledger,adapters,scope=fixture(false,true)
 if fault=='same-input'then other.item=item
 elseif fault=='split'then table.remove(q.queue,3)
 elseif fault=='allocated'then fetch.action={}
 elseif fault=='missing-owner'then s.root.items[bag:getID()]=nil
 elseif fault=='candidate-owner'then recordOf(fetch).borrowings[1].candidate.sourceOwner.fullType='Base.Counterfeit'
 elseif fault=='outside-equipment-reader'then
  scope.tasks[{}]={items={},pickups={},actions={},readsEquipment=true}
 elseif fault=='unknown-reader'then scope.tasks[other.toolkitQueueOperation].unknownInputs=true
 else tail.item.getID=function(self)ledger.track(fetch,'cleanup');return self.id end end
 local decision=p.evaluateMove(q,body,other,true)
 assert(not decision.allowed,fault..': prepared proof escaped its owned complete-input boundary')
 assert(item:getContainer()==source and s.effects()==0,fault..': rejected edit changed native state')
end
do
 local s,p,api,q,route,fetch,body,other,tail,source,item,bag,ledger=fixture(true,true)
 local original=PZSurvivorToolkit.Settings.actionQueue;local armed=false
 PZSurvivorToolkit.Settings.actionQueue=function()
  if armed then recordOf(fetch).borrowings[1].candidate.sourceOwner.fullType='Base.Changed' end
  return original()
 end
 local decision=p.evaluateMove(q,body,other,true);assert(decision.allowed)
 armed=true;assert(not p.editUnchanged(q,decision.snapshot),'commit renewed prepared borrowing ownership')
 assert(item:getContainer()==source and s.effects()==0)
end
-- Settings callbacks run again at commit. Original carried owner identity,
-- location and type remain bound, even if a later route is otherwise valid.
for _,fault in ipairs({'orphan','owner-type'})do
 local s,p,api,q,route,fetch,body,other,tail,source,item,bag=fixture(true,true)
 local original=PZSurvivorToolkit.Settings.actionQueue;local armed=false
 local ownerType=bag:getFullType()
 bag.getFullType=function()return ownerType end
 PZSurvivorToolkit.Settings.actionQueue=function()
  if armed then
   if fault=='orphan'then s.root.items[bag:getID()]=nil;bag.container=nil
   else ownerType='Base.ChangedBag'end
  end
  return original()
 end
 local decision=p.evaluateMove(q,body,other,true);assert(decision.allowed)
 armed=true
 assert(not p.editUnchanged(q,decision.snapshot),'commit renewed original carried owner: '..fault)
end
-- Exercise the public mutation boundary too, injecting only at its last
-- Settings callback rather than rejecting during earlier metadata inspection.
for _,operation in ipairs({'move','cancel'})do
 local function attempt(mutateAt)
  local s,p,api,q,route,fetch,body,other,tail,source,item,bag=fixture(true,true)
  local original=PZSurvivorToolkit.Settings.actionQueue;local calls=0
  PZSurvivorToolkit.Settings.actionQueue=function()
   calls=calls+1
   if calls==mutateAt then s.root.items[bag:getID()]=nil;bag.container=nil end
   return original()
  end
  local before={};for index,member in ipairs(q.queue)do before[index]=member end
  local ok
  if operation=='move'then ok=api.move(q,body,other,true)else ok=api.cancel(q,fetch)end
  if mutateAt then
   assert(not ok,'public '..operation..' accepted stale carried ancestry at commit')
   assert(#q.queue==#before,'rejected '..operation..' changed queue length')
   for index,member in ipairs(before)do assert(q.queue[index]==member,'rejected '..operation..' changed queue order')end
  else assert(ok,'baseline public '..operation..' failed')end
  return calls
 end
 local calls=attempt()
 assert(calls>0);attempt(calls)
end
-- Native Equip checks root admission itself and rebinds a replicated item;
-- a failed pickup cannot produce a hand effect just because the ID is nested.
do
 local s,p,api,q,route,fetch,body,other,tail,source,item=fixture(true)
 assert(body:isValid()==false,'nested input passed native Equip before pickup')
 local canonical=s.item();s.root.items[canonical.id]=nil;source.items[item:getID()]=nil
 canonical.id=item:getID();s.root.items[canonical.id]=canonical
 assert(body:isValid()==true and body.item==canonical,'native Equip did not resolve the canonical root item')
end
-- Moving a command is not future admission. Native SP capacity still refuses
-- the fetch at execution, and the following Equip cannot use its nested input.
do
 local s,p,api,q,route,fetch,body,other,tail,source,item=fixture(false)
 s.root.full=true
 assert(fetch:isValid()==false,'native SP fetch bypassed destination capacity')
 assert(body:isValid()==false and item:getContainer()==source and s.effects()==0,'unpaid failed fetch acquired equipment')
 s.root.full=false
 assert(fetch:isValid()==true,'native SP fetch rejected unchanged permitted input')
end
print('Prepared native Equip: genuine menu triplets, whole-group move/cancel, no editor effects and native canonical admission passed.')
