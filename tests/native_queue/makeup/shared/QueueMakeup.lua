-- Disposable authority setup; checkpoints after baseline only read native state.
require 'Definitions/MakeUpDefinitions'
local F={sp={'preview-close','preview-location','apply-empty','apply-replace'},
 mp={'preview-close','preview-location','apply-empty','apply-replace','cancel-waiting','apply-while-preview'}}
local slots={ItemBodyLocation.MAKE_UP_FULL_FACE,ItemBodyLocation.MAKE_UP_EYES,ItemBodyLocation.MAKE_UP_EYES_SHADOW,ItemBodyLocation.MAKE_UP_LIPS}
function F.same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not F.same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
F.moves={'move-earlier','move-later','move-promote','move-deny-writer'}
F.carriedMoves={'move-worn-earlier','move-nested-later','move-nested-promote','move-nested-deny-writer'}
F.worldMoves={'move-world-container-earlier','move-world-bag-later','move-world-container-promote','move-world-bag-deny-walk'}
local moveSpecs={
 ['move-earlier']={kind='earlier'},['move-later']={kind='later'},['move-promote']={kind='promote'},['move-deny-writer']={kind='deny-writer'},
 ['move-worn-earlier']={kind='earlier',supply='worn-bag'},['move-nested-later']={kind='later',supply='nested-bag'},
 ['move-nested-promote']={kind='promote',supply='nested-bag'},['move-nested-deny-writer']={kind='deny-writer',supply='nested-bag'},
 ['move-world-container-earlier']={kind='earlier',supply='world-container'},['move-world-bag-later']={kind='later',supply='world-bag'},
 ['move-world-container-promote']={kind='promote',supply='world-container'},['move-world-bag-deny-walk']={kind='deny-walk',supply='world-bag'}}
function F.moveCase(case)return moveSpecs[case]~=nil end
function F.moveKind(case)return moveSpecs[case]and moveSpecs[case].kind end
function F.moveSupply(case)return moveSpecs[case]and moveSpecs[case].supply end
function F.placed(case)return F.supplyCase(case)or F.moveCase(case)end
F.supplySP={'apply-worn-bag','apply-nested-bag','apply-world-container','apply-world-bag'}
F.supplyMP={'apply-worn-bag','apply-nested-bag','apply-world-container','apply-world-bag','cancel-nested-bag','cancel-world-container'}
function F.cancel(case)return case=='cancel-waiting'or case:sub(1,7)=='cancel-'end
function F.applies(case)return case:sub(1,6)=='apply-'or F.cancel(case)end
function F.supplyCase(case)
 for _,value in ipairs(F.supplyMP)do if case==value then return true end end;return false
end
function F.placement(player)
 local square=player:getCurrentSquare()
 return {tile={x=math.floor(player:getX()),y=math.floor(player:getY()),z=math.floor(player:getZ())},
  square=square and {x=square:getX(),y=square:getY(),z=square:getZ()}or false}
end
function F.validPlacement(tile)
 if type(tile)~='table'then return false end
 local count=0;for key,value in pairs(tile)do
  if (key~='x'and key~='y'and key~='z')or type(value)~='number'or value~=math.floor(value)then return false end;count=count+1
 end;return count==3
end
function F.atPlacement(player,tile)
 if not F.validPlacement(tile)then return false end
 local actual=F.placement(player);return F.same(actual.tile,tile)and F.same(actual.square,tile)
