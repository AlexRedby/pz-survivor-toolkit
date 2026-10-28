-- Test-only server-authoritative BodyDamage requests. All animation stays native.
local config=require 'QueueTestSelection'
local J=require 'CartMPJSON'
local options=assert(config.options)
assert(config.disposable==true and options.mp_host==true and options.cart_fast_motion==true and options.cart_injury==true,
 'Injury bank requires disposable native fast-motion Host')
assert(not options.cart_wall_exit and not options.cart_actions and not options.cart_hotkey_setdown,'Injury bank cannot combine wall/actions')
local side,severity=options.cart_injury_side,options.cart_injury_severity
assert(side=='left' or side=='right','Exact injury side required')
assert(severity=='mild' or severity=='heavy','Exact injury severity required')
local Injury={duration=45000,steps={
 {26000,1,0,'injury-healthy'}, {28000,1,0,'injury-apply'},
 {30000,5,0,'injury-left'}, {32400,8,0,'injury-right'},
 {34800,5,1,'injury-run'}, {37200,8,2,'injury-sprint'},
 {39600,1,0,'injury-moving'}, {41000,1,0,'injury-heal'}, {43000,0,0,'injury-stop'},
}}
local originalGod,started,finished,lastSample,current=nil,false,false,0,nil
local pending,acknowledged=nil,{}
local function emit(kind,row) print('[CART_MP_INJURY] '..kind..' '..J.encode(row)) end
local function owner(p)
 assert(p==getPlayer() and p:isLocalPlayer() and p:getUsername()=='client1' and isClient() and not isServer(),
  'BodyDamage request requires exact local fixture owner')
end
local function request(p,phase,now)
 assert(not pending,'Previous native injury snapshot was not acknowledged')
 local item=assert(p:getPrimaryHandItem(),'Injury request cart missing')
 pending={phase=phase,id=item:getID(),wall=now}
 sendClientCommand('CartMP','InjuryMutation',{phase=phase,id=item:getID(),side=side,severity=severity})
end
function Injury.command(args)
 owner(getPlayer())
 assert(pending and args.phase==pending.phase and args.id==pending.id and not acknowledged[args.phase],
  'Unexpected/duplicate native injury acknowledgement')
 assert(args.source=='NetworkPlayerAI.syncDamage' and args.side==side and args.severity==severity,'Native injury source differs')
 local now=getTimestampMs();assert(now-pending.wall<=1000,'Native injury snapshot acknowledgement deadline')
 local row={};for key,value in pairs(args) do row[key]=value end
 row.serverWall=args.wall;row.wall=now;row.requestWall=pending.wall
 emit('ACK',row);acknowledged[args.phase]=true;pending=nil
end
function Injury.phase(p,name,now,epoch)
 if not name:match('^injury%-') then return end
 owner(p)
 if name=='injury-healthy' then
  assert(not started,'Duplicate injury bank start')
  assert(toolkitCartInjurySupported and toolkitCartInjurySupported(p),'Native cart injury source gate unsupported')
  originalGod=p:isGodMod();p:setGodMod(false);started=true
 end
 assert(started and not finished and not p:isGodMod() and not p:isDead(),'Living native injury owner required')
 for _,step in ipairs(Injury.steps) do if step[4]==name then current=step end end
 assert(current and current[4]==name,'Unknown injury phase')
 if name=='injury-healthy' or name=='injury-apply' or name=='injury-heal' then request(p,name,now) end
 emit('PHASE',{phase=name,wall=now,elapsed=now-epoch,side=side,severity=severity,
  authority='server-request',mutation=name=='injury-apply' and 'injure' or name=='injury-heal' and 'heal' or 'none',drive=current[2],gait=current[3],x=p:getX(),y=p:getY()})
end
function Injury.sample(p,setup,now,elapsed)
 if not started or finished or now-lastSample<100 then return end
 owner(p);lastSample=now
 if pending then assert(now-pending.wall<=1000,'Native injury acknowledgement deadline') end
 local item=assert(p:getPrimaryHandItem(),'Injury owner cart missing')
 local count=0;local items=p:getInventory():getItems()
 for i=0,items:size()-1 do if items:get(i):getID()==setup.cartId then count=count+1 end end
 assert(item:getID()==setup.cartId and item:getFullType()==setup.cartType and p:getSecondaryHandItem()==item
  and item:getContainer()==p:getInventory() and not item:getWorldItem() and count==1,'Injury cart ownership changed')
 local contents=item:getInventory():getItems();assert(contents:size()==1,'Injury cargo count changed')
 local row={wall=now,elapsed=elapsed,phase=current[4],drive=current[2],gait=current[3],id=item:getID(),cargoID=contents:get(0):getID(),cargoWeight=item:getInventory():getCapacityWeight(),
  inventoryCount=count,luaActions=#ISTimedActionQueue.getTimedActionQueue(p).queue,
  nativeActions=p:getCharacterActions():size(),hasPath=p:hasPath(),god=p:isGodMod(),dead=p:isDead()}
 assert(row.luaActions==0 and row.nativeActions==0 and not row.hasPath and not row.god and not row.dead,'Injury actor/action state changed')
 emit('INPUT',row)
end
function Injury.finish(p)
 if not started or finished then return end
 owner(p)
 if not acknowledged['injury-heal'] then sendClientCommand('CartMP','InjuryCleanup',{}) end
 p:setGodMod(originalGod);finished=true
end
return Injury
