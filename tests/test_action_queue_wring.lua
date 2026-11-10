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
 f.native('shared/TimedActions/ISWringClothing.lua')
 f.native('shared/RadioCom/ISRadioAction.lua')
 for _,path in ipairs({'Fluids/ISFluidUtil.lua','Fluids/ISFluidContainer.lua','Fluids/ISFluidTransferAction.lua',
  'Fluids/ISFluidEmptyAction.lua','TimedActions/ISTransferAction.lua','TimedActions/ISDrinkFluidAction.lua'})do
  f.native('shared/'..path)
 end
 local nativeInstanceof=instanceof
 instanceof=function(value,name)
  return nativeInstanceof(value,name)or type(value)=='table'and value.class=='Clothing'and name=='InventoryItem'
 end
 getClassSimpleName=function(value)return type(value)=='table'and value.class or 'Foreign'end
 getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
 getGameFilesInput=function(path)
  local filename=NativeActionRoot..'/'..path:gsub('^media/lua/','')
  local text
  if NativeReadText then text=NativeReadText(filename)
  else local input=assert(io.open(filename));text=input:read('*a');input:close()end
  text=text:gsub('\r','')
  if changedSource and path:find('ISWringClothing',1,true)then text=text..'-- changed native source\n'end
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
 local root={class='ItemContainer',items={},getType=function()return 'none'end,
  getParent=function()return f.player end,getContainingItem=function()end,
  getAcceptItemFunction=function()end,getOnlyAcceptCategory=function()end,
  getCapacityWeight=function()return 0 end,getEffectiveCapacity=function()return 100 end}
 root.getItemWithID=function(self,id)for _,item in ipairs(self.items)do if item:getID()==id then return item end end end
 root.getItemById=root.getItemWithID
 root.contains=function(self,item)return self:getItemWithID(item:getID())==item end
 f.player.inventory=root
 local function clothing(location,wetness)
  local item=f.item('Base.ShirtDenim');item.class='Clothing';item.container=root;item.wetness=wetness or 90
  item.body=location or 'Shirt'
  item.getContainer=function(self)return self.container end
  item.wetnessReads=0
  item.getWetness=function(self)self.wetnessReads=self.wetnessReads+1;return self.wetness end
  item.setWetness=function(self,value)self.wetness=value end
  item.getBodyLocation=function(self)return self.body end
  root.items[#root.items+1]=item
  return item
 end
 local inheritedRequire=require;local modules={}
 require=function(name)
  if name=='PZSurvivorToolkit/ActionQueueEditModel'or name=='PZSurvivorToolkit/ActionQueueEditAdapters'
   or name=='PZSurvivorToolkit/ActionQueueWring'then
   if not modules[name]then
    if name=='PZSurvivorToolkit/ActionQueueWring'and unusedBase=='base-index-before'then
     local saved={};for key,value in pairs(ISBaseTimedAction)do saved[key]=value end
     ISBaseTimedAction.__index=function(_,key)WringForeignLookupCalls=WringForeignLookupCalls+1;return saved[key]end
    end
    modules[name]=f.project(name:match('/([^/]+)$'))
   end
   return modules[name]
  end
  return inheritedRequire(name)
 end
 f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
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
 return {f=f,root=root,clothing=clothing,action=action,adapter=adapter,policy=policy,installed=installed,
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
 local s=setup(false,'base-index-before')
 assert(not s.installed and WringForeignLookupCalls==0,'install invoked foreign base __index before rejecting its chain')
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
if TestCoverage then TestCoverage('source-contract','passed')end
print('Wring pending contracts: installed native Lua, real Policy decisions, wetness caps, exact root/actor ownership and unchanged execution passed; known active footprint only; no active/recovery/outcome or capacity authority granted.')
