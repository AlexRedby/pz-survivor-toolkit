local config=require 'QueueTestSelection'
require 'Util/AdjacentFreeTileFinder'
local Fixture=require 'TagFixture'
local json=require 'TagTestEvents'
local states,slots,staging,anchor,nextSlot={},{},{},nil,0
if config.tagRestart then
 for name,expected in pairs(config.tagRestart) do
  local value=expected.setup
  local original={};for _,entry in ipairs(expected.original) do original[entry.id]=entry.count end
  states[name]={owner=name,x=value.x,y=value.y,z=value.z,index=value.index,sourceID=value.source,
   battery=value.battery,apple=value.apple,beans=value.beans,steak=value.steak,
   ruleRevision=value.revision,manualCategory=value.manualCategory,manual=expected.manual,original=original,
   startX=expected.start.x,startY=expected.start.y,startZ=expected.start.z}
 end
end
local placementPlayers,placementAcks,placementSignature={},{},nil
local readyWaitAt={}
local function readyWait(player,reason,state,target)
 local name=player:getUsername();local now=getTimestampMs()
 if readyWaitAt[name] and now-readyWaitAt[name]<1000 then return end
 readyWaitAt[name]=now
 local current=player:getCurrentSquare()
 print('[TAG_READY_WAIT] '..json.encode({actor=name,reason=reason,
  start=state and {x=state.startX,y=state.startY,z=state.startZ} or false,
  crate=state and {x=state.x,y=state.y,z=state.z,index=state.index} or false,
  current=current and {x=current:getX(),y=current:getY(),z=current:getZ()} or false,
  targetLoaded=target~=nil,currentIsTarget=current~=nil and current==target}))
