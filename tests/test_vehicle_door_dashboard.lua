-- UI contract doubles model independent native/Realistic Dashboard lifecycles.
local clientRoot = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/'
local callbacks, nextID, paused, queued = {}, 0, false, {}
PZSurvivorToolkit = {}
Events = {OnGameStart = {Add = function(fn) callbacks[#callbacks + 1] = fn end}}
ISUIHandler = {allUIVisible = true}
getGameSpeed = function() return paused and 0 or 1 end
setGameSpeed = function() end
UIManager = {getSpeedControls = function() return {getCurrentGameSpeed = getGameSpeed} end}
getText = function(key) return key end
getTexture = function(path) return {path = path, getWidth = function() return 32 end,
    getHeight = function() return 32 end, getWidthOrig = function() return 32 end,
    getHeightOrig = function() return 32 end} end
getActivatedMods = function() return {contains = function(_, id) return id == 'RealisticDash' end} end
YourDash = {GetScale = function() return 1 end}

local Element = {}
Element.__index = Element
function Element:new(x, y, width, height)
    nextID = nextID + 1
    return setmetatable({ID = nextID, x = x or 0, y = y or 0, width = width or 0,
        height = height or 0, visible = true, children = {}, childrenInOrder = {}}, self)
end
function Element:derive()
    local class = {}; class.__index = class
    return setmetatable(class, {__index = self})
end
function Element:initialise() end
function Element:instantiate() self.javaObject = self.javaObject or {} end
function Element:addChild(child)
    self.children[child.ID] = child; self.childrenInOrder[#self.childrenInOrder + 1] = child; child.parent = self
end
function Element:removeChild(child)
    self.children[child.ID] = nil
    for index, value in ipairs(self.childrenInOrder) do
        if value == child then table.remove(self.childrenInOrder, index); break end
    end
    -- Native removeChild keeps child.parent; membership is authoritative.
end
function Element:getParent() return self.parent end
function Element:getIsVisible() return self.visible end
function Element:isVisible() return self.visible end
function Element:isReallyVisible() return self.visible end
function Element:isMouseOver() return self.hovered == true end
function Element:drawRect(x, y, width, height, alpha, r, g, b)
    self.draws[#self.draws + 1] = {x = x, y = y, width = width, height = height, alpha = alpha, r = r, g = g, b = b}
end
function Element:drawRectBorder() error('door tile must not render the native square button border') end
function Element:drawTextureScaledAspect(texture, x, y, width, height, alpha, r, g, b)
    self.glyph = {texture = texture, x = x, y = y, width = width, height = height, alpha = alpha, r = r, g = g, b = b}
end
for _, field in ipairs({'X', 'Y', 'Width', 'Height', 'Visible'}) do
    Element['get' .. field] = function(self) return self[field:lower()] end
    Element['set' .. field] = function(self, value) self[field:lower()] = value end
end
for _, anchor in ipairs({'Left', 'Right', 'Top', 'Bottom'}) do
    Element['setAnchor' .. anchor] = function(self, value) self['anchor' .. anchor] = value end
end
ISButton = Element:derive()
function ISButton:new(x, y, width, height, title, target, onclick)
    local button = Element.new(self, x, y, width, height)
    button.title, button.target, button.onclick, button.enable = title, target, onclick, true
    return button
end
function ISButton:setImage(texture) self.image = texture end
function ISButton:forceImageSize(width, height) self.forcedWidthImage, self.forcedHeightImage = width, height end
function ISButton:setEnable(value) self.enable = value end
function ISButton:isEnabled() return self.enable end
function ISButton:setTooltip(value) self.tooltip = value end
function ISButton:setTextureRGBA(r, g, b, a) self.textureColor = {r = r, g = g, b = b, a = a} end
function ISButton:setBorderRGBA(r, g, b, a) self.borderColor = {r = r, g = g, b = b, a = a} end
function ISButton:setBackgroundRGBA(r, g, b, a) self.backgroundColor = {r = r, g = g, b = b, a = a} end
function ISButton:updateTooltip() self.tooltipUpdates = (self.tooltipUpdates or 0) + 1 end
function ISButton:prerender() self:drawRectBorder() end
function ISButton:onMouseDown() self.pressed = true end
function ISButton:onMouseUp()
    self.pressed = false
    if self.visible and self.enable then self.onclick(self.target, self) end
end

local function nativeLifecycle(self, name)
    self.nativeCalls[name] = (self.nativeCalls[name] or 0) + 1
    if name == 'render' and self.nextBackgroundWidth then
        self.backgroundTex:setWidth(self.nextBackgroundWidth)
        self.nextBackgroundWidth = nil
    end
    return 'native-' .. name
end
ISVehicleDashboard = Element:derive()
YourDashPassengerDashboard = ISVehicleDashboard:derive()
for _, class in ipairs({ISVehicleDashboard, YourDashPassengerDashboard}) do
    for _, name in ipairs({'createChildren', 'prerender', 'render'}) do
        class[name] = function(self) return nativeLifecycle(self, name) end
    end
end
ISVehicleMenu = {showRadialMenu = function() end}
ISTimedActionQueue = {queues = {}, add = function(action)
    queued[#queued + 1] = action
    local queue = ISTimedActionQueue.queues[action.character]
    queue.queue[#queue.queue + 1] = action
end}
ISCloseVehicleDoor = {new = function(self, character, vehicle, part)
    return {Type = 'ISCloseVehicleDoor', character = character, vehicle = vehicle, part = part}
end}
local modules = {}
require = function(name)
    if name == 'PZSurvivorToolkit/VehicleDoors' then
        if not modules[name] then modules[name] = dofile(clientRoot .. name .. '.lua') end
        return modules[name]
    end
    if name == 'YourDash/DashboardCore' then return YourDash end
end
local Doors = require 'PZSurvivorToolkit/VehicleDoors'
local Dashboard = dofile(clientRoot .. 'PZSurvivorToolkit/VehicleDoorDashboard.lua')
for _, callback in ipairs(callbacks) do callback() end
local installed = {ISVehicleDashboard.createChildren, ISVehicleDashboard.prerender, ISVehicleDashboard.render,
    YourDashPassengerDashboard.createChildren, YourDashPassengerDashboard.prerender, YourDashPassengerDashboard.render}
for _, callback in ipairs(callbacks) do callback() end
assert(installed[1] == ISVehicleDashboard.createChildren and installed[2] == ISVehicleDashboard.prerender
    and installed[3] == ISVehicleDashboard.render and installed[4] == YourDashPassengerDashboard.createChildren
    and installed[5] == YourDashPassengerDashboard.prerender and installed[6] == YourDashPassengerDashboard.render,
    'repeated game starts must not stack dashboard hooks')

local function fixture(class, realistic)
    local door = {open = true, isOpen = function(self) return self.open end}
    local part = {door = door, item = {}, getDoor = function(self) return self.door end,
        getInventoryItem = function(self) return self.item end}
    local vehicle = {seat = 0, part = part, getSeat = function(self) return self.seat end,
        getPassengerDoor = function(self, seat) if seat == self.seat then return self.part end end}
    local character = {vehicle = vehicle, getVehicle = function(self) return self.vehicle end,
        isDead = function(self) return self.dead == true end}
    ISTimedActionQueue.queues[character] = {queue = {}}
    local dash = Element.new(class, 150, 300, 600, 140)
    dash.vehicle, dash.character, dash.nativeCalls = vehicle, character, {}
    dash.backgroundTex = Element:new(0, 0, 600, 140)
    if realistic then
        local seat, sleep = Element:new(602, 71, 33, 33), Element:new(602, 106, 33, 33)
        if class == YourDashPassengerDashboard then dash.paxMoveSeatBtn, dash.paxSleepBtn = seat, sleep
        else dash.__YourDashMoveSeatButton, dash.__YourDashSleepButton = seat, sleep end
    end
    return dash, character, vehicle, part, door
end

assert(PZSurvivorToolkit.VehicleDoorDashboard == Dashboard)
local function frame(dash)
    dash:prerender(); dash:render()
    return assert(dash.pzstCloseDoorButton)
end
local function buttonChildren(dash)
    local count = 0
    for _, child in pairs(dash.children) do if getmetatable(child) == Dashboard.Button then count = count + 1 end end
    return count
end
local function overlap(a, b)
    return a:getX() < b:getX() + b:getWidth() and b:getX() < a:getX() + a:getWidth()
        and a:getY() < b:getY() + b:getHeight() and b:getY() < a:getY() + a:getHeight()
end
local function near(a, b) return math.abs(a - b) < 0.0001 end
local function draw(button)
    button.draws, button.glyph = {}, nil
    button:prerender()
    assert(#button.draws == 0 and button.tooltipUpdates > 0,
        'tile prerender must retain native tooltip updates without a rectangular button background')
    button:render()
    assert(#button.draws > 1 and button.glyph, 'tile needs a rounded fill and native door glyph')
    return button.draws, button.glyph
end
local function covers(rect, x, y)
    return rect.x <= x and x < rect.x + rect.width and rect.y <= y and y < rect.y + rect.height
end
assert(Dashboard.Button.onMouseDown == ISButton.onMouseDown and Dashboard.Button.onMouseUp == ISButton.onMouseUp,
    'visual subclass must retain native button input handling')
for _, spec in ipairs({{ISVehicleDashboard, false}, {ISVehicleDashboard, true}, {YourDashPassengerDashboard, true}}) do
    local dash, character, vehicle, part, door = fixture(unpack(spec))
    dash:createChildren()
    local button = frame(dash)
    assert(dash.nativeCalls.createChildren == 1 and dash.nativeCalls.prerender == 1 and dash.nativeCalls.render == 1,
        'driver and independent passenger lifecycles must retain their native callbacks')
    assert(button.target == dash and button.onclick == Dashboard.click and button.enable and button.visible)
    assert(button.tooltip == 'ContextMenu_Close_door' and button.image.path == 'media/ui/vehicles/door.png',
        'dashboard must use the native door pictogram and translated action label')
    assert(button.fillColor.r > button.fillColor.g and button.fillColor.g > button.fillColor.b,
        'open door has an ochre filled action state')
    local side = dash.__YourDashMoveSeatButton or dash.paxMoveSeatBtn
    local sleep = dash.__YourDashSleepButton or dash.paxSleepBtn
    if side then
        assert(button.width == 33 and button.height == 33 and button.width == side.width and button.height == side.height,
            'RD door tile must exactly match neighboring shortcut dimensions')
        local rectangles, glyph = draw(button)
        local centerCovered = false
        for _, rect in ipairs(rectangles) do
            assert(rect.x >= 1 and rect.y >= 1 and rect.x + rect.width <= 32 and rect.y + rect.height <= 32,
                '33px RD tile keeps the same 1px transparent margin on every side')
            assert(not covers(rect, 1.5, 1.5) and not covers(rect, 31.5, 1.5)
                and not covers(rect, 1.5, 31.5) and not covers(rect, 31.5, 31.5),
                'rounded tile corners must remain transparent')
            centerCovered = centerCovered or covers(rect, 16.5, 16.5)
            assert(near(rect.alpha, 0.15), 'idle fill matches RD base alpha 0.30 times global opacity 0.5')
        end
        assert(centerCovered, 'tile has a filled center instead of an outline')
        assert(glyph.texture == button.image and glyph.r < 0.15 and glyph.g < 0.15 and glyph.b < 0.15,
            'existing vanilla door texture is rendered as a dark glyph')
        assert(glyph.x > 5 and glyph.y > 5 and glyph.x + glyph.width < 28 and glyph.y + glyph.height < 28
            and near(glyph.width / 31, 0.65) and near(glyph.height / 31, 0.65),
            'door pictogram is centered with the same generous inset as neighboring tiles')
        button.hovered = true
        rectangles = draw(button)
        for _, rect in ipairs(rectangles) do assert(near(rect.alpha, 0.30), 'hover doubles tile opacity like RD') end
        button.hovered, button.joypadFocused = false, true
        rectangles = draw(button)
        for _, rect in ipairs(rectangles) do assert(near(rect.alpha, 0.30), 'joypad focus has the same visible feedback') end
        button.joypadFocused = false
        button:onMouseDown()
        rectangles = draw(button)
        for _, rect in ipairs(rectangles) do
            assert(rect.x > 1 and rect.y > 1 and rect.x + rect.width < 32 and rect.y + rect.height < 32,
                'pressed tile shrinks inside its original hit bounds without shifting neighbors')
        end
        button.pressed = false
    end
    assert(not overlap(button, dash.backgroundTex) and (not side or not overlap(button, side))
        and (not sleep or not overlap(button, sleep)), 'control must not cover native panel or existing shortcuts')
    local width, x, y = dash.width, button.x, button.y
    for _ = 1, 4 do frame(dash) end
    assert(buttonChildren(dash) == 1 and dash.width == width and button.x == x and button.y == y,
        'repeated frame/layout updates must reuse one control without geometry drift')
    assert(button.x + button.width <= dash.width and button.y >= dash.backgroundTex.y,
        'the child hit area must remain within the expanded dashboard bounds')

    door.open = false
    frame(dash)
    assert(button.visible and not button.enable, 'closed installed door keeps a grey, disabled control')
    assert(button.fillColor.r < 0.6 and button.fillColor.g < 0.6 and button.fillColor.b < 0.6)
    local disabledRects = draw(button)
    for _, rect in ipairs(disabledRects) do
        assert(near(rect.alpha, 0.105), 'disabled tile dims the same fill without changing its dimensions')
    end
    local before = #queued
    Dashboard.click(dash); assert(#queued == before, 'programmatic click cannot close an already closed door')
    door.open, paused = true, true
    frame(dash); assert(button.visible and not button.enable)
    Dashboard.click(dash); assert(#queued == before, 'pause prevents callback queueing')
    paused = false
    frame(dash); assert(button.enable)
    button:onMouseDown(); button:onMouseUp()
    local action = queued[#queued]
    assert(#queued == before + 1 and action.character == character and action.vehicle == vehicle and action.part == part,
        'button queues the same native close action for its current occupied door')
    assert(door.open, 'button must not directly change authoritative door state')
    frame(dash); assert(button.visible and not button.enable, 'pending native close disables repeated clicks')
    Dashboard.click(dash); assert(#queued == before + 1, 'disabled pending close remains deduplicated')
    ISTimedActionQueue.queues[character].queue = {}

    local function hidden(change, restore)
        change(); frame(dash); assert(not button.visible and not button.enable)
        local count = #queued; Dashboard.click(dash); assert(#queued == count)
        restore(); frame(dash); assert(button.visible and button.enable)
    end
    hidden(function() part.item = nil end, function() part.item = {} end)
    hidden(function() part.door = nil end, function() part.door = door end)
    hidden(function() character.vehicle = {} end, function() character.vehicle = vehicle end)
    hidden(function() character.dead = true end, function() character.dead = false end)
    hidden(function() vehicle.seat = -1 end, function() vehicle.seat = 0 end)
    if spec[1] == YourDashPassengerDashboard then
        hidden(function() dash.__paxRetracted = true end, function() dash.__paxRetracted = false end)
    end

    -- A click after a seat/door replacement uses the live installed part.
    local replacement = {getDoor = function() return door end, getInventoryItem = function() return {} end}
    vehicle.part = replacement
    Dashboard.click(dash)
    assert(queued[#queued].part == replacement, 'dashboard callback must resolve current door instead of caching its part')
    ISTimedActionQueue.queues[character].queue = {}; vehicle.part = part

    local tooltip = {visible = true, setVisible = function(self, value) self.visible = value end,
        removeFromUIManager = function(self) self.removed = true end}
    button.tooltipUI = tooltip
    dash:removeChild(button)
    assert(button.parent == dash, 'model native stale parent pointer after clear/remove')
    local recreated = frame(dash)
    assert(recreated ~= button and buttonChildren(dash) == 1 and not tooltip.visible and tooltip.removed,
        'removed children recreate exactly one control and release their tooltip owner')
    dash:createChildren(); frame(dash)
    assert(buttonChildren(dash) == 1, 'native child recreation must not accumulate controls')

    if side then
        -- Compact skin has no row above shortcuts; use an adjacent column.
        side:setY(0); side:setWidth(24); side:setHeight(18)
        frame(dash)
        assert(recreated.width == 24 and recreated.height == 18 and recreated.x >= side.x + side.width
            and not overlap(recreated, side), 'compact Realistic Dashboard needs a nonoverlapping second column')
        side:setVisible(false)
    end
    -- Model another renderer moving/resizing the background during its own render.
    dash.nextBackgroundWidth = 720
    frame(dash)
    assert(recreated.x >= 720 and dash.width >= recreated.x + recreated.width,
        'placement must follow native render geometry and expand the final mouse hit bounds')
end
print('Vehicle door dashboard contracts passed: native/passenger hooks, control lifecycle, state, current target, compact layout and resizing.')
