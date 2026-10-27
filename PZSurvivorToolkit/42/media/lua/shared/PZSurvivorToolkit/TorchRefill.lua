local Retention = require "PZSurvivorToolkit/ItemRetention"
if PZSurvivorToolkit.TorchRefill then return PZSurvivorToolkit.TorchRefill end
local Refill = {}
PZSurvivorToolkit.TorchRefill = Refill
Refill.MODULE = "PZSurvivorToolkitTorchRefill"
local original = RecipeCodeOnCreate and RecipeCodeOnCreate.refillBlowTorch
local observer, verifiedBody

local function supported(recipe)
    if not observer or RecipeCodeOnCreate.refillBlowTorch ~= observer or not recipe
        or recipe:getScriptObjectFullType() ~= "Base.RefillBlowTorch" then return false end
    local bodies = recipe:getLoadedScriptBodies()
    if not bodies or bodies:size() ~= 2 or bodies:get(0) ~= "pz-vanilla" then return false end
    local source = bodies:get(1)
    if source == verifiedBody then return true end
    local body = source:gsub("%s+", "")
    if #body ~= 300 then return false end
    local a, b = 1, 0
    for i = 1, #body do
        a = (a + body:byte(i)) % 65521
        b = (b + a) % 65521
    end
    if b * 65536 + a ~= 2207478622 then return false end
    verifiedBody = source
    return true
end

function Refill.supports(recipe)
    local ok, result = pcall(supported, recipe)
    return ok and result == true
end

local function completed(data, character)
    if isClient() or not character or not Refill.supports(data:getRecipe())
        or isServer() and not instanceof(character, "IsoPlayer") then return end
    local consumed, created, kept = data:getAllConsumedItems(), data:getAllCreatedItems(), data:getAllKeepInputItems()
    if consumed:size() ~= 1 or created:size() ~= 1 or kept:size() ~= 1 then return end
    local source, output, tank = consumed:get(0), created:get(0), kept:get(0)
    if not instanceof(source, "DrainableComboItem") or not instanceof(output, "DrainableComboItem")
        or not instanceof(tank, "DrainableComboItem") or source == output
        or source:getFullType() ~= "Base.BlowTorch" or output:getFullType() ~= "Base.BlowTorch"
        or tank:getFullType() ~= "Base.PropaneTank" then return end
    local sourceID, outputID = source:getID(), output:getID()
    if type(sourceID) ~= "number" or type(outputID) ~= "number" or sourceID == outputID
        or sourceID ~= math.floor(sourceID) or outputID ~= math.floor(outputID) then return end
    -- The native callback owns fuel/condition. Copy only the user's retention intent.
    if Retention.isRetained(source) then
        Retention.apply(output, true)
        if isServer() then
            if output:getContainer() then syncItemModData(character, output) end
            local locator = Retention.locate(output, character)
            if locator then
                sendServerCommand(Retention.MODULE, "State", {owner = character:getOnlineID(),
                    retained = true, items = {locator}})
            end
        end
    end
    local args = {sourceID = sourceID, outputID = outputID}
    if isServer() then
        args.onlineID = character:getOnlineID()
        sendServerCommand(character, Refill.MODULE, "Refilled", args)
    elseif Refill.onRefilled then
        Refill.onRefilled(character, args)
    end
end

local class = original and getClassSimpleName and getClassSimpleName(original)
if class == "LuaJavaInvoker" or class == "MultiLuaJavaInvoker" then
    local function pack(...) return {n = select("#", ...), ...} end
    observer = function(data, character)
        local result = pack(original(data, character))
        -- A compatibility observer must never interrupt native consumption/cleanup.
        local ok, reason = pcall(completed, data, character)
        if not ok then print("[PZSurvivorToolkit] Torch refill observer: " .. tostring(reason)) end
        return unpack(result, 1, result.n)
    end
    RecipeCodeOnCreate.refillBlowTorch = observer
end

return Refill
