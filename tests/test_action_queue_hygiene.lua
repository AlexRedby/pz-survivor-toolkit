if not NativeActionRoot then print('Hygiene native contracts SKIP.'); return end
local f = assert(loadfile(ProjectRoot .. '/tests/support/action_queue_native.lua'))()
for _, kind in ipairs({'ISWashClothing', 'ISWashYourself', 'ISDryMyself'}) do
    f.native('shared/TimedActions/' .. kind .. '.lua')
end
local nativeInstanceof = instanceof
instanceof = function(value, kind)
    return nativeInstanceof(value, kind) or (type(value) == 'table' and kind == 'InventoryItem' and value.item == true)
        or (type(value)=='table' and kind=='IsoObject' and value.class=='IsoWorldInventoryObject')
end
local client, server, clock = false, false, 2000
isClient, isServer = function() return client end, function() return server end
getTimeInMillis = function() return clock end
CharacterStat, Metabolics = {WETNESS='wetness', UNHAPPINESS='unhappiness'}, {LightDomestic=1}
ItemBodyLocation = {MAKE_UP_FULL_FACE=1, MAKE_UP_EYES=2, MAKE_UP_EYES_SHADOW=3, MAKE_UP_LIPS=4}
BloodBodyPartType = {MAX={index=function() return 1 end}, FromIndex=function(i) return i end}
local function list(...)
    local values = {...}
    return {class='List', size=function() return #values end, get=function(_, i) return values[i+1] end,
        isEmpty=function() return #values == 0 end}
end
BloodClothingType={getCoveredParts=function() return list() end}
Math={ceil=math.ceil}
local player, inventory = f.player, f.player.inventory
player.class = 'IsoPlayer'
inventory.values = {}
inventory.contains = function(self, item) return self.values[item:getID()] == item end
inventory.getItemById = function(self, id) return self.values[id] end
inventory.containsID = function(self, id) return self.values[id] ~= nil end
inventory.getSoapList = function(self) return self.soaps or list() end
inventory.getType = function() return 'none' end
inventory.getParent = function() end
inventory.getContainingItem = function() end
local wetness, blood, dirt, makeupRemoved = 80, 1, 1, 0
local stats = {get=function() return wetness end, remove=function() end}
player.getStats = function() return stats end
player.getBodyDamage = function() return {decreaseBodyWetness=function(_, amount) wetness=wetness-amount end} end
player.setMetabolicTarget, player.setIsFarming = function() end, function() end
player.getHumanVisual = function() return {getBlood=function() return blood end, getDirt=function() return dirt end,
    setBlood=function(_, _, value) blood=value end, setDirt=function(_, _, value) dirt=value end} end
player.getWornItem = function() end
player.removeWornItem = function() makeupRemoved=makeupRemoved+1 end
player.resetModelNextFrame = function() end
player.getCharacterActions = function() return {contains=function() return false end} end
ISLogSystem = {logAction=function() end}
sendHumanVisual, sendDamage = function() end, function() end
ISInventoryPaneContextMenu.getContainers = function() return {contains=function() return false end} end
local function item(kind)
    local value = f.item(kind); value.item, value.uses = true, 3
    value.getType = function() return kind:match('%.(.+)$') end
    if kind=='Base.BathTowel' or kind=='Base.DishCloth' then value.class='DrainableComboItem' end
    value.getCurrentUsesFloat = function(self) return self.uses end
    value.getCurrentUses = function(self) return self.uses end
    value.Use = function(self) self.uses=self.uses-1; self.spent=(self.spent or 0)+1 end
    value.UseAndSync = value.Use
    value.getItemAfterCleaning = function() end
    value.getBloodLevel = function() return 1 end
    value.getBloodClothingType = function() return 'Shirt' end
    value.getIsCraftingConsumed = function() return false end
    value.getContainer = function(self) return inventory:contains(self) and inventory or nil end
    inventory.values[value:getID()] = value
    return value
end
local function sink()
    return {class='IsoObject', water=10, getFluidAmount=function(self) return self.water end,
        useFluid=function(self, amount) self.water=self.water-amount; self.spent=(self.spent or 0)+amount; return amount end,
        transmitModData=function() end}
end
local function book()
    local value = f.action(ISReadABook, {item=item('Base.Book')})
    value.begin=function(self) self.begun=true end
    return value
end
f.project('ActionQueueOperations'); f.project('ActionQueueDefinitions'); f.project('ActionQueueLabels')
local policy = f.project('ActionQueuePolicy')
local api = f.project('ActionQueue')
local function dry(towel)
    local value = ISDryMyself:new(player, towel); value.toolkitQueueOperation={}; return value
end
local function wash(target, soap)
    local value = f.action(ISWashClothing, {item=target, sink=sink(), soaps=soap and list(soap) or list(), noSoap=true})
    return value
end
local head, tail, towel = book(), book(), item('Base.BathTowel')
local drying = dry(towel)
local q = f.queue(head, drying, tail)
assert(policy.inspect(drying).interrupt == 'finish-step' and not policy.stoppable(drying))
assert(not policy.moveReason(q, drying, tail, true), 'drying can cross an independent book')
assert(api.cancel(q, drying) and q.queue[1]==head and q.queue[2]==tail and towel.uses==3,
    'waiting cancellation consumes nothing and preserves both unrelated ends')
local pickup=f.action(ISInventoryTransferAction, {item=towel})
drying=dry(towel); drying.toolkitQueueOperation=pickup.toolkitQueueOperation
q=f.queue(head, pickup, drying, tail)
assert(api.cancelOperation(q, drying) and q.queue[1]==head and q.queue[2]==tail and #q.queue==2,
    'waiting cancellation removes the owned pickup and dry chain together')
local soap = item('Base.Soap2'); soap.class='DrainableComboItem'
local clothing = item('Base.Shirt'); clothing.class='Clothing'
local first, second = wash(clothing, soap), wash(item('Base.Shirt2'), soap)
second.item.class='Clothing'
q=f.queue(head, first, second)
assert(policy.moveReason(q, first, second, true)=='move_shared_item')
assert(policy.cancelOperationReason(q, first)=='operation_shared_item', 'soap is shared even on a no-soap clothing wash')
first.soaps=list(); second.soaps=list(); second.sink=first.sink
assert(policy.moveReason(q, first, second, true)=='move_dependent', 'one sink remains a shared resource')
second.sink=sink()
assert(not policy.moveReason(q, first, second, true), 'separate no-soap washes can move')
local bucket=item('Base.Bucket')
first.sink={class='IsoWorldInventoryObject', getItem=function() return bucket end}
local moveBucket=f.action(ISInventoryTransferAction, {item=bucket})
q=f.queue(head, first, moveBucket)
assert(policy.moveReason(q, first, moveBucket, true)=='move_shared_item', 'world water containers retain their item identity')
first.sink=sink()
local otherDry = dry(towel)
q=f.queue(head, drying, otherDry)
assert(policy.moveReason(q, drying, otherDry, true)=='move_shared_item')
assert(policy.cancelOperationReason(q, drying)=='operation_shared_item')
otherDry.item=item('Base.DishCloth')
assert(policy.moveReason(q, drying, otherDry, true)=='move_dependent', 'drying shares player wetness even with different towels')
local bodyWash=f.action(ISWashYourself, {sink=sink(), soaps=list(soap)})
assert(policy.inspect(bodyWash).knownInputs==false, 'server soap selection and makeup removal are not frozen inputs')
local calls=0
first.soaps={size=function() calls=calls+1; return 0 end}
assert(not policy.inspect(first) and calls==0, 'foreign soap selector is never called')
first.soaps=list(soap)
local original=ISWashClothing.GetRequiredWater
ISWashClothing.GetRequiredWater=function() calls=calls+1; return 0 end
assert(not policy.inspect(first) and not policy.hygieneUnavailable(first) and calls==0,
    'a replaced helper closes inspection and depletion checks')
ISWashClothing.GetRequiredWater=original
drying.onStartFunc=function() calls=calls+1 end
assert(not policy.inspect(drying) and not policy.hygieneUnavailable(drying) and calls==0)
drying.onStartFunc=nil

-- Native SP update spends the towel before completion; finishing or cancelling must never replay it.
wetness=80; towel.uses=3; drying=dry(towel); tail=book(); q=f.queue(drying, tail)
drying:update()
assert(towel.uses==2 and towel.spent==1 and wetness==72)
assert(api.cancelOperation(q, drying) and q.toolkitGroupCancel and not q.toolkitCancel,
    'active drying finishes its native step instead of force-stopping or resuming')
assert(towel.spent==1 and drying:complete(), 'cancellation itself does not spend an extra use')
drying:perform()
assert(q.queue[1]==tail and #q.queue==1 and tail.begun and towel.spent==1,
    'native completion retains the unrelated tail and never reconstructs drying')

-- A current dry finishes once while the rest of its operation is discarded.
towel.uses=3; drying=dry(towel); local follow=dry(item('Base.DishCloth'))
follow.toolkitQueueOperation=drying.toolkitQueueOperation
tail=book(); q=f.queue(drying, follow, tail)
assert(api.cancelOperation(q, drying))
drying:complete(); drying:perform()
assert(q.queue[1]==tail and #q.queue==1 and not follow.action,
    'current cancellation drops the remaining hygiene chain and preserves the tail')

-- Native MP server ticks spend once per event and force completion only after depletion.
server=true; towel.uses=1; drying=dry(towel)
drying.netAction={forceComplete=function(self) self.completed=true end}
local previous=towel.spent
drying:animEvent('serverTick')
assert(towel.uses==0 and towel.spent==previous+1)
drying:animEvent('serverTick')
assert(drying.netAction.completed and towel.spent==previous+1 and drying:complete())
server=false

-- Native body wash spends only its dirty parts, and a second completion has no resource effect.
blood,dirt=1,1; soap.uses=2; bodyWash.sink=sink()
assert(bodyWash:complete() and soap.uses==1 and bodyWash.sink.water==9)
assert(bodyWash:complete() and soap.uses==1 and bodyWash.sink.water==9)

-- Real clothing completion owns its soap/water mutation; cancellation never calls it early.
local garment=item('Base.Shirt'); garment.class='Clothing'
local garmentBlood=1
garment.getBlood=function() return garmentBlood end
garment.getDirt=function() return 1 end
garment.setBlood=function(_, _, value) garmentBlood=value end
garment.setDirt, garment.setWetness, garment.setDirtiness, garment.setBloodLevel=function() end, function() end, function() end, function() end
garment.setJobDelta=function() end
garment.getBloodClothingType=function() return 'Shirt' end
soap.hasComponent=function() return false end
BloodClothingType.getCoveredParts=function() return list(0) end
ComponentType={FluidContainer=1}
syncItemFields, syncVisuals, triggerEvent=function() end, function() end, function() end
player.updateHandEquips, player.resetModel=function() end, function() end
player.isPrimaryHandItem, player.isSecondaryHandItem=function() return false end, function() return false end
local cleaning=wash(garment, soap); cleaning.noSoap=false
soap.uses=2; tail=book(); q=f.queue(cleaning, tail)
assert(api.cancelOperation(q, cleaning) and soap.uses==2 and cleaning.sink.water==10)
assert(cleaning:complete() and soap.uses==1 and cleaning.sink.water==2)
cleaning:perform()
assert(q.queue[1]==tail and #q.queue==1 and soap.uses==1 and cleaning.sink.water==2)
BloodClothingType.getCoveredParts=function() return list() end

-- A depleted native action would stop and reset the queue. Skip only audited unavailable steps.
wetness=50; towel.uses=0; drying=dry(towel); tail=book(); q=f.queue(head, drying, tail)
assert(not drying:isValid() and policy.hygieneUnavailable(drying))
policy.skipUnavailableHygiene(q)
assert(q.queue[1]==head and q.queue[2]==tail and #q.queue==2)
towel.uses=0; drying=dry(towel); tail=book(); q=f.queue(head, drying, tail)
q:onCompleted(head)
assert(q.current==tail and #q.queue==1 and tail.begun,
    'the controller skips an exhausted next towel before native queue advancement')
for _, state in ipairs({'exhausted', 'removed', 'dry'}) do
    wetness=50; towel.uses=state=='exhausted' and 0 or 2
    inventory.values[towel:getID()]=towel
    if state=='removed' then inventory.values[towel:getID()]=nil end
    if state=='dry' then wetness=0 end
    drying=dry(towel); tail=book(); q=f.queue(drying, tail)
    drying.action={}
    assert(not drying:isValid())
    drying:stop()
    assert(#q.queue==2 and q.toolkitCancelStopped, 'native '..state..' stop preserves the tail until Java removal')
    q:tick()
    assert(q.current==tail and #q.queue==1 and tail.begun,
        'native '..state..' stop advances once without reconstructing or clearing the tail')
end
wetness=50
towel.uses=2; inventory.values[towel:getID()]=nil
assert(policy.hygieneUnavailable(drying), 'removed towels are unavailable')
inventory.values[towel:getID()]=towel
local replica=item('Base.BathTowel'); replica.id=towel:getID(); inventory.values[towel:getID()]=replica
client=true; drying:start()
assert(drying.item==replica and not policy.hygieneUnavailable(drying), 'native MP start rebinds the same item ID')
replica.uses=0
assert(not policy.hygieneUnavailable(drying), 'running MP item depletion awaits the authoritative completion')
drying.started=false
assert(policy.hygieneUnavailable(drying), 'waiting MP depletion is unavailable')
local stale=item('Base.BathTowel'); stale.uses=2
local live=item('Base.BathTowel'); live.id=stale:getID(); live.uses=0
inventory.values[stale:getID()]=live
local reboundDry=dry(stale)
assert(policy.hygieneUnavailable(reboundDry), 'MP preflight reads the depleted live same-ID towel instead of its stale full proxy')
head,tail=book(),book(); q=f.queue(head,reboundDry,tail)
policy.skipUnavailableHygiene(q)
assert(q.queue[1]==head and q.queue[2]==tail and #q.queue==2, 'depleted live replacement is skipped before it can enter native MP start')
stale.uses=0; live.uses=2
assert(not policy.hygieneUnavailable(reboundDry), 'MP preflight preserves a full live replacement behind an empty stale proxy')
reboundDry:start()
assert(reboundDry.item==live and reboundDry:isValid(), 'native MP start binds the available same-ID replacement')
for _,kind in ipairs({'Base.BathTowelWet','Base.DishClothWet'}) do
    local original=item(kind=='Base.BathTowelWet' and 'Base.BathTowel' or 'Base.DishCloth')
    local replacement=item(kind); replacement.uses=1
    assert(original:getID()~=replacement:getID(), 'native depletion creates a new wet item ID')
    inventory.values[original:getID()]=nil
    local duplicate=dry(original)
    -- ReplaceInventoryItemInContainerPacket rewrites queued fields to this new item/ID.
    duplicate.item=replacement
    assert(duplicate:isValid(), 'native validity alone accepts the normal wet replacement')
    assert(policy.hygieneUnavailable(duplicate), 'wet replacement must not enter another native dry/use')
    local completedDry=dry(original); completedDry.item=replacement; completedDry.started=true
    tail=book(); q=f.queue(completedDry,duplicate,tail)
    assert(policy.cancelReason(q,duplicate)=='dependent' and policy.moveReason(q,duplicate,tail,true)=='move_dependent',
        'recognizing an unavailable wet replacement must not grant cancellation or movement')
    assert(not policy.evaluateMove(q,duplicate,tail,true).allowed and not policy.evaluateCancel(q,duplicate).allowed
        and not policy.evaluateCancel(q,duplicate,true).allowed, 'wet replacement rejects both action and operation edits')
    completedDry:perform()
    assert(#q.queue==1 and q.current==tail and tail.begun and inventory:contains(replacement) and not replacement.spent,
        'native completion skips the rebound duplicate, preserves its wet output and starts unrelated reading')
    duplicate.started=true
    assert(not policy.hygieneUnavailable(duplicate), 'running MP replacement still waits for native authority')
end
for _,kind in ipairs({'Base.Apple','Base.HandTowel','Mod.BathTowelWet'}) do
    local arbitrary=dry(item(kind))
    assert(not policy.inspect(arbitrary) and not policy.hygieneUnavailable(arbitrary), 'arbitrary normal items gain neither a dry contract nor skipping')
    head,tail=book(),book(); q=f.queue(head,arbitrary,tail)
    assert(not policy.evaluateMove(q,arbitrary,tail,true).allowed and not policy.evaluateCancel(q,arbitrary).allowed
        and not policy.evaluateCancel(q,arbitrary,true).allowed, 'arbitrary normal items gain no movement or cancellation permissions')
end
client=false
reboundDry.item=stale; reboundDry.started=false
assert(policy.hygieneUnavailable(reboundDry) and not reboundDry:isValid(), 'SP retains native item-reference containment instead of accepting a same-ID replacement')
first.item=clothing; first.sink.water=0
assert(policy.hygieneUnavailable(first), 'insufficient washing water cannot clear a following book')
first.sink.water=100; inventory.values[clothing:getID()]=nil
assert(policy.hygieneUnavailable(first), 'removed clothing is unavailable on the authoritative side')
bodyWash.sink.water=0
assert(policy.hygieneUnavailable(bodyWash))
print('Native hygiene resource conflicts, finish-step cancellation, SP/MP depletion and guarded skipping passed.')
