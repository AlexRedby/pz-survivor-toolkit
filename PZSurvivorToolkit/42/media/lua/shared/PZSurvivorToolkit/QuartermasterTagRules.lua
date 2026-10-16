local Tags = require "PZSurvivorToolkit/ItemTags"

local Rules = {}
PZSurvivorToolkit.QuartermasterTagRules = Rules
local FIELD, STORE, FILE = "PZSTQuartermasterTagRules", "PZSTQuartermasterTagRules", "PZSTQuartermasterTagRules.txt"
local ANY = "__PZST_ANY__"
local byCategories = setmetatable({}, {__mode = "k"})
local gatheringPlayer
local REVISIONS = FIELD .. "Revisions"

local function copy(rule)
    return rule and Tags.normalizeRule(rule) or nil
end

function Rules.getBox(obj, ci)
    local md = obj and obj:getModData()
    return copy(md and type(md[FIELD]) == "table" and md[FIELD][tostring(ci)])
end

function Rules.getBoxRevision(obj, ci)
    local md = obj and obj:getModData()
    return tonumber(md and type(md[REVISIONS]) == "table" and md[REVISIONS][tostring(ci)]) or 0
end

function Rules.presetsSynced()
    return not isClient() or Rules.received ~= nil
end

function Rules.presetStore()
    if isClient() then return Rules.received or {} end
    if isServer() then
        local store = ModData.getOrCreate(STORE)
        store.presets = store.presets or {}
        return store.presets
    end
    if Rules.localPresets then return Rules.localPresets end
    Rules.localPresets = {}
    local reader = getFileReader(FILE, false)
    if reader then
        local lines, line = {}, reader:readLine()
        while line do lines[#lines + 1] = line; line = reader:readLine() end
        reader:close()
        local stored = LootSorter.presetDeserialize(table.concat(lines, "\n"))
        for name, entry in pairs(stored) do
            local rule = {mode = entry.items[ANY] and "any" or "all", include = {}, exclude = {}}
            for id in pairs(entry.cats) do rule.include[#rule.include + 1] = id end
            for id in pairs(entry.items) do if id ~= ANY then rule.exclude[#rule.exclude + 1] = id end end
            rule = Tags.normalizeRule(rule)
            if rule then Rules.localPresets[name] = {rule = rule, gen = entry.gen} end
        end
    end
    return Rules.localPresets
end

function Rules.persistPresets()
    if isServer() then ModData.transmit(STORE); return end
    if isClient() then return end
    local records = {}
    for name, entry in pairs(Rules.presetStore()) do
        local rule = copy(entry.rule)
        if rule and Tags.ruleActive(rule) then
            local record = {cats = {}, items = {}, gen = entry.gen}
            for _, id in ipairs(rule.include) do record.cats[id] = true end
            for _, id in ipairs(rule.exclude) do record.items[id] = true end
            if rule.mode == "any" then record.items[ANY] = true end
            records[name] = record
        end
    end
    local writer = getFileWriter(FILE, true, false)
    if not writer then error("Cannot save Quartermaster tag rules") end
    writer:write(LootSorter.presetSerialize(records)); writer:close()
end

function Rules.getPreset(name, preset)
    local entry = Rules.presetStore()[name]
    if type(entry) ~= "table" or not preset or tostring(entry.gen) ~= tostring(preset.gen) then return nil end
    return copy(entry.rule)
end

local function addMatches(cats, rule)
    if not Tags.enabled() or not rule or not Tags.ruleActive(rule) then return end
    for _, category in ipairs(LootSorter.getCategories()) do
        if Tags.matchesRule(category, rule) then cats[category] = true end
    end
end

-- Core's private sorter reads the public resolver, so index the exact tables it passes there.
function Rules.indexSquare(square, player)
    if not square then return end
    if isClient() and (not player or not LootSorter.canLootSquare(square, player)) then return end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if obj and obj:hasModData() then
            local md = obj:getModData()
            for _, cats in pairs(md.LSBox or {}) do byCategories[cats] = nil end
            for ci, rule in pairs(md[FIELD] or {}) do
                if Tags.ruleActive(copy(rule)) then
                    md.LSBox = md.LSBox or {}
                    md.LSBox[ci] = md.LSBox[ci] or {}
                    byCategories[md.LSBox[ci]] = rule
                end
            end
        end
    end
end

function Rules.installShared()
    if not LootSorter or LootSorter.pzstTagRuleResolver or not LootSorter.resolveEffective
        or not LootSorter.modDataHasDesignation then return end
    LootSorter.pzstTagRuleResolver = true
    local designated, resolve = LootSorter.modDataHasDesignation, LootSorter.resolveEffective
    LootSorter.modDataHasDesignation = function(md)
        if designated(md) then return true end
        for _, rule in pairs(type(md) == "table" and md[FIELD] or {}) do
            if Tags.ruleActive(copy(rule)) then return true end
        end
        return false
    end
    LootSorter.resolveEffective = function(cats, items, links, presets)
        local resultCats, resultItems = resolve(cats, items, links, presets)
        addMatches(resultCats, copy(byCategories[cats]))
        for name, link in pairs(links or {}) do
            local preset = presets and presets[name]
            if LootSorter.linkResolves(preset, link) then addMatches(resultCats, Rules.getPreset(name, preset)) end
        end
        return resultCats, resultItems
    end
end

function Rules.installClient()
    Rules.installShared()
    if not LootSorter or LootSorter.pzstTagRuleClient or not LootSorter.getRegistry
        or not LootSorter.findDesignatedOnSquare then return end
    LootSorter.pzstTagRuleClient = true
    if LootSorter.requestPresets then
        local request = LootSorter.requestPresets
        LootSorter.requestPresets = function(...)
            if isClient() then ModData.request(STORE) end
            return request(...)
        end
    end
    for _, name in ipairs({"gatherBoxes", "gatherBoxesOrWarn"}) do
        local gather = LootSorter[name]
        if gather then
            LootSorter[name] = function(player, ...)
                local previous = gatheringPlayer
                gatheringPlayer = player
                local ok, boxes, synced = pcall(gather, player, ...)
                gatheringPlayer = previous
                if not ok then error(boxes) end
                return boxes, synced
            end
        end
    end
    local registry, find = LootSorter.getRegistry, LootSorter.findDesignatedOnSquare
    LootSorter.getRegistry = function(...)
        local result = registry(...)
        byCategories = setmetatable({}, {__mode = "k"})
        local cell = getCell()
        for key in pairs(result) do
            local x, y, z = LootSorter.parseCoordKey(key)
            local current = gatheringPlayer and gatheringPlayer:getCurrentSquare()
            local inRange = not current or (math.abs(x and x - current:getX() or math.huge) <= (LootSorter.MAX_TILES or 50)
                and math.abs(y - current:getY()) <= (LootSorter.MAX_TILES or 50)
                and math.abs(z - current:getZ()) <= (LootSorter.MAX_LEVELS or 0))
            if x and cell and inRange then Rules.indexSquare(cell:getGridSquare(x, y, z), gatheringPlayer) end
        end
        return result
    end
    LootSorter.findDesignatedOnSquare = function(square, ...)
        local manifest = LootSorter._manifestWin
        local player = gatheringPlayer or getSpecificPlayer(manifest and manifest.playerNum or 0)
        if isClient() and (not player or not LootSorter.canLootSquare(square, player)) then return {} end
        Rules.indexSquare(square, player)
        return find(square, ...)
    end
    if LootSorter.copyDesignation then
        local copyDesignation, paste = LootSorter.copyDesignation, LootSorter.pasteDesignation
        LootSorter.copyDesignation = function(obj, ci)
            local result = copyDesignation(obj, ci)
            result.pzstTagRule = Rules.getBox(obj, ci)
            return result
        end
        LootSorter.pasteDesignation = function(obj, ci)
            local clipboard = LootSorter.clipboard
            if not clipboard then return false end
            if not Tags.ruleActive(clipboard.pzstTagRule) and not Rules.getBox(obj, ci) then return paste(obj, ci) end
            local snapshot = {priority = clipboard.priority, pzstTagRule = copy(clipboard.pzstTagRule)}
            for _, field in ipairs({"cats", "items", "presets"}) do
                snapshot[field] = {}
                for key, value in pairs(clipboard[field] or {}) do snapshot[field][key] = value end
            end
            Rules.saveBox(obj, ci, snapshot.pzstTagRule, getSpecificPlayer(0), function(verdict)
                if verdict == "ok" then
                    local current = LootSorter.clipboard
                    LootSorter.clipboard = snapshot
                    local ok, result = pcall(paste, obj, ci)
                    LootSorter.clipboard = current
                    if not ok then error(result) end
                elseif LootSorter.notify then
                    LootSorter.notify(getSpecificPlayer(0), getText("UI_PZST_QMTagRuleFailed", tostring(verdict)))
                end
            end)
            return true
        end
        local has, describe = LootSorter.hasClipboardContent, LootSorter.describeClipboard
        LootSorter.hasClipboardContent = function()
            return has() or Tags.ruleActive(LootSorter.clipboard and LootSorter.clipboard.pzstTagRule)
        end
        LootSorter.describeClipboard = function()
            local text = describe()
            if Tags.ruleActive(LootSorter.clipboard and LootSorter.clipboard.pzstTagRule) then
                return (text and text ~= "empty" and text .. ", " or "") .. getText("UI_PZST_QMTagRule")
            end
            return text
        end
    end
end

Rules.FIELD, Rules.STORE, Rules.REVISIONS = FIELD, STORE, REVISIONS
return Rules
