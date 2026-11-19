-- Authority-only seeds/interventions; native queue work is never synthesized.
local F={}
function F.beltCase(case)return case=='belt-scissors'or case=='belt-scissors-cancel'or case=='belt-scissors-replace'end
function F.cancelCase(case)return case=='cancel-active'or case=='belt-scissors-cancel'end
function F.beltSnapshot(s)
 if not F.beltCase(s.ids.case)then return end
 local p=s.player;local tool=assert(F.find(p,s.ids.items.razor.id));local replacement=assert(F.find(p,s.ids.items.replacement.id))
 local provider=p:getWornItem(assert(F.find(p,s.ids.items.belt.id)):getBodyLocation())
 local function item(row)return{id=row:getID(),slot=row:getAttachedSlot(),slotType=row:getAttachedSlotType()or false,model=row:getAttachedToModel()or false,root=p:getInventory():getItemById(row:getID())==row and row:getContainer()==p:getInventory()}end
 return{tool=item(tool),replacement=item(replacement),occupant=(p:getAttachedItem('Belt Left Screwdriver')and p:getAttachedItem('Belt Left Screwdriver'):getID()or false),provider=provider and provider:getID()or false}
end
local P=require 'QueueEnergyPlacement'
local mandatoryTypes={['mandatory-both-stone-wheel']='Base.StoneWheelSmall',['mandatory-both-wood-axe-new-primary-intent']='Base.WoodAxe'}
function F.heavyCase(case)return case=='heavy-stone-anvil'or case=='heavy-stone-anvil-new-primary-intent'or case=='heavy-stone-anvil-unavailable'end
function F.unavailableHeavy(case)return case=='heavy-stone-anvil-unavailable'end
function F.mandatoryType(case)return mandatoryTypes[case]end
function F.mandatoryCase(case)return mandatoryTypes[case]~=nil end
function F.twoHandedCase(case)return case=='two-handed-axe'or case=='two-handed-axe-new-primary-intent'end
function F.oneHandedCase(case)return case=='one-handed-axe'or case=='one-handed-axe-new-primary-intent'end
function F.axeCase(case)return F.twoHandedCase(case)or F.oneHandedCase(case)end
function F.equipmentCase(case)return F.axeCase(case)or F.mandatoryCase(case)or F.heavyCase(case)end
function F.sharedHandCase(case)return F.twoHandedCase(case)or F.mandatoryCase(case)or F.heavyCase(case)end
function F.intentCase(case)return case=='heavy-stone-anvil-new-primary-intent'or case=='new-primary-intent'or case=='two-handed-axe-new-primary-intent'or case=='one-handed-axe-new-primary-intent'or case=='mandatory-both-wood-axe-new-primary-intent'end
function F.returnedCase(case)return case=='heavy-stone-anvil'or case=='restore-success'or case=='mandatory-both-stone-wheel'or case=='two-handed-axe'or case=='one-handed-axe'or case=='empty-primary'or case=='cancel-active'or case=='trim-scissors'or case=='cut-hair-scissors'end
function F.restoreBoundaryCase(case)return case=='empty-primary'or F.equipmentCase(case)and not F.intentCase(case)and not F.unavailableHeavy(case)end
local function id(item)return item and item:getID()or false end
function F.same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not F.same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
function F.find(player,wanted)
 local function scan(container)
  local items=container:getItems()
  for i=0,items:size()-1 do local item=items:get(i)
   if item:getID()==wanted then return item end
   if instanceof(item,'InventoryContainer')then local found=scan(item:getItemContainer());if found then return found end end
  end
 end
 return scan(player:getInventory())
end
-- Exact world identity is independently observed on authority and replica.
function F.heavySnapshot(s)
 if not F.heavyCase(s.ids.case)then return end
 local spec=s.ids.items.previous;local root=s.player:getInventory();local inventory=F.find(s.player,spec.id)
 local at=s.ids.placement;local square=assert(getCell():getGridSquare(at.x,at.y,at.z));local found,world,count=nil,nil,0
 local objects=square:getWorldObjects()
 for i=0,objects:size()-1 do local candidate=objects:get(i);local item=candidate:getItem()
  if item and item:getID()==spec.id then found,world,count=item,candidate,count+1 end
 end
 assert(count<=1 and not(inventory and found),'heavy fixture exact ID duplicated across inventory/world')
 local item=inventory or found or assert(s.previousItem,'heavy fixture lost original detached item')
 assert(item:getFullType()==spec.type,'heavy fixture ID changed type');s.previousItem=item
 local present=world~=nil and world:getItem()==item and item:getWorldItem()==world and world:getSquare()==square
 return{item=item,world=world,physical={id=spec.id,type=spec.type,x=at.x,y=at.y,z=at.z,
  state=inventory and'root'or present and'world'or'unavailable',rootPresent=inventory~=nil,worldPresent=present,
  canonical=inventory and item:getContainer()==root and root:getItemById(spec.id)==item or present or not inventory and not found}}
