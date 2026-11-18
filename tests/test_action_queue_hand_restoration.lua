-- Pure scheduling obligations only. These checks confer no native receipt,
-- completion, selected-mod or Host replication coverage.
local root = ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/'
local function setup()
    local env = setmetatable({PZSurvivorToolkit={}}, {__index=_G})
    env._G = env
    local function load(name) return assert(setfenv(assert(loadfile(root..name..'.lua')), env))() end
    local model, hands = load('ActionQueueEditModel'), load('ActionQueueHands')
    local hook, modelHook, calls, modelCalls = nil, nil, 0, 0
    local nativeEquip, nativeEvaluate = hands.equipResource, model.evaluate
    hands.equipResource = function(...)
        calls = calls+1
        if hook then hook() end
        return nativeEquip(...)
    end
    model.evaluate = function(...)
        modelCalls = modelCalls+1
        if modelHook then modelHook() end
        return nativeEvaluate(...)
    end
    env.require = function(name)
        if name=='PZSurvivorToolkit/ActionQueueHands' then return hands end
        assert(name=='PZSurvivorToolkit/ActionQueueEditModel'); return model
    end
    local planner = load('ActionQueueHandRestoration')
    return {env=env, hands=hands, model=model, planner=planner,
        hook=function(value) hook=value end, modelHook=function(value) modelHook=value end,
        calls=function() return calls end, modelCalls=function() return modelCalls end}
end
local opaqueMeta = {__index=function() error('item getter executed') end,
    __eq=function() error('item equality executed') end}
local function row(weapon)
    return {item=setmetatable({}, opaqueMeta), requiresBoth=false, handWeapon=weapon==true, handgun=false}
end
local function state(primary, secondary) return {primary=primary, secondary=secondary} end
local function copyRow(value)
    if value==false then return false end
    return {item=value.item, requiresBoth=value.requiresBoth, handWeapon=value.handWeapon, handgun=value.handgun}
end
local function copy(value) return state(copyRow(value.primary), copyRow(value.secondary)) end
local function sameRow(left, right)
    if left==false or right==false then return left==right end
    return rawequal(left.item,right.item) and left.requiresBoth==right.requiresBoth
        and left.handWeapon==right.handWeapon and left.handgun==right.handgun
end
local function same(left, right)
    assert(sameRow(left.primary,right.primary) and sameRow(left.secondary,right.secondary), 'hand plan changed unrelated slot or traits')
end
local function empty(value)
    for _ in pairs(value) do return false end
    return true
end
local function sealEntry(handle)
    local key,value
    for candidate,callback in pairs(handle) do
        assert(key==nil, 'opaque handle unexpectedly exposes more than its seal')
        key,value=candidate,callback
    end
    return key,value
end
local function refused(reason, value, actual)
    assert(value==nil and actual==reason, 'expected refusal '..reason..', got '..tostring(actual))
end
local function inputs(secondary, previousWeapon, toolWeapon)
    local previous, tool = row(previousWeapon), row(toolWeapon)
    if previousWeapon=='empty' then previous=false end
    return state(previous,secondary), state(tool,copyRow(secondary)), tool
end
local function capture(case, before, after, tool)
    return assert(case.planner.capture(before,after,tool), 'ordinary primary preparation refused')
end

-- The old primary can be empty, an ordinary object or single-hand weapon. Secondary
-- remains precisely the original opaque item (or empty), and never gets a write.
for _, secondary in ipairs({false,row(),row(true)}) do
    for _, previousWeapon in ipairs({false,true,'empty'}) do
        for _, toolWeapon in ipairs({false,true}) do
            local case = setup()
            local before,after,tool = inputs(secondary,previousWeapon,toolWeapon)
            local handle = capture(case,before,after,tool)
            local proposal,plan = case.planner.propose(handle,copy(after))
            local mode=before.primary==false and 'unequip' or 'primary'
            assert(proposal and plan.mode==mode and sameRow(plan.incoming,before.primary))
            assert(empty(proposal) and handle.before==nil and handle.after==nil, 'private snapshots escaped into handles')
            same(plan.expected,before)
            assert(case.calls()>0 and case.modelCalls()>=3, 'capture/proposal bypassed actual hand assignment projection')
            if mode=='primary' then assert(case.calls()>=3, 'occupied restore bypassed Hands assignment projection') end
            local consumed = assert(case.planner.consume(handle,proposal,copy(after)))
            same(consumed.expected,before)
            assert(consumed.mode==mode and sameRow(consumed.incoming,before.primary))
            refused('invalid_proposal',case.planner.consume(handle,proposal,after))
            refused('not_open',case.planner.propose(handle,after))
            refused('not_open',case.planner.waive(handle))
        end
    end
end

