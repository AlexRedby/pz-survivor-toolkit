local Authority,states,turn={}, {}, 1
local Selection=require 'QueueHealthSelection'
local Cases=Selection.cases
local origin
local function key(player) return player:getUsername() end
local function online(name)
 local values=getOnlinePlayers();for i=0,values:size()-1 do local player=values:get(i);if key(player)==name then return player end end
end
local function position(player,x,y,z)
 player:teleportTo(math.floor(x),math.floor(y),z);player:setX(x);player:setY(y);player:setZ(z)
 player:setLastX(x);player:setLastY(y);player:setLastZ(z);player:setCurrentSquareFromPosition()
 if isServer() then sendServerCommand(player,'HealthQueueTest','Position',{x=x,y=y,z=z}) end
end
Authority.position=position
local function part(player) return player:getBodyDamage():getBodyPart(BodyPartType.ForeArm_L) end
local function image(body)
 return {bandaged=body:bandaged(),stitched=body:stitched(),glass=body:haveGlass(),bullet=body:haveBullet(),wash=body:isNeedBurnWash(),
 splint=body:getSplintFactor(),alcohol=body:getAlcoholLevel(),comfrey=body:getComfreyFactor(),garlic=body:getGarlicFactor(),plantain=body:getPlantainFactor()}
end
function Authority.readiness(body)
 return {injured=body:HasInjury(),deep=body:isDeepWounded(),fractured=body:getFractureTime()>0,
  bandaged=body:bandaged(),stitched=body:stitched(),glass=body:haveGlass(),bullet=body:haveBullet(),wash=body:isNeedBurnWash(),
  splinted=body:getSplintFactor()>0,comfrey=body:getComfreyFactor()>0,garlic=body:getGarlicFactor()>0,plantain=body:getPlantainFactor()>0}
end
function Authority.clinicalReady(body,expected)
 for field,value in pairs(Authority.readiness(body)) do if expected[field]~=value then return false end end
 return true
end
local function syncBody(body) if isServer() then syncBodyPart(body,0xffffffffffff) end end
local function seed(current,player,name,kind)
 local item=assert(player:getInventory():AddItem(kind),kind);item:setFavorite(true)
 current.items[name]=item;current.ids.items[name]=item:getID()
 if isServer() then sendAddItemToContainer(player:getInventory(),item) end
 return item
end
local function inventory(player)
 local result={}
 local function scan(container)
  local values=container:getItems();for i=0,values:size()-1 do local item=values:get(i)
   assert(not result[item:getID()],'duplicate actual inventory ID');result[item:getID()]=item
   if instanceof(item,'InventoryContainer') then scan(item:getItemContainer()) end
  end
 end
 scan(player:getInventory());return result
end
local function visualNames(body,patient)
 local kind,gender=body:getType(),patient:getCharacterGender()
 local clean=kind:getBandageModel()
 return {clean=clean,blood=clean and clean..'_Blood',bite=kind:getBiteWoundModel(gender),scratch=kind:getScratchWoundModel(gender),cut=kind:getCutWoundModel(gender)}
end
local function visualFlags(body)
 return {bandaged=body:bandaged(),bite=body:bitten(),scratch=body:scratched(),cut=body:isCut()}
