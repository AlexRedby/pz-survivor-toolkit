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
local captured, options = nil, {}
local menu={addOption=function(_,label,target,callback)
    captured={label=label,target=target,callback=callback};options[#options+1]=captured
end}
Events.OnFillInventoryObjectContextMenu.fire(0,menu,{hammer,{items={hammer,hammer,nails}}})
local originalAdd=C.addItems
C.addItems=function(number,entries)assert(number==0 and #entries==2)end
captured.callback(captured.target);C.addItems=originalAdd
print("PASS wishlist inventory: mixed stacks, clipped rows, both CleanUI classes, toggle and deduplicated menu")

-- Single-type actions refer to the displayed list, not all highlighted/shared lists.
Events.OnFillInventoryObjectContextMenu.fire(0,menu,{{items={hammer,hammer}}})
assert(captured.label == 'UI_PZSW_AddWanted', 'other lists do not turn Add into Remove')
C.select(0,'bob')
captured.callback(captured.target)
local request = sent[#sent]
assert(request.action == 'addMany' and request.listId == 'alice' and #request.entries == 1)
local updated = snapshot(3,other,nil,request.requestId)
updated.lists[1].entries['Base.Hammer'] = {amount=2,done=true}
C.receive(0,updated);C.select(0,'alice')
Events.OnFillInventoryObjectContextMenu.fire(0,menu,{hammer})
assert(captured.label == 'UI_PZSW_RemoveWanted', 'completed entries can still be removed')
C.select(0,'bob');captured.callback(captured.target)
request = sent[#sent]
assert(request.action == 'remove' and request.listId == 'alice' and request.fullType == 'Base.Hammer' and not request.entries)
C.receive(0,snapshot(4,other,nil,request.requestId))
assert(C.getList(0,'bob').entries['Base.Hammer'], 'removing from one list keeps other lists intact')
Events.OnFillInventoryObjectContextMenu.fire(0,menu,{nails})
assert(captured.label == 'UI_PZSW_RemoveWanted')
C.receive(0,snapshot(4)) -- access to the displayed Bob list is revoked before clicking
local beforeRevoked = #sent
captured.callback(captured.target)
assert(#sent == beforeRevoked and C.state(0).error == 'forbidden' and not C.state(0).pending)
print('PASS wishlist inventory: Add/Remove includes done rows and preserves target list across switches/revocation')

-- A compatible variant removes one explicit request, even with overlapping groups and an exact wish.
getItemNameFromFullType=function(fullType)return fullType end
local tire=item('Base.ModernTire2')
local function grouped(primary)
    return {amount=1,done=true,vehicleTypes={primary,'Base.ModernTire2'},vehicleClass=2}
end
updated=snapshot(5,other)
updated.lists[1].entries={['Base.ModernTire2']={amount=3,done=false},
    ['vehicle:Base.OldTire2']=grouped('Base.OldTire2'),
    ['vehicle:Base.NormalTire2']=grouped('Base.NormalTire2'),
    ['vehicle:Base.OldTire1']={amount=1,done=false,vehicleTypes={'Base.OldTire1','Base.ModernTire1'},vehicleClass=1}}
C.receive(0,updated);C.select(0,'alice');options={}
Events.OnFillInventoryObjectContextMenu.fire(0,menu,{tire})
assert(#options==3 and options[1].label=='UI_PZSW_RemoveWanted')
assert(options[2].label=='UI_PZSW_RemoveVehicleWanted: Base.NormalTire2')
assert(options[3].label=='UI_PZSW_RemoveVehicleWanted: Base.OldTire2')
C.select(0,'bob');options[1].callback(0);request=sent[#sent]
assert(request.action=='remove' and request.listId=='alice' and request.fullType=='Base.ModernTire2',
    'each menu callback retains its own key, including the exact entry')
updated.requestId=request.requestId;updated.lists[1].revision=6
C.receive(0,updated)
options[3].callback(0);request=sent[#sent]
assert(request.action=='remove' and request.listId=='alice' and request.fullType=='vehicle:Base.OldTire2')
updated.requestId=request.requestId;updated.lists[1].revision=7
updated.lists[1].entries['vehicle:Base.OldTire2']=nil
C.receive(0,updated)
assert(C.getList(0,'alice').entries['Base.ModernTire2'] and C.getList(0,'alice').entries['vehicle:Base.NormalTire2']
    and C.getList(0,'alice').entries['vehicle:Base.OldTire1'], 'removing one group preserves all independent requests')
C.select(0,'alice');options={};Events.OnFillInventoryObjectContextMenu.fire(0,menu,{tire})
local removal=options[2]
C.receive(0,{lists={other}})
beforeRevoked=#sent;removal.callback(0)
assert(#sent==beforeRevoked and C.state(0).error=='forbidden', 'revoked group removal never edits a fallback list')
assert(#C.entryKeys(C.selected(0),'Base.ModernTire2')==0, 'highlighted or removed shared entries do not imply membership')
print('PASS wishlist grouped removal: variant membership, done, overlap, exact coexistence, classes and captured/revoked targets')
C.receive(0,snapshot(4,other))
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

local windowClasses = {}
ISCollapsableWindow = {derive = function(_, name)
    local class = {}; windowClasses[name] = class; return class
end, prerender = function() end}
UIFont = {Small = 1}
getTextManager = function() return {getFontHeight = function() return 14 end,
    MeasureStringX = function(_, _, value) return #value * 6 end} end
dofile(base .. "UI.lua")
local closed, unfocused, removed = 0, 0, 0
local window = {catalogWindow = {close = function() closed = closed + 1 end},
    shareWindow = {close = function() closed = closed + 1 end},
    selector = {hidePopup = function() closed = closed + 1 end},
    search = {unfocus = function() unfocused = unfocused + 1 end},
    quantity = {unfocus = function() unfocused = unfocused + 1 end},
    setVisible = function(_, visible) assert(not visible) end,
    removeFromUIManager = function() removed = removed + 1 end}
PZSurvivorWishlist.UI.close(window)
assert(closed == 3 and unfocused == 2 and removed == 1)
print("PASS wishlist windows: closing releases child dialogs, keyboard focus and UIManager references")

local Catalog = windowClasses.PZSWCatalog
local catalog = setmetatable({playerNum=0,listId='alice',width=600,query='',
    search={getInternalText=function()return '' end},
    list={selected=1,items={{item={fullType='Base.Hammer'}}}},
    quantity={value='2',getInternalText=function(self)return self.value end,
        setEditable=function(self,value)self.editable=value end},
    addButton={setTitle=function(self,value)self.title=value end,
        setEnable=function(self,value)self.enable=value end,getBottom=function()return 440 end},
    drawText=function()end}, {__index=Catalog})
C.receive(0,snapshot(4,other));C.select(0,'bob')
catalog:prerender()
assert(catalog.addButton.title == 'UI_PZSW_AddTo' and catalog.addButton.enable and catalog.quantity.editable)
catalog:add();request=sent[#sent]
assert(request.action == 'addMany' and request.listId == 'alice' and request.entries[1].amount == 2)
catalog:prerender();assert(not catalog.addButton.enable, 'wait for authoritative membership before another click')
local sentPending=#sent;catalog:add();assert(#sent==sentPending and #C.state(0).queue==0)
updated=snapshot(5,other,nil,request.requestId)
updated.lists[1].entries['Base.Hammer']={amount=2,done=true}
C.receive(0,updated)
catalog.quantity.value='invalid';catalog:prerender()
assert(catalog.addButton.title == 'UI_PZSW_RemoveFrom' and catalog.addButton.enable and not catalog.quantity.editable,
    'Remove ignores quantity and includes completed entries')
catalog:add();request=sent[#sent]
assert(request.action=='remove' and request.listId=='alice' and request.fullType=='Base.Hammer')
C.receive(0,snapshot(6,other,nil,request.requestId));catalog:prerender()
assert(catalog.addButton.title=='UI_PZSW_AddTo' and not catalog.addButton.enable and catalog.quantity.editable)
catalog.quantity.value='1';catalog:prerender();assert(catalog.addButton.enable)
catalog.list.selected=0;catalog:prerender();assert(not catalog.addButton.enable)
catalog.list.selected=1;catalog.listId='bob';catalog:prerender()
assert(catalog.addButton.title=='UI_PZSW_RemoveFrom')
C.receive(0,snapshot(6));catalog:prerender()
assert(not catalog.addButton.enable, 'revoked catalog cannot edit a fallback list')
beforeRevoked=#sent;catalog:add();assert(#sent==beforeRevoked)
catalog.listId='alice';catalog:prerender()
updated=snapshot(7)
updated.lists[1].entries['Base.Hammer']={amount=1,done=false}
C.receive(0,updated)
local beforeConcurrent=#sent
catalog:add();assert(#sent==beforeConcurrent, 'a displayed Add must not remove a concurrently added entry')
catalog:prerender();assert(catalog.addButton.title=='UI_PZSW_RemoveFrom')
C.receive(0,snapshot(8))
catalog:add();assert(#sent==beforeConcurrent, 'a displayed Remove must not re-add a concurrently removed entry')
catalog:prerender();assert(catalog.addButton.title=='UI_PZSW_AddTo')
catalog.list.items[1].item.fullType='Base.Nails'
catalog:add();assert(#sent==beforeConcurrent, 'changing the row before repaint cannot edit another item')
print('PASS wishlist catalog: authoritative Add/Remove refresh, amount handling, fixed target and revocation')
