local Tidy,actors={},{}
local installed=false
local function actor(player)
 if not player then return end
 local value=actors[player:getPlayerNum()]
 if value and value.player==player then return value end
end
local function observe(line)
 if type(line)~='string' then return end
 local number,session,message=line:match('^%[P4TidyUpMeister%]%[P(%d+)%]%[S([%d%-]+)%] (.+)$')
 local value=number and actors[tonumber(number)]
 if not value then return end
 if session=='-' then
  local completed=tonumber(message:match('^restore queue complete S(%d+)$'))
  for _,entry in pairs(value.records[completed] or {}) do
   if entry.stage==3 then entry.completed=true end
  end
  return
 end
 session=tonumber(session)
 if not session or session<=0 or session%1~=0 then return end
 local item,destination=message:match('^remember transfer Base%.PetrolCan#(%d+)@crate %-> (%S+)$')
 local id=tonumber(item)
 if id and destination==value.rootType then
  value.records[session]=value.records[session] or {}
  value.records[session][id]={stage=1,completed=false}
  return
 end
 local records=value.records[session]
 if not records then return end
 id=tonumber(message:match('^link transfer Base%.PetrolCan#(%d+)@[%w_]+ %-> operation [%w_]+$'))
 if id and records[id] and records[id].stage==1 then records[id].stage=2;return end
 local source
 item,source=message:match('^queue transfer restore Base%.PetrolCan#(%d+)@(%S+) %-> crate$')
 id=tonumber(item)
 if id and source==value.rootType and records[id] and records[id].stage==2 then records[id].stage=3 end
end
function Tidy.install(withP4)
 if installed then return end
 if withP4 then
  local options=assert(PZAPI.ModOptions:getOptions('P4TidyUpMeister'),'P4 options unavailable')
  assert(options:getOption('DebugOutput'),'P4 debug option unavailable').selected=2
  local original=print
  print=function(...)
   if select('#',...)==1 then observe((...)) end
   return original(...)
  end
 end
 Events.OnPlayerUpdate.Add(function(player)
  local value=actor(player)
  if not value then return end
  local queue=ISTimedActionQueue.getTimedActionQueue(player)
  value.idle=#queue.queue==0 and not player:hasTimedActions() and value.idle+1 or 0
 end)
 installed=true
end
function Tidy.reset(player)
 actors[player:getPlayerNum()]={player=player,rootType=player:getInventory():getType(),records={},idle=0}
end
function Tidy.restore(player,id)
 local value=actor(player)
 if not value then return end
 local result
 for session,records in pairs(value.records) do
  local entry=records[id]
  if entry and entry.stage==3 then
   if result then return end
   result={sessionId=session,completed=entry.completed}
  end
 end
 return result
end
function Tidy.idleUpdates(player)
 local value=actor(player)
 return value and value.idle or 0
end
return Tidy
