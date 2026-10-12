-- Native Lua queue/base/book callbacks; Java lifecycle is exercised by the MP smoke.
require = function() end
local enabled, activePlayer = true, nil
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}}
getSpecificPlayer = function() return activePlayer end
getText = function(key) return key end
instanceof = function(value, name) return value.class == name end
local function derive(self, name)
    local t = {Type = name, derive = derive}
    t.__index = t
    return setmetatable(t, {__index = self})
end
ISBaseObject = {derive = derive}
table.wipe = function(t) for k in pairs(t) do t[k] = nil end end
Events = {OnTick = {Add = function() end}}
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
    'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do
    _G[name] = {instance = function() return {} end}
end
DebugType = {Action = {warn = function() end}}
ISLogSystem = {logAction = function() end}
if not NativeActionRoot then
    print('Action queue native-contract checks skipped (pass --native-action-root media/lua).')
    return
end
local function load(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
load('shared/TimedActions/ISBaseTimedAction.lua')
load('client/TimedActions/ISTimedActionQueue.lua')
load('shared/TimedActions/ISReadABook.lua')
LuaTimedActionNew = {new = function(t)
    return {table = t, started = false, progress = 0,
        isStarted = function(s) return s.started end,
        forceStop = function(s) s.stopping = true end,
        isForceComplete = function(s) return s.completing == true end,
        finished = function(s) return s.done == true end,
        hasStalled = function() return false end,
        getJobDelta = function(s) return s.progress end}
end}
local function player()
    local p = {class = 'IsoPlayer', actions = {}, farming = false, reading = false}
    function p:getPlayerNum() return 0 end
    function p:isDead() return self.dead == true end
    function p:isAsleep() return false end
    function p:isLocalPlayer() return true end
    function p:isDraggingCorpse() return false end
    function p:isFarming() return self.farming end
    function p:isPlayerMoving() return self.moving == true end
    function p:pressedMovement() return self.moving == true end
    function p:setIsFarming(v) self.farming = v end
    function p:setReading(v) self.reading = v end
    function p:playSound() end
    function p:setTimedActionToRetrigger(v) self.retrigger = v end
    function p:getCharacterActions()
        return {contains = function(_, action) return self.actions[action] == true end}
    end
    function p:StartAction(a) self.actions[a] = true end
    function p:StopAllActionQueue()
        for a in pairs(self.actions) do if a.started then a.table:stop() end end
        self.actions = {}
    end
    activePlayer = p
    return p
end
local function book(p)
    local a = ISBaseTimedAction.new(ISReadABook, p)
    a.maxTime = 1
    a.item = {delta = .5, getNumberOfPages = function() return 100 end,
        getAlreadyReadPages = function() return 12 end, getType = function() return 'BookCarpentry' end,
        setJobDelta = function(s,v) s.delta = v end, getDisplayName = function() return 'Book' end,
        class = 'InventoryItem'}
    a.start = function(self) self.character:setReading(true) end
    a.isValid = function(s) return not s.missing end
    a.perform = function(s) s.character:setReading(false); ISBaseTimedAction.perform(s) end
    return a
end
local completions = {}
local leafType = ISBaseTimedAction:derive('ToolkitTestLeaf')
local function leaf(p, name)
    local a = ISBaseTimedAction.new(leafType, p)
    a.maxTime, a.name, a.toolkitIndependentBulk = 1, name, true
    a.isValid = function(s) return not s.missing end
    a.perform = function(s) completions[#completions+1] = s.name; ISBaseTimedAction.perform(s) end
    return a
end
-- Uses the native updater's perform-before-stop and remove-after-stop ordering.
local function frame(p)
    local q = ISTimedActionQueue.getTimedActionQueue(p)
    local a = q.queue[1]
    if a and a.action and p.actions[a.action] then
        local j = a.action
        if not j.started then j.started = true; a:start() end
        if j.done or j.completing then a:perform() end
        if j.stopping or not a:isValid() then a:stop() end
        if j.stopping or j.done or j.completing or not a:isValid() then p.actions[j] = nil end
    end
    q:tick()
end
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueue.lua'))()
local api = PZSurvivorToolkit.ActionQueue
local p = player()
local a, b, c = book(p), book(p), leaf(p, 'tail')
local q = ISTimedActionQueue.add(a); ISTimedActionQueue.add(b); ISTimedActionQueue.add(c)
frame(p)
assert(api.cancel(q,b) and q.queue[1] == a and q.queue[2] == c and q.current == a)
assert(not api.cancel(q,b), 'stale identity must never cancel another row')
assert(api.cancel(q,a)); assert(q.current == a and q.queue[2] == c)
q:tick(); assert(q.current == a, 'wait for engine stop and packet before resuming')
frame(p)
assert(q.current == c and #q.queue == 1 and not p.reading and a.item.delta == 0)
assert(not q.toolkitCancel and not p.actions[a.action] and p.actions[c.action])
c.action.done = true; frame(p); assert(#q.queue == 0 and completions[1] == 'tail')
-- More than five rows; removal preserves all identities and order.
p = player(); q = ISTimedActionQueue.add(book(p)); local originals = {}
for i=1,20 do originals[i] = book(p); ISTimedActionQueue.add(originals[i]) end
assert(api.cancel(q, originals[10]) and #q.queue == 20)
for i=1,9 do assert(q.queue[i+1] == originals[i]) end
for i=11,20 do assert(q.queue[i] == originals[i]) end
-- Dependencies, callbacks and utility operations are never removed blindly.
local utility = leaf(p, 'transfer'); utility.toolkitIndependentBulk = nil; utility.Type = 'ISInventoryTransferAction'
ISTimedActionQueue.add(utility)
assert(not api.cancel(q, utility) and #q.queue == 21)
local linked = book(p); ISTimedActionQueue.addAfter(originals[1], linked)
assert(api.cancelReason(q, linked) == 'dependent' and api.cancelReason(q, originals[1]) == 'dependent')
local callback = book(p); callback.onCompleteFunc = function() error('must not invoke') end
ISTimedActionQueue.add(callback); assert(api.cancelReason(q, callback) == 'dependent')
local bulk = leaf(p, 'dismantle'); ISTimedActionQueue.add(bulk)
assert(api.cancel(q, bulk), 'independent pending bulk leaf')
bulk = leaf(p, 'dismantle'); ISTimedActionQueue.add(bulk)
local generator = leaf(p, 'generator'); generator.Type = 'ISQueueActionsAction'; generator.toolkitIndependentBulk = nil
ISTimedActionQueue.add(generator); assert(api.cancelReason(q, bulk) == 'dependent')
-- Started transfers/crafts are blocked; no item transaction API is called.
p = player(); a = leaf(p, 'active'); q = ISTimedActionQueue.add(a); frame(p)
assert(api.cancelReason(q, a) == 'active')
-- Skip one bulk operation, retaining the next selected weapon's native preparation.
p = player(); q = ISTimedActionQueue.add(book(p))
local first, equip, second = leaf(p,'first-weapon'), leaf(p,'equip'), leaf(p,'second-weapon')
equip.Type, equip.toolkitIndependentBulk, equip.toolkitBulkPreparation = 'ISEquipWeaponAction', nil, true
ISTimedActionQueue.add(first); ISTimedActionQueue.add(equip); ISTimedActionQueue.add(second)
assert(api.cancel(q, first) and q.queue[2] == equip and q.queue[3] == second)
assert(api.cancelReason(q, equip) == 'dependent', 'preparation itself remains protected')
-- A finishing read wins the native completion race; never complete it twice.
p = player(); a,b = book(p),leaf(p,'finish-race'); q = ISTimedActionQueue.add(a); ISTimedActionQueue.add(b)
assert(api.cancelReason(q,a) == 'starting'); frame(p)
a.action.done = true; assert(api.cancelReason(q,a) == 'starting'); a.action.done = false
assert(api.cancel(q,a)); a.action.completing = true; frame(p)
assert(q.current == b and #q.queue == 1 and not q.toolkitCancel)
-- Disable-after-click still drains an already accepted stop; no orphaned tail.
p = player(); a,b = book(p),leaf(p,'disabled'); q = ISTimedActionQueue.add(a); ISTimedActionQueue.add(b); frame(p)
assert(api.cancel(q,a)); enabled = false; frame(p); assert(q.current == b)
assert(not api.cancel(q,b)); enabled = true
-- External clear, movement, death/respawn and dropped Java stack cannot resurrect actions.
for _, mode in ipairs({'clear','move','dead','respawn','dropped'}) do
    p = player(); a,b = book(p),leaf(p,mode); q = ISTimedActionQueue.add(a); ISTimedActionQueue.add(b); frame(p)
    assert(api.cancel(q,a))
    if mode == 'clear' then ISTimedActionQueue.clear(p)
    elseif mode == 'move' then p.moving = true
    elseif mode == 'dead' then p.dead = true
    elseif mode == 'respawn' then activePlayer = player()
    else p.actions = {} end
    frame(p)
    assert(#q.queue == 0 and not q.toolkitCancel, mode .. ' retained/resurrected a tail')
end
-- Native invalid isValidStart on the successor retains the game's reset semantics.
p = player(); a,b = book(p),leaf(p,'missing-target'); b.isValidStart = function() return false end
q = ISTimedActionQueue.add(a); ISTimedActionQueue.add(b); frame(p); assert(api.cancel(q,a)); frame(p)
assert(#q.queue == 0 and q.current == nil, 'vanished successor must not be started')
assert(api.label(book(p)):find('Book',1,true))
print('Native queue cancellation: middle/current, 21 rows, callbacks, dependencies, completion race, lifecycle, invalid tail passed.')
-- The view keeps real action identities across refreshes, hide/show and player replacement.
local ui, refresh, playerCount = {}, nil, 1
local widget = {derive = derive}
function widget:new(x,y,w,h)
    return setmetatable({x=x,y=y,width=w,height=h,items={},selected=-1,scroll=0}, {__index=self})
end
function widget:initialise() if self.createChildren then self:createChildren() end end
function widget:instantiate() end
function widget:titleBarHeight() return 20 end
function widget:addChild(child) child.parent=self end
function widget:addToUIManager() ui[#ui+1]=self end
function widget:removeFromUIManager() self.removed=true end
function widget:setVisible(v) self.visible=v end
function widget:setEnable(v) self.enabled=v end
function widget:setTooltip(v) self.tooltip=v end
function widget:update() end
function widget:onResize() end
function widget:setWidth(v) self.width=v end
function widget:setHeight(v) self.height=v end
function widget:setY(v) self.y=v end
function widget:getYScroll() return self.scroll end
function widget:setYScroll(v) self.scroll=v end
function widget:clear() self.items={} end
function widget:addItem(text, item) self.items[#self.items+1]={item=item,index=#self.items+1,height=self.itemheight} end
ISCollapsableWindow = widget:derive('ISCollapsableWindow')
function ISCollapsableWindow:createChildren() self.closeButton=widget:new() end
ISScrollingListBox = widget:derive('ISScrollingListBox')
ISButton = widget:derive('ISButton')
UIFont = {Small=1}
getTextManager = function() return {getFontHeight=function() return 14 end} end
getNumActivePlayers = function() return playerCount end
getPlayerScreenLeft = function() return 0 end
getPlayerScreenTop = function() return 0 end
getPlayerScreenHeight = function() return 720 end
getPlayerScreenWidth = function() return 1280 end
Events.OnTickEvenPaused = {Add=function(fn) refresh=fn end}
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueuePanel.lua'))()
p = player(); a,b,c = book(p),book(p),book(p)
q = ISTimedActionQueue.add(a); ISTimedActionQueue.add(b); ISTimedActionQueue.add(c)
refresh(); local panel=ui[#ui]; panel:update()
assert(panel.visible and #panel.list.items==3 and not panel.closeButton.visible)
panel.list.selected=2; panel:update(); assert(panel.cancelButton.enabled)
panel.list.scroll=-30; panel:cancelSelected(); panel:update()
assert(#panel.list.items==2 and panel.list.items[2].item==c and panel.list.selected==-1)
assert(panel.list.scroll==-30 and not panel.cancelButton.enabled)
panel.list.selected=2; panel:update(); api.cancel(q,a) -- still not started, must refuse
assert(q.current==a and #q.queue==2)
enabled=false; refresh(); assert(not panel.visible and #panel.list.items==0, 'hidden view must release action snapshots')
enabled=true; refresh(); assert(panel.visible and ui[#ui]==panel)
p.dead=true; refresh(); assert(not panel.visible)
p=player(); ISTimedActionQueue.add(book(p)); refresh()
assert(panel.removed and ui[#ui]~=panel and ui[#ui].queue.character==p)
local replaced = ui[#ui]
ISTimedActionQueue:new(p); ISTimedActionQueue.add(book(p)); refresh()
assert(replaced.removed and ui[#ui].queue == ISTimedActionQueue.queues[p])
ui[#ui]:update(); ISTimedActionQueue.clear(p); refresh()
assert(not ui[#ui].visible and #ui[#ui].list.items == 0, 'completed/stopped queue must release rows')
playerCount=0; refresh(); assert(ui[#ui].removed)
print('Queue view: identity selection, removed-row safety, scroll, independent visibility and respawn passed.')
