require = function() end
PZSurvivorToolkit = {}
local style = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/UIStyle.lua")
require = function(name) if name == "PZSurvivorToolkit/UIStyle" then return style end end
assert(PZSurvivorToolkit.UIStyle == style)
local fields = {"backgroundColor", "backgroundColorMouseOver", "borderColor", "textColor"}
local function sameStyle(button, reference)
    for _, field in ipairs(fields) do
        for _, channel in ipairs({"r", "g", "b", "a"}) do
            assert(button[field][channel] == reference[field][channel], field .. "." .. channel)
        end
    end
end
local function callback() end
local before = {x = 11, y = 13, width = 150, height = 28, title = "A long translated label",
    target = {}, onclick = callback, onClickArgs = {7}, enable = false, tooltip = "Details",
    prerender = callback, render = callback, font = 1, image = {}, sounds = {activate = "Click"}}
local button = {}
for key, value in pairs(before) do button[key] = value end
assert(style.button(button) == button)
local reference = style.button({})
style.button(button)
sameStyle(button, reference)
for key, value in pairs(before) do assert(button[key] == value, "changed " .. key) end
button.backgroundColor.r = 0
assert(reference.backgroundColor.r ~= 0, "native enabled/disabled changes must stay local to each button")

UIFont = {Small = 1}
getTextManager = function() return {getFontHeight = function() return 12 end} end
getText = function(key) return key end
getCore = function() return {getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end} end
local methods = {}
for _, name in ipairs({"initialise", "instantiate", "addToUIManager", "bringToTop", "setResizable", "setWantKeyEvents", "setOnMouseDownFunction"}) do
    methods[name] = function() end
end
function methods:setTitle(value) self.title = value end
function methods:setVisible(value) self.visible = value end
function methods:setEnable(value) self.enable = value end
function methods:addChild(child) self.children = self.children or {}; self.children[#self.children + 1] = child end
function methods:titleBarHeight() return 20 end
function methods:getBottom() return self.y + self.height end
local function control(x, y, width, height)
    return setmetatable({x = x, y = y, width = width, height = height, items = {}, prerender = function() end}, {__index = methods})
end
ISCollapsableWindow = {initialise = function() end, new = function(class, x, y, width, height)
    local window = control(x, y, width, height)
    return setmetatable(window, {__index = class})
end}
function ISCollapsableWindow:derive() return setmetatable({}, {__index = function(_, key) return self[key] or methods[key] end}) end
ISComboBox, ISScrollingListBox = {new = function(_, ...) return control(...) end}, {new = function(_, ...) return control(...) end}
local created = {}
ISButton = {new = function(_, x, y, width, height, title, target, onclick)
    local b = control(x, y, width, height)
    b.title, b.target, b.onclick = title, target, onclick
    b.original = {x = x, y = y, width = width, height = height, title = title, target = target, onclick = onclick}
    created[#created + 1] = b
    return b
end}
local function verifyCreated()
    assert(#created > 0)
    for _, b in ipairs(created) do
        sameStyle(b, reference)
        for key, value in pairs(b.original) do assert(b[key] == value, "factory changed " .. key) end
    end
end
Events = {OnMainMenuEnter = {Add = function() end}, OnGameStart = {Add = function() end}}
for _, withToolkit in ipairs({false, true}) do
    created = {}
    local applications = 0
    PZSurvivorToolkit = withToolkit and {UIStyle = {button = function(b) applications = applications + 1; return style.button(b) end}} or nil
    PZSurvivorWishlist = {Client = {sync = function() end, selected = function() end}, Settings = {craftingEnabled = function() return true end}}
    local UI = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorWishlist/UI.lua")
    local window = UI.open(0)
    assert(#created == 5 and window.shareButton.target == window)
    verifyCreated()
    assert(applications == (withToolkit and 5 or 0), "optional toolkit helper was not used")
    created, applications = {}, 0
    ISCraftRecipePanel = {createDynamicChildren = function(panel)
        panel.rootTable = {addRow = function() return {index = function() return 0 end, setVisible = function() end} end,
            setElement = function() end}
    end, prerender = function() end}
    ISBuildRecipePanel = {}
    ISWidgetInput = {}
    local crafting = dofile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorWishlist/Crafting.lua")
    crafting.install()
    local panel = {player = {}, logic = {getRecipe = function() return {} end}}
    ISCraftRecipePanel.createDynamicChildren(panel)
    assert(panel.pzswButton.target == panel and panel.pzswButton.onclick == crafting.openMenu)
    verifyCreated()
    assert(applications == (withToolkit and 1 or 0))
end
print("UI style checks passed: idempotence, independent colors, unchanged geometry/callbacks and standalone wishlist factories.")