end
local function members(container)
 local out={};local items=container:getItems()
 for i=0,items:size()-1 do local item=items:get(i);out[#out+1]={id=item:getID(),kind=item:getFullType()}end
 table.sort(out,function(a,b)return a.id<b.id end);return out
end
local function direct(container,id)
 local found
 for i=0,container:getItems():size()-1 do local item=container:getItems():get(i)
  if item:getID()==id then assert(not found,'duplicate supply member identity');found=item end
 end;return found
end
local function worldSource(spec)
 local square=getCell():getGridSquare(spec.x,spec.y,spec.z);if not square then return end
 if spec.kind=='world-bag'then
  if spec.index<0 or spec.index>=square:getWorldObjects():size()then return end
  local obj=square:getWorldObjects():get(spec.index);local bag=obj:getItem()
  if not bag or bag:getID()~=spec.id or bag:getFullType()~=spec.type or bag:getWorldItem()~=obj
   or obj:getSquare()~=square or bag:getModData().MakeupSupplyOwner~=spec.owner then return end
  return bag:getItemContainer(),obj,bag
 end
 if spec.index<0 or spec.index>=square:getObjects():size()then return end
 local obj=square:getObjects():get(spec.index)
 if not instanceof(obj,'IsoThumpable')or obj:getSquare()~=square or not obj:getSprite()
  or obj:getSprite():getName()~=spec.sprite or obj:getModData().MakeupSupplyOwner~=spec.owner then return end
 local c=obj:getContainerByIndex(spec.containerIndex)
 if not c or c:getParent()~=obj or c:getSourceGrid()~=square or c:getType()~=spec.type then return end
 return c,obj
end
function F.supplyState(player,spec)
 local container=player:getInventory();local rows={};local world,access
 if spec.world then
  local obj,bag;container,obj,bag=worldSource(spec.world);if not container then return end
  access={blocked=assert(player:getCurrentSquare()):isBlockedTo(obj:getSquare())}
  world={kind=spec.world.kind,x=obj:getSquare():getX(),y=obj:getSquare():getY(),z=obj:getSquare():getZ(),
   index=spec.world.kind=='world-bag'and obj:getSquare():getWorldObjects():indexOf(obj)or obj:getObjectIndex(),
   owner=(bag or obj):getModData().MakeupSupplyOwner,type=bag and bag:getFullType()or container:getType()}
  if bag then world.id=bag:getID()else world.sprite=obj:getSprite():getName();world.containerIndex=obj:getContainerIndex(container)end
 end
 for _,expected in ipairs(spec.ancestors)do
  local bag=direct(container,expected.id)
  if not bag or not instanceof(bag,'InventoryContainer')or bag:getFullType()~=expected.kind or bag:getContainer()~=container then return end
  container=bag:getItemContainer()
  rows[#rows+1]={id=bag:getID(),kind=bag:getFullType(),parent=expected.parent,items=members(container)}
 end
 -- World roots also publish their direct contents, independently on both roles.
 local source={kind=spec.kind,world=world or false,ancestors=rows,items=members(container),access=access or false}
 return container,source
end
function F.kit(s)
 local source
 if s.ids.supply then source=F.supplyState(s.player,s.ids.supply)else source=s.player:getInventory()end
 return source and direct(source,s.ids.items.kit),source
end
local function adjacent(player)
 local origin=assert(player:getCurrentSquare())
 for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}})do
  local square=getCell():getGridSquare(origin:getX()+d[1],origin:getY()+d[2],origin:getZ())
  if square and square:canStand()and square:isFree(false)and not origin:isBlockedTo(square)then return square end
 end;error('no free adjacent makeup supply tile')
end
-- A free native two-step route; execution uses normal pathfinding in both
-- directions. The actor's published supply checkpoints stay on the origin.
function F.walkRoute(player,world)
 local origin=assert(player:getCurrentSquare());local x,y,z=origin:getX(),origin:getY(),origin:getZ()
 for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}})do
  local via=getCell():getGridSquare(x+d[1],y+d[2],z)
  local out=getCell():getGridSquare(x+2*d[1],y+2*d[2],z)
  if via and out and via:canStand()and out:canStand()and via:isFree(false)and out:isFree(false)
   and not origin:isBlockedTo(via)and not via:isBlockedTo(out)
   and math.max(math.abs(out:getX()-world.x),math.abs(out:getY()-world.y))>1 then
   return {origin={x=x,y=y,z=z},via={x=via:getX(),y=via:getY(),z=z},out={x=out:getX(),y=out:getY(),z=z},source=world}
  end
 end;error('no free native two-step makeup walk route away from world source')
end
local function backpackSlot(bag)
 local slot=ItemBodyLocation.BACK
 assert(slot and bag:canBeEquipped()==slot,'native schoolbag Back equipment slot changed')
 return slot
