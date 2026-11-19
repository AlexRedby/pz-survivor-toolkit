-- Seeds disposable inputs; all grooming, drops and pickups use normal native producers.
local P=require 'QueueEnergyPlacement'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local A={}
local s={players={}}
local diagnosticInstalled
local function role(player)return config.kind=='sp'and'client1'or player:getUsername()end
local function peer()return s.case=='peer-pickup'or s.case=='owner-pickup-first'end
local function peerWins()return s.case=='peer-pickup'end
local function emit(marker,row)print('[GENERATOR_RECOVERY] '..marker..' '..JSON.encode(row))end
local function find(player,wanted)
 local function scan(container)
  local items=container:getItems()
  for i=0,items:size()-1 do local item=items:get(i)
   if item:getID()==wanted then return item end
   if instanceof(item,'InventoryContainer')then local found=scan(item:getItemContainer());if found then return found end end
  end
 end
 return scan(player:getInventory())
end
local function remove(player,item)
 if not item then return end
 if player:getPrimaryHandItem()==item then player:setPrimaryHandItem(nil)end
 if player:getSecondaryHandItem()==item then player:setSecondaryHandItem(nil)end
 local container=item:getContainer();if container and container:contains(item)then container:Remove(item);if isServer()then sendRemoveItemFromContainer(container,item)end end
end
local function dispose()
 assert(s.result,'previous generator case was not verified')
 for _,player in pairs(s.players)do
  for _,name in ipairs({'original','razor','replacement','tail','output'})do
   local spec=s.ids.items[name];local item=spec and find(player,spec.id)or name=='output'and s.output
   remove(player,item)
  end
  if player==s.players.client1 then player:removeWornItem(s.bag,false);if isServer()then sendClothing(player,s.bag:canBeEquipped(),nil)end;remove(player,s.bag)end
  if isServer()then sendEquip(player)end
 end
 for _,object in ipairs({s.target,s.decoy})do
  if object and object:getObjectIndex()>=0 then
   local square=assert(object:getSquare());square:transmitRemoveItemFromSquare(object)
   if object:getObjectIndex()>=0 then object:removeFromWorld();object:removeFromSquare()end
  end
 end
end
function A.layout(player,case)
 local name=role(player);assert(name=='client1'or peer()and name=='client2'or (case=='peer-pickup'or case=='owner-pickup-first')and name=='client2','unexpected recovery actor')
 if case~=s.case then
  if name~='client1'then return end
  if s.case then dispose()end
  s={players={},case=case,origin=P.choose(player)}
 end
 local at=s.origin
 return{case=case,target=P.target(name=='client1'and at or{x=at.x+1,y=at.y,z=at.z}),generator=P.target(at)}
end
function A.prepare(player,case,target,proof)
 local layout=assert(A.layout(player,case));assert(P.atCentered(player,layout.target),'recovery authority arrival differs')
 assert(proof and proof.target and proof.target.x==target.x and proof.target.y==target.y and proof.target.z==target.z,'recovery placement proof missing')
 s.players[role(player)]=player
end
function A.players()return s.players end
function A.seed()
 if s.ids then return s.ids end
 if not diagnosticInstalled then
  assert(not isClient(),'authority diagnostic observer must not be installed on a replica')
  local recovery=require 'PZSurvivorToolkit/ActionQueueGeneratorRecovery';local previous=recovery.onArmDenied
  recovery.onArmDenied=function(actor,reason)
   if previous then previous(actor,reason)end
   if actor==s.players.client1 then emit('ARM_DENIED',{case=s.case,reason=tostring(reason),actor=actor:getOnlineID()})end
  end
  diagnosticInstalled=true
 end
 local owner=s.players.client1;if not owner or peer()and not s.players.client2 then return end
 local root=owner:getInventory();assert(not owner:isFemale(),'native beard producer requires male character')
 assert(not owner:getPrimaryHandItem()and not owner:getSecondaryHandItem(),'recovery seed requires empty hands')
 s.bag=assert(root:AddItem('Base.Bag_Military'));assert(not owner:getWornItem(s.bag:canBeEquipped()),'fixture bag slot occupied');owner:setWornItem(s.bag:canBeEquipped(),s.bag)
 local existing=root:getItems();for i=0,existing:size()-1 do assert(existing:get(i):getFullType()~='Base.Generator','generator fixture requires no preexisting carried generator')end
 local ids={bag={id=s.bag:getID(),type=s.bag:getFullType()},case=s.case,x=s.origin.x,y=s.origin.y,z=s.origin.z,items={},initialBeard='LongScruffy',targetBeard='Moustache'}
 for name,kind in pairs({original='Base.Generator',razor='Base.Razor',replacement='Base.Screwdriver',tail='Base.BookCarpentry1'})do
  local item=assert((name=='razor'and s.bag:getItemContainer()or root):AddItem(kind));s[name]=item;item:setFavorite(true);ids.items[name]={id=item:getID(),type=kind}
 end
 s.original:setCondition(73);s.original:getModData().fuel=7.5;s.original:getModData().fixtureAncestry='source'
 local pages=s.tail:getNumberOfPages();assert(pages>2);ids.total=pages;ids.initialPages=pages-2
 s.tail:setAlreadyReadPages(pages-2);owner:setAlreadyReadPages(s.tail:getFullType(),pages-2);owner:setPerkLevelDebug(Perks.Woodwork,0)
 local visual=owner:getHumanVisual();visual:setBeardModel(ids.initialBeard);owner:resetModel()
 local square=assert(owner:getCurrentSquare());s.square=square
 local decoyItem=assert(instanceItem('Base.Generator'));decoyItem:setCondition(41);decoyItem:getModData().fuel=3.25
 s.decoy=IsoGenerator.new(decoyItem,getCell(),square);ids.decoyIndex=s.decoy:getObjectIndex()
 if isServer()then sendAddItemToContainer(root,s.bag);for _,name in ipairs({'original','replacement','tail'})do sendAddItemToContainer(root,s[name])end;sendClothing(owner,s.bag:canBeEquipped(),s.bag)end
 owner:setPrimaryHandItem(s.original);owner:setSecondaryHandItem(s.original)
 if isServer()then sendEquip(owner);sendHumanVisual(owner)end
 ids.ownerOnlineId=owner:getOnlineID();ids.pickerOnlineId=peer()and s.players.client2:getOnlineID()or nil
 if peer()then assert(s.players.client2~=owner and ids.pickerOnlineId~=ids.ownerOnlineId,'peer actor is not independent')end
 s.ids=ids;return ids
