local Tags = require "PZSurvivorToolkit/ItemTags"
local Rules = require "PZSurvivorToolkit/QuartermasterTagRules"
local MODULE = "PZSTQuartermasterTags"

local function integer(value)
    return type(value) == "number" and value == math.floor(value) and math.abs(value) < 10000000
end

function Rules.applyBox(player, args)
    if isClient() or not player or type(args) ~= "table" or not LootSorter
        or not LootSorter.pzstTagRuleResolver or type(LootSorter.squareHasDesignation) ~= "function" then return "invalid" end
    local value = args.rule
    if value == false then value = nil end
    local rule = Tags.normalizeRule(value)
    if not rule then return "invalid" end
    if not integer(args.x) or not integer(args.y) or not integer(args.z)
        or not integer(args.object) or args.object < 0 or not integer(args.ci) or args.ci < 0
        or not integer(args.baseRevision) or args.baseRevision < 0 then return "invalid" end
    local square = getCell():getGridSquare(args.x, args.y, args.z)
    local current = player:getCurrentSquare()
    if not square or not current or current:getZ() ~= args.z
        or math.abs(current:getX() - args.x) > 1 or math.abs(current:getY() - args.y) > 1 then return "unreachable" end
    if current ~= square and current:isBlockedTo(square) then return "unreachable" end
    if isServer() then
        if not SafeHouse or not SafeHouse.isSafehouseAllowLoot
            or SafeHouse.isSafehouseAllowLoot(square, player) ~= true then return "denied" end
    end
    local objects = square:getObjects()
    if args.object >= objects:size() then return "missing" end
    local obj = objects:get(args.object)
    if not obj or obj:getSquare() ~= square or args.ci >= obj:getContainerCount() then return "missing" end
    local container = obj:getContainerByIndex(args.ci)
    if not container or container:isLockedToCharacter(player) then return "denied" end
    local md, key = obj:getModData(), tostring(args.ci)
    local revision = Rules.getBoxRevision(obj, args.ci)
    if args.baseRevision ~= revision then return "stale" end
    md[Rules.REVISIONS] = md[Rules.REVISIONS] or {}
    md[Rules.REVISIONS][key] = revision + 1
    md[Rules.FIELD] = md[Rules.FIELD] or {}
    md[Rules.FIELD][key] = Tags.ruleActive(rule) and rule or nil
    if Tags.ruleActive(rule) then
        md.LSBox = md.LSBox or {}
        md.LSBox[key] = md.LSBox[key] or {}
    end
    obj:transmitModData()
    local registry = ModData.getOrCreate("LootSorter_Registry")
    registry.boxes = registry.boxes or {}
    local coord = args.x .. "," .. args.y .. "," .. args.z
    registry.boxes[coord] = LootSorter.squareHasDesignation(square) and true or nil
    if isServer() then ModData.transmit("LootSorter_Registry") end
    return "ok", revision + 1
end

function Rules.installAuthority()
    Rules.installShared()
    if not LootSorter or LootSorter.pzstTagRuleAuthority or not LootSorter.serverFns
        or not LootSorter.serverFns.putPreset then return end
    LootSorter.pzstTagRuleAuthority = true
    if isServer() then Rules.presetStore() end
    local put, remove = LootSorter.serverFns.putPreset, LootSorter.serverFns.removePreset
    LootSorter.serverFns.putPreset = function(player, args)
        local rule
        if type(args) == "table" and args.pzstTagRule ~= nil then
            local value = args.pzstTagRule
            if value == false then value = nil end
            rule = Tags.normalizeRule(value)
            if not rule then return "invalid" end
        end
        local verdict, detail = put(player, args)
        if verdict == "ok" and type(args) == "table" and type(args.name) == "string" then
            local presets = isServer() and ModData.getOrCreate("LootSorter_Presets").presets
                or LootSorter.getPresetStore()
            local preset = presets and presets[args.name]
            local store = Rules.presetStore()
            if preset and rule then
                store[args.name] = Tags.ruleActive(rule) and {rule = rule, gen = preset.gen} or nil
                Rules.persistPresets()
            elseif store[args.name] and not Rules.getPreset(args.name, preset) then
                store[args.name] = nil
                Rules.persistPresets()
            end
        end
        return verdict, detail
    end
    LootSorter.serverFns.removePreset = function(player, args)
        local verdict, detail = remove(player, args)
        if verdict == "ok" and args and Rules.presetStore()[args.name] then
            Rules.presetStore()[args.name] = nil; Rules.persistPresets()
        end
        return verdict, detail
    end
end

Events.OnInitGlobalModData.Add(Rules.installAuthority)
Events.OnGameStart.Add(Rules.installAuthority)
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= MODULE or command ~= "saveBox" or isClient() then return end
    Rules.installAuthority()
    local verdict = "invalid"
    local ok, result, revision = pcall(Rules.applyBox, player, args)
    if ok then verdict = result end
    if player and type(args) == "table" and integer(args.token) then
        sendServerCommand(player, MODULE, "saved", {token = args.token, verdict = verdict, revision = revision})
    end
end)
return Rules
