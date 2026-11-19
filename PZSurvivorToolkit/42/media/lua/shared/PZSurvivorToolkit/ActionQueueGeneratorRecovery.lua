-- One outstanding recovery episode per actor. An arm grants observation of an
-- exact native equip; only its synchronous drop evidence can select a generator.
require 'TimedActions/ISEquipWeaponAction'
require 'TimedActions/ISTakeGenerator'
local Drop = require 'PZSurvivorToolkit/ActionQueueGeneratorDrop'
local Proof = require 'PZSurvivorToolkit/SourceProof'
local Recovery = {}
PZSurvivorToolkit = PZSurvivorToolkit or {}
PZSurvivorToolkit.ActionQueueGeneratorRecovery = Recovery
local slots, seal = {}, {}
local equip, take, base = ISEquipWeaponAction, ISTakeGenerator, ISBaseTimedAction
local nativeComplete, nativeTake = equip.complete, take.complete
local nativeDuration, nativeStart = take.getDuration, take.start
local nativeDrop, nativeForce, factory = forceDropHeavyItems, isForceDropHeavyItem, instanceItem
local factoryClass = getClassSimpleName and getClassSimpleName(factory)
local equipMethods, takeMethods = {}, {}
for name, value in pairs(equip) do if type(value) == 'function' then equipMethods[name] = value end end
for name, value in pairs(take) do if type(value) == 'function' then takeMethods[name] = value end end
local supported
local function qualify()
    if supported == nil then
        supported = Proof.matches('media/lua/shared/TimedActions/ISEquipWeaponAction.lua', 4004646560, nil, true)
            and Proof.matches('media/lua/shared/TimedActions/ISTakeGenerator.lua', 2180174053)
            and Proof.closure(nativeComplete, 'ISEquipWeaponAction.lua')
            and Proof.closure(nativeTake, 'ISTakeGenerator.lua')
    end
    return supported
end
local function dropBindings()
    local drop, force = forceDropHeavyItems, isForceDropHeavyItem
    if force ~= nativeForce then return end
    if drop == nativeDrop and Proof.closure(drop, 'ISEquipWeaponAction.lua') then return drop, force end
    -- The known cart guard delegates to this exact native body. Its private
    -- predecessor is inspected rather than trusted by a filename alone.
    local facts, api, carts = toolkitLuaCaptureFactsMatch, toolkitLuaCaptureFactsApiMatches, SaucedCarts
    if not carts or type(facts) ~= 'function' or type(api) ~= 'function' or not api(facts)
        or not Proof.closure(drop, 'ForceDropGuard.lua')
        or not Proof.matches('media/lua/shared/SaucedCarts/ForceDropGuard.lua', 538857615, 'SaucedCarts', true)
        or not Proof.matches('media/lua/shared/SaucedCarts/Core.lua', 2570266575, 'SaucedCarts', true) then return end
    local classifier = carts.isCart
    if not facts(classifier, {fingerprint='a23d4ea275d694882863b5c3aa41c3be83751644d2977e050d5db1f46d6866be',
        parameters=1, upvalues=1, captures={{slot=0,test='identity',value=type}}}) then return end
    if facts(drop, {fingerprint='f6ccb8ddc816f321a1991074a1b2973a506d86f2c45626437da0221627c401d4',
        parameters=1, upvalues=2, captures={{slot=0,test='closure',recipe={fingerprint='230c76818b99cb8981839c5b1b50388f3617244c01bfdf169e9b8fe0058ac1c5',parameters=1,upvalues=0,captures={}}},
            {slot=1,test='identity',value=classifier}}}) then return drop, force, carts, classifier end
