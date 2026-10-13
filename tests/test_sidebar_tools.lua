-- Sidebar contract doubles; native rendering is covered separately.
local toolkit = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/"
local wishlist = ProjectRoot .. "/PZSurvivorWishlist/42/media/lua/client/PZSurvivorWishlist/"
local count = 0
local function equal(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function test(name, body)
    body(); count = count + 1; print("PASS " .. name)
end
local function setup()
    local w = {height = 720, top = 0, show = true, enabled = true, context = true, mods = {PZSurvivorToolkit = true}}
    local function event()
        local handlers = {}
        return {Add = function(fn) handlers[#handlers+1] = fn end,
            fire = function(...) for _, fn in ipairs(handlers) do fn(...) end end}
    end
    Events = {OnTickEvenPaused = event(), OnGameStart = event(), OnKeyPressed = event()}
    w.player = {getPlayerNum = function() return 2 end, isDead = function() return w.dead == true end}
    getPlayer = function() return w.player end
    getPlayerData = function() return w.data end
    getPlayerScreenTop = function() return w.top end
    getPlayerScreenHeight = function() return w.height end
    getActivatedMods = function() return {contains = function(_, name) return w.mods[name] == true end} end
    getTexture = function(path) return path end
    getKeyName = function(key) return "KEY_" .. key end
    getText = function(key, arg) return arg and key .. ":" .. arg or key end
    getCore = function() return {isDoingTextEntry = function() return w.typing end} end
    MainScreen = {instance = {setVisible = function(_, value) w.mainVisible = value end}}
    MainOptions = {instance = {
        isVisible = function() return w.optionsVisible end,
        setVisible = function(_, value) w.optionsVisible = value end,
        toUI = function() w.optionsLoaded = true end,
        tabs = {activateView = function(_, name) w.optionsTab = name end}}}
    w.optionY = 1200
    local control = {
        getHeight = function() return 20 end, getY = function() return w.optionY end,
        parent = {setYScroll = function(_, value) w.optionsScroll = value end}}
    PZAPI = {ModOptions = {Dict = {PZSurvivorToolkit = {getOption = function(_, name)
        equal(name, "Enabled")
        equal(w.optionsTab, "UI_mainscreen_mods", "native Mods view must create controls before lookup")
        return {element = control}
    end}}}}
    local settings = {
        isEnabled = function() return w.enabled end, showHighlightButton = function() return w.show end,
        getToggleKey = function() return 66 end, contextMenus = function() return w.context end,
        getColor = function() return {r = .1, g = .2, b = .3, a = 1} end,
        toggle = function() w.enabled = not w.enabled end}
    PZSurvivorToolkit = {Settings = settings, ContextMenus = {openEditor = function() w.editorOpened = true end}}
    PZSurvivorWishlist = nil
    ISButton = {}
    function ISButton:derive() return setmetatable({}, {__index = self}) end
    function ISButton:new(x, y, width, height, title, target, onclick)
        self.__index = self
        return setmetatable({x=x, y=y, width=width, height=height, title=title,
            target=target, onclick=onclick, Type="ISButton", isButton=true, visible=true,
            backgroundColor={r=0,g=0,b=0,a=1}}, self)
    end
    function ISButton:initialise() self.initialised = true end
    function ISButton:instantiate() self.instantiated = true end
    function ISButton:setEnable(value)
        self.enable = value
        local channel = value and 1 or .3
        self.textureColor = {r=channel,g=channel,b=channel,a=1}
    end
    function ISButton:setTitle(value) self.title = value end
    function ISButton:setTooltip(value) self.tooltip = value end
    function ISButton:setDisplayBackground(value) self.displayBackground = value end
    function ISButton:setImage(value) self.image = value end
    function ISButton:ignoreWidthChange() self.ignoreWidth = true end
    function ISButton:ignoreHeightChange() self.ignoreHeight = true end
    function ISButton:forceImageSize(width, height) self.imageWidth, self.imageHeight = width, height end
    function ISButton:getWidth() return self.width end
    function ISButton:getHeight() return self.height end
    function ISButton:getY() return self.y end
    function ISButton:getRight() return self.x+self.width end
    function ISButton:getBottom() return self.y+self.height end
    function ISButton:getIsVisible() return self.visible end
    function ISButton:getAbsoluteX() return self.parent.x+self.x end
    function ISButton:getAbsoluteY() return self.parent.y+self.y end
    function ISButton:setX(value) self.x = value end
    function ISButton:setY(value) self.y = value end
    function ISButton:setWidth(value) self.width = value end
    function ISButton:setHeight(value) self.height = value end
    function ISButton:render() self.nativeRenders = (self.nativeRenders or 0)+1 end
    function ISButton:drawTextureScaledAspect(texture, x, y, width, height)
        self.tickDraw = {texture=texture, x=x, y=y, width=width, height=height}
    end
    function ISButton:click() self.onclick(self.target, self) end
    ISContextMenu = {get = function(num, x, y)
        w.menu = {num=num, x=x, y=y, options={}}
        function w.menu:addOption(name, target, callback)
            self.options[#self.options+1] = {name=name, target=target, callback=callback}
        end
        return w.menu
    end}
    function w:sidebar(bottom, panelHeight)
        local side = {x=10, y=70, width=48, height=panelHeight or 980, children={}, chr=self.player}
        function side:getWidth() return self.width end
        function side:getHeight() return self.height end
        function side:getAbsoluteY() return self.y end
        function side:setWidth(value) self.width = value end
        function side:setHeight(value) self.height = value end
        function side:getChildren() return self.children end
        function side:addChild(child) self.children[#self.children+1] = child; child.parent = self end
        function side:removeChild(child)
            for i, current in ipairs(self.children) do
                if current == child then table.remove(self.children, i); child.parent=nil; return end
            end
        end
        function side:addMouseOverToolTipItem(child, text) child.nativeTooltip = text end
        function side:shrinkWrap() self.wrapped = true end
        local inv = ISButton:new(0, 12, 48, 24, "Inventory")
        side.invBtn = inv; side:addChild(inv)
        local image = ISButton:new(0, (bottom or 600)-24, 48, 24, "")
        image.Type, image.isButton = "ISImage", nil
        side:addChild(image)
        local admin = ISButton:new(0, 960, 48, 24, "Admin")
        admin.visible=false; side:addChild(admin)
        local decoration = ISButton:new(0, 940, 48, 24, "")
        decoration.Type, decoration.isButton = "ISLabel", nil
        side:addChild(decoration)
        return side
    end
    w.data = {equipped=w:sidebar()}
    require = function(name)
        if name == "PZSurvivorToolkit/UIStyle" then return dofile(toolkit .. "UIStyle.lua") end
    end
    function w:tick(times) for _=1,times or 1 do Events.OnTickEvenPaused.fire() end end
    function w:loadToolkit() dofile(toolkit .. "ToggleButton.lua"); self:tick() end
    function w:loadWishlist()
        PZSurvivorWishlist = {UI = {toggle=function(num) w.wishlistPlayer = num end}, Settings={key=function() return 67 end}}
        ISEquippedItem = {initialise=function(panel) panel.children={panel.invBtn}; return "native" end}
        dofile(wishlist .. "Sidebar.lua")
    end
    return w
end

test("compact icons sit beside inventory and show status, shortcut and tick", function()
    local w=setup(); w:loadToolkit()
    local side=w.data.equipped
    local light, hub=side.toolkitHighlightButton, side.toolkitToolsButton
    equal(light.title, ""); equal(hub.title, "")
    equal(light.y, 12, "inventory row ignores distant native and hidden admin controls")
    equal(light.x, 54); equal(light.width, 24); equal(hub.x, 82)
    equal(light.image, "Item_Flashlight2")
    equal(hub.image, "media/ui/Entity/Icon_Tools_48x48.png")
    equal(light.imageWidth, 20); equal(hub.imageHeight, 20)
    equal(light.backgroundColor.a, 0); equal(light.isBaseBackgroundVisible, false); equal(light.isBorderVisible, false)
    assert(light.ignoreWidth and light.ignoreHeight and hub.ignoreWidth and hub.ignoreHeight)
    w:tick(20)
    equal(light.textureColor.r, 1); equal(light.textureColor.g, .72); equal(light.textureColor.b, .36)
    equal(light.tooltip, "UI_PZSurvivorToolkit_button_on\nUI_PZSurvivorToolkit_button_tooltip:KEY_66")
    equal(hub.tooltip, "UI_PZSurvivorToolkit_tools_tooltip")
    light:render()
    equal(light.nativeRenders, 1); equal(light.tickDraw.texture, "media/ui/inventoryPanes/Tickbox_Tick.png")
    equal(light.tickDraw.width, 9)
    light:click(); equal(w.enabled, false)
    w:tick(20)
    equal(light.textureColor.r, .55); equal(light.textureColor.g, .55); equal(light.textureColor.b, .55)
    equal(light.tooltip, "UI_PZSurvivorToolkit_button_off\nUI_PZSurvivorToolkit_button_tooltip:KEY_66")
    light.tickDraw=nil; light:render(); equal(light.tickDraw, nil)
    light:click(); w.dead=true; w:tick(20)
    equal(light.enable, false); equal(light.textureColor.r, .55)
    light:click(); equal(w.enabled, true, "death must disable toggling")
    w.dead=false; w:tick(20)
    equal(light.enable, true)
    equal(light.textureColor.r, 1); equal(light.textureColor.g, .72); equal(light.textureColor.b, .36)
    light:click(); w.dead=true; w:tick(20); w.dead=false; w:tick(20)
    equal(light.enable, true); equal(light.textureColor.r, .55)
end)

test("720p sidebar stays beside inventory and preserves foreign geometry", function()
    local w=setup(); w.data.equipped=w:sidebar(700); w:loadToolkit()
    local side=w.data.equipped
    equal(side.toolkitHighlightButton.x, 54); equal(side.toolkitHighlightButton.y, 12)
    equal(side.toolkitToolsButton.x, 82); equal(side.width, 106)
    assert(side.toolkitToolsButton:getAbsoluteY()+side.toolkitToolsButton:getHeight()<=720)
    w:tick(20); equal(side.width, 106); equal(side.height, 980)
    side.width, side.height=130, 1100
    w.show=false; w:tick(20)
    equal(side.width, 130, "foreign resize must stay foreign across subsequent ticks")
    equal(side.height, 1100); equal(side.toolkitHighlightButton, nil)
    assert(side.toolkitToolsButton)
    w.show=true; w:tick(20); equal(side.width, 130); equal(side.height, 1100)
    w.data.equipped=w:sidebar(580, 620); w:tick()
    assert(w.data.equipped.toolkitToolsButton~=side.toolkitToolsButton)
    equal(w.data.equipped.toolkitHighlightButton.y, 12)
    equal(w.data.equipped.toolkitHighlightButton.x, 54)
    equal(w.data.equipped.width, 106)
    w.data.equipped.y=680; w:tick()
    equal(w.data.equipped.toolkitHighlightButton.y, 10, "icon must fit its player viewport")
    assert(w.data.equipped.toolkitToolsButton:getAbsoluteY()+24<=w.top+w.height)
end)

test("tools hub remains with highlight hidden and opens optional tools and settings", function()
    local w=setup(); w.show=false; w:loadToolkit()
    local side=w.data.equipped
    equal(side.toolkitHighlightButton, nil); equal(side.toolkitToolsButton.x, 54)
    side.toolkitToolsButton:click()
    equal(#w.menu.options, 2); equal(w.menu.num, 2)
    equal(w.menu.x, side.x+54+24); equal(w.menu.y, side.y+12)
    equal(w.menu.options[1].name, "UI_PZSurvivorToolkit_context_editor")
    w.menu.options[1].callback(w.menu.options[1].target); equal(w.editorOpened, true)
    w.menu.options[2].callback(w.menu.options[2].target)
    assert(w.mainVisible and w.optionsVisible and w.optionsLoaded)
    equal(w.optionsTab, "UI_mainscreen_mods")
    equal(w.optionsScroll, -1140, "settings must reveal the Toolkit controls")
    w.optionY=30; w.menu.options[2].callback(w.menu.options[2].target)
    equal(w.optionsScroll, 0, "settings near the top must not scroll past the start")
    w.mods.PZSurvivorWishlist=true
    side.toolkitToolsButton:click(); equal(#w.menu.options, 2, "active mod without its UI is unavailable")
    w:loadWishlist(); side.toolkitToolsButton:click()
    equal(#w.menu.options, 3); equal(w.menu.options[1].name, "UI_PZSW_Open")
    w.menu.options[1].callback(w.menu.options[1].target); equal(w.wishlistPlayer, 2)
    w.mods.PZSurvivorWishlist=false; side.toolkitToolsButton:click(); equal(#w.menu.options, 2)
    w.context=false; side.toolkitToolsButton:click(); equal(#w.menu.options, 1)
    w.context=true; PZSurvivorToolkit.ContextMenus=nil; side.toolkitToolsButton:click(); equal(#w.menu.options, 1)
    local last=w.menu; w.dead=true; w:tick(); equal(side.toolkitToolsButton.enable, false)
    side.toolkitToolsButton:click(); equal(w.menu, last)
    w.player=nil; side.toolkitToolsButton:click(); equal(w.menu, last)
end)

test("Wishlist stays standalone, avoids duplicate Toolkit entry and rebuilds sidebar", function()
    local w=setup(); w:loadWishlist()
    local side=w.data.equipped
    Events.OnGameStart.fire(); equal(side.pzswButton, nil, "Toolkit hub owns the Wishlist entry")
    w.mods.PZSurvivorToolkit=false; PZSurvivorToolkit=nil
    Events.OnGameStart.fire()
    local button=side.pzswButton
    assert(button.initialised and button.instantiated)
    equal(button.title, ""); equal(button.image, "media/ui/Entity/Icon_Tools_48x48.png")
    equal(button.x, 54); equal(button.y, 12); equal(button.width, 24); equal(button.height, 24)
    equal(button.imageWidth, 20); equal(button.imageHeight, 20)
    equal(button.backgroundColor.a, 0); equal(button.isBaseBackgroundVisible, false); equal(button.isBorderVisible, false)
    equal(button.nativeTooltip, "UI_PZSW_Open")
    button:click(); equal(w.wishlistPlayer, 2)
    local children=#side.children; Events.OnGameStart.fire(); equal(#side.children, children)
    side.y=680
    equal(ISEquippedItem.initialise(side), "native")
    assert(side.pzswButton~=button and side.pzswButton.parent==side)
    equal(side.pzswButton.y, 10, "standalone icon must fit its player viewport")
    w.wishlistPlayer=nil; Events.OnKeyPressed.fire(67); equal(w.wishlistPlayer, 0)
    w.wishlistPlayer=nil; w.typing=true; Events.OnKeyPressed.fire(67); equal(w.wishlistPlayer, nil)
    w.typing=false; w.optionsVisible=true; Events.OnKeyPressed.fire(67); equal(w.wishlistPlayer, nil)
    w.optionsVisible=false; w.dead=true; Events.OnKeyPressed.fire(67); equal(w.wishlistPlayer, nil)
    w.dead=false; Events.OnKeyPressed.fire(0); equal(w.wishlistPlayer, nil)
    Events.OnKeyPressed.fire(66); equal(w.wishlistPlayer, nil)
end)
print("Sidebar checks passed: " .. count)
