-- Only the authority seeds/removes equipment and appearance. After admission all
-- helpers observe; resolve waits for exact replicas without repairing equipment.
local F={}
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
function F.appearance(player)
 local v=player:getHumanVisual();local h,b=v:getHairColor(),v:getBeardColor()
 return {model=v:getHairModel()or'',nonAttached=v:getNonAttachedHair()or false,beardModel=v:getBeardModel()or'',
  color={r=h:getRedFloat(),g=h:getGreenFloat(),b=h:getBlueFloat()},
  beardColor={r=b:getRedFloat(),g=b:getGreenFloat(),b=b:getBlueFloat()}}
end
function F.snapshot(state)
 local p,root=state.player,state.player:getInventory();local rows,worn,hands={},{},{}
 local function scan(container,parent)
  local items=container:getItems()
  for i=0,items:size()-1 do local item=items:get(i)
   rows[#rows+1]={id=item:getID(),type=item:getFullType(),container=parent,condition=item:getCondition(),favorite=item:isFavorite(),count=item:getCount()}
   if instanceof(item,'InventoryContainer')then scan(item:getItemContainer(),item:getID())end
  end
 end
 scan(root,'root');table.sort(rows,function(a,b)return a.id<b.id end)
 local values=p:getWornItems()
 for i=0,values:size()-1 do local row=values:get(i);worn[#worn+1]={id=row:getItem():getID(),location=tostring(row:getLocation())}end
 table.sort(worn,function(a,b)return a.location<b.location end)
 for _,slot in ipairs({'primary','secondary'})do
  local item;if slot=='primary'then item=p:getPrimaryHandItem()else item=p:getSecondaryHandItem()end
  hands[slot]=item and{id=item:getID(),type=item:getFullType(),root=root:getItemById(item:getID())==item,
   sameReference=F.find(p,item:getID())==item,equipParent=item:getEquipParent()==p,container=item:getContainer()==root and'root'or false}or false
 end
 local result={case=state.ids.case,male=not p:isFemale(),items=rows,worn=worn,hands=hands,appearance=F.appearance(p),books={}}
 for _,name in ipairs({'front','tail'})do local spec=state.ids[name];local item=F.find(p,spec.id)
  result.books[name]={id=spec.id,type=item and item:getFullType()or'',root=item and item:getContainer()==root or false,
   total=item and item:getNumberOfPages()or -1,pages=item and item:getAlreadyReadPages()or -1,characterPages=p:getAlreadyReadPages(spec.type)}
 end
 return result
end
function F.prepare(player,case,mode,previous)
 assert(not isClient()and not player:isFemale(),'authority native male actor required')
 if previous then for _,name in ipairs({'razor','front','tail'})do
  local item=F.find(player,previous[name].id)
  if item then
   if player:getPrimaryHandItem()==item then player:setPrimaryHandItem(nil)end
   if player:getSecondaryHandItem()==item then player:setSecondaryHandItem(nil)end
   local container=item:getContainer();container:Remove(item);if isServer()then sendRemoveItemFromContainer(container,item)end
  end
 end end
 require('QueueEnergyPlacement')(player);player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
 local root=player:getInventory();local razor=assert(root:AddItem('Base.Razor'));razor:setFavorite(true)
 player:setPrimaryHandItem(razor);player:setSecondaryHandItem(nil)
 local v=player:getHumanVisual();v:setBeardModel('LongScruffy')
 -- Exact fixed points of HumanVisual's native byte transport.
 v:setHairColor(ImmutableColor.new(51/255,102/255,153/255,1));v:setBeardColor(ImmutableColor.new(153/255,102/255,51/255,1));player:resetModel()
 local ids={case=case,mode=mode,actor=player:getOnlineID(),razor={id=razor:getID(),type='Base.Razor'},initialBeard='LongScruffy',targetBeard='Moustache',duration=300}
 local initial=assert(getBeardStylesInstance():FindStyle(ids.initialBeard));local target=assert(getBeardStylesInstance():FindStyle(ids.targetBeard))
 assert(target:getLevel()<initial:getLevel(),'native menu beard transition unavailable')
 for _,name in ipairs({'front','tail'})do
  local kind=name=='front'and'Base.BookCarpentry1'or'Base.BookCooking1';local item=assert(root:AddItem(kind));local total=item:getNumberOfPages()
  local pages=total-(name=='front'and 3 or 1);assert(pages>0);item:setAlreadyReadPages(pages);player:setAlreadyReadPages(kind,pages)
  ids[name]={id=item:getID(),type=kind,total=total,initial=pages}
 end
 player:setPerkLevelDebug(Perks.Woodwork,0);player:setPerkLevelDebug(Perks.Cooking,0)
 if isServer()then
  for _,name in ipairs({'razor','front','tail'})do sendAddItemToContainer(root,assert(F.find(player,ids[name].id)))end
  sendEquip(player);sendHumanVisual(player)
 end
 local state={player=player,ids=ids};ids.baseline=F.snapshot(state);return state
end
local resolved={}
function F.resolve(player,ids)
 if isClient()and player:getOnlineID()~=ids.actor then return end
 for _,name in ipairs({'razor','front','tail'})do
  local item=F.find(player,ids[name].id)
  if not item or item:getFullType()~=ids[name].type or item:getContainer()~=player:getInventory()then return end
 end
 local state={player=player,ids=ids}
 if not resolved[ids]then
  -- Character read checkpoints are actor-local bookkeeping before baseline;
  -- hands, worn items and visuals must have arrived unchanged from authority.
  local actual=F.snapshot(state)
  for _,key in ipairs({'items','worn','hands','appearance','male'})do if not F.same(actual[key],ids.baseline[key])then return end end
  for _,name in ipairs({'front','tail'})do
   local item=F.find(player,ids[name].id);item:setAlreadyReadPages(ids[name].initial);player:setAlreadyReadPages(ids[name].type,ids[name].initial)
  end
  player:setPerkLevelDebug(Perks.Woodwork,0);player:setPerkLevelDebug(Perks.Cooking,0);resolved[ids]=true
 end
 if F.same(F.snapshot(state),ids.baseline)then return state end
end
function F.removeRazor(state)
 assert(not isClient(),'tool revocation requires authority')
 local p=state.player;local root=p:getInventory();local item=assert(F.find(p,state.ids.razor.id))
 assert(item:getContainer()==root and p:getPrimaryHandItem()==item and not p:getSecondaryHandItem(),'exact held razor changed before authority revocation')
 p:setPrimaryHandItem(nil);root:Remove(item)
 if isServer()then sendRemoveItemFromContainer(root,item);sendEquip(p)end
 return F.snapshot(state)
end
function F.expected(state)
 local function clone(t)if type(t)~='table'then return t end;local r={};for k,v in pairs(t)do r[k]=clone(v)end;return r end
 local v=clone(state.ids.baseline)
 if state.ids.case=='lost-tool'then
  for i=#v.items,1,-1 do if v.items[i].id==state.ids.razor.id then table.remove(v.items,i)end end
  v.hands.primary=false
 elseif state.ids.mode=='toolkit'then
  if state.ids.case=='pending-restore'then v.appearance.beardModel=state.ids.targetBeard;v.books.front.pages=state.ids.front.total;v.books.front.characterPages=state.ids.front.total end
  v.books.tail.pages=state.ids.tail.total;v.books.tail.characterPages=state.ids.tail.total
 end
 return v
end
function F.verify(state)
 local actual=F.snapshot(state);if F.same(actual,F.expected(state))then return actual end;return nil,actual
end
return F
