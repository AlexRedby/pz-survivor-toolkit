local Clothing={}
local watched,installed
function Clothing.watch(state)watched=state end
function Clothing.observeLine(state,line)
 if not state or type(line)~='string'then return end
 local actor,session,message=line:match('^%[P4TidyUpMeister%]%[P(%d+)%]%[S([%d%-]+)%] (.+)$')
 if tonumber(actor)~=state.player:getPlayerNum()then return end
 local proof=state.clothingP4
 if session=='-'then
  local completed=tonumber(message:match('^restore queue complete S(%d+)$'))
  if proof and proof.restore and completed==proof.session then proof.completed=true end
  return
 end
 session=tonumber(session)
 if not session or session<=0 then return end
 local sock='Base.Socks_Ankle#'..state.clothingSocks:getID()..'@'..state.root:getType()
 if message:find('^capture worn=%[')and message:find(tostring(state.clothingLocation)..'='..sock,1,true)then
  if proof then proof.problem='duplicate P4 clothing capture';return end
  proof={session=session};state.clothingP4=proof
 end
 if not proof or proof.session~=session then return end
 if message:find('^add%[%w+%] type=ISUnequipAction item=')and message:find(sock,1,true)then proof.unequip=true end
 if message:find('^add%[%w+%] type=ISCutHair item=nil$')then proof.producer=true end
 if message:find('^RESTORE actionTotal=')then
  if proof.restore or not proof.unequip or not proof.producer then proof.problem='P4 restore missing native clothing producer evidence' end
  proof.restore=true
 end
end
function Clothing.install(withP4)
 if installed or not withP4 then return end
 local options=assert(PZAPI.ModOptions:getOptions('P4TidyUpMeister'),'P4 options unavailable')
 assert(options:getOption('DebugOutput'),'P4 debug option unavailable').selected=2
 local original=print
 print=function(...)
  if select('#',...)==1 then Clothing.observeLine(watched,(...))end
  return original(...)
 end
 installed=true
end
function Clothing.prepare(state,seed)
 seed('clothingSocks','Base.Socks_Ankle')
 local item=state.clothingSocks
 state.clothingLocation=item:getBodyLocation()
 assert(item:getCategory()=='Clothing' and item:canBeEquipped()==nil and state.clothingLocation
  and not item:hasTag(ItemTag.WEARABLE)and not item:hasTag(ItemTag.REPLACE_PRIMARY),'ordinary socks fixture required')
 state.player:setWornItem(state.clothingLocation,item)
 local visual=state.player:getHumanVisual()
 state.clothingHair=state.ids and assert(state.ids.clothingHair,'authoritative clothing hair style missing')
  or (state.player:isFemale()and 'Bob'or 'CrewCut')
 local styles=getHairStylesInstance()
 local style=state.player:isFemale() and styles:FindFemaleStyle(state.clothingHair) or styles:FindMaleStyle(state.clothingHair)
 assert(style and tostring(style:getName())==state.clothingHair and not style:isAttachedHair(),'plain native hair definition required')
 for _,name in ipairs({'Bald','Mohawk','Spike','Greased','Buffont'})do
  assert(not tostring(style:getName()):find(name,1,true),'haircut fixture must not consume styling items or reset hair color')
 end
 if isClient()then
  assert(tostring(visual:getHairModel())==state.clothingHair and not visual:getNonAttachedHair(),
   'client has not adopted authoritative plain hair setup')
 else
  -- Disposable-character setup, like seeding socks/hands. The tested native
  -- haircut later requests this same validated style without consumables.
  visual:setNonAttachedHair(nil);visual:setHairModel(state.clothingHair);state.player:resetModel()
  if isServer()then sendHumanVisual(state.player)end
 end
end
function Clothing.available(player,ids)
 return type(ids.clothingHair)=='string'and tostring(player:getHumanVisual():getHairModel())==ids.clothingHair
  and not player:getHumanVisual():getNonAttachedHair()
end
function Clothing.enqueue(state,helpers)
 require 'TimedActions/ISCutHair'
 -- This is an explicit native-constructor fixture, not a natural menu flow that
 -- removes socks. Genuine native actions temporarily unequip the socks and cut
 -- the unchanged plain hair style. P4's public queue observer sees ISCutHair and
 -- arms restoreWorn; only P4 itself may construct the eventual ISWearClothing.
 helpers.run(function()
  state.clothingUnequip=ISUnequipAction:new(state.player,state.clothingSocks,50)
  ISTimedActionQueue.add(state.clothingUnequip)
  state.clothingProducer=ISCutHair:new(state.player,state.clothingHair,nil,100)
  ISTimedActionQueue.add(state.clothingProducer)
 end)
 assert(state.clothingUnequip.maxTime==50 and state.clothingProducer.maxTime==100
  and state.clothingProducer.complete==ISCutHair.complete,'native constructor durations/effects changed')
