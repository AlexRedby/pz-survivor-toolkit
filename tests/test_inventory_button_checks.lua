-- Source-backed setter model; the native probe separately exercises the real
-- discovery/event stack. Run with --game (or --native-action-root) for sources.
local fixture = ProjectRoot .. '/tests/native_queue/contributions/base-walking-profile/client/InventoryButtonChecks.lua'
local source
if NativeActionRoot then
    local file = assert(io.open(NativeActionRoot .. '/client/ISUI/ISUIElement.lua'))
    source = file:read('*a'):gsub('\r\n', '\n'); file:close()
else
    print('SKIP native ISUIElement sources: supply --game or --native-action-root; fixture model still runs')
end
local function setup(settings)
    settings = settings or {}
    local stats = {refreshes=0, ticks=0, nativeSetters=0}
    ISUIElement = {}
    function ISUIElement:getKeepOnScreen() if self.keepOnScreen ~= nil then return self.keepOnScreen end; return not self.parent end
    function ISUIElement:setX(x) self.x=x; if self.javaObject then self.javaObject:setX(x) end end
    function ISUIElement:setY(y) self.y=y; if self.javaObject then self.javaObject:setY(y) end end
    function ISUIElement:onResize() self.x,self.y=self:getX(),self:getY() end
    if source then
        for _, name in ipairs({'setX','setY','getKeepOnScreen','onResize'}) do
            local text = assert(source:match('(function ISUIElement:' .. name .. '%b().-\nend)'), name .. ' source missing')
            assert(loadstring(text))()
        end
    end
    ISButton = setmetatable({}, {__index=ISUIElement}); ISButton.__index=ISButton
    local Page = {}; Page.__index=Page; CleanUI_Clean_ISInventoryPage=Page
    local pane = {mode='details',selected={}}
    local page = setmetatable({player=0,onCharacter=false,visible=false,isCollapsed=settings.collapsed,
        inventoryPane=pane,backpacks={},buttonPool={},toolkitRefreshState={scope=0,force=settings.force}},Page)
    local panel = {children={},childrenInOrder={}}
    local nativeChildren = {}
    local controls = {size=function() return #nativeChildren end, get=function(_,index) return nativeChildren[index+1] end}
    panel.javaObject = {getControls=function() return controls end}
    page.containerButtonPanel=panel
    local item={}
    local items={item,size=function(self) return #self end,get=function(self,index) return self[index+1] end}
    local container={getItems=function() return items end,getType=function() return 'crate' end}
    page.inventory,pane.inventory=container,container
    local function button(id,x,y,active)
        local native={x=x,y=y,width=32,height=32,parent=active and panel.javaObject or nil}
        function native:getX() return self.x end
        function native:getY() return self.y end
        function native:getWidth() return self.width end
        function native:getHeight() return self.height end
        function native:getParent() return self.parent end
        function native:setX(value) self.x=value;stats.nativeSetters=stats.nativeSetters+1 end
        function native:setY(value) self.y=value;stats.nativeSetters=stats.nativeSetters+1 end
        local result=setmetatable({ID=id,x=x,y=y,width=32,height=32,inventory=container,parent=panel,javaObject=native},ISButton)
        if active then panel.children[id]=result;panel.childrenInOrder[#panel.childrenInOrder+1]=result;nativeChildren[#nativeChildren+1]=native end
        return result
    end
    local first, second, spare=button(1,0,0,true),button(2,0,32,true),button(3,0,64,false)
    page.backpacks={first,second};page.buttonPool={spare}
    if settings.foreign then second.setX=function(self,x) return ISUIElement.setX(self,x) end end
    if settings.noEligible then first.setX=false;second.setX=false;spare.setX=false end
    function Page:getIsVisible() return self.visible end
    function Page:refreshBackpacks()
        stats.refreshes=stats.refreshes+1
        if settings.failAt==stats.refreshes then error('injected callback failure') end
        -- The source-backed setters execute on the original model, in both
        -- wrapped modes. This models no discovery invalidation or UI shortcut.
        for index,value in ipairs(self.backpacks) do
            if settings.noSkip then value:setX(-1);value:setY(-1) end
            value:setX(0);value:setY((index-1)*32)
        end
        if settings.geometryAt==stats.refreshes then first.javaObject.x=17 end
        if settings.identityAt==stats.refreshes then items[1]={} end
        if settings.parentAt==stats.refreshes then first.javaObject.parent=nil end
        if settings.successorAt==stats.refreshes then first.setX=settings.successor end
    end
    getSpecificPlayer=function() return {getJoypadBind=function() return -1 end} end
    getPlayerLoot=function() return page end
    baseWalkingExperimentClockMs=function()
        stats.ticks=stats.ticks+1
        if settings.clockFailAt==stats.ticks then error('injected clock failure') end
        return stats.ticks / 4
    end
    getFilenameOfClosure=function() return settings.foreignSource
        or '/game/media/lua/client/ISUI/ISUIElement.lua' end
    ISMouseDrag={}
    return dofile(fixture),page,pane,stats,first,second,spare
end
local function absent(object,key) for name in pairs(object) do if name==key then return false end end;return true end
for _, initial in ipairs({{}, {force=false,collapsed=false}, {collapsed=true,foreign=true}}) do
    local checks,page,pane,stats,first,second,spare=setup(initial)
    local foreign=second.setX
    local receipt=checks.run(0)
    assert(receipt.totalCalls==2560 and receipt.callsPerBatch==256 and receipt.rounds==5 and #receipt.batches==10)
    assert(receipt.warmupPerMode==8 and receipt.guardedButtons==(initial.foreign and 2 or 3))
    local modes={'candidate','control','control','candidate','candidate','control','control','candidate','candidate','control'}
    for index,batch in ipairs(receipt.batches) do
        assert(batch.mode==modes[index] and batch.calls==256 and batch.elapsedMs==64)
        assert(batch.modelUnchanged and batch.geometryMatched)
        if batch.mode=='candidate' then assert(batch.skippedSetters>0 and batch.calledSetters==0)
        else assert(batch.skippedSetters==0 and batch.calledSetters>0) end
    end
    assert(stats.refreshes==2576 and stats.ticks==stats.refreshes*2)
    assert(receipt.restoreConflicts==0 and receipt.checks.restored and receipt.limits.assumesGeometryMirror)
    assert(receipt.workload.buttons==2 and receipt.workload.pooledButtons==1 and #receipt.workload.sources==3)
    assert(absent(first,'setX') and absent(first,'setY') and absent(spare,'setX') and absent(spare,'setY'))
    if initial.foreign then assert(second.setX==foreign and not absent(second,'setX')) else assert(absent(second,'setX')) end
    assert(page.toolkitRefreshState.force==initial.force and page.isCollapsed==initial.collapsed and not page.visible)
end
for _, case in ipairs({{failAt=20, message='injected callback failure'},
    {clockFailAt=20,message='injected clock failure'},
    {geometryAt=20,message='Lua/native geometry mismatch'},
    {identityAt=20,message='ordered identity changed'},
    {parentAt=20,message='identity/container/parent changed'}}) do
    local checks,page,pane,stats,first,second,spare=setup(case)
    local ok,problem=pcall(checks.run,0)
    assert(not ok and tostring(problem):find(case.message,1,true),tostring(problem))
    for _,button in ipairs({first,second,spare}) do assert(absent(button,'setX') and absent(button,'setY')) end
    assert(page.toolkitRefreshState.force==nil and page.isCollapsed==nil and not page.visible)
end
do
    local checks,page,pane,stats,first,second,spare=setup({noSkip=true})
    local ok,problem=pcall(checks.run,0)
    assert(not ok and tostring(problem):find('Candidate skipped no setters',1,true),tostring(problem))
    for _,button in ipairs({first,second,spare}) do assert(absent(button,'setX') and absent(button,'setY')) end
end
do
    local successor=function() end
    local checks,page,pane,stats,first=setup({successorAt=20,successor=successor,force=false,collapsed=false})
    local ok,problem=pcall(checks.run,0)
    assert(not ok and tostring(problem):find('successor',1,true) and first.setX==successor and absent(first,'setY'))
    assert(page.toolkitRefreshState.force==false and page.isCollapsed==false)
end
do
    local checks,page,pane,stats=setup()
    pane.selected[1]=true
    local ok,problem=pcall(checks.run,0)
    assert(not ok and tostring(problem):find('hidden idle',1,true) and stats.refreshes==0 and pane.selected[1])
end
do
    local checks,page,pane,stats,first=setup({noEligible=true})
    local ok,problem=pcall(checks.run,0)
    assert(not ok and tostring(problem):find('No eligible',1,true) and first.setX==false and stats.refreshes==0)
end
do
    local checks,page,pane,stats=setup({foreignSource='/cache/mods/foreign/media/lua/client/ISUI/ISUIElement.lua'})
    local ok,problem=pcall(checks.run,0)
    assert(not ok and tostring(problem):find('not the native source',1,true) and stats.refreshes==0)
end
print('PASS button feasibility fixture: balanced alternating modes, source setters, geometry/model guards, exact restoration and successor preservation')
