-- Geometry and input checks run against the downloaded Navigator render/drag source.
local client = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/'
local active, enabled, realistic = false, true, true
local callbacks, modules, mapCalls, requires = {}, {}, {}, {}
local worldMap = false
Events = {OnGameStart = {Add = function(fn) callbacks[#callbacks + 1] = fn end}}
getActivatedMods = function() return {contains = function(_, id)
    return active and (id == 'Navigator' or realistic and id == 'RealisticDash')
end} end
PZSurvivorToolkit = {Settings = {navigatorDashboard = function() return enabled end}}
require = function(name)
    requires[#requires + 1] = name
    if name == 'PZSurvivorToolkit/Settings' or name == 'ISUI/ISPanel' then return end
    return assert(modules[name], name)
end
dofile(client .. 'PZSurvivorToolkit/Navigator.lua')
assert(not PZSurvivorToolkit.Navigator and #requires == 1, 'Absent Navigator must have no dependency/hook')
if not NativeNavigatorConfig then
    print('PASS navigator: absent dependency guard; upstream geometry checks require --navigator-source')
    return
end
active = true
getTexture = function(path) return {getWidth = function() return path:find('base') and 330 or 294 end,
    getHeight = function() return path:find('base') and 31 or 208 end} end
local Config = assert(loadstring(NativeNavigatorConfig))()
modules['NavigatorRadio/MonitorConfig'] = Config
local State = {isDashboardEnabledFor = function(dash) return dash.enabled end,
    setDashboardOpen = function(open, dash) dash.enabled = open end,
    toggleDashboard = function(dash) dash.enabled = not dash.enabled end}
modules['NavigatorRadio/MonitorState'] = State
modules['NavigatorRadio/RadioMatch'] = {vehicleHasNavigatorRadio = function(dash) return dash.radio end,
    isNavigatorPart = function(part) return part ~= nil end}
local Map = {hide = function(dash) dash.hidden = true end,
    update = function(dash, x, y, w, h, progress)
        assert(not dash.failMap, 'map failure')
        mapCalls[#mapCalls + 1] = {x=x,y=y,w=w,h=h,mapWidth=Config.MAP_WIDTH,mapHeight=Config.MAP_HEIGHT,progress=progress}
    end}
modules['NavigatorRadio/MonitorMap'] = Map
modules['NavigatorRadio/MonitorMapContext'] = {isWorldMapVisible = function() return worldMap end}
modules['NavigatorRadio/MonitorTurnPanel'] = {Draw = function(panel)
    panel.powerDrawX = Config.MONITOR_POWER_BUTTON_X
    assert(Config.MONITOR_TURN_PANEL_MAX_WIDTH <= panel.width - 28)
end}
modules['NavigatorRadio/MonitorRouteDataStatusPanel'] = {Draw = function() return false end}
local profile, scale = {family='standard',accentColor='black'}, 1
modules['YourDash/DashboardCore'] = {GetVehicleProfile = function() return profile end,GetScale = function() return scale end}
getPerformance = function() return {getUIRenderFPS = function() return 30 end} end
ISUIHandler = {allUIVisible=true}
getSoundManager = function() return {playUISound = function() end} end
ISPanel = {}
function ISPanel:derive() local t={};t.__index=t;return setmetatable(t,{__index=self}) end
function ISPanel:new(x,y,w,h) return setmetatable({x=x,y=y,width=w,height=h},{__index=self}) end
for _, name in ipairs({'initialise','instantiate','addToUIManager','setAlwaysOnTop','setRenderThisPlayerOnly','render','drawRect','drawRectBorder','drawTexture','drawTextureScaled','setStencilRect','clearStencilRect','prerender'}) do ISPanel[name]=function() end end
for _, field in ipairs({'X','Y','Width','Height','Visible'}) do
    ISPanel['set'..field]=function(self,value) self[string.lower(field)]=value end
    ISPanel['get'..field]=function(self) return self[string.lower(field)] end
end
function ISPanel:getAbsoluteX() return self.x end
function ISPanel:getAbsoluteY() return self.y end
function ISPanel:isVisible() return self.visible end
ISPanel.onMouseDown=function(self) self.moving=true;return 'drag' end
ISPanel.onMouseUp=function(self) self.moving=false end
local Drag=assert(loadstring(NativeNavigatorDrag))()
modules['NavigatorRadio/NavigatorMonitorDrag']=Drag
local Render=assert(loadstring(NativeNavigatorRender))()
modules['NavigatorRadio/MonitorRender']=Render
local nativeDraw=Render.draw
local drawn={}
function ISPanel:drawTextureScaled(texture,x,y,w,h,alpha,r,g,b)
    drawn[#drawn+1]={texture=texture,x=x,y=y,w=w,h=h,r=r,g=g,b=b,stencil=self._stencil}
end
function ISPanel:setStencilRect(x,y,w,h)
    self._stencil={x=x,y=y,w=w,h=h}
end
function ISPanel:clearStencilRect()
    self._stencil=nil
end
local dash=ISPanel:new(80,700,780,172)
dash.vehicle={getPartById=function() return {} end};dash.radio=true;dash.playerNum=0
dash.backgroundTex=ISPanel:new(17,0,745,172)
dofile(client..'PZSurvivorToolkit/Navigator.lua')
local nav=PZSurvivorToolkit.Navigator
for _, family in ipairs({'standard','heavy','sport'}) do
    for _, accent in ipairs({'black','red','wood'}) do
        profile={family=family,accentColor=accent}
        for _, s in ipairs({0.75,1,1.4,2}) do
            scale=s
            Render.draw(dash)
            local layout=dash._toolkitNavigatorLayout
            local call=mapCalls[#mapCalls]
            local screen,base=drawn[#drawn-1],drawn[#drawn]
            assert(screen.texture==Config.MONITOR_SCREEN_TEXTURE and base.texture==Config.MONITOR_BASE_TEXTURE)
            assert(screen.w==layout.width and screen.h==layout.height and base.w==layout.baseWidth and base.h==layout.baseHeight)
            assert(base.stencil and base.stencil.h==layout.faceHeight)
            assert(math.abs(layout.faceHeight * 31 / base.h - 22)<0.00001, "Face and lower rail must meet at the same source row")
            assert(screen.stencil and screen.stencil.h==layout.height and not dash._stencil)
            assert(screen.r==layout.color[1] and screen.g==layout.color[2] and screen.b==layout.color[3])
            assert(layout.map.MAP_WIDTH<layout.width and layout.map.MAP_HEIGHT<layout.height)
            assert(layout.map.MAP_HEIGHT>=150 and layout.height < math.floor(208 * layout.width / 294 + 0.5))
            assert(layout.y+layout.faceHeight==dash.backgroundTex.y)
            assert(layout.controls.MONITOR_POWER_BUTTON_Y+22<=layout.faceHeight)
            assert(layout.controls.MONITOR_TURN_PANEL_Y+19<=layout.faceHeight)
            assert(call.mapWidth==layout.map.MAP_WIDTH and call.mapHeight==layout.map.MAP_HEIGHT)
            assert(Config.MAP_WIDTH==258 and Config.MAP_HEIGHT==161, 'Shared config leaked')
            assert(dash._navMonitorDragPanel.width==layout.baseWidth and dash._navMonitorDragPanel.height==layout.faceHeight)
            local drag=dash._navMonitorDragPanel
            drag:render();assert(drag.powerDrawX==layout.controls.MONITOR_POWER_BUTTON_X)
            local x,y=layout.controls.MONITOR_POWER_BUTTON_X+2,layout.controls.MONITOR_POWER_BUTTON_Y+2
            dash.enabled=false
            assert(drag:onMouseDown(x,y)==true);drag:onMouseUp(x,y);assert(dash.enabled)
            assert(Config.MONITOR_POWER_BUTTON_X==284 and Config.MONITOR_TURN_PANEL_X==24)
            drag:onMouseDown(2,4);assert(drag.moving and not drag._powerButtonPressed)
            drag:setX(drag.defaultX+13);drag:setY(drag.defaultY-7);drag:updateOffsets()
            Render.draw(dash);call=mapCalls[#mapCalls]
            assert(call.x==layout.x+13+layout.screenX and call.y==layout.y-7-layout.height+layout.gap)
            dash._navMonitorOffsetX=0;dash._navMonitorOffsetY=0
        end
    end
end
print('PASS navigator: 36 theme/scale combinations, map/frame geometry, power hitboxes and drag offsets')
local textureLoader=getTexture
for _,field in ipairs({'MONITOR_BASE_TEXTURE','MONITOR_SCREEN_TEXTURE'}) do
    local texture=Config[field];Config[field]=nil;getTexture=function() return nil end
    Render.draw(dash)
    assert(dash._toolkitNavigatorLayout==nil and dash.hidden and not dash._navMonitorDragPanel.visible)
    dash.backgroundTex:prerender()
    getTexture=textureLoader;Render.draw(dash)
    assert(Config[field] and dash._toolkitNavigatorLayout and dash._navMonitorDragPanel.visible)
    Config[field]=texture
end
print('PASS navigator: unavailable screen/base textures hide safely and retry native loading')
dash.failMap=true
assert(not pcall(Render.draw,dash))
assert(Config.MAP_WIDTH==258 and Config.MAP_HEIGHT==161, 'Error must restore shared config')
dash.failMap=false;enabled=false
Render.draw(dash);assert(dash._toolkitNavigatorLayout==nil)
assert(mapCalls[#mapCalls].mapWidth==258 and dash._navMonitorDragPanel.width==330)
assert(Render.draw~=nativeDraw)
enabled=true;dash.radio=false;dash.enabled=true
Render.draw(dash);assert(dash._navMonitorProgress==0 and dash.hidden and not dash.enabled)
ISUIHandler.allUIVisible=false;dash.radio=true
Render.draw(dash);assert(not dash._navMonitorDragPanel.visible)
enabled=true;ISUIHandler.allUIVisible=true
Render.draw(dash)
local bg=dash.backgroundTex
local drawOrder={}
bg.drawTextureScaled=function(self,texture,x,y,w,h)
    local l=dash._toolkitNavigatorLayout
    assert(texture==Config.MONITOR_BASE_TEXTURE and self._stencil)
    assert(self._stencil.w==l.baseWidth and self._stencil.h==l.footHeight)
    assert(math.abs((self._stencil.y-y)*31/h-22)<0.00001, 'Mount must use only the lower rail, never repeat the control face')
    drawOrder[#drawOrder+1]='apron'
end
-- The installed wrapper captured the original draw method before replacement.
bg:prerender();assert(drawOrder[1]=='apron' and not bg._stencil)
local l=dash._toolkitNavigatorLayout
assert(l.footHeight>=l.baseHeight-22)
worldMap=true;Render.draw(dash)
assert(not dash._navMonitorDragPanel.visible)
bg:prerender();assert(#drawOrder==2, 'World map must not reopen the dock gap')
enabled=false;bg:prerender();assert(#drawOrder==2, 'Disable must stop apron rendering')
print('PASS navigator: one clipped lower rail preserves curved docking and world-map fill; disable removes it')
print('PASS navigator: live original rollback, missing radio, hidden UI and config restoration on failure')
