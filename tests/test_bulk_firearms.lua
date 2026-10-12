-- Selection, native queues and pre-start safety; actual MP mutations run in the native fixture.
require = function() end
local fill, player, queued = nil, nil, {}
local nativeCalls = {gun = 0, magazine = 0, part = 0}
local unloadEnabled, attachmentsEnabled, dead = true, true, false
PZSurvivorToolkit = {Settings = {
    bulkUnload = function() return unloadEnabled end,
    bulkRemoveAttachments = function() return attachmentsEnabled end,
}}
Events = {OnFillInventoryObjectContextMenu = {Add = function(fn) fill = fn end}}
instanceof = function(item, class)
    return item and item.id and (class == 'InventoryItem' or (class == 'HandWeapon' and item.kind == 'gun'))
end
getSpecificPlayer = function() return player end
getText = function(key, n) return key .. (n and '(' .. tostring(n) .. ')' or '') end
ItemTag = {SCREWDRIVER = 'Screwdriver'}
isForceDropHeavyItem = function(item) return item and item.heavy end
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end}
end
local root, bag = {items = {}}, {}
function root:getItemById(id) return self.items[id] end
function root:getFirstTagEvalRecurse(tag, predicate)
    assert(tag == 'Screwdriver')
    if self.tool and predicate(self.tool) then return self.tool end
end
player = {getInventory = function() return root end, isDead = function() return dead end,
    getPrimaryHandItem = function(self) return self.primary end,
    getSecondaryHandItem = function(self) return self.secondary end,
    isEquippedClothing = function(_, item) return item.worn == true end}
