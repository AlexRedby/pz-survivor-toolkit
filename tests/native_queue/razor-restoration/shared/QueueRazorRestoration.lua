-- Authority-only seeds/interventions; native queue work is never synthesized.
local F={}
local P=require 'QueueEnergyPlacement'
function F.returnedCase(case)return case=='restore-success'or case=='empty-primary'or case=='cancel-active'or case=='trim-scissors'or case=='cut-hair-scissors'end
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
 table.sort(items,function(a,b)return a.id<b.id end)
 local values=player:getWornItems()
 for i=0,values:size()-1 do local row=values:get(i);worn[#worn+1]={id=row:getItem():getID(),location=tostring(row:getLocation())}end
 table.sort(worn,function(a,b)return a.location<b.location end)
 local visual=player:getHumanVisual();local hc,bc=visual:getHairColor(),visual:getBeardColor()
 local tail=assert(F.find(player,s.ids.items.tail.id))
 return{case=s.ids.case,male=not player:isFemale(),items=items,worn=worn,
  primary=id(player:getPrimaryHandItem()),secondary=id(player:getSecondaryHandItem()),
  origin={id=bag:getID(),type=bag:getFullType(),container=detached and'unavailable'or'root',worn=player:getWornItems():contains(bag),sourceCount=bag:getItemContainer():getItems():size()},
  appearance={beard=visual:getBeardModel()or'',hair=visual:getHairModel()or'',nonAttached=visual:getNonAttachedHair()or false,
   hairColor={r=hc:getRedFloat(),g=hc:getGreenFloat(),b=hc:getBlueFloat()},beardColor={r=bc:getRedFloat(),g=bc:getGreenFloat(),b=bc:getBlueFloat()}},
  tail={id=tail:getID(),type=tail:getFullType(),pages=tail:getAlreadyReadPages(),total=tail:getNumberOfPages(),characterPages=player:getAlreadyReadPages(tail:getFullType())}}
end
function F.transferSnapshot(s,role)
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
 if not s or s.returnObserved then return end
 local role=s.pickupObserved and'returned'or'pickup'
 if role=='returned'and(s.ids.handAckDelay or not F.returnedCase(s.ids.case))then return end
 local row=F.transferSnapshot(s,role)
 if row.sourceCount~=0 or row.destinationCount~=1 or not row.canonical or not row.bagCanonical then return end
 if role=='pickup'then s.pickupObserved=true else s.returnObserved=true end
 s.transfers=s.transfers or{};s.transfers[#s.transfers+1]=row;return row
end
function F.dispose(s)
 local player=s.player
 for _,spec in pairs(s.ids.items)do local item=assert(F.find(player,spec.id))
  if player:getPrimaryHandItem()==item then player:setPrimaryHandItem(nil)end
  if player:getSecondaryHandItem()==item then player:setSecondaryHandItem(nil)end
  local owner=item:getContainer();owner:Remove(item);if isServer()then sendRemoveItemFromContainer(owner,item)end
 end
 local bag=F.find(player,s.ids.bag.id)or assert(s.bag);s.bag=bag;local slot=bag:canBeEquipped()
 local carried=player:getInventory():getItemById(bag:getID())==bag;player:setWornItem(slot,nil)
 if carried then player:getInventory():Remove(bag)end
 if isServer()then sendClothing(player,slot,nil);if carried then sendRemoveItemFromContainer(player:getInventory(),bag)end;sendEquip(player)end
end
function F.prepare(player,case,target,proof,previous)
 assert(not isClient()and P.atCentered(player,target),'authority must be at the prepared square')
 assert(not player:isFemale(),'native male character creation required for beard trimming')
 assert(({['restore-success']=true,['empty-primary']=true,['new-primary-intent']=true,['cancel-active']=true,['full-origin']=true,['unavailable-origin']=true,['keep-return']=true,['trim-scissors']=true,['cut-hair-scissors']=true})[case],'unknown razor case')
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
 for name,kind in pairs({razor=(case=='trim-scissors'or cut)and'Base.Scissors'or'Base.Razor',previous='Base.Hammer',replacement='Base.Screwdriver',tail='Base.BookCarpentry1'})do
  local item=assert((name=='razor'and source or root):AddItem(kind));item:setFavorite(true)
  ids.items[name]={id=item:getID(),type=kind}
 end
 local tail=F.find(player,ids.items.tail.id);local pages=tail:getNumberOfPages();assert(pages>2)
 ids.items.tail.total=pages;ids.items.tail.initial=pages-2
 tail:setAlreadyReadPages(pages-2);player:setAlreadyReadPages(tail:getFullType(),pages-2);player:setPerkLevelDebug(Perks.Woodwork,0)
 player:setWornItem(bag:canBeEquipped(),bag)
 if case=='empty-primary'then player:setSecondaryHandItem(F.find(player,ids.items.previous.id))
 else player:setPrimaryHandItem(F.find(player,ids.items.previous.id))end
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
  for name,spec in pairs(ids.items)do if name~='razor'then sendAddItemToContainer(root,F.find(player,spec.id))end end
  sendClothing(player,bag:canBeEquipped(),bag);sendEquip(player);sendHumanVisual(player)
 end
 ids.baseline=F.snapshot(s);return s
end
local resolved={}
function F.resolve(player,ids)
 if not P.atCentered(player,ids.placement)then return end
 local bag=F.find(player,ids.bag.id);if not bag or bag:getContainer()~=player:getInventory()or bag:getFullType()~=ids.bag.type then return end
 for name,spec in pairs(ids.items)do local item=F.find(player,spec.id)
  if not item or item:getFullType()~=spec.type or item:getContainer()~=(name=='razor'and bag:getItemContainer()or player:getInventory())then return end
 end
 local s={player=player,ids=ids,bag=bag}
 if not resolved[ids]then
  -- Native book read checkpoints are actor-local baseline bookkeeping only.
  local tail=F.find(player,ids.items.tail.id);tail:setAlreadyReadPages(ids.items.tail.initial)
  player:setAlreadyReadPages(tail:getFullType(),ids.items.tail.initial);player:setPerkLevelDebug(Perks.Woodwork,0)
  if not F.same(F.snapshot(s),ids.baseline)then return end;resolved[ids]=true
 end
 return s
end
function F.expected(ids)
 local function clone(value)if type(value)~='table'then return value end;local copy={};for k,v in pairs(value)do copy[k]=clone(v)end;return copy end
 local row=clone(ids.baseline)
 if ids.case=='cut-hair-scissors'then row.appearance.hair=ids.targetHair;row.appearance.nonAttached=false
 else row.appearance.beard=ids.case=='cancel-active'and ids.initialBeard or ids.targetBeard end
 if ids.case=='empty-primary'then row.primary=false
 else row.primary=ids.items[ids.handAckDelay and'razor'or ids.case=='new-primary-intent'and'replacement'or'previous'].id end
 row.tail.pages=ids.items.tail.total;row.tail.characterPages=ids.items.tail.total
 if ids.handAckDelay or not F.returnedCase(ids.case)then
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
 local row=F.snapshot(s);if F.same(row,F.expected(s.ids))then row.authority=not isClient();return row end
end
return F
