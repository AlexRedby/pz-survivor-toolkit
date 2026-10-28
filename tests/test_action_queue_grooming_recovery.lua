if not NativeActionRoot then print('Trim recovery proof SKIP (pass --game).');return end
GroomingNativeSetupOnly=true
local nativeSetup=assert(loadfile(ProjectRoot..'/tests/test_action_queue_grooming_active.lua'))()
GroomingNativeSetupOnly=nil
local function read(path)
 if NativeReadText then return NativeReadText(path):gsub('\r','')end
 local file=assert(io.open(path));local value=file:read('*a');file:close();return value:gsub('\r','')
end
local function setup(allowRejected)
 ItemTag={RAZOR={},SCISSORS={}}
 local s=nativeSetup('ISTrimBeard',false,{pending=true})
 s.grooming=PZSurvivorToolkit.ActionQueueGrooming
 local actor,tool,root=s.player,s.tool,s.player.inventory
 actor.primary=tool
 actor.getPrimaryHandItem=function()return actor.primary end
 actor.getSecondaryHandItem=function()return actor.secondary end
 tool.getIsCraftingConsumed=function()return tool.consumed==true end
 tool.hasTag=function(_,tag)return not tool.untagged and (tag==ItemTag.RAZOR or tag==ItemTag.SCISSORS)end
 tool.getType=function()return 'Scissors'end
 tool.isBroken=function()return false end
 tool.container=root;tool.getContainer=function()return tool.container end
 local contains,byID=root.getItems,root.getItemById
 root.getItems=function()
  local values=contains(root)
  values.size=function()return tool.present~=false and 1 or 0 end
  values.get=function(_,i)return i==0 and tool.present~=false and tool or nil end
  return values
 end
 s.rootByID=byID
 s.recovery=s.f.project('ActionQueueRecoveryAdapters')
 if not allowRejected then assert(s.grooming.canRecoverTrim(s.body),'actual installed pending trim lacked recovery proof')end
 return s
end
local function reject(s,label)
 assert(s.grooming.canRecoverTrim(s.body)==false,'unsafe trim retained recovery proof: '..label)
 assert(not s.recovery.capture(s.body,false),'unsafe trim retained recovery capture: '..label)
end

