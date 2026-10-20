-- LootSorter presets: pure logic for named category/item bundles ("presets"), resolving a box's
-- EFFECTIVE designation and checking optimistic edits. Persistence belongs to
-- PZSurvivorToolkit/QuartermasterPresets; this module makes no engine calls.
--
-- A preset is flat: { cats = { [categoryName]=true }, items = { [displayName]=true } }.
-- The preset store is a map: presets = { [presetName] = <preset> }.
-- A box records which presets it uses as a set { [presetName]=true }; its effective cats/items are its
-- own manual sets UNION the cats/items of every preset it uses. Presets are "linked": editing a preset
-- changes every box that uses it, because resolution reads the live store at sort time. Deleted or
-- missing presets contribute nothing (a box's dangling reference just resolves to empty).

LootSorter = LootSorter or {}

local function copySet(source)
    local out = {}
    if source then for key, value in pairs(source) do if value then out[key] = true end end end
    return out
end

local function unionInto(target, source)
    if source then for key, value in pairs(source) do if value then target[key] = true end end end
end

-- sorted list of preset names (stable, alphabetical)
function LootSorter.presetNames(presets)
    local names = {}
    if presets then for name in pairs(presets) do names[#names + 1] = name end end
    table.sort(names)
    return names
end

-- Should a write be applied, and if not, why? `existing` is the stored preset or nil; the claims
-- come from the client, which is the only side that knows whether it meant to create or edit.
function LootSorter.presetWriteVerdict(existing, expectExisting, baseRev, baseGen)
    local exists = existing ~= nil
    if expectExisting and not exists then return "deleted" end
    if not expectExisting and exists then return "nameTaken" end
    if not exists then return "ok" end

    -- A preset deleted and remade under the same name restarts the revision at 1, so an editor
    -- holding 1 would sail through the revision check. The generation is what catches it. Both
    -- sides must have one: a store or a link predating generations matches by name alone.
    local currentGen = existing.gen
    local claimedGen = tonumber(baseGen)
    if currentGen and claimedGen and claimedGen ~= currentGen then return "stale" end

    -- Normalised, not compared raw: a nil would never equal 0, so every edit of a revision-less
    -- preset would be refused as stale, permanently.
    if (tonumber(baseRev) or 0) ~= (existing.rev or 0) then return "stale" end
    return "ok"
end

-- A link carries the generation it was made against, so a name that was deleted and remade is a
-- different preset. Legacy links are plain `true`, and legacy presets have no generation.
function LootSorter.linkResolves(preset, link)
    if not preset or not link then return false end
    if link == true or preset.gen == nil then return true end
    -- Normalised like the two verdicts do: links cross a wire, so a type difference must not read
    -- as a different preset in resolution or the container editor.
    return tonumber(link) == tonumber(preset.gen)
end

-- A delete names the preset the user was looking at. If that name now holds a different one, deleting
-- would destroy something they never saw. Missing generation on either side falls back to the name.
function LootSorter.presetDeleteVerdict(existing, baseGen)
    if existing == nil then return "gone" end
    local currentGen = existing.gen
    local claimedGen = tonumber(baseGen)
    if currentGen and claimedGen and claimedGen ~= currentGen then return "stale" end
    return "ok"
end

-- a box's EFFECTIVE designation: its manual sets unioned with the cats/items of every preset it uses.
-- usedPresets is a set { [presetName]=true }. Returns two fresh sets; the caller's inputs are untouched.
function LootSorter.resolveEffective(manualCats, manualItems, usedPresets, presets)
    local effectiveCats = copySet(manualCats)
    local effectiveItems = copySet(manualItems)
    if usedPresets and presets then
        for name, link in pairs(usedPresets) do
            local preset = presets[name]
            if LootSorter.linkResolves(preset, link) then
                unionInto(effectiveCats, preset.cats)
                unionInto(effectiveItems, preset.items)
            end
        end
    end
    return effectiveCats, effectiveItems
end
