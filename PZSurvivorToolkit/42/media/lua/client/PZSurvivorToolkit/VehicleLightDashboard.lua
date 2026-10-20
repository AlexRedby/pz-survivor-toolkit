-- Nep's stock colour patch targets the switch; YourDash uses a separate lamp.
if not getActivatedMods():contains("NepHighBeams") then return end
require "Vehicles/ISUI/ISVehicleDashboard"

local D = {}
PZSurvivorToolkit = PZSurvivorToolkit or {}
PZSurvivorToolkit.VehicleLightDashboard = D

function D.mode(vehicle)
    if not vehicle or not vehicle:getHeadlightsOn() or vehicle:getBatteryCharge() <= 0 then return "off" end
    local data = vehicle:getModData()
    return data and data.NepHB and data.NepHB.highBeamsOn == true and "high" or "low"
end

-- The rotary position is the driver's selection, independent of battery power
-- and alarm flashes. YourDash also holds optimistic power changes until the
-- native command is acknowledged; reuse that state rather than inventing one.
function D.switchMode(dash)
    local vehicle = dash.vehicle
    if not vehicle then return "off" end
    local on
    if dash._YourDashGetHeadlightSwitchState then
        on = dash:_YourDashGetHeadlightSwitchState()
    else
        on = vehicle:getHeadlightsOn()
    end
    if not on then return "off" end
    local data = vehicle:getModData()
    return data and data.NepHB and data.NepHB.highBeamsOn == true and "high" or "low"
end

local function rotaryAvailable(dash)
    return dash.__YourDashFamily == "standard" and NepHBO7
        and type(NepHBO7.activateHighBeams) == "function"
        and type(NepHBO7.deactivateHighBeams) == "function"
end

function D.onClickRotary(dash, original, ...)
    if not rotaryAvailable(dash) then return original(dash, ...) end
    if not dash.vehicle or getGameSpeed() == 0 then return end
    local mode = D.switchMode(dash)
    -- Native power toggles read actual headlights, not YourDash's optimistic
    -- selection. Wait for that command's ACK (or upstream pending expiry),
    -- otherwise rapid clicks could send ON again while the knob says OFF.
    if (dash.__YourDashHeadlightSwitchPending or 0) > 0
            and (dash.vehicle:getHeadlightsOn() == true) ~= (mode ~= "off") then
        return
    end
    if mode == "low" then
        -- This step only changes the beam. Match the native speed guard even
        -- though the native power callback must not run for LOW -> HIGH.
        if getGameSpeed() > 1 then setGameSpeed(1) end
        NepHBO7.activateHighBeams(dash.vehicle)
    else
        -- Native power commands, pause handling and YourDash's alarm-safe
        -- optimistic switch state stay on their established callback path.
        NepHBO7.deactivateHighBeams(dash.vehicle)
        return original(dash, ...)
    end
end

local rotaryMarks = {}
local function drawRotaryMark(dash, switch)
    if not rotaryAvailable(dash) or not dash.drawTextureScaled then return end
    local scale = YourDash and YourDash.GetScaleKey and YourDash.GetScaleKey()
    if not scale then return end
    if rotaryMarks[scale] == nil then
        rotaryMarks[scale] = getTexture("media/ui/PZSurvivorToolkit/beams/standard/" .. scale .. "/high-mark.png") or false
    end
    local mark = rotaryMarks[scale]
    if not mark then return end
    -- Half the warning tile's authored dimensions matches the small printed
    -- low-beam legend. Keep this neutral: it is a faceplate marking, not a lamp.
    local width, height = mark:getWidthOrig() * .5, mark:getHeightOrig() * .5
    -- A 135-degree HIGH detent points above/right. Its legend fits inside the
    -- original left faceplate; a 180-degree legend would cross the panel seam.
    local scaleFactor = switch.width / 48
    local centerX = switch.x + switch.width * .5 + 14.5 * scaleFactor
    local centerY = switch.y + switch.height * .5 - 22.5 * scaleFactor
    dash:drawTextureScaled(mark, centerX - width * .5,
        centerY - height * .5, width, height, 1, .72, .72, .72)
end

