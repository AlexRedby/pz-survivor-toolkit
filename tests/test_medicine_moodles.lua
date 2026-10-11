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
        fire = function(...) for _, fn in ipairs(callbacks) do fn(...) end end,
        count = function() return #callbacks end}
end
local client, server, active, now, multiplier = false, true, false, 0, 1
local sync, herbs = true, true
local requests, responses, requires, players = {}, {}, {}, {}
Events = {}
for _, name in ipairs({"OnTick", "OnPlayerUpdate", "OnGameStart", "OnClientCommand",
    "OnServerCommand", "OnMainMenuEnter", "OnPlayerDeath"}) do Events[name] = event() end
isClient = function() return client end
isServer = function() return server end
getActivatedMods = function() return {contains = function(_, id) return active and id == "MedicineMoodlesB42" end} end
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
        or name == "TimedActions/ISEatFoodAction", "Unexpected optional dependency: " .. name)
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
    local p = {num = num or 0, id = id or 12, traits = traits or {}, stats = {sickness = 50, poison = 25},
        raw = {Antibiotics = 25, Antidepressants = 3300, BetaBlockers = 3300,
            Painkillers = 2700, SleepingTablets = 3300, SleepingIntensity = 0.2,
            BlackSage = 3.5, CommonMallow = 2.5}}
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
active = true
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
    for _, value in ipairs({0, -1, 1.5, 2147483648, math.huge, "1"}) do request({request = value}) end
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

-- Match upstream's value-change early return: intensity-only tooltip changes must survive it.
getText = function(key, value) return key .. (value ~= nil and "(" .. tostring(value) .. ")" or "") end
round = function(value, places)
    local scale = 10 ^ (places or 0)
    local rounded = math.floor(value * scale + 0.5) / scale
    return rounded % 1 == 0 and math.floor(rounded) or rounded
end
getScriptManager = function()
    return {getItem = function(_, name) return {getNormalTexture = function() return "texture:" .. name end} end}
end
local upstreamCalls = 0
local mod = {Medicines = {}, PlayerMoodles = {}, MoodleLevels = {Hidden = -0.5, Bad = {-1.05}},
    MoodleType = {Good = 1, Bad = 2, Special = 3}}
function mod:checkSkillRequirements(moodle) return moodle.allowed ~= false end
function mod:setupMoodle(moodle) if moodle then moodle:setValue(-0.5) end end
function mod:addMedicine(name, item, getValue)
    self.Medicines[name] = {item = item, getValue = getValue}
end
function mod:updateMoodle(moodle)
    if not self:checkSkillRequirements(moodle) then moodle:setValue(-0.5); return end
    local value, kind, intensity = self.Medicines[moodle.name].getValue(self, moodle.char)
    kind = kind or self.MoodleType.Good
    local shown = kind == self.MoodleType.Special and value
        or value > 0 and (kind == self.MoodleType.Bad and -value - 1 or value) or -0.5
    if moodle:getValue() == shown then return end
    moodle:setValue(shown)
    if moodle:getLevel() > 0 and kind ~= self.MoodleType.Special then
        local description = getText("IGUI_RemainingPercent", round(value * 100))
        if intensity and intensity > 0 then
            description = getText("IGUI_climate_intensity") .. ": " .. round(intensity, 2) .. " / " .. description
        end
        moodle:setDescription(kind, moodle:getLevel(), description)
    end
end
local scales = {Antibiotics = 50, Antidepressants = 6600, BetaBlockers = 6600,
    Painkillers = 5400, SleepingTablets = 6600, LemonGrass = 280, BlackSage = 7, CommonMallow = 5}
for name in pairs(scales) do
    if name ~= "BlackSage" and name ~= "CommonMallow" then
        mod:addMedicine(name, "Base." .. name, function(self, who)
            assert(self == mod and who == players[who:getPlayerNum()])
            upstreamCalls = upstreamCalls + 1
            return 0.25, mod.MoodleType.Bad, 7
        end)
    end
