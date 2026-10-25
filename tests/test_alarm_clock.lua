local path = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/AlarmClock.lua"
local function setup(client)
    local w = {speed = 3, resets = 0, rings = 0, ui = {}, commands = {}, handlers = {}, multiplier = 1}
    PZSurvivorToolkit, MPFastForward, MPFF_Panel = {}, nil, nil
    require = function(name) assert(name == "PZSurvivorToolkit", "must not require optional mods") end
    Events = setmetatable({}, {__index = function(t, name)
        local event = {Add = function(fn)
            w.handlers[name] = w.handlers[name] or {}
            table.insert(w.handlers[name], fn)
        end}
        t[name] = event
        return event
    end})
    isClient = function() return client end
    toolkitConsumeAlarmRing = function()
        if w.rings == 0 then return false end
        w.rings = w.rings - 1
        return true
    end
    w.controls = {getCurrentGameSpeed = function() return w.speed end,
        SetCurrentGameSpeed = function(_, speed) w.resets = w.resets + 1; w.speed = speed end}
    UIManager = {getSpeedControls = function() return w.controls end, getUI = function()
        return {size = function() return #w.ui end, get = function(_, i) return w.ui[i + 1] end}
    end}
    getGameTime = function() return {getMultiplier = function() return w.multiplier end,
        setMultiplier = function(_, value) w.multiplier = value end} end
    w.tick = dofile(path).onTick
    return w
end

local w = setup(false)
w.tick()
assert(w.speed == 3 and w.resets == 0, "no audible ring must preserve speed")
w.rings = 1; w.tick(); w.tick()
assert(w.speed == 1 and w.resets == 1, "heard alarm resets SP acceleration once")
for _, speed in ipairs({0, 1}) do
    w.speed = speed; w.rings = 1; w.tick()
    assert(w.speed == speed and w.resets == 1, "alarm must preserve pause and normal speed")
end
w.controls = nil; w.rings = 1; w.tick()
toolkitConsumeAlarmRing = nil; w.tick()
UIManager = nil; toolkitConsumeAlarmRing = function() return true end; w.tick()
print("PASS alarm SP resets only acceleration; absent Java bridge/UI stays inert")

w = setup(true)
w.rings = 1; w.tick()
assert(w.resets == 0 and w.speed == 3, "MP without MPFF must not write local speed")
MPFastForward = {NORMAL = 1}; MPFF_Panel = {}
w.rings = 1; w.tick()
assert(w.resets == 0, "missing MPFF panel must remain inert")
local selected, selections = 4, {}
MPFF_Panel.__index = MPFF_Panel
function MPFF_Panel:getSelected() return selected end
function MPFF_Panel:userSelect(level, force, veto)
    selections[#selections + 1] = {level, force, veto}
    selected = level
end
local panel = setmetatable({}, MPFF_Panel)
w.ui = {{getTable = function() return nil end}, {getTable = function() return {Type = "MPFF_Panel"} end},
    {getTable = function() return panel end}}
w.rings = 1; w.tick(); w.tick()
assert(#selections == 1 and selections[1][1] == 1 and selections[1][2] == false and selections[1][3] == true)
assert(w.resets == 0, "MPFF reset must use upstream selection, never SP controls")
w.multiplier = 10; w.rings = 1; w.tick()
assert(#selections == 2, "server acceleration must reset even when local vote is normal")
w.multiplier = 1
for _, speed in ipairs({0, 1}) do
    selected = speed; w.rings = 1; w.tick()
end
assert(#selections == 2, "MPFF pause and normal speed must remain untouched")
w.ui = {}; w.rings = 1; w.tick()
assert(#selections == 2, "removed panel must never be retained")
print("PASS alarm discovers only live MPFF panel and sends normal safety veto for accelerated selection/server speed")

if not NativeMPFFClientSource or not NativeMPFFPanelSource or not NativeMPFFConfigSource then
    print("SKIP alarm upstream MPFF client checks require --mpff-source")
    return
end
w = setup(true)
assert(loadstring(NativeMPFFConfigSource))()
MPFastForward.logBoot = function() end
MPFastForward.isConflictModActive = function() return false end
require = function() end
ISPanel = {}
function ISPanel:derive() local class = {}; class.__index = class; return setmetatable(class, {__index = self}) end
function ISPanel:new() return setmetatable({}, self) end
function ISPanel:addToUIManager()
    local panel = self
    w.ui[#w.ui + 1] = {getTable = function() return panel end}
end
assert(loadstring(NativeMPFFPanelSource))()
function MPFF_Panel:createButtons()
    self.buttons = {}
    for level = 0, 4 do
        self.buttons[#self.buttons + 1] = {level = level, setSelected = function(button, value) button.selected = value end,
            isSelected = function(button) return button.selected end}
    end
end
MPFF_PauseOverlay = {new = function() return {addToUIManager = function() end, setShown = function() end} end}
SandboxVars = {MPFastForward = {ControlMode = MPFastForward.CONTROL_ADMIN}}
getSoundManager = function() return {setMusicState = function() end, resumeSoundAndMusic = function() end} end
sendClientCommand = function(module, command, args) w.commands[#w.commands + 1] = {module, command, args} end
assert(loadstring(NativeMPFFClientSource))()
w.handlers.OnCreatePlayer[1](0, {})
w.handlers.OnServerCommand[1](MPFastForward.MODULE, "speed", {multiplier = 20})
w.rings = 1; w.tick()
local sent = w.commands[#w.commands]
assert(sent[1] == "MPFastForward" and sent[2] == "select" and sent[3].level == MPFastForward.NORMAL
    and sent[3].force == false and sent[3].veto == true, "actual upstream client must receive safety veto in admin mode")
assert(w.multiplier == 1 and w.resets == 0, "actual upstream client must apply its own immediate normal reset")
print("PASS actual MPFF private Client/panel callback resets local multiplier and sends normal veto in admin mode")
