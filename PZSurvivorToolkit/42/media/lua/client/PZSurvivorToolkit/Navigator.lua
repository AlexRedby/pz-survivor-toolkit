require "PZSurvivorToolkit/Settings"
if not getActivatedMods():contains("Navigator") then return end

local Toolkit = PZSurvivorToolkit
local Config = require "NavigatorRadio/MonitorConfig"
local Render = require "NavigatorRadio/MonitorRender"
local Map = require "NavigatorRadio/MonitorMap"
local Context = require "NavigatorRadio/MonitorMapContext"
local State = require "NavigatorRadio/MonitorState"
local Radio = require "NavigatorRadio/RadioMatch"
local Drag = require "NavigatorRadio/NavigatorMonitorDrag"
local YourDash = getActivatedMods():contains("RealisticDash") and require "YourDash/DashboardCore" or nil
local Navigator = {}
Toolkit.Navigator = Navigator

-- Upstream shares geometry constants; scope changes to one call, including on failure.
local function configured(values, fn, ...)
    local saved = {}
    for key, value in pairs(values) do saved[key], Config[key] = Config[key], value end
    local ok, result = pcall(fn, ...)
    for key, value in pairs(saved) do Config[key] = value end
    if not ok then error(result) end
    return result
end

function Navigator.layout(dash)
    local bg = dash.backgroundTex
    local profile = YourDash and YourDash.GetVehicleProfile(dash.vehicle)
    local scale = YourDash and YourDash.GetScale() or 1
    local width = math.floor(math.max(280, 300 * math.min(scale, 1.4)) + 0.5)
    local ratio = width / Config.MONITOR_SCREEN_TEXTURE:getWidth()
    local verticalRatio = math.max(150 / 161, ratio * 0.92)
    local height = math.floor(Config.MONITOR_SCREEN_TEXTURE:getHeight() * verticalRatio + 0.5)
    local baseWidth = math.floor(Config.MONITOR_BASE_TEXTURE:getWidth() * ratio + 0.5)
    local gap = math.floor(Config.MONITOR_SCREEN_GAP * verticalRatio + 0.5)
    local faceHeight = math.max(22, math.floor(22 * ratio + 0.5))
    local baseHeight = Config.MONITOR_BASE_TEXTURE:getHeight() * faceHeight / 22
    local center = bg:getWidth() / 2
    local color = {1, 1, 1}
    if profile then
        center = ({standard = 326, heavy = 300, sport = 314})[profile.family] * scale
        if profile.family == "heavy" then color = {0.8, 0.8, 0.8} end
        if profile.accentColor == "red" then color = {1, 0.4, 0.45}
        elseif profile.accentColor == "wood" then color = {1, 0.65, 0.4} end
    end
    local powerX = baseWidth - math.floor(24 * ratio + 0.5) - Config.MONITOR_POWER_BUTTON_SIZE
    return {x = math.floor(bg:getX() + center - baseWidth / 2),
        y = bg:getY() - faceHeight,
        width = width, height = height, baseWidth = baseWidth, baseHeight = baseHeight,
        screenX = math.floor((baseWidth - width) / 2), gap = gap,
        faceHeight = faceHeight, footHeight = math.ceil(30 * scale), color = color,
        controls = {MONITOR_POWER_BUTTON_X = powerX, MONITOR_POWER_BUTTON_Y = math.max(0, math.floor((22 * ratio - 22) / 2)),
            MONITOR_TURN_PANEL_X = math.floor(24 * ratio + 0.5),
            MONITOR_TURN_PANEL_Y = math.max(1, math.floor((22 * ratio - 19) / 2)),
            MONITOR_TURN_PANEL_MAX_WIDTH = powerX - math.floor(24 * ratio + 0.5) - 6},
        map = {MAP_WIDTH = math.floor(258 * ratio + 0.5), MAP_HEIGHT = math.floor(161 * verticalRatio + 0.5),
            MAP_OFFSET_Y = math.floor(2 * verticalRatio + 0.5)}}
end

