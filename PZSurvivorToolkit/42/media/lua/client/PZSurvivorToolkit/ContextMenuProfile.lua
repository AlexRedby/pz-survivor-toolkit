local Profile = {}
local Storage = require "PZSurvivorToolkit/ContextMenuProfileStorage"

local function encode(value)
    return tostring(value or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\r", "%%0D"):gsub("\n", "%%0A")
end
local function decode(value)
    return value:gsub("%%0A", "\n"):gsub("%%0D", "\r"):gsub("%%7C", "|"):gsub("%%25", "%%")
end
local function validKey(value)
    return type(value) == "string" and #value > 0 and #value <= 1024
end
local function validScope(value)
    return value == "*" or (type(value) == "string" and #value <= 160 and value:find(".", 1, true) and not value:find("[%c|]"))
end
local function cleanName(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    if #value == 0 or #value > 256 or value:find("%c") then return nil end
    return value
end
local function copy(values)
    local out = {}; for i, value in ipairs(values or {}) do out[i] = value end; return out
end

local fields = {"entries", "overrides", "items", "scoped", "customGroups", "names", "orders", "discovered", "tagProfiles", "typeTags"}
local function empty()
    local result = {layouts = {}, revision = 0}
    for _, field in ipairs(fields) do result[field] = {} end
    return result
end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end
local function boundedIndex(value, maximum)
    if type(value) ~= "string" or #value > 2 or not value:match("^[1-9]%d*$") then return end
    local number = tonumber(value)
    if number <= maximum then return number end
end

local function parse(lines, Rules, Tags, version)
    local self, builtin = empty(), {root = true, hidden = true}
    for _, id in ipairs(Rules.groups) do builtin[id] = true end
    local function allowed(id) return builtin[id] or self.customGroups[id] ~= nil end
    local typeScope = validScope
    local function validScope(value)
        if typeScope(value) then return true end
        for _, profile in ipairs(self.tagProfiles) do if profile.id == value then return true end end
        return false
    end
    local pending = {}
    for _, raw in ipairs(lines) do
        if #raw <= 8192 then
            local fields = {}; for value in (raw .. "|"):gmatch("(.-)|") do fields[#fields + 1] = decode(value) end
            pending[#pending + 1] = fields
            if fields[1] == "G" and fields[2] and fields[2]:match("^custom:%d+$") and cleanName(fields[3]) then self.customGroups[fields[2]] = fields[3] end
        end
    end
    -- Load filters before their scoped preferences, regardless of record order.
    local filters, ordered = {}, {}
    for _, row in ipairs(pending) do
        if row[1] == "F" and type(row[2]) == "string" and row[2]:match("^tags:%d+$") and #row[2] <= 160
            and cleanName(row[3]) then
            local existing = filters[row[2]]
            if existing then
                if existing.rule.groups or row[4] == "groups" then existing.invalid = true end
            elseif #ordered < 64 then
                local rule
                if row[4] == "all" or row[4] == "any" then rule = {mode = row[4], include = {}, exclude = {}}
                elseif row[4] == "groups" and version == 2 and #row == 5 then
                    local count = boundedIndex(row[5], 64)
                    if count then
                        rule = {groups = {}}
                        for index = 1, count do rule.groups[index] = {include = {}, exclude = {}} end
                    end
                end
                if rule then
                    local profile = {id = row[2], name = row[3], rule = rule}
                    filters[row[2]], ordered[#ordered + 1] = profile, profile
                end
            end
        end
    end
    for _, row in ipairs(pending) do
        local profile = (row[1] == "A" or row[1] == "B") and filters[row[2]]
        if profile then
            if profile.rule.groups then
                local index = row[1] == "B" and boundedIndex(row[3], #profile.rule.groups)
                if not index or #row ~= 5 or (row[4] ~= "include" and row[4] ~= "exclude") then
                    profile.invalid = true
                else
                    local values = profile.rule.groups[index][row[4]]
                    if #values >= 64 then profile.invalid = true else values[#values + 1] = row[5] end
                end
            elseif row[1] == "B" then profile.invalid = true
            elseif row[3] == "include" or row[3] == "exclude" then
                local values = profile.rule[row[3]]
                if #values < 65 then values[#values + 1] = row[4] or "" end
            end
        end
    end
    for _, profile in ipairs(ordered) do
        local rule = not profile.invalid and Tags and Tags.normalizeRule(profile.rule)
        if rule and Tags.ruleActive(rule) then profile.rule = rule; self.tagProfiles[#self.tagProfiles + 1] = profile end
    end
    for _, row in ipairs(pending) do
        local kind, a, b, c, d = unpack(row)
        if kind == "E" and validKey(a) and validKey(b) then self.entries[a] = {key = a, label = b, category = allowed(c) and c or nil}
        elseif kind == "R" and validKey(a) and allowed(b) then self.overrides[a] = b
        elseif kind == "I" and validScope(a) and a ~= "*" and cleanName(b) then self.items[a] = b
        elseif kind == "T" and typeScope(a) and a ~= "*" and Tags and Tags.normalizeRule({include = {b}}) then
            self.typeTags[a] = self.typeTags[a] or {}; self.typeTags[a][#self.typeTags[a] + 1] = b
        elseif kind == "C" and typeScope(a) and a ~= "*" and validKey(b) then
            self.typeTags[a] = self.typeTags[a] or {}; self.typeTags[a].legacyCategory = b
        elseif kind == "D" and validScope(a) and validKey(b) and validKey(c) then
            self.discovered[a] = self.discovered[a] or {}; self.discovered[a][b] = {key = b, label = c, category = allowed(d) and d or nil}
        elseif kind == "P" and validScope(a) and a ~= "*" and validKey(b) and allowed(c) then
            self.scoped[a] = self.scoped[a] or {}; self.scoped[a][b] = c
        elseif kind == "N" and validScope(a) and allowed(b) and b ~= "root" and b ~= "hidden" and cleanName(c) then
            self.names[a] = self.names[a] or {}; self.names[a][b] = c
        elseif kind == "O" and validScope(a) and validKey(b) and tonumber(c) and validKey(d) then
            local index = tonumber(c)
            if index >= 1 and index <= 512 and index == math.floor(index) then
                self.orders[a] = self.orders[a] or {}; self.orders[a][b] = self.orders[a][b] or {}; self.orders[a][b][index] = d
            end
        end
    end
    for _, parents in pairs(self.orders) do
        for parent, keys in pairs(parents) do
            local out, seen = {}, {}
            for i = 1, 512 do local key = keys[i]; if key and not seen[key] then out[#out + 1] = key; seen[key] = true end end
            parents[parent] = out
        end
    end
    return self
end

local function serialize(self)
    local lines, version = {}, 1
    local function line(...)
        local fields = {}; for i = 1, select('#', ...) do fields[i] = encode(select(i, ...)) end
        lines[#lines + 1] = table.concat(fields, "|")
    end
    for id, name in pairs(self.customGroups) do line("G", id, name) end
    for _, profile in ipairs(self.tagProfiles) do
        if profile.rule.groups then
            version = 2
            line("F", profile.id, profile.name, "groups", #profile.rule.groups)
            for index, group in ipairs(profile.rule.groups) do
                for _, field in ipairs({"include", "exclude"}) do
                    for _, tag in ipairs(group[field]) do line("B", profile.id, index, field, tag) end
                end
            end
        else
            line("F", profile.id, profile.name, profile.rule.mode)
            for _, field in ipairs({"include", "exclude"}) do
                for _, tag in ipairs(profile.rule[field]) do line("A", profile.id, field, tag) end
            end
        end
    end
    for itemType, tags in pairs(self.typeTags) do
        for _, tag in ipairs(tags) do line("T", itemType, tag) end
        if tags.legacyCategory then line("C", itemType, tags.legacyCategory) end
    end
    for key, entry in pairs(self.entries) do line("E", key, entry.label, entry.category) end
    for key, id in pairs(self.overrides) do line("R", key, id) end
    for scope, name in pairs(self.items) do line("I", scope, name) end
    for scope, entries in pairs(self.discovered) do
        for key, entry in pairs(entries) do line("D", scope, key, entry.label, entry.category) end
    end
    for scope, rules in pairs(self.scoped) do for key, id in pairs(rules) do line("P", scope, key, id) end end
    for scope, names in pairs(self.names) do for id, name in pairs(names) do line("N", scope, id, name) end end
    for scope, parents in pairs(self.orders) do
        for parent, keys in pairs(parents) do for index, key in ipairs(keys) do line("O", scope, parent, index, key) end end
    end
    return lines, version
end

function Profile.new(Rules, Tags)
    local self = empty()
    local preferencesRevision, actualLayouts = 0, {}
    local snapshot, writeFailed
    local function failed(code, detail)
        if self.storageError ~= code then print("[PZSurvivorToolkit] Context menu settings " .. code .. ": " .. tostring(detail)) end
        self.storageError = code
        return false, code
    end
    function self.ensureLoaded()
        if snapshot then return true end
        local ok, candidate, data = pcall(function()
            local context = Storage.load()
            return context, parse(context.lines, Rules, Tags, context.version or 1)
        end)
        if not ok then return failed("ReadFailed", candidate) end
        -- Discovery may continue while storage is unavailable; preferences always come from the verified disk state.
        for _, field in ipairs({"entries", "items", "typeTags"}) do
            for key, value in pairs(self[field]) do data[field][key] = value end
        end
        for scope, entries in pairs(self.discovered) do
            data.discovered[scope] = data.discovered[scope] or {}
            for key, entry in pairs(entries) do data.discovered[scope][key] = entry end
        end
        for _, field in ipairs(fields) do self[field] = data[field] end
        snapshot, self.storageError = candidate, nil
        preferencesRevision, self.revision = preferencesRevision + 1, self.revision + 1
        return true
    end
    function self.save()
        if not self.ensureLoaded() then return false, self.storageError end
        local ok, candidate = pcall(function() return Storage.save(snapshot, serialize(self)) end)
        if not ok then
            snapshot = nil -- A complete slot can exist despite a close/readback error; reload before any next edit.
            return failed("WriteFailed", candidate)
        end
        snapshot, self.storageError = candidate, nil
        return true
    end
    local builtin = {root = true, hidden = true}
    for _, id in ipairs(Rules.groups) do builtin[id] = true end
    local function allowed(id) return builtin[id] or self.customGroups[id] ~= nil end
    local function scopeOf(scope) return scope or "*" end
    function self.tagProfileIndex(id)
        for index, profile in ipairs(self.tagProfiles) do if profile.id == id then return index end end
    end
    function self.getTagProfile(id)
        local index = self.tagProfileIndex(id)
        return index and self.tagProfiles[index]
    end
    local typeScope = validScope
    local function validScope(scope) return typeScope(scope) or self.getTagProfile(scope) ~= nil end
    function self.matchingTagProfiles(tagSets)
        local ids = {}
        if not Tags or #tagSets == 0 then return ids end
        for _, profile in ipairs(self.tagProfiles) do
            local matches = true
            for _, tags in ipairs(tagSets) do if not Tags.matchesRule(tags, profile.rule) then matches = false; break end end
            if matches then ids[#ids + 1] = profile.id end
        end
        return ids
    end
    local function scopes(scope, context)
        scope = scopeOf(scope)
        local result, index = {}, self.tagProfileIndex(scope)
        if scope ~= "*" then result[#result + 1] = scope end
        local matches
        if type(context) == "table" then matches = context
        elseif scope ~= "*" then
            local tags = self.typeTags[type(context) == "string" and context or scope]
            matches = tags and self.matchingTagProfiles({tags}) or {}
        else matches = {} end
        for _, id in ipairs(matches) do
            if id ~= scope and (not index or (self.tagProfileIndex(id) or 0) > index) then result[#result + 1] = id end
        end
        result[#result + 1] = "*"
        return result
    end
    local function inherited(values, key, scope, context)
        for _, id in ipairs(scopes(scope, context)) do
            if values[id] and values[id][key] ~= nil then return values[id][key] end
        end
    end
    local function changed()
        if not self.save() then writeFailed = true; return end
        preferencesRevision = preferencesRevision + 1
        self.revision = self.revision + 1
        if self.settingsChanged then self.settingsChanged() end
    end
    function self.rememberItem(id, name, tags)
        self.items[id] = name
        self.typeTags[id] = copy(tags)
        self.typeTags[id].legacyCategory = tags and tags.legacyCategory
    end
    function self.createTagProfile(name, rule)
        name = cleanName(name)
        rule = Tags and Tags.normalizeRule(rule)
        if not name or not rule or not Tags.ruleActive(rule) or #self.tagProfiles >= 64 then return nil end
        local index = 1; while self.getTagProfile("tags:" .. index) do index = index + 1 end
        local id = "tags:" .. index
        self.tagProfiles[#self.tagProfiles + 1] = {id = id, name = name, rule = rule}
        changed(); return id
    end
    function self.updateTagProfile(id, name, rule)
        local profile = self.getTagProfile(id)
        name, rule = cleanName(name), Tags and Tags.normalizeRule(rule)
        if not profile or not name or not rule or not Tags.ruleActive(rule) then return false end
        profile.name, profile.rule = name, rule
        changed(); return true
    end
    function self.deleteTagProfile(id)
        local index = self.tagProfileIndex(id)
        if not index then return false end
        table.remove(self.tagProfiles, index)
        self.scoped[id], self.names[id], self.orders[id], self.discovered[id], self.layouts[id] = nil, nil, nil, nil, nil
        changed(); return true
    end
    function self.moveTagProfile(id, delta)
        local index = self.tagProfileIndex(id)
        if (delta ~= -1 and delta ~= 1) or not index or not self.tagProfiles[index + delta] then return false end
        self.tagProfiles[index], self.tagProfiles[index + delta] = self.tagProfiles[index + delta], self.tagProfiles[index]
        changed(); return true
    end
    function self.isCustomGroup(id) return self.customGroups[id] ~= nil end
    function self.defaultGroupName(id) return getText("UI_PZSurvivorToolkit_context_group_" .. id) end
    function self.groupIds()
        local out = copy(Rules.groups)
        local custom = {}; for id in pairs(self.customGroups) do custom[#custom + 1] = id end
        table.sort(custom, function(a, b) return tonumber(a:match("%d+$")) < tonumber(b:match("%d+$")) end)
        for _, id in ipairs(custom) do out[#out + 1] = id end
        return out
    end
    function self.hasGroupName(id, scope, context)
        return inherited(self.names, id, scope, context)
    end
    function self.groupName(id, scope, context)
        local name = self.hasGroupName(id, scope, context)
        if name then return name end
        local layout = self.layouts[type(context) == "string" and context or scopeOf(scope)]
        if layout then
            for _, row in ipairs(layout.root or {}) do if row.key == "group:" .. id then return row.label end end
        end
        return self.customGroups[id] or self.defaultGroupName(id)
    end
    function self.getOwnOverride(key, scope)
        if scopeOf(scope) == "*" then return self.overrides[key] end
        return (self.scoped[scopeOf(scope)] or {})[key]
    end
    function self.getOverride(key, scope, context)
        for _, id in ipairs(scopes(scope, context)) do
            local value = self.getOwnOverride(key, id)
            if value ~= nil then return value end
        end
    end
    function self.setOverride(key, category, scope)
        scope = scopeOf(scope)
        if not validKey(key) or not validScope(scope) or (category ~= nil and not allowed(category)) then return false end
        local target = self.overrides
        if scope ~= "*" then self.scoped[scope] = self.scoped[scope] or {}; target = self.scoped[scope] end
        target[key] = category; changed(); return true
    end
    function self.createGroup(name, scope)
        name = cleanName(name)
        if not name or not validScope(scopeOf(scope)) then return nil end
        local count = 0; for _ in pairs(self.customGroups) do count = count + 1 end
        if count >= 64 then return nil end
        local index = 1; while self.customGroups["custom:" .. index] do index = index + 1 end
        local id = "custom:" .. index; self.customGroups[id] = name
        changed(); return id
    end
    function self.renameGroup(id, name, scope)
        name, scope = cleanName(name), scopeOf(scope)
        if not name or not validScope(scope) or not allowed(id) or id == "root" or id == "hidden" then return false end
        self.names[scope] = self.names[scope] or {}; self.names[scope][id] = name
        changed(); return true
    end
    function self.deleteGroup(id)
        if not self.customGroups[id] then return false end
        self.customGroups[id] = nil
        for key, category in pairs(self.overrides) do if category == id then self.overrides[key] = nil end end
        for _, overrides in pairs(self.scoped) do
            for key, category in pairs(overrides) do if category == id then overrides[key] = nil end end
        end
        for _, names in pairs(self.names) do names[id] = nil end
        for _, parents in pairs(self.orders) do
            parents[id] = nil
            for parent, keys in pairs(parents) do
                local kept = {}; for _, key in ipairs(keys) do if key ~= "group:" .. id then kept[#kept + 1] = key end end
                parents[parent] = kept
            end
        end
        changed(); return true
    end
    function self.getOrder(scope, parent, context)
        return copy(inherited(self.orders, parent or "root", scope, context))
    end
    function self.setOrder(scope, parent, keys)
        scope = scopeOf(scope)
        if not validScope(scope) or not validKey(parent) or type(keys) ~= "table" or #keys > 512 then return false end
        local seen = {}
        for _, key in ipairs(keys) do if not validKey(key) or seen[key] then return false end; seen[key] = true end
        self.orders[scope] = self.orders[scope] or {}; self.orders[scope][parent] = copy(keys)
        changed(); return true
    end
    local function orderRows(rows, scope, parent, context)
        local ranks = {}; for i, key in ipairs(self.getOrder(scope, parent, context)) do ranks[key] = i end
        for i, row in ipairs(rows) do row.position = i end
        local function before(a, b)
            local x, y = ranks[a.key], ranks[b.key]
            if x and y then return x < y end
            if x or y then return x ~= nil end
            return a.position < b.position
        end
        local start = 1
        for boundary = 1, #rows + 1 do
            if boundary > #rows or rows[boundary].kind == "title" then
                local segment = {}; for i = start, boundary - 1 do segment[#segment + 1] = rows[i] end
                table.sort(segment, before)
                for i, row in ipairs(segment) do rows[start + i - 1] = row end
                start = boundary + 1
            end
        end
        return rows
    end
    function self.getLayout(scope, parent, previewType)
        scope, parent = scopeOf(scope), parent or "root"
        if previewType and scope ~= "*" and not self.getTagProfile(scope) and scope ~= previewType then return {} end
        local actual = actualLayouts[scope]
        if not previewType and actual and actual.version == preferencesRevision then
            local rows = {}
            for _, row in ipairs(actual.layout[parent] or {}) do
                rows[#rows + 1] = {key = row.key, label = row.label, kind = row.kind, category = row.category}
            end
            return rows
        end
        if previewType and self.getTagProfile(scope) then
            local tags = self.typeTags[previewType]
            if not Tags or not tags or not Tags.matchesRule(tags, self.getTagProfile(scope).rule) then return {} end
        end
        if previewType and self.renderPreview then
            local rendered = self.renderPreview(scope, previewType)
            if rendered then
                local rows = {}
                for _, row in ipairs(rendered[parent] or {}) do
                    rows[#rows + 1] = {key = row.key, label = row.label, kind = row.kind, category = row.category}
                end
                return rows
            end
        end
        local layout = self.layouts[previewType or scope] or {}
        local root, groups, seen = {}, {}, {}
        local function add(row, originalParent)
            if seen[row.key] then return end; seen[row.key] = true
            local category = self.getOverride(row.key, scope, previewType) or originalParent
            if category == "hidden" then return end
            local out = {key = row.key, label = row.label, kind = "action", category = category}
            if category == "root" then root[#root + 1] = out
            else
                if not groups[category] then
                    groups[category] = {}
                    root[#root + 1] = {key = "group:" .. category, label = self.groupName(category, scope, previewType), kind = "group", category = category}
                end
                groups[category][#groups[category] + 1] = out
            end
        end
        for _, row in ipairs(layout.root or {}) do
            if row.kind == "title" then
                root[#root + 1] = {key = row.key, label = row.label, kind = "title", category = "root"}
            elseif row.kind == "group" then
                for _, child in ipairs(layout[row.category] or {}) do add(child, row.category) end
            else add(row, "root") end
        end
        -- Hidden defaults can be explicitly restored without reopening the native menu.
        for _, row in ipairs(self.getEntries(scope)) do
            if not seen[row.key] and self.getOverride(row.key, scope, previewType) and (not previewType or (self.discovered[previewType] or {})[row.key]) then add(row, row.category or "root") end
        end
        return orderRows(parent == "root" and root or (groups[parent] or {}), scope, parent, previewType)
    end
    function self.moveEntry(scope, parent, key, delta, previewType)
        if delta ~= -1 and delta ~= 1 then return false end
        local rows = self.getLayout(scope, parent, previewType); local at
        for i, row in ipairs(rows) do if row.key == key then at = i; break end end
        if not at or not rows[at + delta] or rows[at].kind == "title" or rows[at + delta].kind == "title" then return false end
        rows[at], rows[at + delta] = rows[at + delta], rows[at]
        local keys = {}; for i, row in ipairs(rows) do keys[i] = row.key end
        return self.setOrder(scope, parent, keys)
    end
    function self.getEntries(scope)
        scope = scopeOf(scope)
        local entries = scope == "*" and self.entries or (self.discovered[scope] or {})
        local profile = self.getTagProfile(scope)
        if profile then
            entries = {}
            for itemType, tags in pairs(self.typeTags) do
                if Tags.matchesRule(tags, profile.rule) then
                    for key, entry in pairs(self.discovered[itemType] or {}) do entries[key] = entry end
                end
            end
        end
        local actual = actualLayouts[scope]
        local parents = actual and actual.version == preferencesRevision and actual.parents or {}
        local out = {}
        for key, entry in pairs(entries) do out[#out + 1] = {key = key, label = entry.label, category = parents[key] or self.getOverride(key, scope) or entry.category or "root"} end
        table.sort(out, function(a, b) return a.label < b.label or (a.label == b.label and a.key < b.key) end)
        return out
    end
    function self.record(scope, key, label, category)
        scope = scopeOf(scope)
        local old = self.entries[key]
        if not old or old.label ~= label or old.category ~= category then
            self.entries[key] = {key = key, label = label, category = category}; self.revision = self.revision + 1
        end
        if scope ~= "*" then
            self.discovered[scope] = self.discovered[scope] or {}
            local prior = self.discovered[scope][key]
            if not prior or prior.label ~= label or prior.category ~= category then
                self.discovered[scope][key] = {key = key, label = label, category = category}; self.revision = self.revision + 1
            end
        end
    end
    function self.captureLayout(scope, layout)
        scope = scopeOf(scope)
        self.layouts[scope] = layout
        local entries = scope == "*" and self.entries or (self.discovered[scope] or {})
        for parent, rows in pairs(layout) do
            for _, row in ipairs(rows) do
                if row.kind ~= "group" and entries[row.key] then entries[row.key].category = parent end
            end
        end
        self.revision = self.revision + 1
    end
    function self.captureActualLayout(scope, layout)
        local parents = {}
        for parent, rows in pairs(layout) do
            for _, row in ipairs(rows) do if row.kind == "action" then parents[row.key] = parent end end
        end
        actualLayouts[scopeOf(scope)] = {version = preferencesRevision, layout = layout, parents = parents}
    end
    function self.hasChanges(scope, context)
        for _, id in ipairs(scopes(scope, context)) do
            for _ in pairs(id == "*" and self.overrides or (self.scoped[id] or {})) do return true end
            for _ in pairs(self.names[id] or {}) do return true end
            for _ in pairs(self.orders[id] or {}) do return true end
        end
        return false
    end
    function self.reset(scope)
        scope = scopeOf(scope)
        if scope == "*" then self.overrides, self.scoped, self.names, self.orders, self.customGroups, self.tagProfiles = {}, {}, {}, {}, {}, {}
        else self.scoped[scope], self.names[scope], self.orders[scope] = nil, nil, nil end
        changed()
    end
    for _, name in ipairs({"createTagProfile", "updateTagProfile", "deleteTagProfile", "moveTagProfile",
        "setOverride", "createGroup", "renameGroup", "deleteGroup", "setOrder", "reset"}) do
        local mutate = self[name]
        self[name] = function(...)
            if not self.ensureLoaded() then return nil, self.storageError end
            local previous = {}
            for _, field in ipairs(fields) do previous[field] = clone(self[field]) end
            previous.layouts = clone(self.layouts)
            writeFailed = false
            local result = mutate(...)
            if writeFailed then
                for field, value in pairs(previous) do self[field] = value end
                return nil, self.storageError
            end
            return result
        end
    end
    self.ensureLoaded()
    return self
end
return Profile
