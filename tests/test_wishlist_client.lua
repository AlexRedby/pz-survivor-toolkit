local base = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorWishlist/"
local function event()
    local callbacks = {}
    return { Add = function(fn) callbacks[#callbacks + 1] = fn end,
        fire = function(...) for _, fn in ipairs(callbacks) do fn(...) end end }
end
Events = { OnServerCommand = event(), OnTick = event(), OnGameStart = event(), OnMainMenuEnter = event(),
    OnFillInventoryObjectContextMenu = event() }
PZSurvivorToolkit = {}
require = function(name)
    if name == "PZSurvivorToolkit/UIStyle" or name == "PZSurvivorToolkit/InventoryClasses" then
        return dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/" .. name .. ".lua")
    end
end
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
assert(not C.hasWanted(0), "new client state has no wanted types")
C.receive(0, snapshot(0))
assert(not C.hasWanted(0), "empty authoritative snapshot has no wanted types")
assert(C.selected(0).id == "alice")
C.addItem(0, "Base.Hammer", 2)
assert(not C.hasWanted(0), "unacknowledged edits cannot enable discovery")
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
assert(C.hasWanted(0) and C.isWanted(0, "Base.Hammer") and not C.isWanted(0, "Base.Nails"))
C.select(0, "bob")
C.addItem(0, "Base.Hammer", 1)
C.addItem(0, "Base.Nails", 1)
local pendingId = C.state(0).pending.requestId
C.receive(0, snapshot(2, nil, "forbidden", pendingId))
assert(C.selected(0).id == "alice" and #C.state(0).queue == 0 and not C.isWanted(0, "Base.Hammer"))
assert(not C.hasWanted(0), "revoking the last shared goal clears membership")
local completed = snapshot(3)
completed.lists[1].entries["Base.Hammer"] = {done = true}
C.receive(0, completed)
assert(not C.hasWanted(0), "completed goals do not enable world discovery")
local variants = snapshot(4)
variants.lists[1].entries["vehicle:empty"] = {done = false, vehicleTypes = {}}
C.receive(0, variants)
assert(not C.hasWanted(0), "a goal without concrete types does not enable discovery")
variants.lists[1].entries["vehicle:empty"].vehicleTypes = {"Base.Tire1", "Base.Tire2"}
C.receive(0, variants)
assert(C.hasWanted(0) and C.isWanted(0, "Base.Tire2"), "concrete vehicle variants enable discovery")
Events.OnMainMenuEnter.fire()
assert(not C.hasWanted(0), "main menu clears wanted membership")
C.receive(0, variants)
Events.OnGameStart.fire()
assert(not C.hasWanted(0), "game start clears old-session wanted membership")
do
    local many = snapshot(5)
    local types = {}
    for index = 1, 400 do types[index] = "Mod.Part" .. index end
    local group = {done = false, vehicleTypes = types}
    many.lists[1].entries["vehicle:many"] = group
    local function repeatedReads(expected)
        local membership, originalPairs = C.state(0).wanted, pairs
        pairs = function(value)
            assert(value ~= membership, "hasWanted must not snapshot membership keys on each tick")
            return originalPairs(value)
        end
        for _ = 1, 1000 do assert(C.hasWanted(0) == expected) end
        pairs = originalPairs
    end
    C.receive(0, many)
    assert(C.isWanted(0, "Mod.Part400"), "large authoritative variant group was populated")
    repeatedReads(true)
    group.done = true
    C.receive(0, many)
    assert(not C.isWanted(0, "Mod.Part400"))
    repeatedReads(false)
end
C.receive(0, snapshot(2))
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
dofile(base .. "Inventory.lua")
local I = PZSurvivorWishlist.Inventory
C.receive(0, snapshot(2, other))
local hammer, nails = item("Base.Hammer"), item("Base.Nails")
local draw = {}
local pane = {player=0,items={ {items={hammer,hammer,nails}},nails,hammer },itemHgt=20,headerHgt=16,
    getYScroll=function()return -5 end,getHeight=function()return 90 end,getWidth=function()return 100 end,
    drawRect=function()end,drawRectBorder=function(_,x,y,w,h)draw[#draw+1]={y=y,h=h}end}
assert(#I.marks(pane) == 2)
I.draw(pane); assert(#draw == 2)
assert(draw[1].y == 21 and draw[1].h == 15, "row overlay clipped below fixed header")
rowsEnabled = false;draw={};I.draw(pane);assert(#draw==0)
rowsEnabled = true;pane.dragging=true;pane.dragStarted=true;pane.selected={[3]=true};assert(#I.marks(pane)==1)
local captured, options = nil, {}
local menu={addOption=function(_,label,target,callback)
    captured={label=label,target=target,callback=callback};options[#options+1]=captured
end}
Events.OnFillInventoryObjectContextMenu.fire(0,menu,{hammer,{items={hammer,hammer,nails}}})
local originalAdd=C.addItems
C.addItems=function(number,entries)assert(number==0 and #entries==2)end
captured.callback(captured.target);C.addItems=originalAdd
print("PASS wishlist inventory: mixed stacks, clipped rows, settings, drag exclusion and deduplicated menu")

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

do
    local entries={['Base.Part']={amount=1,done=true},
        ['vehicle:Base.Z']={vehicleTypes={'Base.Part','Base.Part','Base.Other'},done=true},
        ['vehicle:Base.A']={vehicleTypes={'Base.Part'},done=false}}
    local displayed={entries=entries}
    local index=C.entryIndex(displayed)
    local keys=C.entryKeys(displayed,'Base.Part',index)
    assert(#keys==3 and keys[1]=='Base.Part' and keys[2]=='vehicle:Base.A' and keys[3]=='vehicle:Base.Z',
        'batch entry index changed exact-first ordering, completed groups or duplicate variants')
    keys[1]='changed'
    assert(C.entryKeys(displayed,'Base.Part',index)[1]=='Base.Part','entry result mutated the prepared index')
    entries['Base.Part']=nil;entries['Base.Replacement']={amount=1,done=false}
    assert(#C.entryKeys(displayed,'Base.Part')==2 and #C.entryKeys(displayed,'Base.Replacement')==1,
        'standalone removal lookup reused an earlier snapshot')
    assert(#C.entryKeys(displayed,'Base.Missing',index)==0 and #C.entryKeys(nil,'Base.Part')==0)
end
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
    selector = {expanded=true, popup={}, hidePopup = function() closed = closed + 1 end},
    search = {unfocus = function() unfocused = unfocused + 1 end},
    quantity = {unfocus = function() unfocused = unfocused + 1 end},
    setVisible = function(_, visible) assert(not visible) end,
    removeFromUIManager = function() removed = removed + 1 end}
window.selector.popup.parentCombo = window.selector
PZSurvivorWishlist.UI.close(window)
assert(closed == 3 and unfocused == 2 and removed == 1)
assert(not window.selector.expanded)
print("PASS wishlist windows: closing releases child dialogs, keyboard focus and UIManager references")

do
    local Window = windowClasses.PZSWWindow
    local originalNext = next
    next=nil -- Kahlua does not expose Lua's global next.
    local originalText = getText
    getText=function(key,value)
        if key=='UI_PZSW_Carried' then return key .. ':' .. tostring(value) end
        return originalText(key,value)
    end
    local visits, listClears, selectorClears, bodyDraws = 0, 0, 0, 0
    local function countedContainer(items)
        return {getItems=function()return{size=function()return #items end,
            get=function(_,index)visits=visits+1;return items[index+1]end}end}
    end
    local contents = {}
    for index=1,4800 do contents[index]=nails end
    local carriedBag = {class='InventoryContainer',getFullType=function()return 'Base.Bag_Schoolbag'end,
        getInventory=function()return countedContainer(contents)end}
    player.getInventory=function()return countedContainer({carriedBag})end
    getScriptManager=function()return{getItem=function()return nil end}end
    local function control()
        return {setEnable=function(self,value)self.enable=value end,
            setTitle=function(self,value)self.title=value end}
    end
    local pane = {items={},selected=0,scroll=0,getYScroll=function(self)return self.scroll end,
        setYScroll=function(self,value)self.scroll=value end,
        clear=function(self)listClears=listClears+1;self.items={}end,
        addItem=function(self,name,row)self.items[#self.items+1]={text=name,item=row}end}
    local subject = setmetatable({playerNum=0,nextRefresh=0,width=600,height=470,footerY=400,
        selector={options={},selected=1,getBottom=function()return 40 end,
            clear=function(self)selectorClears=selectorClears+1;self.options={}end,
            addOptionWithData=function(self,label,id)self.options[#self.options+1]={text=label,data=id}end},
        list=pane,shareButton=control(),addButton=control(),amountButton=control(),
        doneButton=control(),removeButton=control(),
        drawText=function()bodyDraws=bodyDraws+1 end}, {__index=Window})
    C.receive(0,snapshot(20));C.select(0,'alice');now=20000
    subject:prerender()
    assert(visits==0, 'empty Wishlist must not traverse carried inventory')
    local initialLists,initialSelectors=listClears,selectorClears
    for _=1,60 do now=now+750;subject:prerender()end
    assert(visits==0 and listClears==initialLists and selectorClears==initialSelectors,
        'unchanged empty Wishlist must not count inventory or rebuild lists on its refresh timer')
    local populated=snapshot(21,other)
    populated.lists[1].entries['Base.Nails']={amount=2,done=false}
    C.receive(0,populated);subject:prerender()
    assert(visits==4801 and #pane.items==1 and pane.items[1].item.detail:find('UI_PZSW_Carried:4800',1,true),
        'adding the first goal refreshes immediately inside the old timer interval')
    pane.selected,pane.scroll=1,-37
    local initialVisits=visits
    local selectorCount=selectorClears
    for _=1,1000 do subject:prerender()end
    now=now+749;subject:prerender()
    assert(visits==initialVisits, 'visible populated Wishlist retains the 750ms count guard')
    contents[#contents+1]=nails
    now=now+1;subject:prerender()
    assert(visits==initialVisits+4802 and pane.selected==1 and pane.scroll==-37
        and pane.items[1].item.detail:find('UI_PZSW_Carried:4801',1,true),
        'due counts read current bag contents and retain selection and scroll')
    assert(selectorClears==selectorCount, 'count refreshes must not rebuild unchanged list selectors')
    C.select(0,'bob');subject:prerender()
    assert(#pane.items==2 and not subject.shareButton.enable and subject.addButton.enable,
        'switching the displayed list bypasses the count timer and updates ownership controls')
    initialVisits,initialLists,initialSelectors=visits,listClears,selectorClears
    subject.isCollapsed=true;bodyDraws=0
    for _=1,60 do now=now+750;subject:prerender()end
    C.receive(0,snapshot(22));subject:prerender()
    assert(visits==initialVisits and listClears==initialLists and selectorClears==initialSelectors and bodyDraws==0,
        'collapsed Wishlist defers counts, body rendering and structural refreshes, including revocation')
    subject.isCollapsed=false;subject:prerender()
    assert(#pane.items==0 and pane.selected==0 and subject.shareButton.enable and subject.addButton.enable
        and not subject.amountButton.enable and not subject.doneButton.enable and not subject.removeButton.enable,
        'first expanded frame immediately clears revoked rows and updates all controls')
    beforeRevoked=#sent;subject:done();subject:remove()
    assert(#sent==beforeRevoked, 'revoked rows cannot edit the fallback list after expansion')
    C.receive(0,{recipient='alice',lists={}});subject:prerender()
    assert(not subject.shareButton.enable and not subject.addButton.enable and #pane.items==0,
        'expanded no-access state disables list actions immediately')
    C.receive(0,populated);C.select(0,'alice');subject:prerender()
    -- Reopening before the next timer deadline must still read current counts.
    subject.setVisible=function(self,value)self.visible=value end
    subject.removeFromUIManager=function()end
    subject.addToUIManager=function()end
    subject.bringToTop=function()end
    PZSurvivorWishlist.UI.windows[0]=subject
    subject:close();contents[#contents+1]=hammer;initialVisits=visits
    PZSurvivorWishlist.UI.open(0);subject:prerender()
    assert(visits==initialVisits+4803, 'reopening a populated Wishlist refreshes counts immediately')
    PZSurvivorWishlist.UI.windows[0]=nil

    local dialog
    ISTextBox={new=function(_,x,y,width,height,prompt,amount,target,callback)
        dialog={entry={getInternalText=function()return '7'end,focus=function()end},
            initial=amount,target=target,callback=callback,initialise=function()end,
            setOnlyNumbers=function()end,setValidateFunction=function()end,addToUIManager=function()end}
        return dialog
    end}
    local function actionSnapshot(requestId)
        local result=snapshot(30,{id='bob',owner='bob',revision=30,members={alice=true},
            entries={['Base.Hammer']={amount=5,done=false},['Base.Nails']={amount=9,done=true}}},nil,requestId)
        result.lists[1].entries['Base.Nails']={amount=1,done=false}
        return result
    end
    local function displayShared()
        C.receive(0,actionSnapshot());C.select(0,'bob');subject:prerender();pane.selected=2
        assert(pane.items[2].item.fullType=='Base.Nails')
    end
    displayShared();C.select(0,'alice');subject:done();request=sent[#sent]
    assert(request.action=='done' and request.listId=='bob' and request.fullType=='Base.Nails' and not request.done,
        'Done before repaint targets the displayed shared row, not the newly selected personal list')
    C.receive(0,actionSnapshot(request.requestId));subject:remove();request=sent[#sent]
    assert(request.action=='remove' and request.listId=='bob' and request.fullType=='Base.Nails',
        'Remove before repaint preserves the displayed list identity')
    local changedAmount=actionSnapshot(request.requestId)
    changedAmount.lists[2].entries['Base.Nails'].amount=12
    C.receive(0,changedAmount);subject:amount()
    assert(dialog.initial=='12', 'amount dialog uses the current entry in the displayed list')
    pane.selected=1
    dialog.callback(dialog.target,{internal='OK',parent=dialog});request=sent[#sent]
    assert(request.action=='set' and request.listId=='bob' and request.fullType=='Base.Nails' and request.amount==7,
        'amount dialog retains its captured displayed list and row across selection changes')
    C.receive(0,actionSnapshot(request.requestId));displayShared();subject:amount()
    local capturedDialog=dialog
    local revoked=actionSnapshot();revoked.lists[2]=nil
    C.receive(0,revoked);subject.isCollapsed=true;beforeRevoked=#sent;dialog=nil
    subject:done();subject:remove();subject:amount()
    capturedDialog.callback(capturedDialog.target,{internal='OK',parent=capturedDialog})
    assert(#sent==beforeRevoked and not dialog,
        'revocation before repaint blocks hidden Done/Remove/Amount and an already open amount dialog')
    subject.isCollapsed=false;displayShared();subject:amount();capturedDialog=dialog
    local removed=actionSnapshot();removed.lists[2].entries['Base.Nails']=nil
    C.receive(0,removed);beforeRevoked=#sent;dialog=nil
    subject:done();subject:remove();subject:amount()
    capturedDialog.callback(capturedDialog.target,{internal='OK',parent=capturedDialog})
    assert(#sent==beforeRevoked and not dialog, 'removed entries cannot be edited or recreated through stale row controls')
    displayShared();local changedDone=actionSnapshot();changedDone.lists[2].entries['Base.Nails'].done=false
    C.receive(0,changedDone);beforeRevoked=#sent;subject:done()
    assert(#sent==beforeRevoked, 'stale Reopen cannot complete a concurrently reopened row')
    C.receive(0,populated);C.select(0,'alice');subject:prerender()
    print('PASS wishlist row actions: displayed target, current entry, pending dialog, removal and revocation')

    if NativeWishlistGameRoot then
        local savedPanel = ISPanel
        local savedWindow = ISCollapsableWindow
        ISPanel={derive=function()return{}end}
        dofile(NativeWishlistGameRoot .. '/media/lua/client/ISUI/ISCollapsableWindow.lua')
        ISPanel=savedPanel
        subject.collapse=ISCollapsableWindow.collapse
        subject.onMouseMoveOutside=ISCollapsableWindow.onMouseMoveOutside
        subject.onMouseMove=ISCollapsableWindow.onMouseMove
        subject.collapseButton={setVisible=function()end,bringToTop=function()end}
        subject.pinButton={setVisible=function()end,bringToTop=function()end}
        subject.titleBarHeight=function()return 16 end
        subject.getMouseX=function()return -1 end
        local mouseY=-1
        subject.getMouseY=function()return mouseY end
        subject.getWidth=function()return subject.width end
        subject.getHeight=function()return subject.height end
        subject.setMaxDrawHeight=function(self,value)self.maxDrawHeight=value end
        subject.clearMaxDrawHeight=function(self)self.maxDrawHeight=nil end
        getGameTime=function()return{getMultiplier=function()return 1 end,getTrueMultiplier=function()return 1 end}end
        isMouseButtonDown=function()return false end
        subject.collapseCounter=0;subject:collapse()
        for _=1,17 do subject:onMouseMoveOutside(0,0)end
        assert(subject.isCollapsed and subject.maxDrawHeight==16, 'native pointer exit collapses the window')
        initialVisits=visits;contents[#contents+1]=hammer
        -- No collapsed prerender occurs between native collapse and expansion.
        mouseY=5;subject:onMouseMove(0,0);subject:prerender()
        assert(not subject.isCollapsed and not subject.maxDrawHeight and visits==initialVisits+4804,
            'native title-bar hover refreshes immediately even if no collapsed frame was drawn')
        subject:collapse();mouseY=-1
        for _=1,17 do subject:onMouseMoveOutside(0,0)end
        bodyDraws=0;initialVisits=visits;subject:prerender()
        assert(visits==initialVisits and bodyDraws==0, 'native collapsed prerender never draws the body')
        C.receive(0,{recipient='alice',lists={}})
        mouseY=5;subject:onMouseMove(0,0);subject:prerender()
        assert(#pane.items==0 and not subject.shareButton.enable and not subject.addButton.enable,
            'native expansion applies access revocation before exposing controls')
        ISCollapsableWindow=savedWindow
        print('PASS wishlist native window: collapse/unpin, pointer exit and title-bar expansion')
    else
        print('SKIP wishlist native collapse lifecycle: supply --game')
    end
    getText=originalText
    next=originalNext
    print('PASS wishlist refresh: empty/collapsed idle, populated freshness, selection, access and reopen')
end

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
