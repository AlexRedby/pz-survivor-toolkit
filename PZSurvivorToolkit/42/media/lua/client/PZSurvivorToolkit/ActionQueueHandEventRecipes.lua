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
    neatState = {mod="NeatUI_Equipment", path="media/lua/client/NeatEquipment/NEQ_State.lua",
        filename="NEQ_State.lua", adler=3830470481},
    cartsCore = {mod="SaucedCarts", path="media/lua/shared/SaucedCarts/Core.lua",
        filename="Core.lua", adler=2570266575},
    cartsForceDrop = {mod="SaucedCarts", path="media/lua/shared/SaucedCarts/ForceDropGuard.lua",
        filename="ForceDropGuard.lua", adler=538857615},
    equipWeapon = {path="media/lua/shared/TimedActions/ISEquipWeaponAction.lua",
        filename="ISEquipWeaponAction.lua", adler=4117952124},
    radioSelected = {mod="TVRadio_ReInvented", path="media/lua/client/RadioCom/ISRadioWindow.lua",
        filename="ISRadioWindow.lua", adler=3319232873},
    radio = {path="media/lua/client/RadioCom/ISRadioWindow.lua",
        filename="ISRadioWindow.lua", adler=1292121519},
    archeryState = {mod="WildernessProgressionArcheryNexusCompanion",
        path="media/lua/shared/R5_AimState.lua", filename="R5_AimState.lua", adler=2769489859},
    bowReload = {mod="WildernessProgressionArcheryNexusCompanion",
        path="media/lua/shared/WPANC_BowReload.lua", filename="WPANC_BowReload.lua", adler=3277238911},
    bowDurability = {mod="WildernessProgressionArcheryNexusCompanion",
        path="media/lua/shared/WPANC_BowDurability.lua",
        filename="WPANC_BowDurability.lua", adler=4069891281},
    archeryContract = {mod="WildernessProgressionArcheryNexusCompanion",
        path="media/lua/shared/WPANC_ArcheryContract.lua",
        filename="WPANC_ArcheryContract.lua", adler=848735890},
    bowPresentation = {mod="WildernessProgressionArcheryNexusCompanion",
        path="media/lua/client/WPANC_BowPresentation.lua",
        filename="WPANC_BowPresentation.lua", adler=766214428},
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

function Recipes.neatLocalPlayerNum()
    return recipe("e71a4b9a5365f99b42147b158bb2e34ce352ea7c761e64962fcb1822fe76e23e", 1, 0)
end

function Recipes.cartsGetPlayerKey()
    return recipe("fa91f5411ca668e1bb15abc105cfdc433effd99b5f4c936de35686b3b43315df", 1, 0)
end

function Recipes.cartsUnregisterKey()
    -- Empty queried state and transition state must be the SAME live cell.
    -- The ordinary-item branch returns before observing holderCount.
    return recipe("121a77b45c1d51a0b567885c8696f0bd3e8dd9be6d1c2623c34963f64c2b7728", 1, 2,
        {{slot=0, test="empty-table", cell="cartsHolders"}})
end

function Recipes.cartsOrdinary()
    -- All module links are checked inside one query. Independently matching
    -- lookalike modules or independently empty holder tables is insufficient.
    local unregister = recipe("d4590a9600bc780c3f149656eb3d7efb99b1804b6135ed847720c513ff2c6e0f", 1, 2, {
        {slot=0, bind="cartsModule", test="field", key="unregisterKey",
            predicate={test="closure", recipe=Recipes.cartsUnregisterKey()}},
        {slot=1, test="closure", recipe=Recipes.cartsGetPlayerKey()},
    })
    local handle = recipe("b9c288c430925b6336f51141cc6b552a5d099d5b9a45a8e5933ab024d6a6e570", 3, 1,
        {{slot=0, bind="cartsModule", test="field", key="unregisterPlayer",
            predicate={test="closure", recipe=unregister}}})
    local key = recipe("8da704a0f67b168313cb0994d580571f065bf5ba6b4fa7ca43d4e9a4f33f32e8", 1, 1,
        {{slot=0, test="empty-table", cell="cartsHolders"}})
    return recipe("2141e9cff4b90a78f9f9f51d4572ddbbfec251c2ad7fc636f2c114e6ad90ff1d", 2, 1, {
        {slot=0, bind="cartsModule", test="field", key="handleEquipPrimary",
            predicate={test="closure", recipe=handle}},
        {slot=0, test="field", key="isHolderKey", predicate={test="closure", recipe=key}},
    })
end

function Recipes.cartsIsCart(typeFunction)
    return recipe("a23d4ea275d694882863b5c3aa41c3be83751644d2977e050d5db1f46d6866be", 1, 1,
        {{slot=0, test="identity", value=typeFunction}})
end

function Recipes.forceDropNative()
    return recipe("230c76818b99cb8981839c5b1b50388f3617244c01bfdf169e9b8fe0058ac1c5", 1, 0)
end

function Recipes.isForceDropHeavyItem()
    return recipe("1fabc3e17ca94a06c29604ba1ad0d2f51a0caac93c9e758af877f1449f58e493", 1, 0)
end

