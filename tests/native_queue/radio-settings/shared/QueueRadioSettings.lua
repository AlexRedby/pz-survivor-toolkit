local Fixture={}
local cases={reorder=true,cancel=true,barrier=true}

local function identity(device)
 local square=assert(device:getSquare())
 return {x=square:getX(),y=square:getY(),z=square:getZ(),index=device:getObjectIndex()}
end

local function radio(square)
 local object=IsoRadio.new(getCell(),square,assert(getSprite('appliances_radio_01_0')))
 square:AddSpecialObject(object)
 local data=assert(object:getDeviceData())
 data:setIsBatteryPowered(false);data:setIsPortable(false);data:setIsTelevision(false)
 data:setIsTwoWay(true);data:setNoTransmit(false);data:setPower(1)
 data:setMinChannelRange(88000);data:setMaxChannelRange(108000)
 data:setChannelRaw(90000);data:setDeviceVolumeRaw(.5);data:setMicIsMuted(false)
 data:setTurnedOnRaw(true)
 local presets=data:getDevicePresets();presets:clearPresets()
 presets:addPreset('Queue A',95000);presets:addPreset('Queue B',96000)
 assert(data:getParent()==object and data:isIsoDevice() and data:getPower()>0)
 return object,data
end

function Fixture.prepare(player,case,mode,previous)
 assert(cases[case] and (mode=='native' or mode=='toolkit'),'unknown radio-settings selection')
 local origin=require('QueueEnergyPlacement')(player)
 local x,y,z=origin:getX(),origin:getY(),origin:getZ()
 local generator=IsoGenerator.new(assert(instanceItem('Base.Generator')),getCell(),getCell():getGridSquare(x,y+1,z))
 generator:setCondition(100);generator:setFuel(10);generator:setActivated(true)
 local a,dataA=radio(getCell():getGridSquare(x+1,y,z))
 local b,dataB=radio(getCell():getGridSquare(x-1,y,z))
 assert(a:getSquare():haveElectricity() and b:getSquare():haveElectricity()
  and dataA:canBePoweredHere() and dataB:canBePoweredHere(),'radio fixture has no mains power')
 if isServer() then a:transmitCompleteItemToClients();b:transmitCompleteItemToClients() end
 local ids={case=case,mode=mode,a=identity(a),b=identity(b)}
 return {player=player,a=a,b=b,dataA=dataA,dataB=dataB,generator=generator,ids=ids}
end

local function resolveDevice(id)
 local square=getCell():getGridSquare(id.x,id.y,id.z)
 if not square then return end
 for i=0,square:getObjects():size()-1 do
  local object=square:getObjects():get(i)
  if object:getObjectIndex()==id.index and instanceof(object,'IsoRadio') then return object end
 end
end

function Fixture.resolve(player,ids)
 local a,b=resolveDevice(ids.a),resolveDevice(ids.b)
 if not a or not b then return end
 -- The server's fixture teleport does not position the owning client synchronously.
 -- Arrange the local actor before invoking the real walk-to callbacks.
 local x,y,z=(ids.a.x+ids.b.x)/2,ids.a.y,ids.a.z
 if math.floor(player:getX())~=x or math.floor(player:getY())~=y or math.floor(player:getZ())~=z then
  player:teleportTo(x+.5,y+.5,z)
  return
 end
 local dataA,dataB=a:getDeviceData(),b:getDeviceData()
 for _,data in ipairs({dataA,dataB}) do
  if not data:getIsTurnedOn() or data:getPower()<=0 or not data:canBePoweredHere()
   or not data:getIsTwoWay() or data:isNoTransmit() or data:getChannel()~=90000
   or math.abs(data:getDeviceVolume()-.5)>.00001 or data:getMicIsMuted() then return end
 end
 return {player=player,a=a,b=b,dataA=dataA,dataB=dataB,ids=ids}
end

function Fixture.snapshot(state)
 local result={case=state.ids.case,devices={}}
 for _,name in ipairs({'a','b'}) do
  local device=state[name];local row=identity(device);local original=state.ids[name]
  for key,value in pairs(original) do assert(row[key]==value,'radio world identity changed') end
  assert(resolveDevice(original)==device,'radio object was replaced')
  local data=device:getDeviceData()
  assert(data==(name=='a' and state.dataA or state.dataB) and data:getParent()==device,'radio DeviceData replaced')
  row.volume,row.channel,row.micMuted=data:getDeviceVolume(),data:getChannel(),data:getMicIsMuted()
  row.on,row.powered=data:getIsTurnedOn(),data:getPower()>0 and data:canBePoweredHere()
  result.devices[name]=row
 end
 return result
end

function Fixture.expected(case,mode,server)
 assert(cases[case] and (mode=='native' or mode=='toolkit'),'unknown radio outcome')
 return {a={volume=case=='barrier' and 0 or mode=='toolkit' and .25 or .75,channel=95000,
   micMuted=not server and case~='barrier' and (case~='cancel' or mode=='native')},
  b={volume=.25,channel=96000,micMuted=false}}
end

function Fixture.verify(state,server)
 local receipt=Fixture.snapshot(state);local expected=Fixture.expected(state.ids.case,state.ids.mode,server)
 for name,values in pairs(expected) do
  local row=receipt.devices[name]
  if not row.on or not row.powered or math.abs(row.volume-values.volume)>.00001
   or row.channel~=values.channel or row.micMuted~=values.micMuted then return nil,receipt end
 end
 return receipt
end

return Fixture
