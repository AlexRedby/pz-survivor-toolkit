-- Live food values and the owner's published rows are the freshness boundary.
local root=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'
local options, checks, getters, upstreamCalls
local function setup(active, installed)
    options={showFoodFreshnessBar=true,showFoodFreshnessPercentage=true}
    checks,getters,upstreamCalls=0,0,0
    getActivatedMods=function() return {contains=function(_,id) return active and id=='EURY_CONTAINERS' end} end
    instanceof=function(item,kind) checks=checks+1;return kind=='Food' and type(item)=='table' and item.food end
    UIFont={Medium='medium'}
    getTextManager=function() return {MeasureStringX=function(_,_,text) return #text*5 end,
        getFontHeight=function() return 12 end} end
    ISInventoryPane={renderdetails=function() return 'native' end,MAX_ITEMS_IN_STACK_TO_RENDER=50}
    local upstream={_installed=installed}
    upstream.install=function()
        upstreamCalls=upstreamCalls+1
        if upstream._installed then return end
        upstream._installed=true
    end
    require=function(name)
        if name=='BetterContainers/_Options' then return options end
        if name=='BetterContainers/Upgrades/FoodFreshness' then return upstream end
    end
    local result=dofile(root..'PZSurvivorToolkit/InventoryFreshness.lua')
    if active and not installed then
        assert(not upstream._installed,'requiring freshness activated it before the upstream install hook')
        upstream.install()
    end
    return result,upstream,ISInventoryPane
end
local function food(age,max,off)
    local value={food=true,age=age,max=max,off=off or 4}
    function value:getOffAgeMax() getters=getters+1;return self.max end
    function value:getAge() getters=getters+1;return self.age end
    function value:getOffAge() getters=getters+1;return self.off end
    return value