end
local serverComplete, pickupComplete, installServerWrapper
local consumedKey = {}
local function live()
    if not qualify() then return false, 'native-source' end
    if ISEquipWeaponAction ~= equip or ISTakeGenerator ~= take or ISBaseTimedAction ~= base then return false, 'native-class' end
    if instanceItem ~= factory then return false, 'factory-replaced' end
    if factoryClass ~= 'LuaJavaInvoker' and factoryClass ~= 'MultiLuaJavaInvoker' then return false, 'factory-class:' .. tostring(factoryClass) end
    for name, callback in pairs(equipMethods) do
        if equip[name] ~= (name == 'complete' and serverComplete or callback) then return false, 'equip-method:' .. tostring(name) end
    end
    for name, callback in pairs(takeMethods) do
        if take[name] ~= (name == 'complete' and pickupComplete or callback) then return false, 'pickup-method:' .. tostring(name) end
    end
    for name, callback in pairs(equip) do
        if type(callback) == 'function' and not equipMethods[name] then return false, 'equip-added-method:' .. tostring(name) end
    end
    for name, callback in pairs(take) do
        if type(callback) == 'function' and not takeMethods[name] then return false, 'pickup-added-method:' .. tostring(name) end
    end
    return true
end
local function integer(value)
    return type(value) == 'number' and value == value and value % 1 == 0
        and value >= -2147483648 and value <= 2147483647
end
local function arguments(sourceID, toolID, episode)
    return integer(sourceID) and integer(toolID) and sourceID ~= toolID
        and type(episode) == 'number' and episode > 0 and episode <= 9007199254740991 and episode % 1 == 0
end
local function actorValid(actor)
    return actor and instanceof(actor, 'IsoPlayer') and not actor:isDead() and actor:getCurrentSquare() ~= nil
end
local function rootItem(root, id)
    local item = root:getItemWithID(id)
    if item and item:getContainer() == root then return item end
end
local function toolValid(item)
    return item and (item:getFullType() == 'Base.Razor' or item:getFullType() == 'Base.Scissors')
        and not item:isForceDropHeavyItem() and not item:isRequiresEquippedBothHands()
end
local function fresh(record)
    return record and getTimestampMs() < record.deadline
end
local function carried(record)
    return actorValid(record.actor) and record.actor:getInventory() == record.root
        and rootItem(record.root, record.toolID) == record.tool and toolValid(record.tool)
end
local function heldTool(record)
    return carried(record) and record.actor:getPrimaryHandItem() == record.tool
        and record.actor:getSecondaryHandItem() == nil
end
local function armDenied(actor, reason)
    -- Optional diagnostic observer; normal gameplay installs no callback and
    -- retains no failure history or actor registry.
    if type(Recovery.onArmDenied) == 'function' then pcall(Recovery.onArmDenied, actor, reason) end
    return false, reason
end
function Recovery.arm(actor, args)
    if isClient() or not actorValid(actor) or type(args) ~= 'table' then return armDenied(actor, 'authority-actor-or-args') end
    -- Replacing an abandoned episode must not leave its world object adoptable.
    slots[actor] = nil
    local valid, reason = live()
    if not valid then return armDenied(actor, reason) end
    if not arguments(args.sourceID, args.toolID, args.episode) then return armDenied(actor, 'episode-arguments') end
    local drop, force, carts, classifier = dropBindings()
    if not drop then return armDenied(actor, 'drop-helper-binding') end
    Recovery.prune()
    local count = 0
    for _ in pairs(slots) do count = count + 1 end
    if count >= 64 then return armDenied(actor, 'episode-capacity') end
    local root = actor:getInventory()
    local source, tool = rootItem(root, args.sourceID), rootItem(root, args.toolID)
    if not source or not toolValid(tool) or actor:getPrimaryHandItem() ~= source
        or actor:getSecondaryHandItem() ~= source or not source:isForceDropHeavyItem()
        or not source:isRequiresEquippedBothHands() then return armDenied(actor, 'held-source-or-tool-ownership') end
    local kind = source:getFullType()
    if not source:hasTag(ItemTag.GENERATOR) and not kind:find('.Generator', 1, true) then return armDenied(actor, 'source-not-generator') end
    slots[actor] = {actor=actor, root=root, source=source, sourceID=args.sourceID,
        tool=tool, toolID=args.toolID, episode=args.episode, deadline=getTimestampMs() + 300000,
        dropBinding=drop, forceBinding=force, carts=carts, classifier=classifier}
    installServerWrapper()
    return true
