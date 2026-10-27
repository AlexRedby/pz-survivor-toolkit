require 'Entity/ISEntityUI'
local config=require 'QueueTestSelection'
if config.suite~='plastic-battery'or config.cases[1]~='native-recipes'then return end
local F=require 'PlasticBatteryFixture'
local JSON=require 'QueueHealthEvents'
local started,done,owner,state,packet,authority,restored,restore,guard
local phase,index,since='prepare',1,0
local action,seen,menu,available,settleAt,diagnosticCount,serverDiagnostic
local function emit(event,data)print('[PLASTIC_BATTERY] '..event..' '..JSON.encode(data))end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function request(command)
 if isClient()then sendClientCommand(F.module,command,{index=index});return end
 if command=='Prepare'then
  if not owner then owner=F.init(getPlayer());restore,guard=F.install(function()return state end,function(row)emit('PERFORMED',row)end)end
  state=F.prepare(owner,index);packet=state.packet
 elseif command=='Verify'then authority=F.authority(state,guard);emit('AUTHORITY',authority)
 else F.restore(owner);restore();restored=true end
end
local function menuOptions(gun)
 local context=assert(ISInventoryPaneContextMenu.createMenu(0,true,{gun},150,150,getPlayerInventory(0).inventoryPane))
 local rows,selected={},nil
 local function scan(current)
  for _,option in ipairs(current.options or {})do
   if option.onSelect==ISInventoryPaneContextMenu.OnNewCraft and option.param1 then
    local name=option.param1:getScriptObjectFullType()
    assert(name=='Base.InsertBattery'or name=='Base.RemoveBattery','nonstandard battery menu path '..name)
    rows[#rows+1]={recipe=name,enabled=not option.notAvailable}
    if name==packet.recipe then assert(not selected,'duplicate battery menu option');selected=option end
   end
   if option.subOption then local child=current:getSubMenu(option.subOption);if child then scan(child)end end
  end
 end
 scan(context)
 return context,rows,selected
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~=F.module then return end
 if command=='Prepared'then packet=args
 elseif command=='Verified'then authority=args
 elseif command=='Diagnostic'then serverDiagnostic=args;emit('AUTHORITY_DIAGNOSTIC',args)
 elseif command=='Restored'then restored=true end
end)
local function diagnose(reason)
 local q=queue();local actions={}
 for _,value in ipairs(q.queue)do
  actions[#actions+1]={type=value.Type or '',current=q.current==value,
   nativeAction=value.action~=nil,started=value.action~=nil and value:isStarted()or false}
 end
 local row=state and F.diagnostic(state)or {index=index}
 row.reason=reason;row.elapsedMs=getTimestampMs()-since;row.actions=actions
 row.hasTimedActions=getPlayer():hasTimedActions();row.nativeActionCount=getPlayer():getCharacterActions():size()
 row.performingAction=getPlayer():getVariableBoolean('IsPerformingAnAction')
 row.craftObserved=seen==true;row.currentType=q.current and q.current.Type or ''
 row.actionQueued=action~=nil and q:indexOf(action)~=-1
 row.actionStarted=action~=nil and action.action~=nil and action:isStarted()or false
 emit('CLIENT_DIAGNOSTIC',row)
 if isClient()and packet then sendClientCommand(F.module,'Diagnose',{index=index})end
