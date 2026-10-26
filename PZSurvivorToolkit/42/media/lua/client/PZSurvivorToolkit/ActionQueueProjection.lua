-- Presentation-only structure. No action permissions, resources or effects are cached.
local Projection = {}

function Projection.capture(queue, previous)
    local state = previous and previous.queue == queue and previous or {queue = queue}
    local capture, currentIndex = toolkitQueueViewSnapshot, toolkitQueueViewCurrentIndex
    local native
    if type(capture) == "function" and type(currentIndex) == "function" then
        native = capture(queue.queue, state.capture == capture and state.native or nil, queue.current)
    end
    state.stable = native ~= nil and native == state.native and state.capture == capture
        and state.currentIndexReader == currentIndex
    state.native, state.capture, state.currentIndexReader = native, capture, currentIndex
    state.currentIndex = native and currentIndex(native) or nil
    -- The panel builds its groups together with rows in one pass. Unsupported
    -- queues must not pay for an extra Lua scan or allocate group records.
    if not state.stable then state.groups = nil end
    return state
end

return Projection
