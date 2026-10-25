if not NativeActionRoot then print('Queue recovery SKIP (pass --game).');return end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions');f.project('ActionQueuePolicy');f.project('ActionQueueLabels')
f.project('ActionQueue')
local player=f.player
isClient=function()return false end
local moving,dead,enabled,blocked=false,false,true,false
local natives={}
player.class='IsoPlayer'
player.isLocalPlayer=function()return true end
player.isDraggingCorpse=function()return false end
player.isPlayerMoving=function()return moving end
player.pressedMovement=function()return moving end
player.isDead=function()return dead end
player.hasTimedActions=function()return next(natives)~=nil end
player.getCharacterActions=function()return {contains=function(_,value)return natives[value]==true end}end
PZSurvivorToolkit.Settings.actionQueue=function()return enabled end
local captures,plans,starts=0,0,0
local class=ISBaseTimedAction:derive('FixtureRecoveryAction')
function class:begin()
 starts=starts+1
 self.toolkitQueueOperation.toolkitStarted=true
 if PZSurvivorToolkit.ActionQueueRecovery then PZSurvivorToolkit.ActionQueueRecovery.started(self)end
 self.action={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
 natives[self.action]=true
end
local function action(label,kind,token)
 local a=ISBaseTimedAction.new(class,player)
 a.label=label;a.Type=kind or 'FixtureRecoveryAction';a.toolkitQueueOperation=token or {}
 return a
end
local adapters={capture=function(a,active)
 captures=captures+1
 if a.unsupported then return nil,'unsupported' end
 return {label=a.label,kind=a.Type,active=active}
end,plan=function(records,actor)
 plans=plans+1
 if blocked then return nil,'item_missing' end
 local fresh={}
 for _,record in ipairs(records)do
  local a=ISBaseTimedAction.new(class,actor);a.label=record.label;a.Type=record.kind
  fresh[#fresh+1]=a
 end
 return fresh
end}
local previous=require
require=function(name)if name=='PZSurvivorToolkit/ActionQueueRecoveryAdapters'then return adapters end;return previous(name)end
local recovery=f.project('ActionQueueRecovery')
local function drain()natives={}end
local function queue(...)
 local q=f.queue(...)
 return q
end
local function reset(q)
 q:resetQueue()
 assert(#q.queue==0 and q.current==nil)
end
local function infoCount(count,skipped)
 local info=assert(recovery.info(player))
 assert(info.count==count and info.skipped==(skipped or 0))
 return info
end
-- Native completion removes a prefix. A cancelled singleton page reader and
-- untouched operations recover under fresh objects/tokens, never the prefix.
do
 local done=action('already completed');local read=action('partly read','ISReadABook')
 local b,c=action('b'),action('c');local q=queue(done,read,b,c)
 q:onCompleted(done)
 assert(q.current==read and read.action)
 local oldToken=read.toolkitQueueOperation
 reset(q);local saved=infoCount(3)
 assert(oldToken.toolkitCancelled and recovery.preview(player).blocked=='settling')
 drain();moving=true;assert(recovery.preview(player).blocked=='moving');moving=false
 local before=starts;assert(recovery.preview(player).available and starts==before,'preview never begins native actions')
 assert(recovery.restore(player,saved.id))
 assert(q.queue[1]~=read and q.queue[1].label=='partly read' and #q.queue==3)
 assert(q.queue[1].toolkitQueueOperation~=oldToken and not q.queue[1].toolkitQueueOperation.toolkitCancelled)
 for _,a in ipairs(q.queue)do assert(a.label~='already completed')end
 assert(not recovery.info(player)and not recovery.restore(player,saved.id),'snapshot is consumed once')
end
-- Native clearQueue wipes the array without clearing current. Once Java has
-- drained, that stale pointer cannot keep restoration permanently disabled.
do
 drain();local a=action('cleared without reset');local q=queue(a)
 q:clearQueue();assert(#q.queue==0 and q.current==a)
 local saved=infoCount(1);assert(recovery.preview(player).available)
 assert(recovery.restore(player,saved.id)and q.current~=a and q.current.label=='cleared without reset')
end
-- A started operation contains paid prep/cleanup; do not resurrect pending
-- children from it. Whole untouched groups retain grouping with a new token.
do
 drain();local token={toolkitStarted=true};local a,b=action('paid',nil,token),action('cleanup',nil,token)
 local group={};local c,d=action('next 1',nil,group),action('next 2',nil,group)
 local q=queue(a,b,c,d);a:begin();reset(q);drain()
 local saved=infoCount(1,1);assert(recovery.restore(player,saved.id))
 assert(#q.queue==2 and q.queue[1].label=='next 1' and q.queue[2].label=='next 2')
 assert(q.queue[1].toolkitQueueOperation==q.queue[2].toolkitQueueOperation
  and q.queue[1].toolkitQueueOperation~=group and group.toolkitCancelled)
end
-- A partly supported operation is omitted as a unit; other supported operations
-- still require live validation. Failed validation retains the snapshot.
do
 drain();local token={};local a,b=action('known',nil,token),action('unknown',nil,token);b.unsupported=true
 local c=action('safe');local q=queue(a,b,c);reset(q);drain()
 local saved=infoCount(1,1);blocked=true
 assert(recovery.preview(player).blocked=='item_missing'and not recovery.restore(player,saved.id))
 assert(recovery.info(player).id==saved.id);blocked=false
 assert(recovery.restore(player,saved.id)and #q.queue==1 and q.queue[1].label=='safe')
end
-- A completion callback can be paid while its row is still present.
do
 drain();local a,b=action('paid but deferred','ISReadABook'),action('not begun')
 local q=queue(a,b);a:begin()
 assert(PZSurvivorToolkit.ActionQueueLifecycle.begin(a,'perform'))
 assert(PZSurvivorToolkit.ActionQueueLifecycle.completionEntered(q,a))
 reset(q);drain();local saved=infoCount(1)
 assert(recovery.restore(player,saved.id)and #q.queue==1 and q.queue[1].label=='not begun')
end
-- A paid-only native row is housekeeping, not a replacement cancellation.
do
 drain();local old=action('previous cancelled work');local q=queue(old);reset(q);drain()
 local saved=infoCount(1)
 local paid=action('finished row awaiting Java','ISReadABook');q=queue(paid);paid:begin()
 assert(PZSurvivorToolkit.ActionQueueLifecycle.begin(paid,'perform'))
 reset(q);drain();assert(recovery.info(player).id==saved.id)
 assert(recovery.restore(player,saved.id)and #q.queue==1 and q.queue[1].label=='previous cancelled work')
end
-- Direct native cancelQueue may not be followed by wipe. Any original action
-- that actually starts/completes afterward is tombstoned, not recoverable.
do
 drain();local a,b=action('actually completed'),action('cancelled')
 local q=queue(a,b);q:cancelQueue();infoCount(2)
 recovery.started(a);recovery.completed(a);infoCount(1)
 table.wipe(q.queue);q.current=nil
 local saved=infoCount(1);assert(recovery.restore(player,saved.id)and q.queue[1].label=='cancelled')
end
-- Empty housekeeping and unrelated new work cannot overwrite the last history.
-- A newer real cancellation and actor/settings changes invalidate stale UI IDs.
do
 drain();local a=action('first history');local q=queue(a);reset(q);local first=infoCount(1)
 q:resetQueue();assert(recovery.info(player).id==first.id)
 local new=action('new work');q=queue(new)
 assert(recovery.preview(player).blocked=='busy'and not recovery.restore(player,first.id))
 table.wipe(q.queue);q.current=nil
 assert(recovery.info(player).id==first.id)
 q=queue(action('new cancellation'));reset(q);local second=infoCount(1)
 assert(second.id~=first.id and not recovery.restore(player,first.id)and not recovery.forget(player,first.id))
 assert(recovery.info(player).id==second.id)
 enabled=false;assert(not recovery.info(player));enabled=true
 q=queue(action('death'));reset(q);dead=true;assert(not recovery.info(player));dead=false
 q=queue(action('forget'));reset(q);local saved=infoCount(1)
 assert(recovery.forget(player,saved.id)and not recovery.info(player))
 assert(not recovery.info(nil))
end
-- Split tokens and non-local/non-player native queues never grant recovery.
do
 drain();local token={};local a,b,c=action('split first',nil,token),action('independent'),action('split last',nil,token)
 local q=queue(a,b,c);reset(q);local saved=infoCount(1,2)
 assert(recovery.restore(player,saved.id)and #q.queue==1 and q.queue[1].label=='independent')
 recovery.capture({character={class='IsoGameCharacter'},queue={a}})
 assert(not recovery.info({class='IsoGameCharacter'}))
end
assert(captures>0 and plans>0)
print('Queue recovery: pre-wipe capture, completed-prefix exclusion, one-shot fresh tokens, grouping, settlement, stale resources/history and lifecycle guards passed.')
