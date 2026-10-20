local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
PZSurvivorToolkit = {}
UIFont = {Small=1, Medium=2}
Joypad = {AButton=1, BButton=2}
getText = function(key) return key end
getTextManager = function() return {MeasureStringX=function(_, _, text) return #text end} end
local player = {getJoypadBind=function() return 0 end}
getSpecificPlayer = function() return player end
local focus
setJoypadFocus = function(_, value) focus=value end
ColorInfo = {new=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end}
local Widget = {}
function Widget:new() return setmetatable({}, {__index=self}) end
function Widget:initialise() end
function Widget:instantiate() end
function Widget:setTooltip(value) self.tooltip=value end
function Widget:setText(value) self.value=value end
function Widget:getInternalText() return self.value end
function Widget:setImage(value) self.image=value end
function Widget:setTitle(value) self.title=value end
function Widget:forceImageSize(w,h) self.imageSize={w,h} end
function Widget:setMaxTextLength(value) self.limit=value end
function Widget:setX(value) self.x=value end
function Widget:setY(value) self.y=value end
function Widget:setWidth(value) self.width=value end
function Widget:getAbsoluteX() return self.x or 10 end
function Widget:getAbsoluteY() return self.y or 20 end
function Widget:getHeight() return 26 end
function Widget:addToUIManager() self.visible=true end
function Widget:removeSelf() self.visible=false;focus=self.resetFocusTo end
ISLabel, ISButton = Widget, Widget
ISTextEntryBox = setmetatable({}, {__index=Widget})
function ISTextEntryBox:new(value) local result=Widget.new(self);result.value=value;return result end
ISColorPickerHSB = setmetatable({}, {__index=Widget})
function ISColorPickerHSB:setPickedFunc(fn) self.pickedFunc=fn;self.pickedArgs={} end
function ISColorPickerHSB:setInitialColor(color) self.pickedRGB=color end
-- The actual installed native Save passes false; gamepad passes nil. Neither is a release flag.
if NativeColorPickerSource then
    local source=NativeColorPickerSource:gsub('\r','')
    for _, method in ipairs({'onSave', 'picked'}) do
        local body=assert(source:match('(function ISColorPickerHSB:'..method..'%(.-)\nfunction '))
        assert(loadstring(body))()
    end
else
    function ISColorPickerHSB:onSave() self.pickedFunc(self.pickedTarget,self.pickedRGB,false) end
    function ISColorPickerHSB:picked() self.pickedFunc(self.pickedTarget,self.pickedRGB,nil) end
end
local saved={name='Old',icon={kind='item',value='Base.Plank'},color={r=0.2,g=0.3,b=0.4,a=1}}
local reads, iconCallback = 0
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for key,v in pairs(value) do result[key]=copy(v) end;return result
end
local enabled=true
local styles={food={r=.48,g=.8,b=.4},medical={r=.95,g=.43,b=.4},tool={r=.4,g=.68,b=.95}}
local tags={forCategory=function(key) return key=='Tools' and {'tool'} or {} end,
    forScriptItem=function(script) return script and {'tool','carpentry'} or {} end,
    label=function(id) return 'Label '..id end}
LootSorter={getItemFullType=function(key) return key=='Hammer' and 'Base.Hammer' end}
getScriptManager=function() return {FindItem=function(_,key) assert(key=='Base.Hammer');return {} end} end
require=function(name)
    if name:sub(1,5)=='ISUI/' then return end
    if name=='PZSurvivorToolkit/ContainerAppearance' then return {
        available=function() return enabled end,
        read=function(obj,ci,who) assert(obj=='crate' and ci==2 and who==player);reads=reads+1;return copy(saved) end}
    end
    if name=='BetterContainers/Helpers' then return {getIconTexture=function(icon) return icon.value end} end
    if name=='PZSurvivorToolkit/ContainerIconPicker' then return {open=function(_,fn) iconCallback=fn end} end
    if name=='PZSurvivorToolkit/ContainerTagIcons' then return {install=function() end} end
    if name=='PZSurvivorToolkit/ItemTags' then return tags end
    if name=='PZSurvivorToolkit/TagVisuals' then return {get=function(id) return assert(styles[id]) end} end
    error(name)
end
local Controls=dofile(root..'client/PZSurvivorToolkit/ContainerAppearanceControls.lua')
local function picker(kind)
    local p={targetKind=kind or 'box',targetObj='crate',targetCI=2,playerNum=0}
    function p:addChild() end
    function p:getWidth() return 396 end
    Controls.create(p)
    return p
end
local p=picker()
assert(p.appearanceName.value=='Old' and p.appearanceIcon.image=='Base.Plank')
assert(Controls.value(p)==nil and Controls.layout(p,28)==92)
Controls.select(p,'tag','food')
assert(Controls.value(p)==nil,'selection overwrote an existing appearance')
p.appearanceName:setText('New')
Controls.chooseIcon(p);iconCallback({kind='item',value='Base.Hammer'})
Controls.chooseColor(p)
local popup=p.toolkitColorPicker
assert(focus==popup and popup.visible)
popup.pickedRGB={r=0.8,g=0.5,b=0.1};popup:onSave()
assert(focus==p and not popup.visible and p.toolkitAppearance.color.r==0.8,'native false-valued Save dropped color')
Controls.chooseColor(p);popup=p.toolkitColorPicker;popup.pickedRGB={r=0.1,g=0.9,b=0.2};popup:picked(true)
assert(p.toolkitAppearance.color.g==0.9,'native gamepad nil-valued confirm dropped color')
local value=Controls.value(p)
assert(value.name=='New' and value.icon.value=='Base.Hammer' and value.color.g==0.9)
assert(saved.name=='Old' and saved.icon.value=='Base.Plank' and saved.color.g==0.3,'draft mutated stored appearance')
Controls.reset(p);value=Controls.value(p)
assert(value.name=='' and not value.icon and not value.color,'reset kept an override')
Controls.chooseColor(p);p.toolkitTagClosed=true;popup=p.toolkitColorPicker;popup:onSave()
assert(not p.toolkitAppearance.color,'late color callback changed closed draft')
Controls.close(p);assert(not popup.visible and not p.toolkitColorPicker)
saved={};p=picker()
assert(Controls.value(p)==nil,'opening a blank editor suggested an appearance')
Controls.select(p,'presets','Pantry')
assert(Controls.value(p)==nil,'unordered preset guessed a first tag')
Controls.select(p,'tag','medical');Controls.select(p,'tag','food')
value=Controls.value(p)
assert(value.name=='Label medical' and value.icon.kind=='pzst-tag' and value.icon.value=='medical'
    and value.color.r==styles.medical.r,'later or alphabetically earlier tag replaced the first selection')
assert(not saved.icon and not saved.color and not saved.name,'suggestion mutated stored values before Save')
p.appearanceName:setText('');Controls.select(p,'tag','food')
assert(Controls.value(p).name=='','later selection refilled a deliberately empty name')
Controls.reset(p);Controls.select(p,'items','Hammer');Controls.select(p,'tag','food')
value=Controls.value(p)
assert(value.name=='' and value.icon.kind=='item' and value.icon.value=='Base.Hammer'
    and value.color.b==styles.tool.b,'item did not use its icon and primary tag color without a name')
Controls.reset(p);Controls.select(p,'cats','Tools')
assert(Controls.value(p).name=='Label tool','reset did not allow a fresh first choice')
for _,field in ipairs({'name','icon','color'}) do
    local custom={name='My box',icon={kind='container',value='crate'},color={r=.2,g=.4,b=.6,a=1}}
    saved={[field]=custom[field]};p=picker();Controls.select(p,'tag','food');value=Controls.value(p)
    assert(value.name==(field=='name' and 'My box' or 'Label food'))
    assert(value.icon.value==(field=='icon' and 'crate' or 'food'))
    assert(value.color.r==(field=='color' and .2 or styles.food.r),'filled fields were not preserved independently')
end
saved={};p=picker();p.appearanceName:setText('Typed before selection');Controls.select(p,'items','Hammer')
assert(Controls.value(p).name=='Typed before selection','item erased a manually typed name')
assert(not picker('preset').appearanceName,'sorting preset acquired a chest appearance')
enabled=false;assert(not picker().appearanceName,'BC-free picker created appearance controls')
print('PASS appearance draft, first tag/item suggestions, independent preservation, reset/cancel and native color callbacks')
