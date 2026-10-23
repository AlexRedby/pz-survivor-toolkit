-- Own selection/dialog state, with actual native transfer callbacks when supplied.
local Membership = dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/InventoryMembership.lua')
require = function(name)
    if name == 'PZSurvivorToolkit/InventoryMembership' then return Membership end
end
local enabled, fill, active, player = true, nil, {}, nil
PZSurvivorToolkit = {Settings = {quantityTransfers = function() return enabled end}}
getActivatedMods = function() return {contains = function(_, id) return active[id] end} end
Events = {OnFillInventoryObjectContextMenu = {Add = function(fn) fill = fn end}}
instanceof = function(item, class) return class == 'InventoryItem' and item.id ~= nil end
getText = function(key, ...) return key .. ':' .. table.concat({...}, ':') end
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end,
        contains = function(_, x) for _, v in ipairs(values) do if x == v then return true end end; return false end}
end
local function container(owned, kind)
    local c = {values = {}, owned = owned, kind = kind or 'crate'}
    function c:isInCharacterInventory(p) return self.owned and p == player end
    function c:isItemAllowed(item)
        if self.onAccept then self.onAccept(item) end
        return not item.forbidden
    end
    function c:getAcceptItemFunction() return self.acceptFunction end
    function c:getItems()
        if self.rawValues ~= self.values then
            self.rawValues, self.rawItems = self.values, list(self.values)
        end
        return self.rawItems
    end
    function c:getType() return self.kind end
    return c
end
local inv, bag, crate, second, virtual = container(true), container(true), container(false), container(false), container(false)
local function item(id, source)
    local x = {id = id, source = source}
    function x:getID() return self.id end
    function x:getContainer() return self.source end
    function x:getName() return self.name or tostring(self.id) end
    function x:isFavorite() return self.favorite end
    function x:isHumanCorpse() return false end
    return x
