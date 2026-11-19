require 'TimedActions/ISEquipWeaponAction'
require 'TimedActions/ISTransferAction'
local Drop=require 'PZSurvivorToolkit/ActionQueueGeneratorDrop'
local P=require 'QueueEnergyPlacement'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local A={}
local session={peers={}}
local function role(player)return config.kind=='sp'and'client1'or player:getUsername()end
local function same(a,b)return a.x==b.x and a.y==b.y and a.z==b.z end
function A.layout(player,case)
 assert(case==(config.kind=='sp'and'same-square'or'peer-pickup'),'unexpected generator drop case')
 local name=role(player);assert(name=='client1'or config.kind=='mp'and name=='client2','unexpected generator actor')
 if not session.origin then
  if name~='client1'then return end
  session.origin=P.choose(player);session.case=case
 end
 assert(case==session.case,'generator case changed')
 local origin=session.origin
 local target=name=='client1'and origin or{x=origin.x+1,y=origin.y,z=origin.z}
 return{case=case,target=P.target(target),generator=P.target(origin)}
end
function A.prepare(player,case,target,proof)
 local layout=assert(A.layout(player,case));target=P.target(target)
 assert(same(target,layout.target)and P.atCentered(player,target),'generator authority arrival differs')
 assert(proof and same(P.target(proof.target),target),'generator arrival proof missing')
 local name=role(player);assert(not session.peers[name]or session.peers[name]==player,'generator actor replaced')
 session.peers[name]=player
end
function A.seed()
 if session.ids then return session.ids end
 local owner=session.peers.client1
 local picker=config.kind=='sp'and owner or session.peers.client2
 if not owner or not picker then return end
 assert(config.kind=='sp'or owner~=picker and owner:getOnlineID()~=picker:getOnlineID(),'Host requires distinct real actors')
 local root=owner:getInventory()
 assert(not owner:getPrimaryHandItem()and not owner:getSecondaryHandItem(),'generator owner hands must initially be empty')
 assert(not picker:getPrimaryHandItem()and not picker:getSecondaryHandItem(),'generator picker hands must initially be empty')
 local original=assert(root:AddItem('Base.Generator'));original:setFavorite(true);original:setCondition(73)
 original:getModData().fuel=7.5;original:getModData().fixtureAncestry='original'
 local tool=assert(root:AddItem('Base.Razor'))
 if isServer()then sendAddItemToContainer(root,original);sendAddItemToContainer(root,tool)end
 owner:setPrimaryHandItem(original);owner:setSecondaryHandItem(original)
 if isServer()then sendEquip(owner)end
 local square=assert(owner:getCurrentSquare())
 local decoyItem=assert(instanceItem(original:getFullType()));decoyItem:setCondition(41);decoyItem:getModData().fuel=3.25
 local decoy=IsoGenerator.new(decoyItem,getCell(),square)
 assert(root:getItemById(tool:getID())==tool and tool:getContainer()==root,'razor must be in root before observation')
 local ticket=assert(Drop.begin(owner,tool),'generator observation did not begin')
 local equip=ISEquipWeaponAction:new(owner,tool,50,true,false)
 assert(equip:complete(),'stock razor equip failed to drop generator')
 local handle=assert(Drop.finish(ticket,owner,tool),'generator drop had no exact observation')
 local target=assert(Drop.target(handle,owner),'generator observation has no live target')
 assert(target~=decoy and target:getSquare()==square and decoy:getSquare()==square
  and target:getGeneratorItemType()==original:getFullType()and decoy:getGeneratorItemType()==original:getFullType(),
  'same-square generator identities/types differ')
 assert(Drop.target(handle,owner)==target and Drop.target(handle,owner)==target,'live generator observation is not repeatable')
 if picker~=owner then assert(Drop.target(handle,picker)==nil and Drop.target(handle,owner)==target,'foreign actor acquired/revoked original observation')end
 assert(target:getCondition()==73 and math.abs(target:getFuel()-7.5)<.01,'native generator drop lost condition/fuel')
 assert(root:getItemById(original:getID())==nil and owner:getPrimaryHandItem()==tool,'native drop did not consume original/equip razor')
 session.owner,session.picker,session.original,session.tool=owner,picker,original,tool
 session.handle,session.target,session.decoy,session.square=handle,target,decoy,square
 session.ids={case=session.case,x=square:getX(),y=square:getY(),z=square:getZ(),
  objectIndex=target:getObjectIndex(),decoyIndex=decoy:getObjectIndex(),originalId=original:getID(),razorId=tool:getID(),
  owner=role(owner),picker=role(picker),ownerOnlineId=owner:getOnlineID(),pickerOnlineId=picker:getOnlineID(),
  type=original:getFullType(),condition=73,fuel=7.5}
 return session.ids
