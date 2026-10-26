local F={}
function F.isCase(c)return c=='cook-sandwich-plain-joined'or c=='cook-sandwich-enriched-joined'end
local function array(a)local r={};if a then for i=0,a:size()-1 do r[#r+1]=a:get(i)end end;return r end
local function strings(a)local r=array(a);table.sort(r);return r end
local function items(c,out)out=out or {};for _,v in ipairs(array(c:getItems()))do out[#out+1]=v;if instanceof(v,'InventoryContainer')then items(v:getItemContainer(),out)end end;return out end
local function count(c,id)local n=0;for _,v in ipairs(items(c))do if v:getID()==id then n=n+1 end end;return n end
function F.snapshot(v)
 if not v then return end
 local r={id=v:getID(),kind=v:getFullType(),uses=v:getCurrentUses(),weight=v:getActualWeight()}
 if instanceof(v,'Food')then
  r.hunger=v:getHungChange();r.effectiveHunger=v:getHungerChange();r.baseHunger=v:getBaseHunger();r.calories=v:getCalories();r.carbohydrates=v:getCarbohydrates();r.proteins=v:getProteins();r.lipids=v:getLipids()
  r.cooked=v:isCooked();r.burnt=v:isBurnt();r.frozen=v:isFrozen();r.extras=strings(v:getExtraItems());r.spices=strings(v:getSpices())
 end;return r
end
function F.resolveSource(s)
 if not s then return end
 local sq=getCell():getGridSquare(s.x,s.y,s.z)
 if not sq or s.objectIndex<0 or s.objectIndex>=sq:getObjects():size()then return end
 local obj=sq:getObjects():get(s.objectIndex)
 if not obj or obj:getSquare()~=sq or not obj:getSprite()or obj:getSprite():getName()~=s.sprite or obj:getModData().CookSandwichOwner~=s.ownerToken then return end
 local c=obj:getContainerByIndex(s.containerIndex)
 if not c or c:getParent()~=obj or c:getSourceGrid()~=sq or c:getType()~=s.containerType then return end
 if s.containerType=='crate'and not instanceof(obj,'IsoThumpable')then return end
 if s.containerType=='stove'and(not instanceof(obj,'IsoStove')or obj:isMicrowave())then return end
 return c,obj
end
local function adjacent(p,excluded)
 local origin=assert(p:getSquare())
 for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}})do
  local sq=getCell():getGridSquare(origin:getX()+d[1],origin:getY()+d[2],origin:getZ())
  if sq and sq~=excluded and sq:canStand()and sq:isFree(false)and not origin:isBlockedTo(sq) then return sq end
 end;error('no free adjacent native kitchen tile')
end
local function source(p,case,oven,excluded)
 local sq=adjacent(p,excluded);local sprite=oven and 'appliances_cooking_01_0'or 'carpentry_01_16';local obj,c
 if oven then
  local sp=assert(getSprite(sprite),'native oven sprite missing');obj=IsoStove.new(getCell(),sq,sp);obj:createContainersFromSpriteProperties()
  c=assert(obj:getContainerByType('stove'));assert(not obj:isMicrowave()and not obj:Activated(),'native oven must begin inactive');sq:AddTileObject(obj)
 else
  obj=IsoThumpable.new(getCell(),sq,sprite,false,{});obj:setBlockAllTheSquare(true);obj:setIsContainer(true)
  c=assert(obj:getContainer());c:setType('crate');c:setCapacity(100);sq:AddSpecialObject(obj)
 end
 c:setExplored(true);local token=case..':'..p:getUsername()..':'..getTimestampMs()..':'..c:getType();obj:getModData().CookSandwichOwner=token
 local spec={x=sq:getX(),y=sq:getY(),z=sq:getZ(),objectIndex=obj:getObjectIndex(),containerIndex=obj:getContainerIndex(c),sprite=sprite,containerType=c:getType(),ownerToken=token}
 assert(F.resolveSource(spec)==c,'native source publication differs')
 return c,obj,spec
end
local function generatorSnapshot(obj)
 local sq=assert(obj:getSquare())
 return {x=sq:getX(),y=sq:getY(),z=sq:getZ(),objectIndex=obj:getObjectIndex(),ownerToken=obj:getModData().CookSandwichOwner,
  condition=obj:getCondition(),fuel=obj:getFuel(),active=obj:isActivated()}
