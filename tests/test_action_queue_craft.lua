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
    return {size = function() return #values end, get = function(_, index) return values[index + 1] end}
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
    assert(loadstring(source))()
    local refreshes = 0
    local neat = owner(NC_CraftActionPanel)
    neat.refreshAfterCraftBatch = function() refreshes = refreshes + 1 end
    neat.queuedCraftActions = {}
    local first, second = withOwner(handcraft(), neat), withOwner(handcraft(), neat)
    first.toolkitQueueOperation = {}; second.toolkitQueueOperation = first.toolkitQueueOperation
    assert(craft.supports(first) and craft.cancelWaiting(first) and craft.cancelWaiting(second))
    assert(refreshes == 1 and neat.craftTimes == nil and neat.queuedCraftActions == nil)
    local old = NC_CraftActionPanel.onHandcraftActionCancelled
    NC_CraftActionPanel.onHandcraftActionCancelled = function() end
    assert(not craft.supports(withOwner(handcraft(), neat)))
    NC_CraftActionPanel.onHandcraftActionCancelled = old
end
print('Craft/repair native identities, callback ownership, waiting UI cleanup and input dependencies passed.')