local function item(id, kind, container)
    local value = {id = id, kind = kind, container = container or root, ammo = 3, parts = {}}
    function value:getID() return self.id end
    function value:getContainer() return self.container end
    function value:isFavorite() return self.favorite == true end
    function value:getCurrentAmmoCount() return self.ammo end
    function value:getAmmoType() return not self.noAmmoType and 'Base.Bullets9mm' or nil end
    function value:getMaxAmmo() return self.kind == 'other' and 0 or 10 end
    function value:getMagazineType() return self.magazineType end
    function value:getDisplayName() return self.kind .. self.id end
    function value:getWorldItem() return self.ground end
    function value:isBroken() return self.broken end
    function value:getWeaponPart(kind) return self.parts[kind] end
    function value:getDetachableWeaponParts(p)
        local result = {}
        for _, part in pairs(self.parts) do
            if part:canDetach(p, self) then result[#result + 1] = part end
        end
        return list(result)
    end
    return value
end
local function part(id, kind)
    return {getID = function() return id end, getPartType = function() return kind end,
        getName = function() return kind end,
        canDetach = function(self) return not self.blocked end}
end
local function menu()
    local result = {options = {}}
    function result:addOption(name, target, callback, ...)
        local value = {name = name, target = target, onSelect = callback}
        for i = 1, select('#', ...) do value['param' .. i] = select(i, ...) end
        self.options[#self.options + 1] = value
        return value
    end
    function result:getNew() return menu() end
    function result:getSubMenu(child) return child end
    function result:addSubMenu(option, child) option.subOption = child end
    return result
end
ISTimedActionQueue = {add = function(action) queued[#queued + 1] = action end}
ISEquipWeaponAction = {new = function(_, p, value, time, primary, twoHands)
    assert(p == player and primary and not twoHands)
    return {Type = 'ISEquipWeaponAction', item = value, maxTime = time,
        start = function(self) self.nativeStarted = true end, forceStop = function(self) self.stopped = true end,
        isValid = function(self)
            local resolved = root:getItemById(self.item:getID())
            if resolved then self.item = resolved; return true end
            return false
        end}
end}
ISUnequipAction = {new = function(_, _, value) return {Type = 'ISUnequipAction', item = value} end}
ISUnloadBulletsFromFirearm = {new = function(_, p, value)
    assert(p == player)
    return {Type = 'ISUnloadBulletsFromFirearm', gun = value, isValid = function() return true end}
end}
ISUnloadBulletsFromMagazine = {new = function(_, p, value)
    assert(p == player)
    return {Type = 'ISUnloadBulletsFromMagazine', magazine = value, isValid = function() return true end}
end}
ISRemoveWeaponUpgrade = {new = function(_, p, weapon, kind)
    assert(p == player)
    return {Type = 'ISRemoveWeaponUpgrade', weapon = weapon, partType = kind, isValid = function() return true end}
end}
ISInventoryPaneContextMenu = {}
function ISInventoryPaneContextMenu.transferIfNeeded(p, value)
    if luautils.haveToBeTransfered(p, value) then
        ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(p, value, value.container, root))
    end
end
function ISInventoryPaneContextMenu.equipWeapon(value)
    if value.ground then
        local transfer = ISInventoryTransferUtil.newInventoryTransferAction(player, value, value.container, root)
        transfer.maxTime = 20;ISTimedActionQueue.add(transfer)
    else ISInventoryPaneContextMenu.transferIfNeeded(player, value) end
    ISTimedActionQueue.add(ISEquipWeaponAction:new(player, value, value.ground and 1 or 50, true, false))
end
-- Stand-ins for the wrapped callbacks: bypassing them loses Tidy's snapshot/restore setup.
function ISInventoryPaneContextMenu.onUnloadBulletsFromFirearm(p, value)
    nativeCalls.gun = nativeCalls.gun + 1
    ISInventoryPaneContextMenu.equipWeapon(value)
    ISTimedActionQueue.add(ISUnloadBulletsFromFirearm:new(p, value))
end
function ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine(p, value)
    nativeCalls.magazine = nativeCalls.magazine + 1
    ISInventoryPaneContextMenu.transferIfNeeded(p, value)
    ISTimedActionQueue.add(ISUnloadBulletsFromMagazine:new(p, value))
end
function ISInventoryPaneContextMenu.onRemoveUpgradeWeapon(value, upgrade, p)
    nativeCalls.part = nativeCalls.part + 1
    ISInventoryPaneContextMenu.transferIfNeeded(p, value)
    local screwdriver = root:getFirstTagEvalRecurse(ItemTag.SCREWDRIVER, function(tool) return not tool:isBroken() end)
    if screwdriver then ISInventoryPaneContextMenu.equipWeapon(screwdriver) end
    ISTimedActionQueue.add(ISRemoveWeaponUpgrade:new(p, value, upgrade:getPartType()))
end
-- Load the same shared helpers used by the module, mocking only native transfer construction.
luautils = {haveToBeTransfered = function(_, value) return value.container ~= root end}
ISInventoryTransferUtil = {newInventoryTransferAction = function(_, value, source, destination)
    return {Type = 'ISInventoryTransferAction', item = value, srcContainer = source, destContainer = destination, maxTime = 50, transactionId = 0,
        setOnComplete = function(self, fn) self.onCompleteFunc = fn end, stop = function() end}
end}
dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/BulkActions.lua')
dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/BulkFirearms.lua')
local bulk = PZSurvivorToolkit.BulkFirearms
local a, b, magazine, other = item(1, 'gun'), item(2, 'gun', bag), item(3, 'magazine', bag), item(4, 'other')
local pistol = item(5, 'gun');pistol.magazineType = 'Base.9mmClip'
root.items = {[1] = a, [4] = other, [5] = pistol}
local entries = bulk.unloadEntries(player, {{items = {a, a, b}}, magazine, other, pistol})
assert(#entries == 3 and entries[1].item == a and entries[2].item == b and entries[3].item == magazine,
    'exact deduplicated mixed selection must exclude inserted-magazine weapons and unrelated items')
assert(bulk.queueUnload(player, entries) == 3)
local equips, unloads, transfers = {}, {}, {}
for _, action in ipairs(queued) do
    if action.Type == 'ISEquipWeaponAction' then equips[#equips + 1] = action
    elseif action.Type == 'ISInventoryTransferAction' then transfers[#transfers + 1] = action
    else unloads[#unloads + 1] = action end
end
assert(#equips == 2 and #transfers == 2 and #unloads == 3 and nativeCalls.gun == 2 and nativeCalls.magazine == 1)
assert(equips[1].toolkitBulkPreparation and equips[2].toolkitBulkPreparation)
for _, action in ipairs(unloads) do assert(action.toolkitIndependentBulk) end
assert(equips[1]:isValidStart());equips[1]:start();player.primary = a
assert(unloads[1]:isValidStart(), 'our queued native equip must not invalidate firearm unloading')
a.ammo = 0
assert(unloads[1]:isValid(), 'MP ammo replication must not continuously invalidate an executing action')
assert(not unloads[1]:isValidStart(), 'empty firearm at start must be rejected')
a.ammo, player.primary = 3, nil
assert(not equips[2]:isValidStart() and not unloads[2]:isValidStart(), 'missing transferred instance fails closed')
local bReplacement = item(2, 'gun');root.items[2] = bReplacement
assert(equips[2]:isValidStart());equips[2]:start();player.primary = bReplacement
assert(unloads[2]:isValidStart() and unloads[2].gun == bReplacement, 'MP replacement must resolve by ID')
for _, flag in ipairs({'favorite', 'worn'}) do
    bReplacement[flag] = true;assert(not unloads[2]:isValidStart());bReplacement[flag] = nil
end
player.primary = nil
magazine.container, root.items[3] = root, magazine
assert(unloads[3]:isValidStart())
player.secondary = magazine;assert(not unloads[3]:isValidStart());player.secondary = nil
magazine.ammo = 0;assert(not unloads[3]:isValidStart());magazine.ammo = 3
for _, hand in ipairs({'primary', 'secondary'}) do
    player[hand] = a;assert(#bulk.unloadEntries(player, {a}) == 0);player[hand] = nil
end

local scope, sling, fixed = part(11, 'Scope'), part(12, 'Sling'), part(13, 'Stock');fixed.blocked = true
a.parts = {Scope = scope, Sling = sling, Stock = fixed}
b.parts = {Scope = part(14, 'Scope')}
local screwdriver = item(20, 'other', bag);root.tool = screwdriver
queued = {}
local attached = bulk.attachmentEntries(player, {a, b, other, {items = {a}}})
assert(#attached == 2 and #attached[1].parts == 2)
assert(bulk.queueAttachments(player, attached) == 3)
local removals, weaponPickups, toolPickups, toolEquips = {}, 0, 0, 0
for _, action in ipairs(queued) do
    if action.Type == 'ISRemoveWeaponUpgrade' then removals[#removals + 1] = action
    elseif action.Type == 'ISInventoryTransferAction' and action.item == b then weaponPickups = weaponPickups + 1
    elseif action.Type == 'ISInventoryTransferAction' and action.item == screwdriver then toolPickups = toolPickups + 1
    elseif action.Type == 'ISEquipWeaponAction' and action.item == screwdriver then toolEquips = toolEquips + 1 end
end
assert(#removals == 3 and weaponPickups == 1 and toolPickups == 1 and toolEquips == 3 and nativeCalls.part == 3,
    'weapon and shared screwdriver pickups must occur once with native equip/action types visible to Tidy')
assert(removals[1]:isValidStart())
local firstType = removals[1].partType
local firstPart = a.parts[firstType]
a.parts[firstType] = nil
assert(not removals[1]:isValidStart() and removals[1]:isValid(), 'missing part fails only before starting')
a.parts[firstType] = part(999, firstType);assert(not removals[1]:isValidStart(), 'changed part cannot be substituted')
a.parts[firstType] = firstPart;firstPart.blocked = true;assert(not removals[1]:isValidStart());firstPart.blocked = nil
local cloned = item(2, 'gun');cloned.parts = b.parts;root.items[2] = cloned
assert(removals[3]:isValidStart() and removals[3].weapon == cloned, 'attachment action must resolve moved weapon by ID')

local context = menu()
local native = context:addOption('Native unload', player, ISInventoryPaneContextMenu.onUnloadBulletsFromFirearm, a)
local icon, tooltip = {}, {};native.iconTexture, native.toolTip = icon, tooltip
fill(0, context, {a, magazine})
assert(#context.options == 2 and not native.onSelect and #native.subOption.options == 2)
local one, all = native.subOption.options[1], native.subOption.options[2]
assert(one.onSelect == ISInventoryPaneContextMenu.onUnloadBulletsFromFirearm and one.param1 == a
    and one.iconTexture == icon and one.toolTip == tooltip and all.onSelect == bulk.queueUnload)
local removeRow = context.options[2]
assert(removeRow.name == getText('ContextMenu_Remove_Weapon_Upgrade') and #removeRow.subOption.options == 3,
    'one weapon keeps per-part rows and gets remove-all choice')
fill(0, context, {a, magazine})
assert(#context.options == 2 and #native.subOption.options == 2 and #removeRow.subOption.options == 3)
local mixed = menu();fill(0, mixed, {a, b, magazine})
assert(#mixed.options == 2 and #mixed.options[1].subOption.options[2].param1 == 3,
    'mixed native-omitted rows receive one native anchor and exact bulk selection')
local nested = menu();local parent = nested:addOption('Native group');local child = menu();nested:addSubMenu(parent, child)
local partMenu = child:addOption(getText('ContextMenu_Remove_Weapon_Upgrade'));local choices = menu();child:addSubMenu(partMenu, choices)
choices:addOption('Scope', a, ISInventoryPaneContextMenu.onRemoveUpgradeWeapon, scope, player)
fill(0, nested, {a, b})
assert(#choices.options == 2 and choices.options[1].param1 == scope, 'existing native part options must survive nested menus')
unloadEnabled, attachmentsEnabled = true, false
local onlyUnload = menu();fill(0, onlyUnload, {a, magazine})
assert(#onlyUnload.options == 1 and onlyUnload.options[1].subOption.options[2].onSelect == bulk.queueUnload,
    'attachment toggle must not suppress unloading')
unloadEnabled, attachmentsEnabled = false, true
local onlyAttachments = menu();fill(0, onlyAttachments, {a, magazine})
assert(#onlyAttachments.options == 1 and onlyAttachments.options[1].name == getText('ContextMenu_Remove_Weapon_Upgrade'),
    'unload toggle must not suppress attachment removal')
unloadEnabled, attachmentsEnabled, queued = false, false, {}
assert(bulk.queueUnload(player, entries) == nil and bulk.queueAttachments(player, attached) == nil and #queued == 0)
local disabled = menu();fill(0, disabled, {a, b});assert(#disabled.options == 0)
unloadEnabled, attachmentsEnabled, dead = true, true, true
assert(bulk.queueUnload(player, entries) == nil and bulk.queueAttachments(player, attached) == nil)
dead = false
local add = ISTimedActionQueue.add
local original = ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine
ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine = function() error('callback failure') end
local ok = pcall(bulk.queueUnload, player, bulk.unloadEntries(player, {magazine}))
assert(not ok and ISTimedActionQueue.add == add, 'native callback failure must restore the queue interceptor')
ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine = original
queued = {}
bulk.queueUnload(player, bulk.unloadEntries(player, {a}))
local firstEquip, firstUnload = queued[1], queued[2]
-- Native addToQueue begins an idle queue's first action without calling isValidStart.
firstEquip:start();player.primary = a
assert(firstEquip.nativeStarted and firstUnload:isValidStart(), 'first-action native equip must authorize our held gun')
player.primary, queued = nil, {}
bulk.queueUnload(player, bulk.unloadEntries(player, {a}))
a.favorite = true;queued[1]:start()
assert(queued[1].stopped and not queued[1].nativeStarted, 'first-action equip must still protect favorite selection changes')
a.favorite = nil
local ground = item(40, 'gun', bag);ground.ground = true;queued = {}
bulk.queueUnload(player, bulk.unloadEntries(player, {ground}))
assert(queued[1].maxTime == 20 and queued[2].maxTime == 1, 'native ground pickup/equip durations must survive interception')
player.primary,unloadEnabled,attachmentsEnabled=nil,true,false
local repeated=menu()
local gunOption=repeated:addOption('Unload gun',player,ISInventoryPaneContextMenu.onUnloadBulletsFromFirearm,a)
local magazineOption=repeated:addOption('Unload magazine',player,ISInventoryPaneContextMenu.onUnloadBulletsFromMagazine,magazine)
fill(0,repeated,{a,magazine});fill(0,repeated,{a,magazine})
assert(gunOption.subOption and #gunOption.subOption.options==2 and magazineOption.onSelect and not magazineOption.subOption,
    'mixed gun/magazine selection gets one batch command while distinct native actions survive')
unloadEnabled,attachmentsEnabled=false,true
local repeatedParts=menu()
local firstParent=repeatedParts:addOption(getText('ContextMenu_Remove_Weapon_Upgrade'))
local firstChoices=menu();repeatedParts:addSubMenu(firstParent,firstChoices)
firstChoices:addOption('Scope',a,ISInventoryPaneContextMenu.onRemoveUpgradeWeapon,scope,player)
local secondParent=repeatedParts:addOption(getText('ContextMenu_Remove_Weapon_Upgrade'))
local secondChoices=menu();repeatedParts:addSubMenu(secondParent,secondChoices)
secondChoices:addOption('Scope',b,ISInventoryPaneContextMenu.onRemoveUpgradeWeapon,b.parts.Scope,player)
fill(0,repeatedParts,{a,b});fill(0,repeatedParts,{a,b})
assert(#firstChoices.options==2 and #secondChoices.options==1 and secondChoices.options[1].target==b,
    'one attachment batch must preserve both weapon-specific native part choices')
print('Bulk firearm checks passed: native queues, exact items/parts, MP pre-start guards, mixed menus and independent toggles.')
