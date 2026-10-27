local JSON=require 'QueueHealthEvents'
local F={module='LotStreamingTest',seed='PZ-Lot-Qualification-42.21',cells='42,39;43,39',
 chunks='1354,1260;1386,1260',record='PZLotStreamingQualification',start={10835,10144},away={11107,10144}}
function F.emit(event,value)print('[LOT_STREAMING] '..event..' '..JSON.encode(value))end
function F.probe(event,role,phase,payload)
 assert(type(payload)=='string'and payload:find('"ok":true',1,true),'Native probe failed: '..tostring(payload))
 print('[LOT_STREAMING] '..event..' {"role":'..JSON.encode(role)..',"phase":'..JSON.encode(phase)..',"probe":'..payload..'}')
 return payload
end
function F.snapshot(role,phase)
 assert(lotQualSnapshot,'Native snapshot probe unavailable')
 return F.probe('SNAPSHOT',role,phase,lotQualSnapshot(F.cells))
end
function F.baseline(config,role)
 local prior=ModData.get(F.record)
 if config.cases[1]=='reload'then
  assert(prior and prior.seed==F.seed and type(prior.snapshot)=='string','Saved authoritative fixture baseline missing')
  F.probe('BASELINE',role,'saved',prior.snapshot)
 else assert(not prior or not prior.snapshot,'Fresh fixture unexpectedly restored prior state')end
end
function F.store(snapshot)
 local record=ModData.getOrCreate(F.record)
 record.seed,record.snapshot=F.seed,snapshot
end
function F.near(player,target)
 return math.abs(player:getX()-target[1]-.5)<=3 and math.abs(player:getY()-target[2]-.5)<=3
end
return F
