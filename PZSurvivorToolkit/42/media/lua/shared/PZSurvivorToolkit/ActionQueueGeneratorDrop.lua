-- Scope these observations to one synchronous authority-side equip completion.
-- Tickets are local to the caller. They are never saved or accepted over the network.
local Drop = {}

local function heldSource(actor, item, root)
    return actor:getPrimaryHandItem() == item and actor:getSecondaryHandItem() == item
        and item:getContainer() == root and root:getItemWithID(item:getID()) == item
end

function Drop.begin(actor, tool)
    if isClient() or not actor or actor:isDead() or not tool or not actor:getCurrentSquare() then return end
    local begin = _G.toolkitGeneratorDropBegin
    local finish, cancel = _G.toolkitGeneratorDropFinish, _G.toolkitGeneratorDropCancel
    if type(begin) ~= 'function' or type(finish) ~= 'function' or type(cancel) ~= 'function' then return end
    local item, root = actor:getPrimaryHandItem(), actor:getInventory()
    if not item or item == tool or not heldSource(actor, item, root)
        or tool:getContainer() ~= root or root:getItemWithID(tool:getID()) ~= tool
        or not item:isForceDropHeavyItem() or not item:isRequiresEquippedBothHands() then return end
    local kind = item:getFullType()
    if not item:hasTag(ItemTag.GENERATOR) and not kind:find('.Generator', 1, true) then return end
    local fuel = item:hasModData() and item:getModData().fuel or 0
    -- Native IsoGenerator.load clamps the serialised fuel level to ten litres.
    if type(fuel) ~= 'number' or fuel < 0 or fuel > 10 or fuel ~= fuel then return end
    local ticket = {actor=actor, root=root, item=item, tool=tool, square=actor:getCurrentSquare(),
        kind=kind, condition=item:getCondition(), fuel=fuel, finish=finish, cancel=cancel}
    ticket.scope = begin(item)
    if ticket.scope then return ticket end
end

function Drop.cancel(ticket)
    if ticket and ticket.scope then
        local scope = ticket.scope
        ticket.scope = nil
        ticket.cancel(scope)
    end
end

-- The native bridge binds the original item reference during conversion. Coordinates,
-- sprite, condition and fuel describe a bound generator; they cannot select one.
function Drop.finish(ticket, actor, tool)
    if not ticket or not ticket.scope then return end
    local scope = ticket.scope
    ticket.scope = nil
    local generator = ticket.finish(scope)
    if not generator or isClient() or actor ~= ticket.actor or tool ~= ticket.tool or actor:isDead()
        or actor:getInventory() ~= ticket.root or actor:getCurrentSquare() ~= ticket.square
        or actor:getPrimaryHandItem() ~= tool or actor:getSecondaryHandItem() ~= nil
        or tool:getContainer() ~= ticket.root or ticket.root:getItemWithID(tool:getID()) ~= tool
        or ticket.root:getItemWithID(ticket.item:getID()) ~= nil
        or generator:getSquare() ~= ticket.square or generator:getGeneratorItemType() ~= ticket.kind
        or generator:getCondition() ~= ticket.condition or generator:getFuel() ~= ticket.fuel then return end
    return {actor=actor, generator=generator, square=ticket.square, tool=tool, root=ticket.root,
        sourceID=ticket.item:getID(), kind=ticket.kind, condition=ticket.condition, fuel=ticket.fuel}
end

-- A read-only availability check. Pickup and output ownership require separate evidence.
function Drop.target(record, actor)
    if not record or isClient() or actor ~= record.actor or actor:isDead() then return end
    local generator, square = record.generator, record.square
    local index = generator:getObjectIndex()
    if index < 0 or generator:getSquare() ~= square or index >= square:getObjects():size()
        or square:getObjects():get(index) ~= generator or not square:getSpecialObjects():contains(generator)
        or getCell():getGridSquare(square:getX(), square:getY(), square:getZ()) ~= square
        or generator:isConnected() or generator:isActivated()
        or record.kind and generator:getGeneratorItemType() ~= record.kind
        or record.condition and generator:getCondition() ~= record.condition
        or record.fuel and generator:getFuel() ~= record.fuel then return end
    local here = actor:getCurrentSquare()
    if here and (here == square or here:canReachTo(square)) then return generator end
end

return Drop
