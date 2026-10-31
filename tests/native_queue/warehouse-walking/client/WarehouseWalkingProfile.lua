-- Observes existing native closures. No class, instance or event callback is replaced.
local Profile = {}
local active, identities
local function bind(object, key, label, required)
    local callback = object and object[key]
    if type(callback) ~= 'function' then
        assert(not required, 'Missing warehouse timing boundary: '..label)
        return
    end
    identities[#identities+1] = {object=object,key=key,callback=callback,label=label}
    warehouseWalkingProfileBind(label, callback)
end
local function module(name, prefix)
    local value = require(name)
    -- InventoryFilter publishes its public table as a side effect and returns
    -- no module value. Kahlua/Lua require may consequently report nil or true.
    if name == 'PZSurvivorToolkit/InventoryFilter' and type(value) ~= 'table' then
        value = PZSurvivorToolkit and PZSurvivorToolkit.InventoryFilter
    end
    assert(type(value) == 'table', 'Missing consumer module: '..name)
    local keys = {}
    for key, callback in pairs(value) do
        if type(key)=='string' and type(callback)=='function' then keys[#keys+1]=key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do bind(value,key,prefix..'.'..key,true) end
end
function Profile.begin(index, playerNum)
    assert(not active, 'Warehouse timing observer already active')
    assert(type(warehouseWalkingProfileReset)=='function', 'Native warehouse observer missing')
    warehouseWalkingProfileReset()
    identities = {}
    for _, page in ipairs({getPlayerInventory(playerNum),getPlayerLoot(playerNum)}) do
        assert(page and page.inventoryPane, 'Warehouse page/pane missing')
        local class, pane = assert(getmetatable(page)), page.inventoryPane
        for _, key in ipairs({'refreshBackpacks','addContainerButton','checkExplored','refreshWeight','updateItemCount'}) do
            bind(class,key,'page.'..key,true)
        end
        local paneClass=assert(getmetatable(pane))
        for _, key in ipairs({'refreshContainer','restoreSelection','saveSelection'}) do
            bind(paneClass,key,'pane.'..key,true)
        end
        -- Class chain and the deferred-row instance gate get distinct identities.
        bind(pane,'refreshContainer','pane.instance.refreshContainer',true)
        bind(pane,'itemSortFunc','pane.itemSortFunc',true)
    end
    for _, pair in ipairs({
        {'BetterContainers/Nested','bc.Nested'}, {'BetterContainers/Proximity','bc.Proximity'},
        {'BetterContainers/_Options','bc.Options'},
        {'PZSurvivorToolkit/InventoryRows','rows'},
        {'PZSurvivorToolkit/InventoryRefresh','refresh'},
        {'PZSurvivorToolkit/InventoryFilter','filter'},
        {'PZSurvivorToolkit/InventorySearch','search'},
        {'PZSurvivorToolkit/InventoryCategoryGroups','categoryGroups'},
        {'PZSurvivorToolkit/InventoryOrder','order'},
        {'PZSurvivorToolkit/InventoryDetailSort','detailSort'},
        {'PZSurvivorToolkit/ItemCategoryRules','categoryRules'},
        {'PZSurvivorToolkit/ItemCategories','categories'},
    }) do module(pair[1],pair[2]) end
    warehouseWalkingProfileBegin(index)
    active=index
end
function Profile.finish()
    assert(active, 'Warehouse timing observer inactive')
    -- Stop first: identity checks and result allocation are outside measured work.
    local phase=active
    active=nil
    local result=warehouseWalkingProfileFinish()
    for _, entry in ipairs(identities) do
        assert(entry.object[entry.key]==entry.callback,'Warehouse observer identity changed: '..entry.label)
    end
    identities=nil
    assert(result.phase==phase,'Warehouse observer phase mismatch')
    result.identities_unchanged=true
    return result
end
return Profile
