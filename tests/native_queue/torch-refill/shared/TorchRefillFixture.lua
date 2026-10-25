local config=require 'QueueTestSelection'
local Retention=require 'PZSurvivorToolkit/ItemRetention'
local Spawn=require 'PinnedItemsFixture'
local F={module='TorchRefillTest'}
function F.prepare(player)
 local case=config.cases[1]
 local state={player=player,case=case,retained=case~='trunk-unmarked'}
 local source
 if case=='root-retained'then source=player:getInventory()
 else
  Spawn.types={'Base.BlowTorch','Base.PropaneTank'}
  state.vehicle,source=Spawn.spawn(player,true,3,48)
 end
 state.source=source
 if case=='root-retained'then
  state.torch=assert(source:AddItem('Base.BlowTorch'));state.tank=assert(source:AddItem('Base.PropaneTank'))
 else state.torch=source:getItems():get(0);state.tank=source:getItems():get(1)end
 state.torch:setCurrentUses(1);state.tank:setCurrentUses(state.tank:getMaxUses())
 Retention.apply(state.torch,state.retained)
 state.sourceID,state.tankID=state.torch:getID(),state.tank:getID()
 state.torchBefore,state.tankBefore=state.torch:getCurrentUses(),state.tank:getCurrentUses()
 state.torchMax,state.tankMax=state.torch:getMaxUses(),state.tank:getMaxUses()
 -- B42.21 zombie.ZomboidGlobals initializes refillBlowtorchPropaneAmount to 70.
 -- Java static fields are not exposed through the Lua ZomboidGlobals table.
 local full=state.torchMax*70
 local held=state.torch:getCurrentUsesFloat()*full
 local added=math.min(full-held,state.tankBefore)
 state.expectedTorchFloat=(held+added)/full;state.expectedTankUses=math.floor(state.tankBefore-added+.5)
 local area=state.vehicle and state.vehicle:getAreaCenter(state.vehicle:getPartById('TruckBed'):getArea())
 state.packet={case=case,sourceID=state.sourceID,tankID=state.tankID,
  torchBefore=state.torchBefore,tankBefore=state.tankBefore,torchMax=state.torchMax,tankMax=state.tankMax,
  expectedTorchFloat=state.expectedTorchFloat,expectedTankUses=state.expectedTankUses,
  truckId=state.vehicle and state.vehicle:getId()or -1,
  x=area and area:getX()or player:getX(),y=area and area:getY()or player:getY()}
 if isServer()then
  if state.vehicle then sendItemsInContainer(state.vehicle,source)
  else sendAddItemToContainer(source,state.torch);sendAddItemToContainer(source,state.tank)end
 end
 return state
end
function F.resolve(packet,player)
 local source=player:getInventory();local vehicle
 if packet.case~='root-retained'then
  vehicle=getVehicleById(packet.truckId)
  local part=vehicle and vehicle:getPartById('TruckBed');source=part and part:getItemContainer()
 end
 if not source then return end
 local torch,tank=source:getItemById(packet.sourceID),source:getItemById(packet.tankID)
 if not torch or not tank then return end
 return {player=player,source=source,vehicle=vehicle,packet=packet,case=packet.case,
  retained=packet.case~='trunk-unmarked',sourceID=packet.sourceID,tankID=packet.tankID,
  torchBefore=packet.torchBefore,tankBefore=packet.tankBefore,torchMax=packet.torchMax,tankMax=packet.tankMax,
  expectedTorchFloat=packet.expectedTorchFloat,expectedTankUses=packet.expectedTankUses}
end
function F.receipt(state)
 local root,source=state.player:getInventory(),state.source
 local pools=source==root and {root}or {source,root}
 local outputs,tanks={},{}
 for _,pool in ipairs(pools)do
  if pool:getItemWithIDRecursiv(state.sourceID)then return nil,'old torch still exists'end
  local items=pool:getItems()
  for index=0,items:size()-1 do
   local item=items:get(index)
   if item:getFullType()=='Base.BlowTorch'then outputs[#outputs+1]=item end
   if item:getFullType()=='Base.PropaneTank'then tanks[#tanks+1]=item end
  end
 end
 if #outputs~=1 or #tanks~=1 then return nil,'torch/tank count changed'end
 local output,tank=outputs[1],tanks[1]
 if output:getContainer()~=source or tank:getContainer()~=source then return nil,'items not returned'end
 if output:getID()==state.sourceID or tank:getID()~=state.tankID then return nil,'identity mismatch'end
 if Retention.isRetained(output)~=state.retained then return nil,'retention mismatch'end
 if math.abs(output:getCurrentUsesFloat()-state.expectedTorchFloat)>.0001
  or tank:getCurrentUses()~=state.expectedTankUses then return nil,'exact native fuel mismatch'end
 return {case=state.case,sourceID=state.sourceID,outputID=output:getID(),tankID=tank:getID(),
  retained=Retention.isRetained(output),sourceRemoved=true,returned=true,tankReturned=true,
  fuelExact=true,conserved=true,torchUses=output:getCurrentUses(),tankUses=tank:getCurrentUses(),
  torchBefore=state.torchBefore,tankBefore=state.tankBefore}
end
function F.diagnostic(state)
 local rows={}
 local root=state.player:getInventory()
 for _,pool in ipairs(state.source==root and {root}or {state.source,root})do
  local items=pool:getItems()
  for index=0,items:size()-1 do
   local item=items:get(index)
   if item:getFullType()=='Base.BlowTorch'or item:getFullType()=='Base.PropaneTank'then
    rows[#rows+1]={id=item:getID(),fullType=item:getFullType(),root=pool==root,source=pool==state.source,
     retained=Retention.isRetained(item),uses=item:getCurrentUses()}
   end
  end
 end
 return rows
end
return F
