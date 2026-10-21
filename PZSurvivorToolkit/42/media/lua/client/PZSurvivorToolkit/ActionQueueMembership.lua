local Membership = {}

-- Queue tables also change through native code and other mods. Inspect them
-- afresh, retaining only tracked identities instead of copying unrelated tails.
function Membership.find(registries)
    local pending, found, remaining = {}, {}, 0
    for _, registry in ipairs(registries) do
        for action in pairs(registry) do
            if not pending[action] then
                pending[action], remaining = true, remaining + 1
            end
        end
    end
    if remaining == 0 then return found end
    for character, queue in pairs(ISTimedActionQueue.queues) do
        if not character.isDead or not character:isDead() then
            for _, action in ipairs(queue.queue or {}) do
                if pending[action] then
                    pending[action], found[action], remaining = nil, true, remaining - 1
                    if remaining == 0 then return found end
                end
            end
        end
    end
    return found
end

return Membership