end
local function removeFixtureVisuals(player,body)
 local removedWorn,removedInventory=0,0
 local allowed={};for _,kind in pairs(visualNames(body,player)) do allowed[kind]=true end
 -- Output cleanup may already have removed inventory entries; worn references still block native recreation.
 local worn=player:getWornItems()
 for i=worn:size()-1,0,-1 do local item=worn:getItemByIndex(i)
  if allowed[item:getFullType()] then worn:remove(item);removedWorn=removedWorn+1 end
 end
 local values=player:getInventory():getItems()
 for i=values:size()-1,0,-1 do local item=values:get(i)
  if allowed[item:getFullType()] then player:getInventory():Remove(item);removedInventory=removedInventory+1 end
 end
 player:resetModelNextFrame();player:onWornItemsChanged()
 local remainingWorn,remainingInventory=0,0
 for i=0,worn:size()-1 do if allowed[worn:getItemByIndex(i):getFullType()] then remainingWorn=remainingWorn+1 end end
 for i=0,values:size()-1 do if allowed[values:get(i):getFullType()] then remainingInventory=remainingInventory+1 end end
 print('[QUEUE_TEST] HEALTH_VISUAL_RESET patient='..key(player)..' removedWorn='..removedWorn..' removedInventory='..removedInventory
  ..' remainingWorn='..remainingWorn..' remainingInventory='..remainingInventory..' bodyBandaged='..tostring(body:bandaged()))
 assert(remainingWorn==0 and remainingInventory==0,'exact native fixture visual reset failed before injury seeding')
end
function Authority.setBagHand(player,bag,hand)
 assert(bag:getContainer()==player:getInventory(),'fixture schoolbag must remain carried')
 player:setSecondaryHandItem(hand)
 getPlayerInventory(player:getPlayerNum()):refreshBackpacks()
 local visible=ISInventoryPaneContextMenu.getContainers(player):contains(bag:getItemContainer())
 assert(visible==(hand==bag),'native bag UI visibility differs after hand/refresh')
 assert(PZSurvivorToolkit.ActionQueuePolicy.isCarriedContainer(bag:getItemContainer(),player),'hidden fixture bag lost carried-container proof')
 print('[QUEUE_TEST] HEALTH_BAG_UI bagId='..bag:getID()..' visible='..tostring(visible)..' carried=true')
end
function Authority.setup(player)
 if states[key(player)] then return states[key(player)].ids end
 if not origin then local point=require('QueueEnergyPlacement')(player);origin={x=point:getX()+0.5,y=point:getY()+0.5,z=point:getZ()} end
 position(player,origin.x+(key(player)=='client2' and 1 or 0),origin.y,origin.z)
 player:getInventory():setCapacity(150)
 local current={ids={items={},spawn=origin,username=key(player)},items={},verified=0}
 states[key(player)]=current
 for _,spec in ipairs({{'front','Base.BookCarpentry1'},{'tail','Base.BookFirstAid1'},{'bag','Base.Bag_Schoolbag'}}) do seed(current,player,spec[1],spec[2]) end
 return current.ids
end
function Authority.session(player)
 if not isServer() then return {active=true,turn=1,patient=key(player),doctor=key(player)} end
 if not online('client1') or not online('client2') then return end
 local actor=turn==1 and 'client1' or 'client2'
 return {active=key(player)==actor,turn=turn,doctor=actor,patient=turn==1 and 'client2' or 'client1'}
