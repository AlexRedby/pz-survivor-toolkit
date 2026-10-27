require 'Entity/TimedActions/ISHandcraftAction'
local F={module='PlasticBatteryTest',gunType='damnCraft.PlasticWeldingGun'}
F.plans={}
for _,operation in ipairs({'insert','remove'})do
 for _,charge in ipairs({0,0.37,1})do
  F.plans[#F.plans+1]={operation=operation,requestedCharge=charge}
 end
end
function F.recipes(role)
 local manager=getScriptManager()
 local absent=true
 for _,name in ipairs({'damnCraftInsertBatteryIntoPlasticWeldingGun','damnCraftRemoveBatteryFromPlasticWeldingGun'})do
  absent=absent and manager:getCraftRecipe(name)==nil and manager:getCraftRecipe('Base.'..name)==nil
 end
 local present=manager:getCraftRecipe('InsertBattery')~=nil and manager:getCraftRecipe('RemoveBattery')~=nil
 assert(absent and present,'fixed recipe registry mismatch')
 return {role=role,customAbsent=absent,basePresent=present}
end
local function relevant(item)return item:getFullType()==F.gunType or item:getFullType()=='Base.Battery'end
function F.snapshot(player)
 local result={};local items=player:getInventory():getItems()
 for i=0,items:size()-1 do
  local item=items:get(i)
  if relevant(item)then result[#result+1]={id=item:getID(),type=item:getFullType(),
   uses=item:getCurrentUses(),maxUses=item:getMaxUses()}end
 end
 table.sort(result,function(a,b)return a.id<b.id end)
 return result
end
local function remove(player,item)
 player:removeFromHands(item)
 if isServer()then sendRemoveItemFromContainer(player:getInventory(),item)end
 player:getInventory():Remove(item)
end
local function add(player,item)
 local value=player:getInventory():AddItem(item)
 if isServer()then sendAddItemToContainer(player:getInventory(),value)end
 return value
end
function F.init(player)
 local owner={player=player,stash={},original={}}
 local items=player:getInventory():getItems()
 for i=items:size()-1,0,-1 do
  local item=items:get(i);owner.original[item:getID()]=true
  if relevant(item)then owner.stash[#owner.stash+1]=item;remove(player,item)end
 end
 return owner
end
function F.clean(owner)
 local items=owner.player:getInventory():getItems()
 for i=items:size()-1,0,-1 do
  local item=items:get(i)
  if relevant(item)and not owner.original[item:getID()]then remove(owner.player,item)end
 end
end
function F.restore(owner)
 F.clean(owner)
 for _,item in ipairs(owner.stash)do add(owner.player,item)end
 for id in pairs(owner.original)do assert(owner.player:getInventory():getItemById(id),'original inventory item lost')end
end
function F.prepare(owner,index)
 F.clean(owner)
 local plan=assert(F.plans[index]);local player=owner.player;local inventory=player:getInventory()
 assert(player:getInventoryWeight()+3<player:getMaxWeight(),'insufficient carry headroom')
 -- Use bounded integers; Battery float 1 rounds above its native maximum.
 local gun=assert(inventory:AddItem(F.gunType));local battery
 gun:setCurrentUses(plan.operation=='insert'and 0 or math.floor(gun:getMaxUses()*plan.requestedCharge+.5))
 if plan.operation=='insert'then
  battery=assert(inventory:AddItem('Base.Battery'))
  battery:setCurrentUses(math.floor(battery:getMaxUses()*plan.requestedCharge+.5))
 end
 if isServer()then
  sendAddItemToContainer(inventory,gun)
  if battery then sendAddItemToContainer(inventory,battery)end
 end
 local packet={index=index,operation=plan.operation,requestedCharge=plan.requestedCharge,
  recipe=plan.operation=='insert'and 'Base.InsertBattery'or 'Base.RemoveBattery',
  gunID=gun:getID(),batteryID=battery and battery:getID()or -1,gunUseDelta=gun:getUseDelta(),before=F.snapshot(player)}
 return {owner=owner,player=player,packet=packet,performCalls=0,inputIDs={},nativeDuration=false}
end
function F.expected(state,role)
 local p=state.packet;local source
 for _,item in ipairs(p.before)do
  if item.id==(p.operation=='insert'and p.batteryID or p.gunID)then source=item end
 end
 assert(source,'missing exact source input')
 local transfer=math.floor(source.uses/source.maxUses*(p.operation=='insert'and 1111 or 142))
 local codec=isClient()and role~='authority'and p.operation=='insert'and p.requestedCharge>0
 local observed=transfer
 if codec then
  -- B42.21 ItemStatsPacket.setData stores getCurrentUsesFloat() (float uses*useDelta).
  -- applyItemStats sets integer uses=(int)(float(maxUses)*usedDelta), without rounding.
  -- Source-checked constants cover only this fixture's bounded insertion matrix;
  -- Python independently calculates both IEEE754 binary32 operations from metadata.
  assert(p.gunUseDelta==0.0008999999845400453,'native gun useDelta changed')
  local targets={[414]=413,[1111]=1110}
  observed=assert(targets[transfer],'unreviewed native packet charge case')
 end
 return {nativeTransferUses=transfer,expectedObservedUses=observed,
  stockStatsCodec=codec and 'native-item-stats'or 'none'}
end
function F.receipt(state,role)
 local packet=state.packet;role=role or 'authority';local expected=F.expected(state,role)
 return {index=packet.index,operation=packet.operation,requestedCharge=packet.requestedCharge,
  recipe=packet.recipe,gunID=packet.gunID,batteryID=packet.batteryID,gunUseDelta=packet.gunUseDelta,
  before=packet.before,after=F.snapshot(state.player),effectRole=role,
  nativeTransferUses=expected.nativeTransferUses,expectedObservedUses=expected.expectedObservedUses,
  stockStatsCodec=expected.stockStatsCodec}
end
function F.effectReady(state)
 local p=state.packet;local after=F.snapshot(state.player);local gun,batteries
 batteries={}
 for _,item in ipairs(after)do
  if item.type==F.gunType then if gun then return false,'duplicate guns' end;gun=item
  else batteries[#batteries+1]=item end
 end
 if not gun or gun.id~=p.gunID then return false,'gun identity differs' end
 local expected=F.expected(state,isClient()and 'local'or 'authority').expectedObservedUses
 if p.operation=='insert'then
  return #batteries==0 and gun.uses==expected,
   'insert expected gun uses '..expected..', observed '..gun.uses..', battery count '..#batteries
 end
 return gun.uses==0 and #batteries==(p.requestedCharge==0 and 0 or 1)
  and(#batteries==0 or batteries[1].uses==expected),
  'remove expected battery uses '..expected..', gun uses '..gun.uses..', battery count '..#batteries
end
function F.diagnostic(state)
 local ready,reason=F.effectReady(state)
 return {index=state.packet.index,packet=state.packet,after=F.snapshot(state.player),
  expectation=F.expected(state,isClient()and 'local'or 'authority'),
  effectReady=ready,effectReason=reason or '',performCalls=state.performCalls or -1,
  inputIDs=state.inputIDs or {},nativeDuration=state.nativeDuration==true}
end
function F.install(getState,onObserved)
 local native=ISHandcraftAction.performRecipe
 local function observer(action,...)
  local state=getState()
  if not state or action.character~=state.player then return native(action,...)end
  assert(action.craftRecipe:getScriptObjectFullType()==state.packet.recipe,'unexpected fixture recipe')
  state.performCalls=state.performCalls+1
  assert(state.performCalls==1,'duplicate native craft')
  state.nativeDuration=action:getDuration()==action.craftRecipe:getTime(state.player)*5 and action:getDuration()>1
  -- Native perform materializes applied inputs on both roles. It retains that
  -- data through luaCallOnCreate/processDestroyAndUsedItems; the latter only
  -- uses consumed items and sends stats. Observe afterwards without recomputing
  -- recipe admission, which would populate/alter the server's crafting cache.
  local result=native(action,...)
  local inputs=assert(action.logic,'missing authoritative craft logic'):getRecipeData():getAllInputItems()
  local found={}
  for i=0,inputs:size()-1 do
   local id=inputs:get(i):getID();assert(not found[id],'duplicate native input');found[id]=true
   state.inputIDs[#state.inputIDs+1]=id
   assert(id==state.packet.gunID or id==state.packet.batteryID,'foreign native recipe input')
  end
  assert(found[state.packet.gunID]and(state.packet.operation=='remove'or found[state.packet.batteryID]),
   'native craft did not select fixture inputs')
  if onObserved then onObserved(F.diagnostic(state))end
  return result
 end
 ISHandcraftAction.performRecipe=observer
 return function()
  assert(ISHandcraftAction.performRecipe==observer,'craft observer replaced')
  ISHandcraftAction.performRecipe=native
 end,function()return ISHandcraftAction.performRecipe==observer end
end
function F.authority(state,guard)
 local row=F.receipt(state)
 row.performCalls=state.performCalls;row.inputIDs=state.inputIDs
 row.nativeDuration=state.nativeDuration;row.observerIntact=guard()
 assert(row.observerIntact,'craft observer replaced')
 return row
end
return F