end
function Recovery.cancel(actor, episode)
    local record = slots[actor]
    if record and record.episode == episode then slots[actor] = nil end
end
function Recovery.beforeEquip(action)
    if isClient() or type(action) ~= 'table' or getmetatable(action) ~= equip
        or action.Type ~= 'ISEquipWeaponAction' or action.primary ~= true or action.twoHands ~= nil and action.twoHands ~= false
        or action.alwaysTurnOn or action.fromHotbar or action.onCompleteFunc or action.additionalTest then return end
    local record = slots[action.character]
    if not fresh(record) or not live() or record.drop or record.equip or not carried(record)
        or forceDropHeavyItems ~= record.dropBinding or isForceDropHeavyItem ~= record.forceBinding
        or record.carts and (SaucedCarts ~= record.carts or record.carts.isCart ~= record.classifier) or action.item ~= record.tool
        or rootItem(record.root, record.sourceID) ~= record.source
        or record.actor:getPrimaryHandItem() ~= record.source
        or record.actor:getSecondaryHandItem() ~= record.source then return end
    local ticket = Drop.begin(record.actor, record.tool)
    if ticket then
        record.equip = action
        return {seal=seal, record=record, action=action, ticket=ticket}
    end
end
function Recovery.afterEquip(attempt, action, succeeded)
    if type(attempt) ~= 'table' or attempt.seal ~= seal or attempt.action ~= action then return end
    attempt.seal = nil
    local record = attempt.record
    if not succeeded or slots[record.actor] ~= record or record.equip ~= action or not live()
        or forceDropHeavyItems ~= record.dropBinding or isForceDropHeavyItem ~= record.forceBinding then
        Drop.cancel(attempt.ticket)
        if slots[record.actor] == record then slots[record.actor] = nil end
        return
    end
    local drop = Drop.finish(attempt.ticket, record.actor, record.tool)
    if not drop or drop.sourceID ~= record.sourceID or not heldTool(record) then
        slots[record.actor] = nil
        return
    end
    record.drop = drop
end
-- SP observes its already-owned per-instance equip lifecycle instead. The
-- server has no client wrappers and captures only the explicitly armed episode.
installServerWrapper = function()
    if isServer() and not pickupComplete then
        pickupComplete = function(action)
            local generator = action.generator
            if generator and generator:hasModData() and generator:getModData()[consumedKey] == seal then return true end
            return nativeTake(action)
        end
        take.complete = pickupComplete
    end
    if not isServer() or serverComplete then return end
    serverComplete = function(action)
        if not slots[action.character] then return nativeComplete(action) end
        local attempt = Recovery.beforeEquip(action)
        local ok, result = pcall(nativeComplete, action)
        Recovery.afterEquip(attempt, action, ok and result == true)
        if not ok then error(result, 0) end
        return result
    end
    equip.complete = serverComplete
end
function Recovery.authorizes(owner, name, callback)
    return live() and name == 'complete' and (serverComplete ~= nil and owner == equip and callback == serverComplete
        or pickupComplete ~= nil and owner == take and callback == pickupComplete)
end
local function receipt(actor, sourceID, toolID, episode, output, unknown)
    if not arguments(sourceID, toolID, episode) then return end
    local args = {sourceID=sourceID, toolID=toolID, episode=episode, skipped=output == nil and not unknown, unknown=unknown == true}
    if output then args.outputID, args.outputType = output:getID(), output:getFullType() end
    if isServer() then
        args.onlineID = actor:getOnlineID()
        sendServerCommand(actor, 'PZSurvivorToolkitGenerator', 'Recovered', args)
    elseif type(Recovery.onRecovered) == 'function' then Recovery.onRecovered(actor, args) end
