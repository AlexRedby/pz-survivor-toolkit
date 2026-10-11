-- Own selection/dialog state, with actual native transfer callbacks when supplied.
require = function() end
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
    function c:isItemAllowed(item) return not item.forbidden end
    function c:getItems() return list(self.values) end
    function c:getType() return self.kind end
    return c
end
local inv, bag, crate, second, virtual = container(true), container(true), container(false), container(false), container(false)
local function item(id, source)
    local x = {id = id, source = source}
    function x:getID() return self.id end
    function x:getContainer() return self.source end
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
active.TakeAnyAmount=true
dofile(root..'PZSurvivorToolkit/QuantityTransfers.lua')
assert(PZSurvivorToolkit.QuantityTransfers==nil and fill==nil,'legacy quantity mod must prevent duplicate feature')
active.TakeAnyAmount=nil
dofile(root..'PZSurvivorToolkit/QuantityTransfers.lua')
local Q=PZSurvivorToolkit.QuantityTransfers
for _, value in ipairs({'', '0','-1','2.5','nan','inf','1e309','4',false,0/0,math.huge}) do
    assert(Q.parse(value,3)==nil,'invalid amount must be rejected: '..tostring(value))
end
assert(Q.parse(' 2 ',3)==2 and Q.parse('3',3)==3)
local selection=Q.snapshot(0,{{items={a,a,b}},{items={c,d}},a},inv,true)
assert(#selection.items==4,'mixed groups/header duplicates must yield exact unique instances')
assert(Q.transfer(selection,'3')==3 and #queued==3 and queued[1].item==a and queued[3].item==c,
    'one common budget across both stacks, using native callbacks')
local allocator=ISInventoryTransferUtil.newInventoryTransferAction
assert(queued[1].onCompleteFunc and queued[2].onCompleteFunc, 'own transfers need the existing rejection guard')
local plain=allocator(player,a,a.source,inv)
assert(not plain.onCompleteFunc, 'ordinary allocator calls must remain unchanged')
local nativeMove=ISInventoryPaneContextMenu.onMoveItemsTo
ISInventoryPaneContextMenu.onMoveItemsTo=function() error('fixture native transfer error') end
assert(not pcall(Q.transfer,selection,'2'))
assert(ISInventoryTransferUtil.newInventoryTransferAction==allocator, 'allocator must restore after a native callback error')
ISInventoryPaneContextMenu.onMoveItemsTo=nativeMove
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
print('Quantity selection, common budget, native transfers, stale/respawn/reachability and dialogs passed' .. (NativeInventoryContextMenuSource and ' with actual native callbacks.' or '.'))