end
local function placement()
 local names={};for name in pairs(staging) do names[#names+1]=name end;table.sort(names)
 if #names~=2 then return end
 local squares,signature={},{}
 for _,name in ipairs(names) do
  for _,kind in ipairs({'start','crate'}) do
   local square=staging[name][kind]
   squares[#squares+1]={x=square:getX(),y=square:getY(),z=square:getZ()}
   signature[#signature+1]=name..':'..kind..':'..square:getX()..','..square:getY()..','..square:getZ()
  end
 end
 signature=table.concat(signature,';')
 if signature~=placementSignature then placementSignature=signature;placementAcks={} end
 return {signature=signature,squares=squares},names
end
local function stagedPlayer(name)
 local player,pair=placementPlayers[name],staging[name]
 return player and pair and player:getCurrentSquare()==pair.start and Fixture.startFree(pair.start,player)
end
local function placementReady()
 local packet,names=placement();if not packet then return false end
 local ready=true
 for _,name in ipairs(names) do
  if not stagedPlayer(name) then ready=false
  elseif placementAcks[name]~=packet.signature then
   sendServerCommand(placementPlayers[name],'TagBaseline','Placement',packet);ready=false
  end
 end
 return ready
end
local function makeBox(player,square)
 if Fixture.crateSquare(player)~=square then return end
 local start=player:getCurrentSquare()
 local obj=IsoThumpable.new(getCell(),square,Fixture.crateSprite,false,{})
 obj:setBlockAllTheSquare(true);obj:setIsContainer(true)
 local container=assert(obj:getContainer(),'fixture crate container missing')
 container:setType('crate');container:setCapacity(100);container:setExplored(true)
 obj:getModData().PZSTTagFixtureOwner=player:getUsername()
 square:AddSpecialObject(obj);obj:transmitCompleteItemToClients();obj:transmitModData()
 assert(player:getCurrentSquare()==start and start:canStand(),'fixture crate invalidated player starting floor')
 print('[TAG_PLACEMENT] '..json.encode({actor=player:getUsername(),sprite=Fixture.crateSprite,
  player={x=start:getX(),y=start:getY(),z=start:getZ()},crate={x=square:getX(),y=square:getY(),z=square:getZ()}}))
 return obj
end
local function packet(state)
 return {x=state.x,y=state.y,z=state.z,index=state.index,owner=state.owner,
  battery=state.battery,apple=state.apple,beans=state.beans,steak=state.steak,source=state.sourceID,revision=state.ruleRevision,manualCategory=state.manualCategory}
end
local function ownedBox(state,square)
 local box=Fixture.object(packet(state),state.owner)
 if box then return box end
 local found
 local objects=square:getObjects()
 for index=0,objects:size()-1 do
  local object=objects:get(index)
  if object and object:getSquare()==square and object:hasModData()
   and object:getModData().PZSTTagFixtureOwner==state.owner
   and object:getContainerCount()>0 and object:getContainerByIndex(0) then
   if found then return nil,'multiple owned crate objects' end
   found=object
  end
 end
 if found then state.index=found:getObjectIndex() end
 return found,'owned crate object missing'
end
local function ready(player,args)
 local name=player:getUsername()
 if config.tagRestart then assert(states[name],'restart may only resolve the original fixture owner') end
 if args.reconnect and not states[name] then error('reconnect fixture state missing; refusing duplicate fixture creation') end
 local state=states[name]
 if state then state.player=player end
 local current=player:getCurrentSquare()
 if not current then readyWait(player,'player square missing',state);return end
 placementPlayers[name]=player
 anchor=anchor or {x=current:getX(),y=current:getY(),z=current:getZ()}
 if slots[name]==nil then slots[name]=nextSlot;nextSlot=nextSlot+1 end
 local pair=staging[name]
 if state then
  -- Chunk unloads may pool square objects; only persisted coordinates identify staging.
  local start=getCell():getGridSquare(state.startX,state.startY,state.startZ)
  if not start then readyWait(player,'start square missing',state);return end
  local crate=getCell():getGridSquare(state.x,state.y,state.z)
  if not crate then readyWait(player,'crate square missing',state,start);return end
  local box,reason=ownedBox(state,crate)
  if not box then readyWait(player,reason,state,start);return end
  state.box=box;pair={start=start,crate=crate};staging[name]=pair
 end
 if not states[name] and pair and Fixture.crateSquare(player,pair.start)~=pair.crate then pair=nil;staging[name]=nil end
 if not pair then
  pair=Fixture.stagePair(player,{x=anchor.x+slots[name]*8,y=anchor.y,z=anchor.z},staging,name)
  if not pair then readyWait(player,'valid staging pair missing',state);return end
  staging[name]=pair
  print('[TAG_STAGING] '..json.encode({actor=name,intended={x=anchor.x+slots[name]*8,y=anchor.y,z=anchor.z},
   selected={x=pair.start:getX(),y=pair.start:getY(),z=pair.start:getZ()},
   crate={x=pair.crate:getX(),y=pair.crate:getY(),z=pair.crate:getZ()}}))
 end
 local target=pair.start
 if not Fixture.startFree(target,player) then readyWait(player,'start square unavailable',state,target);return end
 if current:getX()~=target:getX() or current:getY()~=target:getY() or current:getZ()~=target:getZ() then
  readyWait(player,'positioning player at start',state,target)
  Fixture.position(player,target:getX()+0.5,target:getY()+0.5,target:getZ())
  sendServerCommand(player,'TagBaseline','Position',{x=target:getX()+0.5,y=target:getY()+0.5,z=target:getZ()})
  return
 end
 if not states[name] then
  if not placementReady() then readyWait(player,'placement acknowledgements pending',state,target);return end
  local inv=player:getInventory();local original=Fixture.counts(inv)
  local box=makeBox(player,pair.crate);if not box then return end
  local source,sourceID=inv,nil
  do
   local bag=assert(inv:AddItem('Base.Bag_Schoolbag'),'fixture source bag missing')
   bag:getModData().PZSTTagFixtureOwner=name;sendAddItemToContainer(inv,bag)
   source,sourceID=bag:getInventory(),bag:getID()
  end
  local state={box=box,source=source,sourceID=sourceID,original=original,owner=name,player=player,
   startX=target:getX(),startY=target:getY(),startZ=target:getZ()}
  for _,entry in ipairs({{'battery','Base.Battery'},{'apple','Base.Apple'},{'beans','Base.TinnedBeans'},{'steak','Base.Steak'}}) do
   if config.tagRules or entry[1]=='battery' or entry[1]=='apple' then
    local item=assert(source:AddItem(entry[2]),'fixture item missing '..entry[2])
    item:getModData().PZSTTagFixtureOwner=name
    state[entry[1]]=item:getID();sendAddItemToContainer(source,item)
   end
  end
  local square=box:getSquare()
  state.x,state.y,state.z,state.index=square:getX(),square:getY(),square:getZ(),box:getObjectIndex()
  states[name]=state
 end
 local state=states[name]
 state.player=player
 local bag=Fixture.find(player:getInventory(),state.sourceID)
 if not bag then readyWait(player,'owned source bag missing',state,target);return end
 assert(bag:getModData().PZSTTagFixtureOwner==name,'reconnected source bag owner differs')
 local box=Fixture.object(packet(state),name)
 if not box then readyWait(player,'owned crate object missing after reacquire',state,target);return end
 state.source,state.box=bag:getInventory(),box
 state.reconnected=state.reconnected or args.reconnect==true
 sendServerCommand(player,'TagBaseline','Setup',packet(state))
end
local function setAt(md,field) return md[field] and md[field]['0'] or {} end
local function copySet(source)
 local result={};for key,value in pairs(source) do result[key]=value end;return result
end
local function sameSet(actual,expected)
 for key,value in pairs(expected) do if actual[key]~=value then return false end end
 for key,value in pairs(actual) do if expected[key]~=value then return false end end
 return true
end
local function verifyRules(state)
 local Rules=require 'PZSurvivorToolkit/QuartermasterTagRules'
 assert(Fixture.sameRule(Rules.getBox(state.box,0)),'server dynamic rule changed')
 local cats=assert(LootSorter.getBoxCats and LootSorter.getBoxCats(state.box,0)
  or state.box:getModData().LSBox and state.box:getModData().LSBox['0'],'server manual categories absent')
 assert(state.manualCategory and cats[state.manualCategory] and not cats.food and not cats.perishable and not cats.meat,'manual categories changed or tag IDs leaked')
 local md=state.box:getModData();assert(state.manual,'manual designation was not captured')
 for _,field in ipairs({'LSBox','LSBoxItems','LSBoxPresets'}) do
  assert(sameSet(setAt(md,field),state.manual[field]),'native precise designation changed '..field)
 end
 assert((md.LSBoxPriority and md.LSBoxPriority['0'] or 0)==state.manual.priority,'native priority changed')
 return Rules.getBoxRevision(state.box,0)
end
local function verifyItems(state,phase)
 assert(state.manualCategory and state.box:getModData().LSBox['0'][state.manualCategory],'native Battery designation absent on authority')
 local status,reason,fixtureIDs,source,destination=Fixture.receipt(state.source,state.box:getContainerByIndex(0),state,phase)
 assert(status~='invalid',reason)
 local all=Fixture.counts(state.player:getInventory())
 assert(all[state.sourceID]==1,'fixture source bag left inventory')
 for id,count in pairs(state.original) do
  assert(all[id]==count and not destination[id],'original inventory changed '..tostring(id))
 end
 for _,key in ipairs({'battery','apple','beans','steak'}) do
  local id=state[key]
  if id then assert((all[id] or 0)==(source[id] or 0),'fixture ID duplicated/moved outside owned bag '..key) end
 end
 state.receiptWaiting=state.receiptWaiting or {}
 if status=='pending' then
  local began=state.receiptWaiting[phase] or getTimestampMs();state.receiptWaiting[phase]=began
  assert(getTimestampMs()-began<15000,'authority receipt timeout '..phase..' '..tostring(reason))
  local value={actor=state.owner,phase=phase,reason=reason,ids=fixtureIDs}
  print('[TAG_RECEIPT_PENDING] '..json.encode(value))
  sendServerCommand(state.player,'TagBaseline','Pending',value)
  return
 end
 state.receiptWaiting[phase]=nil
 print('[TAG_RECEIPT] '..json.encode({actor=state.owner,phase=phase,ids=fixtureIDs,exact=true,originalInventoryUnchanged=true,reconnected=state.reconnected or false}))
 if config.tagRestartSeed and state.reconnected and phase=='enabled' and not state.restartSeedLogged then
  local original={};for id,count in pairs(state.original) do original[#original+1]={id=id,count=count} end
  print('[TAG_RESTART_SEED] '..json.encode({actor=state.owner,setup=packet(state),
   start={x=state.startX,y=state.startY,z=state.startZ},original=original,manual=state.manual}))
  state.restartSeedLogged=true
 end
 sendServerCommand(state.player,'TagBaseline','Verified',{ok=true,phase=phase,ids=fixtureIDs})
end
local function peers()
 for name,state in pairs(states) do
  if state.ruleRevision then
   for otherName,other in pairs(states) do
    if otherName~=name and other.ruleRevision then
     local value=packet(other);value.revision=other.ruleRevision
     sendServerCommand(state.player,'TagBaseline','Peer',value)
    end
   end
  end
 end
end
Events.OnServerStarted.Add(function() print('[QUEUE_TEST] SERVER_READY') end)
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='TagBaseline' or not player then return end
 local ok,err=pcall(function()
  if command=='Ready' then ready(player,args or {});return end
  if command=='PlacementReady' then
   local packet=placement();local name=player:getUsername()
   if packet and type(args)=='table' and args.signature==packet.signature
    and placementPlayers[name]==player and stagedPlayer(name) then
    placementAcks[name]=packet.signature
    print('[TAG_PLACEMENT_READY] '..json.encode({actor=name,signature=packet.signature}))
   end
   return
  end
  local state=assert(states[player:getUsername()],'fixture not ready')
  assert(state.box:getModData().PZSTTagFixtureOwner==state.owner,'fixture crate owner changed')
  if command=='ManualCategory' then
   assert(type(args.category)=='string' and #args.category>0 and #args.category<=160,'invalid fixture manual category')
   local cats=setAt(state.box:getModData(),'LSBox')
   if not (cats[args.category] and cats.toolElectrical and cats.craftingElectrical_material) then return end
   state.manualCategory=args.category
   sendServerCommand(player,module,'ManualCategory',{ok=true})
  elseif command=='CaptureManual' then
   local md=state.box:getModData();if not state.manualCategory or not setAt(md,'LSBox')[state.manualCategory] then return end
   state.manual={priority=md.LSBoxPriority and md.LSBoxPriority['0'] or 0}
   for _,field in ipairs({'LSBox','LSBoxItems','LSBoxPresets'}) do state.manual[field]=copySet(setAt(md,field)) end
   sendServerCommand(player,module,'ManualCaptured',{ok=true})
  elseif command=='Verify' then verifyItems(state,config.tagRules and args.phase or 'baseline')
  elseif command=='VerifyRule' then
   local revision=verifyRules(state)
   if args.phase=='saved' then state.ruleRevision=revision
   else assert(revision==state.ruleRevision,'stale command mutated authoritative revision') end
   if config.tagRestart then
    print('[TAG_RESTART_VERIFIED] '..json.encode({actor=state.owner,phase=args.phase,revision=revision,
     rule=require('PZSurvivorToolkit/QuartermasterTagRules').getBox(state.box,0),setup=packet(state)}))
   end
   sendServerCommand(player,module,'RuleVerified',{ok=true,phase=args.phase,revision=revision})
   peers()
  elseif command=='Peers' then peers() end
 end)
 if not ok then
  print('[QUEUE_TEST] FAIL tag authority '..tostring(err))
  sendServerCommand(player,module,'Error',{reason=tostring(err)})
 end
end)
