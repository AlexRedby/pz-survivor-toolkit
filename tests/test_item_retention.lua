local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local callbacks = {}
Events = {}
for _, name in ipairs({'OnClientCommand','OnServerCommand','OnFillInventoryObjectContextMenu','OnGameStart','OnCreatePlayer'}) do
    callbacks[name] = {}
    Events[name] = {Add=function(fn) callbacks[name][#callbacks[name]+1]=fn end}
end
local client, server = false, true
isClient=function() return client end
isServer=function() return server end
local function list(values)
    return {size=function() return #values end,get=function(_,index) return values[index+1] end}
end
instanceof=function(value, class) return value and value.class == class or class=='InventoryItem' and value and value.item end
local function square(x,y,z)
    local s={x=x,y=y,z=z,objects={},bodies={}}
    function s:getX() return self.x end
    function s:getY() return self.y end
    function s:getZ() return self.z end
    function s:getObjects() return list(self.objects) end
    function s:getStaticMovingObjects() return list(self.bodies) end
    function s:isBlockedTo(other) return self.blocked end
    return s
end
local here,near,far,up = square(10,10,0),square(11,10,0),square(15,10,0),square(10,10,1)
local squares={here,near,far,up}
getCell=function() return {getGridSquare=function(_,x,y,z)
    for _,s in ipairs(squares) do if s.x==x and s.y==y and s.z==z then return s end end
end} end
local player={square=here}
function player:isDead() return self.dead end
function player:getCurrentSquare() return self.square end
function player:getInventory() return self.inventory end
function player:getOnlineID() return 7 end
function player:canAccessContainer(c) return not c.locked end
local function container(s,owned)
    local c={values={},square=s,owned=owned}
    function c:isInCharacterInventory(actor) return self.owned and actor==player end
    function c:getItemWithIDRecursiv(id)
        for _, item in ipairs(self.values) do
            if item.id==id then return item end
            if item.inventory then
                local found=item.inventory:getItemWithIDRecursiv(id)
                if found then return found end
            end
        end
    end
    function c:getParent() return self.parent end
    function c:getVehiclePart() return self.part end
    function c:getContainingItem() return self.holder end
    function c:getSourceGrid() return self.square end
    return c
end
local function item(id,c,data)
    local i={id=id,source=c,data=data or {},item=true}
    function i:getID() return self.id end
    function i:getName() return tostring(self.id) end
    function i:getContainer() return self.source end
    function i:getOutermostContainer() return self.outer or self.source end
    function i:getWorldItem() return self.world end
    function i:hasModData() return next(self.data)~=nil end
    function i:getModData() return self.data end
    if c then c.values[#c.values+1]=i end
    return i
end
local function object(s,c)
    local o={}
    function o:getSquare() return s end
    function o:getContainerCount() return 1 end
    function o:getContainerByIndex(index) if index==0 then return c end end
    s.objects[#s.objects+1]=o;c.parent=o
    return o
end
local inv,crate,remote,upper=container(nil,true),container(near),container(far),container(up)
player.inventory=inv
object(near,crate); object(far,remote); object(up,upper)
local mine,held,other,above=item(1,inv,{ocStuck=true,untouched=42}),item(2,crate),item(3,remote),item(4,upper)
local Access=dofile(root..'shared/PZSurvivorToolkit/ItemAccess.lua')
package.loaded['PZSurvivorToolkit/ItemAccess']=Access
local R=dofile(root..'shared/PZSurvivorToolkit/ItemRetention.lua')
local modules={['PZSurvivorToolkit/ItemRetention']=R,['PZSurvivorToolkit/ItemAccess']=Access}
require=function(name)
    if modules[name] then return modules[name] end
    local file=root..'client/'..name..'.lua'
    local result=dofile(file);modules[name]=result;return result
end
assert(R.isEnabled() and R.isRetained(mine),'OC saved flag must remain effective without OC namespace/options')
R.apply(mine,false)
assert(not R.isRetained(mine) and mine.data.ocStuck==nil and mine.data.untouched==42)
R.apply(mine,true)
assert(mine.data.pzstRetained==true)
local syncs,wire={},{ }
syncItemModData=function(actor,value) assert(actor==player);syncs[#syncs+1]=value end
sendServerCommand=function(...) wire[#wire+1]={...} end
SafeHouse={isSafehouseAllowLoot=function(s,actor) return not s.denied end}
dofile(root..'server/PZSurvivorToolkit/ItemRetentionAuthority.lua')
local seq=0
local function set(locators,value)
    seq=seq+1
    return R.applyRequest(player,{request=seq,retained=value,items=locators})
end
local own={id=1,inv=true};local nearby={id=2,x=11,y=10,z=0}
assert(set({own,nearby},true)==2 and R.isRetained(held) and #syncs==2)
assert(wire[1][1]==R.MODULE and wire[1][2]=='State' and wire[2][2]==R.MODULE and wire[2][3]=='Result')
assert(R.applyRequest(player,{request=seq,retained=false,items={nearby}})==nil and R.isRetained(held),'duplicate/reordered set must not reverse newer state')
assert(set({{id=3,x=15,y=10,z=0},{id=4,x=10,y=10,z=1},{id=2,inv=true}},true)==0,'range, floor and forged ownership fail')
here.blocked=true;assert(set({nearby},false)==0 and R.isRetained(held));here.blocked=nil
crate.locked=true;assert(set({nearby},false)==0);crate.locked=nil
near.denied=true;assert(set({nearby},false)==0);near.denied=nil
player.dead=true;assert(set({nearby},false)==nil);player.dead=nil
held.outer=remote
assert(set({nearby},false)==0,'a stale collection entry cannot override the actual item root location')
held.outer=nil
assert(set({nearby},false)==1 and not R.isRetained(held))
assert(set({[2]=nearby},true)==nil,'sparse arrays rejected')
assert(set({{id=2,x=0/0,y=10,z=0}},true)==nil,'nonfinite coordinates rejected')
assert(set({{id=2,x=11,y=10,z=0,arbitrary=true}},true)==nil,'unrecognized locator fields rejected')
local large={};for i=1,R.MAX_ITEMS+1 do large[i]=nearby end
assert(set(large,true)==nil,'request size bounded before resolution')
-- Vehicle identity, part access and current position are verified from server objects.
local trunk=container(near)
local vehicle={allowed=true,square=near}
function vehicle:getId() return 12 end
function vehicle:getCurrentSquare() return self.square end
local otherTrunk=container(near)
function vehicle:getPartByIndex(index) if index==0 then return trunk.part elseif index==1 then return otherTrunk.part end end
function vehicle:canAccessContainer(index,actor) return self.allowed and (index==0 or index==1) and actor==player end
trunk.part={getVehicle=function() return vehicle end,getIndex=function() return 0 end,getItemContainer=function() return trunk end}
otherTrunk.part={getVehicle=function() return vehicle end,getIndex=function() return 1 end,getItemContainer=function() return otherTrunk end}
getVehicleById=function(id) if id==12 then return vehicle end end
local cargo=item(5,trunk)
local cargoLocation=R.locate(cargo,player)
assert(cargoLocation.vehicle==12 and cargoLocation.part==0 and set({cargoLocation},true)==1)
vehicle.allowed=false;assert(set({cargoLocation},false)==0 and R.isRetained(cargo));vehicle.allowed=true
-- Host clients can report the adjacent vehicle square while the exact item,
-- vehicle and part still match. Admission uses the live server access gates.
local drift=square(11,11,0)
vehicle.square=drift
assert(set({cargoLocation},false)==1 and not R.isRetained(cargo),
    'one-tile replicated vehicle-square drift must not reject the exact accessible cargo item')
R.apply(cargo,true)
assert(set({{id=5,x=11,y=10,vehicle=12,part=0}},false)==nil,'vehicle locators still require valid coordinate shape')
assert(set({{id=5,x=10,y=10,z=0,vehicle=13,part=0}},false)==0,'wrong exact vehicle fails')
assert(set({{id=999,x=11,y=10,z=0,vehicle=12,part=0}},false)==0,'wrong exact cargo item fails')
assert(set({{id=5,x=11,y=10,z=0,vehicle=12,part=1}},false)==0,'wrong exact part fails')
-- Even a stale old-part collection entry cannot claim an item moved elsewhere.
cargo.source=otherTrunk;otherTrunk.values={cargo}
assert(set({cargoLocation},false)==0 and R.isRetained(cargo),'stale old-part membership cannot bypass the actual cargo part')
cargo.source=trunk;otherTrunk.values={}
vehicle.square=square(20,10,0)
assert(set({cargoLocation},false)==0,'live distant vehicle fails despite the nearby client coordinates')
vehicle.square=up
assert(set({cargoLocation},false)==0,'live vehicle on another floor fails despite the client floor')
vehicle.square=drift
vehicle.allowed=false;assert(set({cargoLocation},false)==0);vehicle.allowed=true
trunk.locked=true;assert(set({cargoLocation},false)==0);trunk.locked=nil
drift.denied=true;assert(set({cargoLocation},false)==0,'live vehicle SafeHouse denial remains authoritative');drift.denied=nil
local cargoBag=item(14,trunk);cargoBag.class='InventoryContainer';cargoBag.inventory=container(nil)
function cargoBag:getInventory() return self.inventory end
cargoBag.inventory.holder=cargoBag
local cargoChild=item(15,cargoBag.inventory);cargoChild.outer=trunk
local nestedCargoLocation=R.locate(cargoChild,player)
cargoBag.inventory.locked=true
assert(set({nestedCargoLocation},true)==0,'a nested vehicle bag retains its own access gate')
cargoBag.inventory.locked=nil
assert(set({nestedCargoLocation},true)==1 and R.isRetained(cargoChild))
assert(R.isRetained(cargo),'rejected vehicle edits leave the original retained state intact')
vehicle.square=near
-- Nested roots keep both the container and inner bag access checks.
local bag=item(6,crate);bag.class='InventoryContainer';bag.inventory=container(nil)
function bag:getInventory() return self.inventory end
bag.inventory.holder=bag
local nested=item(7,bag.inventory);nested.outer=crate
bag.inventory.locked=true
assert(set({{id=7,x=11,y=10,z=0}},true)==0)
bag.inventory.locked=nil
assert(set({{id=7,x=11,y=10,z=0}},true)==1 and R.isRetained(nested))
local carriedBag=item(12,inv);carriedBag.class='InventoryContainer';carriedBag.inventory=container(nil,true)
function carriedBag:getInventory() return self.inventory end
carriedBag.inventory.holder=carriedBag
local carriedChild=item(13,carriedBag.inventory)
inv.locked=true
assert(set({{id=13,inv=true}},true)==0,'owned nested inventory still checks every protected ancestor')
inv.locked=nil
assert(set({{id=13,inv=true}},true)==1 and R.isRetained(carriedChild))
-- Loose floor items and nested world bags have no player-owned container.
local function worldObject(value)
    local world={class='IsoWorldInventoryObject',getItem=function() return value end,getSquare=function() return near end}
    value.world=world;near.objects[#near.objects+1]=world;return world
end
local loose=item(8,nil)
worldObject(loose)
local syncBefore=#syncs
assert(set({R.locate(loose,player)},true)==1 and R.isRetained(loose) and #syncs==syncBefore,
    'loose world items use authoritative State without a missing native ContainerID')
local worldBag=item(9,nil);worldBag.class='InventoryContainer';worldBag.inventory=container(nil)
function worldBag:getInventory() return self.inventory end
worldBag.inventory.holder=worldBag;worldObject(worldBag)
local innerBag=item(10,worldBag.inventory);innerBag.class='InventoryContainer';innerBag.inventory=container(nil)
function innerBag:getInventory() return self.inventory end
innerBag.inventory.holder=innerBag
local worldNested=item(11,innerBag.inventory);worldNested.outer=worldBag.inventory
worldBag.inventory.locked=true
assert(set({R.locate(worldNested,player)},true)==0,'outer world-bag lock remains authoritative for nested items')
worldBag.inventory.locked=nil
assert(set({R.locate(worldNested,player)},true)==1 and R.isRetained(worldNested))
-- Client UI uses the actual menu callback and never treats optimistic state as acceptance.
local Protection=dofile(root..'shared/PZSurvivorToolkit/InventoryTransferProtection.lua')
modules['PZSurvivorToolkit/InventoryTransferProtection']=Protection
modules['PZSurvivorToolkit/InventoryClasses']={panes=function(fn) fn(ISInventoryPane) end,onToggle=function(fn) end}
getSpecificPlayer=function(index) if index==0 then return player end end
getNumActivePlayers=function() return 1 end
local refreshes=0
local page={inventoryPane={refreshContainer=function() refreshes=refreshes+1 end}}
getPlayerInventory=function() return page end
getPlayerLoot=function() return page end
getTexture=function(path) return path end
getText=function(key) return key end
local transfers={}
local function transferEntries(entries) transfers[#transfers+1]=entries;return entries end
ISInventoryPane={
    transferItemsByWeight=function(_,entries) return transferEntries(entries) end,
    onContext=function(pane) return ISInventoryPaneContextMenu.onMoveItemsTo(Protection.items({pane.items[pane.buttonOption]}), inv, pane.player) end,
    doGrabOnJoypadSelected=function(pane) return ISInventoryPaneContextMenu.onGrabItems(Protection.items({pane.items[pane.joyselection+1]}), pane.player) end,
}
ISInventoryPaneContextMenu={addToolTip=function() return {} end,onMoveItemsTo=function(entries,destination,playerNum)
    if destination=='floor' then return ISInventoryPaneContextMenu.onDropItems(entries,playerNum) end
    return transferEntries(entries)
end}
for _,name in ipairs({'onGrabItems','onGrabHalfItems','onGrabOneItems','onPutItems','onDropItems'}) do
    ISInventoryPaneContextMenu[name]=transferEntries
end
ISInventoryPaneContextMenu.createMenu=function(playerNum,inInventory,rows)
    local actual=Protection.items(rows)
    local child={options={}}
    for _,name in ipairs({'onGrabItems','onGrabHalfItems','onGrabOneItems','onPutItems','onDropItems'}) do
        child.options[#child.options+1]={onSelect=ISInventoryPaneContextMenu[name],target=rows}
    end
    child.options[#child.options+1]={onSelect=ISInventoryPaneContextMenu.onMoveItemsTo,target=actual}
    local menu={options={{subOption=1}},getSubMenu=function() return child end}
    menu.actual,menu.child=actual,child
    return menu
end
ISInventoryPageTransferHandler={canTransferItem=function() return true end}
local sent={}
sendClientCommand=function(actor,module,command,args) sent[#sent+1]={actor=actor,module=module,command=command,args=args} end
client,server=true,false
dofile(root..'client/PZSurvivorToolkit/ItemRetentionUI.lua')
R.install()
R.apply(held,false)
local menu={options={},addOption=function(self,label,target,callback,param)
    local option={name=label,target=target,onSelect=callback,param1=param};self.options[#self.options+1]=option;return option
end}
callbacks.OnFillInventoryObjectContextMenu[1](0,menu,{held})
local option=menu.options[1]
assert(option.pzstKey=='retainItem' and option.name=='UI_PZSurvivorToolkit_retain_item')
assert(option.iconTexture=='media/textures/PZSurvivorToolkit/item_retained.png' and option.toolTip.description=='UI_PZSurvivorToolkit_retain_item_tip')
option.onSelect(option.target,option.param1)
assert(#sent==1 and sent[1].command=='Set' and sent[1].args.retained and not R.isRetained(held),'menu callback sends request without optimistic mutation')
local result={request=sent[1].args.request,accepted=1,rejected=0}
callbacks.OnServerCommand[1](R.MODULE,'Result',result)
assert(R.lastResult==result and not R.isRetained(held),'ack count alone is not item-state proof')
callbacks.OnServerCommand[1](R.MODULE,'State',{owner=7,retained=true,items={nearby}})
assert(R.isRetained(held) and refreshes==2)
R.apply(mine,true)
local mass=ISInventoryPane.transferItemsByWeight({}, {held,mine}, inv)
assert(#mass==0,'mass pane moves must skip retained items')
ISMouseDrag={dragging={{items={held,held}},{items={mine,mine}}}}
assert(#ISInventoryPane.transferItemsByWeight({}, {held,mine}, inv)==2,'explicit multirow drag may move all retained items')
assert(#ISInventoryPane.transferItemsByWeight({}, {held}, inv)==1,'narrowed drag callback keeps the same explicit intent')
local foreign=item(99,inv,{pzstRetained=true})
assert(#ISInventoryPane.transferItemsByWeight({}, {held,foreign}, inv)==0,'unrelated callback cannot borrow the current drag')
ISMouseDrag=nil
assert(#ISInventoryPaneContextMenu.onMoveItemsTo({held,mine},inv,0)==0,'automatic multirow context calls skip retention')
assert(#ISInventoryPaneContextMenu.onMoveItemsTo({held},inv,0)==0,'automatic one-item Move to Floor also keeps retention')
local selected={{items={held,held}},{items={mine,mine}}}
local transferMenu=ISInventoryPaneContextMenu.createMenu(0,false,selected)
assert(#ISInventoryPaneContextMenu.onMoveItemsTo(transferMenu.actual,inv,0)==2,'menu Move gets its distinct flattened multirow payload')
assert(#ISInventoryPaneContextMenu.onMoveItemsTo(transferMenu.actual,'floor',0)==2,'selected floor move keeps intent through nested Drop')
for index=1,5 do
    local option=transferMenu.child.options[index]
    assert(#option.onSelect(option.target,0)==2,'manual Grab/Half/One/Put/Drop must keep the selected retained objects')
end
assert(#ISInventoryPaneContextMenu.onMoveItemsTo(transferMenu.actual,inv,1)==0,'another player cannot reuse a menu payload')
transferMenu.actual[#transferMenu.actual+1]=foreign
assert(#ISInventoryPaneContextMenu.onMoveItemsTo(transferMenu.actual,inv,0)==0,'mutated payload must not bless extra retained objects')
assert(#ISInventoryPane.onContext({items={selected[1]},buttonOption=1,player=0})==1,'single-row action buttons keep their explicit selection')
assert(#ISInventoryPane.doGrabOnJoypadSelected({items={selected[1]},joyselection=0,player=0})==1,'controller picks keep their explicit selection')
assert(#ISInventoryPaneContextMenu.onMoveItemsTo({held},inv,0)==0,'row/controller scopes must not leak to later automatic transfers')
assert(not ISInventoryPageTransferHandler.canTransferItem(held,inv,player),'CleanUI Transfer All cannot bypass retention')
assert(R.isRetained(held) and R.isRetained(mine),'manual transfer never clears retained flags')
local before=ISInventoryPane.transferItemsByWeight;R.install();assert(before==ISInventoryPane.transferItemsByWeight,'pane hooks idempotent')
assert(R.isContextWrapper(ISInventoryPaneContextMenu,'onMoveItemsTo'))
local reviewed=ISInventoryPaneContextMenu.onMoveItemsTo
ISInventoryPaneContextMenu.onMoveItemsTo=function() end
assert(not R.isContextWrapper(ISInventoryPaneContextMenu,'onMoveItemsTo'),'foreign callback replacement cannot inherit reviewed identity')
local foreign=ISInventoryPaneContextMenu.onMoveItemsTo
R.install()
assert(ISInventoryPaneContextMenu.onMoveItemsTo==foreign and not R.isContextWrapper(ISInventoryPaneContextMenu,'onMoveItemsTo'),
    'reinstall must not bless a changed callback with a fresh owner wrapper')
ISInventoryPaneContextMenu.onMoveItemsTo=reviewed
assert(not R.isContextWrapper({onMoveItemsTo=reviewed},'onMoveItemsTo'),'foreign owner cannot inherit reviewed identity')
client,server=false,false
R.setRetained(0,{held},false)
assert(not R.isRetained(held),'SP authoritative local edit works')
print('Retained-item migration, authoritative admission, replay bounds, menu callback, state and transfer hooks passed.')

-- Execute the installed game's actual option builders: Grab uses the original
-- rows, while the controller's Move submenu uses a separately flattened array.
if NativeInventoryContextMenuSource then
    local source=NativeInventoryContextMenuSource:gsub('\r','')
    local first=assert(source:find('function ISInventoryPaneContextMenu.doGrabMenu(',1,true))
    local last=assert(source:find('function ISInventoryPaneContextMenu.doEvorecipeMenu(',first,true))
    assert(loadstring(source:sub(first,last-1),'native retention grab builder'))()
    first=assert(source:find('local moveItems = ISInventoryPane.getActualItems(items)',1,true))
    last=assert(source:find('    if tests.animalCorpse then',first,true))
    local buildMove=assert(loadstring('return function(context,items,player,playerObj,playerInv,isInPlayerInventory,loot)\n'
        ..source:sub(first,last-1)..'\nend','native retention move builder'))()
    local function context(rootMenu)
        local value={options={},root=rootMenu}
        value.root=value.root or value
        value.children={}
        function value:addOption(label,target,callback,param1,param2)
            local option={name=label,target=target,onSelect=callback,param1=param1,param2=param2}
            self.options[#self.options+1]=option
            return option
        end
        function value:getNew()
            local child=context(self.root)
            child.menuID=#self.root.children+1
            self.root.children[child.menuID]=child
            return child
        end
        function value:addSubMenu(option,child) option.subOption=child.menuID end
        function value:getSubMenu(index) return self.root.children[index] end
        return value
    end
    page.inventory=inv
    inv.isItemAllowed=function() return true end
    inv.getItems=function() return list({}) end
    player.getJoypadBind=function() return 0 end
    player.getWornItems=function() return list({}) end
    player.getPrimaryHandItem=function() end
    player.getSecondaryHandItem=function() end
    isForceDropHeavyItem=function() return false end
    ISInventoryPane.getActualItems=Protection.items
    ISInventoryPage={GetFloorContainer=function() return crate end,lootAll=function() end,transferAll=function() end}
    ISInventoryPaneContextMenu.canUnpack=function() return true end
    ISInventoryPaneContextMenu.canMoveTo=function() end
    ISInventoryPaneContextMenu.hasRoomForAny=function() return true end
    ISInventoryPaneContextMenu.createMenu=function(playerNum,inInventory,rows)
        local result=context()
        ISInventoryPaneContextMenu.doGrabMenu(result,rows,playerNum)
        buildMove(result,rows,playerNum,player,inv,inInventory,page)
        return result
    end
    R.install()
    R.apply(held,true);R.apply(mine,true);R.apply(worldNested,true)
    local rows={{items={held,held,mine}},{items={worldNested,worldNested}}}
    local nativeMenu=ISInventoryPaneContextMenu.createMenu(0,false,rows)
    for index=1,3 do
        local option=nativeMenu.options[index]
        assert(option.target==rows and option.param1==0,'native Grab/One/Half use original rows and player param1')
        assert(#option.onSelect(option.target,option.param1)==2,
            'native-built Grab/One/Half callback must retain the registered original row payload')
    end
    local child=nativeMenu:getSubMenu(nativeMenu.options[4].subOption)
    local move=child.options[1]
    assert(move.target~=rows and #move.target==3 and move.param1==inv and move.param2==0,
        'native Move submenu uses separately flattened items, destination param1 and player param2')
    assert(#move.onSelect(move.target,move.param1,move.param2)==3,
        'native-built Move submenu must register its separate flattened payload')
    assert(#move.onSelect(move.target,move.param1,1)==0,'native-built Move intent remains bound to its player')
    assert(#ISInventoryPaneContextMenu.onMoveItemsTo({held,mine,worldNested},inv,0)==0,
        'a fresh automatic array cannot inherit native menu registration')
    print('Retention menu registration passed with actual native Grab and Move submenu builders.')
end
