require "LootSorter_Rpc"
local Rules = require "PZSurvivorToolkit/QuartermasterTagRules"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Config = require "PZSurvivorToolkit/QuartermasterContainerConfig"

function Rules.saveBox(obj, ci, value, player, onDone, baseRevision, configuration)
    local rule = Tags.normalizeRule(value)
    local config = configuration ~= nil and Config.normalize(configuration) or nil
    if not obj or not player or not rule or not obj:getSquare()
        or (configuration ~= nil and not config) then onDone("invalid"); return end
    local square = obj:getSquare()
    local args = {x = square:getX(), y = square:getY(), z = square:getZ(),
        object = obj:getObjectIndex(), ci = ci, rule = rule, baseRevision = baseRevision or Rules.getBoxRevision(obj, ci),
        configuration = config}
    local client = isClient()
    LootSorter.callServer("saveBox", args, function(verdict, detail)
        local revision = type(detail) == "table" and detail.revision or nil
        if verdict == nil then verdict = "timeout" end
        if not client then onDone(verdict, revision); return end
        if verdict == "ok" and (obj:getSquare() ~= square or obj:getObjectIndex() ~= args.object) then verdict = "missing" end
        if verdict == "ok" and (type(revision) ~= "number" or revision ~= args.baseRevision + 1) then verdict = "invalid" end
        if verdict == "ok" and Rules.getBoxRevision(obj, ci) > revision then verdict = "stale" end
        if verdict == "ok" then
            -- Mirror just the accepted fields; an object update may still be in flight.
            local md = obj:getModData()
            if config then Config.apply(obj, ci, player, config) end
            md[Rules.FIELD] = md[Rules.FIELD] or {}
            md[Rules.FIELD][tostring(ci)] = Tags.ruleActive(rule) and rule or nil
            md[Rules.REVISIONS] = md[Rules.REVISIONS] or {}
            md[Rules.REVISIONS][tostring(ci)] = revision
        end
        onDone(verdict, revision)
    end, player)
end
return Rules