end
function F.observeHeavyAuthority(s)
 if not s or not F.heavyCase(s.ids.case)then return end
 assert(not isClient(),'heavy authority observed on replica')
 local found=F.heavySnapshot(s);local phase=found.physical.state
 if phase=='root'and not s.heavyDropped or s.heavyLast==phase then return end
 if phase=='world'then s.heavyDropped=true end
 assert(s.heavyDropped,'heavy item disappeared before exact native world drop was observed')
 s.heavyLast=phase
 local row={case=s.ids.case,phase=phase=='world'and'dropped'or phase=='root'and'recovered'or'removed',at=getTimestampMs(),authority=true,
  player=s.player:getOnlineID(),itemSame=found.item==s.seedPrevious,physical=found.physical,snapshot=F.snapshot(s)}
 assert(row.itemSame,'authority heavy drop/recovery changed exact seeded object')
 s.heavy=s.heavy or{};s.heavy[#s.heavy+1]=row;return row
end
function F.removeHeavy(s,requestedAt)
 assert(not isClient()and F.unavailableHeavy(s.ids.case)and not s.heavyRemoved,'unexpected heavy authority intervention')
 local found=F.heavySnapshot(s);local world=assert(found.world,'heavy intervention requires exact world object')
 local player=s.player;local razor=assert(F.find(player,s.ids.items.razor.id))
 assert(found.physical.state=='world'and player:getPrimaryHandItem()==razor and player:getHumanVisual():getBeardModel()==s.ids.initialBeard,'heavy intervention missed genuine trim')
 local row={case=s.ids.case,at=getTimestampMs(),requestedAt=requestedAt,authority=true,before=F.snapshot(s)}
 local square=assert(world:getSquare());square:transmitRemoveItemFromSquare(world)
 if world:getObjectIndex()>=0 then world:removeFromWorld();world:removeFromSquare()end
 found.item:setWorldItem(nil);row.after=F.snapshot(s)
 assert(row.after.heavy.state=='unavailable','heavy world removal did not take effect');s.heavyRemoved=row;return row
end
function F.snapshot(s)
 local player,root=s.player,s.player:getInventory();local items,worn={},{}
 local bag=F.find(player,s.ids.bag.id)or assert(s.bag);s.bag=bag;local detached=root:getItemById(bag:getID())~=bag
 local function scan(container,parent)
  local values=container:getItems()
  for i=0,values:size()-1 do local item=values:get(i)
   items[#items+1]={id=item:getID(),type=item:getFullType(),container=parent,condition=item:getCondition(),
    favorite=item:isFavorite(),count=item:getCount(),canonical=item:getContainer()==container and F.find(player,item:getID())==item}
   if instanceof(item,'InventoryContainer')then scan(item:getItemContainer(),item:getID())end
  end
 end
 scan(root,'root')
 if detached then
  items[#items+1]={id=bag:getID(),type=bag:getFullType(),container='unavailable',condition=bag:getCondition(),favorite=bag:isFavorite(),count=bag:getCount(),canonical=bag==s.bag and root:getItemById(bag:getID())==nil}
  scan(bag:getItemContainer(),bag:getID())
 end
 local heavy=F.heavySnapshot(s)
 if heavy and heavy.physical.state~='root'then local item=heavy.item
  items[#items+1]={id=item:getID(),type=item:getFullType(),container=heavy.physical.state,condition=item:getCondition(),
   favorite=item:isFavorite(),count=item:getCount(),canonical=heavy.physical.canonical}
 end
 table.sort(items,function(a,b)return a.id<b.id end)
 local values=player:getWornItems()
 for i=0,values:size()-1 do local row=values:get(i);worn[#worn+1]={id=row:getItem():getID(),location=tostring(row:getLocation())}end
 table.sort(worn,function(a,b)return a.location<b.location end)
 local visual=player:getHumanVisual();local hc,bc=visual:getHairColor(),visual:getBeardColor()
 local tail=assert(F.find(player,s.ids.items.tail.id))
 return{belt=F.beltSnapshot(s),heavy=heavy and heavy.physical or nil,case=s.ids.case,male=not player:isFemale(),items=items,worn=worn,
  primary=id(player:getPrimaryHandItem()),secondary=id(player:getSecondaryHandItem()),
  origin={id=bag:getID(),type=bag:getFullType(),container=detached and'unavailable'or'root',worn=player:getWornItems():contains(bag),sourceCount=bag:getItemContainer():getItems():size()},
  appearance={beard=visual:getBeardModel()or'',hair=visual:getHairModel()or'',nonAttached=visual:getNonAttachedHair()or false,
   hairColor={r=hc:getRedFloat(),g=hc:getGreenFloat(),b=hc:getBlueFloat()},beardColor={r=bc:getRedFloat(),g=bc:getGreenFloat(),b=bc:getBlueFloat()}},
  tail={id=tail:getID(),type=tail:getFullType(),pages=tail:getAlreadyReadPages(),total=tail:getNumberOfPages(),characterPages=player:getAlreadyReadPages(tail:getFullType())}}
end
function F.transferSnapshot(s,role)
 if role=='heavyPickup'then
  local found=F.heavySnapshot(s);local state=found.physical
  return{case=s.ids.case,role=role,at=getTimestampMs(),authority=not isClient(),itemId=state.id,itemType=state.type,
   source='world',destination='root',sourceCount=state.worldPresent and 1 or 0,destinationCount=state.rootPresent and 1 or 0,
   canonical=state.canonical,bagCanonical=true,heavy=state}
 end
 local root=s.player:getInventory();local bag=F.find(s.player,s.ids.bag.id)or assert(s.bag);s.bag=bag;local source=bag:getItemContainer()
 local wanted=s.ids.items.razor;local function count(container)
  local total=0;local values=container:getItems()
  for i=0,values:size()-1 do if values:get(i):getID()==wanted.id then total=total+1 end end;return total
 end
 local rootCount,bagCount=count(root),count(source);local item=F.find(s.player,wanted.id)
 local pickup=role=='pickup'
 return{case=s.ids.case,role=role,at=getTimestampMs(),authority=not isClient(),itemId=wanted.id,itemType=wanted.type,
  source=pickup and s.ids.bag.id or'root',destination=pickup and'root'or s.ids.bag.id,
  sourceCount=pickup and bagCount or rootCount,destinationCount=pickup and rootCount or bagCount,
  canonical=item~=nil and item:getFullType()==wanted.type and(rootCount+bagCount)==1
   and(item:getContainer()==root or item:getContainer()==source),
  bagCanonical=root:getItemById(s.ids.bag.id)==bag and bag:getContainer()==root and s.player:getWornItems():contains(bag)}
end
function F.observeTransferAuthority(s)
 if not s or s.returnObserved or F.beltCase(s.ids.case)then return end
 local role=s.pickupObserved and'returned'or'pickup'
 if role=='returned'and(s.ids.handAckDelay or not F.returnedCase(s.ids.case))then return end
 local row=F.transferSnapshot(s,role)
 if row.sourceCount~=0 or row.destinationCount~=1 or not row.canonical or not row.bagCanonical then return end
 if role=='pickup'then s.pickupObserved=true else s.returnObserved=true end
 s.transfers=s.transfers or{};s.transfers[#s.transfers+1]=row;return row
end
function F.dispose(s)
 local player=s.player
 for _,spec in pairs(s.ids.items)do local item=F.find(player,spec.id)or F.heavyCase(s.ids.case)and spec==s.ids.items.previous and assert(s.previousItem);assert(item)
  if F.beltCase(s.ids.case)then player:removeAttachedItem(item);if player:isEquippedClothing(item)then player:removeWornItem(item,false);if isServer()then sendClothing(player,item:getBodyLocation(),nil)end end end
  if player:getPrimaryHandItem()==item then player:setPrimaryHandItem(nil)end
  if player:getSecondaryHandItem()==item then player:setSecondaryHandItem(nil)end
  local world=item:getWorldItem()
  if world and world:getSquare()and world:getSquare():getWorldObjects():contains(world)then
   local square=world:getSquare();square:transmitRemoveItemFromSquare(world);world:removeFromWorld();world:removeFromSquare();item:setWorldItem(nil)
  end
  local owner=item:getContainer();if owner and owner:contains(item)then owner:Remove(item);if isServer()then sendRemoveItemFromContainer(owner,item)end end
 end
 local bag=F.find(player,s.ids.bag.id)or assert(s.bag);s.bag=bag;local slot=bag:canBeEquipped()
 local carried=player:getInventory():getItemById(bag:getID())==bag;player:setWornItem(slot,nil)
 if carried then player:getInventory():Remove(bag)end
 if isServer()then sendClothing(player,slot,nil);if carried then sendRemoveItemFromContainer(player:getInventory(),bag)end;sendEquip(player)end
end
function F.prepare(player,case,target,proof,previous)
 assert(not isClient()and P.atCentered(player,target),'authority must be at the prepared square')
 assert(not player:isFemale(),'native male character creation required for beard trimming')
 assert((F.beltCase(case)or F.heavyCase(case)or F.mandatoryCase(case)or({['restore-success']=true,['one-handed-axe']=true,['one-handed-axe-new-primary-intent']=true,['two-handed-axe']=true,['two-handed-axe-new-primary-intent']=true,['empty-primary']=true,['new-primary-intent']=true,['cancel-active']=true,['full-origin']=true,['unavailable-origin']=true,['keep-return']=true,['trim-scissors']=true,['cut-hair-scissors']=true})[case]),'unknown razor case')
 if previous then F.dispose(previous)end
 assert(not player:getPrimaryHandItem()and not player:getSecondaryHandItem(),'authority seed requires empty initial hands')
 local root=player:getInventory();local bag=assert(root:AddItem('Base.Bag_Military'));local source=bag:getItemContainer();source:setExplored(true)
 assert(not player:getWornItem(bag:canBeEquipped()),'authority bag slot occupied')
 local ids={case=case,placement=P.target(target),placementProof=proof,bag={id=bag:getID(),type=bag:getFullType()},items={},initialBeard='LongScruffy',targetBeard='Moustache'}
 local config=require 'QueueTestSelection'
 if config.options and config.options.razor_hand_ack_delay_ms~=nil then ids.handAckDelay=true end
 local cut=case=='cut-hair-scissors'
 if cut then ids.initialHair='Fabian';ids.targetHair='Bald' end
 local s={player=player,ids=ids,bag=bag}
 local types={razor=(F.beltCase(case)or case=='trim-scissors'or cut)and'Base.Scissors'or'Base.Razor',previous=F.heavyCase(case)and'Base.StoneAnvil'or F.mandatoryType(case)or F.axeCase(case)and'Base.Axe'or'Base.Hammer',replacement='Base.Screwdriver',tail='Base.BookCarpentry1'}
 if F.oneHandedCase(case)then types.secondary='Base.Pen'end
 if F.beltCase(case)then types.belt='Base.Belt2'end
 for name,kind in pairs(types)do
  local item=assert((name=='razor'and not F.beltCase(case)and source or root):AddItem(kind));item:setFavorite(true)
  if name=='previous'and F.mandatoryCase(case)then
   assert(item:isRequiresEquippedBothHands()and item:isForceDropHeavyItem()==false,'mandatory both-hands fixture requires safe carried native item')
  end
  ids.items[name]={id=item:getID(),type=kind}
 end
 if F.heavyCase(case)then ids.heavyActor=player:getOnlineID();s.previousItem=assert(F.find(player,ids.items.previous.id));s.seedPrevious=s.previousItem;assert(s.previousItem:isForceDropHeavyItem()and s.previousItem:isRequiresEquippedBothHands(),'heavy fixture must naturally force-drop')end
 local tail=F.find(player,ids.items.tail.id);local pages=tail:getNumberOfPages();assert(pages>2)
 ids.items.tail.total=pages;ids.items.tail.initial=pages-2
 tail:setAlreadyReadPages(pages-2);player:setAlreadyReadPages(tail:getFullType(),pages-2);player:setPerkLevelDebug(Perks.Woodwork,0)
 player:setWornItem(bag:canBeEquipped(),bag)
 if F.beltCase(case)then
  s.belt=assert(F.find(player,ids.items.belt.id));player:setWornItem(s.belt:getBodyLocation(),s.belt)
  local tool=assert(F.find(player,ids.items.razor.id));assert(tool:getAttachmentType()=='Screwdriver')
  -- The client discovers saved hotbar ordering before the authority configures this root item.
 end
 if case=='empty-primary'then player:setSecondaryHandItem(F.find(player,ids.items.previous.id))
 else player:setPrimaryHandItem(F.find(player,ids.items.previous.id))
  if F.equipmentCase(case)then player:setSecondaryHandItem(F.find(player,(ids.items.secondary or ids.items.previous).id))end
 end
 local visual=player:getHumanVisual();visual:setBeardModel(ids.initialBeard)
 if cut then
  -- Disposable fixture setup precedes the exact inventory/appearance baseline.
  local head=player:getClothingItem_Head()
  if head then
   local worn=player:getWornItems();local slot
   for i=0,worn:size()-1 do local row=worn:get(i);if row:getItem()==head then slot=row:getLocation();break end end
   assert(slot,'starter headwear location unavailable');player:removeWornItem(head,false);if isServer()then sendClothing(player,slot,nil)end
  end
  visual:setHairModel(ids.initialHair);visual:setNonAttachedHair(nil)
 end
 visual:setHairColor(cut and visual:getNaturalHairColor()or ImmutableColor.new(51/255,102/255,153/255,1));visual:setBeardColor(ImmutableColor.new(153/255,102/255,51/255,1));player:resetModel()
 if isServer()then
  sendAddItemToContainer(root,bag)
  for name,spec in pairs(ids.items)do if name~='razor'or F.beltCase(case)then sendAddItemToContainer(root,F.find(player,spec.id))end end
  if s.belt then sendClothing(player,s.belt:getBodyLocation(),s.belt)end
  sendClothing(player,bag:canBeEquipped(),bag);sendEquip(player);sendHumanVisual(player)
 end
 ids.baseline=F.snapshot(s);return s
end
function F.configureBelt(s,index)
 assert(not isClient()and F.beltCase(s.ids.case)and not s.ids.beltConfigured,'unexpected belt authority setup')
 assert(type(index)=='number'and index%1==0 and index>1 and index<100,'invalid actual native belt index')
 local player=s.player;local tool=assert(F.find(player,s.ids.items.razor.id));local root=player:getInventory()
 assert(tool:getContainer()==root and root:getItemById(tool:getID())==tool,'belt setup must retain exact root ownership')
 s.ids.beltIndex=index;s.ids.beltConfigured=true
 player:setAttachedItem('Belt Left Screwdriver',tool);tool:setAttachedSlot(index);tool:setAttachedSlotType('SmallBeltLeft');tool:setAttachedToModel('Belt Left Screwdriver')
 if isServer()then syncItemFields(player,tool);sendAttachedItem(player,'Belt Left Screwdriver',tool)end
 s.ids.baseline=F.snapshot(s);return s.ids
end
local resolved={}
function F.resolve(player,ids)
 if F.beltCase(ids.case)and not ids.beltConfigured then return end
 if not P.atCentered(player,ids.placement)then return end
 local bag=F.find(player,ids.bag.id);if not bag or bag:getContainer()~=player:getInventory()or bag:getFullType()~=ids.bag.type then return end
 for name,spec in pairs(ids.items)do local item=F.find(player,spec.id)
  if not item or item:getFullType()~=spec.type or item:getContainer()~=(name=='razor'and not F.beltCase(ids.case)and bag:getItemContainer()or player:getInventory())then return end
 end
 local s={player=player,ids=ids,bag=bag,previousItem=F.find(player,ids.items.previous.id)}
 if not resolved[ids]then
  -- Native book read checkpoints are actor-local baseline bookkeeping only.
  local tail=F.find(player,ids.items.tail.id);tail:setAlreadyReadPages(ids.items.tail.initial)
  player:setAlreadyReadPages(tail:getFullType(),ids.items.tail.initial);player:setPerkLevelDebug(Perks.Woodwork,0)
  if not F.same(F.snapshot(s),ids.baseline)then return end;resolved[ids]=true
 end
 return s
end
function F.expected(ids,authorityWire)
 local function clone(value)if type(value)~='table'then return value end;local copy={};for k,v in pairs(value)do copy[k]=clone(v)end;return copy end
 local row=clone(ids.baseline)
 if ids.case=='cut-hair-scissors'then row.appearance.hair=ids.targetHair;row.appearance.nonAttached=false
 else row.appearance.beard=F.cancelCase(ids.case)and ids.initialBeard or ids.targetBeard end
 if ids.case=='empty-primary'then row.primary=false
 else row.primary=ids.items[ids.handAckDelay and'razor'or F.intentCase(ids.case)and'replacement'or'previous'].id end
 if F.sharedHandCase(ids.case)and(F.intentCase(ids.case)or F.unavailableHeavy(ids.case))then row.secondary=false end
 if F.unavailableHeavy(ids.case)then row.primary=ids.items.razor.id end
 if F.heavyCase(ids.case)and ids.case~='heavy-stone-anvil'then
  row.heavy.state=F.unavailableHeavy(ids.case)and'unavailable'or'world';row.heavy.rootPresent=false;row.heavy.worldPresent=not F.unavailableHeavy(ids.case)
  for _,item in ipairs(row.items)do if item.id==ids.items.previous.id then item.container=row.heavy.state end end
 end
 row.tail.pages=ids.items.tail.total;row.tail.characterPages=ids.items.tail.total
 if F.beltCase(ids.case)then
  row.primary=ids.items.previous.id
  if ids.case=='belt-scissors-replace'then
   row.belt.tool.slot=-1
   -- Native Host SyncItemFields encodes nil strings as UTF length zero;
   -- the authority's exact received values are empty strings, SP/client nil.
   row.belt.tool.slotType=authorityWire and''or false;row.belt.tool.model=authorityWire and''or false
   row.belt.replacement.slot=ids.beltIndex;row.belt.replacement.slotType='SmallBeltLeft';row.belt.replacement.model='Belt Left Screwdriver';row.belt.occupant=ids.items.replacement.id
  end
 elseif ids.handAckDelay or not F.returnedCase(ids.case)then
  row.origin.sourceCount=0
  for _,item in ipairs(row.items)do if item.id==ids.items.razor.id then item.container='root'end end
 end
 if ids.case=='unavailable-origin'then
  row.origin.container='unavailable';row.origin.worn=false
  for _,item in ipairs(row.items)do if item.id==ids.bag.id then item.container='unavailable'end end
  for i=#row.worn,1,-1 do if row.worn[i].id==ids.bag.id then table.remove(row.worn,i)end end
 end
 return row
end
-- Called only by the authority after genuine trim progress was observed client-side.
function F.changeOrigin(s,requestedAt)
 assert(not isClient()and not s.originChanged,'origin intervention requires fresh authority')
 local player,bag=s.player,s.bag;local root=player:getInventory();local razor=assert(F.find(player,s.ids.items.razor.id))
 assert(razor:getContainer()==root and player:getPrimaryHandItem()==razor and player:getHumanVisual():getBeardModel()==s.ids.initialBeard,'origin intervention missed active borrowed razor')
 local source=bag:getItemContainer();local room=source:hasRoomFor(player,razor)
 local receipt={case=s.ids.case,kind=s.ids.case=='unavailable-origin'and'unavailable'or'full',authority=true,requestedAt=requestedAt,at=getTimestampMs(),
  bagId=bag:getID(),itemId=razor:getID(),itemType=razor:getFullType(),capacityBefore=source:getCapacity(),roomBefore=room,
  before=F.snapshot(s)}
 assert(room and bag:getContainer()==root and player:getWornItems():contains(bag),'origin was not initially available')
 if receipt.kind=='full'then source:setCapacity(0)
 else
  player:removeWornItem(bag,false);root:Remove(bag)
  if isServer()then sendClothing(player,bag:canBeEquipped(),nil);sendRemoveItemFromContainer(root,bag)end
 end
 receipt.capacityAfter=source:getCapacity();receipt.roomAfter=source:hasRoomFor(player,razor);receipt.after=F.snapshot(s)
 assert(receipt.kind=='full'and receipt.capacityAfter==0 and not receipt.roomAfter or receipt.kind=='unavailable'and receipt.after.origin.container=='unavailable'and not receipt.after.origin.worn,'origin intervention had no physical effect')
 s.originChanged=receipt;return receipt
end
function F.verify(s)
 local row=F.snapshot(s);if F.same(row,F.expected(s.ids,isServer()))then row.authority=not isClient();return row end
end
return F
