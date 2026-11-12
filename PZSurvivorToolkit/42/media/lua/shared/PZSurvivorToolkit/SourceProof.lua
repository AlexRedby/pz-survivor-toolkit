local Proof = {}
local utf8Strings = string.byte("洗") == 230

local function hash(reader, adler, limit)
    local value, sum, units = adler and 1 or 5381, 0, 0
    local function add(code)
        units = units + 1
        if units > limit then return false end
        if adler then
            value = (value + code) % 65521
            sum = (sum + value) % 65521
        else
            value = (value * 33 + code) % 4294967296
        end
        return true
    end
    while true do
        local line = reader:readLine()
        if line == nil then break end
        if type(line) ~= "string" then return end
        local i = 1
        while i <= #line do
            local code = string.byte(line, i)
            if utf8Strings and code >= 128 then
                local count
                if code >= 194 and code < 224 then count = 2
                elseif code >= 224 and code < 240 then count = 3
                elseif code >= 240 and code <= 244 then count = 4
                else return end
                code = code % (2 ^ (7 - count))
                for offset = 1, count - 1 do
                    local nextByte = string.byte(line, i + offset)
                    if not nextByte or nextByte < 128 or nextByte > 191 then return end
                    code = code * 64 + nextByte % 64
                end
                if (count == 3 and code < 2048) or (count == 4 and code < 65536)
                    or code > 1114111 or (code >= 55296 and code <= 57343) then return end
                i = i + count - 1
                if code > 65535 then
                    code = code - 65536
                    if not add(55296 + math.floor(code / 1024)) then return end
                    code = 56320 + code % 1024
                end
            end
            if not add(code) then return end
            i = i + 1
        end
        -- Java readLine strips line endings; pins include one LF per returned line.
        if not add(10) then return end
    end
    return adler and sum * 65536 + value or value
end

-- Kahlua rawget follows metatables, unlike Lua 5.1. pairs inspects only the
-- table's own delegate, without invoking inherited callbacks or __index.
function Proof.own(owner, key)
    if type(owner) ~= "table" then return nil end
    for name, value in pairs(owner) do if name == key then return value end end
    return nil
end

function Proof.checksum(reader, adler, limit)
    return hash(reader, adler, limit or 2000000)
end

function Proof.matches(path, expected, mod, adler, limit)
    local input = mod and getModFileReader or getGameFilesInput
    if type(input) ~= "function" or type(expected) ~= "number" then return false end
    local opened, reader
    if mod then opened, reader = pcall(input, mod, path, false)
    else opened, reader = pcall(input, path) end
    if not opened or not reader then return false end
    local valid, checksum = pcall(hash, reader, adler, limit or 2000000)
    local closed = pcall(function() reader:close() end)
    return valid and closed and checksum ~= nil and checksum == expected
end

local filenameAccessor = getFilenameOfClosure
local closureSources, closureCount = {}, 0
function Proof.closure(callback, filename)
    local accessor = getFilenameOfClosure
    local memoize = accessor == filenameAccessor
    -- A replacement accessor may compute changing results. Keep it live rather
    -- than assuming it has the native binding's compile-time metadata semantics.
    if not memoize then closureSources, closureCount = {}, 0 end
    if type(callback) ~= "function" or type(accessor) ~= "function" or type(filename) ~= "string" then return false end
    local source = memoize and closureSources[callback]
    if not source then
        local ok, path = pcall(accessor, callback)
        if not ok or type(path) ~= "string" then return false end
        source = path:gsub("\\", "/"):match("([^/]+)$")
        if not source then return false end
        -- Native getFilenameOfClosure reads the loaded prototype's compile-time
        -- filename. Retain only that metadata; callback identities, file contents
        -- and the live facts used by callers are still checked independently.
        -- Kahlua ignores weak-table modes, so bound retained callback identities.
        if memoize then
            if closureCount >= 1024 then closureSources, closureCount = {}, 0 end
            closureSources[callback] = source
            closureCount = closureCount + 1
        end
    end
    return source == filename
end

-- Query-local Lua bindings, not a proof of behavior or a cached queue decision.
-- Reviewed owners select their dependencies; arbitrary guard callbacks gain no
-- authority from making a watcher. No getter or metatable callback is invoked.
local bindingType, bindingMeta, bindingRaw = type, getmetatable, rawget
local bindingPairs, bindingEach, bindingEqual = pairs, ipairs, rawequal
local bindingNativeMeta, bindingGlobals = toolkitLuaMetatableMatches, _G
local function actualBindingMeta(owner, expected)
    if bindingType(bindingNativeMeta) ~= "function" then return expected == nil end
    return bindingMeta(bindingGlobals) == nil
        and bindingEqual(bindingRaw(bindingGlobals,"toolkitLuaMetatableMatches"),bindingNativeMeta)
        and bindingNativeMeta(owner, expected) == true