function Recipes.radio()
    return recipe("76cfef8a7d5f9ffa1d83b6415c219cbc49dfdc2bf119bc17624b4402de00b792", 2, 0)
end

function Recipes.cartsSafeIsCart(tostringFunction)
    -- Recursive source fingerprint includes pcall and failure-log children.
    return recipe("5cf57e67de2ea7de1c2aaeb5d54960d519955161332cc2f71c13b66cc92d1f98", 1, 1,
        {{slot=0, test="identity", value=tostringFunction}})
end

function Recipes.forceDropGuard(isCart)
    -- The captured predecessor must be vanilla's complete body, not a source
    -- filename lookalike; the classifier must be the separately proved helper.
    return recipe("f6ccb8ddc816f321a1991074a1b2973a506d86f2c45626437da0221627c401d4", 1, 2, {
        {slot=0, test="closure", recipe=Recipes.forceDropNative()},
        {slot=1, test="identity", value=isCart},
    })
end

function Recipes.forceDropFactory()
    return recipe("f283c39cac1ac35bcb2dd631acdbd8ef1041636e161dd06c2bea195c8c916241", 2, 0)
end

function Recipes.bowPresentationLocalPlayer()
    return recipe("73b1725c90338e61d5ac60d222319f681af2bd9dd9be34bccab46d0bcb65cd40", 1, 0)
end

function Recipes.bowPresentationStateForPlayer()
    -- The source-private table and rows are never returned by a public API.
    -- Its source-owned writers create plain rows and derived scalar/item
    -- fields. This recipe proves the accessor body, not row emptiness.
    return recipe("31f44b0bc30b52278a8743083f479ddab93008f66faca990debfecc09ddc93ac", 1, 1)
end

function Recipes.bowPresentation(presentation, durability)
    local localPlayer = Recipes.bowPresentationLocalPlayer()
    local stateForPlayer = Recipes.bowPresentationStateForPlayer()
    local update = recipe("d8d34a28722bd9cf78a9a1010cf538e0e57c828bc4487d62a8ea1e92a3d5e12b", 1, 7, {
        {slot=0, bind="bowPresentationLocalPlayer", test="closure", recipe=localPlayer},
        {slot=1, bind="bowPresentationStateForPlayer", test="closure", recipe=stateForPlayer},
        {slot=2, test="identity", value=durability},
        {slot=6, test="identity", value=presentation},
    })
    return recipe("1a233e458cd7e28dfbe20f5b3759659cd1c85ead5791956907523f224e131d8b", 2, 3, {
        {slot=0, bind="bowPresentationLocalPlayer", test="closure", recipe=localPlayer},
        {slot=1, bind="bowPresentationStateForPlayer", test="closure", recipe=stateForPlayer},
        {slot=2, test="identity", value=presentation},
        {slot=2, test="field", key="onPlayerUpdate", predicate={test="closure", recipe=update}},
    })
end

function Recipes.bowDurabilityIsBow(contract)
    return recipe("cdbe6fb99bc9a1a2592cc667bab2dc8bb96ef25a3cdad236a4f2f6ff418c954b", 1, 1,
        {{slot=0, test="identity", value=contract}})
end

function Recipes.archeryPrimitiveBow(contract)
    return recipe("2585f9e964e829164abddefdb0df99c7fe8d1a11ed7f15a98b80242aa99b3420", 1, 1,
        {{slot=0, test="identity", value=contract}})
end

function Recipes.archeryPlayerCharacter()
    return recipe("99146e1ec95ea9009e2be5192c1a95785b5d7e39383d4a93d79e85d8a2e25785", 1, 0)
end

function Recipes.archeryCanMutatePlayer()
    return recipe("41ef56daed4a4abc8b7be41f7b2baca39c0e1b8ad2faf0a9998ed2e033419603", 1, 0)
end

function Recipes.archeryPrimary(contract, bowReload)
    -- Tracking absence is a separate live native fact. With no previous bow,
    -- the exact refresh guard returns before optional Gunworks helper calls.
    local refresh = recipe("95c95bef73fc8d17d278fdc0f0363bb14638d94823292f2eea9e7de8c443c336", 2, 1)
    return recipe("120f5a9ca69ede731c33fab5f38d2a46f5c6d9aa2c92b198eeb2a9346e83698a", 2, 8, {
        {slot=0, test="identity", value=contract},
        {slot=1, test="closure", recipe=Recipes.archeryCanMutatePlayer()},
        {slot=2, test="identity", value=bowReload},
        {slot=4, test="closure", recipe=refresh},
    })
end

function Recipes.archerySecondary(contract, bowReload)
    return recipe("1790ecf60c6036ad702cfc9f0c4a08f5cf510d97128d26b3a804f7d5520465c8", 2, 6, {
        {slot=0, test="identity", value=contract},
        {slot=1, test="closure", recipe=Recipes.archeryCanMutatePlayer()},
        {slot=2, test="identity", value=bowReload},
    })
end

-- Both selected wrappers delegate to the same source-owned Contract helper.
function Recipes.bowReloadPrimitiveBow(contract)
    return Recipes.bowDurabilityIsBow(contract)
end

return Recipes
