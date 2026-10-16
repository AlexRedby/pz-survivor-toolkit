local root=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/'
local enabled,tagsEnabled=true,true
PZSurvivorToolkit={Settings={inventoryFilters=function() return enabled end,itemTags=function() return tagsEnabled end}}
getText=function(key) return key end
getTextOrNull=function() end
string.trim=function(value) return value:match("^%s*(.-)%s*$") end
local loaded={}
local Tags
local store,listError,saveError,removeError={},nil,nil,nil
local writes,removes=0,0
local Storage={}
function Storage.list()
    if listError then return nil,listError end
    local entries={}
    for name,rule in pairs(store) do entries[#entries+1]={name=name,rule=Tags.normalizeRule(rule)} end
    table.sort(entries,function(a,b) return a.name<b.name end)
    return entries
end
function Storage.save(name,rule)
    writes=writes+1
    if saveError then return nil,saveError end
    if name=='' then return nil,'InvalidName' end
    store[name]=Tags.normalizeRule(rule);return true
end
function Storage.remove(name)
    removes=removes+1
    if removeError then return nil,removeError end
    store[name]=nil;return true
end
require=function(name)
    if name:sub(1,5)=='ISUI/' then return end
    if name=='PZSurvivorToolkit/TagFilterPresets' then return Storage end
    if not loaded[name] then loaded[name]=assert(loadfile(root..'shared/'..name..'.lua'))() end
    return loaded[name]
end
Tags=require 'PZSurvivorToolkit/ItemTags'
local character={}
getSpecificPlayer=function() return character end
local owner={inventory={},getIsVisible=function() return true end}
owner.parent={inventoryPane=owner}
JoypadState={players={{focus=owner}}}
getJoypadData=function(player) return JoypadState.players[player+1] end
setJoypadFocus=function(player,focus) JoypadState.players[player+1].focus=focus end
UIManager={setShowPausedMessage=function() end,getSpeedControls=function() end}
MainScreen={}
ISContextMenu={}
function ISContextMenu:getNew()
    local menu={options={}}
    function menu:addOption(name,target,callback,arg)
        local option={name=name,target=target,onSelect=callback,param1=arg}
        self.options[#self.options+1]=option;return option
    end
    function menu:addSubMenu(option,child) option.submenu=child end
    return menu
end
local function control(parent,internal)
    return {parent=parent,internal=internal,setEnable=function(self,value) self.enable=value end,
        isEnabled=function(self) return self.enable~=false end}
end
local Modal={}
function Modal:initialise() end
function Modal:addToUIManager() self.added=true end
function Modal:removeFromUIManager() self.added=false end
function Modal:setVisible(value) self.visible=value end
function Modal:destroy() self:setVisible(false);self:removeFromUIManager() end
function Modal:showErrorMessage(show,message) self.showError,self.errorMsg=show,message end
ISTextBox=setmetatable({}, {__index=Modal})
function ISTextBox:new(_,_,_,_,prompt,default,target,callback,player)
    local modal=setmetatable({text=prompt,target=target,onclick=callback,player=player,visible=true}, {__index=self})
    modal.entry={value=default,focus=function(self) self.focused=true end,getText=function(self) return self.value end,
        getInternalText=function(self) return self.value end}
    modal.yes,modal.no=control(modal,'OK'),control(modal,'CANCEL')
    return modal
end
function ISTextBox:updateButtons()
    self.yes:setEnable((not self.noEmpty or string.trim(self.entry.value)~='')
        and (not self.maxChars or #self.entry.value<=self.maxChars))
end
function ISTextBox:onClick(button)
    setJoypadFocus(self.player,self.prevFocus)
    self.onclick(self.target,button)
    if not self.showError then self:destroy() end
end
ISModalDialog=setmetatable({}, {__index=Modal})
function ISModalDialog:new(_,_,_,_,text,_,target,callback,player)
    local modal=setmetatable({text=text,target=target,onclick=callback,player=player,visible=true}, {__index=self})
    modal.ok=control(modal,'OK');return modal
end
function ISModalDialog:onClick() self:destroy();setJoypadFocus(self.player,self.prevFocus) end
-- Exercise the real native close/error/focus ordering when source is supplied.
local function nativeMethods(source,class,names)
    source=source:gsub('\r','')
    for _,name in ipairs(names) do
        local start=assert(source:find('function '..class..':'..name..'(',1,true))
        local finish=source:find('\nfunction ',start+1,true) or #source+1
        assert(loadstring(source:sub(start,finish-1)))()
    end
end
if NativeTextBoxSource then nativeMethods(NativeTextBoxSource,'ISTextBox',{'onClick','destroy','showErrorMessage','updateButtons'}) end
if NativeModalDialogSource then nativeMethods(NativeModalDialogSource,'ISModalDialog',{'onClick','destroy'}) end
local Menu=assert(loadfile(root..'client/PZSurvivorToolkit/TagFilterPresetsMenu.lua'))()
local received,applies
local rule={mode='all',include={'food'},exclude={'meat'}}
local function build(value)
    local menu=ISContextMenu:getNew()
    Menu.add(menu,{owner=owner,player=0,rule=value,onApply=function(saved) received=saved;applies=(applies or 0)+1 end})
    return menu
end
local function find(menu,key)
    for _,option in ipairs(menu.options) do
        if option.pzstKey==key then return option end
        if option.submenu then local found=find(option.submenu,key);if found then return found end end
    end
end
local function click(option) return option.onSelect(option.target,option.param1) end
local menu=build(nil)
assert(#menu.options==1 and find(menu,'tagPresets'),'saved filters must use one root submenu')
assert(find(menu,'tagPresetSave').notAvailable and find(menu,'tagPresetDelete').notAvailable)
menu=build(rule)
local dialog=click(find(menu,'tagPresetSave'))
assert(dialog and dialog.maxChars==48 and dialog.noEmpty and dialog.entry.focused and dialog.text=='UI_PZST_TagPresetPrompt')
assert(JoypadState.players[1].focus==dialog,'save dialog did not take controller focus')
if dialog.updateButtons then
    dialog.entry.value=string.rep('x',49);dialog:updateButtons();assert(not dialog.yes.enable,'native 48-character UI limit missing')
    dialog.entry.value='';dialog:updateButtons();assert(not dialog.yes.enable,'native empty-name guard missing')
    dialog.entry.value=string.rep('x',48);dialog:updateButtons();assert(dialog.yes.enable,'native 48-character boundary rejected')
end
local writesBeforeEnter=writes
dialog.entry.value=string.rep('x',100);dialog.entry.onCommandEntered()
assert(writes==writesBeforeEnter and dialog.added and not dialog.yes:isEnabled(), 'Enter bypassed the 48-character name limit')
dialog.entry.value='   ';dialog.entry.onCommandEntered()
assert(writes==writesBeforeEnter and dialog.added and not dialog.yes:isEnabled(), 'Enter bypassed the empty-name guard')
rule.include[1]='tool'
dialog.entry.value='Pantry';dialog.entry.onCommandEntered()
assert(store.Pantry.include[1]=='food' and not dialog.added and JoypadState.players[1].focus==owner,'save snapshot or focus restoration failed')
menu=build(rule);assert(find(menu,'tagPreset:Pantry'),'saved filter missing after reopening menu')
click(find(menu,'tagPreset:Pantry'));assert(received.include[1]=='food')
received.include[1]='electrical';assert(store.Pantry.include[1]=='food','applied rule aliases stored rule')
-- Same name deliberately replaces its definition through the standard dialog.
dialog=click(find(menu,'tagPresetSave'));dialog.entry.value='Pantry';dialog:onClick(dialog.yes)
assert(store.Pantry.include[1]=='tool','existing name was not replaced')
menu=build(rule);dialog=click(find(menu,'tagPresetSave'))
saveError='WriteFailed';dialog.entry.value='Keep my name';dialog:onClick(dialog.yes)
assert(dialog.added and dialog.showError and dialog.entry.value=='Keep my name' and not store['Keep my name']
    and store.Pantry.include[1]=='tool','write failure lost dialog input or previous data')
assert(JoypadState.players[1].focus==dialog,'native error callback lost controller focus')
dialog:onClick(dialog.no);assert(not dialog.added and not dialog.showError,'cancel after error left dialog open')
saveError=nil
menu=build(rule);dialog=click(find(menu,'tagPresetSave'));dialog.entry.value='';dialog:onClick(dialog.yes)
assert(dialog.showError and dialog.errorMsg=='UI_PZST_TagPresetInvalidName','invalid name feedback missing')
dialog:onClick(dialog.no)
menu=build(rule);removeError='WriteFailed'
local failure=click(find(menu,'tagPresetDelete:Pantry'))
assert(failure and failure.added and failure.text=='UI_PZST_TagPresetWriteFailed' and store.Pantry,'delete failure lost previous data')
failure:onClick(failure.ok);removeError=nil
menu=build(rule);click(find(menu,'tagPresetDelete:Pantry'))
assert(not store.Pantry and not find(build(rule),'tagPreset:Pantry'),'delete/reopened menu kept old filter')
for _,error in ipairs({'ReadFailed','Version'}) do
    listError=error;menu=build(rule)
    assert(not find(menu,'tagPresetSave') and not find(menu,'tagPresetDelete'),'unreadable storage exposed mutation actions')
    local errorDialog=click(find(menu,'tagPresetError'))
    assert(errorDialog and errorDialog.text=='UI_PZST_TagPreset'..error,'read error native feedback missing')
    errorDialog:onClick(errorDialog.ok)
end
listError=nil
Storage.save('Stale',rule)
menu=build(rule)
local oldApply,oldSave,oldDelete=find(menu,'tagPreset:Stale'),find(menu,'tagPresetSave'),find(menu,'tagPresetDelete:Stale')
local oldInventory=owner.inventory;owner.inventory={}
local count=applies;local writesBefore,removesBefore=writes,removes
click(oldApply);assert(not click(oldSave));click(oldDelete)
assert(applies==count and writes==writesBefore and removes==removesBefore,'stale container menu mutated state')
owner.inventory=oldInventory
menu=build(rule);dialog=click(find(menu,'tagPresetSave'));dialog.entry.value='Must not save'
owner.removed=true;dialog:onClick(dialog.yes)
assert(not store['Must not save'] and not dialog.added,'removed owner dialog wrote a preset')
owner.removed=nil
menu=build(rule);local selected=find(menu,'tagPreset:Stale')
local prior=character;character={};click(selected);assert(applies==count,'previous player menu changed new session')
character=prior
owner.parent.inventoryPane={};click(selected);assert(applies==count,'replaced pane menu still applied')
owner.parent.inventoryPane=owner
enabled=false;click(selected);assert(applies==count and #build(rule).options==0,'disabled inventory filters still applied/surfaced presets')
enabled=true;tagsEnabled=false;click(selected);assert(applies==count and #build(rule).options==0,'disabled tags still applied/surfaced presets')
print('Saved tag-filter menu passed: named snapshots, replacement, native dialogs/focus, apply/delete/errors, stale owners and opt-out.')
