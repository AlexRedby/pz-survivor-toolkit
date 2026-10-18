-- Medicine UI must read server effects without changing native consumption or stats.
local base = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/"
local passed = 0
local function check(name, test)
    test()
    passed = passed + 1
    print("PASS medicine: " .. name)
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.000001, tostring(actual) .. " ~= " .. tostring(expected))
end
local function event()
    local callbacks = {}
    return {Add = function(fn) callbacks[#callbacks + 1] = fn end,
        Remove = function(fn) for i = #callbacks, 1, -1 do if callbacks[i] == fn then table.remove(callbacks, i) end end end,
        fire = function(...) for _, fn in ipairs(callbacks) do fn(...) end end,
        count = function() return #callbacks end}
end
local client, server, active, legacy, now = false, true, false, false, 0
local sync, herbs = true, true
local requests, responses, requires, players = {}, {}, {}, {}
Events = {}
for _, name in ipairs({"OnTick", "OnPlayerUpdate", "OnGameStart", "OnClientCommand",
    "OnServerCommand", "OnMainMenuEnter", "OnPlayerDeath", "OnCreatePlayer"}) do Events[name] = event() end
isClient = function() return client end
isServer = function() return server end
getActivatedMods = function() return {contains = function(_, id) return active and id == "MoodleFramework" or legacy and id == "MedicineMoodlesB42" end} end
getTimestampMs = function() return now end
getSpecificPlayer = function(num) return players[num] end
PZSurvivorToolkit = {Settings = {
    medicineMoodleSync = function() return sync end,
    medicineHerbs = function() return herbs end,
}}
require = function(name)
    requires[#requires + 1] = name
    if name == "PZSurvivorToolkit/MedicineEffects" then return PZSurvivorToolkit.MedicineEffects end
    assert(name == "PZSurvivorToolkit" or name == "PZSurvivorToolkit/Settings"
        or name == "MF_ISMoodle", "Unexpected optional dependency: " .. name)
end
sendClientCommand = function(player, module, command, args)
    requests[#requests + 1] = {player = player, module = module, command = command, args = args}
end
sendServerCommand = function(player, module, command, args)
    responses[#responses + 1] = {player = player, module = module, command = command, args = args}
end
ISEatFoodAction = {complete = function() end, eat = function() end}
local nativeComplete, nativeEat = ISEatFoodAction.complete, ISEatFoodAction.eat
local function player(num, id)
    local p = {modData = {Moodles = {LegacyMedicine = {Value = 0.75}}}, num = num or 0, id = id or 12,
        raw = {Antibiotics = 25, Antidepressants = 3300, BetaBlockers = 3300,
            Painkillers = 2700, SleepingTablets = 3300, SleepingIntensity = 0.2,
            BlackSage = 3.5, CommonMallow = 2.5, LemonGrassCooldown = 140}}
    function p:getModData() return self.modData end
    function p:getMoodles() return {getNumMoodles = function() return 0 end} end
    function p:getPlayerNum() return self.num end
    function p:getOnlineID() return self.id end
    function p:isDead() return self.dead == true end
    function p:isLocalPlayer() return self.remote ~= true end
    function p:getBodyDamage()
        return {getPainReduction = function() return self.raw.BlackSage end,
            getColdReduction = function() return self.raw.CommonMallow end}
    end
    for getter, field in pairs({getReduceInfectionPower = "Antibiotics", getDepressEffect = "Antidepressants",
        getBetaEffect = "BetaBlockers", getPainEffect = "Painkillers", getSleepingTabletEffect = "SleepingTablets",
        getSleepingTabletDelta = "SleepingIntensity"}) do
        p[getter] = function(self) return self.raw[field] end
    end
    return p
end
toolkitMedicineCooldown = function(who)
    if not client then return who.raw.LemonGrassCooldown end
end
local nativeCooldown = toolkitMedicineCooldown

check("absent optional mod has no callbacks, hooks or dependencies", function()
    dofile(base .. "shared/PZSurvivorToolkit/MedicineEffects.lua")
    dofile(base .. "server/PZSurvivorToolkit/MedicineMoodles.lua")
    dofile(base .. "client/PZSurvivorToolkit/MedicineMoodles.lua")
    for _, value in pairs(Events) do assert(value.count() == 0) end
    assert(ISEatFoodAction.complete == nativeComplete and ISEatFoodAction.eat == nativeEat)
    assert(not PZSurvivorToolkit.MedicineEffects and not PZSurvivorToolkit.MedicineMoodles)
    assert(#requires == 1 and requires[1] == "PZSurvivorToolkit/Settings")
end)
active, legacy = true, true
check("legacy mod wins without Toolkit hooks, indicators or server traffic", function()
    dofile(base .. "shared/PZSurvivorToolkit/MedicineEffects.lua")
    dofile(base .. "server/PZSurvivorToolkit/MedicineMoodles.lua")
    dofile(base .. "client/PZSurvivorToolkit/MedicineMoodles.lua")
    for _, value in pairs(Events) do assert(value.count() == 0) end
    assert(ISEatFoodAction.complete == nativeComplete and ISEatFoodAction.eat == nativeEat)
    assert(not PZSurvivorToolkit.MedicineEffects and not PZSurvivorToolkit.MedicineMoodles)
end)
legacy = false
dofile(base .. "shared/PZSurvivorToolkit/MedicineEffects.lua")
local effects = PZSurvivorToolkit.MedicineEffects
local p = player()
players[0] = p

check("native readings need no food hooks, callbacks, or independent countdown", function()
    assert(ISEatFoodAction.complete == nativeComplete and ISEatFoodAction.eat == nativeEat)
    assert(Events.OnTick.count() == 0 and Events.OnPlayerUpdate.count() == 0)
    p.raw.LemonGrassCooldown = 187.625
    near(effects.capture(p).LemonGrassCooldown, 187.625)
    Events.OnTick.fire(); Events.OnPlayerUpdate.fire(p)
    near(effects.capture(p).LemonGrassCooldown, 187.625)
    p.raw.LemonGrassCooldown = 7.25
    near(effects.capture(p).LemonGrassCooldown, 7.25)
    p.raw.LemonGrassCooldown = 0
    assert(effects.capture(p).LemonGrassCooldown == 0)
end)
check("missing, unsupported and invalid cooldown readings are unknown rather than zero", function()
    toolkitMedicineCooldown = nil
    local values = effects.capture(p)
    assert(values.LemonGrassCooldown == false and values.Painkillers == 2700)
    toolkitMedicineCooldown = function() return nil end
    assert(effects.capture(p).LemonGrassCooldown == false)
    toolkitMedicineCooldown = nativeCooldown
    for _, invalid in ipairs({false, true, "3", -1, math.huge, -math.huge, 0 / 0, 1000000001}) do
        p.raw.LemonGrassCooldown = invalid
        assert(effects.capture(p).LemonGrassCooldown == false)
    end
    p.raw.LemonGrassCooldown = 140
    near(effects.capture(p).LemonGrassCooldown, 140)
    client = true
    assert(effects.capture(p).LemonGrassCooldown == false)
    client = false
end)
check("native effect zero crossings are clamped without changing character state", function()
    for key in pairs(p.raw) do p.raw[key] = -0.01 end
    for key, value in pairs(effects.capture(p)) do
        if key == "LemonGrassCooldown" then assert(value == false) else assert(value == 0) end
    end
    assert(p.raw.Painkillers == -0.01)
    p.raw = player().raw
end)

dofile(base .. "server/PZSurvivorToolkit/MedicineMoodles.lua")
local function request(args, module, command, who)
    Events.OnClientCommand.fire(module or "PZSurvivorToolkitMedicine", command or "Read", who or p, args)
end
check("server accepts authenticated self reads only, with nonce and 750ms rate limit", function()
    for _, value in ipairs({0, -1, 1.5, 2147483648, math.huge, 0 / 0, "1"}) do request({request = value}) end
    request(nil)
    request(true)
    request("invalid-root")
    request({request = 1}, "OtherModule")
    request({request = 1}, nil, "Write")
    p.dead = true
    request({request = 1})
    p.dead = false
    assert(#responses == 0)
    request({request = 1, onlineID = 999, player = "someone-else"})
    assert(#responses == 1 and responses[1].player == p)
    assert(responses[1].module == "PZSurvivorToolkitMedicine" and responses[1].command == "State")
    assert(responses[1].args.onlineID == p.id and responses[1].args.request == 1)
    near(responses[1].args.BlackSage, 3.5)
    near(responses[1].args.CommonMallow, 2.5)
    near(responses[1].args.LemonGrassCooldown, 140)
    assert(responses[1].args.LemonGrass == nil, "never send the old estimated field")
    now = 749
    request({request = 2})
    assert(#responses == 1)
    now = 750
    request({request = 2})
    assert(#responses == 2 and responses[2].args.request == 2)
    local other = player(1, 24)
    request({request = 3}, nil, nil, other)
    assert(#responses == 3 and responses[3].player == other and responses[3].args.onlineID == 24)
end)

check("server reports unavailable cooldown without discarding other native readings", function()
    local other = player(2, 25)
    toolkitMedicineCooldown = nil
    request({request = 4}, nil, nil, other)
    local values = responses[#responses].args
    assert(values.onlineID == 25 and values.request == 4)
    assert(values.LemonGrassCooldown == false and values.Painkillers == 2700)
    toolkitMedicineCooldown = nativeCooldown
end)

-- Use the real framework when supplied; default fixtures cover only the public UI contract.
getText = function(key, value) return key .. (value ~= nil and "(" .. tostring(value) .. ")" or "") end
round = function(value, places)
    local scale = 10 ^ (places or 0)
    local rounded = math.floor(value * scale + 0.5) / scale
    return rounded % 1 == 0 and math.floor(rounded) or rounded
end
getScriptManager = function()
    return {getItem = function(_, name) return {
        getNormalTexture = function() return "texture:" .. name end,
        getDisplayName = function() return "native-title:" .. name end,
    } end}
end
ISUIElement = {}
function ISUIElement:derive() local o = {}; setmetatable(o, {__index = self}); return o end
function ISUIElement:new(x, y, w, h)
    local o = {x = x, y = y, width = w, height = h}
    setmetatable(o, {__index = self}); return o
end
function ISUIElement:initialise() end
function ISUIElement:getWidth() return self.width end
function ISUIElement:getX() return self.x end
function ISUIElement:getY() return self.y end
function ISUIElement:setX(v) self.x = v end
function ISUIElement:setY(v) self.y = v end
function ISUIElement:setWidth(v) self.width = v end
function ISUIElement:setHeight(v) self.height = v end
function ISUIElement:addToUIManager() self.visible = true end
function ISUIElement:removeFromUIManager() self.visible = false end
getCore = function() return {getOptionMoodleSize = function() return 1 end} end
getTexture = function(name) return "texture:" .. name end
getPlayerScreenLeft = function() return 0 end
getPlayerScreenWidth = function() return 1280 end
getPlayerScreenTop = function() return 0 end
Registries = {MOODLE_TYPE = {getValues = function() return {size = function() return 0 end} end}}
if NativeMedicineFrameworkSource then
    assert(loadstring(NativeMedicineFrameworkSource))()
else
    MF = {MoodlesStorage = {}, createdMoodleTypes = {}, ISMoodle = ISUIElement:derive()}
    function MF.createMoodle(name)
        if MF.createdMoodleTypes[name] then return end
        MF.createdMoodleTypes[name] = true
        Events.OnCreatePlayer.Add(function(num) MF.ISMoodle:new(name, getSpecificPlayer(num)) end)
    end
    function MF.getMoodle(name, num) return MF.MoodlesStorage[num] and MF.MoodlesStorage[num][name] end
    function MF.ISMoodle:new(name, who)
        local old = MF.getMoodle(name, who.num)
        if old then old:removeFromUIManager(); Events.OnPlayerDeath.Remove(old.death) end
        local m = ISUIElement.new(self, 0, 0, 32, 32)
        m.name, m.char, m.value = name, who, 0
        m.title, m.desc, m.pics = {{}, {}}, {{}, {}}, {{}, {}}
        m.death = function(dead) if dead == who then m:removeFromUIManager(); m.disable = true end end
        Events.OnPlayerDeath.Add(m.death)
        MF.MoodlesStorage[who.num] = MF.MoodlesStorage[who.num] or {}
        MF.MoodlesStorage[who.num][name] = m
        return m
    end
    function MF.ISMoodle:setThresholds(...) self.thresholds = {...} end
    function MF.ISMoodle:setValue(v) if not self.disable then self.value = v; self.visible = v ~= 0 end end
    function MF.ISMoodle:getValue() return self.value end
    function MF.ISMoodle:getLevel()
        local v = math.abs(self.value)
        return v >= 0.7 and 4 or v >= 0.4 and 3 or v >= 0.1 and 2 or v >= 0.000001 and 1 or 0
    end
    function MF.ISMoodle:getGoodBadNeutral() return self.value > 0 and 1 or self.value < 0 and 2 or 0 end
    function MF.ISMoodle:setTitle(kind, level, v) self.title[kind][level] = v end
    function MF.ISMoodle:setPicture(kind, level, v) self.pics[kind][level] = v end
    function MF.ISMoodle:setDescription(kind, level, v) self.desc[kind][level] = v end
    function MF.ISMoodle:getDescription(kind, level) return self.desc[kind][level] end
end
local scales = {Antibiotics = 50, Antidepressants = 6600, BetaBlockers = 6600,
    Painkillers = 5400, SleepingTablets = 6600, LemonGrass = 280, BlackSage = 7, CommonMallow = 5}
client, server, now = true, false, 0
dofile(base .. "client/PZSurvivorToolkit/MedicineMoodles.lua")
local medicine = PZSurvivorToolkit.MedicineMoodles
Events.OnCreatePlayer.fire(0)
local function poll(who) Events.OnPlayerUpdate.fire(who or p) end
local function moodle(name, who) return MF.getMoodle(medicine.names[name], (who or p).num) end
local function description(name) local m = moodle(name); return m:getDescription(m:getGoodBadNeutral(), m:getLevel()) end
local function payload(who)
    who = who or p
    local result = effects.capture(who)
    result.LemonGrassCooldown = 140
    result.request = medicine.states[who.num].request
    result.onlineID = who.id
    return result
end
local function receive(values, module, command)
    Events.OnServerCommand.fire(module or "PZSurvivorToolkitMedicine", command or "State", values)
end
check("client polling is local-only and retries pending reads after five seconds", function()
    p.remote = true
    poll()
    assert(#requests == 0)
    p.remote = false
    poll()
    assert(#requests == 1 and requests[1].player == p and requests[1].args.request == 1)
    local old = payload()
    now = 1000; poll()
    now = 4999; poll()
    assert(#requests == 1)
    now = 5000; poll()
    assert(#requests == 2 and requests[2].args.request ~= old.request)
    receive(old)
    assert(not medicine.states[0].values)
    receive(payload()); poll()
    assert(medicine.states[0].values and not medicine.states[0].request)
end)
check("eight own authoritative indicators, pending antidepressant and sleeping intensity", function()
    for name in pairs(scales) do
        local m = moodle(name)
        near(math.abs(m:getValue()), 0.5)
        assert(m.name == "PZSurvivorToolkitMedicine" .. name)
        assert(m:getGoodBadNeutral() == (name == "LemonGrass" and 2 or 1))
    end
    medicine.states[0].values.Antidepressants = 6600; poll()
    assert(moodle("Antidepressants"):getLevel() == 1)
    assert(moodle("Antidepressants"):getGoodBadNeutral() == 2)
    assert(description("Antidepressants") == "UI_PZSurvivorToolkit_medicine_pending")
    medicine.states[0].values.Antidepressants = 3300; poll()
    near(moodle("Antidepressants"):getValue(), 0.5)
    assert(description("Antidepressants") == "IGUI_RemainingPercent(50)")
end)
check("duration-unchanged tooltips refresh and all item icons use native assets", function()
    assert(description("SleepingTablets") == "IGUI_climate_intensity: 2 / IGUI_RemainingPercent(50)")
    medicine.states[0].values.SleepingIntensity = 0.3; poll()
    assert(description("SleepingTablets") == "IGUI_climate_intensity: 3 / IGUI_RemainingPercent(50)")
    assert(description("LemonGrass") == "UI_PZSurvivorToolkit_medicine_cooldown(50)")
    for name, item in pairs({Antibiotics = "Antibiotics", Antidepressants = "PillsAntiDep",
        BetaBlockers = "PillsBeta", Painkillers = "Pills", SleepingTablets = "PillsSleepingTablets",
        LemonGrass = "LemonGrass", BlackSage = "BlackSage", CommonMallow = "CommonMallow"}) do
        local m = moodle(name)
        local title = (name == "BlackSage" or name == "CommonMallow")
            and "UI_PZSurvivorToolkit_medicine_" .. name or "native-title:Base." .. item
        for kind = 1, 2 do for level = 1, 4 do
            assert(m.title[kind][level] == title)
            assert(m.pics[kind][level] == "texture:Base." .. item)
        end end
    end
    assert(p.modData.Moodles.LegacyMedicine.Value == 0.75)
end)
check("unavailable and legacy estimates hide only lemongrass; native zero stays valid", function()
    for _, case in ipairs({{"legacy", 0}, {false, 0}, {0, 0}, {70, -0.25}, {140, -0.5}}) do
        now = now + 1000; poll()
        local values = payload()
        values.LemonGrass = 280
        if case[1] == "legacy" then values.LemonGrassCooldown = nil
        else values.LemonGrassCooldown = case[1] end
        receive(values); poll()
        near(moodle("LemonGrass"):getValue(), case[2])
        near(moodle("Painkillers"):getValue(), 0.5)
        assert(not medicine.states[0].request)
    end
end)
check("invalid and mismatched snapshots cannot replace accepted state", function()
    now = now + 1000; poll()
    local state, accepted = medicine.states[0], medicine.states[0].values
    local function rejected(values, module, command)
        receive(values, module, command)
        assert(state.values == accepted and state.request ~= nil)
    end
    rejected(nil); rejected("not-a-table"); rejected(payload(), "OtherModule"); rejected(payload(), nil, "OtherCommand")
    for _, invalid in ipairs({-1, math.huge, 0 / 0, "1", 1000000001}) do
        local values = payload(); values.Painkillers = invalid; rejected(values)
    end
    for _, invalid in ipairs({true, -1, math.huge, 0 / 0, "1", 1000000001}) do
        local values = payload(); values.LemonGrassCooldown = invalid; rejected(values)
    end
    local values = payload(); values.BlackSage = nil; rejected(values)
    values = payload(); values.SleepingIntensity = 0 / 0; rejected(values)
    values = payload(); values.SleepingIntensity = -1; rejected(values)
    values = payload(); values.onlineID = 999; rejected(values)
    values = payload(); values.request = state.request + 1; rejected(values)
    p.dead = true; rejected(payload()); p.dead = false
    p.remote = true; rejected(payload()); p.remote = false
    receive(payload())
    assert(state.values ~= accepted and not state.request)
    accepted = state.values
    values = payload(); values.Painkillers = 999; receive(values)
    assert(state.values == accepted, "Unsolicited state without an outstanding nonce must be ignored")
end)
check("stale state hides all effects; death and respawn reject previous identity", function()
    now = medicine.states[0].receivedAt + 10001; poll()
    for name in pairs(scales) do assert(moodle(name):getLevel() == 0) end
    local old = payload()
    local replacement = player(0, 99)
    players[0] = replacement
    receive(old)
    assert(medicine.states[0].request == old.request)
    poll(replacement)
    assert(medicine.states[0].player == replacement)
    receive(old)
    assert(not medicine.states[0].values)
    receive(payload(replacement)); poll(replacement)
    assert(medicine.states[0].values)
    replacement.dead = true
    Events.OnPlayerDeath.fire(replacement)
    assert(not medicine.states[0])
    for name in pairs(scales) do assert(not moodle(name, replacement).visible) end
    replacement.dead = false
    -- A fresh character, rather than reviving the framework's suspended dead UI.
    p = player(0, 100); players[0] = p
    Events.OnCreatePlayer.fire(0)
    poll(); receive(payload()); poll()
    for name in pairs(scales) do assert(moodle(name).char == p and moodle(name):getLevel() > 0) end
end)
check("independent switches hide six medicine indicators and two native herb pools", function()
    sync, herbs = false, true; poll()
    for name in pairs(scales) do
        assert((moodle(name):getLevel() > 0) == (name == "BlackSage" or name == "CommonMallow"))
    end
    sync, herbs = true, false; poll()
    for name in pairs(scales) do
        assert((moodle(name):getLevel() > 0) == (name ~= "BlackSage" and name ~= "CommonMallow"))
    end
    sync, herbs = false, false; poll()
    assert(not medicine.states[0])
    for name in pairs(scales) do assert(moodle(name):getLevel() == 0) end
    sync, herbs = true, true; poll(); receive(payload()); poll()
    Events.OnMainMenuEnter.fire()
    assert(next(medicine.states) == nil)
end)
check("split-screen slots retain their own player, nonce, and framework indicators", function()
    local other = player(1, 101); players[1] = other
    Events.OnCreatePlayer.fire(1)
    poll(); poll(other)
    local first, second = payload(), payload(other)
    assert(first.request ~= second.request)
    receive(second); poll(other)
    assert(not medicine.states[0].values and medicine.states[1].values)
    receive(first); poll()
    assert(moodle("Painkillers").char == p and moodle("Painkillers", other).char == other)
end)
check("single-player reads native effects directly without any network requests", function()
    client, server, sync, herbs = false, false, true, true
    local sent = #requests
    p.raw.Antibiotics, p.raw.Painkillers = 25, 2700
    p.raw.BlackSage, p.raw.CommonMallow = 3.5, 2.5
    p.raw.LemonGrassCooldown = 70
    poll()
    for _, name in ipairs({"Antibiotics", "Painkillers", "BlackSage", "CommonMallow"}) do near(moodle(name):getValue(), 0.5) end
    near(moodle("LemonGrass"):getValue(), -0.25)
    toolkitMedicineCooldown = nil; poll()
    assert(moodle("LemonGrass"):getLevel() == 0)
    near(moodle("Painkillers"):getValue(), 0.5)
    toolkitMedicineCooldown = nativeCooldown
    assert(#requests == sent)
end)
check("module reloads preserve UI registrations and native hooks", function()
    local count, hook = Events.OnCreatePlayer.count(), ISEatFoodAction.complete
    dofile(base .. "shared/PZSurvivorToolkit/MedicineEffects.lua")
    dofile(base .. "client/PZSurvivorToolkit/MedicineMoodles.lua")
    server = true
    local commands = Events.OnClientCommand.count()
    dofile(base .. "server/PZSurvivorToolkit/MedicineMoodles.lua")
    assert(Events.OnCreatePlayer.count() == count and Events.OnClientCommand.count() == commands)
    assert(ISEatFoodAction.complete == hook)
end)
print("Medicine moodles regressions passed: " .. passed .. ".")
