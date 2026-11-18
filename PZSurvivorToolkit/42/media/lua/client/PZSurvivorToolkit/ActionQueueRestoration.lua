-- Own restoration producers schedule cleanup; Settlement alone proves and pays debt.
local Toolkit = PZSurvivorToolkit
local Settlement = require "PZSurvivorToolkit/ActionQueueSettlement"
local Proof = require "PZSurvivorToolkit/SourceProof"
local Restoration = {}
Toolkit.ActionQueueRestoration = Restoration
local enqueue = Settlement.enqueueBorrowedReturn
local capture, origin = Proof.captureBindings, Proof.closure
local borrowedReturns

-- Snapshot before any source checks, native constructors or family callbacks.
-- Handles remain opaque: neither copied fields nor a producer flag earn a loan.
local function handlesSnapshot(handles)
    if type(handles) ~= "table" or getmetatable(handles) ~= nil then return end
    local size, result, seen = #handles, {}, {}
    for key in pairs(handles) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > size then return end
    end
    for index = 1, size do
        local handle = handles[index]
        if type(handle) ~= "table" or getmetatable(handle) ~= nil then return end
        if not seen[handle] then
            seen[handle] = true
            result[#result + 1] = handle
        end
    end
    return result
end

local function sourceLease()
    if PZSurvivorToolkit ~= Toolkit or Toolkit.ActionQueueRestoration ~= Restoration
        or Restoration.borrowedReturns ~= borrowedReturns or Toolkit.ActionQueueSettlement ~= Settlement
        or Proof.captureBindings ~= capture or Proof.closure ~= origin
        or Settlement.enqueueBorrowedReturn ~= enqueue then return end
    local watch = capture({
        {owner = _G, keys = {"PZSurvivorToolkit"}},
        {owner = Toolkit, keys = {"ActionQueueRestoration", "ActionQueueSettlement"}},
        {owner = Proof, keys = {"captureBindings", "closure"}},
        {owner = Restoration, keys = {"borrowedReturns"}},
        {owner = Settlement, keys = {"enqueueBorrowedReturn"}},
    })
    if watch and origin(enqueue, "ActionQueueSettlement.lua") and watch() then return watch end
end

-- Call inside the family's existing required cleanup expansion. Native enqueue
-- retains its ordering and ownership rules. The callback annotates each queued
-- child at the same boundary as the old family loop; it grants no authority.
-- No actionQueue setting gate: admitted cleanup can outlive disabling the editor.
borrowedReturns = function(handles, onEnqueued)
    local snapshot = handlesSnapshot(handles)
    if not snapshot or onEnqueued ~= nil and type(onEnqueued) ~= "function" then return nil, "invalid_batch" end
    if #snapshot == 0 then return 0 end
    local watch = sourceLease()
    if not watch then return nil, "source_changed" end
    local count = 0
    for _, handle in ipairs(snapshot) do
        if not watch() then return count, "source_changed" end
        -- Rechecks the exact native loan, current cleanup parent/dependencies,
        -- source identity/accessibility and prior planned return for every item.
        local action, reason = enqueue(handle)
        if reason ~= nil then return count, reason end
        if action then
            count = count + 1
            if onEnqueued then onEnqueued(action) end
        end
    end
    return count
end

-- Native readItem retains its existing optional return. Source-proven wringing
-- may plan a missing optional return through the shared private loan owner.
local observeNative, nativeSources, nativeReadRole, nativeWringRole
local prepare = Settlement.observePreparation
local remember = Settlement.rememberPreparation
local planOptional = Settlement.planOptionalReturn
local activatedMods = getActivatedMods
local firstLine = getFirstLineOfClosure
local filename = getFilenameOfClosure
local sourceMatches = Proof.matches
local nativeOperations = Toolkit.ActionQueueOperations
local nativeProducer = nativeOperations and nativeOperations.producer
local nativeProducerVerified
local ownIntentInstalled
local selectorOwn,selectorMeta,selectorRaw,selectorEqual=Proof.own,toolkitLuaMetatableMatches,rawget,rawequal
local function installOwnIntent(saved)
    if ownIntentInstalled then return end
    local intent, menu = Toolkit.ActionQueueTidyIntent, ISInventoryPaneContextMenu
    local install,poll = intent and intent.install,intent and intent.pollOwn
    local pane,panel,element,object=ISInventoryPane,ISPanel,ISUIElement,ISBaseObject
    if not selectorEqual(Proof.own,selectorOwn)or not selectorEqual(toolkitLuaMetatableMatches,selectorMeta)
        or not selectorEqual(rawget,selectorRaw)or not selectorEqual(rawequal,selectorEqual)
        or type(selectorOwn)~='function'or type(selectorMeta)~='function'then return end
    local actual=selectorOwn(pane,'getActualItems') -- One own-field read at installation only.
    local utils,foodAge=ISInventoryTransferUtil,CleanUI_ToolkitFoodAge
    if type(install) ~= "function" or type(poll) ~= "function" or type(menu) ~= "table" or getmetatable(menu) ~= nil
        or type(pane) ~= "table" or type(actual) ~= "function"or type(utils)~='table'
        or not selectorMeta(utils,nil)or foodAge~=nil and(type(foodAge)~='table'or not selectorMeta(foodAge,nil))then return end
    -- Use the same exact selected context source already qualified by the own
    -- producer. CleanUI's public callbacks retain native equipment execution.
    local cleanContext=nativeReadRole==3229
    local callbacks = {OnPrimaryWeapon = {menu.OnPrimaryWeapon,cleanContext and 4138 or 3623},
        OnSecondWeapon = {menu.OnSecondWeapon,cleanContext and 4205 or 3689},
        OnTwoHandsEquip = {menu.OnTwoHandsEquip,cleanContext and 4183 or 3667},
        equipWeapon = {menu.equipWeapon,cleanContext and 4221 or 3705},
        transferIfNeeded = {menu.transferIfNeeded,cleanContext and 2263 or 1911}}
    if cleanContext then
        callbacks.cleanUIResetStaleTimedActionRetrigger={menu.cleanUIResetStaleTimedActionRetrigger,4036}
        callbacks.cleanUILogTimedActionFix={menu.cleanUILogTimedActionFix,4030}
    end
    local bindings={{owner = _G, keys = {"PZSurvivorToolkit","P4TidyUpMeister","ISInventoryPaneContextMenu","ISEquipWeaponAction",
            "ISInventoryTransferAction","ISInventoryPane","ISPanel","ISUIElement","ISBaseObject","ISInventoryTransferUtil",
            "CleanUI_ToolkitFoodAge","toolkitLuaMetatableMatches","rawget","rawequal","getActivatedMods","getFirstLineOfClosure","getFilenameOfClosure"}},
        {owner = Toolkit, keys = {"ActionQueueRestoration","ActionQueueTidyIntent","ActionQueuePolicy","Settings"}},
        {owner = Proof, keys = {"closure","matches","captureBindings","own"}},
        {owner = menu, keys = {"cleanUIResetStaleTimedActionRetrigger","cleanUILogTimedActionFix"}},
        {owner = utils, keys = {"newInventoryTransferAction"}},
        {owner = intent, keys = {"install","pollOwn"}}, {owner = saved.policy, keys = {"matchesNative"}},
        {owner = saved.settings, keys = {"actionQueue"}}}
    if foodAge then bindings[#bindings+1]={owner=foodAge,keys={'protocol','enhancedSourceSha256','updateCollapsedStack'}}end
    local watch=capture(bindings)
    local function selectorBinding()
        if not watch or not watch()then return false end
        -- Native UI ancestry is fixed depth. Prove roots and __index before
        -- inherited rawget, then prove this selector cannot come from a parent.
        return type(object)=='table'and type(element)=='table'and type(panel)=='table'
            and selectorMeta(object,nil)and selectorEqual(selectorRaw(object,'__index'),object)
            and selectorMeta(element,object)and selectorEqual(selectorRaw(element,'__index'),element)
            and selectorMeta(panel,element)and selectorEqual(selectorRaw(panel,'__index'),panel)
            and selectorMeta(pane,panel)and selectorRaw(panel,'getActualItems')==nil
            and selectorEqual(selectorRaw(pane,'getActualItems'),actual)
    end
    local function selectedSelector()
        local line=firstLine(actual)
        if line==916 then return sourceMatches('media/lua/client/ISUI/ISInventoryPane.lua',3795077573,nil,true)end
        if not sourceMatches('media/lua/client/ISUI/ISInventoryPane.lua',2870025445,'CleanUI',true)then return false end
        if line==4014 then return foodAge==nil end
        -- Exact reviewed Java compiler output (d3824561...), not a line range.
        local update=foodAge and foodAge.updateCollapsedStack
        return line==4016 and foodAge and foodAge.protocol==1
            and foodAge.enhancedSourceSha256=='34e7b696f17417b0e93cbb6b4d31e49b70bf5d2efa9e7975b362dd42df32ca0a'
            and type(update)=='function'and origin(update,'ISInventoryPane.lua')and firstLine(update)==955
    end
    if not watch or not origin(install,"ActionQueueTidyIntent.lua") or not origin(poll,"ActionQueueTidyIntent.lua")
        or firstLine(install) ~= 575 or firstLine(poll) ~= 444
        or not sourceMatches("media/lua/client/PZSurvivorToolkit/ActionQueueTidyIntent.lua",716420265,"PZSurvivorToolkit",true)
        or not selectorBinding()or not origin(actual,"ISInventoryPane.lua")or not selectedSelector()
        or not sourceMatches("media/lua/client/ISUI/ISInventoryPaneContextMenu.lua",cleanContext and 1708080922 or 3980587789) then return end
    for name, entry in pairs(callbacks) do
        if type(entry[1]) ~= "function" or not origin(entry[1],"ISInventoryPaneContextMenu.lua")
            or firstLine(entry[1]) ~= entry[2] or not selectorBinding()
            or not selectorEqual(selectorRaw(menu,name),entry[1]) then return end
    end
    for name, entry in pairs(callbacks) do if not selectorEqual(selectorRaw(menu,name),entry[1]) then return end end
    local function valid(action)
        if not selectorBinding() or P4TidyUpMeister ~= nil or saved.enabled() ~= true then return false end
        local ok,mods = pcall(activatedMods)
        if not ok or not mods or type(mods.contains) ~= "function" then return false end
        local checked,selected = pcall(mods.contains,mods,"P4TidyUpMeister")
        if not checked or selected ~= false or not selectorBinding() then return false end
        -- This installs observation, never queue/edit authority. Other explicit
        -- intent kinds remain outside the own optional-equipment slice.
        local accepted=action==nil or(selectorEqual(getmetatable(action),ISEquipWeaponAction)
            or selectorEqual(getmetatable(action),ISInventoryTransferAction))and saved.matches(action)
        return accepted and selectorBinding()
    end
    if not valid() then return end
    if install(valid,nil,nil,true)~=true then return end
    Events.OnPlayerUpdate.Add(function(player)
        poll(player) -- Captured authenticated callback clears its private state on guard loss.
    end)
    ownIntentInstalled = true
end
local function nativeDependencies()
    local policy, definitions, settings, operations = Toolkit.ActionQueuePolicy, Toolkit.ActionQueueDefinitions,
        Toolkit.Settings, Toolkit.ActionQueueOperations
    if type(policy) ~= "table" or getmetatable(policy) ~= nil
        or type(definitions) ~= "table" or getmetatable(definitions) ~= nil
        or type(settings) ~= "table" or getmetatable(settings) ~= nil
        or type(operations) ~= "table" or getmetatable(operations) ~= nil
        or type(settings.actionQueue) ~= "function" then return end
    -- Capture references before invoking metadata. nativeLease authenticates
    -- this candidate only after its source/export watch has been prepared.
    local saved = nativeSources or {policy = policy, definitions = definitions, settings = settings, operations = operations,
        matches = policy.matchesNative, ordinary = policy.isOrdinaryTransfer, carried = policy.isCarriedContainer,
        inspect = definitions.inspect, enabled = settings.actionQueue, producer = operations.producer}
    if policy ~= saved.policy or definitions ~= saved.definitions or settings ~= saved.settings or operations ~= saved.operations
        or policy.matchesNative ~= saved.matches or policy.isOrdinaryTransfer ~= saved.ordinary
        or policy.isCarriedContainer ~= saved.carried or definitions.inspect ~= saved.inspect
        or settings.actionQueue ~= saved.enabled or operations.producer ~= saved.producer then return end
    return saved
end
local function nativeLease()
    if P4TidyUpMeister ~= nil or PZSurvivorToolkit ~= Toolkit or Toolkit.ActionQueueRestoration ~= Restoration
        or Restoration.observeNative ~= observeNative or Toolkit.ActionQueueSettlement ~= Settlement
        or Settlement.observePreparation ~= prepare or Settlement.rememberPreparation ~= remember
        or Settlement.planOptionalReturn ~= planOptional
        or Proof.captureBindings ~= capture or Proof.closure ~= origin or Proof.matches ~= sourceMatches
        or getActivatedMods ~= activatedMods or type(activatedMods) ~= "function"
        or getFirstLineOfClosure ~= firstLine or type(firstLine) ~= "function"
        or getFilenameOfClosure ~= filename or type(filename) ~= "function" then return end
    local saved = nativeDependencies()
    if not saved then return end
    local watch = capture({
        {owner = _G, keys = {"PZSurvivorToolkit", "P4TidyUpMeister", "getActivatedMods", "getFirstLineOfClosure", "getFilenameOfClosure", "ISInventoryPaneContextMenu"}},
        {owner = Toolkit, keys = {"ActionQueueRestoration", "ActionQueueSettlement", "ActionQueuePolicy", "ActionQueueDefinitions", "ActionQueueOperations", "Settings"}},
        {owner = Restoration, keys = {"observeNative"}},
        {owner = Settlement, keys = {"observePreparation", "rememberPreparation", "planOptionalReturn"}},
        {owner = Proof, keys = {"captureBindings", "closure", "matches"}},
        {owner = saved.policy, keys = {"matchesNative", "isOrdinaryTransfer", "isCarriedContainer"}},
        {owner = saved.definitions, keys = {"inspect"}},
        {owner = saved.operations, keys = {"producer"}},
        {owner = saved.settings, keys = {"actionQueue"}},
    })
    if not watch then return end
    if not nativeSources then
        if not origin(saved.matches, "ActionQueuePolicy.lua")
            or not origin(saved.ordinary, "ActionQueuePolicy.lua")
            or not origin(saved.carried, "ActionQueuePolicy.lua")
            or not origin(saved.inspect, "ActionQueueDefinitions.lua")
            or not origin(saved.producer, "ActionQueueOperations.lua")
            or not origin(prepare, "ActionQueueSettlement.lua")
            or not origin(remember, "ActionQueueSettlement.lua")
            or not origin(planOptional, "ActionQueueSettlement.lua") or not watch() then return end
        nativeSources = saved
    end
    return watch, saved
end
local function selectMenuRoles(watch)
    if nativeReadRole == nil then
        local path = "media/lua/client/ISUI/ISInventoryPaneContextMenu.lua"
        local role = false
        if sourceMatches(path, 3980587789) then role, nativeWringRole = 2799, 2560
        elseif sourceMatches(path, 1708080922) then role, nativeWringRole = 3229, 2959 end
        if not watch() then return false end
        nativeReadRole = role
    end
    return nativeReadRole and watch()
end

function Restoration.prepareOwnHandIntent()
    local watch,saved=nativeLease()
    if not watch or not selectMenuRoles(watch) then return false end
    installOwnIntent(saved)
    return ownIntentInstalled == true and watch()
end

observeNative = function(action)
    -- Existing P4 runs pay only this cheap check. Selection is checked separately
    -- below, so a selected mod with a delayed/missing global never enables us.
    if P4TidyUpMeister ~= nil or PZSurvivorToolkit ~= Toolkit
        or Toolkit.ActionQueueRestoration ~= Restoration or Restoration.observeNative ~= observeNative
        or Toolkit.ActionQueueOperations ~= nativeOperations
        or not nativeOperations or nativeOperations.producer ~= nativeProducer
        or Proof.closure ~= origin or getFilenameOfClosure ~= filename then return false end
    if not nativeProducerVerified then
        if not origin(nativeProducer, "ActionQueueOperations.lua") or P4TidyUpMeister ~= nil
            or PZSurvivorToolkit ~= Toolkit or Toolkit.ActionQueueRestoration ~= Restoration
            or Restoration.observeNative ~= observeNative or Toolkit.ActionQueueOperations ~= nativeOperations
            or nativeOperations.producer ~= nativeProducer or getFilenameOfClosure ~= filename
            or Proof.closure ~= origin then return false end
        nativeProducerVerified = true -- Immutable callback metadata only.
    end
    local callback, owner, method = nativeProducer(action)
    -- Unrelated enqueues do no source-file, mod-list or contract inspection.
    if owner ~= ISInventoryPaneContextMenu or (method ~= "readItem" and method ~= "onWringClothing") then return false end
    local watch, saved = nativeLease()
    if not watch or saved.producer ~= nativeProducer
        or not origin(callback, "ISInventoryPaneContextMenu.lua") or not watch() then return false end
    local lineOk, line = pcall(firstLine, callback)
    if not lineOk or (method == "readItem" and line ~= 2799 and line ~= 3229)
        or (method == "onWringClothing" and line ~= 2560 and line ~= 2959) or not watch() then return false end
    local ok, mods = pcall(activatedMods)
    if not ok or not mods or type(mods.contains) ~= "function" then return false end
    local selected, present = pcall(mods.contains, mods, "P4TidyUpMeister")
    if not selected or present ~= false or saved.enabled() ~= true or not watch() then return false end
    -- Cache immutable source qualification only, after the cheap provider and
    -- setting gates. Unsupported source is not reread for every book click.
    if not selectMenuRoles(watch) then return false end
    if line ~= (method == "readItem" and nativeReadRole or nativeWringRole) or not watch() then return false end
    installOwnIntent(saved)
    if method ~= "onWringClothing" or action.Type ~= "ISWringClothing" then remember(action, saved.inspect) end
    if method == "onWringClothing" and action.Type == "ISWringClothing" then
        local wring, item, actor = Toolkit.ActionQueueWring, action.item, action.character
        if type(wring) ~= "table" or getmetatable(wring) ~= nil or not item
            or not instanceof(item, "Clothing") or actor:isEquipped(item)
            or type(wring.callbacksTrusted) ~= "function" or type(wring.inspectPrepared) ~= "function"
            or type(wring.matchesPrepared) ~= "function" then return false end
        local matches, inspector, binding = wring.callbacksTrusted, wring.inspectPrepared, wring.matchesPrepared
        local bodyWatch = capture({{owner = Toolkit, keys = {"ActionQueueWring"}},
            {owner = wring, keys = {"callbacksTrusted", "inspectPrepared", "matchesPrepared"}}, {owner = owner, keys = {method}}})
        if not bodyWatch or not origin(matches, "ActionQueueWring.lua")
            or not origin(inspector, "ActionQueueWring.lua") or not origin(binding, "ActionQueueWring.lua")
            or not sourceMatches("media/lua/client/PZSurvivorToolkit/ActionQueueWring.lua",2590770586,"PZSurvivorToolkit",true)
            or not bodyWatch() or not watch() then return false end
        local contract = inspector(action)
        if not contract or not contract.edit or contract.edit.complete ~= true
            or not matches(action) or not watch() or not bodyWatch() then return false end
        -- This lease survives the synchronous producer. No later completion can
        -- reconstruct producer authority from public action fields.
        local function lease(pickup, body)
            if not watch() or not bodyWatch() or P4TidyUpMeister ~= nil then return false,"source" end
            local listed, currentMods = pcall(activatedMods)
            if not listed or not currentMods or type(currentMods.contains) ~= "function" then return false,"mod-list" end
            local checked, selected = pcall(currentMods.contains, currentMods, "P4TidyUpMeister")
            if not checked or selected ~= false or not watch() or not bodyWatch() then return false,"provider" end
            if not body or binding(body) ~= true then return false,"body-binding" end
            if body ~= action or saved.enabled() ~= true then return false,"body-owner" end
            if item ~= body.item then
                local canonical = body.item
                if not isClient() or not canonical or canonical:getID() ~= item:getID()
                    or canonical:getFullType() ~= item:getFullType() then return false,"body-item" end
                local root = actor:getInventory()
                if canonical:getContainer() ~= root or root:getItemById(item:getID()) ~= canonical then return false,"body-canonical" end
            end
            if body.character ~= actor or not instanceof(item,"Clothing") then return false,"actor-item" end
            if actor:isEquipped(body.item) then return false,"equipped" end
            if not (pickup.item == item or isClient() and pickup.item and pickup.item:getID() == item:getID()
                and pickup.item:getFullType() == item:getFullType()) then return false,"pickup-item" end
            if pickup.character ~= actor or not matches(body) then return false,"callback" end
            return watch() and bodyWatch()
        end
        return planOptional(action, lease, contract) == true
    end
    if not watch() or action.Type ~= "ISInventoryTransferAction" or not saved.matches(action)
        or not saved.ordinary(action) or not action.item
        or action.destContainer ~= action.character:getInventory()
        or not saved.carried(action.srcContainer, action.character) or not watch() then return false end
    if method == "onWringClothing" and (not instanceof(action.item, "Clothing")
        or action.character:isEquipped(action.item)) then return false end
    local function guard(value)
        return value == action and watch() and saved.matches(value) and saved.ordinary(value) and watch()
    end
    local handle = prepare(action, {guard = guard,
        capture = function(value) return {source = value.srcContainer} end,
        observed = function() return false end})
    return handle ~= nil and watch()
end
Restoration.observeNative = observeNative

Restoration.borrowedReturns = borrowedReturns
return Restoration
