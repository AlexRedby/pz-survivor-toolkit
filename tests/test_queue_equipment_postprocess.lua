package.preload.QueueEquipmentBulk=function() return assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/shared/QueueEquipmentBulk.lua'))() end
package.preload.QueueEquipmentClothing=function() return assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/shared/QueueEquipmentClothing.lua'))() end
package.preload.QueueEquipmentHotbar=function() return assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/shared/QueueEquipmentHotbar.lua'))() end
local Postprocess=assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/shared/QueueEquipmentPostprocess.lua'))()
local function list(items)
 return {size=function() return #items end,get=function(_,i) return items[i+1] end,
  contains=function(_,item) for _,value in ipairs(items) do if value==item then return true end end return false end}
end
local function container()
 return {items={},getItems=function(self) return list(self.items) end}
end
local nextID=0
local function item(kind,dest)
 nextID=nextID+1
 local value={id=nextID,kind=kind,container=dest,pages=220}
 function value:getID() return self.id end
 function value:getFullType() return self.kind end
 function value:getContainer() return self.container end
 function value:getItemContainer() return self.inside end
 function value:getAlreadyReadPages() return self.pages end
 function value:getNumberOfPages() return 220 end
 function value:getWorldItem() return self.world end
 function value:getAttachedSlot() return self.slot or -1 end
 function value:getAttachedSlotType() return self.slotType end
 function value:getAttachedToModel() return self.model end
 dest.items[#dest.items+1]=value;return value
end
function instanceof(value,kind) return kind=='InventoryContainer' and value.inside~=nil end
local function move(value,dest)
 if value.container then
  for i,entry in ipairs(value.container.items) do if entry==value then table.remove(value.container.items,i);break end end
 end
 value.container=dest;if dest then dest.items[#dest.items+1]=value end
end
local function fixture(id,mode)
 local state={id=id,root=container(),items={},baseline={},original={},originalContainers={},expectedWorn={},originalAttached={}}
 local function seed(name,kind,dest)
  local value=item(kind or name,dest or state.root)
  state[name]=value;state.items[name]=value;state.baseline[value.id]=value;return value
 end
 for _,name in ipairs({'front','tail','hammer','screwdriver','bag'}) do seed(name) end
 state.bag.inside=container();state.source=state.bag.inside;state.expectedWorn.Back=state.bag
 local player={primary=state.hammer,secondary=state.screwdriver,worn=state.expectedWorn,attached={}}
 function player:getInventory() return state.root end
 function player:getPrimaryHandItem() return self.primary end
 function player:getSecondaryHandItem() return self.secondary end
 function player:getAlreadyReadPages() return 220 end
 function player:getWornItems()
  local values={};for _,value in pairs(self.worn) do values[#values+1]=value end
  local result=list(values);result.getItemByIndex=result.get
  function result:getLocation(value) for location,entry in pairs(player.worn) do if entry==value then return location end end end
  return result
 end
 function player:getAttachedItems()
  local values={}
  for location,value in pairs(self.attached) do
   local slot,entry=location,value
   values[#values+1]={getLocation=function() return slot end,getItem=function() return entry end}
  end
  return list(values)
 end
 state.player=player
 local original=item('original',state.root);state.original[original.id]=original;state.originalContainers[original.id]=state.root
 state.baseline[original.id]=original
 player.attached.Unrelated=original;state.originalAttached.Unrelated=original
 if id=='hands-chain' or id=='waiting-cancel' then
  seed('bat',nil,id=='waiting-cancel' and mode=='toolkit' and state.source or state.root);seed('content',nil,state.source)
  if id=='waiting-cancel' and mode=='native' then player.primary,player.secondary=state.bat,state.bat end
 elseif id=='bag-capacity' then
  for i=1,3 do seed('plank'..i,nil,state.source) end
  seed('pickupBag');state.pickupBag.inside=container();state.pickupSource=state.pickupBag.inside
  seed('pickup');player.secondary=state.pickupBag;state.expectedWorn.Back=nil
 elseif id=='clothing-chain' then
  seed('clothingA');seed('clothingB');state.expectedWorn.Socks=state.clothingB
 elseif id=='hotbar-chain' then
  seed('hotbarInitial');seed('hotbarReplacement');state.hotbarLocation='Shovel Back with Bag'
  state.hotbarIndex,state.hotbarType=1,'Back'
  state.hotbarReplacement.slot,state.hotbarReplacement.slotType,state.hotbarReplacement.model=1,'Back',state.hotbarLocation
  player.attached[state.hotbarLocation]=state.hotbarReplacement
 elseif id:match('^bulk') then
  seed('bulkHeavyA',nil,id=='bulk-waiting-cancel' and state.source or state.root)
  for i=1,3 do seed('bulkLight'..i,nil,id=='bulk-waiting-cancel' and state.source or state.root) end
  seed('bulkHeavyB',nil,id=='bulk-waiting-cancel' and state.source or state.root)
  if id=='bulk-mixed' then seed('bulkBorrowed') end
  if id=='bulk-waiting-cancel' then seed('bulkSurvivor') end
 elseif id=='floor-pickup' then
  seed('pickup');state.floor={id=state.pickup.id,x=1,y=2,z=0}
  local square={objects={}};function square:getWorldObjects() return list(self.objects) end
  function getCell() return {getGridSquare=function() return square end} end
  state.pickupWorld={getItem=function() return state.pickup end};state.square=square
 end
 return state
end
local function rejected(state,mode,tidy,reason)
 local ok,problem=pcall(Postprocess.verify,state,mode,tidy)
 assert(not ok and tostring(problem):find(reason,1,true),'missing expected failure '..reason..': '..tostring(problem))
end
for _,id in ipairs({'hands-chain','waiting-cancel','bag-capacity','clothing-chain','hotbar-chain','floor-pickup','bulk-pickup','bulk-waiting-cancel','bulk-mixed'}) do
 local state=fixture(id,'native');assert(Postprocess.verify(state,'native',false).postprocessingVerified)
end
for _,id in ipairs({'hands-chain','clothing-chain'}) do
 local state=fixture(id,'native')
 local value,dest=state.bat or state.pickup or state.clothingA,state.pickupSource or state.source
 move(value,dest);assert(Postprocess.verify(state,'native',true).postprocessingVerified)
 rejected(state,'native',false,'container differs')
end
local capacity=fixture('bag-capacity','native');move(capacity.pickup,capacity.pickupSource)
rejected(capacity,'native',true,'P4 returned deliberately picked up carried item')
local cancelled=fixture('waiting-cancel','toolkit');assert(Postprocess.verify(cancelled,'toolkit',true).postprocessingVerified)
local waiting=fixture('waiting-cancel','native');move(waiting.bat,waiting.source);waiting.player.primary,waiting.player.secondary=nil,nil
rejected(waiting,'native',true,'P4 removed deliberately equipped bat')
local hotbar=fixture('hotbar-chain','native');move(hotbar.hotbarReplacement,hotbar.source);hotbar.player.attached={}
rejected(hotbar,'native',true,'P4 removed deliberately attached hotbar item')
local floor=fixture('floor-pickup','native');local oldPickup=floor.pickup;move(oldPickup,nil)
local restored=item(oldPickup.kind,container());restored.id=oldPickup.id;move(restored,nil)
local world={getItem=function() return restored end,getSquare=function() return floor.square end}
restored.world=world;floor.square.objects={world};floor.owned={oldPickup}
rejected(floor,'native',true,'P4 returned deliberately picked up floor item')
assert(floor.pickup==restored and floor.items.pickup==restored and floor.owned[1]==restored,'restored floor identity was not rebound')
rejected(floor,'native',false,'floor pickup returned without pack')
floor.square.objects={world,world};rejected(floor,'native',true,'duplicate restored floor ID')
floor.square.objects={world};move(floor.pickup,floor.root);rejected(floor,'native',true,'floor pickup duplicated')
local lost=fixture('hands-chain','native');move(lost.content,nil);rejected(lost,'native',false,'lost/replaced inventory ID')
local duplicate=fixture('hands-chain','native');duplicate.source.items[#duplicate.source.items+1]=duplicate.front
rejected(duplicate,'native',false,'duplicate postprocessing inventory ID')
local extra=fixture('hands-chain','native');item('unexpected',extra.root);rejected(extra,'native',false,'unexpected postprocessing inventory ID')
local wrongType=fixture('hands-chain','native');local original=wrongType.content;local replacement=item('wrong',wrongType.source)
move(original,nil);replacement.id=original.id;rejected(wrongType,'native',false,'lost/replaced inventory ID')
local changed=fixture('hands-chain','native');local old=next(changed.original);move(changed.original[old],changed.source)
rejected(changed,'native',false,'postprocessing moved original item')
local book=fixture('hands-chain','native');book.tail.pages=219;rejected(book,'native',false,'book incomplete')
local slots=fixture('hands-chain','native');slots.player.worn={};rejected(slots,'native',false,'worn item changed')
local attachment=fixture('hands-chain','native');attachment.player.attached.Unexpected=attachment.hammer
rejected(attachment,'native',false,'unexpected attachment')
local metadata=fixture('hotbar-chain','native');metadata.hotbarReplacement.slotType=nil
rejected(metadata,'native',false,'postprocessing changed hotbar metadata')
print('Equipment postprocessing: exact identities, deterministic returns, floor restoration and deliberate equipment protection passed.')

local mixed=fixture('bulk-mixed','toolkit');move(mixed.bulkBorrowed,mixed.source)
assert(Postprocess.verify(mixed,'toolkit',true).postprocessingVerified,'borrowed bulk item must return after idle')
move(mixed.bulkLight2,mixed.source)
rejected(mixed,'toolkit',true,'bulk exact source/destination differs bulkLight2')
local bulk=fixture('bulk-pickup','toolkit');move(bulk.bulkHeavyB,bulk.source)
rejected(bulk,'toolkit',true,'bulk exact source/destination differs bulkHeavyB')
local bulkCancel=fixture('bulk-waiting-cancel','toolkit');move(bulkCancel.bulkSurvivor,bulkCancel.source)
rejected(bulkCancel,'toolkit',true,'bulk exact source/destination differs bulkSurvivor')

-- Borrowed floor returns require exact pose, activation and identity, not merely an empty queue.
local borrowed=fixture('floor-pickup','toolkit');borrowed.id='tidy-floor'
local gun=borrowed.pickup
function gun:getCurrentAmmoCount() return 0 end
function gun:isRoundChambered() return false end
function borrowed.hammer:isActivated() return self.active~=false end
borrowed.floor.pose={0.25,0.75,0,0,0,37}
local pose={0.25,0.75,0,0,0,37}
local returned={getItem=function() return gun end,getSquare=function() return borrowed.square end,
 getOffX=function() return pose[1] end,getOffY=function() return pose[2] end,getOffZ=function() return pose[3] end}
function gun:getWorldXRotation() return pose[4] end
function gun:getWorldYRotation() return pose[5] end
function gun:getWorldZRotation() return pose[6] end
move(gun,nil);gun.world=returned;borrowed.square.objects={returned}
assert(Postprocess.verify(borrowed,'toolkit',true).floorRestored)
for i=1,6 do
 local old=pose[i];pose[i]=old+0.1
 rejected(borrowed,'toolkit',true,'borrowed floor pose changed');pose[i]=old
end
borrowed.hammer.active=false;rejected(borrowed,'toolkit',true,'torch activation');borrowed.hammer.active=true
borrowed.square.objects={};rejected(borrowed,'toolkit',true,'lost floor pickup ID');borrowed.square.objects={returned}
borrowed.square.objects={returned,returned};rejected(borrowed,'toolkit',true,'duplicate restored floor ID')

-- Empty hands must be restored after borrowing, with the exact gun returned once.
for _,mode in ipairs({'toolkit','native'}) do
 local empty=fixture('clothing-chain',mode);empty.id='tidy-empty-hands'
 empty.pickup=empty.clothingA;empty.items.pickup=empty.clothingA;empty.items.clothingA=nil
 function empty.pickup:getCurrentAmmoCount() return 0 end
 function empty.pickup:isRoundChambered() return false end
 empty.player.primary,empty.player.secondary=empty.pickup,nil
 assert(Postprocess.verify(empty,mode,false).postprocessingVerified)
 rejected(empty,mode,true,'postprocessing changed final hands')
 empty.player.primary=nil
 rejected(empty,mode,true,'postprocessing seed container differs pickup')
 move(empty.pickup,empty.source)
 assert(Postprocess.verify(empty,mode,true).postprocessingVerified)
 empty.player.secondary=empty.screwdriver
 rejected(empty,mode,true,'postprocessing changed final hands')
end

-- The server final postprocess independently checks alarm state after P4 has
-- restored/removed the exact root watch, rather than trusting client evidence.
do
 local Clothing=require 'QueueEquipmentClothing'
 local oldInstanceof=instanceof
 instanceof=function(value,kind)
  return value.watch and (kind=='AlarmClockClothing'or kind=='Clothing')or oldInstanceof(value,kind)
 end
 isClient=function()return false end
 getCell=function()return {getProcessItems=function()return {contains=function()return true end}end,
  getProcessItemsRemove=function()return {contains=function()return false end}end}end
 for _,case in ipairs({'tidy-watch-digital-restore','tidy-watch-digital-remove','tidy-watch-classic-restore','tidy-watch-classic-remove',
  'tidy-watch-overlap-primary','tidy-watch-overlap-secondary','tidy-watch-overlap-both',
  'tidy-watch-held-primary','tidy-watch-held-secondary','tidy-watch-held-both'})do
  for _,tidy in ipairs({false,true})do
   local sample=fixture(case,'native')
   local spec=Clothing.spec(sample)
   local watch=item(spec.fullType,sample.root);watch.watch=true;watch.hour=21;watch.minute=40;watch.alarm=spec.alarmSet;watch.ringing=false
   watch.getHour=function(self)return self.hour end;watch.getMinute=function(self)return self.minute end
   watch.isAlarmSet=function(self)return self.alarm end;watch.isRinging=function(self)return self.ringing end
   watch.getCategory=function()return 'AlarmClock'end
   sample.clothingItem=watch;sample.clothingLocation=spec.location;sample.clothingHair='CrewCut'
   sample.clothingWatch={alarmHour=21,alarmMinute=40,alarmSet=spec.alarmSet,ringing=false}
   sample.items.clothingItem=watch;sample.baseline[watch.id]=watch
   sample.root.getItemById=function(self,id)for _,value in ipairs(self.items)do if value.id==id then return value end end end
   sample.player.getWornItem=function(self,location)return self.worn[location]end
   sample.player.getHumanVisual=function()return {getHairModel=function()return 'CrewCut'end,getNonAttachedHair=function()end}end
   for _,item in ipairs({sample.hammer,sample.screwdriver})do item.isActivated=function()return false end end
   sample.player.primary,sample.player.secondary=Clothing.expectedHands(sample,tidy)
   local worn=Clothing.finalWorn(sample,tidy)
   getCell=function()return {getProcessItems=function()return {contains=function()return spec.alarmSet and worn end}end,
    getProcessItemsRemove=function()return {contains=function()return false end}end}end
   sample.player.worn[spec.location]=worn and watch or nil
   local value=Postprocess.verify(sample,'native',tidy).clothing
   assert(value.watch.alarmHour==21 and value.watch.alarmSet==spec.alarmSet and value.watchProcessing.active==(spec.alarmSet and worn))
   for key,bad in pairs({hour=22,minute=30,alarm=not spec.alarmSet,ringing=true})do
    local before=watch[key];watch[key]=bad
    rejected(sample,'native',tidy,'native watch alarm changed')
    watch[key]=before
   end
  end
 end
 instanceof=oldInstanceof
end
print('Equipment watch postprocessing: authority rejects changed time, enabled state and ringing after exact native cleanup.')

-- Final authority independently proves both original and temporary roots and
-- exact same-slot/exclusive output, after the live fixture's native receipts.
do
 local Clothing=require 'QueueEquipmentClothing'
 for _,case in ipairs({'tidy-clothing-replace','tidy-headwear-hat-exclusive','tidy-headwear-full-hat-exclusive'})do
  for _,tidy in ipairs({false,true})do
   local sample=fixture(case,'native');local spec=Clothing.spec(sample)
   local baseline=item(spec.fullType,sample.root);local temp=item(spec.temporaryType,sample.root)
   baseline.getBodyLocation=function()return spec.location end;temp.getBodyLocation=function()return spec.temporaryLocation end
   sample.clothingItem,sample.clothingTemporary,sample.clothingLocation,sample.clothingHair=baseline,temp,spec.location,'CrewCut'
   sample.items.clothingItem=baseline;sample.items.clothingTemporary=temp
   sample.baseline[baseline.id]=baseline;sample.baseline[temp.id]=temp;sample.expectedWorn[spec.location]=baseline
   sample.root.getItemById=function(self,id)for _,value in ipairs(self.items)do if value.id==id then return value end end end
   sample.player.getWornItem=function(self,location)return self.worn[location]end
   sample.player.getHumanVisual=function()return {getHairModel=function()return 'CrewCut'end,getNonAttachedHair=function()end}end
   sample.player.worn=Clothing.expectedWorn(sample,sample.player.worn,tidy)
   local value=Postprocess.verify(sample,'native',tidy).clothing
   assert(value.id==baseline.id and value.worn==tidy and value.temporary.id==temp.id and value.temporary.worn==not tidy)
   local kind=temp.kind;temp.kind='Base.Other';assert(not pcall(Postprocess.verify,sample,'native',tidy));temp.kind=kind
   sample.player.worn[spec.location]=tidy and temp or baseline
   assert(not pcall(Postprocess.verify,sample,'native',tidy),'wrong same/exclusive final worn identity must fail')
  end
 end
end
print('Equipment displacement postprocessing: both exact root identities and same/exclusive final slots passed.')

-- Server postprocess validates its own native Mohawk output and gel conservation;
-- client and SP use the same snapshot helper with their role-specific model.
do
 local Clothing=require 'QueueEquipmentClothing'
 for _,case in ipairs({'tidy-headwear-mohawk-hat-restore','tidy-headwear-mohawk-hat-remove','tidy-headwear-mohawk-full-hat-restore','tidy-headwear-mohawk-full-hat-remove'})do
  for _,role in ipairs({'sp','client','server'})do for _,tidy in ipairs({false,true})do
   local sample=fixture(case,'native');local spec=Clothing.spec(sample)
   local garment=item(spec.fullType,sample.root);local gel=item('Base.Hairgel',sample.root)
   garment.getBodyLocation=function()return spec.location end
   gel.getMaxUses=function()return 20 end;gel.getUseDelta=function()return 0.05 end;gel.getCurrentUses=function()return gel.uses end;gel.uses=20
   sample.clothingItem,sample.clothingGel,sample.clothingLocation,sample.clothingHair=garment,gel,spec.location,'MohawkFan'
   sample.items.clothingItem=garment;sample.items.clothingGel=gel
   sample.baseline[garment.id]=garment;sample.baseline[gel.id]=gel
   sample.root.getItemById=function(self,id)for _,value in ipairs(self.items)do if value.id==id then return value end end end
   sample.player.getWornItem=function(self,location)return self.worn[location]end
   local color={getRedFloat=function()return 0.2 end,getGreenFloat=function()return 0.3 end,getBlueFloat=function()return 0.4 end}
   local visual={hair='MohawkFan',getHairModel=function(self)return self.hair end,getNonAttachedHair=function()end,getHairColor=function()return color end}
   sample.player.getHumanVisual=function()return visual end
   sample.clothingAppearanceBaseline=Clothing.appearance(sample);gel.uses=19
   sample.clothingAppearanceCheckpoint=Clothing.appearance(sample)
   visual.hair=tidy and role~='client'and (role=='sp'or not spec.remove)and 'MohawkFlat'or 'MohawkFan'
   sample.player.worn=Clothing.expectedWorn(sample,sample.player.worn,Clothing.finalWorn(sample,tidy))
   isClient=function()return role=='client'end;isServer=function()return role=='server'end
   local result=Postprocess.verify(sample,'native',tidy).clothing
   assert(result.appearance.hairModel==visual.hair and result.appearance.gel.id==gel.id and result.appearance.gel.uses==19)
   gel.uses=20;assert(not pcall(Postprocess.verify,sample,'native',tidy),'missing native styling use accepted');gel.uses=19
   local expected=visual.hair;visual.hair=expected=='MohawkFan'and 'MohawkFlat'or 'MohawkFan'
   assert(not pcall(Postprocess.verify,sample,'native',tidy),'wrong per-role native appearance accepted');visual.hair=expected
  end end
 end
 isClient=function()return false end;isServer=function()return false end
end
print('Equipment Mohawk postprocessing: exact per-role hair, color/attachment and one native gel use passed; growth timer unavailable.')

-- Shared postprocess keeps the exact ordinary tool, Belt2 provider and prior
-- secondary on authority, including no-P4 temporary held outcomes.
do
 local Hotbar=require 'QueueEquipmentHotbar'
 getClassSimpleName=function(item)return item.javaClass end
 for _,case in ipairs({'tidy-hotbar-normal-left','tidy-hotbar-normal-right'})do
  for _,tidy in ipairs({false,true})do
   local sample=fixture(case,'native');local player=sample.player
   local target=item('Base.ScissorsBluntMedical',sample.root);local belt=item('Base.Belt2',sample.root)
   target.javaClass='ComboItem'
   sample.screwdriver.kind='Base.Screwdriver'
   sample.pickup,sample.belt=target,belt;sample.items.pickup=target;sample.items.belt=belt
   sample.baseline[target.id]=target;sample.baseline[belt.id]=belt
   sample.hotbarIndex=case:find('left',1,true)and 11 or 13
   sample.hotbarType=case:find('left',1,true)and 'SmallBeltLeft'or 'SmallBeltRight'
   sample.hotbarLocation=case:find('left',1,true)and 'Belt Left Screwdriver'or 'Belt Right Screwdriver'
   target.slot,target.slotType,target.model=sample.hotbarIndex,sample.hotbarType,sample.hotbarLocation
   target.canBeActivated=function()return false end;target.getScriptItem=function()return {getItemType=function()return 'base:normal'end}end
   target.getCondition=function(self)return self.condition or 10 end;target.getSharpness=function()return 1 end
   belt.getBodyLocation=function()return 'base:belt'end
   sample.root.getItemById=function(self,id)for _,value in ipairs(self.items)do if value.id==id then return value end end end
   player.getWornItem=function(self,location)return self.worn[location]end
   local color={getRedFloat=function()return 0.2 end,getGreenFloat=function()return 0.3 end,getBlueFloat=function()return 0.4 end}
   player.getHumanVisual=function()return {getHairModel=function()return 'CrewCut'end,getNonAttachedHair=function()end,getHairColor=function()return color end}end
   local prior=case=='tidy-hotbar-normal-right'
   sample.hotbarOrdinaryBaseline={condition=10,sharpness=1,hairStyle='CrewCut',nonAttachedHair=false,hairColor={r=0.2,g=0.3,b=0.4},
    secondary=prior and {id=sample.screwdriver.id,fullType='Base.Screwdriver',container='root'}or false}
   player.primary,player.secondary=Hotbar.expectedHands(sample,tidy)
   player.worn['base:belt']=belt;sample.expectedWorn['base:belt']=belt
   if tidy then player.attached[sample.hotbarLocation]=target end
   isClient=function()return false end;isServer=function()return true end
   isForceDropHeavyItem=function()return false end
   local result=Postprocess.verify(sample,'native',tidy).hotbar
   assert(result.id==target.id and result.attached==tidy and result.providerItem==belt.id and result.ordinaryBaseline==sample.hotbarOrdinaryBaseline)
   target.javaClass='InventoryItem';assert(not pcall(Postprocess.verify,sample,'native',tidy),'generic base class accepted instead of native ComboItem');target.javaClass='ComboItem'
   target.condition=9;assert(not pcall(Postprocess.verify,sample,'native',tidy),'changed normal tool condition accepted');target.condition=nil
   player.secondary=sample.hammer;assert(not pcall(Postprocess.verify,sample,'native',tidy),'changed native secondary accepted')
  end
 end
 isClient=function()return false end;isServer=function()return false end
end
print('Equipment ordinary hotbar postprocess: exact tool/provider/root/hands and unchanged condition/sharpness/appearance passed.')