end
local function resolveGenerator(spec)
 if not spec then return end
 local sq=getCell():getGridSquare(spec.x,spec.y,spec.z)
 if not sq or spec.objectIndex<0 or spec.objectIndex>=sq:getObjects():size()then return end
 local obj=sq:getObjects():get(spec.objectIndex)
 if not obj or not instanceof(obj,'IsoGenerator')or obj:getSquare()~=sq
  or obj:getModData().CookSandwichOwner~=spec.ownerToken then return end
 return obj
end
local function generator(p,case,ovenContainer)
 local origin=assert(p:getSquare());local square
 -- Search a bounded loaded outdoor ring; this source needs no actor movement.
 for radius=2,4 do
  for dx=-radius,radius do for dy=-radius,radius do
   if not square and math.max(math.abs(dx),math.abs(dy))==radius then
    local sq=getCell():getGridSquare(origin:getX()+dx,origin:getY()+dy,origin:getZ())
    if sq and sq:isOutside()and not sq:getRoom()and sq:canStand()and sq:isFree(false)
     and sq:getObjects():size()<=1 and sq:getSpecialObjects():size()==0 then square=sq end
   end
  end end
  if square then break end
 end
 assert(square,'no free loaded outdoor generator tile within four squares')
 -- The native constructor publishes the real world object on the server.
 local obj=IsoGenerator.new(assert(instanceItem('Base.Generator')),getCell(),square)
 obj:getModData().CookSandwichOwner=case..':'..p:getUsername()..':'..getTimestampMs()..':generator'
 obj:setCondition(100);obj:setFuel(10.0);obj:setActivated(true)
 local spec=generatorSnapshot(obj)
 assert(resolveGenerator(spec)==obj and obj:isActivated()and obj:getFuel()>0,'owned native generator did not start')
 assert(ovenContainer:getSourceGrid():haveElectricity()and ovenContainer:isPowered(),'native generator did not power the prepared oven')
 return obj,spec