-- A separately qualified optional two-hand weapon is one exact prior item in
-- both slots. Native primary preparation clears its secondary grip, so its
-- inverse must project the real both-hands equip rather than a primary write.
for _, toolWeapon in ipairs({false,true}) do
    local case=setup()
    local previous,tool=row(true),row(toolWeapon)
    local before,after=state(previous,copyRow(previous)),state(tool,false)
    local originalBefore,originalAfter=copy(before),copy(after)
    local handle=capture(case,before,after,tool)
    before.primary.item=row().item;before.secondary.handWeapon=false
    after.primary.item=row().item;tool.handWeapon=not toolWeapon
    local proposal,plan=case.planner.propose(handle,originalAfter)
    assert(proposal and plan.mode=='both' and sameRow(plan.incoming,originalBefore.primary))
    same(plan.expected,originalBefore)
    assert(rawequal(plan.expected.primary.item,plan.expected.secondary.item), 'shared prior item identity lost')
    plan.mode='primary';plan.incoming.item=row().item;plan.expected.secondary=false
    local consumed=assert(case.planner.consume(handle,proposal,originalAfter))
    assert(consumed.mode=='both' and sameRow(consumed.incoming,originalBefore.primary))
    same(consumed.expected,originalBefore)
    refused('invalid_proposal',case.planner.consume(handle,proposal,originalAfter))
    refused('not_open',case.planner.propose(handle,originalAfter))
end

-- Neither a stale observation nor a new independent offhand authorizes the
-- two-hand restoration. Explicit user intent waives even an issued proposal.
do
    local case=setup()
    local previous,tool=row(true),row()
    local before,after=state(previous,copyRow(previous)),state(tool,false)
    local handle=capture(case,before,after,tool)
    for _, changed in ipairs({state(row(),false),state(tool,row()),state(tool,previous),state(previous,false)}) do
        refused('current_changed',case.planner.propose(handle,changed))
    end
    local proposal=assert(case.planner.propose(handle,after))
    for _, changed in ipairs({state(row(),false),state(tool,row()),state(tool,previous),state(previous,false)}) do
        refused('current_changed',case.planner.consume(handle,proposal,changed))
    end
    assert(case.planner.waive(handle))
    refused('invalid_proposal',case.planner.consume(handle,proposal,after))
    refused('not_open',case.planner.propose(handle,after))
    local pending=capture(case,before,after,tool)
    assert(case.planner.waive(pending))
    refused('not_open',case.planner.propose(pending,after))
end

-- The exception is only the exact shared prior weapon. It never accepts
-- unrelated secondary effects, a shared preparation tool or nonweapon overlap.
do
    local case=setup()
    local previous,tool=row(true),row()
    local before,after=state(previous,copyRow(previous)),state(tool,false)
    refused('secondary_changed',case.planner.capture(before,state(tool,previous),tool))
    refused('secondary_changed',case.planner.capture(before,state(tool,row()),tool))
    refused('assignment_mismatch',case.planner.capture(before,state(row(),false),tool))
    refused('assignment_mismatch',case.planner.capture(before,state(false,false),tool))
    refused('overlapping_hands',case.planner.capture(before,state(tool,tool),tool))
    local weaponTool=row(true)
    refused('overlapping_hands',case.planner.capture(before,state(weaponTool,weaponTool),weaponTool))
    local object=row()
    refused('overlapping_hands',case.planner.capture(state(object,object),after,tool))
    local different=copyRow(previous);different.handWeapon=false
    refused('overlapping_hands',case.planner.capture(state(previous,different),after,tool))
    local required=copyRow(previous);required.requiresBoth=true
    refused('unsupported_traits',case.planner.capture(state(required,required),after,tool))
    local handgun=copyRow(previous);handgun.handgun=true
    refused('unsupported_traits',case.planner.capture(state(handgun,handgun),after,tool))
    -- An opaque item shared with the incoming tool cannot become a loan.
    refused('unchanged_primary',case.planner.capture(before,state(previous,false),previous))
end

-- Caller-owned inputs and DTOs never become the obligation's private snapshot.
do
    local case = setup()
    local before,after,tool = inputs(row(),false,false)
    local originalBefore,originalAfter = copy(before),copy(after)
    local handle = capture(case,before,after,tool)
    before.primary.item=row().item; before.secondary.handWeapon=true
    after.primary.item=row().item; after.secondary=false; tool.handWeapon=true
    local proposal,plan = case.planner.propose(handle,originalAfter)
    assert(proposal);same(plan.expected,originalBefore)
    plan.mode='both';plan.incoming.item=row().item;plan.expected.primary=false;plan.expected.secondary=false
    local consumed = assert(case.planner.consume(handle,proposal,originalAfter))
    assert(consumed.mode=='primary' and sameRow(consumed.incoming,originalBefore.primary))
    same(consumed.expected,originalBefore)
end