end
local a, b, c, d = item(1, crate), item(2, crate), item(3, second), item(4, second)
crate.values, second.values, virtual.values = {a,b}, {c,d}, {a,b,c,d}
player = {isDead = function(self) return self.dead end, isEquipped = function(_, x) return x.equipped end}
getSpecificPlayer = function(num) assert(num == 0); return player end
local inventoryTab = inv
getPlayerInventory = function() return {inventory = inventoryTab, title = 'Inventory'} end
local destination = crate
getPlayerLoot = function() return {inventory = destination, title = 'Crate'} end
isForceDropHeavyItem = function(x) return x.heavy end
local reachable, queued, walked, walkOK = {inv,bag,crate,second}, {}, {}, true
local function enqueue(items, dest)
    for _, x in ipairs(items) do queued[#queued+1] = ISInventoryTransferUtil.newInventoryTransferAction(player,x,x.source,dest) end
end
ISInventoryPaneContextMenu = {
    getContainers = function() return list(reachable) end,
    doGrabMenu = function(context) context:addOption('Native grab'); return 17 end,
    onGrabItems = function(items) enqueue(items, inv) end,
    onMoveItemsTo = function(items, dest) enqueue(items, dest) end,
    onDropItems = function(items) enqueue(items, 'floor') end,
}
ISInventoryPane = {getActualItems = function(items) return items end}
luautils = {walkToContainer = function(dest) walked[#walked+1]=dest; return walkOK end}
ISTimedActionQueue = {add = function(action) queued[#queued+1]=action end}
ISInventoryTransferUtil = {newInventoryTransferAction = function(p,x,source,dest)
    assert(p==player); return {item=x, source=source, destination=dest, transactionId=0,
        setOnComplete=function(self,fn) self.onCompleteFunc=fn end, stop=function() end}
end}
if NativeInventoryContextMenuSource then
    local source = NativeInventoryContextMenuSource:gsub('\r','')
    for _, pair in ipairs({{'onGrabItems','onGrabOneItems'},{'onMoveItemsTo','canAddManyItems'}}) do
        local first = assert(source:find('ISInventoryPaneContextMenu.'..pair[1]..' = function',1,true))
        local last = assert(source:find('ISInventoryPaneContextMenu.'..pair[2]..' = function',first+1,true))
        assert(loadstring(source:sub(first,last-1)))()
    end
end
JoypadState = {players = {}}
local focus
setJoypadFocus = function(_, modal) focus=modal end
ISTextBox = {new = function(_, x,y,w,h,text,default,target,callback,playerNum,selection)
    assert(playerNum==0 and type(selection)=="table", "native ISTextBox player argument precedes callback params")
    local modal={text=text, callback=callback, selection=selection, entry={text=default}, target=target}
    function modal.entry:getText() return self.text end
    function modal.entry:focus() self.focused=true end
    function modal:initialise() self.yes={internal='OK',parent=self}; self.no={internal='CANCEL',parent=self} end
    function modal:setValidateFunction(target, fn) self.validator=fn end
    function modal:setValidateTooltipText(text) self.tooltip=text end
    function modal:addToUIManager() self.open=true end
    function modal:showErrorMessage(visible, text) self.error=visible; self.showError=visible; self.errorText=text end
    function modal:onClick(button) self.callback(self.target,button,self.selection); if not self.error then self.open=false end end
    return modal
end}
if NativeTextBoxSource then
    local source = NativeTextBoxSource:gsub('\r', '')
    local function method(first, following)
        local a = assert(source:find('function ISTextBox:' .. first, 1, true))
        local b = assert(source:find('function ISTextBox:' .. following, a + 1, true))
        assert(loadstring(source:sub(a,b-1)))()
    end
    local stubNew = ISTextBox.new
    ISPanelJoypad = {new = function(_,x,y,w,h)
        return {getMouseX=function() return 400 end, getMouseY=function() return 300 end,
            setX=function(self,v) self.x=v end, setY=function(self,v) self.y=v end}
    end}
    player.getJoypadBind = function() return -1 end
    UIFont = {Small=1}
    getTextManager = function() return {MeasureStringX=function() return 100 end} end
    getTexture = function(name) return name end
    getJoypadData = function() return nil end
    method('new(', 'close(')
    method('onClick(', 'titleBarHeight(')
    local nativeNew, nativeClick = ISTextBox.new, ISTextBox.onClick
    ISTextBox.new = function(self,...)
        local view, widget = stubNew(self,...), nativeNew(self,...)
        for key,value in pairs(view) do widget[key]=value end
        widget.onClick = nativeClick
        widget.destroy = function(self) self.open=false end
        return widget
    end
end
local function menu()
    return {options={}, addOption=function(self,name,target,onSelect,param)
        local option={name=name,target=target,onSelect=onSelect,param1=param}
        self.options[#self.options+1]=option; return option
    end}
end
local root=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'
dofile(root..'PZSurvivorToolkit/BulkActions.lua')
PZSurvivorToolkit.ItemRetention={isRetained=function(x) return x.stuck end}
dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/InventoryTransferProtection.lua')
active.TakeAnyAmount=true
dofile(root..'PZSurvivorToolkit/QuantityTransfers.lua')
assert(PZSurvivorToolkit.QuantityTransfers==nil and fill==nil,'legacy quantity mod must prevent duplicate feature')
active.TakeAnyAmount=nil
dofile(root..'PZSurvivorToolkit/QuantityTransfers.lua')
local Q=PZSurvivorToolkit.QuantityTransfers
local Protection=PZSurvivorToolkit.InventoryTransferProtection
assert(Protection.allowsAutomatic(a), 'unretained items must allow automatic transfers')
assert(Protection.selectionAllowsStuck({{items={a,a,b}},a,b}), 'one row plus its own children is deliberate')
assert(Protection.selectionAllowsStuck({{items={a,b},cleanUILargeStackOptimized=true},a,b}),
    'CleanUI optimized rows include the actual first item')
assert(not Protection.selectionAllowsStuck({{items={a,a,b}},c}), 'a foreign child makes the selection a batch')
assert(not Protection.selectionAllowsStuck({{items={a,a,b}},{items={a,a,b}}}), 'two distinct rows are a batch')
a.name, b.name = 'stack', 'stack'
assert(Protection.selectionAllowsStuck({a,b}), 'loose items from one source and name are deliberate')
b.source=second
assert(not Protection.selectionAllowsStuck({a,b}), 'same names from different sources remain a batch')
b.source=crate; a.name,b.name=nil,nil
assert(not Protection.selectionAllowsStuck({a,b}) and not Protection.selectionAllowsStuck({}),
    'different names and empty selections are not one deliberate pick')
for _, value in ipairs({'', '0','-1','2.5','nan','inf','1e309','4',false,0/0,math.huge}) do
    assert(Q.parse(value,3)==nil,'invalid amount must be rejected: '..tostring(value))
end
assert(Q.parse(' 2 ',3)==2 and Q.parse('3',3)==3)
local selection=Q.snapshot(0,{{items={a,a,b}},{items={c,d}},a},inv,true)
assert(#selection.items==4,'mixed groups/header duplicates must yield exact unique instances')
assert(Q.transfer(selection,'3')==3 and #queued==3 and queued[1].item==a and queued[3].item==c,
    'one common budget across both stacks, using native callbacks')
local allocator=ISInventoryTransferUtil.newInventoryTransferAction
local originalStop = queued[1].toolkitTransferGuard.original
local guardedStop, completion = queued[1].stop, queued[1].onCompleteFunc
PZSurvivorToolkit.BulkActions.guardTransfer(queued[1])
assert(queued[1].stop == guardedStop and queued[1].onCompleteFunc == completion
    and PZSurvivorToolkit.BulkActions.isGuardedTransfer(queued[1], originalStop),
    'repeated guards must preserve native stop provenance and their anti-merge callback')
queued[1].onCompleteFunc = nil
PZSurvivorToolkit.BulkActions.guardTransfer(queued[1])
assert(queued[1].onCompleteFunc and queued[1].stop == guardedStop
    and PZSurvivorToolkit.BulkActions.isGuardedTransfer(queued[1], originalStop),
    'restoring a missing anti-merge callback must not add another stop wrapper')
local foreignComplete, foreignArgs = function() return 'foreign complete' end, {'foreign argument'}
ISInventoryTransferUtil.newInventoryTransferAction = function(...)
    local transfer = allocator(...)
    transfer.onCompleteFunc, transfer.onCompleteArgs = foreignComplete, foreignArgs
    return transfer
end
queued = {}
assert(Q.transfer(selection,'1') == 1)
assert(queued[1].onCompleteFunc == foreignComplete and queued[1].onCompleteArgs == foreignArgs,
    'quantity transfers must retain a preexisting completion callback and its arguments')
assert(queued[1].toolkitQueueSafeOnComplete == nil,
    'a foreign callback must not gain Toolkit completion permissions')
ISInventoryTransferUtil.newInventoryTransferAction = allocator
queued = {}; Q.transfer(selection,'3')
assert(queued[1].onCompleteFunc and queued[2].onCompleteFunc, 'own transfers need the existing rejection guard')
local plain=allocator(player,a,a.source,inv)
assert(not plain.onCompleteFunc, 'ordinary allocator calls must remain unchanged')
local nativeMove=ISInventoryPaneContextMenu.onMoveItemsTo
ISInventoryPaneContextMenu.onMoveItemsTo=function() error('fixture native transfer error') end
assert(not pcall(Q.transfer,selection,'2'))
assert(ISInventoryTransferUtil.newInventoryTransferAction==allocator, 'allocator must restore after a native callback error')
ISInventoryPaneContextMenu.onMoveItemsTo=nativeMove
-- Preserve original selection scope before the common quantity budget narrows it.
queued={}
local sticking=true
PZSurvivorToolkit.ItemRetention={isEnabled=function() return sticking end,
    isRetained=function(x) return x.stuck end}
a.stuck=true
local batch=Q.snapshot(0,{{items={a,a,b}},{items={c,c,d}}},inv,true)
assert(not batch.allowsStuck and #batch.items==3 and batch.items[1]==b)
assert(Q.transfer(batch,'1')==1 and #queued==1 and queued[1].item==b,
    'a mixed selection must not become deliberate when budget one leaves only its stuck first item')
queued={}; a.stuck=nil
local late=Q.snapshot(0,{a,b,c,d},inv,true)
a.stuck=true
assert(Q.transfer(late,'1')==1 and #queued==1 and queued[1].item==b,
    'new protection after opening the dialog must be checked before consuming its budget')
queued={}
local deliberate=Q.snapshot(0,{{items={a,a,b}},a,b},inv,true)
assert(deliberate.allowsStuck and #deliberate.items==2 and Q.transfer(deliberate,'1')==1
    and queued[1].item==a, 'an original single row with its children keeps the deliberate exception')
queued={}; a.name,b.name='stack','stack'
local flat=Q.snapshot(0,{a,b},inv,true)
assert(flat.allowsStuck and Q.transfer(flat,'1')==1 and queued[1].item==a,
    'an original flat same-source stack remains deliberate')
a.name,b.name=nil,nil
local spanning=Q.snapshot(0,{{items={a,a,c}}},inv,true)
local liveWalk, liveMove=luautils.walkToContainer,ISInventoryPaneContextMenu.onMoveItemsTo
local liveAllocator, walkCalls=ISInventoryTransferUtil.newInventoryTransferAction,{}
luautils.walkToContainer=function(target,number)
    walkCalls[#walkCalls+1]={target,number}
    return liveWalk(target,number)
end
local observedWalk=luautils.walkToContainer
ISInventoryPaneContextMenu.onMoveItemsTo=function()
    luautils.walkToContainer(second,0)
    luautils.walkToContainer(inv,1)
    luautils.walkToContainer(inv,0)
    luautils.walkToContainer(inv,0)
    error('fixture individual native callback error')
end
assert(not pcall(Q.transfer,spanning,'2'))
assert(#walkCalls==4 and walkCalls[1][1]==crate and walkCalls[2][1]==second
    and walkCalls[3][1]==inv and walkCalls[3][2]==1 and walkCalls[4][2]==0,
    'share only the exact destination/player walk; forward source walks and unrelated native requests')
assert(luautils.walkToContainer==observedWalk and ISInventoryTransferUtil.newInventoryTransferAction==liveAllocator,
    'individual callback failures must restore both transient helpers')
luautils.walkToContainer,ISInventoryPaneContextMenu.onMoveItemsTo=liveWalk,liveMove
PZSurvivorToolkit.ItemRetention={isRetained=function(x) return x.stuck end}
a.stuck=nil
queued={}; inventoryTab=bag
assert(Q.transfer(selection,'2')==2 and queued[1].destination==inv and queued[2].destination==inv,
    'switching player inventory tab cannot retarget a captured grab dialog')
inventoryTab=inv; queued={}; walkOK=false
assert(Q.transfer(selection,'2')==0 and #queued==0, 'failed native source walk must not queue')
walkOK=true
assert(Q.transfer(selection,'2.5')==nil and #queued==0)
-- Revalidate snapshot: changed source, favorites, equipment, permissions and reachability.
a.source=bag; b.favorite=true; c.equipped=true; d.forbidden=true
assert(Q.transfer(selection,'4')==0 and #queued==0)
a.source=crate; b.favorite=nil; c.equipped=nil; d.forbidden=nil
reachable={inv,bag}; assert(Q.transfer(selection,'4')==0)
reachable={inv,bag,virtual}; assert(Q.transfer(selection,'4')==4 and #queued==4,'proximity view preserves actual item containers')
queued={}; reachable={inv,bag,crate,second}
enabled=false; assert(Q.transfer(selection,'2')==nil and #queued==0)
local disabledMenu=menu(); assert(ISInventoryPaneContextMenu.doGrabMenu(disabledMenu,{a,b},0)==17 and #disabledMenu.options==1)
enabled=true
local oldPlayer=player; player={isDead=function() return false end}
assert(Q.transfer(selection,'2')==nil and #queued==0,'respawn must invalidate old dialog')
player=oldPlayer; player.dead=true; assert(Q.transfer(selection,'2')==nil); player.dead=nil
-- Deposit captures the target, so switching loot tabs cannot retarget a dialog.
a.source=inv; b.source=bag; c.source=inv; d.source=inv
local putMenu=menu(); fill(0,putMenu,{{items={a,a,b}},c,d})
assert(#putMenu.options==1)
local option=putMenu.options[1]; local modal=option.onSelect(option.target,option.param1)
assert(modal.open and modal.entry.focused and modal.validator(nil,'2') and not modal.validator(nil,'2.5'))
destination=second; modal.entry.text='2.5'; modal:onClick(modal.yes)
assert(modal.open and modal.error and #queued==0,'invalid Enter must keep dialog open and queue nothing')
modal.entry.text='2'; modal.entry.onCommandEntered()
assert(not modal.open and #queued==2 and queued[1].destination==crate and queued[2].destination==crate)
queued={}; local stale=option.onSelect(option.target,option.param1); enabled=false; stale.entry.text='2'; stale:onClick(stale.yes)
assert(#queued==0,'feature disabled after opening must prevent enqueue')
enabled=true; reachable={inv,bag,second}; assert(Q.transfer(option.target,'2')==nil,'removed destination must be rejected')
reachable={inv,bag,crate,second}
local cancelled=option.onSelect(option.target,option.param1); cancelled:onClick(cancelled.no); assert(#queued==0)
JoypadState.players[1]={focus='old'}
local joy=option.onSelect(option.target,option.param1); assert(focus==joy and joy.prevFocus=='old')
b.favorite=true; c.equipped=true; d.heavy=true
assert(#Q.snapshot(0,{a,b,c,d},crate,false).items==1,'protect favorite/equipped/heavy items')
-- Optional source conformance check: execute the installed owner's actual wrapper,
-- without copying its private selection policy into the test.
-- A proximity pane exposes real source items through one raw aggregate list.
-- Its membership is indexed only for the current synchronous enumeration.
do
    local previousReachable, previousQueued, previousProvider, previousMove =
        reachable, queued, PZSurvivorToolkit.ItemRetention, ISInventoryPaneContextMenu.onMoveItemsTo
    PZSurvivorToolkit.ItemRetention = {isEnabled=function() return true end,
        isRetained=function(value) return value.stuck end}
    ISInventoryPaneContextMenu.onMoveItemsTo = function(items, dest) enqueue(items, dest) end
    local function aggregateBatch(count)
        local actual, aggregate, rows = container(false), container(false), {}
        for index=1,count do rows[index]=item(20000+index,actual) end
        aggregate.values=rows
        local raw, reads, scans = list(rows), 0, 0
        local get = raw.get
        raw.get = function(self, index) reads=reads+1; return get(self,index) end
        raw.contains = function() scans=scans+1; error('aggregate membership must be indexed') end
        aggregate.getItems = function() return raw end
        -- A filtered view cannot define raw membership for a selected real item.
        aggregate.visibleItems = {[rows[1]]=true}
        rows[2].stuck, rows[3].favorite, rows[4].equipped, rows[5].forbidden, rows[6].heavy = true,true,true,true,true
        reachable={inv,aggregate}
        local selection=Q.snapshot(0,rows,inv,true)
        assert(#selection.items==count-5 and selection.items[#selection.items]==rows[count],
            'raw aggregate membership must preserve exact selection and all live protections')
        assert(reads==count and scans==0,
            'one snapshot must read aggregate members once rather than scan per selected item')
        reads,queued=0,{}
        assert(Q.transfer(selection,tostring(#selection.items))==count-5 and #queued==count-5)
        assert(reads==count and scans==0, 'confirmation must build its own single membership index')
        -- Change raw contents without changing list identity or count after the dialog opened.
        local removed=rows[count]
        rows[count]=item(40000+count,actual)
        selection.items[1].stuck=true
        reads,queued=0,{}
        assert(Q.transfer(selection,tostring(#selection.items))==count-7 and #queued==count-7,
            'confirmation must see same-count raw replacements and newly stuck items')
        for _, action in ipairs(queued) do assert(action.item~=removed and action.item~=selection.items[1]) end
        assert(reads==count and scans==0, 'a later confirmation cannot retain the earlier raw index')
    end
    aggregateBatch(256)
    aggregateBatch(512)
    reachable,queued,PZSurvivorToolkit.ItemRetention,ISInventoryPaneContextMenu.onMoveItemsTo =
        previousReachable,previousQueued,previousProvider,previousMove
end
-- A large direct source need not linearly search every reachable container per item.
do
    local previousReachable, previousQueued, previousContainers, previousMove =
        reachable, queued, ISInventoryPaneContextMenu.getContainers, ISInventoryPaneContextMenu.onMoveItemsTo
    local reads, searches=0,0
    ISInventoryPaneContextMenu.getContainers=function()
        local result=list(reachable)
        local get,contains=result.get,result.contains
        result.get=function(self,index) reads=reads+1; return get(self,index) end
        result.contains=function(self,value) searches=searches+1; return contains(self,value) end
        return result
    end
    ISInventoryPaneContextMenu.onMoveItemsTo=function(items,dest) enqueue(items,dest) end
    for _,count in ipairs({100,400,1000}) do
        reachable={}
        for i=1,count do reachable[i]=container(false) end
        local source,rows=reachable[count],{}
        for i=1,count do rows[i]=item(60000+i,source) end
        reads,searches=0,0
        local selection=Q.snapshot(0,rows,inv,true)
        assert(#selection.items==count and reads==count and searches==0,
            'quantity snapshot searched the reachable list once per selected item')
        reads,searches,queued=0,0,{}
        assert(Q.transfer(selection,tostring(count))==count and #queued==count and reads==count and searches==0,
            'confirmation did not share one fresh reachable-list prefix')
        -- Same list length after the dialog, but the old world source is gone.
        reachable[count]=container(false)
        reads,searches,queued=0,0,{}
        assert(Q.transfer(selection,tostring(count))==0 and #queued==0 and searches==0,
            'confirmation retained old source reachability')
    end
    local source, replacement=container(false),container(false)
    local first,second,third=item(81001,source),item(81002,source),item(81003,source)
    reachable={source}
    inv.acceptFunction='FixtureAccept'
    inv.onAccept=function(value) if value==second then reachable[1]=replacement end end
    local selection=Q.snapshot(0,{first,second,third},inv,true)
    assert(#selection.items==1 and selection.items[1]==first,
        'a reentrant native accept callback reused stale same-count source reachability')
    -- Confirmation indexes its world destination before native admission. Its
    -- callback can clear itself or reject a row while rewriting the same list.
    for _,reject in ipairs({false,true}) do
        reachable={source,replacement}
        local selection=Q.snapshot(0,{first,second,third},replacement,true)
        assert(#selection.items==3)
        replacement.acceptFunction='FixtureAccept'
        replacement.onAccept=function(value)
            if value==second then
                reachable[1]=container(false)
                replacement.acceptFunction,replacement.onAccept=nil,nil
                value.forbidden=reject
            end
        end
        queued={}
        assert(Q.transfer(selection,'3')==1 and #queued==1 and queued[1].item==first,
            'a self-clearing/rejecting accept callback retained a prefix for itself or a later item')
        second.forbidden=nil
    end
    inv.acceptFunction,inv.onAccept=nil,nil
    reachable,queued,ISInventoryPaneContextMenu.getContainers,ISInventoryPaneContextMenu.onMoveItemsTo=
        previousReachable,previousQueued,previousContainers,previousMove
end
print('Quantity selection, common budget, native transfers, stale/respawn/reachability and dialogs passed' .. (NativeInventoryContextMenuSource and ' with actual native callbacks.' or '.'))
