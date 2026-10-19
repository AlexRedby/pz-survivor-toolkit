local Rules = require "PZSurvivorToolkit/QuartermasterTagRules"
local Tags = require "PZSurvivorToolkit/ItemTags"
local MODULE, nextToken, pending = "PZSTQuartermasterTags", 0, {}

function Rules.saveBox(obj, ci, value, player, onDone, baseRevision)
    local rule = Tags.normalizeRule(value)
    if not obj or not player or not rule or not obj:getSquare() then onDone("invalid"); return end
    local square = obj:getSquare()
    local args = {x = square:getX(), y = square:getY(), z = square:getZ(),
        object = obj:getObjectIndex(), ci = ci, rule = rule, baseRevision = baseRevision or Rules.getBoxRevision(obj, ci)}
    if not isClient() then
        local ok, verdict, revision = pcall(Rules.applyBox, player, args)
        onDone(ok and verdict or "invalid", revision)
        return
    end
    nextToken = nextToken + 1
    args.token = nextToken
    pending[nextToken] = {sent = getTimestampMs(), callback = function(verdict, revision)
        if verdict == "ok" and (obj:getSquare() ~= square or obj:getObjectIndex() ~= args.object) then verdict = "missing" end
        if verdict == "ok" and (type(revision) ~= "number" or revision ~= args.baseRevision + 1) then verdict = "invalid" end
        if verdict == "ok" and Rules.getBoxRevision(obj, ci) > revision then verdict = "stale" end
        if verdict == "ok" then
            -- Native Save transmits this same ModData before the object update may have arrived.
            local md = obj:getModData()
            md[Rules.FIELD] = md[Rules.FIELD] or {}
            md[Rules.FIELD][tostring(ci)] = Tags.ruleActive(rule) and rule or nil
            md[Rules.REVISIONS] = md[Rules.REVISIONS] or {}
            md[Rules.REVISIONS][tostring(ci)] = revision
        end
        onDone(verdict, revision)
    end}
    sendClientCommand(player, MODULE, "saveBox", args)
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= MODULE or command ~= "saved" or type(args) ~= "table" then return end
    local request = pending[args.token]
    if request then pending[args.token] = nil; request.callback(args.verdict, args.revision) end
end)
Events.OnTick.Add(function()
    if not isClient() then return end
    local now, expired = getTimestampMs(), {}
    for token, request in pairs(pending) do
        if now - request.sent > 15000 then expired[#expired + 1] = token end
    end
    for _, token in ipairs(expired) do
        local request = pending[token]
        pending[token] = nil; request.callback("timeout")
    end
end)
Events.OnReceiveGlobalModData.Add(function(key, value)
    if type(value) ~= "table" then return end
    if key == Rules.STORE then Rules.received = value.presets or {}
    elseif key ~= "LootSorter_Presets" then return end
    local picker = LootSorter and LootSorter._presetEditor
    if picker and not picker.toolkitTagRuleTouched then
        local presets = key == "LootSorter_Presets" and value.presets or LootSorter.getPresetStore()
        picker.toolkitTagRule = Rules.getPreset(picker.presetName, presets and presets[picker.presetName])
    end
end)
Events.OnGameStart.Add(function()
    pending = {}
end)
return Rules
