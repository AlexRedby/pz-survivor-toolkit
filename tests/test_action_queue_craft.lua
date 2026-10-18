if not NativeActionRoot then
    print('Craft/repair native-contract checks skipped (pass --native-action-root media/lua).')
    return
end
require = function() end
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject = {derive = derive}
ISPanelJoypad = {derive = derive}
ISPanel = {derive = derive}
UIFont = {Small = 'Small'}
getTextManager = function() return {getFontHeight = function() return 12 end} end
instanceof = function(value, name) return value and value.class == name end
convertToPZNetTable = function(value) return value end
log = function() end
DebugType = {CraftLogic = 'CraftLogic'}
isClient = function() return false end
isServer = function() return false end
showDebugInfoInChat = function() end
getText = function(key) return key end
CharacterTrait = {ALL_THUMBS = 'AllThumbs'}
local function native(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
native('shared/TimedActions/ISBaseTimedAction.lua')
native('shared/TimedActions/ISFixAction.lua')
native('shared/TimedActions/ISCraftAction.lua')
native('shared/Entity/TimedActions/ISHandcraftAction.lua')
native('client/Entity/ISUI/CraftRecipe/ISWidgetHandCraftControl.lua')
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub("\r", "") end
    local file = assert(io.open(path)); local text = file:read('*a'); file:close()
    return text:gsub('\r', '')
end
ISInventoryPaneContextMenu = {}
assert(loadstring(assert(read(NativeActionRoot .. '/client/ISUI/ISInventoryPaneContextMenu.lua')
    :match('(ISInventoryPaneContextMenu.OnNewCraftComplete = function.-\nend)'))))()
PZSurvivorToolkit = {}
local craft = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCraft.lua'))()
local function list(...)
    local values = {...}
    return {class = 'List', size = function() return #values end, get = function(_, index) return values[index + 1] end}
end
local function item()
    return {class = 'InventoryItem', getName = function() return 'Item' end,
        setJobDelta = function(self, value) self.delta = value end}
end
local target, material, tool = item(), item(), item()
local player = {getInventory = function() return {} end, isTimedActionInstant = function() return false end,
    hasTrait = function() return false end, isWearingAwkwardGloves = function() return false end}
local recipe = {class = 'CraftRecipe', getTimedActionScript = function() return nil end,
    isCanWalk = function() return false end, getTime = function() return 10 end}
local fixing = {getRequiredItems = function() return list(material, tool) end,
    getFixers = function() return list({}) end}
FixingManager = {getFixes = function() return list(fixing) end}
local fix = ISFixAction:new(player, target, 0, 0)
local legacyRecipe = {isCanBeDoneFromFloor = function() return false end,
    isStopOnWalk = function() return true end, isStopOnRun = function() return true end,
    getTimeToMake = function() return 10 end, getName = function() return 'Recipe' end}
local legacy = ISCraftAction:new(player, target, legacyRecipe, {}, {})
local function handcraft()
    return ISHandcraftAction:new(player, recipe, {}, nil, nil, {[0] = list(material, tool)}, list(material), tool)
end
assert(craft.supports(fix) and craft.supports(legacy) and craft.supports(handcraft()))
local items = {}
local known, output = craft.collectItems(fix, items)
assert(not known and output and items[target] and items[material] and items[tool],
    'repair cancellation keeps known overlaps, but completion reselects donors so reordering stays protected')
items = {}; known, output = craft.collectItems(handcraft(), items)
assert(known and output and items[material] and items[tool])
local automatic = handcraft(); automatic.items, automatic.manualInputs = nil, false
assert(craft.supports(automatic) and not craft.collectItems(automatic, {}))
assert(not craft.collectItems(legacy, {}))
local stops = {}
local logic = {class = 'HandcraftLogic', getPlayer = function() return player end,
    stopCraftAction = function(_, all) stops[#stops + 1] = all == true and true or 'one' end}
local function owner(class)
    return setmetatable({player = player, logic = logic, craftTimes = 2}, class)
end
local function withOwner(action, panel)
    action:setOnStart(panel.onHandcraftActionStart, panel)
    action:setOnComplete(panel.onHandcraftActionComplete, panel)
    action:setOnCancel(panel.onHandcraftActionCancelled, panel)
    return action
end
local panel = owner(ISWidgetHandCraftControl)
local a, b = withOwner(handcraft(), panel), withOwner(handcraft(), panel)
a.toolkitQueueOperation = {}; b.toolkitQueueOperation = a.toolkitQueueOperation
assert(craft.supports(a) and craft.callbacksSafe(a))
-- Late UI entry/layout wrappers do not alter the native callbacks of an already built action.
for _, name in ipairs({'createChildren', 'calculateLayout', 'prerender', 'onButtonClick', 'startHandcraft'}) do
    local original, calls = ISWidgetHandCraftControl[name], 0
    local wrapper = function(...) calls = calls + 1; return original(...) end
    ISWidgetHandCraftControl[name] = wrapper
    assert(craft.supports(a) and craft.callbacksSafe(a), 'native class UI wrapper closed callback permission: ' .. name)
    ISWidgetHandCraftControl[name] = original
    panel[name] = wrapper
    assert(craft.supports(a) and craft.callbacksSafe(a), 'native instance UI wrapper closed callback permission: ' .. name)
    panel[name] = nil
    assert(calls == 0, 'checking callback permission must not run UI entry/layout wrappers')
end
for _, name in ipairs({'setCraftQuantity', 'sanitizeCraftQuantity', 'triggerEvent',
        'onHandcraftActionStart', 'onHandcraftActionComplete', 'onHandcraftActionCancelled'}) do
    local original, calls = ISWidgetHandCraftControl[name], 0
    local replacement = function() calls = calls + 1 end
    ISWidgetHandCraftControl[name] = replacement
    assert(not craft.supports(a) and not craft.callbacksSafe(a), 'changed native class callback dependency was trusted: ' .. name)
    ISWidgetHandCraftControl[name] = original
    panel[name] = replacement
    assert(not craft.supports(a) and not craft.callbacksSafe(a), 'changed native instance callback dependency was trusted: ' .. name)
    panel[name] = nil
    assert(calls == 0 and craft.supports(a), 'callback dependency check ran replacement or failed to restore native owner')
end
panel.triggerEvent = function() error('unknown native owner event helper') end
assert(not craft.supports(a), 'native owner helper overrides also close callback permission')
panel.triggerEvent = nil
items = {}; assert(craft.collectItems(a, items) and items[panel])
assert(craft.cancelWaiting(a) and craft.cancelWaiting(b) and #stops == 1 and stops[1] == true)
assert(panel.craftTimes == nil, 'cancel one waiting batch owner once without running completion')
local context = handcraft(); context:setOnComplete(ISInventoryPaneContextMenu.OnNewCraftComplete, logic)
assert(craft.supports(context) and craft.cancelWaiting(context) and #stops == 2)
local complete = ISInventoryPaneContextMenu.OnNewCraftComplete
ISInventoryPaneContextMenu.OnNewCraftComplete = function() end
context.onCompleteFunc = ISInventoryPaneContextMenu.OnNewCraftComplete
assert(not craft.supports(context))
ISInventoryPaneContextMenu.OnNewCraftComplete = complete
local unknown = handcraft(); unknown.onCompleteFunc = function() end
assert(not craft.supports(unknown) and not craft.cancelWaiting(unknown))
legacy.onCompleteFunc = function() error('legacy Craft All must never run') end
assert(not craft.supports(legacy))
local mismatched = withOwner(handcraft(), owner(ISWidgetHandCraftControl))
mismatched.onCompleteTarget = panel
assert(not craft.supports(mismatched))
local replaced = handcraft(); replaced.stop = function() end
assert(not craft.supports(replaced))
local derived = ISHandcraftAction:derive('ISHandcraftAction')
assert(not craft.supports(setmetatable(handcraft(), derived)), 'mod subclass spoofing native Type stays protected')
local active = handcraft(); active.action = {isStarted = function() return true end}
assert(craft.supports(active) and not craft.cancelWaiting(active))
local activePanel = owner(ISWidgetHandCraftControl)
active = withOwner(handcraft(), activePanel)
local activeTail = withOwner(handcraft(), activePanel)
active.toolkitQueueOperation = {}; activeTail.toolkitQueueOperation = active.toolkitQueueOperation
local beforeStop = #stops
assert(craft.nativeStopped(active) and #stops == beforeStop, 'marking native cleanup must not invoke callbacks')
local baseStop = ISBaseTimedAction.stop
ISBaseTimedAction.stop = function(value)
    assert(craft.nativeStopped(value) and #stops == beforeStop, 'native base stop precedes UI cancel/complete')
end
active:stop()
ISBaseTimedAction.stop = baseStop
assert(craft.cancelWaiting(activeTail) and #stops == beforeStop + 2 and activePanel.craftTimes == nil,
    'native stop invokes cancel and complete; waiting tails must not invoke cancel again')
context.onCompleteFunc = complete
assert(not craft.nativeStopped(context), 'context completion does not replace full waiting-owner cleanup')
local previousRequire, requireCalls = require, 0
require = function() requireCalls = requireCalls + 1; error('optional UI must not load') end
local otherPanel = owner({})
local unsupported = withOwner(handcraft(), otherPanel)
unsupported.onStartFunc, unsupported.onCompleteFunc, unsupported.onCancelFunc = function() end, function() end, function() end
assert(not craft.supports(unsupported) and not craft.supports(unsupported) and requireCalls == 0)
require = previousRequire
local badFix = ISFixAction:new(player, target, 0, 0)
badFix.fixing = {getRequiredItems = function() error('stale repair data') end}
assert(not craft.collectItems(badFix, {}))
local badInputs = handcraft(); badInputs.items, badInputs.manualInputs = {}, {[0] = {}}
assert(not craft.collectItems(badInputs, {}))
local reads = 0
badInputs.items = {size = function() reads = reads + 1; error('unknown list callback') end,
    get = function() reads = reads + 1; error('unknown list callback') end}
assert(not craft.collectItems(badInputs, {}) and reads == 0, 'unknown list methods must never execute during inspection')

-- The helper retains the actual native stop/completion paths; only the root queue owns tail preservation.
local resets = 0
local repairs = 0
FixingManager.fixItem = function() repairs = repairs + 1 end
ISTimedActionQueue = {getTimedActionQueue = function() return {resetQueue = function() resets = resets + 1 end} end}
player.setIsFarming = function() end
active = withOwner(handcraft(), owner(ISWidgetHandCraftControl))
active:stop()
fix:stop()
assert(resets == 2 and active.onCancelTarget.craftTimes == nil and target.delta == 0 and repairs == 0)
assert(fix:complete() and repairs == 1, 'native completion alone performs repair')
assert(craft.supports(active) and craft.supports(fix), 'native methods stay unchanged')

if NativeNeatCraftingSource or NativeWishlistWorkshopRoot then
    local source = NativeNeatCraftingSource or read(NativeWishlistWorkshopRoot
        .. '/3502080466/mods/Neat_Crafting/common/media/lua/client/Neat_Crafting/NC_CraftActionPanel.lua')
    NC_CraftActionPanel = ISPanel:derive('NC_CraftActionPanel')
    NC_CraftActionPanel.onHandcraftActionStart = function() error('unverified start') end
    NC_CraftActionPanel.onHandcraftActionComplete = function() error('unverified complete') end
    NC_CraftActionPanel.onHandcraftActionCancelled = function() error('unverified cancel') end
    assert(not craft.supports(withOwner(handcraft(), owner(NC_CraftActionPanel))),
        'initial unknown mod-owner callbacks must not become a trusted first snapshot')
    NC_CraftActionPanel = nil
    assert(loadfile(ProjectRoot .. '/tests/support/action_queue_craft_owner.lua'))()(source)
    local refreshes = 0
    local neat = owner(NC_CraftActionPanel)
    neat.HandCraftPanel = {updateContainers = function() refreshes = refreshes + 1 end}
    neat.queuedCraftActions = {}
    local first, second = withOwner(handcraft(), neat), withOwner(handcraft(), neat)
    first.toolkitQueueOperation = {}; second.toolkitQueueOperation = first.toolkitQueueOperation
    assert(craft.supports(first) and craft.cancelWaiting(first) and craft.cancelWaiting(second))
    assert(refreshes == 1 and neat.craftTimes == nil and neat.queuedCraftActions == nil)
    neat.refreshAfterCraftBatch = function() error('unknown owner helper') end
    assert(not craft.supports(withOwner(handcraft(), neat)), 'instance helper replacement also closes permission')
    neat.refreshAfterCraftBatch = nil
    local old = NC_CraftActionPanel.onHandcraftActionCancelled
    NC_CraftActionPanel.onHandcraftActionCancelled = function() end
    assert(not craft.supports(withOwner(handcraft(), neat)))
    NC_CraftActionPanel.onHandcraftActionCancelled = old
end

-- Missing manual inputs are pure ID checks over native containers, never recipe predicates.
do
    ResourceType, ItemType = {Item='Item'}, {CONTAINER='Container'}
    local function script(kind)
        return {class='Item',getFullName=function() return kind end,isItemType=function() return false end,
            getReplaceOnUse=function() end,getReplaceOnDeplete=function() end,
            getOnBreak=function() return kind=='Base.Plank' and 'OnBreak.Plank' end}
    end
    local function container()
        return {class='ItemContainer',items={},getItemById=function(self,id) return self.items[id] end}
    end
    local root,bag,floor=container(),container(),container()
    local function supply(id)
        return {class='InventoryItem',getID=function() return id end}
    end
    local material,tool=supply(101),supply(202)
    local input={class='InputScript',getResourceType=function() return ResourceType.Item end,
        isAcceptsAnyItem=function() return false end,getConsumeFromItemScript=function() end,
        getPossibleInputItems=function() return list(script('Base.Plank')) end,
        getCreateToItemScript=function() end,isReplace=function() return false end,
        getIntAmount=function() return 1 end,isVariableAmount=function() return false end}
    local kept={};for key,value in pairs(input) do kept[key]=value end
    local output={class='OutputScript',getResourceType=function() return ResourceType.Item end,
        getCreateToItemScript=function() end,getPossibleResultItems=function() return list(script('Base.WoodenStick2')) end}
    local manualRecipe={class='CraftRecipe',getTimedActionScript=function() end,
        isCanWalk=function() return false end,getTime=function() return 30 end,
        getScriptLines=function() return list('craftRecipe QueueManual { inputs { item 1 Base.Plank, } }') end,
        getInputs=function() return list(input,kept) end,getOutputs=function() return list(output) end,
        getIndexForIO=function(_,value) return value==input and 0 or 2 end,
        getIOForIndex=function(_,index) return index==0 and input or index==2 and kept end}
    local actor=setmetatable({getInventory=function() return root end},{__index=player})
    local function manual()
        return ISHandcraftAction:new(actor,manualRecipe,list(root,bag,floor),nil,nil,
            {[0]=list(material),[2]=list(tool)},list(material,tool))
    end
    root.items[101],bag.items[202]=material,tool
    assert(not craft.canSkip(manual()),'available exact input in a native bag is not lost')
    root.items[101]=nil
    assert(not craft.futureResources(manual()),'native OnBreak still prevents resource prediction')
    assert(craft.canSkip(manual()),'lost pinned material must skip only its pre-native craft operation')
    local replacement=supply(101);root.items[101]=replacement
    assert(not craft.canSkip(manual()),'MP replacement object with the same ID remains available')
    root.items[101]=nil;floor.items[101]=replacement
    assert(not craft.canSkip(manual()),'available exact floor input is not lost')
    floor.items[101]=nil
    local candidate=manual();candidate.action={isStarted=function() return true end}
    assert(not craft.canSkip(candidate),'allocated native actions retain their native/server stop behavior')
    candidate=manual();candidate.craftStarted=true
    assert(not craft.canSkip(candidate),'started craft cannot be skipped from its stale inputs')
    candidate=manual();candidate.craftStarted=nil
    assert(not craft.canSkip(candidate),'unknown craft-start state cannot grant preservation')
    candidate=manual();candidate.manualInputs=false
    assert(not craft.canSkip(candidate),'automatic selection has no pinned input contract')
    assert(not craft.canSkip(fix),'repair actions keep their native selection behavior')
    candidate=manual();candidate.force=true
    assert(not craft.canSkip(candidate),'forced native crafting retains native behavior')
    local calls=0
    candidate=manual();candidate.onCompleteFunc=function() calls=calls+1 end
    assert(not craft.canSkip(candidate) and calls==0,'foreign callbacks are neither trusted nor executed')
    candidate=manual();candidate.manualInputs[99]=list(material)
    assert(not craft.canSkip(candidate),'extra unknown IO selection closes the contract')
    candidate=manual();candidate.manualInputs[2]=nil
    assert(not craft.canSkip(candidate),'partial manual IO selection closes the contract')
    candidate=manual();candidate.manualInputs[2]=list()
    assert(not craft.canSkip(candidate),'empty manual IO selection closes the contract')
    candidate=manual();candidate.manualInputs={}
    assert(not craft.canSkip(candidate),'empty manual selection closes the contract')
    candidate=manual();candidate.manualInputs[2]=list({})
    assert(not craft.canSkip(candidate),'non-item manual entries close the contract')
    candidate=manual();candidate.manualInputs[2]=list(supply('unknown'))
    assert(not craft.canSkip(candidate),'non-native IDs close the contract')
    candidate=manual();candidate.manualInputs[2]={size=function() calls=calls+1;return 1 end}
    assert(not craft.canSkip(candidate) and calls==0,'foreign list getters are never inspected')
    candidate=manual();candidate.containers=list(root,{getItemById=function() calls=calls+1 end})
    assert(not craft.canSkip(candidate) and calls==0,'foreign container getters are never inspected')
    candidate=manual();candidate.containers={size=function() calls=calls+1;return 1 end}
    assert(not craft.canSkip(candidate) and calls==0,'foreign container-list getters are never inspected')
    candidate=manual();candidate.containers=list()
    assert(not craft.canSkip(candidate),'empty declared-container list closes the contract')
    local amount=input.getIntAmount
    for _,value in ipairs({0,2}) do
        input.getIntAmount=function() return value end
        assert(not craft.canSkip(manual()),'optional or incomplete input selection closes the contract')
    end
    input.getIntAmount=amount
    input.isVariableAmount=function() return true end
    assert(not craft.canSkip(manual()),'variable input selection closes the contract')
    input.isVariableAmount=function() return false end
    local io=manualRecipe.getIOForIndex;manualRecipe.getIOForIndex=function() return kept end
    assert(not craft.canSkip(manual()),'mismatched IO index closes the contract')
    manualRecipe.getIOForIndex=io
    local lines=manualRecipe.getScriptLines
    manualRecipe.getScriptLines=function() return list('OnCreate = UnknownCallback') end
    assert(not craft.canSkip(manual()),'recipe callbacks close the existing safe recipe contract')
    manualRecipe.getScriptLines=lines
    candidate=manual();candidate.logic={canPerformCurrentRecipe=function() calls=calls+1;error('must not execute') end}
    assert(craft.canSkip(candidate) and calls==0,'missing-input inspection does not execute recipe logic')
end

print('Craft/repair native identities, callback ownership, waiting UI cleanup and input dependencies passed.')
