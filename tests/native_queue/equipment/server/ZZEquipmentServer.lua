local cartSelection=require 'QueueTestSelection'
if cartSelection.cases[1]=='cart-pickup' then return end
if not isServer() then return end
local Fixture=require 'QueueEquipmentFixture'
local Scene=require 'QueueEquipmentScene'
local Clothing=require 'QueueEquipmentClothing'
local Hotbar=require 'QueueEquipmentHotbar'
local Selection=require 'QueueTestSelection'
local Postprocess=require 'QueueEquipmentPostprocess'
local JSON=require 'QueueHealthEvents'
local session,pending,waiting,cleanup,verified=nil,nil,nil,nil,0
local function reply(player,command,args) sendServerCommand(player,'EquipmentQueueTest',command,args) end
Events.OnServerStarted.Add(function() print('[EQUIPMENT_TEST] SERVER_READY') end)
local function execute(module,command,player,args)
 local ok,problem=pcall(function()
  assert(player:getUsername()=='client1','unexpected equipment actor')
  if command=='Prepare' then
   assert(not session and not pending and Selection.cases[verified+1]==args.case,'out-of-order equipment prepare')
   player:setGhostMode(true)
   if verified==0 then
    Fixture.position(player)
    local proof=Scene.prepare(player,Selection.cases)
    if proof then print('[EQUIPMENT_TEST] SCENE_HEADWEAR '..JSON.encode(proof))end
   end
   session=Fixture.prepare(player,args.case,nil,Selection.options)
   local ids=Fixture.descriptor(session)
   ids.sceneSetup=Scene.proof(player)
   ids.spawn={x=player:getX(),y=player:getY(),z=player:getZ()}
   for _,item in ipairs(session.owned) do
    if item:getContainer()==player:getInventory() then sendAddItemToContainer(player:getInventory(),item) end
   end
   sendClothing(player,session.location,player:getWornItem(session.location));sendEquip(player)
   if Clothing.isCase(session.id)then sendClothing(player,session.clothingLocation,player:getWornItem(session.clothingLocation))end
   if session.id=='hotbar-chain' then sendAttachedItem(player,session.hotbarLocation,session.hotbarInitial) end
   if Hotbar.isCase(session.id)then
    if session.holster then sendClothing(player,session.holsterLocation,session.holster)end
    if session.hotbarIndex then sendAttachedItem(player,session.hotbarLocation,session.pickup)end
   end
   reply(player,'Prepared',ids)
   print('[EQUIPMENT_TEST] PREPARED case='..args.case)
  elseif command=='ConfigureClothing'then
   assert(session and session.id==args.case and not pending and not cleanup,'invalid authoritative clothing setup session')
   Clothing.configure(session,args.item)
   reply(player,'ClothingConfigured',{case=session.id,item=session.clothingItem:getID(),ok=true})
   print('[EQUIPMENT_TEST] CLOTHING_SETUP_CONFIGURED case='..session.id..' id='..session.clothingItem:getID())
  elseif command=='ConfigureHotbar'then
   assert(session and session.id==args.case and session.holster and not session.hotbarConfigured and not pending
    and args.item==session.pickup:getID(),'invalid native holster setup request')
   Hotbar.configure(session,args.slotIndex);session.hotbarConfigured=true
   sendAttachedItem(player,session.hotbarLocation,session.pickup)
   reply(player,'HotbarConfigured',{case=session.id,item=session.pickup:getID(),slotIndex=session.hotbarIndex,ok=true})
  elseif command=='Checkpoint' or command=='Verify' then
   assert(session and session.id==args.case and not pending,'out-of-order equipment verify')
   assert(command=='Checkpoint' or session.checkpointed,'missing equipment checkpoint')
   pending={player=player,since=getTimestampMs(),checkpoint=command=='Checkpoint'}
  elseif command=='Cleanup' then
   assert(session and session.id==args.case and session.verified and not cleanup,'unverified equipment cleanup')
   cleanup={player=player,since=getTimestampMs()}
  else error('unknown equipment command') end
 end)
 if not ok then print('[QUEUE_TEST] FAIL equipment server '..tostring(problem));reply(player,'Failed',{ok=false,error=tostring(problem)}) end
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='EquipmentQueueTest' then return end
 if command=='Prepare' and not player:getCurrentSquare() then
  assert(not waiting,'duplicate equipment prepare before square loaded')
  waiting={player=player,args=args};return
 end
 execute(module,command,player,args)
