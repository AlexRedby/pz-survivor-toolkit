-- Execute actual shared/server fixtures under LuaJIT with native API boundaries stubbed.
-- ASCII bounds agree with Kahlua's UTF-16 length; the Java probe owns the UTF-8 byte cap.
local root=assert(arg[1]);local config={suite='lot-streaming',cases={'fresh'}}
package.preload.QueueTestSelection=function()return config end
package.preload.QueueHealthEvents=function()return {encode=function(value)return '"'..tostring(value)..'"'end}end
local record
ModData={get=function()return record end,getOrCreate=function()record=record or {};return record end}
local F=dofile(root..'/tests/native_queue/lot-streaming/shared/LotStreamingFixture.lua')
package.loaded.LotStreamingFixture=F
local compact='{"format":1,"ok":true,"kind":"lot-streaming-baseline","cells":[]}'
lotQualBaseline=function()return compact end
F.store('full debug snapshot','client1')
assert(record.schema==1 and record.snapshot==compact and record.snapshot~='full debug snapshot','Only compact data may be persisted')
config.cases={'reload'};F.baseline(config,'client1')
local good=record.snapshot
record.snapshot=string.rep('x',8193)
assert(not pcall(F.baseline,config,'client1'),'Oversized restored string was admitted')
record.snapshot=good
compact='{"format":1,"ok":true,"kind":"lot-streaming-baseline","world":"'..string.rep('x',8193)..'"}'
assert(#compact>8192 and not pcall(F.store,'full debug snapshot','client1'),'Oversized compact string was admitted')
assert(record.snapshot==good,'Rejected overflow changed persistent baseline')
record=nil;config.cases={'fresh'}
isServer=function()return true end
local handler
Events={OnClientCommand={Add=function(fn)handler=fn end}}
local replies,snapshots={},{}
sendServerCommand=function(player,module,command,args)
 replies[#replies+1]={role=player:getUsername(),command=command,phase=args.phase}
end
F.snapshot=function(role,phase)snapshots[#snapshots+1]={role=role,phase=phase};return 'debug-only' end
local function player(role,id)
 return {x=F.start[1]+.5,y=F.start[2]+.5,getUsername=function()return role end,getOnlineID=function()return id end,
 getX=function(self)return self.x end,getY=function(self)return self.y end}
end
local one,two=player('client1',1),player('client2',2)
dofile(root..'/tests/native_queue/lot-streaming/server/ZZLotStreamingServer.lua')
for _,p in ipairs({one,two})do handler(F.module,'Prepare',p,{})end
for _,p in ipairs({one,two})do handler(F.module,'Ready',p,{})end
replies={}
handler(F.module,'Probe',one,{phase='before'})
assert(#snapshots==1 and #replies==0,'First peer was released before the other initial snapshot')
handler(F.module,'Probe',two,{phase='before'})
assert(#snapshots==2 and #replies==2,'Both peers must be released after both initial snapshots')
local roles={}
for _,reply in ipairs(replies)do assert(reply.command=='Probe'and reply.phase=='before');roles[reply.role]=true end
assert(roles.client1 and roles.client2,'Initial ACKs did not reach distinct peers')
one.x,one.y=F.away[1]+.5,F.away[2]+.5
handler(F.module,'Probe',one,{phase='away'})
assert(#snapshots==3 and replies[3].phase=='away','Normal native sequence did not resume after barrier')
-- A phase jump cannot bypass the held initial ACK when another peer is late.
one.x,one.y=F.start[1]+.5,F.start[2]+.5
local failures={}
F.emit=function(event,value)if event=='FAIL'then failures[#failures+1]=value.error end end
dofile(root..'/tests/native_queue/lot-streaming/server/ZZLotStreamingServer.lua')
for _,p in ipairs({one,two})do handler(F.module,'Prepare',p,{});handler(F.module,'Ready',p,{})end
handler(F.module,'Probe',one,{phase='before'})
one.x=F.away[1]+.5
handler(F.module,'Probe',one,{phase='away'})
assert(#failures==1 and failures[1]:find('Initial authority snapshots not captured',1,true),'Early phase jump bypassed initial snapshot barrier')
print('LOT_STREAMING_LUA_CHECKS_OK')
