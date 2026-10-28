-- Optional native sidebar qualification using only the Toolkit controls' setters.
local H, tick, phase, at, hooks, writes = {}, 0, 0, 0, {}, 0
local player, sidebar, saved, option, oldButton, oldHub, pass, deadline, idleSince
local pulse = function() tick = tick + 1 end
local function wait(nextPhase, ticks) phase, at = nextPhase, tick + (ticks or 12) end
local function managed(panel) return panel and panel.javaObject and UIManager.getUI():contains(panel.javaObject) end
local function equipped() return assert(getPlayerData(player:getPlayerNum()).equipped) end
local function instrument(control)
    for _, name in ipairs({'setX', 'setY', 'setWidth', 'setHeight', 'setVisible', 'setEnable', 'setTooltip', 'forceImageSize'}) do
        local original, own = assert(control[name]), nil
        for key, value in pairs(control) do if key == name then own = value end end
        local wrapper = function(self, ...) writes = writes + 1; return original(self, ...) end
        hooks[#hooks + 1] = {control = control, name = name, own = own, wrapper = wrapper}
        control[name] = wrapper
    end
end
local function geometry(show)
    sidebar = equipped()
    local button, hub = sidebar.toolkitHighlightButton, assert(sidebar.toolkitToolsButton)
    assert((button ~= nil) == show, 'highlight option ownership')
    local size = math.max(24, math.floor((sidebar.invBtn:getWidth() - 4) / 2))
    local top, core = sidebar:getAbsoluteY(), getCore()
    local maxY = getPlayerScreenTop(player:getPlayerNum()) + getPlayerScreenHeight(player:getPlayerNum()) - top - size - 6
    local x, y = sidebar:getAbsoluteX() + sidebar:getWidth() + 6, top + math.max(0, math.min(sidebar.invBtn:getY(), maxY))
    local function check(control, desiredX)
        local cx, cy = desiredX, y
        if control:getKeepOnScreen() then
            cx = math.max(0, math.min(cx, core:getScreenWidth() - size))
            cy = math.max(0, math.min(cy, core:getScreenHeight() - size))
        end
        assert(control:getX() == cx and control:getY() == cy and control:getWidth() == size and control:getHeight() == size,
            'sidebar geometry x=' .. control:getX() .. ' y=' .. control:getY() .. ' size=' .. control:getWidth())
        assert(control.forcedWidthImage == size - 4 and control.forcedHeightImage == size - 4, 'sidebar icon size')
        assert(control:getIsVisible() == sidebar:getIsVisible() and control.enable and managed(control), 'sidebar visibility/enable/membership')
    end
    if button then check(button, x) end
    check(hub, x + (show and size + 4 or 0))
end
local function restoreLayout()
    if not saved then return end
    option:setValue(saved.show)
    getCore():setOptionSidebarSize(saved.size)
    sidebar = equipped(); sidebar:checkSidebarSizeOption(); sidebar = equipped()
    sidebar:setWidth(saved.w); sidebar:setHeight(saved.h); sidebar.invBtn:setWidth(saved.invW); sidebar.invBtn:setHeight(saved.invH)
    sidebar:setX(saved.x); sidebar:setY(saved.y); sidebar:setVisible(saved.visible)
end
function H.restore()
    local ok, err = pcall(restoreLayout)
    for _, hook in ipairs(hooks) do
        if hook.control[hook.name] == hook.wrapper then hook.control[hook.name] = hook.own end
    end
    hooks = {}; Events.OnTick.Remove(pulse)
    assert(ok, err)
end
function H.start(actor, report)
    player, pass = actor, report
    sidebar = equipped()
    option = assert(PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ShowHighlightButton'))
    saved = {show = option:getValue(), size = getCore():getOptionSidebarSize(), x = sidebar:getX(), y = sidebar:getY(),
        w = sidebar:getWidth(), h = sidebar:getHeight(), invW = sidebar.invBtn:getWidth(), invH = sidebar.invBtn:getHeight(), visible = sidebar:getIsVisible()}
    option:setValue(true); sidebar:setVisible(true)
    local vehicle = player:getVehicle()
    if vehicle then
        -- Same native exit calls/events as ISExitVehicle.perform; no timed-input claim.
        local seat = vehicle:getSeat(player); assert(seat >= 0)
        vehicle:exit(player); vehicle:setCharacterPosition(player, seat, 'outside')
        player:PlayAnim('Idle'); triggerEvent('OnExitVehicle', player)
        vehicle:updateHasExtendOffsetForExitEnd(player)
    end
    deadline = getTimestampMs() + 90000; Events.OnTick.Add(pulse); wait(1)
end
function H.step()
    assert(getTimestampMs() < deadline, 'sidebar qualification deadline phase=' .. phase)
    if tick < at then return false end
    if phase == 1 then
        assert(player:getVehicle() == nil, 'on-foot sidebar setup'); geometry(true); assert(sidebar:getIsVisible())
        pass('idle-sidebar-on-foot'); saved.controlW = sidebar.toolkitHighlightButton:getWidth()
        instrument(sidebar.toolkitHighlightButton); instrument(sidebar.toolkitToolsButton)
        writes, idleSince = 0, tick; wait(2, 60)
    elseif phase == 2 then
        assert(writes == 0, 'settled sidebar writes=' .. writes)
        print('[VEHICLE_DOORS] IDLE_SIDEBAR settled_ticks=60 sidebar_setter_writes=' .. writes .. ' observed_ticks=' .. (tick - idleSince))
        pass('idle-sidebar-settled')
        sidebar:setX(saved.x + 17); sidebar:setY(saved.y + 19); sidebar:setWidth(saved.w + 14); sidebar:setHeight(saved.h + 8)
        sidebar.invBtn:setWidth(saved.invW + 48); wait(3)
    elseif phase == 3 then
        geometry(true); assert(sidebar:getWidth() == saved.w + 14 and sidebar:getHeight() == saved.h + 8
            and sidebar.toolkitHighlightButton:getWidth() ~= saved.controlW, 'sidebar resize not observed')
        pass('idle-sidebar-layout'); sidebar:setVisible(false); wait(4)
    elseif phase == 4 then
        geometry(true); assert(not sidebar.toolkitHighlightButton:getIsVisible() and not sidebar.toolkitToolsButton:getIsVisible())
        pass('idle-sidebar-hidden'); sidebar:setVisible(true); oldButton = sidebar.toolkitHighlightButton
        option:setValue(false); wait(5)
    elseif phase == 5 then
        geometry(false); assert(not managed(oldButton), 'disabled highlight button leaked')
        option:setValue(true); wait(6)
    elseif phase == 6 then
        geometry(true); assert(sidebar.toolkitHighlightButton ~= oldButton and not managed(oldButton), 'highlight control was not replaced')
        pass('idle-sidebar-option'); oldButton, oldHub = sidebar.toolkitHighlightButton, sidebar.toolkitToolsButton
        local oldSidebar = sidebar
        getCore():setOptionSidebarSize(saved.size == 1 and 2 or 1); sidebar:checkSidebarSizeOption()
        sidebar = equipped(); assert(sidebar ~= oldSidebar, 'native sidebar size option did not replace panel'); wait(7)
    elseif phase == 7 then
        geometry(true); assert(sidebar.toolkitHighlightButton ~= oldButton and sidebar.toolkitToolsButton ~= oldHub)
        assert(not managed(oldButton) and not managed(oldHub), 'old sidebar controls leaked')
        pass('idle-sidebar-replacement'); restoreLayout(); wait(8)
    elseif phase == 8 then
        geometry(saved.show)
        assert(player:getVehicle() == nil and option:getValue() == saved.show and getCore():getOptionSidebarSize() == saved.size
            and sidebar:getX() == saved.x and sidebar:getY() == saved.y and sidebar:getWidth() == saved.w
            and sidebar:getHeight() == saved.h and sidebar:getIsVisible() == saved.visible
            and sidebar.invBtn:getWidth() == saved.invW and sidebar.invBtn:getHeight() == saved.invH, 'sidebar settings/layout restore')
        pass('idle-sidebar-restored')
        if require('QueueTestSelection').options.idle_ui_screenshot ~= false then getCore():TakeFullScreenshot('vehicle-doors-idle-sidebar-on-foot.png') end
        wait(9)
    elseif phase == 9 then H.restore(); return true end
    return false
end
return H