-- Execute only the real UI producer and its native tool predicates. No panel,
-- callback, styling effect or constructor is invoked by inspection or preview.
local s=setup()
local source=read(NativeActionRoot..'/client/XpSystem/ISUI/ISCharacterScreen.lua')
local razor=assert(source:match('(local function predicateRazor.-\nend)'))
local scissors=assert(source:match('(local function predicateScissors.-\nend)'))
local producer=assert(source:match('(ISCharacterScreen.onTrimBeard = function.-\nend)'))
ISCharacterScreen={};ISWorldObjectContextMenu={equip=function(actor,_,tool,primary)
 assert(actor==s.player and tool==s.tool and primary==true);actor.primary=tool
end}
s.player.primary=nil
s.player.inventory.getFirstEvalRecurse=function(_,predicate)return predicate(s.tool)and s.tool or nil end
local originalAdd=ISTimedActionQueue.add
local produced
ISTimedActionQueue.add=function(action)assert(not produced);produced=action end
assert(loadstring(razor..'\n'..scissors..'\n'..producer,'@ISCharacterScreen.lua'))()
ISCharacterScreen.onTrimBeard(s.player,'')
ISTimedActionQueue.add=originalAdd
assert(produced and produced~=s.body and s.grooming.canRecoverTrim(produced),'native primary-hand producer rejected')
local intent=assert(s.recovery.capture(produced,false))
assert(intent.kind=='trim'and intent.beardStyle==''and intent.singleton==true and intent.itemId==s.tool:getID())
assert(s.recovery.validate({intent},s.player),'pure trim preview rejected')
local restored=assert(s.recovery.plan({intent},s.player))
assert(#restored==1 and restored[1]~=produced and restored[1].item==s.tool and restored[1].beardStyle=='')
assert(restored[1].toolkitQueueOperation==nil and restored[1].action==nil,'restored trim retained episode state')
s.player.primary=nil;s.player.secondary=s.tool
assert(s.grooming.canRecoverTrim(produced)and s.recovery.validate({intent},s.player),'secondary held trim rejected')
local preview=setmetatable({Type='ISTrimBeard',character=s.player,item=s.tool,beardStyle='',maxTime=300},ISTrimBeard)
assert(s.grooming.canRecoverTrim(preview),'pure constructor-free preview probe rejected')
print('PASS actual native trim producer, installed pending proof, pure recovery preview and fresh construction')

for _,case in ipairs({'native','started','transaction','native-kind','token-started','token-canceled','token-invalid','token-metatable',
 'sound','duration','instant','style','missing-style','walk-default','run-default','aim-default','calories-default',
 'callback','context','adding','linked','progress','wounds','class-method','class-added','instance-helper','base-method',
 'base-added','base-index','class-index','class-meta-index','class-owner','base-owner','global','global-classifier','filename','source-api','pending-api','pending-owner',
 'policy-api','policy-owner','lifecycle-api','lifecycle-owner','grooming-owner','tags-owner','tag-value',
 'unheld','consumed','broken','untagged','root-id','root-reference','detached','nested','foreign-player','asleep','dead'})do
 local x=setup()
 local body,actor,tool=x.body,x.player,x.tool
 if case=='native'then body.action={}
 elseif case=='started'then body.started=true
 elseif case=='transaction'then body.toolkitNativeTransaction=7
 elseif case=='native-kind'then body.toolkitNativeKind='ISTrimBeard'
 elseif case=='token-started'then body.toolkitQueueOperation.toolkitStarted=true
 elseif case=='token-canceled'then body.toolkitQueueOperation.toolkitCancelled=true
 elseif case=='token-invalid'then body.toolkitQueueOperation=true
 elseif case=='token-metatable'then body.toolkitQueueOperation=setmetatable({},{__index=function()error('token callback invoked')end})
 elseif case=='sound'then body.sound=1
 elseif case=='duration'then body.maxTime=1
 elseif case=='instant'then actor.isTimedActionInstant=function()return true end
 elseif case=='style'then body.beardStyle=false
 elseif case=='missing-style'then body.beardStyle='Missing'
 elseif case=='walk-default'then body.stopOnWalk=false
 elseif case=='run-default'then body.stopOnRun=false
 elseif case=='aim-default'then body.stopOnAim=false
 elseif case=='calories-default'then body.caloriesModifier=.5
 elseif case=='callback'then body.onCompleteFunc=function()error('callback invoked')end
 elseif case=='context'then body.additionalContext={}
 elseif case=='adding'then body._isAddingActions=true
 elseif case=='linked'then body.toolkitQueueLinked=true
 elseif case=='progress'then body.forceProgressBar=true
 elseif case=='wounds'then body.ignoreHandsWounds=true
 elseif case=='class-method'then ISTrimBeard.complete=function()error('effect invoked')end
 elseif case=='class-added'then ISTrimBeard.foreign=function()error('helper invoked')end
 elseif case=='instance-helper'then body.foreign=function()error('instance invoked')end
 elseif case=='base-method'then ISBaseTimedAction.stop=function()error('base invoked')end
 elseif case=='base-added'then ISBaseTimedAction.foreign=function()error('base helper invoked')end
 elseif case=='base-index'then ISBaseTimedAction.__index=function()error('base index invoked')end
 elseif case=='class-index'then ISTrimBeard.__index=function()error('class index invoked')end
 elseif case=='class-meta-index'then getmetatable(ISTrimBeard).__index=function()error('class parent index invoked')end
 elseif case=='class-owner'then ISTrimBeard={}
 elseif case=='base-owner'then ISBaseTimedAction={}
 elseif case=='global'then sendHumanVisual=function()error('global invoked')end
 elseif case=='global-classifier'then getClassSimpleName=function()error('classifier invoked')end
 elseif case=='filename'then getFilenameOfClosure=function()error('source accessor invoked')end
 elseif case=='source-api'then x.sourceProof.own=function()error('proof API invoked')end
 elseif case=='pending-api'then PZSurvivorToolkit.ActionQueueGroomingPending.apply=function()error('pending invoked')end
 elseif case=='pending-owner'then PZSurvivorToolkit.ActionQueueGroomingPending={}
 elseif case=='policy-api'then x.policy.addContainerResources=function()error('policy invoked')end
 elseif case=='policy-owner'then PZSurvivorToolkit.ActionQueuePolicy={}
 elseif case=='lifecycle-api'then PZSurvivorToolkit.ActionQueueLifecycle.hasNativeStopBridge=function()error('bridge invoked')end
 elseif case=='lifecycle-owner'then PZSurvivorToolkit.ActionQueueLifecycle={}
 elseif case=='grooming-owner'then PZSurvivorToolkit.ActionQueueGrooming={}
 elseif case=='tags-owner'then ItemTag={RAZOR={},SCISSORS={}}
 elseif case=='tag-value'then ItemTag.RAZOR={}
 elseif case=='unheld'then actor.primary=nil
 elseif case=='consumed'then tool.consumed=true
 elseif case=='broken'then tool.isBroken=function()return true end
 elseif case=='untagged'then tool.untagged=true
 elseif case=='root-id'then actor.inventory.getItemById=function()return {}end
 elseif case=='root-reference'then tool.present=false
 elseif case=='detached'then tool.container=nil
 elseif case=='nested'then tool.container={class='ItemContainer'}
 elseif case=='foreign-player'then actor.isLocalPlayer=function()return false end
 elseif case=='asleep'then actor.isAsleep=function()return true end
 elseif case=='dead'then actor.isDead=function()return true end end
 reject(x,case)
end
print('PASS trim episode/default/binding and exact root-held tool mutations fail closed without effects')

s=setup()
intent=assert(s.recovery.capture(s.body,false))
-- An inspector must reject changed native constructors without invoking them.
local calls=0
ISTrimBeard.new=function()calls=calls+1;error('preview called constructor')end
assert(not s.recovery.validate({intent},s.player)and calls==0,'pure preview invoked replaced trim constructor')
assert(not s.recovery.plan({intent},s.player)and calls==0,'restore invoked replaced trim constructor')
s=setup();intent=assert(s.recovery.capture(s.body,false))
ISBaseTimedAction.new=function()calls=calls+1;error('preview called base constructor')end
assert(not s.recovery.validate({intent},s.player)and calls==0,'pure preview invoked replaced base constructor')
s=setup();intent=assert(s.recovery.capture(s.body,false))
PZSurvivorToolkit.ActionQueueGrooming.canRecoverTrim=function()calls=calls+1;error('replacement recovery helper invoked')end
assert(not s.recovery.validate({intent},s.player)and calls==0,'preview invoked replaced grooming helper')
s=setup();s.body.beardStyle='Goatee'
intent=assert(s.recovery.capture(s.body,false))
assert(s.recovery.validate({intent},s.player),'native beard catalog style rejected')
local actions=assert(s.recovery.plan({intent},s.player))
assert(actions[1].beardStyle=='Goatee','restore changed requested beard style')
s.tool.consumed=true
assert(not s.recovery.validate({intent},s.player),'stale consumed tool passed preview')
print('PASS constructor/helper traps, live style validation and unavailable tool protect recovery')

-- Recheck current inputs between a successful preview and Restore. No captured
-- action, tool object or callback is retained as authority across that gap.
for _,case in ipairs({'unheld','consumed','detached','root-id','style-catalog'})do
 local x=setup();local record=assert(x.recovery.capture(x.body,false))
 assert(x.recovery.validate({record},x.player))
 if case=='unheld'then x.player.primary=nil
 elseif case=='consumed'then x.tool.consumed=true
 elseif case=='detached'then x.tool.container=nil
 elseif case=='root-id'then x.player.inventory.getItemById=function()return {}end
 elseif case=='style-catalog'then record.beardStyle='Missing'end
 assert(not x.recovery.plan({record},x.player),'restore ignored changed live inputs after preview: '..case)
end
s=setup();intent=assert(s.recovery.capture(s.body,false))
assert(s.recovery.validate({intent},s.player))
local replica={class='InventoryItem',getID=function()return intent.itemId end,
 getFullType=function()return intent.itemType end,getContainer=function()return s.player.inventory end,
 getIsCraftingConsumed=function()return false end,isBroken=function()return false end,
 hasTag=function(_,tag)return tag==ItemTag.SCISSORS end}
s.player.primary=replica
s.player.inventory.getItemById=function(_,id)return id==intent.itemId and replica or nil end
s.player.inventory.getItems=function()return {size=function()return 1 end,get=function(_,index)return index==0 and replica or nil end,
 contains=function(_,item)return item==replica end}end
local fresh=assert(s.recovery.plan({intent},s.player))
assert(fresh[1].item==replica and fresh[1].item~=s.tool,'restore reused captured object instead of current root ID replica')
local originalRead=NativeReadText
NativeReadText=function(path)
 local value
 if originalRead then value=originalRead(path)
 else local file=assert(io.open(path));value=file:read('*a');file:close()end
 if path:find('/shared/TimedActions/ISTrimBeard.lua',1,true)then value=value..'\n-- changed native source\n'end
 return value
end
ItemTag={RAZOR={},SCISSORS={}}
local changed=setup(true)
NativeReadText=originalRead
assert(not PZSurvivorToolkit.ActionQueueGrooming.canRecoverTrim(changed.body),'changed native source installed trim recovery')
print('PASS restore rechecks live tools/catalog, resolves fresh root ID replicas and rejects changed native source pins')
