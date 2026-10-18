return function(legacy)
    local state = {faults = {}, writes = 0, opened = 0, closed = 0}
    state.files = {['PZSurvivorToolkit_ContextMenus.ini'] = legacy or ''}
    function state.reset(text)
        for path in pairs(state.files) do state.files[path] = nil end
        state.files['PZSurvivorToolkit_ContextMenus.ini'] = text or ''
        state.faults, state.writes = {}, 0
    end
    getFileReader = function(path, create)
        assert(create == true)
        local fault = state.faults[path] or {}
        if fault.open then error('reader open failed') end
        if fault.nilReader then return nil end
        if state.files[path] == nil then state.files[path] = '' end
        local contents, position = state.files[path], 1
        state.opened = state.opened + 1
        return {readLine = function()
            if fault.read or (fault.readback and fault.written) then error('reader failed') end
            if position > #contents then return nil end
            local finish = contents:find('\n', position, true)
            local line = contents:sub(position, finish and finish - 1 or #contents):gsub('\r$', '')
            position = finish and finish + 1 or #contents + 1
            return line
        end, close = function()
            state.closed = state.closed + 1
            if fault.close then error('reader close failed') end
        end}
    end
    getFileWriter = function(path, create, append)
        assert(create == true and append == false)
        local fault = state.faults[path] or {}
        state.writes = state.writes + 1
        if fault.nilWriter then return nil end
        if fault.writerOpen then error('writer open failed') end
        state.files[path], fault.written = '', true
        return {write = function(_, text)
            state.files[path] = fault.prefix and text:sub(1, fault.prefix) or text
            if fault.write then error('writer failed') end
        end, close = function() if fault.writerClose then error('writer close failed') end end}
    end
    return state
end
