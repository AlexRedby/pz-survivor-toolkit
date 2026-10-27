local JSON=require 'QueueHealthEvents'
-- Installed Muldraugh objects.lua authors large/small wildlife polylines in these cells.
-- This covers authored geometry and natural generated bits, not creation of random paths.
local F={module='LotStreamingTest',seed='PZ-Lot-Qualification-42.21',cells='40,34;41,34',
 chunks='1295,1096;1319,1096',record='PZLotStreamingQualification',start={10323,8752},away={10595,8752}}
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
  assert(prior and prior.schema==1 and prior.seed==F.seed and type(prior.snapshot)=='string','Saved authoritative fixture baseline missing')
  assert(#prior.snapshot<=8192 and prior.snapshot:find('"kind":"lot-streaming-baseline"',1,true),'Saved compact baseline schema/byte bound differs')
  F.probe('BASELINE',role,'saved',prior.snapshot)
 else assert(not prior or not prior.snapshot,'Fresh fixture unexpectedly restored prior state')end
end
function F.store(snapshot,role)
 assert(type(snapshot)=='string'and lotQualBaseline,'Native full snapshot/compact baseline unavailable')
 local compact=lotQualBaseline(F.cells)
 assert(type(compact)=='string'and #compact<=8192 and compact:find('"kind":"lot-streaming-baseline"',1,true),
  'Native compact baseline failed or exceeded UTF-8 byte bound')
 -- Kahlua length counts UTF-16 units; this is a secondary bound. The Java probe
 -- enforces UTF-8 bytes before returning a native ModData-safe string.
 F.probe('PERSIST_BASELINE',role or 'client1','returned',compact)
 local record=ModData.getOrCreate(F.record)
 record.schema,record.seed,record.snapshot=1,F.seed,compact
end
function F.near(player,target)
 return math.abs(player:getX()-target[1]-.5)<=3 and math.abs(player:getY()-target[2]-.5)<=3
end
return F
