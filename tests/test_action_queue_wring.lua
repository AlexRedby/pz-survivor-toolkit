-- Execute installed native Lua and registered Policy contracts. Clothing/actor
-- getters and sync transport are explicit models; this does not run a game.
if not NativeActionRoot then
 if TestCoverage then TestCoverage('source-contract','skipped','Wring contracts require --game or --native-action-root.')end
 return
end
-- Use the actual native derive hierarchy, including first-constructor __index.
NativeKahluaTableLookup=true
local function setup(changedSource,unusedBase,policyFirst)
 local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
 for _,path in ipairs({'shared/ISBaseObject.lua','shared/TimedActions/ISBaseTimedAction.lua',
  'client/TimedActions/ISTimedActionQueue.lua','client/TimedActions/ISQueueActionsAction.lua',
  'shared/TimedActions/ISReadABook.lua','client/TimedActions/ISInventoryTransferAction.lua'})do f.native(path)end
 f.native('client/TimedActions/WalkToTimedAction.lua')
 f.native('shared/TimedActions/ISInventoryTransferUtil.lua')
 ItemBodyLocation={HAT='Hat',FULL_HAT='FullHat',LEFT_WRIST='LeftWrist',RIGHT_WRIST='RightWrist'}
 ItemTag={REPLACE_PRIMARY='ReplacePrimary',WEARABLE='Wearable'}
 local wearText
 if NativeReadText then wearText=NativeReadText(NativeActionRoot..'/shared/TimedActions/ISWearClothing.lua')
 else local input=assert(io.open(NativeActionRoot..'/shared/TimedActions/ISWearClothing.lua'));wearText=input:read('*a');input:close()end
 for name in wearText:gmatch('ItemBodyLocation%.([%w_]+)')do ItemBodyLocation[name]=ItemBodyLocation[name]or name end
 f.native('shared/TimedActions/ISEquipWeaponAction.lua')
 f.native('shared/TimedActions/ISWearClothing.lua')
 f.native('shared/TimedActions/ISUnequipAction.lua')
 f.native('shared/TimedActions/ISWringClothing.lua')
 f.native('shared/TimedActions/ISEatFoodAction.lua')
 f.native('shared/RadioCom/ISRadioAction.lua')
 for _,path in ipairs({'Fluids/ISFluidUtil.lua','Fluids/ISFluidContainer.lua','Fluids/ISFluidTransferAction.lua',
  'Fluids/ISFluidEmptyAction.lua','TimedActions/ISTransferAction.lua','TimedActions/ISDrinkFluidAction.lua'})do
  f.native('shared/'..path)
 end
 local nativeInstanceof=instanceof
 instanceof=function(value,name)
  return nativeInstanceof(value,name)or type(value)=='table'and (value.class=='Clothing'or value.class=='InventoryContainer'or value.class=='HandWeapon')and name=='InventoryItem'
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
 local receiveAck
 Events.OnServerCommand.Add=function(callback)receiveAck=callback end
 local syncs=0
 syncItemFields=function(actor,item)assert(actor==f.player and item.class=='Clothing');syncs=syncs+1 end
 local client,server=policyFirst==true,false
 isClient,isServer=function()return client end,function()return server end
 f.player.class='IsoPlayer';f.player.getVehicle=function()end
 f.player.getOnlineID=function()return 7 end
 f.player.isLocalPlayer=function()return true end;f.player.isDraggingCorpse=function()return false end
 local worn={}
 f.player.getPrimaryHandItem=function(self)return self.primary end;f.player.getSecondaryHandItem=function(self)return self.secondary end
 f.player.isEquipped=function(self,item)return self.primary==item or self.secondary==item or worn[item.body]==item end
 f.player.getWornItem=function(_,location)return worn[location]end
 f.player.getWornItems=function()
  local entries={};for location,item in pairs(worn)do entries[#entries+1]={getItem=function()return item end,getLocation=function()return location end}end
  return{size=function()return #entries end,get=function(_,index)return entries[index+1]end,contains=function(_,item)return worn[item.body]==item end}
 end
 local group={getLocation=function(_,location)return location end,isMultiItem=function()return false end,isExclusive=function()return false end}
 f.player.getBodyLocationGroup=function()return group end
 f.player.removeWornItem=function(_,item)worn[item.body]=nil end
 getPlayerHotbar=function()return{isItemAttached=function()return false end}end
 sendEquip=function()end;triggerEvent=function()end
 f.player.hasTrait=function()return false end
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
 root.setDrawDirty=function()end
 root.isItemAllowed=function()return true end
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
  item.getEquipParent=function()end;item.getAttachedSlot=function()return -1 end;item.isFakeEquipped=function()return false end;item.getType=function()return 'ShirtDenim'end
  item.getUnequippedWeight=function(self)return 1+self.wetness/100 end;item.getActualWeight=item.getUnequippedWeight
  item.getCategory=function()return 'Clothing'end;item.canBeEquipped=function()end
  item.hasTag=function()return false end;item.isBroken=function()return false end
  item.isForceDropHeavyItem=function()return false end;item.canBeActivated=function()return false end
  item.getClothingItem=function()return {}end;item.getEquippedWeight=function(self)return self:getUnequippedWeight()*.3 end
  item.getUnequipSound=function()end;item.IsInventoryContainer=function()return false end
  item.setJobDelta=function()end;item.setJobType=function()end
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
 if not policyFirst then f.project('ActionQueueLifecycle');f.project('ActionQueueAcknowledgements')end
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
 if policyFirst then assert(PZSurvivorToolkit.ActionQueueLifecycle and PZSurvivorToolkit.ActionQueueAcknowledgements,
  'direct first Policy load did not require its admission observer dependencies')end
 if unusedBase=='optional-engine'then
  ISBaseTimedAction.serverStart=ISBaseTimedAction.perform -- Even a same-file native callback was absent in this slot.
 elseif unusedBase=='missing-helper'then ISBaseTimedAction.setActionAnim=nil
 elseif unusedBase then
  ISBaseTimedAction.unrelatedUnusedHelper=function()error('unused base extension must not execute')end
  ISBaseTimedAction.overrideWeaponType=function()error('unused weapon helper must not execute')end
 end
 f.project('ActionQueueLabels');f.project('ActionQueue')
 local installedObserver=PZSurvivorToolkit.ActionQueueClothing.installObserver()
 assert(installedObserver==(changedSource~='ActionQueueLifecycle.lua'),'fixture observer bootstrap differs from its declared source proof')
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
  owner.getInventory=function()return inside end;owner.getActualWeightUnmodded=function()return 1 end
  owner.isFakeEquipped=function()return false end;owner.getUnequippedWeight=function()return 1+inside.load end
  owner.getActualWeight=owner.getUnequippedWeight;owner.getMaxItemSize=function()return 0 end
  for i=#root.items,1,-1 do if root.items[i]==item then table.remove(root.items,i)end end
  root.items[#root.items+1]=owner;item.container=inside
  return inside,owner
 end
 local function transfer(item,source,destination,token)
  local value=ISInventoryTransferAction:new(f.player,item,source,destination,10)
  value.toolkitQueueOperation=token or{};return value
 end
 return {f=f,setClient=function(value)client=value end,setSourceChange=function(value)changedSource=value end,receiveAck=function(...)assert(receiveAck)(...)end,operations=operations,approach=approach,root=root,worn=worn,group=group,clothing=clothing,action=action,adapter=adapter,policy=policy,installed=installed,bag=bag,transfer=transfer,
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

-- Native worn preparation uses its genuine Unequip member, not a special Wring
-- rule. The same item/slot effect is available to any complete common producer.
local function wornPrepared()
 local s=setup();local head=s.action(s.clothing('Shirt'));head.action={}
 local q=s.f.queue(head)
 local function append(location,weight)
  local item=s.clothing(location,90);item.weight=weight or 1
  item.getUnequippedWeight=function(self)self.weightReads=(self.weightReads or 0)+1;return self.weight end
  item.getEquippedWeight=function(self)self.equippedReads=(self.equippedReads or 0)+1;return self.weight*.3 end
  s.worn[location]=item
  local before=#q.queue
  s.operations.run(function()ISInventoryPaneContextMenu.onWringClothing({item},s.f.player:getPlayerNum())end)
  local remove,body=q.queue[before+1],q.queue[before+2]
  assert(#q.queue==before+2 and getmetatable(remove)==ISUnequipAction and getmetatable(body)==ISWringClothing
   and remove.item==item and body.item==item and remove.toolkitQueueOperation==body.toolkitQueueOperation,
   'actual native worn Wring producer did not retain Unequip/body')
  return item,remove,body
 end
 return s,q,head,append
end
do
 local s,q,head,append=wornPrepared()
 local first,remove,body=append(ItemBodyLocation.SOCKS,1)
 local second,otherRemove,otherBody=append(ItemBodyLocation.HANDS,1)
 local beforeWeight,beforeEquipped=first.weightReads or 0,first.equippedReads or 0
 s.root.getCapacityWeight=function()error('ordinary row inspection read capacity')end
 local contract,source=s.definitions.inspect(remove)
 assert(contract and source=='native.ISUnequipAction'and contract.edit and contract.clothingRemoval
  and contract.hands==s.f.player and contract.preparation and not contract.cancelWaiting)
 assert(contract.edit.resources[1].facts.worn==true and contract.edit.resources[1].effects[1].set==false)
 assert((first.weightReads or 0)==beforeWeight and(first.equippedReads or 0)==beforeEquipped,
  'ordinary row inspection performed weight/capacity work')
 s.root.getCapacityWeight=function(self)return self.load or 0 end
 local context={};local decision=s.policy.evaluateMove(q,body,otherBody,true,context)
 assert(decision.allowed and context.editFallback==nil,'native worn group did not use complete common projection: '..tostring(decision.reason))
 assert(s.policy.evaluateCancel(q,body,true).allowed,'unstarted whole Unequip/body group cannot be cancelled')
 assert(not s.policy.evaluateCancel(q,remove,false).allowed,'individual removal broke its native preparation group')
 local duplicate=ISUnequipAction:new(s.f.player,first,50);duplicate.toolkitQueueOperation={}
 ISTimedActionQueue.add(duplicate)
 assert(not s.policy.evaluateMove(q,duplicate,remove).allowed,'same garment was projected as worn twice')
 assert(s.worn[first.body]==first and s.worn[second.body]==second and s.syncs()==0,'inspection executed native equipment or Wring effects')
end
-- The no-transfer entry must account for every retained positive producer in
-- proposed order. Standalone C+2U checks would incorrectly accept A then B.
do
 local s,q,head,append=wornPrepared()
 local a,removeA,bodyA=append(ItemBodyLocation.SOCKS,1)
 local b,removeB,bodyB=append(ItemBodyLocation.HANDS,1.5)
 s.root.load,s.root.capacity=10,13.75
 local context={};local decision=s.policy.evaluateMove(q,bodyB,removeA,false,context)
 assert(decision.allowed and context.editFallback==nil,'B then A should fit its conservative no-drop peaks: '..tostring(decision.reason))
 local reverse=s.f.queue(head,removeB,bodyB,removeA,bodyA)
 decision=s.policy.evaluateMove(reverse,bodyA,removeB,false)
 assert(not decision.allowed and decision.reason=='container_capacity','independent static removal gates missed cumulative worn growth')
 s.root.capacity=12.25;ISTimedActionQueue.queues[s.f.player]=q
 assert(s.policy.evaluateCancel(q,bodyB,true).allowed,'cancelling an unadmitted removal retained its hypothetical +U growth')
 assert(not s.policy.evaluateMove(q,bodyA,bodyB,true).allowed,'overfull removal acquired release credit')
end
-- Existing transfers and the new positive producer share exactly one prefix
-- walker. Moving pickup after removal can make the native no-drop peak safe.
do
 local s,q,head,append=wornPrepared();local worn,remove,body=append(ItemBodyLocation.SOCKS,1)
 local cargo=s.clothing('Pants');cargo.getUnequippedWeight=function()return 2 end;cargo.getActualWeight=cargo.getUnequippedWeight
 local bag=s.bag(cargo);local pickup=s.transfer(cargo,bag,s.root,{})
 ISTimedActionQueue.add(pickup);s.root.load,s.root.capacity=10,13.25
 local decision=s.policy.evaluateMove(q,pickup,remove,false)
 assert(not decision.allowed and decision.reason=='container_capacity','pickup prefix was omitted from removal peak')
 local reverse=s.f.queue(head,pickup,remove,body)
 local context={};decision=s.policy.evaluateMove(reverse,body,pickup,false,context)
 assert(decision.allowed and context.editFallback==nil,'removal then pickup should fit without future release credit: '..tostring(decision.reason))
end
for _,change in ipairs({'held','hotbar','heavy','activation','head','multi','exclusive','alias','owner','callback','base-index','negative-weight','negative-equipped','item-disallowed','module-source','custom-root','owner-inspect-meta','owner-bindings-meta','owner-weight-meta'})do
 local s,q,head,append=wornPrepared();local item,remove,body=append(ItemBodyLocation.SOCKS,1)
 local second,otherRemove,otherBody=append(ItemBodyLocation.HANDS,1)
 local calls=0
 if change=='held'then s.f.player.primary=item
 elseif change=='hotbar'then remove.fromHotbar=true
 elseif change=='heavy'then item.isForceDropHeavyItem=function()return true end
 elseif change=='activation'then item.canBeActivated=function()return true end
 elseif change=='head'then s.worn[item.body]=nil;item.body=ItemBodyLocation.HAT;s.worn[item.body]=item
 elseif change=='multi'then s.group.isMultiItem=function()return true end
 elseif change=='exclusive'then s.group.isExclusive=function()return true end
 elseif change=='alias'then local replacement=s.clothing(item.body);replacement.id=item.id;s.root.items={replacement,second}
 elseif change=='owner'then PZSurvivorToolkit.ActionQueueClothing={}
 elseif change=='callback'then remove.onCompleteFunc=function()calls=calls+1 end
 elseif change=='base-index'then ISBaseTimedAction.__index=function()calls=calls+1;error('foreign inherited lookup executed')end
 elseif change=='negative-weight'then item.getUnequippedWeight=function()return -1 end
 elseif change=='negative-equipped'then item.getEquippedWeight=function()return -1 end
 elseif change=='item-disallowed'then s.root.isItemAllowed=function()return false end
 elseif change=='custom-root'then
  s.root.getAcceptItemFunction=function()return function()calls=calls+1 end end
  s.root.isItemAllowed=function()calls=calls+1;error('custom root callback executed')end
 elseif change:find('^owner%-')then
  local module=PZSurvivorToolkit.ActionQueueClothing
  local field=change=='owner-inspect-meta'and 'inspect'or change=='owner-bindings-meta'and 'bindingsTrusted'or 'removalWeight'
  module[field]=nil;setmetatable(module,{__index=function()calls=calls+1;error('foreign module lookup executed')end})
 elseif change=='module-source'then
  local reader=getModFileReader
  getModFileReader=function(mod,path)
   if path:find('ActionQueueClothing.lua',1,true)then
    local lines={'changed source'};return{readLine=function()return table.remove(lines,1)end,close=function()end}
   end
   return reader(mod,path)
  end
 else isClient=function()return true end end
 local decision
 if change=='base-index'then
  assert(not s.definitions.inspect(remove),'new native binding accepted hostile inheritance')
  decision={allowed=false}
 else decision=s.policy.evaluateMove(q,body,otherBody,true)end
 assert(not decision.allowed,'unsupported pending equipment gained permission: '..change)
 assert(calls==0 and s.syncs()==0,'inspection invoked a foreign/native effect callback: '..change)
end

-- Real Lifecycle/Ack source, with Java/network state modeled explicitly. Both
-- ordering channels retain their native behavior; only new edit permission waits.
local function modeledNativeBoundary(s)
 s.f.player.setTimedActionToRetrigger=function()end;s.f.player.StartAction=function()end
 s.f.player.setIsFarming=function()end
 s.f.player.isTimedActionInstant=function()return true end
 s.f.player.getCharacterActions=function()return{contains=function()return false end}end
 ISLogSystem={logAction=function()end}
 LuaTimedActionNew={new=function(action)return{getTable=function()return action end,isStarted=function()return true end,
  finished=function()return false end,isForceComplete=function()return false end,hasStalled=function()return false end}end}
end
local function hostAdmission(mode)
 local s,q,head,append=wornPrepared();s.setClient(true)
 s.f.player.isTimedActionInstant=function()return true end
 local paid,remove,body=append(ItemBodyLocation.SOCKS,1)
 local nextItem,nextRemove,nextBody=append(ItemBodyLocation.HANDS,1)
 local context={}
 if mode~=false then
  assert(s.policy.evaluateMove(q,nextBody,remove,false,context).allowed and context.editFallback==nil,
   'fresh initial Host pending groups failed the common contract')
 end
 if mode==false then PZSurvivorToolkit.Settings.actionQueue=function()return false end end
 table.remove(q.queue,1);q.current=remove
 modeledNativeBoundary(s)
 remove.maxTime=1
 remove:begin() -- actual owned Base.begin -> observer.started -> native create
 remove.toolkitNativeTransaction,remove.toolkitNativeKind=1,'ISUnequipAction'
 local function receipt(status,index,action)
  index=index or 1;action=action or remove
  action.toolkitNativeTransaction,action.toolkitNativeKind=index,'ISUnequipAction'
  s.receiveAck('PZSurvivorToolkitActions','State',{protocol=1,player=7,transaction=index,kind='ISUnequipAction',
   token=string.format('%08x-0000-0000-0000-%012x',index,index),state=status})
 end
 receipt('started')
 local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
 local freshness=PZSurvivorToolkit.ActionQueueClothing
 local fresh,why=freshness.capacityFresh(q)
 assert(fresh==false and why=='unresolved:receipt-missing','native admission borrowed weight or lost its scalar diagnostic')
 return s,q,paid,remove,body,nextRemove,nextBody,receipt,lifecycle,freshness
end
for _,order in ipairs({'done-first','sync-first'})do
 local s,q,item,remove,body,nextRemove,nextBody,receipt,lifecycle,freshness=hostAdmission()
 assert(lifecycle.begin(remove,'perform'));remove:perform();lifecycle.finish(remove,'perform',true)
 assert(lifecycle.flush(q)=='completed'and q.current==body,'fixture must use real native removal before later edit')
 local tail=s.action(s.clothing('Pants'));ISTimedActionQueue.add(tail)
 local function physical()
  s.worn[item.body]=nil;s.root.load=1
 end
 if order=='done-first'then receipt('completed')else physical()end
 local fresh,why=freshness.capacityFresh(q)
 assert(fresh==false and why==(order=='done-first'and 'unresolved:physical-mode'or 'unresolved:receipt-started'),
  'one channel alone settled an unresolved worn capacity mode or lost its exact diagnostic: '..order)
 assert(not s.policy.evaluateMove(q,nextBody,tail,true).allowed,'new Host permission ignored unresolved retained removal')
 if order=='done-first'then physical()else receipt('completed')end
 local fresh,why=freshness.capacityFresh(q)
 assert(fresh==true and why==nil,'terminal/physical proof changed the success tuple: '..order)
 assert(s.policy.evaluateMove(q,nextBody,tail,true).allowed,'known physical + receipt proof did not restore pending Host permission')
 assert(freshness.capacityFresh(q),'freshness consumed a proved result or retained unnecessary history')
end
for _,terminal in ipairs({'canceled','rejected'})do
 local s,q,item,remove,body,nextRemove,nextBody,receipt,lifecycle,freshness=hostAdmission()
 -- Model a stop callback with no native equipment completion; run the actual
 -- shared stop notification boundary and retain the sealed server rejection.
 lifecycle.runStop(remove,function()end)
 receipt(terminal)
 assert(freshness.capacityFresh(q),'known no-growth terminal + unchanged physical mode stayed poisoned: '..terminal)
 assert(s.worn[item.body]==item,'witness executed a canceled native removal')
end
for _,change in ipairs({'unknown','replacement','reset','callback-failed','native-owner','lifecycle-started','ack-observe','token','source-method'})do
 local s,q,item,remove,body,nextRemove,nextBody,receipt,lifecycle,freshness=hostAdmission()
 assert(lifecycle.begin(remove,'perform'));lifecycle.finish(remove,'perform',change~='callback-failed')
 receipt('completed');s.worn[item.body]=nil
 local calls=0
 if change=='unknown'then
  -- No terminal for a new exact receipt, despite a matching local physical mode.
  local another=ISUnequipAction:new(s.f.player,nextRemove.item,50);another.toolkitQueueOperation={}
  q.current=another;q.queue[1]=another;lifecycle.started(another);another.action={}
 elseif change=='replacement'then
  local other=s.clothing(item.body);other.id=item.id
  for index,value in ipairs(s.root.items)do if value==item then s.root.items[index]=other end end
 elseif change=='reset'then PZSurvivorToolkit.ActionQueueAcknowledgements.reset(q)
 elseif change=='native-owner'then s.policy.matchesNative=function()calls=calls+1;return true end
 elseif change=='lifecycle-started'then lifecycle.started=function()calls=calls+1 end
 elseif change=='ack-observe'then PZSurvivorToolkit.ActionQueueAcknowledgements.observe=function()calls=calls+1;return 'completed'end
 elseif change=='token'then remove.toolkitQueueOperation={}
 elseif change=='source-method'then ISBaseTimedAction.create=function()calls=calls+1 end end
 local fresh,why=freshness.capacityFresh(q)
 assert(fresh==false and type(why)=='string','unproven history became success or exposed non-scalar diagnostics: '..change)
 if change=='replacement'then assert(why=='unresolved:canonical-item')end
 if change=='reset'then assert(why=='unresolved:receipt-identity-or-pending')end
 if change=='ack-observe'or change=='lifecycle-started'or change=='native-owner'then assert(why=='bindings')end
 assert(calls==0,'freshness invoked a foreign helper')
end
-- Unobserved overflow is a protected debt marker, never silent eviction. SP
-- admissions and inspections allocate/read no Host receipt/history at all.
do
 local s=setup();s.setClient(true);local q=s.f.queue()
 for index=1,33 do
  local item=s.clothing('UniqueSlot'..index);s.worn[item.body]=item
  local action=ISUnequipAction:new(s.f.player,item,50);action.toolkitQueueOperation={}
  q.queue[1]=action;q.current=action
  PZSurvivorToolkit.ActionQueueLifecycle.started(action)
 end
 local fresh,why=PZSurvivorToolkit.ActionQueueClothing.capacityFresh(q)
 assert(fresh==false and why=='protected:overflow','overflow discarded unresolved debt or changed its scalar diagnostic')
end
do
 local s,q,head,append=wornPrepared();local a,removeA,bodyA=append(ItemBodyLocation.SOCKS,1)
 local b,removeB,bodyB=append(ItemBodyLocation.HANDS,1)
 s.f.player.getOnlineID=function()error('SP read Host bookkeeping')end
 local acks=PZSurvivorToolkit.ActionQueueAcknowledgements
 acks.capture=function()error('SP captured a Host receipt')end;acks.observe=function()error('SP observed a Host receipt')end
 assert(PZSurvivorToolkit.ActionQueueClothing.capacityFresh(q),'SP positive capacity used Host bindings/history')
 assert(s.policy.evaluateMove(q,bodyB,removeA,false).allowed,'SP cheap path changed after unrelated Host helper mutation')
 for index=1,33 do ISTimedActionQueue.add(s.action(s.clothing()))end
 local decision=s.policy.evaluateMove(q,bodyB,removeA,false)
 assert(not decision.allowed and decision.reason=='container_capacity','new positive capacity passed its supported queue-size boundary')
 assert(s.policy.evaluateCancel(q,bodyB,true).allowed,'pure unadmitted tail removal lost cheap cancellation at the size boundary')
end

-- Actual last native completion followed by the owned idle tick must preserve
-- the sealed receipt through either mode. Native idle clear is housekeeping,
-- whereas an explicit reset above still revokes the proof.
for _,mode in ipairs({false,true})do
 for _,order in ipairs({'done-first','sync-first'})do
  local s,q,item,remove,body,nextRemove,nextBody,receipt,lifecycle,freshness=hostAdmission(mode)
  for index=#q.queue,2,-1 do table.remove(q.queue,index)end
  lifecycle.begin(remove,'perform');remove:perform();lifecycle.finish(remove,'perform',true)
  if mode then assert(lifecycle.flush(q)=='completed')end
  assert(q.current==nil and #q.queue==0,'last actual native callback did not reach an empty queue')
  q:tick() -- owned wrapper must suppress native empty cancelQueue/Ack.reset
  if order=='done-first'then receipt('completed')else s.worn[item.body]=nil end
  q:tick()
  assert(not freshness.capacityFresh(q),'empty queue guessed its unresolved physical/receipt outcome')
  if order=='done-first'then s.worn[item.body]=nil else receipt('completed')end
  q:tick()
  assert(freshness.capacityFresh(q),'normal idle housekeeping revoked a paid receipt: '..tostring(mode)..'/'..order)
 end
end

-- Native Wear is an observation-only source: it has no common edit registry
-- entry. A displaced garment can increase authoritative load before worn sync;
-- the other-slot pending Unequip must retain its capacity barrier in both modes.
local function hostWear(displaced,mode,beforeAdmission)
 local s,q,head,append=wornPrepared();s.setClient(true);modeledNativeBoundary(s)
 local incoming=s.clothing(ItemBodyLocation.SHIRT)
 incoming.IsClothing=function()return true end
 local old
 if displaced then old=s.clothing(incoming.body);s.worn[old.body]=old end
 local other,remove,body=append(ItemBodyLocation.SOCKS,1)
 local tail=s.action(s.clothing('Pants'));q.queue[#q.queue+1]=tail
 local wear=ISWearClothing:new(s.f.player,incoming);wear.toolkitQueueOperation={}
 head.action=nil;head.maxTime=1;table.insert(q.queue,1,wear);q.current=wear
 if mode==false then PZSurvivorToolkit.Settings.actionQueue=function()return false end end
 s.f.player.getHumanVisual=function()return{getHairModel=function()return{contains=function()return false end}end}end
 s.f.player.setWornItem=function(_,location,item)s.worn[location]=item end
 local freshness=PZSurvivorToolkit.ActionQueueClothing
 assert(freshness.capacityFresh(q),'new fixture has unexplained pre-admission debt')
 assert(not s.policy.matchesNative(wear),'Wear fixture gained a registry/edit authority for its witness')
 local observerOnly=beforeAdmission and beforeAdmission(s,q,incoming,old,wear)
 if observerOnly then PZSurvivorToolkit.ActionQueueLifecycle.started(wear)
 else wear:begin()end -- actual early observer, before fake Java allocation
 local function receipt(status)
  wear.toolkitNativeTransaction,wear.toolkitNativeKind=1,'ISWearClothing'
  s.receiveAck('PZSurvivorToolkitActions','State',{protocol=1,player=7,transaction=1,kind='ISWearClothing',
   token='00000001-0000-0000-0000-000000000001',state=status})
 end
 return s,q,incoming,old,wear,remove,body,tail,receipt,PZSurvivorToolkit.ActionQueueLifecycle,freshness
end
for _,mode in ipairs({false,true})do
 for _,order in ipairs({'done-first','sync-first'})do
  local s,q,item,old,wear,remove,body,tail,receipt,lifecycle,freshness=hostWear(true,mode)
  receipt('started')
  for _=1,2 do assert(not freshness.capacityFresh(q),'positive Wear has no admission debt')end
  local observed=lifecycle.begin(wear,'perform');if mode then assert(observed)end;wear:perform();lifecycle.finish(wear,'perform',true)
  if mode then assert(lifecycle.flush(q)=='completed')end
  assert(getmetatable(q.current)==ISWringClothing and s.worn[item.body]==old,'client perform changed worn state or failed normal handoff')
  local function physical()assert(wear:complete());s.root.load=5 end -- actual native server effect, transport modeled
  if order=='done-first'then receipt('completed')else physical()end
  for _=1,2 do assert(not freshness.capacityFresh(q),'Wear settled from one channel only: '..order)end
  assert(not s.policy.evaluateMove(q,body,tail,true).allowed,'pending other-slot removal spent stale pre-Wear load')
  if order=='done-first'then physical()else receipt('completed')end
  local fresh,reason=freshness.capacityFresh(q)
  assert(fresh,'native Wear completion did not retire its exact displacement: '..order..'/'..tostring(reason))
  assert(freshness.capacityFresh(q),'fresh query consumed the successful Wear proof')
  if mode then assert(s.policy.evaluateMove(q,body,tail,true).allowed,'known settled Wear left unrelated pending rights poisoned')end
 end
end
-- An empty single slot has no increasing effect. Repeated fresh queries must
-- keep callback ownership without turning its active record into blocking debt.
for _,mode in ipairs({false,true})do
 local s,q,item,old,wear,remove,body,tail,receipt,lifecycle,freshness=hostWear(false,mode)
 receipt('started')
 for _=1,3 do assert(freshness.capacityFresh(q),'empty native Wear creates positive capacity debt')end
 local observed=lifecycle.begin(wear,'perform');if mode then assert(observed)end;wear:perform();lifecycle.finish(wear,'perform',true)
 if mode then assert(lifecycle.flush(q)=='completed')end
 assert(freshness.capacityFresh(q),'fresh queries lost the nonblocking native callback record')
 assert(wear:complete());receipt('completed')
 assert(freshness.capacityFresh(q),'empty-slot physical arrival poisoned later capacity')
end
for _,terminal in ipairs({'canceled','rejected'})do
 local s,q,item,old,wear,remove,body,tail,receipt,lifecycle,freshness=hostWear(true)
 receipt('started');lifecycle.runStop(wear,function()end);receipt(terminal)
 assert(freshness.capacityFresh(q),'no-effect Wear terminal did not retain its original exact modes')
 assert(s.worn[item.body]==old,'canceled Wear changed the target slot')
end
for _,change in ipairs({'replacement','missing-old','held-old','wrong-slot','reset','callback','same-file-callback','callback-failed','metachain'})do
 local s,q,item,old,wear,remove,body,tail,receipt,lifecycle,freshness=hostWear(true)
 receipt('started');assert(lifecycle.begin(wear,'perform'));lifecycle.finish(wear,'perform',change~='callback-failed')
 receipt('completed');assert(wear:complete())
 local calls=0
 if change=='replacement'then
  local other=s.clothing(old.body);other.id=old.id
  for index,value in ipairs(s.root.items)do if value==old then s.root.items[index]=other end end
 elseif change=='missing-old'then old.container=nil
 elseif change=='held-old'then s.f.player.primary=old
 elseif change=='wrong-slot'then s.worn[item.body]=old
 elseif change=='reset'then PZSurvivorToolkit.ActionQueueAcknowledgements.reset(q)
 elseif change=='callback'then ISWearClothing.complete=function()calls=calls+1 end
 elseif change=='same-file-callback'then ISWearClothing.complete=ISWearClothing.isValid
 elseif change=='metachain'then
  ISBaseTimedAction.__index=function(_,key)calls=calls+1;return ISBaseTimedAction[key]end
 end
 local fresh,why=freshness.capacityFresh(q)
 assert(fresh==false and type(why)=='string','unqualified Wear history became success: '..change)
 assert(calls==0,'Wear witness invoked a foreign callback/lookup: '..change)
end
-- Even a native empty-slot mode must keep its proof live until its callback.
for _,change in ipairs({'callback','failed'})do
 local s,q,item,old,wear,remove,body,tail,receipt,lifecycle,freshness=hostWear(false)
 receipt('started')
 assert(freshness.capacityFresh(q));assert(freshness.capacityFresh(q))
 local calls=0
 if change=='callback'then ISWearClothing.complete=function()calls=calls+1 end end
 assert(lifecycle.begin(wear,'perform'));lifecycle.finish(wear,'perform',change~='failed')
 assert(not freshness.capacityFresh(q),'nonblocking admission erased changed/failed callback history')
 assert(calls==0,'nonblocking freshness invoked a foreign native effect')
end

-- Two actual empty-looking Wear admissions before sync must not compose their
-- local nonincrease proofs. Only the first server snapshot can arrive after the
-- second action already displaced it on authority.
do
 local s,q,first,old,wear,remove,body,tail,receipt,lifecycle,freshness=hostWear(false)
 receipt('started');lifecycle.begin(wear,'perform');wear:perform();lifecycle.finish(wear,'perform',true)
 assert(lifecycle.flush(q)=='completed');receipt('completed')
 assert(freshness.capacityFresh(q),'single empty Wear should permit a conservative stale-load decision')
 local second=s.clothing(first.body);local nextWear=ISWearClothing:new(s.f.player,second);nextWear.toolkitQueueOperation={}
 -- Model the next genuine native queue admission without running the neutral
 -- waiting front. No sync of the first Wear has been delivered yet.
 q.queue[1]=nextWear;q.current=nextWear;nextWear:begin()
 nextWear.toolkitNativeTransaction,nextWear.toolkitNativeKind=2,'ISWearClothing'
 local function nextReceipt(state)s.receiveAck('PZSurvivorToolkitActions','State',{protocol=1,player=7,transaction=2,
  kind='ISWearClothing',token='00000002-0000-0000-0000-000000000002',state=state})end
 nextReceipt('started');lifecycle.begin(nextWear,'perform');nextWear:perform();lifecycle.finish(nextWear,'perform',true)
 lifecycle.flush(q);nextReceipt('completed')
 assert(wear:complete()) -- first snapshot only; authoritative second swap is deliberately not delivered
 local fresh,reason=freshness.capacityFresh(q)
 assert(fresh==false and reason=='protected:overlapping-equipment','stale empty-slot Wear proofs composed into positive capacity credit')
 assert(not s.policy.evaluateMove(q,body,tail,true).allowed,'first snapshot exposed new removal rights while second Wear was unconfirmed')
end
-- Once both channels of an earlier ordinary Wear have converged, the next
-- genuine Wear may classify its now-visible displacement normally.
do
 local s,q,item,old,wear,remove,body,tail,receipt,lifecycle,freshness=hostWear(false)
 receipt('started');lifecycle.begin(wear,'perform');wear:perform();lifecycle.finish(wear,'perform',true)
 lifecycle.flush(q);assert(wear:complete());receipt('completed')
 assert(freshness.capacityFresh(q),'settled first Wear did not retire')
 local replacement=s.clothing(item.body);local nextWear=ISWearClothing:new(s.f.player,replacement);nextWear.toolkitQueueOperation={}
 q.queue[1]=nextWear;q.current=nextWear;nextWear:begin()
 local fresh,reason=freshness.capacityFresh(q)
 assert(fresh==false and reason=='unresolved:receipt-missing','settled ordinary sequence retained an overlap poison or skipped its positive displacement')
end
-- Rewear after an unconfirmed Unequip is likewise an overlapping equipment
-- mode, even when the retained local slot still looks already worn. Keep native
-- execution, and protect only the new capacity authority until a later world.
do
 local s,q,item,remove,body,nextRemove,nextBody,receipt,lifecycle,freshness=hostAdmission()
 lifecycle.begin(remove,'perform');remove:perform();lifecycle.finish(remove,'perform',true)
 assert(lifecycle.flush(q)=='completed');receipt('completed')
 assert(not freshness.capacityFresh(q),'first removal lost its unresolved physical mode')
 local rewear=ISWearClothing:new(s.f.player,item);rewear.toolkitQueueOperation={}
 q.queue[1]=rewear;q.current=rewear;rewear:begin()
 rewear.toolkitNativeTransaction,rewear.toolkitNativeKind=2,'ISWearClothing'
 local function wearReceipt(state)s.receiveAck('PZSurvivorToolkitActions','State',{protocol=1,player=7,transaction=2,
  kind='ISWearClothing',token='00000002-0000-0000-0000-000000000002',state=state})end
 wearReceipt('started');lifecycle.begin(rewear,'perform');rewear:perform();lifecycle.finish(rewear,'perform',true)
 lifecycle.flush(q);wearReceipt('completed');s.worn[item.body]=nil -- only the earlier removal snapshot
 local fresh,reason=freshness.capacityFresh(q)
 assert(fresh==false and reason=='protected:overlapping-equipment','rewear classified a mode before earlier clothing convergence')
end
-- Native-only observation rejects unsupported admission shapes without invoking
-- changed callbacks, including same-file role substitution and foreign lookup.
for _,change in ipairs({'held','attached','head','alias','negative-weight','equipped-heavy','callback','same-file-callback','metachain'})do
 local calls=0
 local s,q,item,old,wear,remove,body,tail,receipt,lifecycle,freshness=hostWear(true,true,function(s,q,item,old,wear)
  if change=='held'then s.f.player.primary=item
  elseif change=='attached'then item.getAttachedSlot=function()return 2 end
  elseif change=='head'then item.body=ItemBodyLocation.HAT
  elseif change=='alias'then local alias=s.clothing(item.body);alias.id=item.id
   for index,value in ipairs(s.root.items)do if value==item then s.root.items[index]=alias end end
  elseif change=='negative-weight'then item.getUnequippedWeight=function()return -1 end
  elseif change=='equipped-heavy'then item.getEquippedWeight=function()return 100 end
  elseif change=='callback'then ISWearClothing.complete=function()calls=calls+1 end
  elseif change=='same-file-callback'then ISWearClothing.complete=ISWearClothing.isValid
  elseif change=='metachain'then ISBaseTimedAction.__index=function()calls=calls+1 end;return true end
 end)
 assert(not freshness.capacityFresh(q),'unsupported Wear admission gained freshness: '..change)
 assert(calls==0,'Wear admission executed an unsupported callback/lookup: '..change)
end

-- Direct Policy auto-load, with no caller-provided Lifecycle/Acks, must arm
-- before Host admission; later main Queue requires retain those exact owners.
do
 local s=setup(nil,nil,true);local q=s.f.queue(s.action(s.clothing()))
 local fresh,reason=PZSurvivorToolkit.ActionQueueClothing.capacityFresh(q)
 assert(fresh and reason==nil,'direct Policy-first Host bootstrap remained unarmed: '..tostring(reason))
 local lifecycle,acks=PZSurvivorToolkit.ActionQueueLifecycle,PZSurvivorToolkit.ActionQueueAcknowledgements
 assert(require('PZSurvivorToolkit/ActionQueueLifecycle')==lifecycle and require('PZSurvivorToolkit/ActionQueueAcknowledgements')==acks,
  'normal require replaced the observer dependency owners')
end
-- New Host removal bounds reserve loss of current hand discounts. Only exact
-- root refs are read; one item in both hands contributes once, distinct hands
-- contribute cumulatively. No native Equip execution or discount credit occurs.
local function handCapacity(primaryWeight,secondaryWeight,same,capacity,clientMode)
 local s,q,head,append=wornPrepared();s.setClient(clientMode~=false)
 local a,removeA,bodyA=append(ItemBodyLocation.SOCKS,1)
 local b,removeB,bodyB=append(ItemBodyLocation.HANDS,1)
 local reads=0
 local function held(weight)
  local item=s.clothing('Held'..tostring(weight))
  item.getUnequippedWeight=function()reads=reads+1;return weight end
  item.getEquippedWeight=function()return weight*.3 end
  return item
 end
 local primary=primaryWeight and held(primaryWeight)
 local secondary=same and primary or secondaryWeight and held(secondaryWeight)
 s.f.player.primary,s.f.player.secondary=primary,secondary
 local cargo=s.clothing('UnrelatedCargo')
 local current=.6+(primaryWeight or 0)*.3+(same and 0 or secondaryWeight or 0)*.3
 cargo.getUnequippedWeight=function()return 10-current-1.9 end -- neutral Wring front clothing weighs1.9
 cargo.getEquippedWeight=cargo.getUnequippedWeight
 s.root.load,s.root.capacity=10,capacity or 15
 return s,q,bodyA,removeA,bodyB,removeB,primary,secondary,function()return reads end
end
do
 local s,q,a,removeA,b,removeB,primary=handCapacity(4,nil,false,15)
 local decision=s.policy.evaluateMove(q,b,removeA,false)
 assert(not decision.allowed and decision.reason=='container_capacity','Host removal spent the stale old held discount')
 s.root.capacity=16.5
 local context={};decision=s.policy.evaluateMove(q,b,removeA,false,context)
 assert(decision.allowed and context.editFallback==nil,'bounded hand reserve permanently blocked ordinary held items')
end
do
 local s,q,a,removeA,b,removeB,primary,secondary,reads=handCapacity(2,nil,true,15)
 assert(s.policy.evaluateMove(q,b,removeA,false).allowed,'two-hand same item was charged twice')
 assert(reads()==1,'two-hand reserve repeated the same item weight read')
 local both=PZSurvivorToolkit.ActionQueueClothing.handReserve(q)
 assert(math.abs(both-1.4)<0.00001,'same-item hand reserve has the wrong delta')
end
do
 local s,q,a,removeA,b,removeB,primary,secondary=handCapacity(2,2,false,15)
 assert(not s.policy.evaluateMove(q,b,removeA,false).allowed,'distinct hand discounts were not accumulated')
 s.worn[primary.body]=primary
 assert(not s.policy.evaluateMove(q,b,removeA,false).allowed,'worn-and-held status gained release credit')
end
for _,change in ipairs({'alias','container','heavy','negative-upper','negative-equipped','nan-upper','nan-equipped','weight-method','factory-method','owner','module-api'})do
 local s,q,a,removeA,b,removeB,item=handCapacity(2,nil,false,100)
 if change=='alias'then local replacement=s.clothing(item.body);replacement.id=item.id
  for i,value in ipairs(s.root.items)do if value==item then s.root.items[i]=replacement end end
 elseif change=='container'then item.class='InventoryContainer'
 elseif change=='heavy'then item.isForceDropHeavyItem=function()return true end
 elseif change=='negative-upper'then item.getUnequippedWeight=function()return -1 end
 elseif change=='negative-equipped'then item.getEquippedWeight=function()return -1 end
 elseif change=='nan-upper'then item.getUnequippedWeight=function()return 0/0 end
 elseif change=='nan-equipped'then item.getEquippedWeight=function()return 0/0 end
 elseif change=='weight-method'then PZSurvivorToolkit.ActionQueueWeights.unequipped=function()error('changed weight reader invoked')end
 elseif change=='factory-method'then PZSurvivorToolkit.ActionQueueWeights.factoryFree=function()error('changed factory proof invoked')end
 elseif change=='owner'then item.container={}
 elseif change=='module-api'then PZSurvivorToolkit.ActionQueueClothing.handReserve=function()error('changed reserve invoked')end end
 assert(not s.policy.evaluateMove(q,b,removeA,false).allowed,'uncertain current hand acquired new capacity authority: '..change)
end
do
 local s,q,a,removeA,b,removeB,item,secondary,reads=handCapacity(100,nil,false,15,false)
 item.getEquippedWeight=function()error('SP read held discount')end
 assert(s.policy.evaluateMove(q,b,removeA,false).allowed and reads()==0,'SP gained Host hand-weight work')
end
-- A custom loaded multiplier above one can grow an unseen incoming hand
-- mode. Reuse the already-read plain Clothing U/E witness, not a root search.
for _,change in ipairs({'multiplier','zero','subnormal','discount-helper'})do
 local s,q,a,removeA,b,removeB=handCapacity(nil,nil,false,100)
 if change=='multiplier'then
  removeA.item.getEquippedWeight=function(self)return self.weight*2 end
  removeB.item.getEquippedWeight=function(self)return self.weight*2 end
 elseif change=='zero'then removeA.item.weight=0;removeB.item.weight=0
 elseif change=='subnormal'then removeA.item.weight=1.401298464324817e-45;removeB.item.weight=1.401298464324817e-45
 elseif change=='discount-helper'then PZSurvivorToolkit.ActionQueueWeights.nativeDiscountKnown=function()error('foreign discount helper invoked')end end
 assert(not s.policy.evaluateMove(q,b,removeA,false).allowed,'unproved incoming equipped discount gained new rights: '..change)
end
do
 local s,q,a,removeA,b,removeB=handCapacity(nil,nil,false,100)
 local weights=PZSurvivorToolkit.ActionQueueWeights;local calls=0
 removeB.item.getEquippedWeight=function(self)
  weights.nativeDiscountKnown=nil
  setmetatable(weights,{__index=function()calls=calls+1 end})
  return self.weight*.3
 end
 assert(not s.policy.evaluateMove(q,b,removeA,false).allowed and calls==0,
  'new discount proof read hostile module metadata before its actual-table guard')
end
-- No current hands is not evidence that an incoming negative native weapon
-- cannot grow load. Explicit zero keeps the same Host sign qualification.
do
 local s,q,a,removeA,b,removeB=handCapacity(nil,nil,false,100)
 local input=s.clothing('NegativeIncoming');input.class='HandWeapon'
 input.getUnequippedWeight=function()return -5 end;input.getEquippedWeight=function()return -1.5 end
 assert(not s.policy.evaluateMove(q,b,removeA,false).allowed,'zero-hand shortcut accepted negative incoming native weight')
end
for _,mode in ipairs({.3,.8})do
 local s,q,a,removeA,b,removeB=handCapacity(nil,nil,false,100);modeledNativeBoundary(s)
 removeA.item.getEquippedWeight=function(self)return self.weight*mode end
 removeB.item.getEquippedWeight=function(self)return self.weight*mode end
 local input=s.clothing('HotbarIncoming');input.class='HandWeapon';input.slot=2
 input.getAttachedSlot=function(self)return self.slot end;input.getHotbarEquippedWeight=function()return .7 end
 input.getUnequippedWeight=function()return 1 end;input.getEquippedWeight=function()return mode end
 input.getName=function()return 'Incoming'end;input.isTwoHandWeapon=function()return false end
 input.isRequiresEquippedBothHands=function()return false end
 getPlayerHotbar=function()return{chr=s.f.player,isItemAttached=function(_,item)return item==input end}end
 s.f.player.removeAttachedItem=function(_,item)assert(item==input)end -- actual Java removes entry, not item.slot metadata
 local equip=ISEquipWeaponAction:new(s.f.player,input,1,true,false);equip.toolkitQueueOperation={}
 local head=q.queue[1];head.action=nil;head.maxTime=1;table.insert(q.queue,1,equip);q.current=equip
 equip:begin();equip.action.setOverrideHandModelsObject=function()end;equip.action.restoreWeaponType=function()end
 local life=PZSurvivorToolkit.ActionQueueLifecycle
 life.begin(equip,'perform');equip:perform();life.finish(equip,'perform',true);life.flush(q)
 assert(input:getAttachedSlot()==2 and s.f.player:getPrimaryHandItem()==nil,'native client Equip was modeled as applying physical hands or resetting item hotbar metadata')
 local decision=s.policy.evaluateMove(q,b,removeA,false)
 assert(decision.allowed==(mode==.3),'unseen hotbar-to-held .7 -> equipped transition violated source factor proof')
end
-- A transfer-only common decision keeps its existing capacity path and does
-- not call the new clothing reserve API, even while Host hands are uncertain.
do
 local s=setup();s.setClient(true)
 local head=s.action(s.clothing('Shirt'));head.action={};local q=s.f.queue(head)
 local a,b=s.clothing('Pants'),s.clothing('Socks');local bag=s.bag(a)
 for i=#s.root.items,1,-1 do if s.root.items[i]==b then table.remove(s.root.items,i)end end
 b.container=bag;bag.items[#bag.items+1]=b
 local first=s.transfer(a,bag,s.root,{});local second=s.transfer(b,bag,s.root,{})
 ISTimedActionQueue.add(first);ISTimedActionQueue.add(second)
 s.f.player.primary=s.clothing('IndependentHeld')
 PZSurvivorToolkit.ActionQueueClothing.handReserve=function()error('legacy transfer-only called hand reserve')end
 local decision=s.policy.evaluateMove(q,second,first,false)
 assert(decision.allowed,'transfer-only authority changed with the new removal guard: '..tostring(decision.reason))
end

-- Diagnostic failure labels never turn an early unavailable proof into a
-- healthy late empty history. This models eager source availability only;
-- it does not claim that this is the cause of any native capture failure.
do
 local s=setup('ActionQueueLifecycle.lua');s.setSourceChange(false);s.setClient(true)
 local q=s.f.queue(s.action(s.clothing()))
 local fresh,why=PZSurvivorToolkit.ActionQueueClothing.capacityFresh(q)
 assert(fresh==false and why=='bootstrap:source','healthy later readers concealed the original failed bootstrap gate')
 local again,reason=PZSurvivorToolkit.ActionQueueClothing.capacityFresh(q)
 assert(again==fresh and reason==why,'diagnostic query changed the refusal or promoted observer state')
end

if TestCoverage then TestCoverage('source-contract','passed')end
print('Wring pending contracts: installed native Lua, real Policy decisions, wetness caps, exact root/actor ownership and unchanged execution passed; canonical carried/worn preparation, cumulative no-drop capacity and sealed Host freshness; no active edits/recovery authority granted.')
