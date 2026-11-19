if not isServer()then return end
local P=require 'QueueEnergyPlacement'
local F=require 'QueueRazorRestoration'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local index=1
local state,previous,pending
local function raw(event,row)print('[RAZOR_RESTORATION] '..event..' '..JSON.encode(row))end
local function fail(player,reason)state=nil;pending=nil;print('[QUEUE_TEST] FAIL razor-restoration server '..tostring(reason));sendServerCommand(player,'RazorRestorationTest','Failed',{error=tostring(reason)})end
local function verifyWaiting()
 if not state or not F.beltCase(state.ids.case)or pending.lastDiffAt and getTimestampMs()-pending.lastDiffAt<2000 then return end
 pending.lastDiffAt=getTimestampMs()
 local actual,expected=F.snapshot(state),F.expected(state.ids,true);local differences={}
 local function diff(left,right,path)
  if #differences>=12 or F.same(left,right)then return end
  if type(left)=='table'and type(right)=='table'then
   local keys,seen={},{};for key in pairs(left)do keys[#keys+1]=key;seen[key]=true end
   for key in pairs(right)do if not seen[key]then keys[#keys+1]=key end end
   table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
   for _,key in ipairs(keys)do diff(left[key],right[key],path==''and tostring(key)or path..'.'..tostring(key))end
  else
   differences[#differences+1]={path=path,actual=left==nil and'<missing>'or left,expected=right==nil and'<missing>'or right,
    actualType=type(left),expectedType=type(right)}
  end
 end
 diff(actual,expected,'')
 local roots={};local root=state.player:getInventory()
 for name,spec in pairs(state.ids.items)do
  local item=F.find(state.player,spec.id)
  roots[name]={expected=spec.id,actual=item and item:getID()or false,type=item and item:getFullType()or false,
   root=item~=nil and item:getContainer()==root,canonical=item~=nil and root:getItemById(spec.id)==item}
 end
 raw('VERIFY_WAIT',{case=state.ids.case,elapsed=getTimestampMs()-pending.since,primary=actual.primary,expectedPrimary=expected.primary,
  secondary=actual.secondary,expectedSecondary=expected.secondary,belt=actual.belt,expectedBelt=expected.belt,roots=roots,differences=differences})
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='RazorRestorationTest'then return end
 local ok,reason=pcall(function()
  assert(player:getUsername()=='client1'and args.case==config.cases[index]and not pending,'unexpected razor-restoration actor/case/request')
  if command=='Prepare'then
   assert(not state and args.clientPlacement.centered==true,'razor-restoration placement proof missing')
   pending={command=command,player=player,case=args.case,target=P.target(args.placement),arrival=P.observeCentered(player,P.target(args.placement)),since=getTimestampMs()}
  elseif command=='ConfigureBelt'then
   assert(state and state.player==player,'belt setup without authority seed')
   local ids=F.configureBelt(state,args.slotIndex);raw('PREPARED',ids);sendServerCommand(player,'RazorRestorationTest','BeltConfigured',ids)
  elseif command=='ChangeHeavy'then
   assert(state and state.player==player,'heavy intervention without exact authority seed')
   -- The client's intervention can arrive before the server's next observation tick.
   local dropped=F.observeHeavyAuthority(state)
   if dropped then raw('HEAVY_AUTHORITY',dropped)end
   local receipt=F.removeHeavy(state,args.requestedAt);raw('HEAVY_REMOVED',receipt);sendServerCommand(player,'RazorRestorationTest','HeavyChanged',receipt)
  elseif command=='ChangeOrigin'then
   assert(state and state.player==player,'origin intervention without authority seed')
   local receipt=F.changeOrigin(state,args.requestedAt);raw('ORIGIN',receipt);sendServerCommand(player,'RazorRestorationTest','OriginChanged',receipt)
  else assert(command=='Verify'and state and state.player==player,'unexpected razor-restoration authority command');pending={command=command,player=player,since=getTimestampMs()}end
 end)
 if not ok then fail(player,reason)end
end)
Events.OnTick.Add(function()
 if not pending then return end
 local player=pending.player
 local ok,reason=pcall(function()
  assert(getTimestampMs()-pending.since<20000,'razor-restoration authority timeout '..pending.command)
  if pending.command=='Prepare'then
   local proof=P.poll(pending.arrival);if not proof then return end
   state=F.prepare(player,pending.case,pending.target,proof,previous);previous=nil
   if not F.beltCase(state.ids.case)then raw('PREPARED',state.ids)end;sendServerCommand(player,'RazorRestorationTest','Prepared',state.ids);pending=nil
  else
   local receipt=F.verify(state);if not receipt then verifyWaiting();return end
   local transfer=F.observeTransferAuthority(state);if transfer then raw('TRANSFER_AUTHORITY',transfer)end
   local heavy=F.observeHeavyAuthority(state);if heavy then raw('HEAVY_AUTHORITY',heavy)end
   receipt.transfers=state.transfers or{};receipt.heavyTransitions=state.heavy or{}
   raw('VERIFIED',receipt);sendServerCommand(player,'RazorRestorationTest','Verified',receipt)
   previous=state;state=nil;pending=nil;index=index+1
  end
 end)
 if not ok then fail(player,reason)end
end)

Events.OnTick.Add(function()
 if not state then return end
 local player=state.player
 local ok,reason=pcall(function()
  local transfer=F.observeTransferAuthority(state);if transfer then raw('TRANSFER_AUTHORITY',transfer)end
  local heavy=F.observeHeavyAuthority(state);if heavy then raw('HEAVY_AUTHORITY',heavy)end
 end)
 if not ok then fail(player,'transfer authority observation: '..tostring(reason))end
end)
