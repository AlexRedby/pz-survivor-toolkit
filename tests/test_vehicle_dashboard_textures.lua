-- Optional source-backed check:
-- PZ_REALISTIC_DASH_SOURCE=/path/to/Z_PatchVehicleDashboard.lua tools/run_tests.py ...
local sourcePath = os.getenv("PZ_REALISTIC_DASH_SOURCE")
local starts, panels, active, alpha = {}, {}, false, 0.9
require = function() end
Events = {OnGameStart = {Add = function(fn) starts[#starts + 1] = fn end}}
getActivatedMods = function() return {contains = function(_, id) return active and id == "RealisticDash" end} end
getNumActivePlayers = function() return 2 end
getPlayerVehicleDashboard = function(player) return panels[player] end
PZSurvivorToolkit = {}
YourDash = {GetWearFxAlpha = function() return alpha end}
ISVehicleDashboard = {}
ISPanel = {}
function ISPanel:new(x, y, width, height)
    return setmetatable({x=x,y=y,width=width,height=height,draws={}}, {__index=self})
end
function ISPanel:initialise() end
function ISPanel:instantiate() end
function ISPanel:drawTexture(...) self.draws[#self.draws + 1] = {...} end
function YourDash_SetMouseTransparent(panel) panel.mouseTransparent = true end

local function upstreamRender(panel)
    local dash = panel.target or panel.parent
    if not dash or panel.width <= 0 or panel.height <= 0 then return end
    local wearAlpha = (YourDash and YourDash.GetWearFxAlpha and YourDash.GetWearFxAlpha()) or 0.9
    local function draw(texture)
        if texture then
            panel:drawTexture(texture, math.floor((panel.width - texture:getWidthOrig()) * 0.5), 0, wearAlpha)
        end
    end
    if wearAlpha > 0 then draw(dash.__crackTex); draw(dash.__stainTex) end
end
function ISVehicleDashboard:_YourDashEnsureGlassOverlay()
    if self.__YourDashGlassOverlay or not self.backgroundTex then return end
    local panel = ISPanel:new(0,0,1,1)
    panel.target, panel.__YourDashGlass, panel.render = self, true, upstreamRender
    panel.mouseTransparent = true
    self.__YourDashGlassOverlay = panel
    self:addChild(panel)
end
if sourcePath then
    local file = assert(io.open(sourcePath, "rb"))
    local source = file:read("*a"); file:close()
    local first = assert(source:find("function ISVehicleDashboard:_YourDashEnsureGlassOverlay()", 1, true))
    local last = assert(source:find("function ISVehicleDashboard:_YourDashPositionGlassOverlay()", first, true))
    -- Execute the real upstream constructor/render. Other UI dependencies are
    -- irrelevant to the pending-texture contract and are not loaded here.
    assert(loadstring(source:sub(first, last - 1), "@upstream-glass-overlay"))()
else
    print("SKIP upstream Dashboard source: set PZ_REALISTIC_DASH_SOURCE; contract checks still run")
end

local function dashboard()
    local dash = setmetatable({backgroundTex={},children={}}, {__index=ISVehicleDashboard})
    function dash:addChild(panel) self.children[#self.children + 1] = panel; panel.parent = self end
    dash:_YourDashEnsureGlassOverlay()
    dash.__YourDashGlassOverlay.width, dash.__YourDashGlassOverlay.height = 745,172
    return dash
end
local function texture(width, ready)
    return {width=width,ready=ready,reads=0,checks=0,
        isReady=function(self) self.checks=self.checks+1; return self.ready end,
        getWidthOrig=function(self)
            self.reads=self.reads+1
            assert(self.ready, "synchronous pending texture size read")
            return self.width
        end}
end
local function clear(panel) panel.draws = {} end
local function sameDraws(a,b)
    assert(#a==#b, "same number of visible layers")
    for i=1,#a do
        for j=1,4 do assert(a[i][j]==b[i][j], "same texture, position and opacity") end
    end
end

-- Reproduce the source failure before installing the guard.
panels[0] = dashboard()
panels[1] = dashboard()
local pending = texture(745,false)
panels[0].__crackTex = pending
local firstOverlay = panels[0].__YourDashGlassOverlay
local originalRender = firstOverlay.render
assert(not pcall(originalRender,firstOverlay), "unguarded source must reach the blocking dimension call")

local guard = dofile(ProjectRoot.."/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleDashboardTextures.lua")
local originalEnsure = ISVehicleDashboard._YourDashEnsureGlassOverlay
assert(#starts==1 and not starts[1]())
assert(ISVehicleDashboard._YourDashEnsureGlassOverlay==originalEnsure, "inactive mod leaves vanilla alone")
active=true
assert(starts[1]())
assert(firstOverlay.render==guard.renderWear and panels[1].__YourDashGlassOverlay.render==guard.renderWear,
    "patch already-created dashboards for both local players")
local installedEnsure=ISVehicleDashboard._YourDashEnsureGlassOverlay
assert(guard.install() and ISVehicleDashboard._YourDashEnsureGlassOverlay==installedEnsure, "no nested hooks")

-- An unready layer must neither read dimensions nor suppress the other layer.
local stain=texture(746,true)
panels[0].__stainTex=stain
pending.reads=0
clear(firstOverlay);firstOverlay:render()
assert(pending.reads==0 and panels[0].__crackTex==pending, "retain/retry a pending asset without blocking")
assert(#firstOverlay.draws==1 and firstOverlay.draws[1][1]==stain, "ready stain remains visible")
assert(firstOverlay.draws[1][2]==-1, "preserve odd authored padding")
pending.ready=true
clear(firstOverlay);firstOverlay:render()
assert(#firstOverlay.draws==2 and firstOverlay.draws[1][1]==pending and firstOverlay.draws[2][1]==stain,
    "pending crack appears naturally once ready, below the stain")
stain.ready=false;stain.reads=0
clear(firstOverlay);firstOverlay:render()
assert(#firstOverlay.draws==1 and stain.reads==0, "same readiness rule for stain assets")

-- Ready assets must match the upstream draw commands, including size changes.
for _,width in ipairs({560,745,1043,1490}) do
    firstOverlay.width=width
    panels[0].__crackTex=texture(width,true)
    panels[0].__stainTex=texture(width+1,true)
    for _,value in ipairs({0,0.25,0.9,1}) do
        alpha=value
        clear(firstOverlay);originalRender(firstOverlay);local expected=firstOverlay.draws
        clear(firstOverlay);firstOverlay:render();sameDraws(expected,firstOverlay.draws)
    end
end
YourDash.GetWearFxAlpha=nil
clear(firstOverlay);originalRender(firstOverlay);local expected=firstOverlay.draws
clear(firstOverlay);firstOverlay:render();sameDraws(expected,firstOverlay.draws)
YourDash.GetWearFxAlpha=function() return alpha end

-- New/recreated overlays get the guard without changing UI ownership or input.
local fresh=dashboard()
local overlay=fresh.__YourDashGlassOverlay
assert(overlay.render==guard.renderWear and overlay.mouseTransparent and overlay.target==fresh)
local children=#fresh.children
fresh:_YourDashEnsureGlassOverlay()
assert(fresh.__YourDashGlassOverlay==overlay and #fresh.children==children)
fresh.__YourDashGlassOverlay=nil
fresh:_YourDashEnsureGlassOverlay()
assert(fresh.__YourDashGlassOverlay~=overlay and fresh.__YourDashGlassOverlay.render==guard.renderWear)
local foreign={render=function() end}
guard.bind({__YourDashGlassOverlay=foreign})
assert(foreign.render~=guard.renderWear, "do not replace unrelated UI layers")

-- Disabled/empty/invisible layers do not touch texture metadata.
pending=texture(745,false)
fresh.__crackTex=pending
overlay=fresh.__YourDashGlassOverlay
alpha=0;overlay.width=745;overlay.height=172;overlay:render()
assert(pending.checks==0 and pending.reads==0)
alpha=0.9;overlay.width=0;overlay:render();assert(pending.checks==0)
overlay.width=745;overlay.height=0;overlay:render();assert(pending.checks==0)
overlay.height=172;overlay.target=nil;overlay.parent=nil;overlay:render();assert(pending.checks==0)
overlay.parent=fresh;overlay:render();assert(pending.checks==1 and pending.reads==0, "parent fallback")
print("Dashboard readiness: pending failure reproduced, ready draw commands preserved, lifecycle checks passed"
    .. (sourcePath and " against upstream source" or ""))