end
local function all(s)local out=items(s.root);items(s.sourceContainer,out);if s.ovenContainer then items(s.ovenContainer,out)end;return out end
local function exact(s,id)local found,n=nil,0;for _,v in ipairs(all(s))do if v:getID()==id then found=v;n=n+1 end end;assert(n<=1,'duplicate cooking ID '..id);return found,n end
local function outputs(s,kind)local r={};for _,v in ipairs(items(s.root))do if v:getFullType()==kind and not s.baselineSet[v:getID()]then r[#r+1]=F.snapshot(v)end end;table.sort(r,function(a,b)return a.id<b.id end);return r end
local function resource(s,m)
 local v,n=exact(s,m.id);local r=F.snapshot(v)or {id=m.id,kind=m.kind,missing=true}
 r.sourceCount=count(s.sourceContainer,m.id);r.rootCount=count(s.root,m.id);r.ovenCount=s.ovenContainer and count(s.ovenContainer,m.id)or 0;r.totalCount=n;return r
end
local function recipeUses(s,name,metas)
 local recipe=assert(getScriptManager():getEvolvedRecipe('Base.'..name),'native evolved recipe missing: '..name)
 local out={}
 for _,m in ipairs(metas)do
  local item=assert(s.sourceContainer:getItemById(m.id));local entry=recipe:getItemRecipe(item)
  out[m.kind]=entry and entry:getUse()or false
 end;return out
end
function F.prepare(p,case)
 assert(F.isCase(case));local root=p:getInventory()
 local s={player=p,root=root,case=case,bags={},breadInputs={},sandwichInputs={},baselineOutputIds={},baselineSet={},checkpoints={},cookingLevel=p:getPerkLevel(Perks.Cooking)}
 for _,v in ipairs(items(root))do s.baselineOutputIds[#s.baselineOutputIds+1]=v:getID();s.baselineSet[v:getID()]=true end
 if case=='cook-sandwich-enriched-joined'then
  s.ovenContainer,s.ovenObject,s.oven=source(p,case,true)
  s.generatorObject,s.generator=generator(p,case,s.ovenContainer)
 end
 s.sourceContainer,s.sourceObject,s.source=source(p,case,false,s.ovenObject and s.ovenObject:getSquare())
 local base=assert(root:AddItem(s.oven and 'Base.BreadDough'or 'Base.BreadSlices'));s.base=F.snapshot(base)
 assert(instanceof(base,'Food')and not base:isCooked()and not base:isBurnt()and not base:isFrozen(),'ordinary bread seed differs')
 for _,kind in ipairs(s.oven and {'Base.Cheese','Base.ChocolateChips'}or {})do s.breadInputs[#s.breadInputs+1]=F.snapshot(assert(s.sourceContainer:AddItem(kind)))end
 for _,kind in ipairs({'Base.Cabbage','Base.Tomato'})do s.sandwichInputs[#s.sandwichInputs+1]=F.snapshot(assert(s.sourceContainer:AddItem(kind)))end
 s.nativeRecipeUses={Sandwich=recipeUses(s,'Sandwich',s.sandwichInputs)}
 if s.oven then s.nativeRecipeUses.Bread=recipeUses(s,'Bread',s.breadInputs)end
 local knife=assert(root:AddItem('Base.KitchenKnife'));s.knife={id=knife:getID(),kind=knife:getFullType(),condition=knife:getCondition()}
 local book=assert(root:AddItem('Base.BookCarpentry1'));s.book=book:getID();book:setAlreadyReadPages(book:getNumberOfPages()-1);p:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 if isServer()then
  sendAddItemToContainer(root,base);sendAddItemToContainer(root,knife);sendAddItemToContainer(root,book)
  s.sourceObject:transmitCompleteItemToClients();s.sourceObject:transmitModData()
  if s.ovenObject then s.ovenObject:transmitCompleteItemToClients();s.ovenObject:transmitModData()end
  if s.generatorObject then s.generatorObject:transmitModData()end
 end;return s
end
function F.descriptor(s)return {case=s.case,actorId=s.player:getOnlineID(),cookingLevel=s.cookingLevel,bags={},book=s.book,base=s.base,knife=s.knife,source=s.source,oven=s.oven,generator=s.generator,breadInputs=s.breadInputs,sandwichInputs=s.sandwichInputs,baselineOutputIds=s.baselineOutputIds,nativeRecipeUses=s.nativeRecipeUses}end
function F.resolve(p,ids)
 local sourceContainer,sourceObject=F.resolveSource(ids.source);if not sourceContainer then return end
 local ovenContainer,ovenObject,generatorObject
 if ids.oven then
  ovenContainer,ovenObject=F.resolveSource(ids.oven);generatorObject=resolveGenerator(ids.generator)
  if not ovenContainer or not generatorObject or not generatorObject:isActivated()or generatorObject:getFuel()<=0
   or generatorObject:getCondition()<=0 or not ovenObject:getSquare():haveElectricity()or not ovenContainer:isPowered()then return end
 end
 local root=p:getInventory();local base=root:getItemById(ids.base.id);local knife=root:getItemById(ids.knife.id);local book=root:getItemById(ids.book)
 if not base or base:getFullType()~=ids.base.kind or base:getContainer()~=root or not knife or not book then return end
 for _,set in ipairs({ids.breadInputs,ids.sandwichInputs})do for _,m in ipairs(set)do local v=sourceContainer:getItemById(m.id)
  if not v or v:getFullType()~=m.kind or v:getContainer()~=sourceContainer or count(sourceContainer,m.id)~=1 or math.abs(v:getHungChange()-m.hunger)>0.00001 then return end
 end end
 local inv=getPlayerInventory(p:getPlayerNum());local loot=getPlayerLoot(p:getPlayerNum());if not inv or not loot then return end
 inv:refreshBackpacks();loot:refreshBackpacks();local containers=ISInventoryPaneContextMenu.getContainers(p);local seen={}
 for i=0,containers:size()-1 do seen[containers:get(i)]=true end
 if not seen[sourceContainer]or ovenContainer and not seen[ovenContainer]then return end
 return {root=root,base=base,knife=knife,book=book,sourceContainer=sourceContainer,sourceObject=sourceObject,ovenContainer=ovenContainer,ovenObject=ovenObject,generatorObject=generatorObject,containers=containers}
end
function F.observerSnapshot(p,ids,stage)
 local c=F.resolveSource(ids.source);if not c then return end
 if stage=='before'then
  local expected=0
  for _,set in ipairs({ids.breadInputs,ids.sandwichInputs})do for _,m in ipairs(set)do
   expected=expected+1;local item=c:getItemById(m.id)
   if not item or item:getFullType()~=m.kind or item:getContainer()~=c or count(c,m.id)~=1
    or math.abs(item:getHungChange()-m.hunger)>.00001 or math.abs(item:getCalories()-m.calories)>.0001 then return end
  end end
  if c:getItems():size()~=expected then return end
 end
 local r={case=ids.case,source=ids.source,items={}}
 for _,v in ipairs(items(c))do if instanceof(v,'Food')then r.items[#r.items+1]=F.snapshot(v)end end
 table.sort(r.items,function(a,b)return a.id<b.id end);return r
end
function F.checkpoint(s,stage,args)
 assert(stage=='BreadAdded'or stage=='Baked'or stage=='Sliced','unknown sandwich checkpoint')
 local r={case=s.case,stage=stage,breadInputs={},sandwichInputs={},slices=outputs(s,'Base.BreadSlices')};local bread=exact(s,s.base.id);r.bread=F.snapshot(bread)
 if s.ovenObject then
  local obj=assert(resolveGenerator(s.generator),'owned native generator disappeared')
  assert(obj==s.generatorObject and obj:isActivated()and obj:getFuel()>0 and obj:getCondition()>0
   and s.ovenObject:getSquare():haveElectricity()and s.ovenContainer:isPowered(),'owned native generator stopped powering the oven')
  r.oven={active=s.ovenObject:Activated(),temperature=s.ovenObject:getCurrentTemperature(),maximum=s.ovenObject:getMaxTemperature(),powered=s.ovenContainer:isPowered(),generator=generatorSnapshot(obj)}
 end
 for _,m in ipairs(s.breadInputs)do r.breadInputs[#r.breadInputs+1]=resource(s,m)end
 for _,m in ipairs(s.sandwichInputs)do r.sandwichInputs[#r.sandwichInputs+1]=resource(s,m)end
 if stage=='BreadAdded'then assert(bread and not bread:isCooked()and bread:getExtraItems()and bread:getExtraItems():size()==2,'native enriched bread not ready')
 elseif stage=='Baked'then assert(bread and bread:isCooked()and not bread:isBurnt(),'native bread not baked')
 else assert(not bread and #r.slices==3,'native slicing not complete')end
 s.checkpoints[stage]=r;return r
end
local function same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
function F.cleanup(s)
 assert(s.verified==true and s.frozenReceipt and s.frozenReceipt.sourceSnapshot,'unverified joined kitchen cleanup')
 local c,obj=F.resolveSource(s.source)
 assert(c==s.sourceContainer and obj==s.sourceObject,'owned joined kitchen identity changed')
 local permitted={};for _,set in ipairs({s.breadInputs,s.sandwichInputs})do for _,meta in ipairs(set)do permitted[meta.id]=meta.kind end end
 for _,v in ipairs(items(c))do assert(permitted[v:getID()]==v:getFullType(),'joined kitchen contains foreign resources')end
 assert(same(F.observerSnapshot(s.player,F.descriptor(s)),s.frozenReceipt.sourceSnapshot),'verified crate resource snapshot changed')
 local sq=obj:getSquare();sq:transmitRemoveItemFromSquare(obj)
 if obj:getObjectIndex()>=0 then obj:removeFromWorld();obj:removeFromSquare()end
 assert(obj:getObjectIndex()<0,'owned joined kitchen was not removed')
end
function F.verify(s)
 local r={case=s.case,actorId=s.player:getOnlineID(),cookingLevel=s.player:getPerkLevel(Perks.Cooking),nativeRecipeUses=s.nativeRecipeUses,source=s.source,base=resource(s,s.base),breadInputs={},sandwichInputs={},sandwiches=outputs(s,'Base.Sandwich'),slices=outputs(s,'Base.BreadSlices'),checkpoints=s.checkpoints}
 for _,m in ipairs(s.breadInputs)do r.breadInputs[#r.breadInputs+1]=resource(s,m)end
 for _,m in ipairs(s.sandwichInputs)do r.sandwichInputs[#r.sandwichInputs+1]=resource(s,m)end
 local book=s.root:getItemById(s.book);r.bookId=s.book;r.tailRead=book and book:getAlreadyReadPages()==book:getNumberOfPages()or false;r.sourceSnapshot=F.observerSnapshot(s.player,F.descriptor(s))
 local settled=#r.sandwiches==1 and r.tailRead
 for _,v in ipairs(r.sandwichInputs)do settled=settled and v.sourceCount==1 and v.rootCount==0 end
 if s.oven then settled=settled and s.checkpoints.Sliced~=nil and #r.slices==2 end
 s.verifySince=s.verifySince or getTimestampMs();if not settled and getTimestampMs()-s.verifySince<3000 then return nil,'joining sandwich effects settling'end
 s.verified=true;s.frozenReceipt=s.frozenReceipt or r;return r
end
return F
