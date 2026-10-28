require 'TimedActions/ISWashYourself'
local B={cases={['body-full']=true,['body-water-limited']=true,['body-cancel']=true}}
function B.isCase(case)return B.cases[case]==true end
local function slots()return{ItemBodyLocation.MAKE_UP_FULL_FACE,ItemBodyLocation.MAKE_UP_EYES,ItemBodyLocation.MAKE_UP_EYES_SHADOW,ItemBodyLocation.MAKE_UP_LIPS}end
local function all(c,r)r=r or{};local values=c:getItems();for i=0,values:size()-1 do local v=values:get(i);r[#r+1]=v;if instanceof(v,'InventoryContainer')then all(v:getItemContainer(),r)end end;return r end
local function ids(c)local r={};for _,v in ipairs(all(c))do r[#r+1]=v:getID()end;table.sort(r);return r end
local function count(c,id)local n=0;for _,v in ipairs(all(c))do if v:getID()==id then n=n+1 end end;return n end
local function equal(a,b)
 if type(a)~=type(b)then return false end
 if type(a)=='number'then return math.abs(a-b)<.00001 end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not equal(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
function B.weather()
 local climate=assert(getClimateManager(),'native climate missing')
 return{precipitation=climate:getPrecipitationIntensity(),rain=climate:getRainIntensity(),snow=climate:getSnowIntensity(),
  rainAlwaysClean=SandboxVars.RainCleansBlood and SandboxVars.RainCleansBlood.AlwaysClean==true or false}
end
function B.isDry()
 local weather=B.weather();return weather.precipitation==0 and weather.rain==0 and weather.snow==0 and not weather.rainAlwaysClean
end
local function dryPreparation()
 assert(not isClient(),'weather baseline is authority preparation only')
 local climate=assert(getClimateManager());local precipitation=assert(climate:getClimateFloat(ClimateManager.FLOAT_PRECIPITATION_INTENSITY))
 -- Native test-world baseline, before body seeding; no climate writes during gameplay.
 precipitation:setEnableAdmin(true);precipitation:setAdminValue(0);precipitation:setFinalValue(0)
 assert(precipitation:isEnableAdmin()and precipitation:getAdminValue()==0 and B.isDry(),'native dry baseline unavailable/AlwaysClean enabled')
end
function B.snapshot(player)
 local r={parts={},makeupIds={}};local visual=player:getHumanVisual()
 for i=0,BloodBodyPartType.MAX:index()-1 do local part=BloodBodyPartType.FromIndex(i);r.parts[#r.parts+1]={index=i,blood=visual:getBlood(part),dirt=visual:getDirt(part)}end
 for _,slot in ipairs(slots())do local item=player:getWornItem(slot);if item then r.makeupIds[#r.makeupIds+1]=item:getID()end end
 table.sort(r.makeupIds);return r
end
function B.cleanup(s,F)
 assert(s.verified and s.player:getInventory()==s.root,'unverified body cleanup')
 local makeup=s.root:getItemById(s.ids.makeup.id)
 if s.case=='body-cancel'then
  assert(makeup and s.player:getWornItem(ItemBodyLocation.MAKE_UP_EYES)==makeup,'canceled body makeup identity changed')
  s.player:setWornItem(ItemBodyLocation.MAKE_UP_EYES,nil)
  if isServer()then sendClothing(s.player,ItemBodyLocation.MAKE_UP_EYES,nil)end
 else assert(not makeup and not s.player:getWornItem(ItemBodyLocation.MAKE_UP_EYES),'completed body makeup survived')end
 for _,id in ipairs({s.ids.soap.id,s.ids.book,s.ids.makeup.id})do
  local item=s.root:getItemById(id)
  if item then assert(item:getContainer()==s.root and not s.player:isEquipped(item),'body owned item changed');s.root:Remove(item);if isServer()then sendRemoveItemFromContainer(s.root,item)end end
 end
 local obj=assert(F.resolveSink(s.ids.sink));assert(obj==s.sink,'body sink changed');local sq=obj:getSquare();sq:transmitRemoveItemFromSquare(obj)
 if obj:getObjectIndex()>=0 then obj:removeFromWorld();obj:removeFromSquare()end
end
function B.prepare(player,case,F,stand)
 if isServer()then assert(require('PZSurvivorToolkit/SourceProof').closure(ISWashYourself.removeMakeup,'WashMakeupSync.lua'),'native Host makeup removal notification fix is not installed')end
 assert(B.isCase(case));dryPreparation();local root=player:getInventory();local s={player=player,root=root,case=case}
 for _,slot in ipairs(slots())do assert(not player:getWornItem(slot),'fresh body fixture already wears makeup')end
 if stand then
  assert(case=='body-full'and stand.player==player and stand.root==root,'mixed body source identity changed')
  s.sink,s.sinkSpec=stand.sink,stand.ids.sink
 else s.sink,s.sinkSpec=F.createSource(player,case)end
 if case=='body-water-limited'then
  local fluid=s.sink:getFluidContainer();local locked=fluid:isInputLocked();fluid:setInputLocked(false)
  local ok,problem=pcall(function()fluid:Empty();fluid:addFluid(Fluid.Water,1)end);fluid:setInputLocked(locked);assert(ok,problem)
  assert(s.sink:getFluidAmount()==1 and fluid:getAmount()==1,'native limited-water seed differs');s.sinkSpec.amount=1
 end
 local visual=player:getHumanVisual();assert(BloodBodyPartType.MAX:index()==18,'current native body enum differs')
 for i=0,BloodBodyPartType.MAX:index()-1 do local part=BloodBodyPartType.FromIndex(i);visual:setBlood(part,i==0 and .15 or 0);visual:setDirt(part,i<2 and .10 or 0)end
 local soap,book
 if stand then
  soap=assert(root:getItemById(stand.ids.soap.id),'mixed stand soap missing');book=assert(root:getItemById(stand.ids.book),'mixed stand book missing')
  assert(soap:getID()==stand.ids.soap.id and book:getID()==stand.ids.book and soap:getContainer()==root and soap:getFullType()==stand.ids.soap.kind and soap:getCurrentUses()==stand.ids.soap.uses
   and book:getContainer()==root and book:getFullType()=='Base.BookCarpentry1','mixed stand root resource identity changed')
 else soap=assert(root:AddItem('Base.Soap2'));book=assert(root:AddItem('Base.BookCarpentry1'))end
 local makeup=assert(root:AddItem('Base.MakeUp_Crow'))
 assert(instanceof(makeup,'Clothing')and makeup:getBodyLocation()==ItemBodyLocation.MAKE_UP_EYES,'native Crow script/body slot differs')
 player:setWornItem(ItemBodyLocation.MAKE_UP_EYES,makeup);assert(player:getWornItem(ItemBodyLocation.MAKE_UP_EYES)==makeup)
 player:resetModelNextFrame()
 book:setAlreadyReadPages(book:getNumberOfPages()-1);player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 local body=B.snapshot(player);assert(body.parts[1].blood>0 and body.parts[1].dirt>0 and body.parts[2].blood==0 and body.parts[2].dirt>0)
 assert(ISWashYourself.GetRequiredWater(player)==2 and ISWashYourself.GetRequiredSoap(player)==1,'native body seed/profile differs')
 s.ids={case=case,actorId=player:getOnlineID(),sink=s.sinkSpec,soap={id=soap:getID(),kind=soap:getFullType(),uses=soap:getCurrentUses()},
  weather=B.weather(),makeup={id=makeup:getID(),kind=makeup:getFullType(),slot=tostring(ItemBodyLocation.MAKE_UP_EYES)},body=body,book=book:getID(),
  requiredWater=2,requiredSoap=1,expectedDuration=case=='body-water-limited'and 70 or 140,allIds=ids(root)}
 if isServer()then
  if not stand then sendAddItemToContainer(root,soap);sendAddItemToContainer(root,book)end
  sendAddItemToContainer(root,makeup)
  sendClothing(player,ItemBodyLocation.MAKE_UP_EYES,makeup);sendHumanVisual(player)
  s.sink:transmitCompleteItemToClients();s.sink:transmitModData();s.sink:sendSyncEntity(nil)
 end
 return s
end
local readinessLogs={}
local function describe(item,root)
 if not item then return{present=false}end
 local container=item:getContainer()
 return{present=true,id=item:getID(),kind=item:getFullType(),directRoot=container==root,container=tostring(container),reference=tostring(item)}
end
function B.makeupIdentity(player,meta)
 local root=player:getInventory();local spec=meta.makeup
 if spec.slot~=tostring(ItemBodyLocation.MAKE_UP_EYES)then return false,'wrong-slot'end
 local makeup=root:getItemById(spec.id)
 if not makeup or makeup:getFullType()~=spec.kind or makeup:getContainer()~=root or count(root,spec.id)~=1 then return false,'root-identity'end
 local direct=0;local items=root:getItems();for i=0,items:size()-1 do if items:get(i)==makeup then direct=direct+1 end end
 if direct~=1 then return false,'root-membership'end
 local worn=player:getWornItem(ItemBodyLocation.MAKE_UP_EYES)
 if not worn or worn:getID()~=spec.id or worn:getFullType()~=spec.kind then return false,'worn-identity'end
 if worn==makeup then return true,'same-reference'end
 -- SyncClothingPacket may create an unattached same-ID visual before the root
 -- inventory packet arrives. Observe that native client replica; never rebind it.
 if isClient()and not isServer()and worn:getContainer()==nil then return true,'client-unattached-visual'end
 return false,'foreign-or-attached-reference'
end
function B.preparationStatus(player,meta,F)
 local root=player:getInventory();local soap=root:getItemById(meta.soap.id);local book=root:getItemById(meta.book)
 local makeup=root:getItemById(meta.makeup.id);local worn=player:getWornItem(ItemBodyLocation.MAKE_UP_EYES)
 local sink,reason=F.resolveSink(meta.sink);local body=B.snapshot(player);local weather=B.weather();local makeupIdentity,makeupReason=B.makeupIdentity(player,meta)
 local predicates={actor=player:getOnlineID()==meta.actorId,dry=B.isDry(),soapRoot=soap~=nil and soap:getContainer()==root,
  soapType=soap~=nil and soap:getFullType()==meta.soap.kind,soapUses=soap~=nil and soap:getCurrentUses()==meta.soap.uses,
  bookRoot=book~=nil and book:getContainer()==root,makeupRoot=makeup~=nil and makeup:getContainer()==root,
  makeupType=makeup~=nil and makeup:getFullType()==meta.makeup.kind,makeupIdentity=makeupIdentity,
  parts=equal(body.parts,meta.body.parts),wornIds=equal(body.makeupIds,meta.body.makeupIds),sink=sink~=nil,
  sinkAmount=sink~=nil and math.abs(sink:getFluidAmount()-meta.sink.amount)<.00001}
 local ready=true;for _,value in pairs(predicates)do if not value then ready=false end end
 local actualSoap=describe(soap,root);if soap then actualSoap.uses=soap:getCurrentUses()end
 return{case=meta.case,ready=ready,predicates=predicates,expected={actorId=meta.actorId,soap=meta.soap,book=meta.book,makeup=meta.makeup,body=meta.body,weather=meta.weather,sink=meta.sink},
  actual={makeupSameReference=makeup~=nil and worn==makeup,makeupIdentityReason=makeupReason,actorId=player:getOnlineID(),soap=actualSoap,book=describe(book,root),makeup=describe(makeup,root),wornMakeup=describe(worn,root),
   soapCount=count(root,meta.soap.id),bookCount=count(root,meta.book),makeupCount=count(root,meta.makeup.id),body=body,weather=weather,
   sinkReason=reason or(sink and 'resolved'or 'unresolved'),sinkAmount=sink and sink:getFluidAmount()or -1,inventoryIds=ids(root)}},
  {player=player,root=root,case=meta.case,ids=meta,sink=sink,soap=soap,book=book,makeup=makeup}
end
function B.resolve(player,meta,F)
 local status,state=B.preparationStatus(player,meta,F);local log=readinessLogs[meta.case]
 if status.ready then
  if log and not log.ready then status.elapsedMs=getTimestampMs()-log.start;print('[WASHING_TEST] BODY_READY '..require('QueueHealthEvents').encode(status));log.ready=true end
  return state
 end
 if not log then log={start=getTimestampMs(),count=0};readinessLogs[meta.case]=log end
 local elapsed=getTimestampMs()-log.start;local deadlines={0,1000,5000,15000}
 if log.count<4 and elapsed>=deadlines[log.count+1]then
  status.elapsedMs=elapsed;print('[WASHING_TEST] BODY_READY '..require('QueueHealthEvents').encode(status));log.count=log.count+1
 end
end
function B.verify(s,F)
 local root,meta=s.root,s.ids;local soap=root:getItemById(meta.soap.id);local book=root:getItemById(meta.book);local makeup=root:getItemById(meta.makeup.id)
 if not soap or soap:getContainer()~=root or not book or book:getContainer()~=root or F.resolveSink(meta.sink)~=s.sink then return nil,'body resources absent'end
 if book:getAlreadyReadPages()~=book:getNumberOfPages()then return nil,'body independent reader incomplete'end
 assert(B.isDry(),'body weather changed after preparation')
 local fluid=s.sink:getFluidContainer();local r={weather=B.weather(),case=s.case,actorId=s.player:getOnlineID(),body=B.snapshot(s.player),bookId=book:getID(),tailRead=true,allIds=ids(root),
  soap={id=soap:getID(),kind=soap:getFullType(),uses=soap:getCurrentUses(),rootCount=soap:getContainer()==root and 1 or 0,totalCount=count(root,soap:getID())},
  makeup={id=meta.makeup.id,kind=meta.makeup.kind,slot=meta.makeup.slot,rootCount=makeup and makeup:getContainer()==root and 1 or 0,totalCount=count(root,meta.makeup.id),worn=B.makeupIdentity(s.player,meta)},
  sink={source=meta.sink,amount=s.sink:getFluidAmount(),fluidAmount=fluid:getAmount(),pureWater=fluid:isPureFluid(Fluid.Water),moved=s.sink:isMovedThumpable(),
   usesExternalWaterSource=s.sink:getUsesExternalWaterSource(),canBeWaterPiped=s.sink:getModData().canBeWaterPiped,inputLocked=fluid:isInputLocked()}}
 s.verified=true;return r
end
return B
