local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local Base = {}
function Base:derive() return setmetatable({}, {__index=self}) end
function Base:new(x,y,w,h) return setmetatable({x=x,y=y,width=w,height=h}, {__index=self}) end
function Base:addToUIManager() self.visible=true end
function Base:removeFromUIManager() self.visible=false end
function Base:setVisible(value) self.visible=value end
ISCollapsableWindowJoypad = Base
getText = function(key) return key end
getCore = function() return {getScreenWidth=function() return 1280 end, getScreenHeight=function() return 800 end} end
getSpecificPlayer = function() return nil end

-- Distinct atlas images can share a GPU ID and display name; retain both texture objects.
local red = {getID=function() return 12 end}
local blue = {getID=function() return 12 end}
local shared = {label='Arafatka',name='Scarf',searchText='Clothing equipment',tex=red,
    icon={kind='item',value='Base.Arafatka'},expanded=true,children={
        {label='Worn scarf',searchText='A[1] cloth',tex=red,icon={kind='item',value='Base.WornScarf'},
            _aliasList={'Base.HiddenAlias','Base.AnotherAlias'}},
        {label='Container alias',tex=red,icon={kind='container',value='scarfbox'}},
    }}
local catalogue = {groupsSorted={shared,
    {label='Arafatka',tex=blue,icon={kind='item',value='Base.ArafatkaBlue'}},
    {label='Missing first',icon={kind='item',value='Base.Missing'},children={
        {label='Missing alias',searchText='unavailable image',icon={kind='item',value='Base.Missing'}},
    }},
    {label='Missing second',icon={kind='item',value='Base.OtherMissing'}},
    {label='No descriptor',tex=red},
},selectedIcon=shared.children[1].icon}
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for key,v in pairs(value) do result[key]=copy(v) end;return result
end
local function unchanged(value, snapshot)
    if type(value)~='table' then assert(value==snapshot, 'source catalogue changed');return end
    for key,v in pairs(value) do assert(snapshot[key]~=nil, 'source acquired a field');unchanged(v,snapshot[key]) end
    for key in pairs(snapshot) do assert(value[key]~=nil, 'source lost a field') end
end
local before=copy(catalogue)
require = function(name)
    if name:sub(1,5)=='ISUI/' then return end
    if name=='PZSurvivorToolkit/UIStyle' then return {fit=function(value) return value end} end
    if name=='BetterContainers/Customize/ui/IconCatalogue' then return {getCatalogue=function() return catalogue end} end
    error(name)
end
local Picker=dofile(root..'client/PZSurvivorToolkit/ContainerIconPicker.lua')
-- UI doubles expose the real projection, filtering, selection and owner lifecycle.
function Picker:initialise()
    self.search={value='',getInternalText=function(s) return s.value end,unfocus=function() end}
    self.list={items={},selected=1,clear=function(s) s.items={} end,
        addItem=function(s,label,item) s.items[#s.items+1]={text=label,item=item} end}
    self:reload()
end
local oldMouseDown=function() return false end
local owner={dimmer={onMouseDown=oldMouseDown,setVisible=function(s,value) s.visible=value end}}
local picked
local picker=Picker.open(owner,function(icon) picked=icon end)
assert(#picker.entries==4 and #picker.list.items==4, 'shared images were not collapsed or missing images were merged')
assert(picker.entries[1].texture==red and picker.entries[2].texture==blue,
    'different images with equal GPU IDs/display names were merged')
assert(picker.entries[1].icon.kind=='item' and picker.entries[1].icon.value=='Base.Arafatka',
    'first valid image lost its original descriptor')
assert(picker.entries[3].texture==nil and picker.entries[4].texture==nil,
    'missing image acquired another icon texture')
for _,query in ipairs({'worn scarf','clothing equipment','a[1]','base.hiddenalias','base.anotheralias','scarfbox','Scarf'}) do
    picker.search.value=query;picker:reload()
    assert(#picker.list.items==1 and picker.list.items[1].item==picker.entries[1], 'collapsed alias is not searchable: '..query)
end
picker.search.value='unavailable image';picker:reload()
assert(#picker.list.items==1 and picker.list.items[1].item==picker.entries[3], 'nil-texture duplicate lost its search aliases')
picker.search.value='base.arafatkablue';picker:reload()
assert(#picker.list.items==1 and picker.list.items[1].item==picker.entries[2], 'distinct color variant is not searchable')
picker.search.value='';picker:reload();picker.list.selected=1;picker:choose()
assert(picked.kind=='item' and picked.value=='Base.Arafatka' and picked~=shared.icon,
    'selection did not return a detached original descriptor')
assert(not picker.visible and not owner.toolkitIconPicker and not owner.dimmer.visible
    and owner.dimmer.onMouseDown==oldMouseDown, 'selection broke picker close/owner cleanup')
picked.value='changed by callback'
unchanged(catalogue,before)
assert(catalogue.selectedIcon==shared.children[1].icon and shared.tex==red and shared.children[1].tex==red,
    'source texture, selection or alias identities changed')
picker=Picker.open(owner,function(icon) picked=icon end);picker:clearIcon()
assert(picked==nil, 'default icon selection changed its callback contract')
unchanged(catalogue,before)
print('PASS icon image deduplication, distinct variants, alias search, nil textures, descriptors and source isolation')
