local base = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/"
next = nil
require = function() end
local function event()
    return {Add = function() end}
end
Events = {OnServerCommand=event(), OnTick=event(), OnGameStart=event(), OnMainMenuEnter=event(),
    OnMechanicActionDone=event()}
local seated, paused, enabled = false, false, true
local player = {getUsername=function() return "alice" end, getVehicle=function() return seated and {} or nil end}
getSpecificPlayer = function() return player end
isClient, isDebugEnabled, getDebug = function() return false end, function() return false end, function() return false end
getTimestampMs = function() return 0 end
getText = function(key) return key end
getTextOrNull = function() return nil end
UIManager = {getSpeedControls=function()return{getCurrentGameSpeed=function()return paused and 0 or 1 end}end}
PZSurvivorWishlist = {Service = {username=function() return "alice" end}}
dofile(base .. "client/PZSurvivorWishlist/Client.lua")
local W, C = PZSurvivorWishlist, PZSurvivorWishlist.Client
W.Settings = {rowsEnabled=function() return enabled end, color=function() return {r=.25,g=.85,b=.75} end}
local function snapshot(entries)
    C.receive(0, {lists={{id="alice",owner="alice",revision=0,entries=entries,members={}}}})
end
local function item(fullType) return {getFullType=function() return fullType end} end
local function list(values)
    return {size=function()return #values end,isEmpty=function()return #values==0 end,
        get=function(_,i)return values[i+1]end}
end
local valid = {}
for class=1,3 do
    for _, tier in ipairs({"Old", "Normal", "Modern"}) do valid["Base."..tier.."Tire"..class]=true end
end
ScriptManager = {instance={FindItem=function(_, fullType)
    if valid[fullType] then return {getFullName=function() return fullType end} end
end}}
local function part(class, fullType)
    local install, uninstall = {}, {}
    return {getItemType=function()return list({"Base.OldTire"..class,"Base.NormalTire"..class,"Base.ModernTire"..class})end,
        getVehicle=function()return{getScript=function()return{getMechanicType=function()return class end}end,
            canInstallPart=function()return false end,canUninstallPart=function()return false end}end,
        getInventoryItem=function()return fullType and item(fullType) or nil end,
        getTable=function(_,name)return name=="install" and install or name=="uninstall" and uninstall or nil end,
        getWindow=function()return nil end,isContainer=function()return false end,
        getId=function()return "TireFrontLeft" end,getCondition=function()return 50 end,
        getScriptPart=function()return{isRepairMechanic=function()return false end}end}
