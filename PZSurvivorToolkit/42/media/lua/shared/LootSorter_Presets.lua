-- LootSorter presets: pure logic for named category/item bundles ("presets"), resolving a box's
-- EFFECTIVE designation, and (de)serializing the store. NO engine calls -- the caller loads/saves the
-- plain store table (Core persists it to a per-machine file so presets survive across saves/worlds).
--
-- A preset is flat: { cats = { [categoryName]=true }, items = { [displayName]=true } }.
-- The preset store is a map: presets = { [presetName] = <preset> }.
-- A box records which presets it uses as a set { [presetName]=true }; its effective cats/items are its
-- own manual sets UNION the cats/items of every preset it uses. Presets are "linked": editing a preset
-- changes every box that uses it, because resolution reads the live store at sort time. Deleted or
-- missing presets contribute nothing (a box's dangling reference just resolves to empty).

LootSorter = LootSorter or {}

LootSorter.PRESET_FORMAT_CURRENT_VERSION = 2
LootSorter.PRESET_ITEM_FULLNAME_VERSION = 2

local function copySet(source)
    local out = {}
    if source then for key, value in pairs(source) do if value then out[key] = true end end end
    return out
end

local function unionInto(target, source)
    if source then for key, value in pairs(source) do if value then target[key] = true end end end
end

local function sortedKeys(set)
    local keys = {}
    if set then for key, value in pairs(set) do if value then keys[#keys + 1] = key end end end
    table.sort(keys)
    return keys
end

local function skipSpace(text, position)
    local _, stop = text:find("^%s*", position)
    return stop + 1
end

local function parseQuotedString(text, position)
    if text:sub(position, position) ~= '"' then return nil, position end
    local characters, cursor = {}, position + 1
    while true do
        local character = text:sub(cursor, cursor)
        if character == "" then return nil, cursor end
        if character == '"' then return table.concat(characters), cursor + 1 end
        if character == "\\" then
            local digits = text:match("^%d%d?%d?", cursor + 1)
            if digits then
                characters[#characters + 1] = string.char(tonumber(digits))
                cursor = cursor + 1 + #digits
            else
                local escape = text:sub(cursor + 1, cursor + 1)
                if escape == "" then return nil, cursor end
                if escape == "n" then characters[#characters + 1] = "\n"
                elseif escape == "r" then characters[#characters + 1] = "\r"
                elseif escape == "t" then characters[#characters + 1] = "\t"
                else characters[#characters + 1] = escape
                end
                cursor = cursor + 2
            end
        else
            characters[#characters + 1] = character
            cursor = cursor + 1
        end
    end
end

local parseValue, parseTable

parseTable = function(text, position)
    if text:sub(position, position) ~= "{" then return nil, position end
    local result, cursor = {}, skipSpace(text, position + 1)
    while text:sub(cursor, cursor) ~= "}" do
        local key
        if text:sub(cursor, cursor) == "[" then
            cursor = skipSpace(text, cursor + 1)
            if text:sub(cursor, cursor) == '"' then
                key, cursor = parseQuotedString(text, cursor)
            else
                local numberText = text:match("^%-?%d+%.?%d*", cursor)
                if numberText then key, cursor = tonumber(numberText), cursor + #numberText end
            end
            if key == nil then return nil, cursor end
            cursor = skipSpace(text, cursor)
            if text:sub(cursor, cursor) ~= "]" then return nil, cursor end
            cursor = skipSpace(text, cursor + 1)
        else
            key = text:match("^[%a_][%w_]*", cursor)
            if not key then return nil, cursor end
            cursor = skipSpace(text, cursor + #key)
        end
        if text:sub(cursor, cursor) ~= "=" then return nil, cursor end
        cursor = skipSpace(text, cursor + 1)
        local value
        value, cursor = parseValue(text, cursor)
        if value == nil then return nil, cursor end
        result[key] = value
        cursor = skipSpace(text, cursor)
        if text:sub(cursor, cursor) == "," then cursor = skipSpace(text, cursor + 1) end
    end
    return result, cursor + 1
end

parseValue = function(text, position)
    local firstCharacter = text:sub(position, position)
    if firstCharacter == '"' then return parseQuotedString(text, position) end
    if firstCharacter == "{" then return parseTable(text, position) end
    if text:sub(position, position + 3) == "true" then return true, position + 4 end
    if text:sub(position, position + 4) == "false" then return false, position + 5 end
    local digits = text:match("^%-?%d+%.?%d*", position)
    if digits then return tonumber(digits), position + #digits end
    return nil, position
end

-- sorted list of preset names (stable, alphabetical)
function LootSorter.presetNames(presets)
    local names = {}
    if presets then for name in pairs(presets) do names[#names + 1] = name end end
    table.sort(names)
    return names
end

-- create/overwrite a preset from the given cats/items sets (stored as INDEPENDENT copies, so later
-- mutation of the caller's selection tables can't bleed into the saved preset)
-- newGen is only used when creating; editing keeps the preset's existing generation. The caller
-- supplies it because it must not repeat after a delete -- deriving it from the store would hand a
-- reused name the number it just gave up, which is the collision generations exist to prevent.
function LootSorter.presetPut(presets, name, cats, items, newGen)
    if not presets or not name or name == "" then return end
    local existing = presets[name]
    presets[name] = {
        cats = copySet(cats),
        items = copySet(items),
        gen = (existing and existing.gen) or newGen,
        -- carried, not used here: a write that silently dropped these would disable the server's
        -- conflict detection without erroring.
        rev = existing and existing.rev,
        createdBy = existing and existing.createdBy,
    }
end

-- remove a preset (a no-op if it doesn't exist)
function LootSorter.presetRemove(presets, name)
    if presets then presets[name] = nil end
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
    -- Normalised like the two verdicts do: both sides cross a wire, and this is the predicate the
    -- prune DELETES on, so a type difference must not read as a different preset.
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

-- Serialize the whole store to a self-contained Lua chunk ("return { ... }"), deterministically
-- (names + keys sorted) so the on-disk file is stable and diff-friendly. Keys are %q-quoted, so
-- category/item names with spaces or punctuation round-trip intact.
function LootSorter.presetSerialize(presets)
    local parts = { string.format("return { version = %d, presets = {\n", LootSorter.PRESET_FORMAT_CURRENT_VERSION) }
    for _, name in ipairs(LootSorter.presetNames(presets)) do
        local preset = presets[name]
        parts[#parts + 1] = string.format("  [%q] = { cats = {", name)
        for _, cat in ipairs(sortedKeys(preset.cats)) do parts[#parts + 1] = string.format(" [%q]=true,", cat) end
        parts[#parts + 1] = " }, items = {"
        for _, itemName in ipairs(sortedKeys(preset.items)) do parts[#parts + 1] = string.format(" [%q]=true,", itemName) end
        parts[#parts + 1] = " }"
        if preset.gen then parts[#parts + 1] = string.format(", gen = %d", preset.gen) end
        parts[#parts + 1] = " },\n"
    end
    parts[#parts + 1] = "} }\n"
    return table.concat(parts)
end

-- Parse a chunk from presetSerialize back into a clean store. PZ 42.20.4 removed loadstring/load, so
-- this walks the text with a small hand-rolled table-literal parser instead of executing it as code --
-- and still SANITIZES the result -- only string names -> { cats, items } of string->true survive -- so
-- a corrupt or hand-edited file can't inject anything. Returns {} on any error or empty input.
-- Also returns the format version as a second value: 1 (legacy) means the parsed chunk's root WAS the
-- presets map; 2 means the root was { version = 2, presets = <map> } and has already been unwrapped
-- here. Either way the first return is the flat presets map -- callers that only need that can ignore
-- the second value entirely.
function LootSorter.presetDeserialize(text)
    if not text or text == "" then return {}, 1 end
    local afterReturn = text:match("^%s*return%s*()")
    local result
    if afterReturn then
        local success
        success, result = pcall(parseValue, text, afterReturn)
        if not success then result = nil end
    end
    if type(result) ~= "table" then return {}, 1 end
    local version = 1
    if type(result.version) == "number" and type(result.presets) == "table" then
        version = result.version
        result = result.presets
    end
    local clean = {}
    for name, preset in pairs(result) do
        if type(name) == "string" and type(preset) == "table" then
            local cats, items = {}, {}
            if type(preset.cats) == "table" then
                for key, value in pairs(preset.cats) do if type(key) == "string" and value then cats[key] = true end end
            end
            if type(preset.items) == "table" then
                for key, value in pairs(preset.items) do if type(key) == "string" and value then items[key] = true end end
            end
            clean[name] = { cats = cats, items = items, gen = tonumber(preset.gen) }
        end
    end
    return clean, version
end
