-- Display sampling is bounded; authoritative ratios and transfer decisions stay fresh.
local callbacks, now = {}, 1000
Events=setmetatable({}, {__index=function(t,key)
    local event={Add=function(fn) callbacks[key]=fn end}; rawset(t,key,event); return event
end})
require=function() end
PZAPI={ModOptions={create=function()
    return {addTickBox=function() return {getValue=function() return true end} end}
end}}
getTimestampMs=function() return now end
local player={}
getSpecificPlayer=function() return player end
local Capacity=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventoryCapacity.lua')
local reads=0
local function inventory(weight)
    return {weight=weight, maximum=10,
        getEffectiveCapacity=function(self) return self.maximum end,
        getCapacityWeight=function(self) reads=reads+1; return self.weight end}
end
local function owner()
    return {rects={}, height=100, headerHgt=10, getYScroll=function() return 0 end,
        getHeight=function() return 30 end, getWidth=function() return 24 end,
        drawRect=function(self,...) self.rects[#self.rects+1]={...} end,
        drawRectBorder=function() end}
end
local container=inventory(2)
local button=owner(); button.inventory=container
local function draw()
    button.rects={}; Capacity.drawButton(button,0)
    return button.rects[2] and button.rects[2][3]
end
local initial=draw()
for _=1,120 do assert(draw()==initial) end
assert(reads==1,'120 redraws must reuse one owner sample')
container.weight=8 -- Nested/fluid weight changes without any item-count change/event.
now=1199; assert(draw()==initial and reads==1)
now=1200; assert(draw()>initial and reads==2,'TTL refreshes weight without an item-count signal')
container.weight=3
assert(Capacity.ratio(container,player)==.3 and reads==3,'public ratio must remain immediate')
assert(draw()>initial and reads==3,'authoritative read must not alter presentation sampling')
callbacks.OnContainerUpdate(container); draw(); assert(reads==4,'container event invalidates immediately')
local other=inventory(4); button.inventory=other; draw(); assert(reads==5,'pooled rebind changes sample')
local page={backpacks={button},buttonPool={},inventoryPane=owner()}
other.weight=9
callbacks.OnRefreshInventoryWindowContainers(page,'end'); draw(); assert(reads==6,'same-container pooled refresh invalidates')
page.backpacks={};page.buttonPool={button}
callbacks.OnRefreshInventoryWindowContainers(page,'begin'); draw(); assert(reads==7,'idle pooled records invalidate too')
now=1100; draw(); assert(reads==8,'clock rollback invalidates')
player={}; draw(); assert(reads==9,'player identity invalidates')
for _,event in ipairs({'OnGameStart','OnMainMenuEnter','OnCreatePlayer'}) do
    callbacks[event]();draw()
end
assert(reads==12,'world/player lifecycle invalidates without retaining owner registries')
getTimestampMs=nil;draw();draw();assert(reads==14,'missing clock falls back to immediate display')
getTimestampMs=function() return 0/0 end;draw();draw();assert(reads==16,'invalid clock never freezes display')
getTimestampMs=function() return now end
player=nil;draw();assert(button.toolkitCapacitySnapshot==nil,'missing player releases button record')
player={}
draw();local clockReads=reads
now=now+100;draw();assert(reads==clockReads)
now=now-1;draw();assert(reads==clockReads+1,'rollback within a still-live sample invalidates too')

local pane=owner();pane.inventory=container
local function bag(inv) return {IsInventoryContainer=function() return true end,getInventory=function() return inv end} end
local a,b=inventory(1),inventory(7)
local bagA,bagB=bag(a),bag(b)
local function icon(item) Capacity.drawIcon(pane,item,0,20,24,24,true) end
reads=0
for _=1,90 do icon(bagA);icon(bagB);icon(bagA) end
assert(reads==2,'distinct bag icons and duplicate stack representatives reuse pane samples')
a.weight=8; now=now+200;icon(bagA);assert(reads==3,'bag fluid/nested weight expires without count changes')
callbacks.OnContainerUpdate();icon(bagB);assert(reads==4)
pane.inventory=other;icon(bagB);assert(reads==5,'pane container switch invalidates bag snapshots')
callbacks.OnRefreshInventoryWindowContainers({inventoryPane=pane},'end');icon(bagB);assert(reads==6)
now=now-1;icon(bagB);assert(reads==7)
player=nil;icon(bagB);assert(pane.toolkitCapacityIcons==nil,'missing player releases icon records')
player={}
for index=1,100 do icon(bag(inventory(index))) end
local records=0
for _ in pairs(pane.toolkitCapacityIcons.records) do records=records+1 end
assert(records==64 and #pane.toolkitCapacityIcons.slots==64,'icon cache must remain bounded without weak tables')
local before=reads
Capacity.drawIcon(pane,bagA,0,-100,24,24,true)
assert(reads==before,'offscreen icons do not sample weight')
print('PASS capacity display: bounded redraw sampling, fresh authoritative ratios, weight TTL, events, pooled rebind, clock/player/lifecycle reset and bounded bag cache')
