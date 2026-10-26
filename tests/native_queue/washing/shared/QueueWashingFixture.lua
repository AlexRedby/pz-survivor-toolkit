require 'TimedActions/ISWashClothing'
local JSON=require 'QueueHealthEvents'
local F={bagType='Base.Bag_ALICEpack_Army',sinkSprite='location_business_office_generic_01_49',sinkEntity='Base.WaterDispenser'}
local function array(a)local r={};for i=0,a:size()-1 do r[#r+1]=a:get(i)end;return r end
local function all(c,r)r=r or {};for _,v in ipairs(array(c:getItems()))do r[#r+1]=v;if instanceof(v,'InventoryContainer')then all(v:getItemContainer(),r)end end;return r end
local function count(c,id)local n=0;for _,v in ipairs(all(c))do if v:getID()==id then n=n+1 end end;return n end
local function itemIds(c)local r={};for _,v in ipairs(all(c))do r[#r+1]=v:getID()end;table.sort(r);return r end
function F.isCancel(case)return case=='cancel-after-pickup'end
function F.noSoap(case)return case=='borrowed-batch'end
function F.snapshot(item)
 local covered=assert(BloodClothingType.getCoveredParts(item:getBloodClothingType()))
 local r={id=item:getID(),kind=item:getFullType(),blood=item:getBloodLevel(),dirt=item:getDirtiness(),wetness=item:getWetness(),parts={},transforming=false}
 local after=item:getItemAfterCleaning();assert(not after or after=='','fixture garment transforms when cleaned')
 for _,part in ipairs(array(covered))do r.parts[#r.parts+1]={index=part:index(),blood=item:getBlood(part),dirt=item:getDirt(part)}end
 return r
end
function F.resolveSink(spec)
 local sq=getCell():getGridSquare(spec.x,spec.y,spec.z)
 if not sq then return nil,'square-not-loaded'end
 if spec.objectIndex<0 or spec.objectIndex>=sq:getObjects():size()then return nil,'object-index-out-of-range'end
 local obj=sq:getObjects():get(spec.objectIndex)
 if not obj then return nil,'object-index-empty'end
 if obj:getSquare()~=sq then return nil,'object-square-identity'end
 if not obj:getSprite()or obj:getSprite():getName()~=spec.sprite then return nil,'object-sprite'end
 if obj:getModData().QueueWashingOwner~=spec.ownerToken then return nil,'owner-token'end
 if obj:getUsesExternalWaterSource()then return nil,'uses-external-water'end
 if obj:getModData().canBeWaterPiped~=true then return nil,'native-unplumbed-flag'end
 if not obj:isMovedThumpable()then return nil,'native-moved-flag'end
 if not obj:getFluidContainer()then return nil,'fluid-component-missing'end
 if spec.entity~=F.sinkEntity then return nil,'declared-entity-script'end
 if obj:getEntityScript()~=getScriptManager():getGameEntityScript(F.sinkEntity)then return nil,'live-entity-script-identity'end
 if not obj:getFluidContainer():isInputLocked()then return nil,'native-input-lock-changed'end
 return obj
end
function F.sinkDiagnostic(obj,spec)
 local sq=obj:getSquare();local fluid=obj:getFluidContainer();local sprite=obj:getSprite();local script=getScriptManager():getGameEntityScript(F.sinkEntity)
 local r={declared=spec,index=obj:getObjectIndex(),objectCount=sq and sq:getObjects():size()or -1,
  squareMatches=sq==getCell():getGridSquare(spec.x,spec.y,spec.z),sprite=sprite and sprite:getName()or 'nil',
  ownerToken=tostring(obj:getModData().QueueWashingOwner),ownerMatches=obj:getModData().QueueWashingOwner==spec.ownerToken,
  usesExternalWaterSource=obj:getUsesExternalWaterSource(),canBeWaterPiped=tostring(obj:getModData().canBeWaterPiped),moved=obj:isMovedThumpable(),
  declaredIndex=spec.objectIndex,entity=tostring(obj:getEntityScript()),expectedEntity=tostring(script),entityMatches=obj:getEntityScript()==script,
  objectAmount=obj:getFluidAmount(),fluidPresent=fluid~=nil,hasWater='not-exposed'}
 local props=sprite and sprite:getProperties()
 r.spriteWaterAmount=tostring(props and props:get('waterAmount'))
 r.spriteWaterPiped=props and props:has(IsoFlagType.waterPiped)or false
 r.roomPresent=sq and sq:getRoom()~=nil or false;r.squareNoWater=sq and sq:isNoWater()or false
 r.mainsFixRecognizesPlumbed=obj:getModData().canBeWaterPiped==false
 if sq and spec.objectIndex>=0 and spec.objectIndex<sq:getObjects():size()then r.indexObjectMatches=sq:getObjects():get(spec.objectIndex)==obj end
 if obj.hasWater then local ok,value=pcall(obj.hasWater,obj);r.hasWater=tostring(value);r.hasWaterCallOk=ok end
 if fluid then
  r.fluidAmount=fluid:getAmount();r.capacity=fluid:getCapacity();r.pureWater=fluid:isPureFluid(Fluid.Water)
  r.inputLocked=fluid:isInputLocked();r.canAddWater=fluid:canAddFluid(Fluid.Water);r.canPlayerEmpty='not-exposed'
  if fluid.canPlayerEmpty then local ok,value=pcall(fluid.canPlayerEmpty,fluid);r.canPlayerEmpty=ok and value or tostring(value)end
 end
 return r
end
local function sink(player,case)
 local origin=assert(player:getSquare());local sq
 for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}})do
  local v=getCell():getGridSquare(origin:getX()+d[1],origin:getY()+d[2],origin:getZ())
  if v and v:canStand()and v:isFree(false)and not origin:isBlockedTo(v)and v:getBuilding()==player:getBuilding()then sq=v;break end
 end
 assert(sq,'no accessible adjacent fixture sink tile')
 local obj=IsoObject.new(getCell(),sq,assert(getSprite(F.sinkSprite)))
 obj:setMovedThumpable(true);obj:setUsesExternalWaterSource(false)
 -- Native placed-but-not-plumbed state; isWaterInfinite() is private Java.
 obj:getModData().canBeWaterPiped=true
 -- Explicit native entity construction, as used by ISBuildIsoEntity. Generic sink
 -- sprites do not necessarily declare an entity or a FluidContainer in B42.21.
 local entity=assert(getScriptManager():getGameEntityScript(F.sinkEntity),'native water-dispenser entity missing')
 GameEntityFactory.CreateIsoObjectEntity(obj,entity,true);sq:AddSpecialObject(obj)
 local fluid=assert(obj:getFluidContainer(),'native water-dispenser entity did not create a fluid container')
 assert(obj:getEntityScript()==entity,'native water-dispenser entity identity: actual='..tostring(obj:getEntityScript())..' expected='..tostring(entity))
 assert(math.abs(fluid:getCapacity()-15)<.00001,'native water-dispenser capacity: actual='..tostring(fluid:getCapacity())..' expected=15')
 -- Prepare-only deterministic water seed. Native addFluid rejects InputLocked;
 -- restore the script's original lock before publishing or queuing any action.
 local inputLocked=fluid:isInputLocked();assert(inputLocked==true,'native water-dispenser initial input lock differs')
 fluid:setInputLocked(false)
 local filled,problem=pcall(function()fluid:Empty();fluid:addFluid(Fluid.Water,fluid:getCapacity())end)
 fluid:setInputLocked(inputLocked)
 assert(filled,'native water-dispenser water seed: '..tostring(problem))
 obj:getModData().QueueWashingOwner=case..':'..player:getUsername()..':'..getTimestampMs()
 local spec={x=sq:getX(),y=sq:getY(),z=sq:getZ(),objectIndex=obj:getObjectIndex(),sprite=F.sinkSprite,entity=F.sinkEntity,
  ownerToken=obj:getModData().QueueWashingOwner,amount=obj:getFluidAmount(),capacity=fluid:getCapacity(),
  moved=obj:isMovedThumpable(),usesExternalWaterSource=obj:getUsesExternalWaterSource(),canBeWaterPiped=obj:getModData().canBeWaterPiped,inputLocked=fluid:isInputLocked()}
 local diagnostic=F.sinkDiagnostic(obj,spec);local resolved,reason=F.resolveSink(spec)
 diagnostic.resolveReason=reason or 'resolved';print('[WASHING_TEST] SOURCE '..JSON.encode(diagnostic))
 assert(resolved==obj,'washing source identity predicate: '..tostring(reason)..' actual='..JSON.encode(diagnostic))
 assert(fluid:isPureFluid(Fluid.Water),'washing source pureWater=false actual='..JSON.encode(diagnostic))
 assert(math.abs(spec.amount-fluid:getAmount())<.00001,'washing source public/component amount mismatch actual='..JSON.encode(diagnostic))
 assert(math.abs(fluid:getAmount()-fluid:getCapacity())<.00001 and spec.amount<10000,'washing source finite/full amount predicate actual='..JSON.encode(diagnostic))
 if fluid.canPlayerEmpty then assert(fluid:canPlayerEmpty(),'washing source public empty/wash menu predicate=false actual='..JSON.encode(diagnostic))end
 assert(sq:getBuilding()==player:getBuilding(),'washing source public washing menu building identity differs')
 return obj,spec
end
local function cleanup(s)
 assert(s.verified and s.player:getInventory()==s.root,'previous washing fixture was not verified')
 local bag=assert(s.root:getItemById(s.ids.bagId));assert(bag:getContainer()==s.root and bag:getFullType()==s.ids.bagType
  and count(s.root,bag:getID())==1 and not s.player:isEquipped(bag),'previous washing bag changed or remains equipped')
 local allowed={};for _,meta in ipairs(s.ids.garments)do allowed[meta.id]=meta.kind end
 for _,item in ipairs(all(bag:getItemContainer()))do
  assert(allowed[item:getID()]==item:getFullType(),'foreign contents in previous washing bag')
 end
 for _,meta in ipairs(s.ids.garments)do
  local item=assert(s.root:getItemById(meta.id));assert(count(s.root,meta.id)==1 and item:getFullType()==meta.kind,'previous garment identity changed')
  assert(item:getContainer()==(F.isCancel(s.case)and s.root or bag:getItemContainer()),'previous garment left verified endpoint')
  if item:getContainer()==s.root then s.root:Remove(item);if isServer()then sendRemoveItemFromContainer(s.root,item)end end
 end
 for _,id in ipairs({s.ids.bagId,s.ids.soap.id,s.ids.book})do
  local item=assert(s.root:getItemById(id));assert(item:getContainer()==s.root and not s.player:isEquipped(item),'previous root item changed')
  s.root:Remove(item);if isServer()then sendRemoveItemFromContainer(s.root,item)end
 end
 local obj=assert(F.resolveSink(s.ids.sink));assert(obj==s.sink,'previous sink identity changed')
 local sq=obj:getSquare();sq:transmitRemoveItemFromSquare(obj)
 if obj:getObjectIndex()>=0 then obj:removeFromWorld();obj:removeFromSquare()end
end
function F.prepare(player,case,previous)
 assert(case=='borrowed-batch'or case=='borrowed-single-soap'or F.isCancel(case),'unknown washing case')
 if previous then cleanup(previous)end
 local root=player:getInventory();local s={player=player,root=root,case=case}
 s.sink,s.sinkSpec=sink(player,case)
 local bag=assert(root:AddItem(F.bagType));local source=bag:getItemContainer();local garments={}
 for _,kind in ipairs(case=='borrowed-batch'and {'Base.Tshirt_DefaultTEXTURE_TINT','Base.Shirt_FormalWhite'}or {'Base.Tshirt_DefaultTEXTURE_TINT'})do
  local item=assert(source:AddItem(kind));assert(instanceof(item,'Clothing'))
  local parts=assert(BloodClothingType.getCoveredParts(item:getBloodClothingType()));assert(parts:size()>0)
  for j=0,parts:size()-1 do item:setBlood(parts:get(j),j==0 and .15 or 0);item:setDirt(parts:get(j),j==0 and .10 or 0)end
  BloodClothingType.calcTotalBloodLevel(item);BloodClothingType.calcTotalDirtLevel(item)
  item:setWetness(0)
  local meta=F.snapshot(item);meta.requiredWater=ISWashClothing.GetRequiredWater(item);meta.requiredSoap=ISWashClothing.GetRequiredSoap(item)
  assert(meta.blood>0 and meta.dirt>0 and meta.requiredWater>0 and meta.requiredSoap==1,'dirty clothing seed differs')
  garments[#garments+1]=meta
 end
 local soap=assert(root:AddItem('Base.Soap2'));local book=assert(root:AddItem('Base.BookCarpentry1'))
 book:setAlreadyReadPages(book:getNumberOfPages()-1);player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 local water=0;for _,meta in ipairs(garments)do water=water+meta.requiredWater end
 assert(soap:getCurrentUses()>#garments and s.sink:getFluidAmount()>water,'fixture lacks washing resources')
 s.ids={case=case,actorId=player:getOnlineID(),bagId=bag:getID(),bagType=bag:getFullType(),sink=s.sinkSpec,
  garments=garments,soap={id=soap:getID(),kind=soap:getFullType(),uses=soap:getCurrentUses()},book=book:getID(),allIds=itemIds(root)}
 if isServer()then
  sendAddItemToContainer(root,bag);sendAddItemToContainer(root,soap);sendAddItemToContainer(root,book)
  s.sink:transmitCompleteItemToClients();s.sink:transmitModData();s.sink:sendSyncEntity(nil)
 end
 return s
end
function F.resolve(player,ids)
 local root=player:getInventory();local bag=root:getItemById(ids.bagId);local soap=root:getItemById(ids.soap.id);local book=root:getItemById(ids.book);local obj=F.resolveSink(ids.sink)
 if not obj or not bag or bag:getFullType()~=ids.bagType or bag:getContainer()~=root or not soap or not book
  or soap:getContainer()~=root or soap:getCurrentUses()~=ids.soap.uses or math.abs(obj:getFluidAmount()-ids.sink.amount)>.00001
  or not obj:getFluidContainer():isPureFluid(Fluid.Water)or math.abs(obj:getFluidContainer():getAmount()-obj:getFluidAmount())>.00001 then return end
 local source=bag:getItemContainer()
 for _,meta in ipairs(ids.garments)do
  local item=root:getItemById(meta.id)
  if not item or item:getContainer()~=source or item:getFullType()~=meta.kind or math.abs(item:getBloodLevel()-meta.blood)>.00001
   or math.abs(item:getDirtiness()-meta.dirt)>.00001 then return end
 end
 return {root=root,bag=bag,source=source,soap=soap,book=book,sink=obj}
end
function F.verify(s)
 local ids,root=s.ids,s.root;local bag=root:getItemById(ids.bagId);local soap=root:getItemById(ids.soap.id);local book=root:getItemById(ids.book)
 if not bag or bag:getContainer()~=root or not soap or soap:getContainer()~=root or not book or book:getContainer()~=root
  or F.resolveSink(ids.sink)~=s.sink then return nil,'washing owned root resources absent'end
 local r={case=s.case,actorId=s.player:getOnlineID(),bagId=bag:getID(),bagType=bag:getFullType(),bagRootCount=count(root,bag:getID()),
  soap={id=soap:getID(),kind=soap:getFullType(),uses=soap:getCurrentUses(),rootCount=soap:getContainer()==root and 1 or 0,totalCount=count(root,soap:getID())},
  sink={source=ids.sink,amount=s.sink:getFluidAmount(),fluidAmount=s.sink:getFluidContainer():getAmount(),pureWater=s.sink:getFluidContainer():isPureFluid(Fluid.Water),
   moved=s.sink:isMovedThumpable(),usesExternalWaterSource=s.sink:getUsesExternalWaterSource(),canBeWaterPiped=s.sink:getModData().canBeWaterPiped,inputLocked=s.sink:getFluidContainer():isInputLocked()},
  garments={},bookId=book:getID(),tailRead=book:getAlreadyReadPages()==book:getNumberOfPages(),allIds=itemIds(root)}
 for _,meta in ipairs(ids.garments)do
  local item=root:getItemById(meta.id);if not item then return nil,'washing garment disappeared'end
  local v=F.snapshot(item);v.rootCount=item:getContainer()==root and 1 or 0;v.sourceCount=item:getContainer()==bag:getItemContainer()and 1 or 0;v.totalCount=count(root,meta.id)
  r.garments[#r.garments+1]=v
 end
 if not r.tailRead then return nil,'independent washing reader incomplete'end
 s.verified=true;return r
end
return F