end
function A.ready(player,case)
 assert(s.ids and case==s.case and s.players[role(player)]==player,'unprepared recovery ready')
 s.ready=s.ready or{};s.ready[role(player)]=true;return s.ready.client1 and(not peer()or s.ready.client2)
end
function A.observe()
 if not s.ids or s.result then return end
 local owner=s.players.client1
 if not s.target and owner:getInventory():getItemById(s.original:getID())==nil then
  local objects=s.square:getObjects();local found
  for i=0,objects:size()-1 do local object=objects:get(i)
   if instanceof(object,'IsoGenerator')and object~=s.decoy then
    assert(not found,'recovery source world identity ambiguous');found=object
   end
  end
  if found then
   assert(found:getGeneratorItemType()=='Base.Generator'and found:getCondition()==73 and math.abs(found:getFuel()-7.5)<.01,'native dropped generator lost type/condition/fuel')
   s.target=found;s.dropObserved=true;emit('STAGE',{case=s.case,phase='authority-native-drop',originalId=s.original:getID(),objectIndex=found:getObjectIndex(),condition=found:getCondition(),fuel=found:getFuel()})
  end
 end
end
function A.trimStarted(player,case)
 assert(s.ids and player==s.players.client1 and case==s.case and not s.trimStarted,'unexpected grooming boundary')
 A.observe();s.razor=assert(find(player,s.ids.items.razor.id),'exact borrowed razor no longer carried');assert(s.target and s.dropObserved,'native generator drop must precede actual trim progress')
 assert(player:getPrimaryHandItem()==s.razor and player:getHumanVisual():getBeardModel()==s.ids.initialBeard,'authority trim boundary lost razor/initial beard')
 s.trimStarted=true
 return{case=case,x=s.ids.x,y=s.ids.y,z=s.ids.z,objectIndex=s.target:getObjectIndex(),decoyIndex=s.decoy:getObjectIndex()}
end
function A.peerStarted(player,case,source)
 assert(peer()and player==s.players.client2 and case==s.case and s.trimStarted and not s.peerStarted,'peer pickup missed active owner trim')
 local at,delta=tonumber(source.at),tonumber(source.delta)
 -- Kahlua's remainder narrows the quotient to a Java int; epoch milliseconds exceed it.
 assert(at and at>0 and math.floor(at)==at and delta and delta>0 and delta<1,
  'invalid peer progress receipt: at='..tostring(source.at)..', delta='..tostring(source.delta))
 s.peerStarted={at=at,delta=delta,receivedAt=getTimestampMs()}
 emit('PEER_START_AUTHORITY',{case=case,startedAt=at,receivedAt=s.peerStarted.receivedAt,delta=delta,
  targetPresent=s.target:getObjectIndex()>=0,ownerBeard=s.players.client1:getHumanVisual():getBeardModel()})
end
function A.acknowledge(player,case)
 assert(s.result and case==s.case and s.players[role(player)]==player,'unverified recovery case acknowledgement')
 s.observed=s.observed or{};s.observed[role(player)]=true
 return s.observed.client1 and(not peer()or s.observed.client2)