end
local function supply(player,case)
 local kind=assert(case:match('^[^-]+%-(.+)$'));local spec={kind=kind,world=false,ancestors={}};local root=player:getInventory();local c=root;local object,worldBag
 if kind=='world-container'then
  local square=adjacent(player);object=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
  object:setBlockAllTheSquare(true);object:setIsContainer(true);c=assert(object:getContainer());c:setType('crate');c:setCapacity(100);c:setExplored(true)
  square:AddSpecialObject(object);object:getModData().MakeupSupplyOwner=case..':'..tostring(getTimestampMs())
  spec.world={kind=kind,x=square:getX(),y=square:getY(),z=square:getZ(),index=object:getObjectIndex(),
   containerIndex=object:getContainerIndex(c),sprite='carpentry_01_16',type=c:getType(),owner=object:getModData().MakeupSupplyOwner}
 elseif kind=='world-bag'then
  worldBag=assert(instanceItem('Base.Bag_Schoolbag'));c=worldBag:getItemContainer();c:setExplored(true)
  worldBag:getModData().MakeupSupplyOwner=case..':'..tostring(getTimestampMs())
 elseif kind=='worn-bag'or kind=='nested-bag'then
  local bag=assert(root:AddItem('Base.Bag_Schoolbag'));c=bag:getItemContainer();c:setExplored(true)
  spec.ancestors[1]={id=bag:getID(),kind=bag:getFullType(),parent='root'}
  player:setWornItem(backpackSlot(bag),bag)
  if kind=='nested-bag'then c:AddItem('Base.Pencil');local inner=assert(c:AddItem('Base.Bag_Schoolbag'));c=inner:getItemContainer();c:setExplored(true)
   spec.ancestors[2]={id=inner:getID(),kind=inner:getFullType(),parent=bag:getID()}end
 else error('unknown makeup supply topology '..tostring(kind))end
 return c,spec,object,worldBag
end
local function cleanupSupply(player,ids)
 if not ids or not ids.supply then return end
 local spec=ids.supply
 assert(F.supplyState(player,spec),'previous exact supply source disappeared')
 if spec.world then
  local _,object,bag=worldSource(spec.world);local square=assert(object:getSquare());square:transmitRemoveItemFromSquare(object)
  if bag then square:removeWorldObject(object);bag:setWorldItem(nil)end
 else
  local bag=assert(direct(player:getInventory(),spec.ancestors[1].id));player:removeWornItem(bag,false)
  if isServer()then sendRemoveItemFromContainer(player:getInventory(),bag);sendClothing(player,backpackSlot(bag),nil)end
  player:getInventory():Remove(bag)
 end
end
function F.definition(kind)
 for _,v in ipairs(MakeUpDefinitions.makeup)do if v.item==kind then return v end end
 error('native makeup definition missing '..tostring(kind))