end
local function pane(rows)
    local p={items=rows,mode='details',height=200,width=400,headerHgt=20,itemHgt=20,column2=50,column3=300,
        font='medium',fontHgt=12,mouseOverOption=1,draws={}}
    function p:isReallyVisible() return self.visible~=false and self.parentVisible~=false end
    function p:getIsVisible() return self.visible~=false end
    function p:getYScroll() return self.scroll or 0 end
    function p:getHeight() return self.height end
    function p:setStencilRect(...) self.stencil={...};self.lastStencil=self.stencil end
    function p:clearStencilRect() self.stencil=nil end
    function p:repaintStencilRect(...) self.repaint={...} end
    function p:drawRect(...) self.draws[#self.draws+1]={'rect',...} end
    function p:drawText(...) self.draws[#self.draws+1]={'text',...} end
    return p
end
local function texts(p)
    local result={}
    for _,call in ipairs(p.draws) do if call[1]=='text' then result[#result+1]=call[2] end end
    return result
end
local function clear(p) p.draws={};checks,getters=0,0 end
local function equal(a,b,label)
    assert(#a==#b,label..': draw count '..#a..' vs '..#b)
    for i=1,#a do
        assert(#a[i]==#b[i],label..': argument count')
        for j=1,#a[i] do assert(a[i][j]==b[i][j],label..': draw '..i..' argument '..j) end
    end
end

local Freshness,upstream,class=setup(true,false)
assert(upstream._installed,'early ownership did not claim the upstream installer')
local function draw(value) return Freshness.draw(value,class) end
local native=class.renderdetails
upstream.install();upstream.install()
assert(class.renderdetails==native,'repeated upstream install wrapped the owned renderer')
local ordinary,rotten,infinite=food(2,10),food(12,10),food(1,1000000000)
local huge={name='large',items={}}
for i=1,10000 do huge.items[i]=ordinary end
huge.items[10000]=food(9.9,10)
local p=pane({huge})
draw(p)
assert(texts(p)[1]=='1%','collapsed stack ignored its worst tail beyond the render cap')
assert(getters>=30000,'visible group failed to read all current food values')
assert(p.draws[1][2]==58 and p.draws[1][3]==36 and p.draws[1][4]==234,
    'header bar geometry differs from upstream')
-- No cross-frame cache: age and thresholds may change without a refresh.
huge.items[10000].age=0;ordinary.age=3;clear(p);draw(p)
assert(texts(p)[1]=='70%','live age update retained an old worst item')
ordinary.max=20;clear(p);draw(p)
assert(texts(p)[1]=='85%','live spoilage threshold update was cached')
ordinary.max=10;ordinary.age=2
for _,scroll in ipairs({-1000000,1000000}) do
    p.scroll=scroll;clear(p);draw(p)
    assert(#p.draws==0 and checks==0 and getters==0,'clipped 10k stack touched Food/native getters')
end
p.scroll=0
options.showFoodFreshnessBar=false;options.showFoodFreshnessPercentage=false
clear(p);draw(p);assert(checks==0 and getters==0 and #p.draws==0,'disabled flags scanned food')
options.showFoodFreshnessBar=true;clear(p);draw(p)
assert(#p.draws==4 and #texts(p)==0,'bar-only option changed')
options.showFoodFreshnessBar=false;options.showFoodFreshnessPercentage=true
clear(p);draw(p);assert(#p.draws==2 and texts(p)[1]=='80%','percentage-only option changed')
options.showFoodFreshnessBar=true

-- A header uses the full group; expanded children use their own freshness.
local first,second=food(1,10),food(7,10)
local group={name='expanded',items={first,second}}
p=pane({group,second});p.mouseOverOption=0;draw(p)
assert(#texts(p)==1 and texts(p)[1]=='30%','expanded child lost permanent percentage')
p.mouseOverOption=1;clear(p);draw(p)
assert(#texts(p)==2 and texts(p)[1]=='30%' and texts(p)[2]=='30%','header hover percentage changed')
p.mouseOverOption=2;clear(p);draw(p)
assert(#texts(p)==1,'child hover incorrectly enabled header percentage')
-- Viewport begins inside an expanded stack: offscreen header must not rescan it.
p=pane({huge,second});p.scroll=-20;p.mouseOverOption=0
clear(p);draw(p);assert(getters<20 and texts(p)[1]=='30%','mid-stack viewport scanned clipped header')
-- A group beginning on the bottom border is entirely outside the stencil.
-- Keep the preceding physical child visible, without reading the 10k group.
p=pane({{type='separator'},{type='separator'},{type='separator'},second,huge})
p.height=100;p.scroll=-1;p.mouseOverOption=0
clear(p);draw(p)
assert(checks==1 and getters==3,'bottom-border clipped 10k group reached native reads')
assert(#p.draws==6 and texts(p)[1]=='30%' and p.draws[1][3]==96,
    'bottom-border clipping lost the preceding visible child')
-- Partial bars and percentage backgrounds must stay below the fixed header.
p=pane({group,second});p.scroll=-7;draw(p)
assert(p.lastStencil and p.lastStencil[2]==20 and p.lastStencil[4]==179,
    'partial row was not clipped below the fixed header')
assert(not p.stencil and p.repaint[2]==20,'freshness leaked its stencil')
-- Native owners already account for separators and equipped-collapse projection.
p=pane({'separator',{type='separator'},{_bcEquippedAttachedSeparator=true},second})
p.itemslist={huge,{equipped=true,items={rotten}}};p.equippedCollapsed=true;p.mouseOverOption=0
clear(p);draw(p)
assert(getters==3 and texts(p)[1]=='30%','published physical row projection was reconstructed')
assert(p.draws[1][3]==96,'separator rows changed the published y coordinate')
p=pane({{type='separator'},{_bcEquippedAttachedSeparator=true}});clear(p);draw(p)
assert(checks==0 and getters==0,'separator metadata reached instanceof or getters')
p=pane({huge,second});p.dragStarted=true;p.dragging=true;p.selected={[1]=true,[2]=true}
clear(p);draw(p);assert(checks==0 and getters==0 and #p.draws==0,'dragged original rows scanned food')
local broken=food(1,10);broken.getAge=function() error('food getter failed') end
p=pane({{items={broken}}})
assert(not pcall(draw,p) and not p.stencil and p.repaint,'getter failure leaked the freshness stencil')

p=pane({{items={{},infinite,food(0,0),food(0,-1),rotten,first}}})
draw(p);assert(texts(p)[1]=='0%','mixed/nonperishable/rotten group selection changed')
p=pane({{items={{},infinite,food(0,0)}}});clear(p);draw(p)
assert(#p.draws==0,'invalid or infinite food received a freshness indicator')
p=pane({{items={food(-2,10)}}});draw(p);assert(texts(p)[1]=='100%','freshness upper clamp changed')
p=pane({group});p.mode='icons';clear(p);draw(p);assert(checks==0 and #p.draws==0)
p.mode='details';p.visible=false;clear(p);draw(p);assert(checks==0 and #p.draws==0,'hidden pane scanned food')
p.visible=true;p.parentVisible=false;clear(p);draw(p)
assert(p:getIsVisible() and checks==0 and #p.draws==0,'hidden parent scanned food')
p.parentVisible=true
local layout=Freshness.layout(class,p,first)
assert(layout and layout.reservedLeft==280 and layout.reservedRight==300,'owned percentage reservation missing')
assert(not Freshness.layout({},p,first),'owned reservation leaked to a class upstream never installed')
local switched={}
ISInventoryPane=switched;upstream.install();clear(p);Freshness.draw(p,switched)
assert(#p.draws==0 and getters==0,'repeated install activated a previously inactive class')
ISInventoryPane=class;clear(p);draw(p);assert(#p.draws>0,'switching back lost the installed class')
options.showFoodFreshnessPercentage=false;assert(not Freshness.layout(class,p,first))
options.showFoodFreshnessPercentage=true;assert(not Freshness.layout(class,p,infinite))

-- When another owner already installed, keep its renderer and class reservation.
local fallback,late,original=setup(true,true)
assert(original.renderdetails()== 'native')
p=pane({group});fallback.draw(p,original);assert(#p.draws==0,'late activation drew over upstream')
assert(not fallback.layout(original,p,first),'late activation guessed an unobserved installation class')
late._installed=nil;late.install()
assert(fallback.layout(original,p,first),'observed late upstream install did not reserve its class')
assert(not fallback.layout({},p,first),'fallback reserved an unrelated class')
local inactive,unused=setup(false,false)
p=pane({group});inactive.draw(p,{})
assert(not unused._installed and #p.draws==0 and not inactive.layout({},p,first),'inactive BC activated freshness')

-- Optional actual-source parity: the integration runner injects active workshop
-- source. Only aligned rows are compared; published-row fixes have tests above.
if NativeBCFreshnessSource then
    local owned,_,ownedClass=setup(true,false)
    local originalOptions=options
    ISInventoryPane={renderdetails=function() return 'native' end,MAX_ITEMS_IN_STACK_TO_RENDER=50}
    local upstreamModule=assert(loadstring(NativeBCFreshnessSource))()
    upstreamModule.install()
    local sourceRender=ISInventoryPane.renderdetails
    local compared=0
    for _,flags in ipairs({{true,true},{true,false},{false,true}}) do
        originalOptions.showFoodFreshnessBar=flags[1];originalOptions.showFoodFreshnessPercentage=flags[2]
        for _,hover in ipairs({0,1,2}) do
            for _,fixture in ipairs({{items={first,second}}, {items={first,rotten}}, {items={infinite,first}}}) do
                for _,column3 in ipairs({300,114,113}) do
                local expected=pane({fixture,fixture.items[2]});expected.column3=column3
                expected.itemslist={fixture};expected.collapsed={};expected.mouseOverOption=hover
                sourceRender(expected,false)
                local actual=pane(expected.items);actual.mouseOverOption=hover;actual.column3=column3
                owned.draw(actual,ownedClass)
                equal(actual.draws,expected.draws,'active Better Containers source parity')
                compared=compared+1
                end
            end
        end
    end
    print('inventory freshness: '..compared..' active Better Containers draw-stream comparisons passed')
else
    print('SKIP: active Better Containers source parity requires NativeBCFreshnessSource')
end
print('inventory freshness: live groups, visibility, native row projection, options, lifecycle and reservations passed')