local originalDraw = Render.draw
function Render.draw(dash)
    if not Toolkit.Settings.navigatorDashboard() or not dash or not dash.backgroundTex then
        if dash then dash._toolkitNavigatorLayout = nil end
        return originalDraw(dash)
    end
    if not Render.ensureTextures() then
        dash._toolkitNavigatorLayout = nil
        Render.hideDragPanel(dash); Map.hide(dash); return
    end
    if not dash.vehicle or not ISUIHandler.allUIVisible then
        Render.hideDragPanel(dash); Map.hide(dash); return
    end
    if not Radio.vehicleHasNavigatorRadio(dash) then
        if State.isDashboardEnabledFor(dash) then State.setDashboardOpen(false, dash, nil) end
        dash._navMonitorProgress = 0
        Render.hideDragPanel(dash); Map.hide(dash); return
    end
    Render.updateProgress(dash, Render.shouldOpen(dash))
    local layout = Navigator.layout(dash)
    dash._toolkitNavigatorLayout = layout
    local bg = dash.backgroundTex
    if not bg._toolkitNavigatorMount then
        bg._toolkitNavigatorMount = true
        local originalPrerender = bg.prerender
        function bg:prerender()
            local l = dash._toolkitNavigatorLayout
            if l and Toolkit.Settings.navigatorDashboard() and dash.vehicle
                    and ISUIHandler.allUIVisible and Radio.vehicleHasNavigatorRadio(dash) then
                local r, g, b = unpack(l.color)
                local x = l.x - self:getX() + (dash._navMonitorOffsetX or 0)
                local y = l.y - self:getY() + l.faceHeight + (dash._navMonitorOffsetY or 0)
                -- Stretch only the original lower rail; native artwork masks it to the curved seat.
                local ratio = l.footHeight / (Config.MONITOR_BASE_TEXTURE:getHeight() - 22)
                self:setStencilRect(x, y, l.baseWidth, l.footHeight)
                self:drawTextureScaled(Config.MONITOR_BASE_TEXTURE, x, y - 22 * ratio,
                    l.baseWidth, Config.MONITOR_BASE_TEXTURE:getHeight() * ratio, 1, r, g, b)
                self:clearStencilRect()
            end
            return originalPrerender(self)
        end
    end
    local x = layout.x + (dash._navMonitorOffsetX or 0)
    local y = layout.y + (dash._navMonitorOffsetY or 0)
    local progress = dash._navMonitorProgress or 0
    local screenX = x + layout.screenX
    local top = y - layout.height + layout.gap
    local slideY = math.floor(top + (1 - progress) * (layout.height - layout.gap) + 0.5)
    local r, g, b = unpack(layout.color)
    dash:setStencilRect(screenX, top, layout.width, layout.height)
    dash:drawTextureScaled(Config.MONITOR_SCREEN_TEXTURE, screenX, slideY,
        layout.width, layout.height, 1, r, g, b)
    dash:clearStencilRect()
    dash:setStencilRect(x, y, layout.baseWidth, layout.faceHeight)
    dash:drawTextureScaled(Config.MONITOR_BASE_TEXTURE, x, y,
        layout.baseWidth, layout.baseHeight, 1, r, g, b)
    dash:clearStencilRect()
    if Context.isWorldMapVisible() then Render.hideDragPanel(dash)
    else Render.ensureDragPanel(dash, layout.x, layout.y, layout.baseWidth, layout.faceHeight) end
    configured(layout.map, Map.update, dash, screenX, top, layout.width, layout.height, progress)
end

local originalRender = Drag.render
function Drag:render()
    local layout = self.dashboard and self.dashboard._toolkitNavigatorLayout
    if layout and Toolkit.Settings.navigatorDashboard() then
        return configured(layout.controls, originalRender, self)
    end
    return originalRender(self)
end
for _, name in ipairs({"onMouseDown", "onMouseUp"}) do
    local original = Drag[name]
    Drag[name] = function(self, x, y)
        local layout = self.dashboard and self.dashboard._toolkitNavigatorLayout
        if layout and Toolkit.Settings.navigatorDashboard() then
            return configured(layout.controls, original, self, x, y)
        end
        return original(self, x, y)
    end
end
