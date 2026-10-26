require 'TimedActions/ISWashYourself'
local B=require 'QueueWashingBodyFixture'
local JSON=require 'QueueHealthEvents'
local M={};local active
local T=PZSurvivorToolkit
local methods={'new','start','perform','complete','stop','getDuration','isValid','washPart','removeAllMakeup','removeMakeup','onCompleteFunc','onCompleteArgs'}
local function queue(run)return ISTimedActionQueue.getTimedActionQueue(run.player)end
local function soaps(list,soap)
 local r={shape='java-list',count=list:size(),items={},ownOnly=list:size()==1 and list:get(0)==soap}
 for i=0,list:size()-1 do local item=list:get(i);r.items[#r.items+1]={id=item:getID(),kind=item:getFullType(),uses=item:getCurrentUses()}end;return r
end
local function remember(run,action)
 if run.seen[action]or action.Type~='ISWashYourself'or action.character~=run.player then return end
 local contract,id=T.ActionQueueDefinitions.inspect(action)
 local row={kind=action.Type,actorId=action.character:getOnlineID(),duration=action:getDuration(),progress=false,behavior=id,sourceProof=contract~=nil,
  begin={perform=0,complete=0,stop=0},finish={perform=0,complete=0,stop=0},sharedFinish={perform=0,complete=0,stop=0},
  sinkMatches=action.sink==run.state.sink,soaps=soaps(action.soaps,run.state.soap),requiredWater=ISWashYourself.GetRequiredWater(run.player),requiredSoap=ISWashYourself.GetRequiredSoap(run.player)}
 local saved={};for _,name in ipairs(methods)do saved[name]=action[name]end
 run.seen[action]={row=row,methods=saved};run.records[#run.records+1]=row
 if run.reset then run.lateSourceActions=run.lateSourceActions+1 end
end
assert(T.ActionQueueLifecycle.registerObserver('native-washing-body-fixture',{
 begin=function(action,phase)
  if not active then return end;remember(active,action);local entry=active.seen[action]
  if entry and entry.row.begin[phase]~=nil then entry.row.begin[phase]=entry.row.begin[phase]+1;return true end
 end,
 finish=function(action,phase,succeeded)
  if not active then return end;local entry=active.seen[action]
  if entry and entry.row.finish[phase]~=nil then
   entry.row.finish[phase]=entry.row.finish[phase]+1
   if T.ActionQueueLifecycle.current(action.character)==action then entry.row.sharedFinish[phase]=entry.row.sharedFinish[phase]+1 end
   if succeeded~=true then entry.row.failedBoundary=true end
  end
 end
}),'body lifecycle observer registration failed')
local defer=T.ActionQueueOperations.deferCompletion
T.ActionQueueOperations.deferCompletion=function(q,action)
 local result=defer(q,action);if result and active and active.seen[action]then active.localDeferrals=active.localDeferrals+1 end;return result
end
function M.observe(run)
 assert(B.isDry(),'native body dry-weather baseline changed')
 for _,action in ipairs(queue(run).queue)do
  if run.reset and run.seen[action]then run.lateSourceActions=run.lateSourceActions+1 end
  remember(run,action)
 end
 local current=queue(run).current
 for action,entry in pairs(run.seen)do if current==action and action:isStarted()and action:getJobDelta()>0 then entry.row.progress=true end end
 if run.originalTail and current==run.originalTail and run.originalTail:isStarted()then run.originalTailStarted=true end
 local tail=run.freshTail or run.originalTail
 if tail and current==tail and tail:isStarted()and tail:getJobDelta()>0 then run.tailProgress=true end
end
function M.selectMenu(root,player,sink,soap)
 local selected,index,option;local visited={}
 local function walk(menu,depth)
  if depth>8 or visited[menu]then return end;visited[menu]=true
  for i,v in ipairs(menu.options)do
   if v.target==player and v.param1==sink and v.param3==root and v.param4==nil and v.param5==nil and v.param6==nil
    and type(v.onSelect)=='function'and not v.notAvailable and not v.isDisabled
    and v.param2 and v.param2.size and v.param2.get and v.param2:size()==1 and v.param2:get(0)==soap then
    assert(not selected,'ambiguous real Yourself menu');selected,index,option=menu,i,v
   end
   if v.subOption then walk(menu:getSubMenu(v.subOption),depth+1)end
  end
 end
 walk(root,0);return selected,index,option
end
local function read(run)
 local action=ISReadABook:new(run.player,run.state.book);assert(action.minutesPerPage==2 and action.maxTime>1 and not run.player:isTimedActionInstant(),'body reader native cost differs')
 ISTimedActionQueue.add(action);return action
end
function M.start(player,state,ids,enabled)
 local run={body=true,player=player,state=state,ids=ids,enabled=enabled,seen={},records={},localDeferrals=0,tailIndependent=true,tailProgress=false,originalTailStarted=false,lateSourceActions=0,reset=false}
 active=run
 assert(#queue(run).queue==0 and not player:hasTimedActions(),'body start requires real idle')
 assert(T.Settings.actionQueue()==enabled and T.ActionQueueCompat.isInstalled('WashFix'),'body source/setting proof absent')
 assert(T.ActionQueueCompat.verifySources('WashFix')and T.ActionQueueCompat.verifySources('P4TidyUpMeister'),'selected WashFix/P4 sources differ')
 local proof=require 'PZSurvivorToolkit/SourceProof'
 assert(proof.matches('media/lua/shared/TimedActions/ISWashYourself.lua',1510864116,nil,true),'native body source differs')
 local menu=ISContextMenu.get(player:getPlayerNum(),20,20);WS.WMI_BuildWashMenu(menu,{state.sink},player,state.sink,menu)
 local selected,index,option=M.selectMenu(menu,player,state.sink,state.soap);assert(selected,'real WashFix Yourself menu missing')
 run.menu={method='WS.WMI_BuildWashMenu+ISContextMenu.onMouseUp',choice='yourself',exactArguments=true,callback=tostring(option.onSelect),
  actorMatches=true,sinkMatches=true,closeContextMatches=option.param3==menu,soapList=soaps(option.param2,state.soap)}
 selected:setVisible(true);selected.mouseOver=index;selected:onMouseUp(0,0)
 M.observe(run);assert(#run.records==1,'Yourself did not enqueue exactly one real native body action')
 run.originalTail=read(run)
 if enabled then
  local token=run.originalTail.toolkitQueueOperation;assert(type(token)=='table','body reader has no independent token')
  for action in pairs(run.seen)do assert(action.toolkitQueueOperation~=token,'body reader grouped with washing')end
 end
 return run
end
function M.tick(run)
 M.observe(run)
 if run.ids.case~='body-cancel'or run.reset then return end
 local current=queue(run).current
 if not current or current.Type~='ISWashYourself'or not current:isStarted()or current:getJobDelta()<=0 then return end
 local progress=current:getJobDelta();assert(progress<.25,'body reset missed early native progress')
 assert(queue(run):indexOf(run.originalTail)~=-1 and not run.originalTail:isStarted(),'body old reader already ran')
 local generation=queue(run).toolkitOperationGeneration or 0;local token=current.toolkitQueueOperation;local oldTail=run.originalTail.toolkitQueueOperation
 ISTimedActionQueue.clear(run.player);run.reset=true;run.resetAt=getTimestampMs()
 run.resetProof={method='ISTimedActionQueue.clear',progress=progress,beforeGeneration=generation,afterGeneration=queue(run).toolkitOperationGeneration or 0,
  oldTailRemoved=queue(run):indexOf(run.originalTail)==-1}
 assert(run.resetProof.oldTailRemoved,'body native clear retained old reader')
 run.freshTail=read(run);run.resetProof.freshGeneration=queue(run).toolkitOperationGeneration or 0
 local fresh=run.freshTail.toolkitQueueOperation
 run.resetProof.freshIndependent=not run.enabled or type(fresh)=='table'and fresh~=token and fresh~=oldTail
end
function M.finish(run,authority,F)
 M.observe(run);local unchanged=true
 for action,entry in pairs(run.seen)do
  entry.row.methodsUnchanged=true
  for _,name in ipairs(methods)do if action[name]~=entry.methods[name]then unchanged=false;entry.row.methodsUnchanged=false end end
 end
 local row={event='case',id=run.ids.case,status='passed',menu=run.menu,records=run.records,sourceMethodsUnchanged=unchanged,nativeSourceVerified=true,
  localDeferrals=run.localDeferrals,tailProgress=run.tailProgress,tailIndependent=run.tailIndependent,originalTailStarted=run.originalTailStarted,
  reset=run.reset,resetProof=run.resetProof,lateSourceActions=run.lateSourceActions,lateObservedMs=run.resetAt and getTimestampMs()-run.resetAt or 0,
  actualResources=assert(B.verify({player=run.player,root=run.state.root,case=run.ids.case,ids=run.ids,sink=run.state.sink},F))}
 for k,v in pairs(authority)do if k~='case'then row[k]=v end end
 active=nil;return row
end
return M