local function bindRotary(dash, switch)
    local rotary = rotaryAvailable(dash)
    if rotary then
        if switch.onclick ~= switch.__toolkitBeamRotaryClick then
            switch.__toolkitBeamNativeClick = switch.onclick
            switch.__toolkitBeamRotaryClick = function(target, ...)
                return D.onClickRotary(target, switch.__toolkitBeamNativeClick, ...)
            end
            switch.onclick = switch.__toolkitBeamRotaryClick
        end
        if switch.render ~= switch.__toolkitBeamRotaryRender then
            switch.__toolkitBeamNativeRender = switch.render
            switch.__toolkitBeamRotaryRender = function(img, ...)
                switch.__toolkitBeamNativeRender(img, ...)
                drawRotaryMark(dash, img)
            end
            switch.render = switch.__toolkitBeamRotaryRender
        end
        local mode = D.switchMode(dash)
        dash.__lightKnobAngle = mode == "high" and 135 or mode == "low" and 90 or 0
    elseif switch.onclick == switch.__toolkitBeamRotaryClick then
        -- A live dashboard can change vehicle family without replacing ISImage.
        switch.onclick = switch.__toolkitBeamNativeClick
    end
    if not rotary and switch.render == switch.__toolkitBeamRotaryRender then
        switch.render = switch.__toolkitBeamNativeRender
    end
end

local rockerScales = { ["0.75x"] = .75, ["1x"] = 1, ["1.4x"] = 1.4, ["2x"] = 2 }
local rockerTextures = {}
local function rockerArt(dash)
    if dash.__YourDashFamily ~= "heavy" or not dash.backgroundTex or not NepHBO7
            or type(NepHBO7.activateHighBeams) ~= "function"
            or type(NepHBO7.deactivateHighBeams) ~= "function" then return end
    local key = YourDash and YourDash.GetScaleKey and YourDash.GetScaleKey()
    local scale = rockerScales[key]
    if not scale then return end
    if rockerTextures[key] == nil then
        local prefix = "media/ui/PZSurvivorToolkit/beams/heavy/" .. key .. "/"
        local art = { scale = scale, panel = getTexture(prefix .. "light-panel.png") }
        for _, mode in ipairs({ "off", "low", "high" }) do
            art[mode] = getTexture(prefix .. "rocker-" .. mode .. ".png")
        end
        rockerTextures[key] = art.panel and art.off and art.low and art.high and art or false
    end
    return rockerTextures[key] or nil
end

function D.onClickRocker(dash, original, switch)
    if not rockerArt(dash) then return original(dash, switch) end
    if not dash.vehicle or getGameSpeed() == 0 then return end
    local mode = D.switchMode(dash)
    if (dash.__YourDashHeadlightSwitchPending or 0) > 0
            and (dash.vehicle:getHeadlightsOn() == true) ~= (mode ~= "off") then return end
    local y = switch.__toolkitBeamClickY
    if type(y) ~= "number" then return end
    local up = y < switch.height * .5
    if (up and mode == "high") or (not up and mode == "off") then return end
    if mode == "off" or (mode == "low" and not up) then
        NepHBO7.deactivateHighBeams(dash.vehicle)
        return original(dash, switch)
    end
    if getGameSpeed() > 1 then setGameSpeed(1) end
    if up then NepHBO7.activateHighBeams(dash.vehicle)
    else NepHBO7.deactivateHighBeams(dash.vehicle) end
end

local function releaseRocker(dash, switch)
    local native = switch.__toolkitBeamRockerNative
    if not native then return end
    if switch.onclick == switch.__toolkitBeamRockerClick then switch.onclick = native.click end
    if switch.render == switch.__toolkitBeamRockerRender then switch.render = native.render end
    if switch.onMouseUp == switch.__toolkitBeamRockerUp then switch.onMouseUp = native.up end
    if switch.texture == switch.__toolkitBeamRockerTexture then
        if dash._YourDashApplyLightTexture and dash.__light_knob then
            dash:_YourDashApplyLightTexture(dash.__light_knob)
            local x, y = YourDash.GetLayoutPoint(dash, "controls", "lights")
            dash:_YourDashPositionLightsControl(x, y)
        else
            switch.texture = native.texture
            switch:setX(native.x); switch:setY(native.y)
            switch:setWidth(native.width); switch:setHeight(native.height)
        end
    end
    switch.__toolkitBeamRockerNative = nil
