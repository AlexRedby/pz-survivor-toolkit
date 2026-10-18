local base = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorWishlist/"
local function event()
    local callbacks = {}
    return { Add = function(fn) callbacks[#callbacks + 1] = fn end,
        fire = function(...) for _, fn in ipairs(callbacks) do fn(...) end end }
end
Events = { OnServerCommand = event(), OnTick = event(), OnGameStart = event(), OnMainMenuEnter = event(),
    OnFillInventoryObjectContextMenu = event() }
require = function() end
local now, sent = 0, {}
local notices = {}
getText = function(key) return key end
HaloTextHelper = {addText = function(_, message) notices[#notices + 1] = message end}
local player = { getUsername = function() return "alice" end }
getSpecificPlayer = function(n) if n == 0 then return player end end
getNumActivePlayers = function() return 1 end
getTimestampMs = function() return now end
isClient = function() return true end
sendClientCommand = function(who, module, command, args)
    assert(who == player and module == "PZSurvivorWishlist" and command == "request")
    sent[#sent + 1] = args
end
PZSurvivorWishlist = { Service = { username = function(p) return p:getUsername() end } }
dofile(base .. "Client.lua")
local C = PZSurvivorWishlist.Client
local function snapshot(revision, extra, error, requestId)
    local lists = { { id = "alice", owner = "alice", revision = revision, members = {}, entries = {} } }
    if extra then lists[#lists + 1] = extra end
    return { lists = lists, recipient = "alice", error = error, requestId = requestId }
end
C.receive(0, snapshot(0))
assert(C.selected(0).id == "alice")
C.addItem(0, "Base.Hammer", 2)
C.addItem(0, "Base.Nails", 4)
assert(#sent == 1 and sent[1].revision == 0 and #C.state(0).queue == 1)
C.receive(0, snapshot(1, nil, nil, sent[1].requestId))
assert(#sent == 2 and sent[2].revision == 1, "queued additions use confirmed revision")
C.receive(0, snapshot(2, nil, "stale_revision", sent[2].requestId))
assert(not C.state(0).pending and C.state(0).error == "stale_revision")
assert(notices[#notices] == "UI_PZSW_Error_stale_revision", "closed windows still report a rejected edit")
local other = { id = "bob", owner = "bob", revision = 4, members = { alice = true },
    entries = { ["Base.Hammer"] = { amount = 5, done = false }, ["Base.Nails"] = { amount = 9, done = true } } }
C.receive(0, snapshot(2, other))
assert(C.isWanted(0, "Base.Hammer") and not C.isWanted(0, "Base.Nails"))
C.select(0, "bob")
C.addItem(0, "Base.Hammer", 1)
C.addItem(0, "Base.Nails", 1)
local pendingId = C.state(0).pending.requestId
C.receive(0, snapshot(2, nil, "forbidden", pendingId))
assert(C.selected(0).id == "alice" and #C.state(0).queue == 0 and not C.isWanted(0, "Base.Hammer"))
local generation = C.state(0).generation
Events.OnServerCommand.fire("PZSurvivorWishlist", "snapshot", { recipient = "someone-else", lists = {} })
assert(C.state(0).generation == generation, "another local player snapshot cannot overwrite this cache")
C.addItem(0, "Base.Hammer", 1)
local beforeTimeout = #sent
now = 16000
Events.OnTick.fire()
assert(#sent == beforeTimeout + 1 and sent[#sent].action == "sync")
assert(C.state(0).error == "timeout" and not C.state(0).pending, "uncertain increments never retry")
print("PASS wishlist client: serialized revisions, revocation, recipient isolation and timeout")

local rowsEnabled = true
PZSurvivorWishlist.Settings = { rowsEnabled = function() return rowsEnabled end,
    color = function() return {r=0.25,g=0.85,b=0.75,a=1} end }
instanceof = function(item, name) return type(item) == "table" and item.class == name end
getText = function(key) return key end
local function item(fullType) return { class = "InventoryItem", getFullType = function() return fullType end } end
local calls = 0
local function native() calls = calls + 1; return "native" end
ISInventoryPane = { renderdetails = native }
CleanUI_Clean_ISInventoryPane = ISInventoryPane
CleanUI_Vanilla_ISInventoryPane = { renderdetails = native }
dofile(base .. "Inventory.lua")
local I = PZSurvivorWishlist.Inventory
C.receive(0, snapshot(2, other))
local hammer, nails = item("Base.Hammer"), item("Base.Nails")
local draw = {}
local pane = {player=0,items={ {items={hammer,hammer,nails}},nails,hammer },itemHgt=20,headerHgt=16,
    getYScroll=function()return -5 end,getHeight=function()return 90 end,getWidth=function()return 100 end,
    drawRect=function()end,drawRectBorder=function(_,x,y,w,h)draw[#draw+1]={y=y,h=h}end}
assert(#I.marks(pane) == 2)
I.install(); local wrapped = ISInventoryPane.renderdetails; I.install(); assert(wrapped == ISInventoryPane.renderdetails)
assert(ISInventoryPane.renderdetails(pane, false) == "native" and calls == 1 and #draw == 2)
assert(draw[1].y == 21 and draw[1].h == 15, "row overlay clipped below fixed header")
draw = {};CleanUI_Vanilla_ISInventoryPane.renderdetails(pane,false);assert(#draw == 2)
rowsEnabled = false;draw={};ISInventoryPane.renderdetails(pane,false);assert(#draw==0)
rowsEnabled = true;pane.dragging=true;pane.dragStarted=true;pane.selected={[3]=true};assert(#I.marks(pane)==1)
local captured
local menu={addOption=function(_,_,target,callback)captured={target=target,callback=callback}end}
Events.OnFillInventoryObjectContextMenu.fire(0,menu,{hammer,{items={hammer,hammer,nails}}})
local originalAdd=C.addItems
C.addItems=function(number,entries)assert(number==0 and #entries==2)end
captured.callback(captured.target);C.addItems=originalAdd
print("PASS wishlist inventory: mixed stacks, clipped rows, both CleanUI classes, toggle and deduplicated menu")

local bag = { class="InventoryContainer", getFullType=function()return "Base.Bag_Schoolbag" end }
local function container(items)
    return {getItems=function()return{size=function()return #items end,get=function(_,i)return items[i+1]end}end}
end
local bagInventory = container({hammer})
bag.getInventory=function()return bagInventory end
player.getInventory=function()return container({bag,nails})end
local carried=C.carried(0)
assert(carried['Base.Hammer']==1 and carried['Base.Nails']==1 and carried['Base.Bag_Schoolbag']==1)
print("PASS wishlist counts: only carried items and carried bags")

ISCollapsableWindow = {derive = function() return {} end}
UIFont = {Small = 1}
getTextManager = function() return {getFontHeight = function() return 14 end} end
dofile(base .. "UI.lua")
local closed, unfocused, removed = 0, 0, 0
local window = {catalogWindow = {close = function() closed = closed + 1 end},
    shareWindow = {close = function() closed = closed + 1 end},
    selector = {hidePopup = function() closed = closed + 1 end},
    search = {unfocus = function() unfocused = unfocused + 1 end},
    quantity = {unfocus = function() unfocused = unfocused + 1 end},
    username = {unfocus = function() unfocused = unfocused + 1 end},
    setVisible = function(_, visible) assert(not visible) end,
    removeFromUIManager = function() removed = removed + 1 end}
PZSurvivorWishlist.UI.close(window)
assert(closed == 3 and unfocused == 3 and removed == 1)
print("PASS wishlist windows: closing releases child dialogs, keyboard focus and UIManager references")