-- A stale Host snapshot must neither authorize a write nor silently waive it.
-- Both an unrelated primary and secondary change refuse, including at consume.
do
    local case = setup()
    local before,after,tool = inputs(row(),false,false)
    local handle = capture(case,before,after,tool)
    refused('current_changed',case.planner.propose(handle,state(row(),after.secondary)))
    refused('current_changed',case.planner.propose(handle,state(after.primary,row())))
    local proposal = assert(case.planner.propose(handle,after))
    refused('current_changed',case.planner.consume(handle,proposal,state(row(),after.secondary)))
    refused('current_changed',case.planner.consume(handle,proposal,state(after.primary,row())))
    assert(case.planner.consume(handle,proposal,after), 'temporary mismatch implicitly waived obligation')
end

-- Empty-primary restoration keeps the same exact-tool and one-shot gates.
-- Detached DTOs and stale observations cannot change the independently held
-- secondary, waive the obligation, or authorize clearing a replacement tool.
do
    local case=setup()
    local before,after,tool=inputs(row(true),'empty',true)
    local originalBefore,originalAfter=copy(before),copy(after)
    local handle=capture(case,before,after,tool)
    before.secondary.item=row().item;after.primary.item=row().item;tool.handWeapon=false
    refused('current_changed',case.planner.propose(handle,state(row(true),originalAfter.secondary)))
    refused('current_changed',case.planner.propose(handle,state(originalAfter.primary,false)))
    local proposal,plan=case.planner.propose(handle,originalAfter)
    assert(proposal and plan.mode=='unequip' and plan.incoming==false and plan.expected.primary==false)
    same(plan.expected,originalBefore)
    plan.mode='primary';plan.incoming=row();plan.expected.primary=row();plan.expected.secondary=false
    refused('current_changed',case.planner.consume(handle,proposal,state(row(true),originalAfter.secondary)))
    refused('current_changed',case.planner.consume(handle,proposal,state(originalAfter.primary,row())))
    refused('invalid_proposal',case.planner.consume(handle,{},originalAfter))
    local consumed=assert(case.planner.consume(handle,proposal,originalAfter))
    assert(consumed.mode=='unequip' and consumed.incoming==false and consumed.expected.primary==false)
    same(consumed.expected,originalBefore)
    refused('invalid_proposal',case.planner.consume(handle,proposal,originalAfter))
    local waived=capture(case,originalBefore,originalAfter,originalAfter.primary)
    local pending=assert(case.planner.propose(waived,originalAfter))
    assert(case.planner.waive(waived))
    refused('invalid_proposal',case.planner.consume(waived,pending,originalAfter))
    refused('not_open',case.planner.propose(waived,originalAfter))
    refused('assignment_mismatch',case.planner.capture(originalBefore,state(row(),originalBefore.secondary),originalAfter.primary))
    refused('secondary_changed',case.planner.capture(originalBefore,state(originalAfter.primary,false),originalAfter.primary))
    refused('overlapping_hands',case.planner.capture(state(false,originalAfter.primary),state(originalAfter.primary,false),originalAfter.primary))
    local fresh=capture(case,originalBefore,originalAfter,originalAfter.primary)
    local evaluate=case.model.evaluate
    case.modelHook(function()
        refused('reentrant',case.planner.propose(fresh,originalAfter))
        case.model.evaluate=function() error('replacement invoked') end
    end)
    refused('source_changed',case.planner.propose(fresh,originalAfter))
    case.modelHook(nil);case.model.evaluate=evaluate
    assert(case.planner.propose(fresh,originalAfter), 'source refusal consumed empty-primary obligation')
end

-- Waiver represents distinct explicit intent; forged/cross-episode proposals
-- cannot consume or interfere with the genuine outstanding proposal.
do
    local case = setup()
    local before,after,tool = inputs(false,false,false)
    local first,second = capture(case,before,after,tool),capture(case,before,after,tool)
    local proposal = assert(case.planner.propose(first,after))
    local other = assert(case.planner.propose(second,after))
    local copied={};for key,value in pairs(first) do copied[key]=value end
    refused('unknown_obligation',case.planner.propose(copied,after))
    local marker,seal=sealEntry(first)
    assert(type(seal)=='function' and seal()==nil, 'seal exposed private state')
    local foreignCalls=0
    local forged={[marker]=function()
        foreignCalls=foreignCalls+1
        refused('reentrant',case.planner.capture(before,after,tool))
        refused('reentrant',case.planner.waive(first))
        return {before=before,after=after,phase='open'}
    end}
    refused('unknown_obligation',case.planner.propose(forged,after))
    assert(foreignCalls==1, 'forged-handle callback boundary changed')
    forged[marker]=function() seal() end
    refused('unknown_obligation',case.planner.propose(forged,after))
    refused('invalid_proposal',case.planner.consume(first,{},after))
    refused('invalid_proposal',case.planner.consume(first,other,after))
    refused('unknown_obligation',case.planner.propose({},after))
    refused('unknown_obligation',case.planner.waive({}))
    assert(case.planner.waive(first))
    refused('invalid_proposal',case.planner.consume(first,proposal,after))
    refused('not_open',case.planner.waive(first))
    assert(case.planner.consume(second,other,after))
    local open = capture(case,before,after,tool)
    assert(case.planner.waive(open))
    refused('not_open',case.planner.propose(open,after))
