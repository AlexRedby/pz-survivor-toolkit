if not NativeActionRoot then
    print('Animal info checks skipped (pass --native-action-root media/lua).')
    return
end

require = function() end
local function noop() end
local function derive(self, name)
    local class = {Type = name, derive = derive}
    class.__index = class
    return setmetatable(class, {__index = self})
end
local base = {derive = derive, prerender = noop, render = noop}
function base:new() return setmetatable({}, self) end
ISCollapsableWindowJoypad, ISUI3DModel = base, base
ISPanel, ISPanelJoypad = base, base
UIFont = {Small = 1, Medium = 2, Large = 3}
getTextManager = function() return {getFontHeight = function() return 14 end,
    MeasureStringX = function() return 20 end} end
getText = function(key) return key end
getTexture = noop
getJoypadData = noop
AnimalContextMenu = {cheat = false, onAnimalInfo = noop}
assert(loadfile(NativeActionRoot .. '/client/ISUI/Animal/ISAnimalUI.lua'))()
assert(loadfile(NativeActionRoot .. '/client/ISUI/Hutch/ISHutchUI.lua'))()

local distance, health, occupant, nestAnimal, position = 1, 0, nil, nil, 0
local square = {DistToProper = function() return distance end}
local hutch = {getSquare = function() return square end,
    getAnimal = function(_, index) return index == 0 and occupant or nil end,
    getMaxNestBox = function() return 3 end,
    getAnimalInNestBox = function(_, index) return index == 3 and nestAnimal or nil end}
local data = {getSize = function() return 1 end, getHutchPosition = function() return position end,
    getBreed = function() return {getName = function() return 'rhodeisland' end} end,
    getClutchSize = function() return 0 end, haveLayingEggPeriod = function() return false end}
local animal = {getHealth = function() return health end,
    getHutch = function(self) return self.hutch end, hutch = hutch,
    getData = function() return data end,
    isExistInTheWorld = function() return false end,
    getVehicle = noop, isHeld = function() return false end,
    getAnimalType = function() return 'hen' end, isFemale = function() return true end,
    getAgeText = function() return '1 year' end, getHealthText = function() return 'Dead' end,
    getAppearanceText = function() return 'Normal' end, getStressTxt = function() return 'Low' end,
    attackOtherMales = function() return false end, getDZone = noop, getBabies = noop,
    isBaby = function() return false end, canBeMilked = function() return false end,
    canBeSheared = function() return false end, shouldAnimalStressAboveGround = function() return false end,
    needHutch = function() return true end}
occupant = animal
local function button(enabled)
    return {enable = enabled, setEnable = function(self, value) self.enable = value end,
        setX = noop, setY = noop, setVisible = function(self, value) self.visible = value end,
        isVisible = function(self) return self.visible end, getRight = function() return 20 end}
end
local function window()
    return setmetatable({animal = animal, chr = {}, skillLvl = 0, closed = false,
        close = function(self) self.closed = true end,
        avatarPanel = {x = 10, y = 10, width = 128, height = 128,
            setZoom = noop, setXOffset = noop, setYOffset = noop, setCharacter = noop},
        avatarDefinition = {zoom = 1, xoffset = 0, yoffset = 0},
        avatarX = 10, avatarY = 10, avatarWidth = 128, avatarHeight = 128,
        xOffset = 100, width = 680, borderColor = {a = 1, r = 1, g = 1, b = 1}, animalName = 'Chicken',
        drawRectBorder = noop, drawTextureScaled = noop, drawRect = noop,
        drawText = function(self, text) if text == 'Dead' then self.drewDeadHealth = true end end,
        drawTextRight = noop, renderJoypadFocus = noop, setHeight = noop,
        renameBtn = button(true), feedBtn = button(false), milkAnimalBtn = button(true),
        ageBtn = button(true), genderBtn = button(true)}, ISAnimalUI)
end

local baseline = window()
baseline:prerender()
assert(baseline.closed, 'native UI must reproduce the dead-chicken closure')
local nativePrerender = ISAnimalUI.prerender
local nativeCalls = 0
ISAnimalUI.prerender = function(self)
    nativeCalls = nativeCalls + 1
    return nativePrerender(self)
end
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/AnimalInfo.lua'))()

local dead = window()
dead:prerender()
dead:render()
assert(not dead.closed and dead.drewDeadHealth, 'dead hutch animal must keep its native details visible')
assert(nativeCalls == 0, 'dead hutch path must avoid the native health-close gate')
for _, name in ipairs({'renameBtn', 'feedBtn', 'milkAnimalBtn', 'ageBtn', 'genderBtn'}) do
    assert(dead[name].enable == false, name .. ' must be read-only')
end
dead:render()
health = 1
dead:prerender()
dead:render()
assert(nativeCalls == 1 and not dead.closed, 'living animal must use native prerender')
assert(dead.renameBtn.enable and not dead.feedBtn.enable, 'restore prior button states after revival')
health = 0

distance = 5
local far = window()
far:prerender()
assert(far.closed, 'dead info must close beyond the native hutch distance')
distance = 4
local edge = window()
edge:prerender()
assert(not edge.closed, 'native distance boundary must remain inclusive')
occupant = {}
local replaced = window()
replaced:prerender()
assert(replaced.closed, 'stale animal must close when its hutch slot changes')
occupant, nestAnimal, position = nil, animal, -1
local nest = window()
nest:prerender()
nest:render()
assert(not nest.closed and nest.drewDeadHealth, 'dead nest animal has no roost position but remains inspectable')
nestAnimal = nil
nest:prerender()
assert(nest.closed, 'removing a dead animal from its nest must close the window')
position = 0
occupant = animal
animal.hutch = nil
local removed = window()
removed:prerender()
assert(removed.closed, 'dead animal removed from hutch must use the native close gate')
animal.hutch = hutch

-- Exercise the native nest and roost menu targets without replacing their callbacks.
local inspected
AnimalContextMenu.onAnimalInfo = function(target, player) inspected = {target, player} end
local player = {}
ISContextMenu = {get = function()
    local context = {options = {}}
    function context:addOption(text, target, callback, ...)
        local option = {text = text, target = target, callback = callback, args = {...}}
        self.options[#self.options + 1] = option
        if text == 'ContextMenu_AnimalInfo' then
            callback(target, unpack(option.args))
        end
        return option
    end
    return context
end}
for _, class in ipairs({ISHutchRoost, ISHutchNestBox}) do
    local panel = setmetatable({playerNum = 0, chr = player, index = 0, hutchUI = {hutch = hutch},
        getAnimal = function() return animal end,
        getNest = function() return {getEggsNb = function() return 0 end} end,
        getAbsoluteX = function() return 0 end, getAbsoluteY = function() return 0 end}, class)
    panel:onRightMouseUp(0, 0)
    assert(inspected[1] == animal and inspected[2] == player, 'native menus must inspect IsoAnimal with the right player')
end
print('Native hutch animal info checks passed (dead/live, controls, range, removal, roost/nest menus).')
