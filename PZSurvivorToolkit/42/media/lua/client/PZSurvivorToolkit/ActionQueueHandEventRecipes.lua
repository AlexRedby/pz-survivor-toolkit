-- Source-owned descriptions of callback captures. These are observation inputs,
-- not permissions to replace callbacks or skip hand events. Keep facts live.
local Recipes = {}

local sources = {
    fishing = {path="media/lua/client/Fishing/FishingHandler.lua",
        filename="FishingHandler.lua", adler=1284884840},
    snow = {mod="ImmersiveSnow", path="media/lua/client/ImmersiveSnow/ISnow_CharSnow.lua",
        filename="ISnow_CharSnow.lua", adler=301478472},
    neat = {mod="NeatUI_Equipment", path="media/lua/client/NeatEquipment/Patches/NEQ_HideEquipped.lua",
        filename="NEQ_HideEquipped.lua", adler=4065712833},
    carts = {mod="SaucedCarts", path="media/lua/client/SaucedCarts/CartState/HolderRegistry.lua",
        filename="HolderRegistry.lua", adler=2938445108},
}

-- Return copies so a consumer cannot modify a later caller's source pin.
function Recipes.source(kind)
    local source = sources[kind]
    if not source then return end
    return {mod=source.mod, path=source.path, filename=source.filename, adler=source.adler}
end

local function recipe(fingerprint, parameters, upvalues, captures)
    return {fingerprint=fingerprint, parameters=parameters, upvalues=upvalues, captures=captures or {}}
end

function Recipes.snow()
    -- Full-source native compiler: onEquipChange slot 0 -> root register 98
    -- (releaseItems); releaseItems slot 0 -> root register 54 (swapped).
    -- Empty globally is deliberately conservative: no per-item registry scan.
    local release = recipe("d6117398b9fb03d2b18c7ffd3596b50e9bb59d824972ec31f2593b508c55af9d", 2, 3,
        {{slot=0, test="empty-table"}})
    return recipe("74e468f1ffcf7773ac40550ed9ae0c70029ffc47d137bab2d6bbc0b4691eec1b", 1, 1,
        {{slot=0, test="closure", recipe=release}})
end

function Recipes.neat(state, hide)
    -- Both private callback captures point to public, independently checked
    -- modules: slot 0 -> root register 0 (State), slot 1 -> register 2 (H).
    return recipe("a38df0c800099703d602b35e9c15a9ee2f966d5513485f3f543e0cbe1cb8ab1c", 1, 2,
        {{slot=0, test="identity", value=state}, {slot=1, test="identity", value=hide}})
end

function Recipes.neatRefresh(state)
    local pane = recipe("0371c8ae243757f4133483a2dcc048ea37a8b340b44e64a42740d43e52f69762", 1, 0)
    return recipe("8bb9e144d68345038ae10d878c622b4fcfb71b26a476b1fba504ae388a8204a0", 1, 2,
        {{slot=0, test="identity", value=state}, {slot=1, test="closure", recipe=pane}})
end

function Recipes.carts(holder)
    -- The exact anonymous OnEquipPrimary closure captures root register 0.
    -- The source filename alone cannot prove the captured module identity.
    return recipe("2141e9cff4b90a78f9f9f51d4572ddbbfec251c2ad7fc636f2c114e6ad90ff1d", 2, 1,
        {{slot=0, test="identity", value=holder}})
end

function Recipes.cartsHolderKey(key)
    -- isHolderKey slot 0 -> root register 1 (holders). reset() rebinds that
    -- cell; neither a former table nor a previous absence may be retained.
    return recipe("8da704a0f67b168313cb0994d580571f065bf5ba6b4fa7ca43d4e9a4f33f32e8", 1, 1,
        {{slot=0, test="absent-entry", key=key}})
end

function Recipes.cartsHoldersEmpty()
    -- This attests only the isHolderKey capture reached through the captured
    -- module. The public transition methods still need their own checks.
    local holderKey = recipe("8da704a0f67b168313cb0994d580571f065bf5ba6b4fa7ca43d4e9a4f33f32e8", 1, 1,
        {{slot=0, test="empty-table"}})
    return recipe("2141e9cff4b90a78f9f9f51d4572ddbbfec251c2ad7fc636f2c114e6ad90ff1d", 2, 1,
        {{slot=0, test="field", key="isHolderKey", predicate={test="closure", recipe=holderKey}}})
end

function Recipes.fishing()
    return recipe("aea53275030686d425f8be0a64257c0fcbfe1b666439fb679fa40df2a15437db", 2, 0)
end

function Recipes.fishingHandle()
    return recipe("71cf9494f626e186465f75cd7567287fc259482ee6355cb03d13b94669d92839", 2, 0)
end

function Recipes.fishingValid()
    return recipe("008055cc6d1c44c7a954051444a83320d945ca942ae3bb8fe517725452e4e982", 1, 0)
end

return Recipes