end
local menu = {options={}, numOptions=1, setVisible=function(self,v)self.visible=v end}
function menu:addOption(name,target,callback)
    local option={name=name,target=target,onSelect=callback}
    self.options[#self.options+1]=option;self.numOptions=#self.options+1
    return option
end
local function nativeContext(self)
    if paused or seated then return end
    menu.options,menu.numOptions,menu.visible={},1,true
    self.context=menu
end
ISVehicleMechanics = {doPartContextMenu=nativeContext, doDrawItem=function(self,y)self.nativeDraw=true;return y+self.itemheight end}
if NativeWishlistGameRoot then
    ISCollapsableWindow = {derive=function() return {} end}
    UIFont={Small=1,Medium=2}
    getTextManager=function()return{getFontHeight=function()return 14 end,MeasureStringX=function(_,_,s)return #s end}end
    getCore=function()return{getBadHighlitedColor=function()return{getR=function()return 1 end,getG=function()return 0 end,getB=function()return 0 end}end}end
    ISContextMenu={get=function()menu.options,menu.numOptions,menu.visible={},1,true;return menu end}
    FixingManager={getFixes=function()return list({})end}
    JoypadState={players={}}
    ISVehiclePartMenu={}
    dofile(NativeWishlistGameRoot .. "/media/lua/client/Vehicles/ISUI/ISVehicleMechanics.lua")
    ISVehicleMechanics.getWrench=function()end
    ISVehicleMechanics.getScrewdriver=function()end
    ISVehicleMechanics.getTirePump=function()end
end
local V=dofile(base .. "client/PZSurvivorWishlist/Vehicles.lua")
V.install();local wrapped=ISVehicleMechanics.doPartContextMenu;V.install();assert(wrapped==ISVehicleMechanics.doPartContextMenu)
local empty=part(2)
local request=assert(V.entry(empty))
assert(request.fullType=="Base.OldTire2" and #request.vehicleTypes==3 and request.vehicleClass==2)
snapshot({['vehicle:Base.OldTire2']={amount=1,done=false,vehicleTypes=request.vehicleTypes,vehicleClass=2}})
for _,tier in ipairs({"Old","Normal","Modern"})do
    assert(C.isWanted(0,"Base."..tier.."Tire2"))
    assert(not C.isWanted(0,"Base."..tier.."Tire1") and not C.isWanted(0,"Base."..tier.."Tire3"))
end
assert(V.isWanted(0,part(2,"Base.ModernTire2")) and not V.isWanted(0,empty))
assert(not V.isWanted(0,part(1,"Base.ModernTire1")))
assert(C.carriedCount({['Base.OldTire2']=1,['Base.NormalTire2']=2,['Base.ModernTire2']=3,['Base.ModernTire1']=50},request.fullType,request)==6)
local window=setmetatable({playerNum=0,chr=player,doMenuTooltip=function()end,getAbsoluteX=function()return 0 end,getAbsoluteY=function()return 0 end}, {__index=ISVehicleMechanics})
local added, edited
C.edit=function(num,action,values)
    assert(num==0);edited={action=action,values=values};added=values.entries and values.entries[1]
end
local function wishlistOption()
    local found
    for _,option in ipairs(menu.options)do
        if option.name=="UI_PZSW_AddVehicleWanted" or option.name=="UI_PZSW_RemoveVehicleWanted" then
            assert(not found,"menu must contain only one Wishlist option")
            found=option
        end
    end
    return found
end
snapshot({})
-- Native GloveBox advertises an item type but has no replacement recipe.
for _,id in ipairs({"GloveBox","Chassis"})do
    local fixed=part(2,"Base."..id)
    valid["Base."..id]=true
    fixed.getId=function()return id end
    fixed.getItemType=function()return list({"Base."..id})end
    fixed.getTable=function()return nil end
    window:doPartContextMenu(fixed,0,0)
    assert(not wishlistOption(),"nonreplaceable "..id.." must not be offered in Wishlist")
    fixed.getInventoryItem=function()return nil end
    window:doPartContextMenu(fixed,0,0)
    assert(not wishlistOption(),"empty nonreplaceable "..id.." must not be offered in Wishlist")
    if id=="GloveBox" then
        fixed.getTable=function(_,name)return name=="install" and {} or nil end
        window:doPartContextMenu(fixed,0,0)
        local option=assert(wishlistOption(),"modded replaceable glovebox must remain supported")
        option.onSelect(option.target)
        assert(added.fullType=="Base.GloveBox")
    end
end
assert(V.entry(part(2,"Base.ModernTire2")).fullType=="Base.OldTire2","installed replaceable tire remains requestable")
for _=1,3 do
    window:doPartContextMenu(empty,0,0)
    local option=assert(wishlistOption(),"reused native menu must regain its Wishlist option")
    assert(menu.visible and #menu.options==(NativeWishlistGameRoot and 2 or 1))
    if NativeWishlistGameRoot then
        assert(menu.options[1].name=="IGUI_Install" and menu.options[1].notAvailable,
            "temporarily unavailable native install must still allow Wishlist")
        assert(not option.notAvailable)
    end
    option.onSelect(option.target)
    assert(added.vehicleTypes[3]=="Base.ModernTire2")
end
local options,optionCount=menu.options,#menu.options
paused=true;window:doPartContextMenu(empty,0,0);assert(menu.options==options and #menu.options==optionCount);paused=false
seated=true;window:doPartContextMenu(empty,0,0);assert(menu.options==options and #menu.options==optionCount);seated=false
local group={amount=1,done=true,vehicleTypes=request.vehicleTypes,vehicleClass=2}
snapshot({['vehicle:Base.OldTire2']=group})
window:doPartContextMenu(part(2,"Base.ModernTire2"),0,0)
assert(wishlistOption().name=="UI_PZSW_RemoveVehicleWanted", "done group on another donor is removable")
C.receive(0,{lists={{id="bob",owner="bob",revision=0,entries={},members={}},
    {id="alice",owner="alice",revision=0,entries={['vehicle:Base.OldTire2']=group},members={}}}})
C.select(0,"bob");local remove=wishlistOption();remove.onSelect(remove.target)
assert(edited.action=="remove" and edited.values.listId=="alice" and edited.values.fullType=="vehicle:Base.OldTire2")
window:doPartContextMenu(part(1,"Base.ModernTire1"),0,0)
assert(wishlistOption().name=="UI_PZSW_AddVehicleWanted", "another vehicle class retains Add")
C.select(0,"alice");local add=wishlistOption();add.onSelect(add.target)
assert(edited.action=="addMany" and edited.values.listId=="bob" and added.vehicleClass==1)
snapshot({['vehicle:Base.OldTire2']={amount=1,done=false,vehicleTypes=request.vehicleTypes,vehicleClass=2}})
local draws=0
local pane={parent=window,itemheight=20,selected=-1,mouseoverselected=-1,getWidth=function()return 250 end,
    drawRect=function()end,drawRectBorder=function()draws=draws+1 end,drawText=function()end}
window.partRGB={r=1,g=1,b=1,a=1};window.getConditionRGB=function()return{r=1,g=1,b=1}end
local row={height=20,item={part=part(2,"Base.ModernTire2"),name="Tire"}}
assert(ISVehicleMechanics.doDrawItem(pane,10,row)==30 and draws==1)
row.item.part=empty;ISVehicleMechanics.doDrawItem(pane,10,row);assert(draws==1)
row.item.part=part(2,"Base.NormalTire2");enabled=false;ISVehicleMechanics.doDrawItem(pane,10,row);assert(draws==1);enabled=true
snapshot({['vehicle:Base.OldTire2']={amount=1,done=true,vehicleTypes=request.vehicleTypes,vehicleClass=2}})
assert(not C.isWanted(0,"Base.ModernTire2"));ISVehicleMechanics.doDrawItem(pane,10,row);assert(draws==1)
snapshot({['Base.OldTire2']={amount=2,done=false}})
assert(C.isWanted(0,"Base.OldTire2") and not C.isWanted(0,"Base.NormalTire2"))
snapshot({});assert(not C.isWanted(0,"Base.OldTire2"),"revocation clears expanded matching")
local invalid=part(2);invalid.getItemType=function()return list({"Missing.ModPart"})end;assert(V.entry(invalid)==nil)
print("PASS vehicle wishlist: native-compatible variants, classes, replaceable and fixed slots, repeated menu, early exits, row highlight, counts, done and revocation")
