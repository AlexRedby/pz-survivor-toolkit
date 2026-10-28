local protocol=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/VehicleDiagnosticsProtocol.lua')
require=function(name) assert(name=='PZSurvivorToolkit/VehicleDiagnosticsProtocol');return protocol end
local handlers={}
Events=setmetatable({},{__index=function(_,key) return {Add=function(fn) handlers[key]=fn end} end})
local time,network,host,player=1000,true,true,{}
getTimestampMs=function() return time end
isClient=function() return network end
isCoopHost=function() return host end
getSpecificPlayer=function() return player end
local sent={}
sendClientCommand=function(p,module,command,args)
 assert(p==player and module==protocol.MODULE);sent[#sent+1]={command=command,args=args}
end
local D=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleDiagnosticsClient.lua')
assert(D.pollServer().pending and #sent==1 and sent[1].command=='Status')
assert(not D.setServer(true),'cannot race a status request')
local id=sent[1].args.request
D.receive(protocol.MODULE,'State',{request=id+1,status='active',path='foreign'})
assert(D.server.status=='unknown' and D.server.pending,'ignore uncorrelated replies')
D.receive(protocol.MODULE,'State',{request=id,status='bogus',path='x'})
assert(D.server.pending,'ignore malformed status')
D.receive(protocol.MODULE,'State',{request=id,status='off',path='/server/vehicle-sync.log'})
assert(not D.server.pending and D.server.status=='off')
assert(D.setServer(true) and sent[2].args.enabled==true)
local enable=sent[2].args.request
D.receive(protocol.MODULE,'State',{request=id,status='off',path='old'})
assert(D.server.pending and D.server.path~='old','ignore stale reply during mutation')
D.receive(protocol.MODULE,'State',{request=enable,status='active',path='/server/vehicle-sync.log'})
assert(D.server.status=='active' and not D.server.pending)
assert(D.setServer(false))
time=time+5001;D.pollServer()
assert(D.server.status=='timeout' and not D.server.pending)
D.receive(protocol.MODULE,'State',{request=sent[3].args.request,status='off',path='late'})
assert(D.server.status=='timeout' and D.server.path=='','late ack must not turn timeout into success')
assert(D.queryServer())
handlers.OnDisconnect()
D.receive(protocol.MODULE,'State',{request=sent[4].args.request,status='active',path='old-connection'})
assert(D.server.status=='unknown' and not D.server.pending)
host=false;local count=#sent
assert(not D.queryServer() and not D.setServer(true))
assert(D.pollServer().status=='denied' and #sent==count)
network=false;assert(D.pollServer().status=='noServer')
network=true;host=true
sendClientCommand=function() error('unavailable transport') end
assert(not D.queryServer() and D.server.status=='error' and not D.server.pending)

local replies,mutations={},{}
isServer=function() return true end
sendServerCommand=function(p,module,command,args)
 assert(p==player and module==protocol.MODULE and command=='State');replies[#replies+1]=args
end
local allowed,status=true,'off'
toolkitVehicleTraceCanControl=function(p) assert(p==player);return allowed end
toolkitVehicleTraceStatus=function() return status end
toolkitVehicleTracePath=function() return '/server/vehicle-sync.log' end
toolkitVehicleTraceSet=function(value) mutations[#mutations+1]=value;status=value and 'active' or 'off';return status end
local S=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/server/PZSurvivorToolkit/VehicleDiagnosticsServer.lua')
local function command(action,args) S.command(protocol.MODULE,action,player,args) end
command('Status',{request=1});assert(replies[#replies].status=='off' and #mutations==0)
command('Set',{request=2,enabled=true});assert(status=='active' and #mutations==1)
allowed=false
command('Set',{request=3,enabled=false,host=true});assert(status=='active' and #mutations==1)
assert(replies[#replies].status=='denied' and replies[#replies].path=='','guest cannot obtain server state/path')
command('Status',{request=4});assert(replies[#replies].status=='denied')
allowed=true;local count=#replies
for _,args in ipairs({{}, {request=0},{request=0/0},{request=1.5},{request=math.huge},{request=2147483648},{request='5'},{request=5,enabled='false'}}) do
 command('Set',args)
end
assert(#mutations==1 and #replies==count,'reject malformed requests without effects')
toolkitVehicleTraceCanControl=nil
command('Set',{request=6,enabled=false});assert(#mutations==1 and replies[#replies].status=='unavailable')
toolkitVehicleTraceCanControl=function() return true end
toolkitVehicleTraceSet=nil
command('Set',{request=7,enabled=false});assert(replies[#replies].status=='unavailable')
toolkitVehicleTraceSet=function() error('writer failed') end
command('Set',{request=8,enabled=false});assert(replies[#replies].status=='error')
S.command('other','Set',player,{request=9,enabled=false})
assert(replies[#replies].request==8)
print('PASS vehicle diagnostics transport: host authority, schema, confirmed replies, timeout, disconnect, missing bridge')