end

local function bindRocker(dash, switch)
    local art = rockerArt(dash)
    local background = dash.backgroundTex
    if not art then
        releaseRocker(dash, switch)
        if background and background.render == background.__toolkitBeamPanelRender then
            background.render = background.__toolkitBeamPanelNativeRender
        end
        return
    end
    if not switch.__toolkitBeamRockerNative then
        switch.__toolkitBeamRockerNative = { click = switch.onclick, render = switch.render,
            up = switch.onMouseUp, texture = switch.texture, x = switch.x, y = switch.y,
            width = switch.width, height = switch.height }
    end
    -- YourDash can rebuild the native handlers while changing vehicle or scale.
    -- Capture those fresh handlers instead of restoring a previous family's UI.
    local native = switch.__toolkitBeamRockerNative
    if switch.onclick ~= switch.__toolkitBeamRockerClick then native.click = switch.onclick end
    if switch.render ~= switch.__toolkitBeamRockerRender then native.render = switch.render end
    if switch.onMouseUp ~= switch.__toolkitBeamRockerUp then native.up = switch.onMouseUp end
    if not switch.__toolkitBeamRockerClick then
        switch.__toolkitBeamRockerClick = function(target, image)
            return D.onClickRocker(target, switch.__toolkitBeamRockerNative.click, image or switch)
        end
        switch.__toolkitBeamRockerUp = function(image, x, y)
            image.__toolkitBeamClickY = y
            local ok, result = pcall(image.__toolkitBeamRockerNative.up, image, x, y)
            image.__toolkitBeamClickY = nil
            if not ok then error(result) end
            return result
        end
        switch.__toolkitBeamRockerRender = function(image)
            if image.texture then
                image:drawTextureScaled(image.texture, 0, 0, image.width, image.height, image.alpha or 1)
            end
        end
    end
    switch.onclick = switch.__toolkitBeamRockerClick
    switch.onMouseUp = switch.__toolkitBeamRockerUp
    switch.render = switch.__toolkitBeamRockerRender
    local texture = art[D.switchMode(dash)]
    switch.texture, switch.__toolkitBeamRockerTexture = texture, texture
    switch:setWidth(texture:getWidthOrig()); switch:setHeight(texture:getHeightOrig())
    switch:setX(background:getX() + math.floor(45 * art.scale + .5))
    switch:setY(background:getY() + math.floor(124 * art.scale + .5))
    if background.render ~= background.__toolkitBeamPanelRender then
        background.__toolkitBeamPanelNativeRender = background.render
        background.__toolkitBeamPanelRender = function(image, ...)
            image.__toolkitBeamPanelNativeRender(image, ...)
            local active = rockerArt(dash)
            if active then
                image:drawTextureScaled(active.panel, 0, 0,
                    active.panel:getWidthOrig(), active.panel:getHeightOrig(), image.alpha or 1)
            end
        end
        background.render = background.__toolkitBeamPanelRender
    end
end

local function colour(image, r, g, b)
    image.backgroundColor.r, image.backgroundColor.g, image.backgroundColor.b = r, g, b
end

-- The physical switch has an authored YourDash render. Suppress ONLY its
-- inherited stock draw; restore its texture before render and on errors.
local function withoutStockTexture(image, originalPre, ...)
    local texture = image.texture
    image.texture = nil
    local ok, err = pcall(originalPre, image, ...)
    image.texture = texture
    if not ok then error(err) end
end