end)
Events.OnTick.Add(function()
 if waiting and waiting.player:getCurrentSquare() then
  local request=waiting;waiting=nil;execute('EquipmentQueueTest','Prepare',request.player,request.args)
 end
 if cleanup then
  local ok,problem=pcall(function()
   assert(getTimestampMs()-cleanup.since<20000,'native transfers did not settle before equipment cleanup')
   if not Fixture.transactionsSettled() then return end
   Fixture.cleanup(session);sendEquip(cleanup.player)
   reply(cleanup.player,'Cleaned',{case=session.id,ok=true});session=nil;verified=verified+1;cleanup=nil
  end)
  if not ok then
   print('[QUEUE_TEST] FAIL equipment server '..tostring(problem))
   reply(cleanup.player,'Failed',{ok=false,error=tostring(problem)});cleanup=nil
  end
 end
 if not pending then return end
 local ok,problem=pcall(function()
  assert(getTimestampMs()-pending.since<20000,'authoritative equipment state did not converge')
  local idle=Fixture.transactionsSettled()
  local settled=not pending.checkpoint or Fixture.settled(session,Selection.mode,true)
  if not idle or not settled then
   if not pending.diagnostic or getTimestampMs()-pending.diagnostic>=5000 then
    pending.diagnostic=getTimestampMs()
    local player=session.player
    print('[EQUIPMENT_TEST] SERVER_WAIT case='..session.id..' transfers='..equipmentNativeTransferCount()..' settled='..tostring(settled)
     ..' hands='..tostring(player:getPrimaryHandItem() and player:getPrimaryHandItem():getID())..','..tostring(player:getSecondaryHandItem() and player:getSecondaryHandItem():getID())
     ..' expected='..session.hammer:getID()..','..session.screwdriver:getID()..' batRoot='..tostring(session.bat and session.bat:getContainer()==session.root)
     ..' pages='..session.front:getAlreadyReadPages()..','..session.tail:getAlreadyReadPages())
   end
   return
  end
  if pending.checkpoint then
   local outcome=Fixture.verify(session,Selection.mode,true)
   session.checkpointed=true
   print('[EQUIPMENT_TEST] CHECKPOINT case='..session.id)
   reply(pending.player,'Checkpointed',{case=session.id,ok=true,outcome=outcome})
  else
   Fixture.refresh(session)
   local passed,problem=pcall(Postprocess.verify,session,Selection.mode,getActivatedMods():contains('P4TidyUpMeister'))
   session.verified=true
   if passed and (session.id=='tidy-group' or session.id=='tidy-multigroup') then
    print('[EQUIPMENT_TEST] GROUP_AUTHORITY '..JSON.encode({case=session.id,items=problem.groupItems,tailCompleted=true}))
   end
   if passed and Hotbar.isCase(session.id)then
    print('[EQUIPMENT_TEST] HOTBAR_AUTHORITY '..JSON.encode(problem.hotbar))
   end
   if passed and Clothing.isCase(session.id)then
    print('[EQUIPMENT_TEST] CLOTHING_AUTHORITY '..JSON.encode(problem.clothing))
   end
   if passed then
    print('[EQUIPMENT_TEST] AUTHORITY case='..session.id..' inventoryPreserved=true equipmentMatches=true tailCompleted=true')
   else print('[EQUIPMENT_TEST] POSTPROCESS_FAILED case='..session.id..' '..tostring(problem)) end
   reply(pending.player,'Verified',{case=session.id,ok=true,passed=passed,error=not passed and tostring(problem) or nil})
  end
  pending=nil
 end)
 if not ok then
  print('[QUEUE_TEST] FAIL equipment server '..tostring(problem))
  reply(pending.player,'Failed',{ok=false,error=tostring(problem)});pending=nil
 end
end)
