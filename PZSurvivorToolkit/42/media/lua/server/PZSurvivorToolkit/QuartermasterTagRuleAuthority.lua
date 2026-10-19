local Tags = require "PZSurvivorToolkit/ItemTags"
local Rules = require "PZSurvivorToolkit/QuartermasterTagRules"
local Config = require "PZSurvivorToolkit/QuartermasterContainerConfig"
local MODULE = "PZSTQuartermasterTags"

local function integer(value)
    return type(value) == "number" and value == math.floor(value) and math.abs(value) < 10000000
end

function Rules.applyBox(player, args)
    if isClient() or not player or type(args) ~= "table" or not LootSorter
        or type(LootSorter.squareHasDesignation) ~= "function" then return "invalid" end
    local value = args.rule
    if value == false then value = nil end
    local rule = Tags.normalizeRule(value)
    if not rule then return "invalid" end
    local configuration = args.configuration ~= nil and Config.normalize(args.configuration) or nil
    if args.configuration ~= nil and not configuration then return "invalid" end
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
    if configuration then
        if not instanceof(obj, "IsoObject") or instanceof(obj, "BaseVehicle")
            or instanceof(obj, "IsoDeadBody") or instanceof(obj, "IsoWorldInventoryObject")
            or (container.getContainingItem and container:getContainingItem())
            or (container.getParent and container:getParent() ~= obj) then return "invalid" end
        if isServer() and SafeHouse.isSafehouseAllowInteract
            and SafeHouse.isSafehouseAllowInteract(square, player) ~= true then return "denied" end
    end
    local md, key = obj:getModData(), tostring(args.ci)
    local revision = Rules.getBoxRevision(obj, args.ci)
    if args.baseRevision ~= revision then return "stale" end
    if configuration then Config.apply(obj, args.ci, player, configuration) end
    md[Rules.REVISIONS] = md[Rules.REVISIONS] or {}
    md[Rules.REVISIONS][key] = revision + 1
    md[Rules.FIELD] = md[Rules.FIELD] or {}
    md[Rules.FIELD][key] = Tags.ruleActive(rule) and rule or nil
    obj:transmitModData()
    local registry = ModData.getOrCreate("LootSorter_Registry")
    registry.boxes = registry.boxes or {}
    local coord = args.x .. "," .. args.y .. "," .. args.z
    registry.boxes[coord] = LootSorter.squareHasDesignation(square) and true or nil
    if isServer() then ModData.transmit("LootSorter_Registry") end
    return "ok", revision + 1
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= MODULE or command ~= "saveBox" or isClient() then return end
    local verdict = "invalid"
    local ok, result, revision = pcall(Rules.applyBox, player, args)
    if ok then verdict = result end
    if player and type(args) == "table" and integer(args.token) then
        sendServerCommand(player, MODULE, "saved", {token = args.token, verdict = verdict, revision = revision})
    end
end)
return Rules
