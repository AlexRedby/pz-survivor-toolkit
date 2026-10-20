-- The preset store and the two commands that mutate it.
--
-- In server/ because this is where the data is owned. That folder does NOT gate execution -- it loads
-- on multiplayer clients too -- so isServer()/isAuthority() below still does the real gating. What it
-- does give is tier order: shared/ always loads first, so serverFn and the verdicts are already there.
--
-- No isClient() early return on purpose: the caller half (LootSorter.putPreset) is assigned here and
-- has to exist on a client, which only sends the command rather than running it.
LootSorter = LootSorter or {}

local Tags = require "PZSurvivorToolkit/ItemTags"
local Presets = require "PZSurvivorToolkit/QuartermasterPresets"

-- Only string -> true survives, so a malformed or hostile packet can't put arbitrary values in a
-- table every client will read.
local function cleanSet(value)
    local out = {}
    if type(value) ~= "table" then return out end
    for key, on in pairs(value) do
        if type(key) == "string" and on then out[key] = true end
    end
    return out
end

-- The write is refused if either claim is wrong: expectExisting means someone deleted or created the
-- name meanwhile, baseRev/baseGen mean someone else changed it while this editor was open.
LootSorter.putPreset = LootSorter.serverFn("putPreset", function(player, args)
    local rule
    if type(args) == "table" and args.pzstTagRule ~= nil then
        local value = args.pzstTagRule
        if value == false then value = nil end
        rule = Tags.normalizeRule(value)
        if not rule then return "invalid" end
    end
    local name = type(args) == "table" and args.name
    if type(name) ~= "string" or name == "" then return "ok" end
    return Presets.transaction(function(presets, rules)
        local existing = presets[name]
        local verdict = LootSorter.presetWriteVerdict(existing, args.expectExisting or false,
            args.baseRev or 0, args.baseGen)
        if verdict ~= "ok" then
            LootSorter.DBG(("preset %s refused: %s"):format(name, verdict))
            return verdict, {name = name, action = "save"}
        end
        local exists = existing ~= nil
        local preset = {
            cats = cleanSet(args.cats),
            items = cleanSet(args.items),
            rev = (exists and (existing.rev or 0) or 0) + 1,
            gen = (exists and existing.gen) or getTimestampMs(),
            createdBy = (exists and existing.createdBy)
                or (player and player:getUsername()) or nil,
        }
        presets[name] = preset
        local rulesChanged = false
        if rule then
            rules[name] = Tags.ruleActive(rule) and {rule = rule, gen = preset.gen} or nil
            rulesChanged = true
        elseif rules[name] then
            local entry = rules[name]
            if type(entry) ~= "table" or tostring(entry.gen) ~= tostring(preset.gen)
                or not entry.rule or not Tags.normalizeRule(entry.rule) then
                rules[name] = nil
                rulesChanged = true
            end
        end
        LootSorter.DBG("preset saved: " .. name)
        return "ok", nil, true, rulesChanged
    end)
end)

-- baseGen identifies the preset shown to the editor, protecting a deleted/remade name.
LootSorter.removePreset = LootSorter.serverFn("removePreset", function(player, args)
    local name = type(args) == "table" and args.name
    if type(name) ~= "string" or name == "" then return "ok" end
    return Presets.transaction(function(presets, rules)
        local verdict = LootSorter.presetDeleteVerdict(presets[name], args.baseGen)
        if verdict ~= "ok" and verdict ~= "gone" then
            LootSorter.DBG(("preset %s delete refused: %s"):format(name, verdict))
            return verdict, {name = name, action = "delete"}
        end
        local rulesChanged = rules[name] ~= nil
        presets[name], rules[name] = nil, nil
        if verdict == "ok" then LootSorter.DBG("preset removed: " .. name) end
        return "ok", nil, verdict == "ok", rulesChanged
    end)
end)

-- isServer, not isAuthority: single-player's store is the file,
-- so creating the world table there would leave an empty one in the save and report a count of 0
-- however many presets the file holds.
if isServer() then
    -- Make sure the table exists (and so is saved with the world) before anyone writes a preset.
    LootSorter.addOrReplaceHandler(Events.OnInitGlobalModData, "_presetStoreInit", function()
        local presets = Presets.native()
        local count = 0
        for _ in pairs(presets) do count = count + 1 end
        LootSorter.DBG("preset store ready, " .. count .. " preset(s)")
        Presets.publish()
    end)
end

-- Unconditional, and NOT isServer-gated: without it a module that failed to load looks identical to
-- an empty store, and that has to be visible in single-player too.
if LootSorter.isAuthority() then
    print("[Quartermaster] preset commands loaded")
end