end
PZSurvivorToolkitGeneratorRecovery = ISBaseTimedAction:derive('PZSurvivorToolkitGeneratorRecovery')
local Action = PZSurvivorToolkitGeneratorRecovery
function Action:new(character, sourceID, toolID, episode)
    -- These named fields are the complete native timed-action wire contract.
    local action = ISBaseTimedAction.new(self, character)
    action.sourceID, action.toolID, action.episode = sourceID, toolID, episode
    action.maxTime = nativeDuration(action)
    if not isClient() and arguments(sourceID, toolID, episode) then
        local record = slots[character]
        if fresh(record) and record.sourceID == sourceID and record.toolID == toolID and record.episode == episode then
            action.toolkitGeneratorRecovery = {seal=seal, record=record}
        end
    end
    return action
end
function Action:getDuration() return nativeDuration(self) end
-- A stale recovery is an ordinary completed no-op, so independent queue work
-- after it survives. Authority checks immediately before any pickup side effect.
function Action:isValid() return actorValid(self.character) end
function Action:start() nativeStart(self) end
function Action:update() self.character:setMetabolicTarget(Metabolics.HeavyWork) end
function Action:perform() ISBaseTimedAction.perform(self) end
function Action:complete()
    if isClient() or self.toolkitGeneratorRecoveryTerminal == seal then return true end
    self.toolkitGeneratorRecoveryTerminal = seal
    local evidence = self.toolkitGeneratorRecovery
    self.toolkitGeneratorRecovery = nil
    local record = type(evidence) == 'table' and evidence.seal == seal and evidence.record
    local output, unknown
    if fresh(record) and slots[self.character] == record and record.actor == self.character
        and record.sourceID == self.sourceID and record.toolID == self.toolID and record.episode == self.episode then
        slots[self.character] = nil
        local generator = live() and forceDropHeavyItems == record.dropBinding
            and isForceDropHeavyItem == record.forceBinding and heldTool(record) and record.drop and Drop.target(record.drop, self.character)
        if generator and record.root:getItemWithID(record.sourceID) == nil and not self.character:getVehicle()
            and takeMethods.isValid({character=self.character, generator=generator})
            and (not isServer() or SafeHouse.isSafehouseAllowLoot(generator:getSquare(), self.character)) then
            -- The pinned stock body allocates through the pinned native
            -- factory and equips exactly that allocation in both hands.
            local condition, fuel, kind = generator:getCondition(), generator:getFuel(), generator:getGeneratorItemType()
            unknown = true
            local ok, result = pcall(nativeTake, {character=self.character, generator=generator})
            local item = self.character:getPrimaryHandItem()
            if ok and result == true and item and item == self.character:getSecondaryHandItem() and item ~= record.tool and item ~= record.source
                and rootItem(record.root, item:getID()) == item and item:getID() ~= record.sourceID
                and item:getFullType() == kind and item:getCondition() == condition
                and (item:hasModData() and item:getModData().fuel or 0) == fuel
                and generator:getObjectIndex() == -1 then output, unknown = item, false end
            -- Native pickup does not revalidate its target at complete(). Guard
            -- a competing, already-running stock pickup of this exact consumed
            -- object. This removed object owns the inert marker; no registry or
            -- saved world state retains it after native action references die.
            if isServer() and generator:getObjectIndex() == -1 then generator:getModData()[consumedKey] = seal end
        end
    end
    -- Report both outcomes immediately; an intentional skip is terminal too.
    pcall(receipt, self.character, self.sourceID, self.toolID, self.episode, output, unknown)
    return true
end
function Recovery.prune()
    -- Lazy, bounded metadata cleanup only; never poll inventory/world state.
    local online = isServer() and getOnlinePlayers()
    for actor, record in pairs(slots) do
        if not fresh(record) or actor:isDead() or online and not online:contains(actor) then slots[actor] = nil end
    end
end
if Events.OnDisconnect then Events.OnDisconnect.Add(function() slots = {} end) end
if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function() slots = {} end) end
return Recovery
