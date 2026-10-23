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
local R=dofile(root..'shared/PZSurvivorToolkit/ItemRetention.lua')
local modules={['PZSurvivorToolkit/ItemRetention']=R}
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
local vehicle={allowed=true}
function vehicle:getId() return 12 end
function vehicle:getCurrentSquare() return near end
function vehicle:getPartByIndex(index) if index==0 then return trunk.part end end
function vehicle:canAccessContainer(index,actor) return self.allowed and index==0 and actor==player end
trunk.part={getVehicle=function() return vehicle end,getIndex=function() return 0 end,getItemContainer=function() return trunk end}
getVehicleById=function(id) if id==12 then return vehicle end end
local cargo=item(5,trunk)
local cargoLocation=R.locate(cargo,player)
assert(cargoLocation.vehicle==12 and cargoLocation.part==0 and set({cargoLocation},true)==1)
vehicle.allowed=false;assert(set({cargoLocation},false)==0 and R.isRetained(cargo));vehicle.allowed=true
assert(set({{id=5,x=10,y=10,z=0,vehicle=12,part=0}},false)==0,'forged/stale vehicle coordinates fail')
assert(set({{id=5,x=11,y=10,z=0,vehicle=12,part=1}},false)==0,'wrong exact part fails')
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
ISInventoryPane={transferItemsByWeight=function(_,entries) transfers[#transfers+1]=entries;return entries end}
ISInventoryPaneContextMenu={onMoveItemsTo=function(entries) transfers[#transfers+1]=entries;return entries end}
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
ISMouseDrag={dragging={{items={held,held}}}}
assert(#ISInventoryPane.transferItemsByWeight({}, {held}, inv)==1,'one explicit drag row may move retained item')
ISMouseDrag=nil
assert(#ISInventoryPaneContextMenu.onMoveItemsTo({held,mine},inv,0)==0,'multirow context mass moves skip retention')
assert(#ISInventoryPaneContextMenu.onMoveItemsTo({held},inv,0)==1,'deliberate single-item context moves remain allowed')
assert(not ISInventoryPageTransferHandler.canTransferItem(held,inv,player),'CleanUI quick transfers cannot bypass retention')
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
