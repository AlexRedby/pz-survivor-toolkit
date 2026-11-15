-- Test-only point observation. This never authorizes or changes a queue edit.
local config=require 'QueueTestSelection'
local H={}
local enabled=config.options and config.options.equip_host_observation==true
if not enabled then
 function H.poll()return true end
 function H.result()return nil end
 return H
end
assert(config.kind=='mp'and config.cases[1]=='equip-edit','Host hand point needs the Equip bank')
local JSON=require 'QueueHealthEvents'
local pending,observed,query,record,action,reply,failure
local function samePoint(point,args)
 return type(point)=='table'and point.schema==1 and point.scope=='server-native-active-action-point'
  and point.player==args.player and point.transaction==args.transaction and point.token==args.token
  and point.kind==args.kind and point.state=='accepted'and point.packetCorrelated==false
  and point.rootMembershipVerified==false and point.effectsVerified==false and point.editAuthority==false
end
if isServer()then
 local function guard(player,fn)
  local ok,reason=pcall(fn)
  if not ok then
   failure=tostring(reason);pending=nil
   print('[QUEUE_TEST] FAIL magazine-unload equip-edit server hand point '..failure)
   sendServerCommand(player,'EquipEditTest','Failed',{error=failure})
  end
 end
 Events.OnClientCommand.Add(function(module,command,player,args)
  if module~='EquipEditPointTest'or command~='Observe'then return end
  if failure then return end
  guard(player,function()
  assert(not pending and not observed,'duplicate Host hand point query')
  assert(player:getUsername()=='client1'and type(args)=='table'and args.segment=='reorder-two'
   and args.player==player:getOnlineID()and args.kind=='ISReadABook','unexpected Host hand point actor')
  pending={player=player,args=args,since=getTimestampMs()}
  end)
 end)
 Events.OnTick.Add(function()
  if not pending then return end
  guard(pending.player,function()
  assert(toolkitNativeHandStateApiMatches and toolkitNativeHandStateApiMatches(toolkitNativeHandState),'native hand point API unavailable')
  local point=toolkitNativeHandState(pending.player,pending.args.transaction,pending.args.token)
  if not point then assert(getTimestampMs()-pending.since<10000,'Host action point unavailable');return end
  assert(samePoint(point,pending.args),'server hand point action mismatch')
  local value={segment=pending.args.segment,query=pending.args,point=point}
  print('[EQUIP_EDIT] HAND_POINT '..JSON.encode(value))
  sendServerCommand(pending.player,'EquipEditPointTest','Observed',value)
  pending=nil;observed=true
  end)
 end)
else
 Events.OnServerCommand.Add(function(module,command,args)
  if module~='EquipEditPointTest'or command~='Observed'then return end
  if not query or reply or type(args)~='table'or args.segment~=query.segment then failure='unexpected Host hand point reply';return end
  reply=args
 end)
 function H.poll(current,segment,hands)
  assert(not failure,failure)
  local A=PZSurvivorToolkit.ActionQueueAcknowledgements
  assert(isClient()and A,'Host point needs native action receipts')
  if not query then
   record=A.capture(current)
   if not record then return false end
   assert(A.state(current,record)=='started'and record.kind=='ISReadABook','Host front receipt unavailable')
   action=current;query={segment=segment,player=current.character:getOnlineID(),transaction=record.transaction,token=record.token,kind=record.kind}
   sendClientCommand('EquipEditPointTest','Observe',query)
   return false
  end
  assert(current==action and A.state(action,record)=='started','native front changed during Host point query')
  if not reply then return false end
  assert(samePoint(reply.point,query),'client hand point action mismatch')
  for key,value in pairs(query)do assert(reply.query[key]==value,'Host hand point query changed')end
  local pair=hands(current.character)
  assert(reply.point.primaryId==pair.primary and reply.point.secondaryId==pair.secondary,'Host/client point hands disagree')
  observed={query=query,server=reply.point,clientHands=pair,active=true,authority=false}
  return true
 end
 function H.result()return observed end
end
return H