end
-- Native timed-action inheritance only. Prove parents before Kahlua rawget,
-- which follows __index; never use an inherited read to attest its own lookup.
function Proof.nativeActionClassChain(object, base, class, constructing)
    if bindingType(bindingNativeMeta) ~= "function" or not bindingNativeMeta(bindingGlobals,nil)
        or not bindingEqual(bindingRaw(bindingGlobals,"toolkitLuaMetatableMatches"),bindingNativeMeta)
        or not bindingEqual(bindingRaw(bindingGlobals,"rawget"),bindingRaw)
        or not bindingEqual(bindingRaw(bindingGlobals,"rawequal"),bindingEqual)
        or not bindingEqual(bindingRaw(bindingGlobals,"type"),bindingType)
        or not bindingEqual(bindingRaw(bindingGlobals,"ISBaseObject"),object)
        or not bindingEqual(bindingRaw(bindingGlobals,"ISBaseTimedAction"),base)
        or bindingType(object) ~= "table" or bindingType(base) ~= "table" or bindingType(class) ~= "table"
        or not bindingNativeMeta(object,nil) or not bindingEqual(bindingRaw(object,"__index"),object)
        or not bindingNativeMeta(base,object) or not bindingEqual(bindingRaw(base,"__index"),base)
        or not bindingNativeMeta(class,base) then return false end
    local index = bindingRaw(class,"__index")
    -- Before the first native constructor this slot is absent (or inherited
    -- base in Kahlua). Every constructed instance requires the class itself.
    return bindingEqual(index,class) or constructing == true and (index == nil or bindingEqual(index,base))
end
local function bindingArray(value, limit)
    if bindingType(value) ~= "table" or bindingMeta(value) ~= nil then return end
    local count, maximum = 0, 0
    for key in bindingPairs(value) do
        count = count + 1
        if count > limit or bindingType(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > limit then return end
        if key > maximum then maximum = key end
    end
    if count == maximum then return count end
end
-- A private weak-mode metatable has no inherited binding for these keys.
-- Prove and retain its tiny exact shape, then use native rawget for selected
-- fields without scanning an arbitrarily large action/loan registry.
local function inertBindingParent(parent, keys)
    if bindingType(parent)~="table" or bindingMeta(parent)~=nil or not actualBindingMeta(parent,nil) then return end
    local count=0
    for key in bindingPairs(parent) do
        if key~="__mode" then return end
        count=count+1
    end
    for key in bindingPairs(keys) do if bindingRaw(parent,key)~=nil then return end end
    return {owner=parent,mode=bindingRaw(parent,"__mode"),count=count}
end
local function bindingParentUnchanged(parent)
    if bindingMeta(parent.owner)~=nil or not actualBindingMeta(parent.owner,nil) then return false end
    local count=0
    for key,value in bindingPairs(parent.owner) do
        count=count+1
        if count>parent.count or key~="__mode" or not bindingEqual(value,parent.mode) then return false end
    end
    return count==parent.count
end
function Proof.captureBindings(bindings)
    local size = bindingArray(bindings, 32)
    if not size or size == 0 then return end
    local records, owners = {}, {}
    for index = 1, size do
        local specification = bindings[index]
        if bindingType(specification) ~= "table" or bindingMeta(specification) ~= nil then return end
        local owner, keys, exact = specification.owner, specification.keys, specification.exact
        if bindingType(owner) ~= "table" or owners[owner] or exact ~= nil and bindingType(exact) ~= "boolean" then return end
        local keyCount = not exact and bindingArray(keys, 128)
        if exact and keys ~= nil or not exact and (not keyCount or keyCount == 0) then return end
        local record = {owner = owner, meta = bindingMeta(owner), exact = exact == true, fields = {}, keys = {}, count = 0}
        if not actualBindingMeta(owner,record.meta) then return end
        owners[owner], records[index] = true, record
        if not exact then
            for position = 1, keyCount do
                local key = keys[position]
                if key == nil or bindingType(key) == "number" and key ~= key or record.keys[key] then return end
                record.keys[key] = true
            end
        end
        if not exact and record.meta~=nil then record.parent=inertBindingParent(record.meta,record.keys) end
        if exact or record.meta ~= nil and not record.parent then
            local count = 0
            for key, value in bindingPairs(owner) do
                count = count + 1
                if count > 128 then return end
                if exact or record.keys[key] then
                    record.fields[key] = value
                    record.count = record.count + 1
                end
            end
        else
            -- Plain or proven noninheriting selected fields have truly own
            -- rawget semantics, even in Kahlua's metatable-following rawget.
            for _, key in bindingEach(keys) do
                local value = bindingRaw(owner, key)
                if value ~= nil then record.fields[key] = value; record.count = record.count + 1 end
            end
        end
    end
    return function()
        for _, record in bindingEach(records) do
            if not bindingEqual(bindingMeta(record.owner), record.meta) or not actualBindingMeta(record.owner,record.meta) then return false end
            if record.parent and not bindingParentUnchanged(record.parent) then return false end
            if record.exact or record.meta ~= nil and not record.parent then
                local total, found = 0, 0
                for key, value in bindingPairs(record.owner) do
                    total = total + 1
                    if total > 128 then return false end
                    if record.exact or record.keys[key] then
                        found = found + 1
                        if not bindingEqual(record.fields[key], value) then return false end
                    end
                end
                if found ~= record.count then return false end
            else
                for key in bindingPairs(record.keys) do
                    if not bindingEqual(bindingRaw(record.owner, key), record.fields[key]) then return false end
                end
            end
        end
        return true
    end
end

return Proof