end
function Clothing.observe(state,queue,toolkit,tidy)
 local current=queue.current
 if current==state.clothingProducer and current:isStarted()then state.clothingProducerStarted=true end
 for _,action in ipairs(queue.queue)do
  if getmetatable(action)==ISWearClothing and action.Type=='ISWearClothing'and action.item
    and action.item:getID()==state.clothingSocks:getID()then
   assert(tidy and action~=state.clothingProducer,'unexpected non-P4 clothing restoration')
   local source=state.clothingP4
   assert(source and source.restore and not source.problem,'socks wear lacks real source-owned P4 restore evidence')
   assert(not state.clothingRestoreAction or state.clothingRestoreAction==action,'P4 queued duplicate socks restores')
   state.clothingRestoreAction=action
   if toolkit.Settings.actionQueue()then
    local _,kind=toolkit.ActionQueueDefinitions.inspect(action)
    assert(kind=='compat.tidy-equipment','P4 wear lacks verified scoped origin')
   end
   if isClient()and not state.clothingRestoreReceipt then
    state.clothingRestoreReceipt=toolkit.ActionQueueAcknowledgements.capture(action)
   end
  end
 end
end
function Clothing.evidence(state,toolkit,tidy,completion)
 assert(state.clothingProducerStarted,'native haircut producer was never observed running')
 local result=Clothing.verify(state,tidy)
 result.nativeGenerated=state.clothingRestoreAction and 1 or 0
 assert(result.nativeGenerated==(tidy and 1 or 0),'P4 did not generate exactly one socks restore')
 if tidy and isClient()then
  local receipt=assert(state.clothingRestoreReceipt,'P4 clothing restore native receipt not captured')
  assert(toolkit.ActionQueueAcknowledgements.observe(state.clothingRestoreAction,receipt)=='completed',
   'P4 clothing restore lacks authoritative completion')
 end
 result.authoritativeRestore=tidy and isClient()or false
 local source=state.clothingP4
 assert(not tidy or source and source.restore and source.completed and not source.problem,
  'P4 source-owned restore session did not complete')
 result.sourceSession=source and source.session or false
 result.sourceCompleted=tidy and source.completed or false
 result.sharedCompletion=completion
 result.unrelatedTailPreserved=true
 return result
end
function Clothing.settled(state,toolkit,tidy)
 local live=state.root:getItemById(state.clothingSocks:getID())
 if not live or live:getFullType()~='Base.Socks_Ankle'or live:getContainer()~=state.root then return false end
 if (state.player:getWornItem(state.clothingLocation)==live)~=tidy then return false end
 if tidy then
  if not state.clothingRestoreAction then return false end
  local source=state.clothingP4
  if not source or not source.completed or source.problem then return false end
  if isClient()and (not state.clothingRestoreReceipt
   or toolkit.ActionQueueAcknowledgements.observe(state.clothingRestoreAction,state.clothingRestoreReceipt)~='completed')then return false end
 end
 return true
end
function Clothing.verify(state,restored)
 local player,item=state.player,state.clothingSocks
 local live=assert(state.root:getItemById(item:getID()),'exact socks identity missing from root')
 assert(live:getFullType()=='Base.Socks_Ankle' and live:getContainer()==state.root,'socks type/container changed')
 assert((player:getWornItem(state.clothingLocation)==live)==restored,'exact socks worn slot differs')
 assert(tostring(player:getHumanVisual():getHairModel())==state.clothingHair,'native haircut changed the requested existing style')
 assert(player:getPrimaryHandItem()==state.hammer and player:getSecondaryHandItem()==state.screwdriver,
  'clothing restoration changed unrelated hands')
 return {id=live:getID(),fullType=live:getFullType(),bodyLocation=tostring(state.clothingLocation),container='root',
  worn=restored,producer='ISCutHair',producerCompleted=true,hairUnchanged=true,hairStyle=state.clothingHair,unrelatedHandsPreserved=true}
end
return Clothing
