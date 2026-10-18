local originalPrint=print
local forwarded={}
print=function(...)
 forwarded[#forwarded+1]={n=select('#',...),...}
 return 'forwarded',nil,17
end
-- P4 exposes registration methods only; accessing its private state must fail.
P4TidyUpMeister=setmetatable({registerActionPolicy=function()end,registerWornItemReplacement=function()end},
 {__index=function(_,key)error('private P4 access '..key)end})
local option={selected=1}
require=function(name)error('probe executed another module '..name)end
PZAPI={ModOptions={getOptions=function(_,name)
 assert(name=='P4TidyUpMeister')
 return {getOption=function(_,key)assert(key=='DebugOutput');return option end}
end}}
local updates={function()end}
Events={OnPlayerUpdate={Add=function(callback)updates[#updates+1]=callback end}}
local player={num=0,busy=false,queue={queue={}},inventory={kind='none'}}
function player:getPlayerNum()return self.num end
function player:hasTimedActions()return self.busy end
function player:getInventory()return self.inventory end
function player.inventory:getType()return self.kind end
ISTimedActionQueue={getTimedActionQueue=function(value)return value.queue end}
local Tidy=assert(loadfile((ProjectRoot or '.')..'/tests/native_queue/fire/client/QueueFireTidy.lua'))()
Tidy.install(true);local observer=print;Tidy.install(true)
assert(#updates==2 and print==observer and option.selected==2,'probe installation changed P4 flow or repeated itself')
local first,second,third=print('unchanged',false,nil)
local args=forwarded[#forwarded]
assert(args.n==3 and args[1]=='unchanged' and args[2]==false and args[3]==nil
 and first=='forwarded' and second==nil and third==17,'print forwarding changed arguments or return values')
local function line(session,message,number)
 local text='[P4TidyUpMeister][P'..tostring(number or 0)..'][S'..tostring(session)..'] '..message
 print(text)
 assert(forwarded[#forwarded][1]==text and forwarded[#forwarded].n==1,'native P4 output changed')
end
local function remember(session,id,number)
 line(session,'remember transfer Base.PetrolCan#'..id..'@crate -> '..player:getInventory():getType(),number)
end
local function link(session,id,number)
 line(session,'link transfer Base.PetrolCan#'..id..'@crate -> operation ISBBQLightFromPetrol',number)
end
local function plan(session,id,number)
 line(session,'queue transfer restore Base.PetrolCan#'..id..'@'..player:getInventory():getType()..' -> crate',number)
end
local function complete(session,number)line('-','restore queue complete S'..session,number)end
Tidy.reset(player)
remember(1,101);assert(not Tidy.restore(player,101))
link(1,101);assert(not Tidy.restore(player,101))
plan(1,101)
local restored=assert(Tidy.restore(player,101));assert(restored.sessionId==1 and restored.completed==false)
complete(2);assert(not Tidy.restore(player,101).completed,'unrelated session completed restore')
complete(1);assert(Tidy.restore(player,101).completed)
restored.sessionId=999;assert(Tidy.restore(player,101).sessionId==1,'caller mutated probe records')
Tidy.reset(player);assert(not Tidy.restore(player,101),'case reset retained provenance')
player.inventory.kind='inventorymale';Tidy.reset(player)
remember(3,103);link(3,103);plan(3,103);complete(3)
assert(Tidy.restore(player,103).completed,'alternate runtime root container type was rejected')
player.inventory.kind='none'
-- Missing, reordered, cross-session, cross-item and cross-actor chains never combine.
for _,change in ipairs({'missing','order','session','item','actor','source','destination','root-destination','root-source','kind','zero-session','prefix','varargs'}) do
 Tidy.reset(player)
 if change=='source' then line(1,'remember transfer Base.PetrolCan#101@floor -> none')
 elseif change=='root-destination' then line(1,'remember transfer Base.PetrolCan#101@crate -> inventorymale')
 elseif change=='kind' then line(1,'remember transfer Base.Lighter#101@crate -> none')
 elseif change=='zero-session' then remember(0,101)
 elseif change=='prefix' then print('prefix [P4TidyUpMeister][P0][S1] remember transfer Base.PetrolCan#101@crate -> none')
 elseif change=='varargs' then print('[P4TidyUpMeister][P0][S1] remember transfer Base.PetrolCan#101@crate -> none','extra')
 else remember(1,101) end
 if change=='order' then plan(1,101) end
 if change~='missing' then link(change=='session' and 2 or 1,change=='item' and 102 or 101,change=='actor' and 1 or 0) end
 if change=='destination' then line(1,'queue transfer restore Base.PetrolCan#101@none -> floor')
 elseif change=='root-source' then line(1,'queue transfer restore Base.PetrolCan#101@inventorymale -> crate')
 elseif change~='order' then plan(1,101) end
 complete(1)
 assert(not Tidy.restore(player,101),'invalid chain accepted: '..change)
end
Tidy.reset(player);remember(1,101);link(1,101);complete(1);plan(1,101)
assert(not Tidy.restore(player,101).completed,'completion preceding restore plan was accepted')
-- More than one qualifying session for the same ID is ambiguous.
remember(2,101);link(2,101);plan(2,101)
assert(not Tidy.restore(player,101),'ambiguous provenance accepted')
Tidy.reset(player)
assert(Tidy.idleUpdates(player)==0)
updates[2](player);updates[2](player);updates[2](player)
assert(Tidy.idleUpdates(player)==3,'real idle updates were not counted')
player.queue.queue={{}};updates[2](player);assert(Tidy.idleUpdates(player)==0,'queued work did not reset idle counter')
player.queue.queue={};updates[2](player);player.busy=true;updates[2](player)
assert(Tidy.idleUpdates(player)==0,'native timed action did not reset idle counter')
player.busy=false;updates[2](player);Tidy.reset(player)
assert(Tidy.idleUpdates(player)==0,'case reset retained idle updates')
local other={num=0,busy=false,queue={queue={}},getPlayerNum=player.getPlayerNum,hasTimedActions=player.hasTimedActions}
updates[2](other);assert(Tidy.idleUpdates(other)==0 and Tidy.idleUpdates(player)==0,'different player reused actor state')
print=originalPrint
local path=(ProjectRoot or '.')..'/tests/native_queue/fire/client/QueueFireTidy.lua'
-- The default Fire pack has no P4; only the native idle observer is installed.
PZAPI={ModOptions={getOptions=function()error('default pack accessed P4 options')end}}
for _,withP4 in ipairs({false,'omitted'}) do
 local plain=assert(loadfile(path))()
 if withP4==false then plain.install(false) else plain.install() end
 local count=#updates
 plain.install(false)
 assert(print==originalPrint and #updates==count,'default pack changed print or repeated installation')
 plain.reset(player);updates[count](player);updates[count](player);updates[count](player)
 assert(plain.idleUpdates(player)==3 and not plain.restore(player,101),'default pack idle observation failed')
 player.busy=true;updates[count](player);player.busy=false
 assert(plain.idleUpdates(player)==0,'default pack did not reset idle on native work')
end
for _,missing in ipairs({'options','debug'}) do
 PZAPI={ModOptions={getOptions=function()
  if missing=='debug' then return {getOption=function()return nil end} end
 end}}
 local strict=assert(loadfile(path))()
 local count=#updates
 local ok,problem=pcall(strict.install,true)
 assert(not ok and tostring(problem):find(missing=='options' and 'P4 options unavailable' or 'P4 debug option unavailable',1,true),
  'selected P4 silently accepted missing '..missing)
 assert(#updates==count and print==originalPrint,'failed P4 installation changed observers')
end
print('Fire P4 public-log provenance, output forwarding and idle settlement passed.')
