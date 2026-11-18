local config=require 'QueueTestSelection'
if config.suite~='loot-demand' or config.kind~='mp' or config.cases[1]~='natural' or not isServer() then return end
local options=config.options or {}
local arm=options.loot_demand_arm
assert(arm=='observe' or arm=='defer','natural Host requires exact arm')
local PREFIX='[LOOT_NATURAL] '
local run
local function emit(kind,text) print(PREFIX..kind..' role=server arm='..arm..' '..text) end
local function fields(line)
 local row,value,quoted={},'',false
 local i=1
 while i<=#line do
  local c=line:sub(i,i)
  if c=='"' then
   if quoted and line:sub(i+1,i+1)=='"' then value=value..'"';i=i+1 else quoted=not quoted end
  elseif c==',' and not quoted then row[#row+1]=value;value='' else value=value..c end
  i=i+1
 end
 assert(not quoted,'unterminated census CSV');row[#row+1]=value;return row
end
local function censusRows()
 local header,rows=nil,{}
 for line in lootDemandCensus():gmatch('[^\r\n]+') do
  local parts=fields(line)
  if not header then header=parts else
   assert(#parts==#header,'census CSV column mismatch')
   local row={}
   for i,key in ipairs(header) do row[key]=tonumber(parts[i]) or parts[i] end
   rows[#rows+1]=row
  end
 end
 assert(header,'missing census header');return rows
end
local function dump(phase)
 local clock=lootDemandClock()
 emit('ROW','phase='..phase..' clock_ns='..tostring(clock)..' format=status')
 for line in lootDemandCensusStatus():gmatch('[^\r\n]+') do emit('ROW','phase='..phase..' status='..line) end
 for line in lootDemandCensus():gmatch('[^\r\n]+') do emit('ROW','phase='..phase..' csv='..line) end
 return clock
end
local function fail(problem)
 if run and run.done then return end
 if run then run.done=true end
 emit('FAIL','problem='..tostring(problem))
 if run and run.player then sendServerCommand(run.player,'LootNatural','Failure',{problem=tostring(problem)}) end
end
local function objectAt(row)
 local square=getCell():getGridSquare(row.x,row.y,row.z)
 if not square or row.object_index<0 or row.object_index>=square:getObjects():size() then return end
 local object=square:getObjects():get(row.object_index)
 if not object or not object:getSprite() or object:getSprite():getName()~=row.sprite then return end
 local container=object:getContainer()
 if not container or container:getType()~=row.type then return end
 return object,container,square
end
local function choose(player)
 local candidates={}
 local radius=tonumber(options.loot_demand_radius) or 36
 local pin=options.loot_demand_target
 for _,row in ipairs(censusRows()) do
  local dx,dy=row.x-player:getX(),row.y-player:getY()
  local distance=dx*dx+dy*dy
  local pinned=not pin or (row.x==pin.x and row.y==pin.y and row.z==(pin.z or 0) and (pin.index==nil or row.object_index==pin.index))
  if pinned and row.z==player:getZ() and math.max(math.abs(dx),math.abs(dy))>3 and distance<=radius*radius and row.auto_visits>0 then
   local object,container,square=objectAt(row)
   if object then
    assert(row.active_depth==0,'eligible target is still filling')
    local valid=arm=='observe' and row.fill_kind=='automatic' and row.fill_ns>=0 and row.fill_failed==0 and container:isExplored()
      or arm=='defer' and row.fill_kind=='none' and row.fill_ns==-1 and not container:isExplored() and container:isEmpty()
    if valid then candidates[#candidates+1]={row=row,object=object,container=container,square=square,distance=distance,outdoor=square:getRoom()==nil} end
   end
  end
 end
 table.sort(candidates,function(a,b)
  if a.outdoor~=b.outdoor then return a.outdoor end
  if a.distance~=b.distance then return a.distance<b.distance end
  if a.row.x~=b.row.x then return a.row.x<b.row.x end
  if a.row.y~=b.row.y then return a.row.y<b.row.y end
  return a.row.object_index<b.row.object_index
 end)
 assert(candidates[1],'no eligible real primary bin/dumpster outside initial nearby inventory scan')
 return candidates[1]
end
local function selectedRow()
 for _,row in ipairs(censusRows()) do
  local r=run.target.row
  if row.x==r.x and row.y==r.y and row.z==r.z and row.object_index==r.object_index and row.sprite==r.sprite then return row end
 end
 error('selected census identity disappeared')
end
local function witness(container,phase)
 local fields={}
 for line in lootDemandCensusWitness(container):gmatch('[^\r\n]+') do
  local key,value=line:match('^([^=]+)=(.*)$')
  assert(key and fields[key]==nil,'invalid target witness')
  fields[key]=tonumber(value) or value
  emit('WITNESS','phase='..phase..' '..line)
 end
 return fields
end
local function report()
 local row=run.target.row
 local object,container=objectAt(row)
 assert(object==run.target.object and container==run.target.container,'real target identity changed during approach')
 local dx,dy=run.player:getX()-row.x,run.player:getY()-row.y
 local close=math.max(math.abs(dx),math.abs(dy))<=1.9
 local state=tostring(close)..'/'..tostring(container:isExplored())
 if state~=run.previousState then
  run.previousState=state
  local observed=selectedRow()
  emit('STATE','x='..run.player:getX()..' y='..run.player:getY()..' near/explored='..state
       ..' items='..container:getItems():size()..' fill_kind='..observed.fill_kind..' fill_ns='..tostring(observed.fill_ns))
 end
 if not close then return end
 if not container:isExplored() then return end
 local fill=witness(container,'opened')
 local kind,elapsed='unobserved',-1
 if fill.known=='true' then
  -- Native requests can publish explored before their fill returns. The outer
  -- approach timeout still bounds this wait; only completed contents are reported.
  assert(fill.concurrent_fills==0 and fill.fill_failed==0,'overlapping or failed target fill')
  if fill.active_depth>0 then return end
  assert(fill.active_depth==0,'invalid target fill depth')
  assert(fill.repeat_fills==0 and fill.reentries==0,'unexpected repeat/reentrant target fills')
  if fill.fill_ns>=0 then
   assert(fill.fill_kind==(arm=='defer' and 'demand' or 'automatic'),'unexpected first native fill origin')
   if arm=='defer' then assert(fill.first_fill_ns>=run.approachClock,'target filled before approach was armed') end
   kind,elapsed=fill.fill_kind,fill.fill_ns
  else
   assert(fill.fill_kind=='none' and fill.first_fill_ns==0,'invalid missing native fill interval')
  end
 end
 run.reported=true
 local now=dump('after')
 local count=container:getItems():size()
 emit('RESULT','phase=authority x='..row.x..' y='..row.y..' z='..row.z..' index='..row.object_index..' items='..count..' timing_source='..fill.origin..' fill_kind='..kind..' fill_ns='..tostring(elapsed)..' clock_ns='..tostring(now))
 sendServerCommand(run.player,'LootNatural','Authority',{x=row.x,y=row.y,z=row.z,index=row.object_index,sprite=row.sprite,kind=row.type,
  count=count,fingerprint=lootDemandFingerprint(container),fill_kind=kind,fill_ns=elapsed,clock_ns=now})
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='LootNatural' then return end
 local ok,problem=pcall(function()
  assert(player and player:getUsername()=='client1','foreign natural sender')
  if command=='Begin' then
   assert(not run,'duplicate natural Begin')
   assert(lootDemandInstalled(),'authority demand hooks inactive')
   assert(lootDemandCensusStatus():find('arm='..arm..'\n',1,true),'authority arm mismatch')
   run={player=player,begin=getTimestampMs(),started=false,done=false}
   emit('READY','phase=settling x='..player:getX()..' y='..player:getY()..' z='..player:getZ()..' clock_ns='..tostring(lootDemandClock()))
  elseif command=='Approaching' then
   assert(run and not run.done and run.target and not run.started,'unrequested approach')
   run.started=true;run.approachClock=dump('approach');run.approachAt=getTimestampMs()
   emit('APPROACH','phase=armed clock_ns='..tostring(run.approachClock))
   sendServerCommand(player,'LootNatural','Armed',{ready=true})
  elseif command=='Observe' then
   assert(run and run.reported and not run.done and type(args)=='table','unrequested observation')
   assert(args.fingerprint==lootDemandFingerprint(run.target.container),'client native inventory differs from authority')
   assert(args.count==run.target.container:getItems():size(),'client native item count differs')
   run.done=true
   emit('COMPLETE','case=natural outcome='..(args.count==0 and 'empty' or 'native-inventory-matched')..' client_elapsed_ms='..tostring(args.elapsed_ms))
   sendServerCommand(player,'LootNatural','Complete',{ok=true,empty=args.count==0})
  elseif command=='Failure' then if run and run.done then return end;error('client failure: '..tostring(args and args.problem))
  else error('unknown natural command '..tostring(command)) end
 end)
 if not ok then fail(problem) end
end)
Events.OnTick.Add(function()
 if not run or run.done then return end
 local ok,problem=pcall(function()
  assert(not run.player:isDead(),'natural actor died')
  assert(getTimestampMs()-run.begin<180000,'natural Host timeout')
  if not run.target and getTimestampMs()-run.begin>=(tonumber(options.loot_demand_settle_ms) or 5000) then
   run.beforeClock=dump('before');run.target=choose(run.player)
   local row=run.target.row
   local initial=witness(run.target.container,'selected')
   if arm=='defer' and initial.known=='false' then
    assert(lootDemandWatch(run.target.container),'could not observe selected pristine target')
    witness(run.target.container,'armed')
   end
   emit('READY','phase=target x='..row.x..' y='..row.y..' z='..row.z..' index='..row.object_index..' sprite='..row.sprite..' type='..row.type..' outdoor='..tostring(run.target.outdoor)..' auto_visits='..row.auto_visits)
   sendServerCommand(run.player,'LootNatural','Target',{x=row.x,y=row.y,z=row.z,index=row.object_index,sprite=row.sprite,kind=row.type,outdoor=run.target.outdoor})
  elseif run.started and not run.reported then
   report()
   if getTimestampMs()-run.approachAt>90000 and not run.reported then dump('timeout');error('approach timeout at '..run.player:getX()..','..run.player:getY()..' near/explored='..tostring(run.previousState)) end
  end
 end)
 if not ok then fail(problem) end
end)