end
function Authority.finish(player)
 assert(isServer() and ((turn==1 and key(player)=='client1') or (turn==2 and key(player)=='client2')),'out-of-turn finish')
 local current=assert(states[key(player)]);assert(current.verified==#Cases,'incomplete MP phases')
 turn=turn+1
end
function Authority.skip(player,phase,reason)
 local current=assert(states[key(player)])
 local spec=assert(Cases[current.verified+1],'medical selection already complete')
 assert(spec.id==phase and not current.pending,'duplicate/out-of-order skip')
 local expected=Selection.skipReason(spec,key(player))
 assert(expected and reason==expected,'unjustified medical skip')
 current.verified=current.verified+1
 return {phase=phase,ok=true,reason=reason}
end
function Authority.prepare(player,phase)
 local current=assert(states[key(player)]);local spec=assert(Cases[current.verified+1]);assert(spec.id==phase and not current.pending,'duplicate/out-of-order prepare')
 assert(not Selection.skipReason(spec,key(player)),'case must be skipped explicitly')
 local session=assert(Authority.session(player));assert(session.active,'inactive doctor preparation')
 local patient=not spec.inventory and isServer() and assert(online(session.patient),'actual connected patient required') or player
 position(player,origin.x,origin.y,origin.z);position(patient,origin.x+(patient~=player and 1 or 0),origin.y,origin.z)
 local old=inventory(player)
 for id,item in pairs(old) do
  if (current.fixtureIDs and current.fixtureIDs[id]) or (item~=current.items.front and item~=current.items.tail and item~=current.items.bag and current.outputIDs and current.outputIDs[id]) then
   local container=item:getContainer();container:Remove(item);if isServer() then sendRemoveItemFromContainer(container,item) end
  end
 end
 current.fixtureIDs={};current.outputIDs={}
 local body=part(patient);body:RestoreToFullHealth()
 if not isServer() then
  -- B42's visual updater can leave duplicate worn models; reset only this fixture body's exact native types.
  removeFixtureVisuals(patient,body);patient:getBodyDamage():setBodyPartsLastState()
 end
 body:setScratched(true,false);body:setScratchTime(20)
 if spec.kind=='dirtyBandaged' then patient:getBodyDamage():SetBandaged(body:getIndex(),true,0,false,'Base.Bandage')
 elseif spec.kind=='bandaged' then patient:getBodyDamage():SetBandaged(body:getIndex(),true,20,false,'Base.Bandage')
 elseif spec.kind=='deep' then body:generateDeepWound();body:setHaveGlass(false)
 elseif spec.kind=='stitched' then body:setStitched(true)
 elseif spec.kind=='fracture' then body:setFractureTime(21)
 elseif spec.kind=='splinted' then body:setFractureTime(21);body:setSplint(true,3);body:setSplintItem('Base.Plank')
 elseif spec.kind=='glass' then body:generateDeepShardWound()
 elseif spec.kind=='bullet' then body:setHaveBullet(true,0)
 elseif spec.kind=='burn' then body:setBurnTime(50);body:setNeedBurnWash(true) end
 syncBody(body)
 local ids,uses,originalContainers={},{},{}
 for _,entry in ipairs(spec.supply or {}) do
  local name=phase..'-'..entry[1];local item=seed(current,player,name,entry[2]);ids[entry[1]]=item:getID();uses[entry[1]]=entry[3]=='fluid' and item:getFluidContainer():getAmount() or item:getCurrentUses();current.fixtureIDs[item:getID()]=true
  if spec.bag then
   player:getInventory():Remove(item);current.items.bag:getItemContainer():AddItem(item)
   if isServer() then sendRemoveItemFromContainer(player:getInventory(),item);sendAddItemToContainer(current.items.bag:getItemContainer(),item) end
  end
  originalContainers[item:getID()]=item:getContainer()
 end
 local frontPages=spec.remote=='removed' and 2 or 1
 for name,pages in pairs({front=frontPages,tail=1}) do local book=current.items[name]
  book:setAlreadyReadPages(book:getNumberOfPages()-pages);player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-pages)
 end
 current.pending={phase=phase,spec=spec,patient=patient,body=body,before=image(body),ids=ids,uses=uses,originalContainers=originalContainers,inventory=inventory(player),mutated=false,visualNames=not isServer() and visualNames(body,patient),visualFlags=not isServer() and visualFlags(body)}
 return {ok=true,phase=phase,items=ids,body=body:getIndex(),patient=key(patient),spawn=origin,before=current.pending.before,readiness=Authority.readiness(body),
  patientSpawn={x=origin.x+(patient~=player and 1 or 0),y=origin.y,z=origin.z},
  front=current.items.front:getID(),frontPages=frontPages,tail=current.items.tail:getID(),bag=current.items.bag:getID()}
end
local function wornIDs(player)
 local result={};local worn=player:getWornItems()
 for i=0,worn:size()-1 do result[worn:getItemByIndex(i):getID()]=true end
 return result
