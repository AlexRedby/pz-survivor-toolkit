-- Coordinate fixture placement only. Clinical patient movement remains a case effect.
local P=require 'QueueEnergyPlacement'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local H={}
local function same(a,b)return a.x==b.x and a.y==b.y and a.z==b.z end
local function raw(event,value)
 -- SP's native username may be empty; the runner's process role is client1.
 -- Keep real actor identities in the coordinator and canonicalize receipts only.
 if config.kind=='sp'then
  local row={};for key,item in pairs(value)do row[key]=item end
  if row.doctor~='setup'then row.doctor='client1'end
  if row.actor~=nil then row.actor='client1'end
  if row.targets then
   local target,count=nil,0;for _,item in pairs(row.targets)do target=item;count=count+1 end
   assert(count==1,'SP health placement requires one actor');row.targets={client1=target}
  end
  value=row
 end
 print('[HEALTH_PLACEMENT] '..event..' '..JSON.encode(value))
end
H.raw=raw
function H.proof(value,target,mode)
 target=P.target(target)
 assert(type(value)=='table'and value.mode==mode and value.centered==true,'health centered proof role missing')
 assert(same(P.target(value.target),target),'health proof target differs')
 local count=mode=='local'and 1 or 0
 assert(value.teleports==count and value.centers==count,'health proof position writes differ')
 assert(type(value.stableMs)=='number'and value.stableMs>=P.stableMs and type(value.quietMs)=='number'
  and(mode=='local'and value.quietMs>=P.stableMs or mode=='replica'and value.quietMs==0)
  and type(value.elapsedMs)=='number'and value.elapsedMs>=value.stableMs+value.quietMs and value.elapsedMs<P.timeoutMs,'health proof not settled')
 local a=value.actual
 assert(type(a)=='table'and type(a.x)=='number'and type(a.y)=='number'and type(a.z)=='number'
  and math.abs(a.x-target.x-.5)<=.1 and math.abs(a.y-target.y-.5)<=.1 and math.abs(a.z-target.z)<=.01
  and same(P.target(a.square),target)and same(P.target(a.currentSquare),target),'health proof centered squares differ')
 if mode=='local'then assert(a.queued==0 and a.timed==false and a.moving==false and a.hasPath==false
  and a.deferredX==0 and a.deferredY==0,'health proof native motion remains')end
 return true
end
local function names(targets)
 local result={};for name in pairs(targets)do result[#result+1]=name end;table.sort(result);return result
end
function H.newAuthority(A,deliver)
 local C={ready={},round=nil,setup=false,failed=false}
 local roles=config.kind=='mp'and{'client1','client2'}or nil
 local function begin(layout)
  assert(not C.round,'overlapping health placement round')
  C.round={layout=layout,waiting={},proofs={},began=getTimestampMs()}
  raw('LAYOUT',layout)
  for _,name in ipairs(names(layout.targets))do deliver(assert(A.actor(name)),'Placement',layout)end
 end
 function C:handle(player,command,args)
  assert(not self.failed,'health placement coordinator already failed')
  if command=='Ready'then
   local name=player:getUsername()
   if config.kind=='sp'then
    assert(player==getPlayer()and player:isLocalPlayer(),'health setup requires the owning SP actor')
    roles=roles or{name}
   end
   local known=false;for _,role in ipairs(roles)do if name==role then known=true end end
   assert(known,'unexpected health setup actor')
   assert(not self.ready[name]or self.ready[name]==player,'health setup actor replaced')
   self.ready[name]=player
   if self.setup then deliver(player,'Setup',assert(A.ids(player)))end
   return true
  elseif command=='Prepare'then
   assert(self.setup and not self.round,'health Prepare before setup or overlapping placement')
   begin(A.prepareLayout(player,args.phase));return true
  elseif command=='Placed'then
   local r=assert(self.round,'health placement without reserved round');local layout=r.layout;local name=player:getUsername()
   assert(args.phase==layout.phase and args.doctor==layout.doctor and args.actor==name
    and layout.targets[name]and A.actor(name)==player,'health placement round or actor differs')
   assert(not r.waiting[name],'duplicate health owning-client placement')
   assert(same(P.target(args.target),layout.targets[name]),'health placement claim target differs')
   H.proof(args.proof,layout.targets[name],'local')
   r.waiting[name]={clientProof=args.proof,observation=isServer()and P.observeCentered(player,layout.targets[name])or nil}
   return true
  end
  assert(not self.round,'health work requested during pending placement')
  return false
 end
 function C:tick()
  assert(not self.failed,'health placement coordinator already failed')
  if not self.setup and not self.round then
   if not roles then return end
   local players={}
   for _,name in ipairs(roles)do
    local player=self.ready[name];if not player or not player:getCurrentSquare()then return end
    players[#players+1]=player
   end
   begin(A.setupLayout(players))
  end
  local r=self.round;if not r then return end
  assert(getTimestampMs()-r.began<P.timeoutMs,'health placement round timed out')
  local layout=r.layout
  for _,name in ipairs(names(layout.targets))do
   local request=r.waiting[name]
   if request and not r.proofs[name]then
    local proof
    if isServer()then proof=P.poll(request.observation)else proof=request.clientProof end
    if proof then
     H.proof(proof,layout.targets[name],isServer()and'replica'or'local');r.proofs[name]=proof
    end
   end
  end
  for name in pairs(layout.targets)do if not r.proofs[name]then return end end
  A.checkPlacement(layout,r.proofs)
  for _,name in ipairs(names(layout.targets))do
   raw('AUTHORITY_PLACEMENT',{phase=layout.phase,doctor=layout.doctor,actor=name,target=layout.targets[name],
    proof=r.proofs[name],clientProof=r.waiting[name].clientProof})
  end
  local results={}
  if layout.phase=='setup'then
   for _,name in ipairs(names(layout.targets))do results[name]=A.setup(A.actor(name),layout,r.proofs)end
   self.setup=true
  else results[layout.doctor]=A.prepare(A.actor(layout.doctor),layout.phase,layout,r.proofs)end
  raw('PREPARED',layout)
  self.round=nil
  for _,name in ipairs(names(results))do deliver(A.actor(name),layout.phase=='setup'and'Setup'or'Prepared',results[name])end
 end
 return C
end
function H.newClient(send)
 local C={pending=nil,seen={}}
 function C:receive(layout)
  assert(type(layout)=='table'and type(layout.phase)=='string'and type(layout.doctor)=='string'and type(layout.targets)=='table','health client layout missing')
  local player=getPlayer();local name=player:getUsername();local target=P.target(layout.targets[name])
  local id=layout.doctor..':'..layout.phase
  assert(not self.pending and not self.seen[id],'overlapping/duplicate health client layout')
  self.seen[id]=true
  self.pending={layout=layout,target=target,placement=P.beginCentered(player,target),player=player}
 end
 function C:tick()
  local r=self.pending;if not r then return end
  local player=getPlayer();assert(player==r.player,'health local placement actor replaced')
  local name=player:getUsername();assert(same(P.target(r.layout.targets[name]),r.target),'health local layout changed')
  local proof=P.poll(r.placement);if not proof then return end
  assert(P.atCentered(player,r.target),'health local actor left centered placement')
  local value={phase=r.layout.phase,doctor=r.layout.doctor,actor=name,target=r.target,proof=proof}
  raw('CLIENT_PLACEMENT',value);self.pending=nil;send('Placed',value)
 end
 return C
end
return H
