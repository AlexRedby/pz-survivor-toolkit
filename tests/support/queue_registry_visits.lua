-- Count real queue traversal while preserving native iteration and error behavior.
return function(values, callback)
    local original, visits = ipairs, 0
    ipairs = function(sequence)
        local iterator, state, initial = original(sequence)
        if sequence ~= values then return iterator, state, initial end
        return function(current, index)
            local following, value = iterator(current, index)
            if value ~= nil then visits = visits + 1 end
            return following, value
        end, state, initial
    end
    local ok, failure = pcall(callback)
    ipairs = original
    assert(ok, failure)
    return visits
end