end
function A.verify(player,case)
 assert(s.ids and player==s.players.client1 and case==s.case and s.trimStarted,'verification lacks genuine producer')
 if s.result then return s.result end
 A.observe();local ids=s.ids;local owner=s.players.client1;local root=owner:getInventory()
 s.razor=assert(find(owner,ids.items.razor.id),'exact borrowed razor lost before authority verification')
 s.bag=assert(find(owner,ids.bag.id),'exact borrowed razor origin lost before authority verification')
 local recovered=case=='auto-return'or case=='cancel-active'or case=='owner-pickup-first';local hasOutput=recovered or peer()
 local picker=peerWins()and s.players.client2 or owner
 local output=hasOutput and picker:getPrimaryHandItem()or nil
 if hasOutput and(not output or output:getFullType()~='Base.Generator'or s.target:getObjectIndex()~=-1)then return end
 if peer()and not s.peerStarted then return end
 if owner:getHumanVisual():getBeardModel()~=(case=='cancel-active'and ids.initialBeard or ids.targetBeard)then return end
 if owner:getAlreadyReadPages(s.tail:getFullType())~=ids.total then return end
 assert(root:getItemById(s.original:getID())==nil,'original generator inventory identity returned')
 local inventoryGenerators=0
 for _,actor in pairs(s.players)do local values=actor:getInventory():getItems()
  for i=0,values:size()-1 do local item=values:get(i)
   if item:getFullType()=='Base.Generator'then inventoryGenerators=inventoryGenerators+1;assert(item==output,'unexpected generator inventory output/duplicate')end
  end
 end
 assert(inventoryGenerators==(hasOutput and 1 or 0),'generator inventory conservation differs')
 assert(s.decoy:getObjectIndex()>=0 and s.decoy:getSquare()==s.square and s.decoy:getCondition()==41 and math.abs(s.decoy:getFuel()-3.25)<.01,'same-square decoy changed')
 if peer()and not peerWins()then assert(not s.players.client2:getPrimaryHandItem()and not s.players.client2:getSecondaryHandItem(),'losing ordinary peer pickup created/equipped an item')end
 if output then
  assert(picker:getSecondaryHandItem()==output and picker:getInventory():getItemById(output:getID())==output,'native output not canonical in both hands')
  assert(output~=s.original and output:getID()~=s.original:getID()and output:getCondition()==73 and math.abs((output:getModData().fuel or 0)-7.5)<.01,'native output identity/condition/fuel differs')
  assert(not output:isFavorite()and output:getModData().fixtureAncestry==nil,'native output illegally inherited source favorite/modData');s.output=output
 end
 if recovered then assert(owner:getPrimaryHandItem()==output and owner:getSecondaryHandItem()==output,'AUTO generator grips differ')
 elseif peerWins()then assert(owner:getPrimaryHandItem()==s.razor and not owner:getSecondaryHandItem(),'owner recovered foreign/deleted generator')
 else assert(owner:getPrimaryHandItem()==s.replacement and not owner:getSecondaryHandItem()and s.target:getObjectIndex()>=0,'new explicit primary request lost priority')end
 assert(find(owner,s.razor:getID())==s.razor and root:getItemById(s.replacement:getID())==s.replacement,'grooming lost independent equipment')
 assert(s.bag:getContainer()==root and owner:getWornItems():contains(s.bag),'borrowed razor origin bag lost canonical worn state')
 assert(s.razor:getContainer()==(recovered and s.bag:getItemContainer()or root),'borrowed razor return/retention differs after generator restoration')
 local row={case=case,authority=true,producer='ISCharacterScreen.onTrimBeard',type='Base.Generator',condition=73,fuel=7.5,
  originalId=s.original:getID(),razorId=s.razor:getID(),replacementId=s.replacement:getID(),tailId=s.tail:getID(),
  ownerOnlineId=owner:getOnlineID(),pickerOnlineId=peer()and s.players.client2:getOnlineID()or nil,outputId=output and output:getID()or nil,
  sourceFavorite=s.original:isFavorite(),outputFavorite=output and output:isFavorite()or nil,
  originalAbsent=true,decoyPresent=true,decoyIndex=s.decoy:getObjectIndex(),targetPresent=s.target:getObjectIndex()>=0,
  ownerBothHands=recovered,ownerHasRazor=peerWins(),ownerHasReplacement=case=='new-primary-intent',
  razorReturned=s.razor:getContainer()==s.bag:getItemContainer(),razorInRoot=s.razor:getContainer()==root,bagCanonical=true,beard=owner:getHumanVisual():getBeardModel(),tailComplete=true,peerStartedAt=s.peerStarted and s.peerStarted.at or nil,peerBothHands=peerWins(),dropObserved=s.dropObserved,trimStarted=s.trimStarted}
 -- Lua false must survive as an explicit field rather than become nil through and/or.
 if output then row.outputFavorite=output:isFavorite()end
 s.result=row;emit('AUTHORITY',row);return row
end
return A
