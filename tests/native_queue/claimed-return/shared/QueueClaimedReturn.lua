-- Disposable carried storage and independent authority checks. No action callback
-- is invoked here; fixture preparation precedes all native work.
local F={}
local P=require 'QueueEnergyPlacement'
local function id(item)return item and item:getID()or false end
local function count(container,wanted)
 local total=0;local items=container:getItems()
 for i=0,items:size()-1 do local item=items:get(i)
  if item:getID()==wanted then total=total+1 end
 end
 return total
end
function F.snapshot(s)
 local root=s.player:getInventory();local rows={}
 for name,spec in pairs(s.ids.items)do
  local item=root:getItemById(spec.id)or s.source:getItemById(spec.id)
  assert(item and item:getFullType()==spec.type,'owned claimed-return item missing')
  rows[name]={id=spec.id,type=spec.type,root=count(root,spec.id),source=count(s.source,spec.id),
   pages=item:getAlreadyReadPages(),total=item:getNumberOfPages()}
  assert(rows[name].root+rows[name].source==1,'claimed-return identity lost or duplicated')
 end
 return{case=s.ids.case,items=rows,primary=id(s.player:getPrimaryHandItem()),secondary=id(s.player:getSecondaryHandItem()),
  bag={id=s.bag:getID(),type=s.bag:getFullType(),canonicalRoot=root:getItemById(s.ids.bag.id)==s.bag and s.bag:getContainer()==root,
   worn=s.player:getWornItems():contains(s.bag),sourceSame=s.bag:getItemContainer()==s.source}}
end
function F.dispose(s)
 local root=s.player:getInventory()
 for _,spec in pairs(s.ids.items)do local item=root:getItemById(spec.id)or s.source:getItemById(spec.id)
  assert(item,'owned item disappeared before disposal')
  if s.player:getPrimaryHandItem()==item then s.player:setPrimaryHandItem(nil)end
  if s.player:getSecondaryHandItem()==item then s.player:setSecondaryHandItem(nil)end
  local owner=item:getContainer();owner:Remove(item)
  if isServer()then sendRemoveItemFromContainer(owner,item)end
 end
 local slot=s.bag:canBeEquipped();s.player:setWornItem(slot,nil);root:Remove(s.bag)
 if isServer()then sendClothing(s.player,slot,nil);sendRemoveItemFromContainer(root,s.bag);sendEquip(s.player)end
end
function F.prepare(player,case,placement,proof,previous)
 assert(not isClient()and P.atCentered(player,placement),'claimed-return authority placement differs')
 assert(case=='claimed-success'or case=='claimed-failure'or case=='claimed-cancel'or case=='claimed-cancel-success','unknown claimed-return case')
 if previous then F.dispose(previous)end
 local bag=assert(player:getInventory():AddItem('Base.Bag_Military'))
 assert(not player:getWornItem(bag:canBeEquipped()),'fixture bag slot occupied')
 local source=bag:getItemContainer();source:setExplored(true)
 local ids={case=case,placement=P.target(placement),placementProof=proof,bag={id=bag:getID(),type=bag:getFullType()},items={}}
 local s={player=player,ids=ids,source=source,bag=bag,items={}}
 for name,type in pairs({borrowed='Base.BookCarpentry1',previous='Base.BookCooking1',tail='Base.BookFarming1'})do
  local item=assert((name=='borrowed'and source or player:getInventory()):AddItem(type))
  local pages=item:getNumberOfPages();assert(pages>4)
  item:setAlreadyReadPages(pages-4);player:setAlreadyReadPages(type,pages-4)
  s.items[name]=item;ids.items[name]={id=item:getID(),type=type,pages=pages,initial=pages-4}
 end
 assert(not player:getPrimaryHandItem()and not player:getSecondaryHandItem(),'fixture requires empty initial hands')
 -- The client establishes worn storage and hands with actual native actions.
 if isServer()then
  sendAddItemToContainer(player:getInventory(),bag)
  for _,name in ipairs({'previous','tail'})do sendAddItemToContainer(player:getInventory(),s.items[name])end
 end
 return s
end
function F.resolve(player,ids)
 if not P.atCentered(player,ids.placement)then return end
 local root=player:getInventory();local bag=root:getItemById(ids.bag.id)
 if not bag or bag:getContainer()~=root or bag:getFullType()~=ids.bag.type then return end
 local s={player=player,ids=ids,bag=bag,source=bag:getItemContainer(),items={}}
 for name,spec in pairs(ids.items)do local owner=name=='borrowed'and s.source or player:getInventory();local item=owner:getItemById(spec.id)
  if not item or item:getContainer()~=owner or item:getFullType()~=spec.type then return end;s.items[name]=item
  item:setAlreadyReadPages(spec.initial);player:setAlreadyReadPages(spec.type,spec.initial)
 end
 return s
end
function F.verify(s)
 local row=F.snapshot(s);local success=s.ids.case=='claimed-success'or s.ids.case=='claimed-cancel-success'
 local book=row.items.borrowed
 if book.root~=(success and 0 or 1)or book.source~=(success and 1 or 0)
  or row.items.previous.root~=1 or row.items.tail.root~=1
  or row.primary~=(success and s.ids.items.previous.id or s.ids.items.borrowed.id)
  or row.items.tail.pages~=row.items.tail.total or not row.bag.canonicalRoot or not row.bag.worn or not row.bag.sourceSame then return end
 if s.ids.case=='claimed-cancel'or s.ids.case=='claimed-cancel-success'then
  if book.pages>=book.total then return end
 elseif book.pages~=book.total then return end
 row.authority=not isClient();return row
end
return F
