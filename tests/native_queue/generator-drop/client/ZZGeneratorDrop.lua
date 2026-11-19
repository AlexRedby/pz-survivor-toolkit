require 'TimedActions/ISTakeGenerator'
local config=require 'QueueTestSelection'
local P=require 'QueueEnergyPlacement'
local A=require 'QueueGeneratorDropAuthority'
local case=assert(config.cases[1])
local started,done,layout,placement,proof,ids,result,action,announced,sinceVerify,clientTarget,clientDecoy,go
local phase,since='layout',0
local function role(player)return config.kind=='sp'and'client1'or player:getUsername()end
local function send(command,args)
 args=args or{};args.case=case
 if config.kind=='mp'then sendClientCommand('GeneratorDropTest',command,args)
 elseif command=='Layout'then layout=A.layout(getPlayer(),case)
 elseif command=='Prepare'then A.prepare(getPlayer(),case,args.target,args.clientPlacement);ids=A.seed()
 elseif command=='Ready'then go=A.ready(getPlayer(),case)
 elseif command=='Started'then A.started(getPlayer(),case)
 elseif command=='Verify'then result=A.verify(getPlayer(),case)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~='GeneratorDropTest'then return end
 if args.ok==false then done=true;print('[QUEUE_TEST] FAIL generator-drop '..tostring(args.error));return end
 assert(args.case==case,'generator server case differs')
 if command=='Layout'then layout=args elseif command=='Prepared'then ids=args elseif command=='Verified'then result=args
 elseif command=='Begin'then go=true end
end)
require('QueuePreflight').onGameStart(Events,function()
 started=true;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false)
 if not isClient()then getPlayer():setGhostMode(true)end
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
require('QueuePreflight').onTick(Events,function()
 if not started or done or not isIngameState()then return end
 local ok,problem=pcall(function()
  assert(getTimestampMs()-since<180000,'generator fixture timeout '..phase)
  local player=getPlayer();if not player or not player:getSquare()or player:isDead()then return end
  if config.kind=='mp'and(not isClient()or player:getOnlineID()<0)then return end
  if phase=='layout'then send('Layout');phase='placement';return end
  if phase=='placement'then
   if not layout then if getTimestampMs()-(announced or 0)>1000 then send('Layout');announced=getTimestampMs()end;return end
   placement=placement or P.beginCentered(player,layout.target)
   proof=P.poll(placement);if not proof then return end
   send('Prepare',{target=layout.target,clientPlacement=proof});phase='prepared';return
  end
  if phase=='prepared'then
   if not ids then return end
   assert(ids.owner=='client1'and ids.picker==(config.kind=='sp'and'client1'or'client2'),'generator peer ownership differs')
   local square=getCell():getGridSquare(ids.x,ids.y,ids.z);if not square then return end
   local target,decoy
   local objects=square:getObjects()
   if ids.objectIndex<objects:size()then target=objects:get(ids.objectIndex)end
   if ids.decoyIndex<objects:size()then decoy=objects:get(ids.decoyIndex)end
   if not target or not decoy or not instanceof(target,'IsoGenerator')or not instanceof(decoy,'IsoGenerator')then return end
   if target:getCondition()~=73 or decoy:getCondition()~=41 then return end
   assert(math.abs(target:getFuel()-7.5)<.01 and math.abs(decoy:getFuel()-3.25)<.01,
    'client generator fuel differs before pickup')
   assert(target~=decoy and target:getSquare()==decoy:getSquare(),'client same-square targets overlap')
   if role(player)=='client1'and not player:getInventory():getItemById(ids.razorId)then return end
   clientTarget,clientDecoy=target,decoy
   send('Ready');phase='pickup';return
  end
  if phase=='pickup'then
   if not go then return end
   if role(player)~=ids.picker then phase='receipt';return end
   assert(P.atCentered(player,layout.target),'picker left prepared standing square')
   assert(not player:isTimedActionInstant(),'generator pickup must use native duration')
   action=ISTakeGenerator:new(player,clientTarget);assert(action:getDuration()==100,'native generator pickup duration changed')
   ISTimedActionQueue.add(action);phase='running';return
  end
  if phase=='running'then
   if not announced or type(announced)=='number'then
    if not action:isStarted()or action:getJobDelta()<=0 then return end
    announced=true;print('[GENERATOR_DROP] STARTED '..case);send('Started')
   end
   if player:hasTimedActions()or #ISTimedActionQueue.getTimedActionQueue(player).queue>0 then return end
   send('Verify');phase='receipt';return
  end
  if phase=='receipt'then
   if not result then
    if role(player)==(ids and ids.picker)and getTimestampMs()-(sinceVerify or 0)>1000 then
     sinceVerify=getTimestampMs();send('Verify')
    end
    return
   end
   assert(result.case==case and result.distinctDecoy and result.exactAfterDrop and result.missingAfterTake
    and result.decoyStillPresent and result.ownerKeptRazor==(config.kind=='mp')and result.outputInBothHands
    and result.sourceFavorite and result.outputFavorite==false and result.originalId~=result.outputId,'generator authority result invalid')
   local owner=role(player)=='client1'
   local root=player:getInventory()
   if clientTarget:getObjectIndex()~=-1 then return end
   assert(clientDecoy:getObjectIndex()>=0 and clientDecoy:getCondition()==41
    and math.abs(clientDecoy:getFuel()-3.25)<.01,'client same-square decoy disappeared/changed')
   assert(root:getItemById(ids.originalId)==nil,'client original generator ID remained in inventory')
   if owner and not root:getItemById(ids.razorId)then return end
   if owner and config.kind=='mp'and player:getPrimaryHandItem()~=root:getItemById(ids.razorId)then return end
   if role(player)==ids.picker then
    local output=root:getItemById(result.outputId)
    if not output or player:getPrimaryHandItem()~=output or player:getSecondaryHandItem()~=output then return end
    assert(output:getFullType()==result.type and output:getCondition()==result.condition and not output:isFavorite()
     and math.abs((output:getModData().fuel or 0)-result.fuel)<.01,'client generator output differs')
   end
   done=true;print('[GENERATOR_DROP] COMPLETE '..case)
  end
 end)
 if not ok then done=true;print('[QUEUE_TEST] FAIL generator-drop '..tostring(problem))end
end)