end
local function itemReceipt(item)
 local fluid=item.getFluidContainer and item:getFluidContainer()
 return {kind=item:getFullType(),uses=item:getCurrentUses(),fluid=fluid and fluid:getAmount()}
end
function Authority.baseline(player,phase)
 local current=assert(states[key(player)]);local pending=assert(current.pending)
 assert(pending.phase==phase and not pending.baselined,'duplicate/out-of-order baseline')
 local values=inventory(player);pending.inventory=values;pending.visualIDs={};pending.visualRemoval={}
 if not isServer() then
  local names,flags=pending.visualNames,pending.visualFlags
  local expected={}
  if flags.bandaged and names.clean then expected[pending.spec.replace and names.blood or names.clean]=2 end
  for _,field in ipairs({'bite','scratch','cut'}) do if flags[field] and names[field] then expected[names[field]]=1 end end
  local actual={}
  for id,item in pairs(values) do for _,kind in pairs(names) do if item:getFullType()==kind then
   actual[kind]=(actual[kind] or 0)+1;pending.visualIDs[id]=kind;break
  end end end
  local wornCounts={};local wornBefore=pending.patient:getWornItems()
  for i=0,wornBefore:size()-1 do local item=wornBefore:getItemByIndex(i)
   for _,kind in pairs(names) do if item:getFullType()==kind then wornCounts[kind]=(wornCounts[kind] or 0)+1;break end end
  end
  local counts={};for _,kind in pairs(names) do counts[#counts+1]=kind..':actual='..tostring(actual[kind] or 0)..',worn='..tostring(wornCounts[kind] or 0)..',expected='..tostring(expected[kind] or 0) end
  print('[QUEUE_TEST] HEALTH_VISUAL_BASELINE phase='..phase..' bodyBandaged='..tostring(pending.body:bandaged())
   ..' bodyScratched='..tostring(pending.body:scratched())..' '..table.concat(counts,' '))
  for kind,count in pairs(expected) do assert(actual[kind]==count,'native visual setup not settled '..kind..' actual='..tostring(actual[kind])..' expected='..count);actual[kind]=nil end
  for kind in pairs(actual) do error('unexpected fixture body visual before baseline '..kind) end
  local worn=pending.patient:getWornItems()
  for i=0,worn:size()-1 do local item=worn:getItemByIndex(i)
   for _,kind in pairs(names) do if item:getFullType()==kind then assert(values[item:getID()]==item,'orphan native fixture visual remained worn '..kind);break end end
   if pending.visualIDs[item:getID()] then pending.visualRemoval[item:getFullType()]=item:getID() end
  end
  pending.restoreWounds={bite=pending.body:getBiteTime()>0,scratch=pending.body:getScratchTime()>0,cut=pending.body:getCutTime()>0}
 end
 pending.beforeWorn=wornIDs(player);pending.baselineReceipts={}
 for id,item in pairs(values) do
  pending.baselineReceipts[id]=itemReceipt(item)
  print('[QUEUE_TEST] HEALTH_BASELINE_ID phase='..phase..' id='..id..' kind='..item:getFullType()..' worn='..tostring(pending.beforeWorn[id]==true))
 end
 pending.baselined=true
 print('[QUEUE_TEST] HEALTH_BASELINE phase='..phase..' authority='..(isServer() and 'server' or 'sp')..' nativeVisualsSettled=true')
 return {phase=phase,ok=true}
end
function Authority.mutate(player,phase,mode)
 local current=assert(states[key(player)]);local pending=assert(current.pending)
 assert(pending.phase==phase and not pending.mutated,'duplicate/out-of-order mutation');pending.mutated=true
 if mode=='missing' then
  local id=assert(pending.ids.bandage);local item=assert(inventory(player)[id]);local container=item:getContainer();container:Remove(item)
  if isServer() then sendRemoveItemFromContainer(container,item) end;pending.removed=id
 elseif mode=='move' or mode=='range' then
  local distance=mode=='move' and 1 or 9
  position(pending.patient,origin.x+distance,origin.y+1,origin.z)
 else error('unexpected authority mutation '..tostring(mode)) end
 return {ok=true,phase=phase,mode=mode,removed=pending.removed}
end
function Authority.verify(player,phase)
 local current=assert(states[key(player)]);local pending=assert(current.pending);local spec=pending.spec
 local ok,problem=pcall(function()
  assert(pending.phase==phase and pending.baselined and Cases[current.verified+1]==spec,'duplicate/out-of-order/unbaselined receipt')
  local actual=inventory(player);local changed={};local afterWorn=wornIDs(player);local union={};local beforeCount,afterCount=0,0
  for id in pairs(pending.inventory) do union[id]=true;beforeCount=beforeCount+1 end
  for id in pairs(actual) do union[id]=true;afterCount=afterCount+1 end
  for id in pairs(union) do
   local before=pending.baselineReceipts[id];local after=actual[id] and itemReceipt(actual[id])
   local wasWorn,isWorn=pending.beforeWorn[id]==true,afterWorn[id]==true
   if not before or not after or wasWorn~=isWorn or before.uses~=after.uses or before.fluid~=after.fluid then
    print('[QUEUE_TEST] HEALTH_INVENTORY_DELTA phase='..phase..' id='..id..' kind='..(before and before.kind or after.kind)
     ..' before='..tostring(before~=nil)..' after='..tostring(after~=nil)..' beforeWorn='..tostring(wasWorn)..' afterWorn='..tostring(isWorn)
     ..' beforeUses='..tostring(before and before.uses)..' afterUses='..tostring(after and after.uses)
     ..' beforeFluid='..tostring(before and before.fluid)..' afterFluid='..tostring(after and after.fluid))
   end
  end
  print('[QUEUE_TEST] HEALTH_INVENTORY_TOTAL phase='..phase..' before='..beforeCount..' after='..afterCount)
  local cancelled=(spec.cancel and Selection.mode=='toolkit') or (spec.guard and spec.guard~='helper') or spec.expanded or spec.remote or spec.replaceStop
  local removedBandage=spec.replace and spec.replaceStop~='remove'
  local expectedOutputs={};for kind,count in pairs(spec.output or {}) do expectedOutputs[kind]=count end
  if not isServer() and (not cancelled or removedBandage) then
   local names,flags=pending.visualNames,pending.visualFlags
   if spec.replace then
    for id,kind in pairs(pending.visualIDs) do
     assert(kind==names.blood and not actual[id],'native replacement left original dirty bandage visual');changed[id]=true
    end
    if spec.replaceStop=='apply' then
     for _,field in ipairs({'bite','scratch','cut'}) do if pending.restoreWounds[field] and names[field] then expectedOutputs[names[field]]=1 end end
    else expectedOutputs[names.clean]=2 end
   elseif spec.handler=='HApplyBandage' then
    assert(not flags.bandaged,'apply fixture began bandaged');expectedOutputs[names.clean]=2
    for _,field in ipairs({'bite','scratch','cut'}) do if flags[field] and names[field] then
     local id=assert(pending.visualRemoval[names[field]],'native wound visual removal ID missing')
     assert(not actual[id],'native apply left prior wound visual '..names[field]);changed[id]=true
    end end
   elseif spec.handler=='HRemoveBandage' then
    local removed=0
    -- Current dirty=true at zero life, while unbandaged last-state dirty=false; native clears one mapped visual each frame.
    for id,kind in pairs(pending.visualIDs) do if kind==names.clean or kind==names.blood then
     assert(not actual[id],'native remove left original bandage visual id='..id..' kind='..kind);changed[id]=true;removed=removed+1
    end end
    assert(removed==2,'clean bandage fixture did not account for exactly two original visual IDs')
    for _,field in ipairs({'bite','scratch','cut'}) do if pending.restoreWounds[field] and names[field] then expectedOutputs[names[field]]=1 end end
   end
  end
  for _,entry in ipairs(spec.supply or {}) do
   local id=pending.ids[entry[1]];local item=pending.inventory[id];local effect=not cancelled and entry[3]
   local live=actual[id];local amount=live and (effect=='fluid' and live:getFluidContainer():getAmount() or live:getCurrentUses())
   print('[QUEUE_TEST] HEALTH_MEDICINE_RECEIPT phase='..phase..' name='..entry[1]..' id='..id..' kind='..item:getFullType()
    ..' effect='..tostring(effect)..' before='..tostring(pending.uses[entry[1]])..' after='..tostring(amount)..' present='..tostring(live~=nil))
   if id==pending.removed or effect=='remove' then assert(not actual[id],'consumed/deleted exact ID survived '..entry[1]);changed[id]=true
   elseif effect=='fluid' then
    assert(actual[id]==item and math.abs(item:getFluidContainer():getAmount()-(pending.uses[entry[1]]-0.15))<0.00001,'native exact disinfectant fluid consumption differs')
   elseif effect=='use' then
    assert((not actual[id] and pending.uses[entry[1]]==1) or (actual[id] and actual[id]:getCurrentUses()==pending.uses[entry[1]]-1),'native exact use differs '..entry[1]);changed[id]=not actual[id]
   else
    assert(actual[id]==item,'preserved exact supply ID lost '..entry[1])
    local baseline=assert(pending.baselineReceipts[id]);local preserved=itemReceipt(item)
    assert(preserved.uses==baseline.uses and preserved.fluid==baseline.fluid,'preserved supply amount changed '..entry[1])
   end
   if cancelled and spec.bag and id~=pending.removed then
    local expected=assert(pending.originalContainers[id],'original input container not recorded')
    assert(expected==current.items.bag:getItemContainer(),'bag fixture input did not begin in schoolbag')
    assert(actual[id]==item and item:getContainer()==expected,'cancelled input not returned to original schoolbag '..entry[1])
    print('[QUEUE_TEST] HEALTH_RETURN_RECEIPT phase='..phase..' name='..entry[1]..' id='..id..' originalBagId='..current.items.bag:getID()..' restored=true')
   end
  end
  for id,item in pairs(pending.inventory) do if not changed[id] then assert(actual[id]==item,'unrelated original ID changed '..id..' type='..item:getFullType()..' beforeWorn='..tostring(pending.beforeWorn[id]==true)..' afterWorn='..tostring(afterWorn[id]==true)) end end
  local outputs={}
  for id,item in pairs(actual) do if not pending.inventory[id] then outputs[item:getFullType()]=(outputs[item:getFullType()] or 0)+1;current.outputIDs[id]=true;print('[QUEUE_TEST] HEALTH_OUTPUT_RECEIPT phase='..phase..' id='..id..' kind='..item:getFullType()) end end
  for kind,count in pairs(expectedOutputs) do assert(outputs[kind]==count,'exact output count differs '..kind);outputs[kind]=nil end
  for kind,count in pairs(outputs) do assert(count==0,'unexpected output '..kind..' count='..count) end
  for _,name in ipairs({'front','tail'}) do local book=current.items[name]
   assert(actual[book:getID()]==book,'unrelated book ID not preserved '..name)
   local pages,total=book:getAlreadyReadPages(),book:getNumberOfPages()
   -- The native MP handmade splint can consume both inputs while leaving its one-page tail unread.
   if Selection.mode=='native' and name=='tail' and spec.id=='missingSupply' then
    assert(pages==total-1,'native missing-supply tail differs from observed untouched page')
   elseif Selection.mode=='native' and name=='tail' and (spec.id=='nativeStop' or spec.id=='remoteRemoved'
    or Selection.kind=='mp' and (spec.id=='splintApply' or spec.id=='splintDrop')) then
    assert(pages==total or pages==total-1,'native control tail pages outside exact fixture range')
   elseif spec.emptyStart and name=='front' then assert(pages==total-1,'unused front book changed')
   else assert(pages==total,'unrelated book pages not preserved '..name) end
  end
  local after=image(pending.body);local before=pending.before
  local fields={};for field,value in pairs(after) do fields[#fields+1]=field..'='..tostring(value) end
  print('[QUEUE_TEST] HEALTH_BODY_RECEIPT phase='..phase..' patient='..key(pending.patient)..' part='..pending.body:getIndex()..' '..table.concat(fields,' '))
  print('[QUEUE_TEST] HEALTH_BOOK_RECEIPT phase='..phase..' frontId='..current.items.front:getID()..' frontPages='..current.items.front:getAlreadyReadPages()
   ..' tailId='..current.items.tail:getID()..' tailPages='..current.items.tail:getAlreadyReadPages())
  if spec.replace then
   for field,value in pairs(before) do if field~='bandaged' then assert(after[field]==value,'replacement changed unrelated clinical state '..field) end end
   print('[QUEUE_TEST] HEALTH_REPLACE_RECEIPT phase='..phase..' bandaged='..tostring(after.bandaged)..' life='..pending.body:getBandageLife()..' futureBandageId='..pending.ids.bandage)
   if spec.replaceStop=='apply' then assert(not after.bandaged,'completed native removal was rolled back')
   elseif spec.replaceStop=='remove' then assert(after.bandaged and pending.body:getBandageLife()<=0,'cancelled removal changed dirty bandage')
   else assert(after.bandaged and pending.body:getBandageLife()>0,'replacement clean bandage effect missing') end
  elseif cancelled then for field,value in pairs(before) do assert(after[field]==value,'skipped/cancelled clinical state changed '..field) end
  elseif spec.handler=='HApplyBandage' then assert(after.bandaged,'bandage effect missing')
  elseif spec.handler=='HRemoveBandage' then assert(not after.bandaged,'bandage removal missing')
  elseif spec.handler=='HDisinfect' then assert(after.alcohol>before.alcohol,'disinfect effect missing')
  elseif spec.handler=='HStitch' then assert(after.stitched,'stitch effect missing')
  elseif spec.handler=='HRemoveStitch' then assert(not after.stitched,'stitch removal missing')
  elseif spec.handler=='HSplint' then assert(after.splint>0,'splint effect missing')
  elseif spec.handler=='HRemoveSplint' then assert(after.splint==0,'splint removal missing')
  elseif spec.handler=='HRemoveGlass' then assert(not after.glass,'glass effect missing')
  elseif spec.handler=='HRemoveBullet' then assert(not after.bullet,'bullet effect missing')
  elseif spec.handler=='HCleanBurn' then assert(not after.wash,'burn effect missing')
  else local field=spec.handler=='HApplyComfrey' and 'comfrey' or spec.handler=='HApplyGarlic' and 'garlic' or 'plantain';assert(after[field]>0,'poultice effect missing') end
  current.verified=current.verified+1;current.pending=nil
 end)
 print('[QUEUE_TEST] HEALTH_AUTH_RECEIPT '..key(player)..' phase='..phase..' ok='..tostring(ok)..' patient='..key(pending.patient)..' error='..tostring(problem))
 local tail=current.items.tail
 return {phase=phase,ok=ok,error=tostring(problem),body=image(pending.body),supply=pending.ids,front=current.items.front:getID(),tail=tail:getID(),
  outcome={supplyEffectsVerified=ok,clinicalEffectVerified=ok,serverAuthorityVerified=ok and isServer(),body=image(pending.body),tailCompleted=tail:getAlreadyReadPages()==tail:getNumberOfPages(),tailPages=tail:getAlreadyReadPages(),tailTotal=tail:getNumberOfPages()}}
end
return Authority