end

-- Only the observed primary prep delta can earn this narrow data obligation.
do
    local case = setup()
    local before,after,tool = inputs(row(),false,false)
    refused('unchanged_primary',case.planner.capture(after,after,tool))
    refused('secondary_changed',case.planner.capture(before,state(tool,false),tool))
    refused('assignment_mismatch',case.planner.capture(before,state(row(),before.secondary),tool))
    refused('assignment_mismatch',case.planner.capture(before,state(false,before.secondary),tool))
    refused('overlapping_hands',case.planner.capture(before,state(tool,tool),tool))
    refused('overlapping_hands',case.planner.capture(state(before.primary,tool),state(tool,false),tool))
    local altered=copyRow(tool);altered.handWeapon=true
    refused('inconsistent_traits',case.planner.capture(before,state(altered,before.secondary),tool))
    for _, position in ipairs({'before','after','tool'}) do
        for _, trait in ipairs({'requiresBoth','handgun'}) do
            local b,a,t = copy(before),copy(after),copyRow(tool)
            local selected = position=='before' and b.primary or position=='after' and a.primary or t
            selected[trait]=true
            if trait=='handgun' then selected.handWeapon=true end
            refused('unsupported_traits',case.planner.capture(b,a,t))
        end
    end
    for _, mutate in ipairs({
        function(b) b.extra=true end,
        function(b) b.secondary=nil end,
        function(b) b.primary.requiresBoth=nil end,
        function(b) b.primary.handWeapon=1 end,
        function(b) b.primary.item='public-id' end,
        function(b) b.primary.receipt={} end,
        function(b) setmetatable(b,{__index=function() error('state metadata executed') end}) end,
        function(b) setmetatable(b.primary,{__index=function() error('row metadata executed') end}) end,
    }) do
        local b=copy(before);mutate(b)
        refused('invalid_input',case.planner.capture(b,after,tool))
    end
    refused('invalid_input',case.planner.capture(before,after))
    refused('invalid_input',case.planner.capture(before,after,tool,true))
    local handle=capture(case,before,after,tool)
    refused('invalid_input',case.planner.propose(handle))
    refused('invalid_input',case.planner.consume(handle,{}))
    refused('invalid_input',case.planner.waive(handle,true))
end

-- The pure owner and its actual assignment/model functions are bound by exact
-- reference. Replacing a dependency during a projection commits no proposal.
do
    local case=setup()
    local before,after,tool=inputs(row(),false,false)
    local handle=capture(case,before,after,tool)
    local equip=case.hands.equipResource
    case.hook(function() case.hands.equipResource=function() error('replacement invoked') end end)
    refused('source_changed',case.planner.propose(handle,after))
    case.hook(nil);case.hands.equipResource=equip
    local evaluate=case.model.evaluate
    case.modelHook(function() case.model.evaluate=function() error('replacement invoked') end end)
    refused('source_changed',case.planner.propose(handle,after))
    case.modelHook(nil);case.model.evaluate=evaluate
    local proposal=assert(case.planner.propose(handle,after))
    case.env.PZSurvivorToolkit.ActionQueueHands={equipResource=equip}
    refused('source_changed',case.planner.consume(handle,proposal,after))
    case.env.PZSurvivorToolkit.ActionQueueHands=case.hands
    assert(case.planner.consume(handle,proposal,after))
end
do
    local case=setup()
    local before,after,tool=inputs(false,false,false)
    local handle=capture(case,before,after,tool)
    local nested=0
    case.hook(function()
        nested=nested+1
        refused('reentrant',case.planner.capture(before,after,tool))
        refused('reentrant',case.planner.propose(handle,after))
        refused('reentrant',case.planner.waive(handle))
    end)
    local proposal=assert(case.planner.propose(handle,after))
    assert(nested>0)
    case.hook(nil)
    assert(case.planner.consume(handle,proposal,after))
    -- Exceptions release the reentry guard and do not create/waive an episode.
    case.hook(function() error('projection unavailable') end)
    refused('invalid_input',case.planner.capture(before,after,tool))
    case.hook(nil)
    local fresh=capture(case,before,after,tool)
    assert(case.planner.waive(fresh))
end
print('Pure hand-restoration scheduling obligations passed.')
