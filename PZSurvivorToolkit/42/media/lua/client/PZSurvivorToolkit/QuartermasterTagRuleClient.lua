require "LootSorter_Rpc"
local Rules = require "PZSurvivorToolkit/QuartermasterTagRules"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Config = require "PZSurvivorToolkit/QuartermasterContainerConfig"
local Groups = require "PZSurvivorToolkit/ContainerGroups"

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
        if not client then onDone(verdict, revision, detail); return end
        if verdict == "ok" and (obj:getSquare() ~= square or obj:getObjectIndex() ~= args.object) then verdict = "missing" end
        if verdict == "ok" and (type(revision) ~= "number" or revision ~= args.baseRevision + 1) then verdict = "invalid" end
        if verdict == "ok" and Rules.getBoxRevision(obj, ci) > revision then verdict = "stale" end
        local acceptedConfig, acceptedRule, link = config, rule, Groups.link(obj, ci)
        if verdict == "ok" and type(detail) == "table" and detail.groups ~= nil then
            if type(detail.groups) ~= "table" or type(detail.rule) ~= "table"
                or (detail.groupLink ~= false and type(detail.groupLink) ~= "string") then verdict = "invalid"
            else
                acceptedConfig = detail.configuration ~= nil and Config.normalize(detail.configuration) or nil
                acceptedRule, link = Tags.normalizeRule(detail.rule), detail.groupLink
                if (detail.configuration ~= nil and not acceptedConfig) or not acceptedRule
                    or (config and not acceptedConfig) or (acceptedConfig and acceptedConfig.groupOperation) then verdict = "invalid" end
                local operation = config and config.groupOperation
                if operation and operation.mode ~= "detach" then
                    if type(link) ~= "string" or type(detail.groups.groups) ~= "table"
                        or not detail.groups.groups[link] then verdict = "invalid" end
                end
                if verdict == "ok" then
                    local _, reason = Groups.receive(detail.groups)
                    if reason == "invalid" then verdict = "invalid" end
                end
            end
        elseif verdict == "ok" and ((config and config.groupOperation) or link) then verdict = "invalid" end
        if verdict == "ok" then
            -- Mirror just the accepted fields; an object update may still be in flight.
            local md = obj:getModData()
            if acceptedConfig then Config.apply(obj, ci, player, acceptedConfig) end
            Groups.applyLink(obj, ci, link, type(detail) == "table" and detail.groups and detail.groups.revision)
            md[Rules.FIELD] = md[Rules.FIELD] or {}
            md[Rules.FIELD][tostring(ci)] = Tags.ruleActive(acceptedRule) and acceptedRule or nil
            md[Rules.REVISIONS] = md[Rules.REVISIONS] or {}
            md[Rules.REVISIONS][tostring(ci)] = revision
        end
        onDone(verdict, revision, detail)
    end, player)
end
return Rules
