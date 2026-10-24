local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
package.loaded['PZSurvivorToolkit/ItemAccess'] = dofile(root .. 'shared/PZSurvivorToolkit/ItemAccess.lua')
local R = dofile(root .. 'shared/PZSurvivorToolkit/ItemRetention.lua')
package.loaded['PZSurvivorToolkit/ItemRetention'] = R
local View = dofile(root .. 'client/PZSurvivorToolkit/InventoryRetention.lua')
local function item(data)
    return {hasModData=function() return next(data) ~= nil end, getModData=function() return data end}
end
local a, b, c = item({}), item({pzstRetained=true}), item({ocStuck=true})
local group = {items={a,a,b,c}}
local pane = {items={group,a,b,c}, itemHgt=20, headerHgt=20, height=150, column3=200,
    getYScroll=function(self) return self.scroll or 0 end}
local function expect(...)
    local marks, expected = View.marks(pane), {...}
    assert(#marks == #expected, 'wrong marker count')
    for index, value in ipairs(expected) do assert(marks[index] == value, 'wrong physical retained row') end
end
View.invalidate(pane); expect(1,3,4)
-- Collapsed headers include retained children beyond native/CleanUI render caps.
pane.items={group}; expect(1)
pane.items={group,a,b,c}; pane.scroll=-40; expect(3,4)
pane.scroll=0; pane.height=60; expect(1)
pane.height=150; pane.dragStarted=true; pane.dragging=true; pane.selected={[1]=true,[3]=true}
expect(4)
pane.dragStarted, pane.dragging, pane.selected=nil,nil,nil
R.apply(b,false); R.apply(c,false)
View.invalidate(pane); expect()
R.apply(a,true); View.invalidate(pane); expect(1,2)
-- CleanUI's optimized arrays contain actual items starting at index one.
pane.items={{items={a,b},cleanUILargeStackOptimized=true},a,b}; View.invalidate(pane); expect(1,2)
pane.items={{items={b,a},cleanUIFirstActualIndex=2},b,a}; View.invalidate(pane); expect(1,3)
pane.items={{type='separator',items={a,a}},a}; View.invalidate(pane); expect()
local draws={}
getTexture=function(path) assert(path=='media/ui/Entity/keep_item_icon.png');return path end
pane.drawTextureScaled=function(_,texture,x,y,w,h)
    draws[#draws+1]={x=x,y=y,w=w,h=h}
end
pane.items={group,a,b}; View.invalidate(pane); View.draw(pane)
assert(#draws==2 and draws[1].x==182 and draws[1].y==24 and draws[2].y==44)
pane.scroll=-10; draws={}; View.draw(pane)
assert(#draws==1 and draws[1].y==44, 'marker must not escape the fixed header')
pane.scroll=0;pane.height=50;draws={};View.draw(pane)
assert(#draws==1, 'marker must not escape the pane bottom')
print('Retention markers: mixed/expanded/optimized rows, live invalidation, viewport, drag and bounds passed.')
