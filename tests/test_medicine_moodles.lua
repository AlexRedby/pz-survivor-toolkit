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
local client, server, active, legacy, now, multiplier = false, true, false, false, 0, 1
local sync, herbs = true, true
local requests, responses, requires, players = {}, {}, {}, {}
Events = {}
for _, name in ipairs({"OnTick", "OnPlayerUpdate", "OnGameStart", "OnClientCommand",
    "OnServerCommand", "OnMainMenuEnter", "OnPlayerDeath", "OnCreatePlayer"}) do Events[name] = event() end
isClient = function() return client end
isServer = function() return server end
getActivatedMods = function() return {contains = function(_, id) return active and id == "MoodleFramework" or legacy and id == "MedicineMoodlesB42" end} end
getTimestampMs = function() return now end
getGameTime = function() return {getMultiplier = function() return multiplier end} end
getSpecificPlayer = function(num) return players[num] end
CharacterStat = {FOOD_SICKNESS = "sickness", POISON = "poison"}
CharacterTrait = {IRON_GUT = "iron", WEAK_STOMACH = "weak"}
PZSurvivorToolkit = {Settings = {
    medicineMoodleSync = function() return sync end,
    medicineHerbs = function() return herbs end,
}}
require = function(name)
    requires[#requires + 1] = name
    if name == "PZSurvivorToolkit/MedicineEffects" then return PZSurvivorToolkit.MedicineEffects end
    assert(name == "PZSurvivorToolkit" or name == "PZSurvivorToolkit/Settings"
        or name == "TimedActions/ISEatFoodAction" or name == "MF_ISMoodle", "Unexpected optional dependency: " .. name)
end
sendClientCommand = function(player, module, command, args)
    requests[#requests + 1] = {player = player, module = module, command = command, args = args}
end
sendServerCommand = function(player, module, command, args)
    responses[#responses + 1] = {player = player, module = module, command = command, args = args}
end
local nativeCalls = {complete = 0, eat = 0}
local function nativeEating(kind)
    return function(action, amount, marker)
        nativeCalls[kind] = nativeCalls[kind] + 1
        action.amount, action.marker = amount, marker
        if action.reduction then
            action.character.stats.sickness = action.character.stats.sickness - action.reduction
            action.character.stats.poison = action.character.stats.poison - action.reduction
        end
        return action.result
    end
end
ISEatFoodAction = {complete = nativeEating("complete"), eat = nativeEating("eat")}
local nativeComplete, nativeEat = ISEatFoodAction.complete, ISEatFoodAction.eat
local function player(num, id, traits)
    local p = {modData = {Moodles = {LegacyMedicine = {Value = 0.75}}}, num = num or 0, id = id or 12, traits = traits or {}, stats = {sickness = 50, poison = 25},
        raw = {Antibiotics = 25, Antidepressants = 3300, BetaBlockers = 3300,
            Painkillers = 2700, SleepingTablets = 3300, SleepingIntensity = 0.2,
            BlackSage = 3.5, CommonMallow = 2.5}}
    function p:getModData() return self.modData end
    function p:getMoodles() return {getNumMoodles = function() return 0 end} end
    function p:getPlayerNum() return self.num end
    function p:getOnlineID() return self.id end
    function p:isDead() return self.dead == true end
    function p:isLocalPlayer() return self.remote ~= true end
    function p:hasTrait(trait) return self.traits[trait] == true end
    function p:getStats() return {get = function(_, stat) return self.stats[stat] end} end
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
local function action(p, change, reduction, result)
    return {character = p, item = {getFoodSicknessChange = function() return change end},
        reduction = reduction, result = result}
end

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

check("complete preserves native call, arguments and false result", function()
    local a = action(p, -12, 3, false)
    assert(ISEatFoodAction.complete(a, 0.25, "complete-marker") == false)
    assert(nativeCalls.complete == 1 and a.amount == 0.25 and a.marker == "complete-marker")
    near(effects.capture(p).LemonGrass, 230)
end)
check("partial cancelled consumption and native trait cooldown upper bounds", function()
    for _, case in ipairs({{{}, 230}, {{iron = true}, 150}, {{weak = true}, 280}, {{iron = true, weak = true}, 150}}) do
        local other = player(1, 23, case[1])
        local a = action(other, -1, 0.25, "partial-result")
        local calls = nativeCalls.eat
        assert(ISEatFoodAction.eat(a, 0.25, "cancel-marker") == "partial-result")
        assert(nativeCalls.eat == calls + 1 and a.amount == 0.25 and a.marker == "cancel-marker")
        near(effects.capture(other).LemonGrass, case[2])
    end
end)
check("ineffective herbs, ordinary food and client prediction never start cooldown", function()
    local other = player()
    local calls = nativeCalls.complete
    ISEatFoodAction.complete(action(other, -12, nil, "ineffective"))
    ISEatFoodAction.complete(action(other, 0, 1, "ordinary"))
    ISEatFoodAction.complete({character = other, result = "missing-item"})
    assert(nativeCalls.complete == calls + 3 and effects.capture(other).LemonGrass == 0)
    client = true
    ISEatFoodAction.complete(action(other, -12, 1, "client"))
    assert(effects.capture(other).LemonGrass == 0)
    client = false
    multiplier = 2
    Events.OnTick.fire()
    local before = effects.capture(p).LemonGrass
    ISEatFoodAction.complete(action(p, -12, nil, "still-ineffective"))
    near(effects.capture(p).LemonGrass, before)
end)
check("server tick and single-player update use native rate without double decrement", function()
    ISEatFoodAction.complete(action(p, -12, 1, true))
    multiplier = 2
    Events.OnPlayerUpdate.fire(p)
    near(effects.capture(p).LemonGrass, 230)
    Events.OnTick.fire()
    near(effects.capture(p).LemonGrass, 229.97)
    server = false
    Events.OnTick.fire()
    near(effects.capture(p).LemonGrass, 229.97)
    Events.OnPlayerUpdate.fire(p)
    near(effects.capture(p).LemonGrass, 229.94)
    client = true
    Events.OnPlayerUpdate.fire(p)
    Events.OnTick.fire()
    near(effects.capture(p).LemonGrass, 229.94)
    client, server = false, true
end)
check("expired and dead cooldowns clear; native zero crossings cannot be negative", function()
    multiplier = 100000
    Events.OnTick.fire()
    assert(effects.capture(p).LemonGrass == 0)
    ISEatFoodAction.complete(action(p, -12, 1, true))
    p.dead = true
    Events.OnTick.fire()
    assert(effects.capture(p).LemonGrass == 0)
    p.dead, multiplier = false, 1
    for key in pairs(p.raw) do p.raw[key] = -0.01 end
    for _, value in pairs(effects.capture(p)) do assert(value == 0) end
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
    result.LemonGrass = 140
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
check("invalid and mismatched snapshots cannot replace accepted state", function()
    now = 6000; poll()
    local state, accepted = medicine.states[0], medicine.states[0].values
    local function rejected(values, module, command)
        receive(values, module, command)
        assert(state.values == accepted and state.request ~= nil)
    end
    rejected(nil); rejected("not-a-table"); rejected(payload(), "OtherModule"); rejected(payload(), nil, "OtherCommand")
    for _, invalid in ipairs({-1, math.huge, 0 / 0, "1", 1000000001}) do
        local values = payload(); values.Painkillers = invalid; rejected(values)
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
    poll()
    for _, name in ipairs({"Antibiotics", "Painkillers", "BlackSage", "CommonMallow"}) do near(moodle(name):getValue(), 0.5) end
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
