-- Recorded content can teach recipes and grant XP independently of its carrier category.
local Media = {}
local SKILL_CODES = {}
for code in ("SPR LFT NIM SNE BAA BUA CRP COO FRM DOC ELC MTL FKN CRV AIM REL FIS TRA FOR "
    .. "TAI MEC CMB SPE SBU LBA SBA MAS POT BLA GLA HUS BUT TRK"):gmatch("%S+") do SKILL_CODES[code] = true end

local effectsByMedia = setmetatable({}, {__mode = "k"})
local catalogIdentity, categoryStates

local function scan(codes, found)
    if type(codes) ~= "string" then return end
    -- Native ISRadioInteractions splits by comma and ignores tokens of length <= 4.
    for token in codes:gmatch("[^,]+") do
        if #token > 4 then
            local code = token:sub(1, 3)
            if code == "RCP" then found.recipe = true
            elseif SKILL_CODES[code] then
                local amount = tonumber(token:sub(5))
                if amount and token:sub(4, 4) == "-" then amount = -amount end
                if amount and amount > 0 then found.experience = true end
            end
        end
    end
end

function Media.effects(media)
    if not media then return false, false end
    local found = effectsByMedia[media]
    if not found then
        found = {experience = false, recipe = false}
        if media.getLineCount and media.getLine then
            for index = 0, media:getLineCount() - 1 do
                local line = media:getLine(index)
                scan(line and line:getCodes(), found)
            end
        else
            for _, line in ipairs(media.lines or {}) do scan(line.codes, found) end
        end
        effectsByMedia[media] = found
    end
    return found.experience, found.recipe
end

local function catalog()
    local radio = getZomboidRadio and getZomboidRadio()
    local registered = radio and radio.getRecordedMedia and radio:getRecordedMedia()
    if registered and registered.getAllMediaForCategory then return registered, true end
    if type(RecMedia) == "table" then return RecMedia, false end
end

local function possibilities(category)
    local source, registered = catalog()
    if not source then return nil end
    if source ~= catalogIdentity then catalogIdentity, categoryStates = source, {} end
    local states = categoryStates[category]
    if not states then
        states = {}
        local seen = {}
        local function add(media)
            local experience, recipe = Media.effects(media)
            local key = (experience and "1" or "0") .. (recipe and "1" or "0")
            if not seen[key] then
                states[#states + 1] = {experience = experience, recipe = recipe}
                seen[key] = true
            end
        end
        if registered then
            local records = source:getAllMediaForCategory(category)
            if records then for index = 0, records:size() - 1 do add(records:get(index)) end end
        else
            for _, record in pairs(source) do if record.category == category then add(record) end end
        end
        categoryStates[category] = states
    end
    -- Do not let a caller change the cached combinations for later previews.
    local result = {}
    for index, state in ipairs(states) do result[index] = {experience = state.experience, recipe = state.recipe} end
    return result
end

function Media.read(script, item)
    local recording = item and item.getMediaData and item:getMediaData()
    if recording then return Media.effects(recording) end
    local category = script and script.getRecordedMediaCat and script:getRecordedMediaCat()
    if not category or tostring(category) == "" then return nil, nil, nil end
    if item then return false, false, nil end
    local states = possibilities(tostring(category))
    if states == nil then return nil, nil, nil end
    -- ScriptItems describe carriers, never a particular recorded lesson.
    return false, false, states
end

function Media.invalidate()
    catalogIdentity, categoryStates = nil, nil
    effectsByMedia = setmetatable({}, {__mode = "k"})
end

-- Content is immutable after native initialization; mods may register a replacement catalog.
if Events and Events.OnInitRecordedMedia and Events.OnInitRecordedMedia.Add then
    Events.OnInitRecordedMedia.Add(Media.invalidate)
end
return Media