end
function F.snapshot(s)
 local p,root=s.player,s.player:getInventory();local items,worn={},{}
 local values=root:getItems()
 for i=0,values:size()-1 do local item=values:get(i);items[#items+1]={id=item:getID(),kind=item:getFullType()}end
 table.sort(items,function(a,b)return a.id<b.id end)
 values=p:getWornItems()
 for i=0,values:size()-1 do
  local v=values:get(i);local item=v:getItem();local found=root:getItemById(item:getID())
  worn[#worn+1]={id=item:getID(),kind=item:getFullType(),slot=tostring(v:getLocation()),root=found~=nil,
   sameReference=found==item,container=item:getContainer()==root and'root'or false}
 end
 table.sort(worn,function(a,b)return a.slot<b.slot end)
 local kit,source=F.kit(s);assert(kit,'exact native makeup kit disappeared')
 assert(kit:getFullType()==s.ids.types.kit and kit:getContainer()==source,'makeup kit identity/topology changed')
 local supplyState
 if s.ids.supply then local ignored;ignored,supplyState=F.supplyState(p,s.ids.supply);assert(ignored==source,'supply identity changed')end
 local value= {case=s.ids.case,actor=p:getOnlineID(),root=items,worn=worn,
  kit={id=kit:getID(),kind=kit:getFullType(),uses=kit:getCurrentUses(),maxUses=kit:getMaxUses(),root=source==root},
  frontPages=p:getAlreadyReadPages(s.ids.types.front),tailPages=p:getAlreadyReadPages(s.ids.types.tail)}
 if supplyState then value.supply=supplyState end
 if s.ids.move then value.middlePages=p:getAlreadyReadPages(s.ids.types.middle)end
 if supplyState or s.ids.move then value.placement=F.placement(p)end;return value
end
function F.resolve(player,ids)
 if isClient()and player:getOnlineID()~=ids.actor then return end
 if (ids.supply or ids.move)and not F.atPlacement(player,ids.placement)then return end
 local root=player:getInventory()
 for name,wanted in pairs(ids.items)do
  local item,source
  if name=='kit'and ids.supply then item,source=F.kit({player=player,ids=ids})else item,source=root:getItemById(wanted),root end
  if not item or item:getFullType()~=ids.types[name]or item:getContainer()~=source then return end
 end
 local s={player=player,ids=ids}
 for _,name in ipairs(ids.move and {'front','middle','tail'}or {'front','tail'})do
  local item=root:getItemById(ids.items[name]);item:setAlreadyReadPages(ids[name..'Initial'])
  player:setAlreadyReadPages(item:getFullType(),ids[name..'Initial'])
 end
 player:setPerkLevelDebug(Perks.Woodwork,0);player:setPerkLevelDebug(Perks.Doctor,0)
 if ids.move then player:setPerkLevelDebug(Perks.Cooking,0)end
 local actual=F.snapshot(s);local expected=ids.baseline
 if not F.same(actual.root,expected.root)or not F.same(actual.kit,expected.kit)or #actual.worn~=#expected.worn or not F.same(actual.supply,expected.supply)then return end
 for i,row in ipairs(actual.worn)do
  local before=expected.worn[i]
  if row.id~=before.id or row.kind~=before.kind or row.slot~=before.slot or row.root~=before.root then return end
 end
 if ids.move then
  for _,row in ipairs(actual.worn)do for _,slot in ipairs(slots)do
   if row.slot==tostring(slot)and(not row.root or not row.sameReference or row.container~='root')then return end
  end end
 end
 return s
end
function F.prepare(player,case,previous,placement)
 assert(not isClient(),'makeup setup requires authority')
 if F.placed(case)then assert(F.atPlacement(player,placement),'makeup supply actor has not settled on exact placement tile')end
 local root=player:getInventory();cleanupSupply(player,previous)
 for _,slot in ipairs(slots)do local item=player:getWornItem(slot);if item then player:removeWornItem(item,false)end end
 local remove={}
 for i=0,root:getItems():size()-1 do
  local item=root:getItems():get(i)
  local owned=previous and (item:getID()==previous.items.kit or item:getID()==previous.items.front or item:getID()==previous.items.tail or item:getID()==previous.items.middle or item:getID()==previous.items.writer)
  for _,slot in ipairs(slots)do if item:getBodyLocation()==slot then owned=true end end
  if owned then remove[#remove+1]=item end
 end
 for _,item in ipairs(remove)do
  if previous and item:getID()==previous.items.writer then player:removeWornItem(item,false);if isServer()then sendClothing(player,item:getBodyLocation(),nil)end end
  if isServer()then sendRemoveItemFromContainer(root,item)end;root:Remove(item)
 end
 player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
 if not F.placed(case)then require('QueueEnergyPlacement')(player)end
 assert(not player:isTimedActionInstant()and not getDebug(),'ordinary non-debug makeup timing required')
 local ids={case=case,actor=player:getOnlineID(),items={},types={},target='Base.MakeUp_Crow',alternate='Base.MakeUp_RedStripes2',
  different='Base.MakeUp_EyesShadowWhite',oldType='Base.MakeUp_RedStripes1',slot=tostring(ItemBodyLocation.MAKE_UP_EYES),
  otherSlot=tostring(ItemBodyLocation.MAKE_UP_EYES_SHADOW),producer='ISMakeUpUI.onApplyMakeUp',duration=1}
 if F.moveCase(case)then ids.move=true;ids.placement={x=placement.x,y=placement.y,z=placement.z}end
 local function seed(name,kind,destination)
  local item=assert((destination or root):AddItem(kind),'native fixture item absent '..kind);ids.items[name]=item:getID();ids.types[name]=kind;return item
 end
 -- Native Eyes supports both Eyes and EyesShadow; no fabricated All kit.
 local source,object,worldBag=root,nil,nil
 if F.supplyCase(case)or F.moveSupply(case)then
  ids.placement={x=placement.x,y=placement.y,z=placement.z}
  source,ids.supply,object,worldBag=supply(player,F.moveSupply(case)and'apply-'..F.moveSupply(case)or case)
 end
 local kit=seed('kit','Base.MakeupEyeshadow',source)
 if ids.supply then assert(source:AddItem('Base.Pencil'),'native source sentinel missing')end
 assert(kit:getMakeUpType()=='Eyes'and kit:getMaxUses()==5,'native Eyes supply definition changed')
 kit:setCurrentUses(kit:getMaxUses());ids.kitUses=kit:getCurrentUses();ids.kitType=kit:getMakeUpType()
 for _,kind in ipairs({ids.target,ids.alternate,ids.different,ids.oldType})do
  local def=F.definition(kind);local script=assert(getScriptManager():FindItem(kind))
  assert(def.makeuptypes[ids.kitType]and script:getLuaCreate()==nil and script:getItemConfig()==nil,'unreviewed native cosmetic producer')
 end
 assert(getScriptManager():FindItem(ids.target):getBodyLocation()==ItemBodyLocation.MAKE_UP_EYES
  and getScriptManager():FindItem(ids.alternate):getBodyLocation()==ItemBodyLocation.MAKE_UP_EYES
  and getScriptManager():FindItem(ids.oldType):getBodyLocation()==ItemBodyLocation.MAKE_UP_EYES
  and getScriptManager():FindItem(ids.different):getBodyLocation()==ItemBodyLocation.MAKE_UP_EYES_SHADOW,'native cosmetic slots changed')
 for _,name in ipairs(ids.move and {'front','middle','tail'}or {'front','tail'})do
  local book=seed(name,name=='front'and'Base.BookCarpentry1'or name=='middle'and'Base.BookCooking1'or'Base.BookFirstAid1')
  ids[name..'Total']=book:getNumberOfPages();ids[name..'Initial']=ids[name..'Total']-(name=='front'and(ids.move and not F.moveSupply(case)and 8 or 3)or 1)
  book:setAlreadyReadPages(ids[name..'Initial']);player:setAlreadyReadPages(book:getFullType(),ids[name..'Initial'])
 end
 if F.moveKind(case)=='deny-writer'then seed('writer','Base.Socks_Ankle')end
 if case~='apply-empty'and not ids.move then local old=seed('old',ids.oldType);player:setWornItem(ItemBodyLocation.MAKE_UP_EYES,old)end
 -- Native root packet acknowledgement precedes authoritative wearing. This
 -- avoids manufacturing a same-ID unattached clothing proxy on the client.
 if case=='move-earlier'then seed('old',ids.oldType);ids.wearPending=true end
 player:setPerkLevelDebug(Perks.Woodwork,0);player:setPerkLevelDebug(Perks.Doctor,0)
 if ids.move then player:setPerkLevelDebug(Perks.Cooking,0)end
 if worldBag then
  local square=adjacent(player);square:AddWorldInventoryItem(worldBag,.5,.5,0,true);local world=assert(worldBag:getWorldItem())
  ids.supply.world={kind='world-bag',x=square:getX(),y=square:getY(),z=square:getZ(),index=square:getWorldObjects():indexOf(world),
   id=worldBag:getID(),type=worldBag:getFullType(),owner=worldBag:getModData().MakeupSupplyOwner}
 end
 if F.moveKind(case)=='deny-walk'then ids.walk=F.walkRoute(player,assert(ids.supply.world))end
 if isServer()then
  if object then object:transmitCompleteItemToClients();object:transmitModData()end
  if ids.supply and not ids.supply.world then
   local bag=assert(direct(root,ids.supply.ancestors[1].id));sendAddItemToContainer(root,bag);sendClothing(player,backpackSlot(bag),bag)
  end
  for name,wanted in pairs(ids.items)do if name~='kit'or source==root then sendAddItemToContainer(root,assert(root:getItemById(wanted)))end end
  for _,slot in ipairs(slots)do sendClothing(player,slot,player:getWornItem(slot))end
 end
 local s={player=player,ids=ids};ids.baseline=F.snapshot(s);return s
end
function F.wearPrepared(s)
 assert(isServer()and s.ids.wearPending and s.ids.case=='move-earlier','unexpected prepared makeup wear')
 local old=assert(direct(s.player:getInventory(),s.ids.items.old));assert(old:getContainer()==s.player:getInventory())
 s.player:setWornItem(ItemBodyLocation.MAKE_UP_EYES,old)
 assert(s.player:getWornItem(ItemBodyLocation.MAKE_UP_EYES)==old,'authority did not wear exact root cosmetic')
 sendClothing(s.player,ItemBodyLocation.MAKE_UP_EYES,old)
 s.ids.wearPending=nil;s.ids.baseline=F.snapshot(s)
end
function F.output(snapshot,ids)
 local initial={};for _,row in ipairs(ids.baseline.root)do initial[row.id]=true end
 local output
 for _,row in ipairs(snapshot.root)do
  if not initial[row.id]then assert(not output and row.kind==ids.target,'foreign/duplicate output');output=row.id end
 end
 return output or false
end
return F