-- Match the active authored family/scale; never resize the warning image.
local highTextures = {}
local function warningTexture(dash, image, shown)
    local original = dash.__warn_light
    if not original then
        if image.texture ~= image.__toolkitBeamHighTexture then
            image.__toolkitBeamOriginalTexture = image.texture
        end
        original = image.__toolkitBeamOriginalTexture
    end
    if shown ~= "high" or not original then return original end
    local family = dash.__YourDashFamily
    local scale = YourDash and YourDash.GetScaleKey and YourDash.GetScaleKey()
    if not family or not scale then return original end
    local key = family .. "/" .. scale
    if highTextures[key] == nil then
        highTextures[key] = getTexture("media/ui/PZSurvivorToolkit/beams/" .. key .. "/high.png") or false
    end
    local high = highTextures[key]
    if high and high:getWidthOrig() == original:getWidthOrig()
            and high:getHeightOrig() == original:getHeightOrig() then
        image.__toolkitBeamHighTexture = high
        return high
    end
    return original
end

function D.bind(dash)
    local realistic = dash.warnLightTex ~= nil
    local image = realistic and dash.warnLightTex or dash.lightsTex
    if not image then return end
    local mode = D.mode(dash.vehicle)
    if image.__toolkitBeamVehicle ~= dash.vehicle then image.__toolkitBeamLastMode = nil end
    image.__toolkitBeamVehicle = dash.vehicle
    image.__toolkitBeamMode = mode
    if mode ~= "off" then image.__toolkitBeamLastMode = mode end
    if realistic then
        -- Keep native padding, dimensions and soft alpha/glow. High uses the
        -- matching horizontal-ray variant; low keeps the original sloping PNG.
        -- Native prerender AND YourDash render must use the same texture/tint.
        local shown = mode ~= "off" and mode or image.__toolkitBeamLastMode or "low"
        image.texture = warningTexture(dash, image, shown)
        if shown == "low" then colour(image,.4,1,.35) else colour(image,1,1,1) end
        if not image.__toolkitBeamWrapped then
            image.__toolkitBeamWrapped = true
            local originalRender = image.render
            image.render = function(img, ...)
                if not dash.vehicle then return originalRender(img, ...) end
                if img.__offTexture then
                    img:drawTextureScaled(img.__offTexture,0,0,img.width,img.height,1)
                end
                local c = img.backgroundColor
                if img.texture and c.a > .001 then
                    img:drawTextureScaled(img.texture,0,0,img.width,img.height,c.a,c.r,c.g,c.b)
                end
            end
        end
    else
        -- Preserve the stock dashboard's own artwork and drawing path too.
        image.__toolkitBeamWrapped = true
        if dash.vehicle and dash.vehicle:getHeadlightsOn() and not dash.vehicle:getHeadlightCanEmmitLight() then
            local bad = getCore():getBadHighlitedColor()
            colour(image,bad:getR(),bad:getG(),bad:getB())
        elseif mode == "low" then colour(image,.4,1,.35)
        elseif mode == "high" then colour(image,.2,.3,1) end
    end
    if realistic and dash.lightsTex and dash.lightsTex ~= image then
        local switch = dash.lightsTex
        if dash.__YourDashFamily ~= "heavy" then releaseRocker(dash, switch) end
        bindRotary(dash, switch)
        bindRocker(dash, switch)
        if not switch.__toolkitBeamSwitchWrapped then
            switch.__toolkitBeamSwitchWrapped = true
            local originalPre = switch.prerender
            switch.prerender = function(img, ...)
                withoutStockTexture(img, originalPre, ...)
            end
        end
    end
    if dash.lightsTex then
        dash.lightsTex.mouseovertext = getText("UI_PZST_BeamDashboard_"..mode)
            .. " <LINE> " .. getText("Tooltip_Dashboard_Headlights")
        if realistic and rotaryAvailable(dash) then
            dash.lightsTex.mouseovertext = dash.lightsTex.mouseovertext
                .. " <LINE> " .. getText("UI_PZST_BeamDashboard_Rotary")
        elseif realistic and rockerArt(dash) then
            dash.lightsTex.mouseovertext = dash.lightsTex.mouseovertext
                .. " <LINE> " .. getText("UI_PZST_BeamDashboard_Rocker")
        end
    end
end

Events.OnGameStart.Add(function()
    if D.installed then return end
    D.installed = true
    local original = ISVehicleDashboard.prerender
    ISVehicleDashboard.prerender = function(self, ...)
        original(self, ...)
        D.bind(self)
    end
end)