end
function A.players()return session.peers end
function A.ready(player,case)
 assert(session.ids and case==session.case and session.peers[role(player)]==player,'unprepared generator replica')
 session.ready=session.ready or{};session.ready[role(player)]=true
 return session.ready.client1 and(config.kind=='sp'or session.ready.client2)and true or false
end
function A.started(player,case)
 assert(session.ids and session.ready and session.ready.client1 and(config.kind=='sp'or session.ready.client2)
  and case==session.case and player==session.picker and not session.started,'unexpected generator native start')
 session.started=true
end
function A.verify(player,case)
 assert(session.ids and session.started and case==session.case and player==session.picker,'generator verification before native pickup')
 if session.result then return session.result end
 local owner,picker=session.owner,session.picker
 if session.target:getObjectIndex()~=-1 then return end
 local output=picker:getPrimaryHandItem()
 if not output or output==session.tool or output:getFullType()~=session.ids.type then return end
 assert(picker:getSecondaryHandItem()==output and picker:getInventory():getItemById(output:getID())==output,'generator output not held/canonical')
 assert(output~=session.original and output:getID()~=session.original:getID(),'generator pickup reused original inventory identity')
 assert(output:getCondition()==73 and math.abs((output:getModData().fuel or 0)-7.5)<.01,'generator output condition/fuel differs')
 assert(not output:isFavorite()and output:getModData().fixtureAncestry==nil,'generator pickup unexpectedly preserved favorite/modData')
 assert(session.decoy:getObjectIndex()>=0 and session.decoy:getSquare()==session.square
  and session.decoy:getCondition()==41 and math.abs(session.decoy:getFuel()-3.25)<.01,'same-type decoy changed')
 assert(Drop.target(session.handle,owner)==nil and Drop.target(session.handle,owner)==nil,'lost observation retargeted same-square decoy')
 assert(owner:getInventory():getItemById(session.tool:getID())==session.tool,'owner lost razor inventory item')
 assert(owner:getInventory():getItemById(session.original:getID())==nil
  and picker:getInventory():getItemById(session.original:getID())==nil,'original generator inventory ID returned')
 local ownerKeptRazor=owner:getPrimaryHandItem()==session.tool
 assert(ownerKeptRazor==(config.kind=='mp'),'owner hand result differs between SP and Host')
 local result={case=case,owner=role(owner),picker=role(picker),ownerOnlineId=owner:getOnlineID(),pickerOnlineId=picker:getOnlineID(),
  originalId=session.original:getID(),outputId=output:getID(),type=output:getFullType(),condition=output:getCondition(),fuel=output:getModData().fuel,
  distinctDecoy=session.target~=session.decoy,exactAfterDrop=true,missingAfterTake=true,decoyStillPresent=true,
  ownerKeptRazor=ownerKeptRazor,outputInBothHands=true,sourceFavorite=session.original:isFavorite(),outputFavorite=output:isFavorite()}
 session.result=result
 print('[GENERATOR_DROP] AUTHORITY '..JSON.encode(result))
 return result
end
return A