end
local function moodle(name, who)
    local m = {name = name, char = who or p, value = -0.5, descriptions = {}, descriptionWrites = 0,
        titles = {}, pictures = {}}
    function m:getValue() return self.value end
    function m:setValue(value) self.value = value end
    function m:getLevel()
        local value = self.value
        if value < -1 then value = -value - 1 end
        if value <= 0 then return 0 end
        return value >= 0.7 and 4 or value >= 0.4 and 3 or value >= 0.1 and 2 or 1
    end
    function m:setDescription(kind, level, text)
        self.descriptionWrites = self.descriptionWrites + 1
        self.descriptions[kind .. ":" .. level] = text
        self.description = text
    end
    function m:getDescription(kind, level) return self.descriptions[kind .. ":" .. level] end
    function m:setTitle(kind, level, text) self.titles[kind .. ":" .. level] = text end
    function m:setPicture(kind, level, texture) self.pictures[kind .. ":" .. level] = texture end
    return m
end
ModMedicineMoodles = mod
client, server, now = true, false, 0
dofile(base .. "client/PZSurvivorToolkit/MedicineMoodles.lua")
local medicine = PZSurvivorToolkit.MedicineMoodles
Events.OnGameStart.fire()
local function poll(who) Events.OnPlayerUpdate.fire(who or p) end
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
    now = 1000
    poll()
    now = 4999
    poll()
    assert(#requests == 1)
    now = 5000
    poll()
    assert(#requests == 2 and requests[2].args.request ~= old.request)
    receive(old)
    assert(not medicine.states[0].values)
    receive(payload())
    assert(medicine.states[0].values and not medicine.states[0].request)
end)
check("eight authoritative effect scales, pending antidepressant and sleeping intensity", function()
    for name in pairs(scales) do
        local value, kind, intensity = mod.Medicines[name].getValue(mod, p)
        near(value, 0.5)
        if name == "LemonGrass" then assert(kind == mod.MoodleType.Bad) end
        if name == "SleepingTablets" then near(intensity, 2) end
    end
    medicine.states[0].values.Antidepressants = 6600
    local value, kind = mod.Medicines.Antidepressants.getValue(mod, p)
    assert(value == mod.MoodleLevels.Bad[1] and kind == mod.MoodleType.Special)
    local m = moodle("Antidepressants")
    mod:updateMoodle(m)
    assert(m.descriptions["2:1"] == "UI_PZSurvivorToolkit_medicine_pending")
    medicine.states[0].values.Antidepressants = 3300
    mod:updateMoodle(m)
    near(m:getValue(), 0.5)
    assert(m.description == "IGUI_RemainingPercent(50)")
end)
check("sleeping intensity tooltip refreshes while duration is unchanged", function()
    local m = moodle("SleepingTablets")
    mod:updateMoodle(m)
    assert(m.description == "IGUI_climate_intensity: 2 / IGUI_RemainingPercent(50)")
    local writes = m.descriptionWrites
    medicine.states[0].values.SleepingIntensity = 0.3
    mod:updateMoodle(m)
    assert(m.description == "IGUI_climate_intensity: 3 / IGUI_RemainingPercent(50)")
    assert(m.descriptionWrites == writes + 1)
    mod:updateMoodle(m)
    assert(m.descriptionWrites == writes + 1)
    local lemon = moodle("LemonGrass")
    mod:updateMoodle(lemon)
    assert(lemon.description == "UI_PZSurvivorToolkit_medicine_cooldown(50)")
    lemon:setDescription(mod.MoodleType.Bad, lemon:getLevel(), "IGUI_RemainingPercent(50)")
    local lemonWrites = lemon.descriptionWrites
    mod:updateMoodle(lemon)
    assert(lemon.description == "UI_PZSurvivorToolkit_medicine_cooldown(50)")
    assert(lemon.descriptionWrites == lemonWrites + 1, "Repair descriptions overwritten by upstream setup")
    mod:updateMoodle(lemon)
    assert(lemon.descriptionWrites == lemonWrites + 1)
end)
check("skills still hide medicine indicators and herbs have vanilla item icons", function()
    local m = moodle("SleepingTablets")
    m.allowed = false
    mod:updateMoodle(m)
    assert(m:getLevel() == 0 and m.descriptionWrites == 0)
    for _, name in ipairs({"BlackSage", "CommonMallow"}) do
        local herb = moodle(name)
        mod:setupMoodle(herb)
        assert(herb.titles["1:1"] == "UI_PZSurvivorToolkit_medicine_" .. name)
        assert(herb.pictures["2:4"] == "texture:Base." .. name)
    end
end)
check("invalid and mismatched snapshots cannot replace accepted state", function()
    now = 6000
    poll()
    local state, accepted = medicine.states[0], medicine.states[0].values
    local function rejected(values, module, command)
        receive(values, module, command)
        assert(state.values == accepted and state.request ~= nil)
    end
    rejected(nil)
    rejected("not-a-table")
    rejected(payload(), "OtherModule")
    rejected(payload(), nil, "OtherCommand")
    for _, invalid in ipairs({-1, math.huge, "1", 1000000001}) do
        local values = payload(); values.Painkillers = invalid; rejected(values)
    end
    local values = payload(); values.BlackSage = nil; rejected(values)
    values = payload(); values.SleepingIntensity = 0 / 0; rejected(values)
    values = payload(); values.SleepingIntensity = -1; rejected(values)
    values = payload(); values.onlineID = 999; rejected(values)
    values = payload(); values.request = state.request + 1; rejected(values)
    p.dead = true
    rejected(payload())
    p.dead = false
    receive(payload())
    assert(state.values ~= accepted and not state.request)
    accepted = state.values
    values = payload(); values.Painkillers = 999
    receive(values)
    assert(state.values == accepted, "Unsolicited state without an outstanding nonce must be ignored")
end)
check("stale state hides all effects; death and respawn reject previous identity", function()
    now = medicine.states[0].receivedAt + 10001
    for name in pairs(scales) do assert(mod.Medicines[name].getValue(mod, p) == 0) end
    poll()
    local old = payload()
    local replacement = player(0, 99)
    players[0] = replacement
    receive(old)
    assert(medicine.states[0].request == old.request)
    poll(replacement)
    assert(medicine.states[0].player == replacement)
    receive(old)
    assert(not medicine.states[0].values)
    receive(payload(replacement))
    assert(medicine.states[0].values)
    replacement.dead = true
    assert(mod.Medicines.Painkillers.getValue(mod, replacement) == 0)
    Events.OnPlayerDeath.fire(replacement)
    assert(not medicine.states[0])
    replacement.dead = false
    p, players[0] = replacement, replacement
end)
check("sync disable delegates every upstream result; herb disable hides only herbs", function()
    sync, herbs = false, false
    local calls = upstreamCalls
    for name in pairs(scales) do
        if name ~= "BlackSage" and name ~= "CommonMallow" then
            local value, kind, intensity = mod.Medicines[name].getValue(mod, p)
            assert(value == 0.25 and kind == mod.MoodleType.Bad and intensity == 7)
        end
    end
    assert(upstreamCalls == calls + 6)
    for _, name in ipairs({"BlackSage", "CommonMallow"}) do
        local m = moodle(name)
        m.value = 0.5
        mod:updateMoodle(m)
        assert(m:getLevel() == 0)
    end
    poll()
    assert(not medicine.states[0])
    sync, herbs = true, true
    poll()
    receive(payload())
    herbs = false
    near(mod.Medicines.Painkillers.getValue(mod, p), 0.5)
    assert(mod.Medicines.BlackSage.getValue(mod, p) == 0)
    Events.OnMainMenuEnter.fire()
    assert(next(medicine.states) == nil)
end)

check("single-player reads native effects directly without any network requests", function()
    client, server, sync, herbs = false, false, true, true
    local sent = #requests
    p.raw.Antibiotics, p.raw.Painkillers = 25, 2700
    p.raw.BlackSage, p.raw.CommonMallow = 3.5, 2.5
    for _, name in ipairs({"Antibiotics", "Painkillers", "BlackSage", "CommonMallow"}) do
        near(mod.Medicines[name].getValue(mod, p), 0.5)
    end
    poll()
    assert(#requests == sent)
end)

print("Medicine moodles regressions passed: " .. passed .. ".")
