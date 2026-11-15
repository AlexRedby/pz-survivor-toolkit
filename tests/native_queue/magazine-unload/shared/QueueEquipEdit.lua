local P=require 'QueueEnergyPlacement'
local Common=require 'QueueMagazineUnload'
local F={segments={'reorder-two','reorder-three','cancel','dependent','capacity','component-guard'}}
F.preparedSegments={'prepared-move','prepared-cancel-fetch','prepared-cancel-body','prepared-dependent'}
function F.selectedSegments(prepared)
 local values={};for _,name in ipairs(F.segments)do values[#values+1]=name end
 if prepared then for _,name in ipairs(F.preparedSegments)do values[#values+1]=name end end
 return values
end
function F.isPrepared(segment)return type(segment)=='string'and segment:sub(1,9)=='prepared-'end
local function cancelled(ids)return ids.mode=='toolkit'and(ids.segment=='prepared-cancel-fetch'or ids.segment=='prepared-cancel-body')end
F.equal=Common.equal
F.hands=Common.hands
local function inventory(player)
 local rows,seen={},{}
 local function scan(container,path)
  local items=container:getItems()
  for i=0,items:size()-1 do
   local item=items:get(i);local id=item:getID();assert(not seen[id],'duplicate equip fixture inventory ID');seen[id]=true
   assert(item:getContainer()==container,'equip fixture inventory owner differs')
   rows[#rows+1]={id=id,type=item:getFullType(),class=getClassSimpleName(item),path=path,condition=item:getCondition(),count=item:getCount(),uses=item:getCurrentUses()}
   if instanceof(item,'InventoryContainer')then
    local child={};for _,value in ipairs(path)do child[#child+1]=value end;child[#child+1]=id
    scan(item:getItemContainer(),child)
   end
  end
 end
 scan(player:getInventory(),{});table.sort(rows,function(a,b)return a.id<b.id end);return rows
end
function F.snapshot(state)
 local p,ids=state.player,state.ids;local root=p:getInventory();local books={}
 for _,name in ipairs({'front','tail'})do local spec=ids.items[name];local item=root:getItemById(spec.id)
  books[name]={id=spec.id,present=item~=nil,root=item and item:getContainer()==root or false,pages=item and item:getAlreadyReadPages()or -1,
   characterPages=p:getAlreadyReadPages(spec.type),total=spec.pages}
 end
 local bag=root:getItemById(ids.items.bag.id)
 return{case='equip-edit',segment=ids.segment,hands=F.hands(p),inventory=inventory(p),books=books,
  backpack=bag and p:getWornItem(bag:canBeEquipped())==bag or false}
end
local function expectedHands(ids)
 local edited=ids.mode=='toolkit'
 local item=ids.items;local p,s=false,false
 if ids.segment=='reorder-two'then p=edited and item.a.id or item.b.id
 elseif ids.segment=='reorder-three'then p=item.b.id;s=edited and item.a.id or item.c.id
 elseif ids.segment=='cancel'then p=edited and item.a.id or item.c.id;s=item.b.id
 -- P4 returns only the fetched item to its recorded source. The native
 -- return transfer clears that item from hands; it does not clear another
 -- held object. No restore-hands policy is armed by these low-level actions.
 elseif ids.segment=='dependent'then p=false;s=false
 elseif ids.segment=='capacity'then p=item.heldBag.id;s=false
 elseif ids.segment=='component-guard'then p=item.b.id end
 if F.isPrepared(ids.segment)then
  p=cancelled(ids)and item.b.id or item.nested.id
  if ids.segment=='prepared-move'then s=item.b.id end
 end
 return{primary=p,secondary=s}
end
function F.verify(state)
 local value=F.snapshot(state);local expected=expectedHands(state.ids)
 if not F.equal(value.hands,expected)or not value.backpack then return end
 for _,name in ipairs({'front','tail'})do local row=value.books[name]
  if not row.present or not row.root or row.pages~=row.total or row.characterPages~=row.total then return end
 end
 local baseline={};for _,row in ipairs(state.ids.inventory)do baseline[row.id]=row end
 for _,row in ipairs(value.inventory)do local prior=baseline[row.id];if not prior then return end
  for key,v in pairs(prior)do
   if key=='path'and F.isPrepared(state.ids.segment)and not cancelled(state.ids)and row.id==state.ids.items.nested.id then v={}end
   if not F.equal(row[key],v)then return end
  end
  baseline[row.id]=nil
 end
 for _ in pairs(baseline)do return end
 return value
end
function F.prepare(player,segment,mode,kind,placement,proof,previous,workload)
 assert(P.atCentered(player,placement),'equip fixture placement differs')
 if previous then F.dispose(previous)end
 local root=player:getInventory();assert(not player:getPrimaryHandItem()and not player:getSecondaryHandItem(),'equip fixture needs empty native hands')
 local ids={case='equip-edit',segment=segment,mode=mode,kind=kind,origin=placement,placementProof=proof,items={}}
 local state={player=player,ids=ids,items={}}
 local owned={}
 local function seed(name,fullType,container)
  local item=assert((container or root):AddItem(fullType));state.items[name]=item;owned[#owned+1]=item
  ids.items[name]={id=item:getID(),type=fullType,class=getClassSimpleName(item)};return item
 end
 local front=seed('front','Base.BookCarpentry1');local tail=seed('tail','Base.BookFirstAid1')
 for _,book in ipairs({front,tail})do
  assert(book:getNumberOfPages()>1);book:setAlreadyReadPages(book:getNumberOfPages()-1);player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 end
 ids.items.front.pages=front:getNumberOfPages();ids.items.tail.pages=tail:getNumberOfPages()
 if workload and segment=='reorder-two'then
  local initial=front:getNumberOfPages()-2;front:setAlreadyReadPages(initial);player:setAlreadyReadPages(front:getFullType(),initial)
  ids.items.front.initialPages=initial
 end
 for _,perk in ipairs({Perks.Woodwork,Perks.Doctor})do player:setPerkLevelDebug(perk,0)end
 seed('a',segment=='component-guard'and'Base.Hammer'or'Base.Nails');seed('b','Base.Screwdriver');seed('c','Base.Screwdriver')
 local bag=seed('bag','Base.Bag_Schoolbag');local slot=bag:canBeEquipped();assert(slot and not player:getWornItem(slot),'test backpack slot must be empty')
 player:setWornItem(slot,bag);bag:getItemContainer():setExplored(true)
 seed('marker','Base.Nails',bag:getItemContainer())
 if segment=='dependent'or F.isPrepared(segment)then seed('nested','Base.Pencil',bag:getItemContainer())
 elseif segment=='capacity'then
  local held=seed('heldBag','Base.Bag_Schoolbag');held:getItemContainer():setExplored(true)
  seed('nested','Base.Plank',held:getItemContainer())
 end
 ids.inventory=inventory(player);state.input=F.snapshot(state)
 if isServer()then
  -- A root bag packet already contains its children. Publish complete roots
  -- before worn IDs so the client binds the canonical inventory object.
  for _,item in ipairs(owned)do if item:getContainer()==root then sendAddItemToContainer(root,item)end end
  sendClothing(player,slot,bag)
 end
 return state
end
function F.resolve(player,ids)
 if not P.atCentered(player,ids.origin)then return end
 local state={player=player,ids=ids,items={}};local root=player:getInventory()
 local function find(container,id)
  local items=container:getItems();for i=0,items:size()-1 do local item=items:get(i)
   if item:getID()==id then return item end
   if instanceof(item,'InventoryContainer')then local found=find(item:getItemContainer(),id);if found then return found end end
  end
 end
 for name,spec in pairs(ids.items)do local item=find(root,spec.id);if not item or item:getFullType()~=spec.type or getClassSimpleName(item)~=spec.class then return end;state.items[name]=item end
 if player:getPrimaryHandItem()or player:getSecondaryHandItem()then return end
 for _,perk in ipairs({Perks.Woodwork,Perks.Doctor})do player:setPerkLevelDebug(perk,0)end
 -- Read progress belongs to the fresh authority seed and is mirrored for the client reader's native constructor.
 for _,name in ipairs({'front','tail'})do local item=state.items[name];local initial=ids.items[name].initialPages or ids.items[name].pages-1
  if item:getAlreadyReadPages()~=initial then return end
  player:setAlreadyReadPages(item:getFullType(),initial)
 end
 if not F.equal(inventory(player),ids.inventory)or not F.snapshot(state).backpack then return end
 state.input=F.snapshot(state);return state
end
function F.dispose(state)
 assert(F.verify(state),'equip cleanup requires verified authority effects')
 local p,root=state.player,state.player:getInventory();p:setPrimaryHandItem(nil);p:setSecondaryHandItem(nil)
 if isServer()then sendEquip(p)end
 local bag=assert(root:getItemById(state.ids.items.bag.id));local slot=bag:canBeEquipped();assert(p:getWornItem(slot)==bag)
 p:removeWornItem(bag,false);if isServer()then sendClothing(p,slot,nil)end
 -- Remove only exact seeded objects, nested children before their owned bags.
 for _,name in ipairs({'nested','marker','front','tail','a','b','c','heldBag','bag'})do
  local spec=state.ids.items[name];if spec then
   local function locate(container)
    local items=container:getItems();for i=0,items:size()-1 do local item=items:get(i)
     if item:getID()==spec.id then return item end
     if instanceof(item,'InventoryContainer')then local found=locate(item:getItemContainer());if found then return found end end
    end
   end
   local item=assert(locate(root),'equip cleanup exact item missing');local container=item:getContainer()
   container:Remove(item);if isServer()then sendRemoveItemFromContainer(container,item)end
  end
 end
end
return F