end
Events.OnGameStart.Add(function()
 started=true;getPlayer():setGodMod(true);getPlayer():setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
 emit('RECIPES',F.recipes('client1'))
end)
Events.OnTick.Add(function()
 if not started or done or not getPlayer()or not getPlayer():getSquare()then return end
 local ok,problem=pcall(function()
  if phase=='prepare'then
   if config.kind=='mp'and(not isClient()or getPlayer():getOnlineID()<0)then return end
   assert(#queue().queue==0 and not getPlayer():hasTimedActions(),'queue not idle')
   assert(not getPlayer():isTimedActionInstant(),'native duration requires ordinary timed actions')
   packet=nil;authority=nil;action=nil;seen=false;settleAt=nil;diagnosticCount=0;serverDiagnostic=nil
   request('Prepare');since=getTimestampMs();phase='resolve'
  elseif phase=='resolve'then
   assert(getTimestampMs()-since<30000,'fixture replication timeout')
   if not packet then return end
   local inventory=getPlayer():getInventory();local gun=inventory:getItemById(packet.gunID)
   if not gun then return end
   if isClient()then state={player=getPlayer(),packet=packet}end
   if not settleAt then settleAt=getTimestampMs()+1500 end
   if getTimestampMs()<settleAt then return end
   -- A zero-use Battery disappears normally before recipe admission; empty guns persist.
   local recipe=assert(getScriptManager():getCraftRecipe(packet.operation=='insert'and 'InsertBattery'or 'RemoveBattery'))
   local logic=HandcraftLogic.new(getPlayer(),nil,nil)
   logic:setIsoObject(logic:findCraftSurface(getPlayer(),2))
   logic:setContainers(ISInventoryPaneContextMenu.getContainers(getPlayer()))
   logic:setRecipeFromContextClick(recipe,gun);available=logic:canPerformCurrentRecipe()
   emit('READY',{index=index,packet=packet,items=F.snapshot(getPlayer()),available=available})
   assert(available==(packet.requestedCharge>0),'unexpected native admission')
   getPlayerInventory(0).inventoryPane:refreshContainer()
   local context,rows,option=menuOptions(gun);menu=rows
   assert(#menu==(available and 1 or 0),'unexpected standard menu path count')
   if not available then context:hideAndChildren();phase='running';since=getTimestampMs();return end
   assert(option and not option.notAvailable,'native battery menu unavailable')
   option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6)
   context:hideAndChildren()
   for _,value in ipairs(queue().queue)do
    if value.Type=='ISHandcraftAction'then
     assert(not action and value.craftRecipe:getScriptObjectFullType()==packet.recipe,'unexpected craft')
     action=value
    end
   end
   assert(action,'native callback did not queue craft')
   emit('ENQUEUED',{index=index,recipe=packet.recipe,duration=action:getDuration(),queueCount=#queue().queue})
   assert(action:getDuration()==recipe:getTime(getPlayer())*5 and action:getDuration()>1,'native duration changed')
   phase='running';since=getTimestampMs()
  elseif phase=='running'then
   if action and queue().current==action and action.action and action:isStarted()then seen=true end
   local elapsed=getTimestampMs()-since
   if diagnosticCount==0 and elapsed>=5000 then diagnosticCount=1;diagnose('running after 5s')end
   if diagnosticCount==1 and elapsed>=40000 then diagnosticCount=2;diagnose('running before deadline')end
   assert(elapsed<45000,'native battery craft/effect timed out')
   if #queue().queue~=0 or getPlayer():hasTimedActions()or not F.effectReady(state)then return end
   assert(not available or seen,'native craft never observed running')
   emit('LOCAL',F.receipt(state,'local'))
   emit('NATIVE',{index=index,recipe=packet.recipe,gunID=packet.gunID,available=available,menu=menu,
    queueDrained=true,craftObserved=seen,nativeDuration=action~=nil,
    duration=action and action:getDuration()or 0})
   phase='verify';since=getTimestampMs();request('Verify')
  elseif phase=='verify'then
   assert(getTimestampMs()-since<25000,'authority timeout')
   if not authority then return end
   if index<#F.plans then index=index+1;phase='prepare'
   else request('Restore');phase='restore';since=getTimestampMs()end
  elseif phase=='restore'then
   assert(getTimestampMs()-since<25000,'inventory restoration timeout')
   if not restored then return end
   if isClient()then
    for _,item in ipairs(packet.before)do
     if getPlayer():getInventory():getItemById(item.id)then return end
    end
   end
   done=true;emit('COMPLETE',{case='native-recipes',role='client1',phases=6,restored=true})
  end
 end)
 if not ok then
  if state then pcall(function()
   local row=F.diagnostic(state);row.actions=#queue().queue;row.hasTimedActions=getPlayer():hasTimedActions()
   row.craftObserved=seen==true;row.serverDiagnostic=serverDiagnostic or {};emit('FAIL_DIAGNOSTIC',row)
  end)end
  if restore then pcall(restore)end
  done=true;emit('FAIL',{index=index,phase=phase,error=tostring(problem)})
 end
end)
