-- Authority-only seed. After admission, all fixture helpers only observe.
local F={}
local P=require 'QueueEnergyPlacement'
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
 local function scan(container,parent)
  local values=container:getItems()
  for i=0,values:size()-1 do local item=values:get(i)
   items[#items+1]={id=item:getID(),type=item:getFullType(),container=parent,condition=item:getCondition(),
    favorite=item:isFavorite(),count=item:getCount(),canonical=item:getContainer()==container and F.find(player,item:getID())==item}
   if instanceof(item,'InventoryContainer')then scan(item:getItemContainer(),item:getID())end
  end
 end
 scan(root,'root');table.sort(items,function(a,b)return a.id<b.id end)
 local values=player:getWornItems()
 for i=0,values:size()-1 do local row=values:get(i);worn[#worn+1]={id=row:getItem():getID(),location=tostring(row:getLocation())}end
 table.sort(worn,function(a,b)return a.location<b.location end)
 local visual=player:getHumanVisual();local hc,bc=visual:getHairColor(),visual:getBeardColor()
 local tail=assert(F.find(player,s.ids.items.tail.id))
 return{case=s.ids.case,male=not player:isFemale(),items=items,worn=worn,
  primary=id(player:getPrimaryHandItem()),secondary=id(player:getSecondaryHandItem()),
  appearance={beard=visual:getBeardModel()or'',hair=visual:getHairModel()or'',nonAttached=visual:getNonAttachedHair()or false,
   hairColor={r=hc:getRedFloat(),g=hc:getGreenFloat(),b=hc:getBlueFloat()},beardColor={r=bc:getRedFloat(),g=bc:getGreenFloat(),b=bc:getBlueFloat()}},
  tail={id=tail:getID(),type=tail:getFullType(),pages=tail:getAlreadyReadPages(),total=tail:getNumberOfPages(),characterPages=player:getAlreadyReadPages(tail:getFullType())}}
end
function F.transferSnapshot(s,role)
 local root=s.player:getInventory();local bag=assert(F.find(s.player,s.ids.bag.id));local source=bag:getItemContainer()
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
 if role=='returned'and s.ids.case~='restore-success'then return end
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
 local bag=assert(F.find(player,s.ids.bag.id));local slot=bag:canBeEquipped()
 player:setWornItem(slot,nil);player:getInventory():Remove(bag)
 if isServer()then sendClothing(player,slot,nil);sendRemoveItemFromContainer(player:getInventory(),bag);sendEquip(player)end
end
function F.prepare(player,case,target,proof,previous)
 assert(not isClient()and not player:isFemale()and P.atCentered(player,target),'male authority at exact centered placement required')
 assert(case=='restore-success'or case=='new-primary-intent','unknown razor case')
 if previous then F.dispose(previous)end
 assert(not player:getPrimaryHandItem()and not player:getSecondaryHandItem(),'authority seed requires empty initial hands')
 local root=player:getInventory();local bag=assert(root:AddItem('Base.Bag_Military'));local source=bag:getItemContainer();source:setExplored(true)
 assert(not player:getWornItem(bag:canBeEquipped()),'authority bag slot occupied')
 local ids={case=case,placement=P.target(target),placementProof=proof,bag={id=bag:getID(),type=bag:getFullType()},items={},initialBeard='LongScruffy',targetBeard='Moustache'}
 local s={player=player,ids=ids}
 for name,kind in pairs({razor='Base.Razor',previous='Base.Hammer',replacement='Base.Screwdriver',tail='Base.BookCarpentry1'})do
  local item=assert((name=='razor'and source or root):AddItem(kind));item:setFavorite(true)
  ids.items[name]={id=item:getID(),type=kind}
 end
 local tail=F.find(player,ids.items.tail.id);local pages=tail:getNumberOfPages();assert(pages>2)
 ids.items.tail.total=pages;ids.items.tail.initial=pages-2
 tail:setAlreadyReadPages(pages-2);player:setAlreadyReadPages(tail:getFullType(),pages-2);player:setPerkLevelDebug(Perks.Woodwork,0)
 player:setWornItem(bag:canBeEquipped(),bag);player:setPrimaryHandItem(F.find(player,ids.items.previous.id))
 local visual=player:getHumanVisual();visual:setBeardModel(ids.initialBeard)
 visual:setHairColor(ImmutableColor.new(51/255,102/255,153/255,1));visual:setBeardColor(ImmutableColor.new(153/255,102/255,51/255,1));player:resetModel()
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
 local s={player=player,ids=ids}
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
 local row=clone(ids.baseline);row.appearance.beard=ids.targetBeard
 row.primary=ids.items[ids.case=='restore-success'and'previous'or'replacement'].id
 row.tail.pages=ids.items.tail.total;row.tail.characterPages=ids.items.tail.total
 if ids.case=='new-primary-intent'then for _,item in ipairs(row.items)do if item.id==ids.items.razor.id then item.container='root'end end end
 return row
end
function F.verify(s)
 local row=F.snapshot(s);if F.same(row,F.expected(s.ids))then row.authority=not isClient();return row end
end
return F
