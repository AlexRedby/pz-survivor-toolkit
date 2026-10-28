-- All mutations are disposable fixture setup; snapshots only read native state.
local F={cases={'pet-success','pet-cancel','pet-invalid'}}
local placement,placed,active,placementPollAt
local function at(player,target)
 local square=player:getSquare()
 return square and square:getX()==target.x and square:getY()==target.y and square:getZ()==target.z
  and math.floor(player:getX())==target.x and math.floor(player:getY())==target.y and math.floor(player:getZ())==target.z
end
function F.at(player,target)return at(player,target)end
function F.placementTarget(value)
 assert(type(value)=='table','missing local-client placement target')
 local count=0;for key in pairs(value)do assert(key=='x'or key=='y'or key=='z','foreign placement field');count=count+1 end
 assert(count==3,'placement target fields missing')
 for _,key in ipairs({'x','y','z'})do assert(type(value[key])=='number'and value[key]==value[key]and math.abs(value[key])<1000000 and value[key]%1==0,'placement target must contain finite integer coordinates')end
 return {x=value.x,y=value.y,z=value.z}
end
local function float32(value)local color=Color.new();color:set(value,0,0,1);return color:getR()end
-- Read-only native XP event: Java publishes the post-multiplier amount after
-- updating its float32 XP map. Nothing here invokes or replaces a pet callback.
Events.AddXP.Add(function(player,perk,amount)
 if isClient()or not active or active.player~=player or perk~=Perks.Husbandry then return end
 local row={sequence=#active.xpLedger+1,at=getTimestampMs(),amount=amount,before=active.lastXP,
  after=player:getXp():getXP(Perks.Husbandry),petTimer=active.animal:getPetTimer(),
  level=active.ids.baseline.husbandryLevel,acceptance=active.animal:getAcceptanceLevel(player)}
 active.lastXP=row.after;active.xpLedger[#active.xpLedger+1]=row
 print('[ANIMAL_TERMINAL] XP '..(require 'QueueHealthEvents').encode({case=active.ids.case,event=row}))
end)
function F.book(player,ids)
 local item=player:getInventory():getItemById(ids.book.id)
 if item and item:getFullType()==ids.book.type and item:getContainer()==player:getInventory()then return item end
end
function F.animal(ids)
 local animal=getAnimal(ids.animal.online)
 if animal and animal:getAnimalID()==ids.animal.id then return animal end
 -- SP animal lookup is not guaranteed to be indexed by a network ID.
 for x=ids.origin.x-10,ids.origin.x+10 do for y=ids.origin.y-10,ids.origin.y+10 do
  local square=getSquare(x,y,ids.origin.z)
  if square then local list=square:getAnimals();for i=0,list:size()-1 do
   if list:get(i):getAnimalID()==ids.animal.id then return list:get(i)end
  end end
 end end
end
function F.snapshot(state)
 local p,a,b=state.player,state.animal,state.book
 local ledger={};for _,entry in ipairs(state.xpLedger or{})do ledger[#ledger+1]=entry end
 local root={};local items=p:getInventory():getItems()
 for i=0,items:size()-1 do root[#root+1]=items:get(i):getID()end;table.sort(root)
 return {case=state.ids.case,animal=a:getAnimalID(),online=a:getOnlineID(),animalType=a:getAnimalType(),
  acceptance=a:getAcceptanceLevel(p),cooldownReady=a:petTimerDone(),petTimer=a:getPetTimer(),
  ghost=p:isGhostMode(),held=a:isHeld(),husbandryXP=p:getXp():getXP(Perks.Husbandry),
  husbandryLevel=p:getPerkLevel(Perks.Husbandry),xpLedger=ledger,petting=p:getVariableBoolean('petanimal'),
  idleAction=a:getVariableString('idleAction')or'',distance=p:getSquare():DistTo(a:getSquare()),
  book={id=b:getID(),type=b:getFullType(),root=b:getContainer()==p:getInventory(),pages=p:getAlreadyReadPages(b:getFullType()),itemPages=b:getAlreadyReadPages(),total=b:getNumberOfPages()},rootIds=root}
end
function F.prepare(player,caseID,previous,remoteTarget)
 assert(not isClient(),'animal setup requires authority')
 if isServer()then
  local target=F.placementTarget(remoteTarget)
  if placement then
   assert(target.x==placement.x and target.y==placement.y and target.z==placement.z,'local-client placement target changed')
  else
   -- Only the local client can teleport its actor. Authority waits for the
   -- exact target to arrive through ordinary player position replication.
   player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
   placement=target
  end
 end
 if not placement then
  player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
  local square=require('QueueEnergyPlacement')(player)
  placement={x=square:getX(),y=square:getY(),z=square:getZ()}
  return
 end
 if not placed then
  if not at(player,placement)then
   local now=getTimestampMs()
   if not placementPollAt or now-placementPollAt>=5000 then
    placementPollAt=now;local square=player:getSquare()
    print('[ANIMAL_TERMINAL] PLACEMENT_WAIT '..(require 'QueueHealthEvents').encode({target=placement,
     actual={x=player:getX(),y=player:getY(),z=player:getZ()},
     square=square and{x=square:getX(),y=square:getY(),z=square:getZ()}or false}))
   end
   return
  end
  placed=true
  print('[ANIMAL_TERMINAL] PLACEMENT '..(require 'QueueHealthEvents').encode({target=placement,arrived=true,teleports=1}))
 end
 if previous then previous.animal:getBehavior():setBlockMovement(false)end
 local origin=player:getSquare();local target
 local distance=caseID=='pet-invalid'and 6 or 1
 for _,offset in ipairs({{distance,0},{0,distance},{-distance,0},{0,-distance}})do
  local square=getSquare(origin:getX()+offset[1],origin:getY()+offset[2],origin:getZ())
  if square and square:getFloor()and square:isFree(false)and(caseID=='pet-invalid'or origin:canReachTo(square))then target=square;break end
 end
 assert(target,'no loaded reachable native animal fixture square')
 local breed=AnimalDefinitions.getDef('hen'):getBreedByName('rhodeisland')
 local animal=assert(addAnimal(getCell(),target:getX()+.5,target:getY()+.5,target:getZ(),'hen',breed))
 animal:setWild(false);animal:addToWorld();animal:stopAllMovementNow();animal:getBehavior():setBlockMovement(true)
 animal:setDebugAcceptance(player,40)
 assert(animal:canBePet()and animal:petTimerDone(),'fresh animal pet capability/cooldown unavailable')
 local book=assert(player:getInventory():AddItem('Base.BookFirstAid1'))
 local total=book:getNumberOfPages();assert(total>1,'native book has no pages')
 book:setAlreadyReadPages(total-1);player:setAlreadyReadPages(book:getFullType(),total-1);player:setPerkLevelDebug(Perks.Doctor,0)
 local ids={case=caseID,actor=player:getOnlineID(),animal={id=animal:getAnimalID(),online=animal:getOnlineID(),type='hen',breed='rhodeisland'},
  origin={x=origin:getX(),y=origin:getY(),z=origin:getZ()},placement=placement,book={id=book:getID(),type=book:getFullType(),total=total,initial=total-1},duration=400}
 local state={player=player,animal=animal,book=book,ids=ids,xpLedger={},lastXP=player:getXp():getXP(Perks.Husbandry)}
 local mult=SandboxVars.MultiplierConfig or{}
 ids.xpContext={boost=player:getXp():getPerkBoost(Perks.Husbandry),bookMultiplier=player:getXp():getMultiplier(Perks.Husbandry),
  fast=player:hasTrait(CharacterTrait.FAST_LEARNER),slow=player:hasTrait(CharacterTrait.SLOW_LEARNER),
  global=mult.Global or false,globalToggle=mult.GlobalToggle==true,husbandry=mult.Husbandry or false}
 if caseID=='pet-invalid'then
  local gate=assert(player:getInventory():AddItem('Base.BookCarpentry1'));local pages=gate:getNumberOfPages()
  gate:setAlreadyReadPages(pages-1);player:setAlreadyReadPages(gate:getFullType(),pages-1);player:setPerkLevelDebug(Perks.Woodwork,0)
  state.gate=gate;ids.gate={id=gate:getID(),type=gate:getFullType(),total=pages,initial=pages-1}
  if isServer()then sendAddItemToContainer(player:getInventory(),gate)end
 end
 if isServer()then sendAddItemToContainer(player:getInventory(),book)end
 ids.baseline=F.snapshot(state);active=state;return state
end
function F.resolve(player,ids)
 local animal,book=F.animal(ids),F.book(player,ids)
 if not animal or not book or player:getOnlineID()~=ids.actor then return end
 local origin=ids.origin
 if math.floor(player:getX())~=origin.x or math.floor(player:getY())~=origin.y or math.floor(player:getZ())~=origin.z then
  return
 end
 book:setAlreadyReadPages(ids.book.initial);player:setAlreadyReadPages(book:getFullType(),ids.book.initial)
 local state={player=player,animal=animal,book=book,ids=ids}
 if ids.gate then
  local gate=player:getInventory():getItemById(ids.gate.id);if not gate or gate:getFullType()~=ids.gate.type then return end
  gate:setAlreadyReadPages(ids.gate.initial);player:setAlreadyReadPages(gate:getFullType(),ids.gate.initial);state.gate=gate
 end
 return state
end
function F.effect(state,value)
 local success=state.ids.case=='pet-success';local events=value.xpLedger
 if value.animal~=state.ids.animal.id or value.animalType~='hen'or type(events)~='table'then return false end
 if not success then return #events==0 and value.petTimer==0 and value.cooldownReady
  and value.husbandryXP==state.ids.baseline.husbandryXP end
 if #events~=1 or value.cooldownReady or value.petTimer<=0 then return false end
 local event=events[1];local adjustment=event.level*200
 return event.sequence==1 and event.before==state.ids.baseline.husbandryXP and event.amount>0
  and event.after==float32(event.before+event.amount)and value.husbandryXP==event.after
  and event.petTimer%1==0 and event.petTimer>=15000-adjustment and event.petTimer<=24999-adjustment
end
function F.clean(value)return not value.petting and value.idleAction==''end
return F
