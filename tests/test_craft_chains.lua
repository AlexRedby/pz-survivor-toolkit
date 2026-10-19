next = nil -- Native Kahlua does not expose this Lua standard-library global.
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local enabled, dead, recipe, quantity, changedId, changedMaterial, queued = true, false, {}, nil, 1, false, 0
local player = {getPlayerNum=function() return 0 end, isDead=function() return dead end, isAsleep=function() return false end}
getSpecificPlayer = function() return player end
getText = function(key, ...) return key .. table.concat({...}, ',') end
getTextManager = function() return {getFontHeight=function() return 14 end,MeasureStringX=function(_,_,value) return #value*6 end} end
getCore = function() return {getScreenWidth=function() return 1280 end, getScreenHeight=function() return 720 end} end
getScriptManager = function() return {getItem=function(_, id) return {
    getDisplayName=function() return id end,getNormalTexture=function() return id..'-icon' end} end} end
getMouseX,getMouseY=function() return 10 end,function() return 20 end
ISContextMenu={get=function()
    return {options={},addOption=function(self,label,target,callback,selection)
        local option={name=label,target=target,onSelect=callback,selection=selection}
        self.options[#self.options+1]=option;return option
    end,setOptionChecked=function(_,option,checked) option.checked=checked end,
    hideAndChildren=function(self) self.hidden=true end}
end}
UIFont = {Small=1}
local methods = {}
for _, name in ipairs({'Visible','Enable','X','Y','Width','Height','Tooltip','YScroll','AnchorLeft','AnchorRight','AnchorTop','AnchorBottom'}) do
    methods['set'..name] = function(self, value) self[name:lower()] = value end
end
function methods:initialise() end
function methods:instantiate() if self.createChildren then self:createChildren() end end
function methods:addChild(child) self.children = self.children or {}; table.insert(self.children,child) end
function methods:removeChild(child) for i,v in ipairs(self.children or {}) do if v==child then table.remove(self.children,i);break end end end
function methods:getIsVisible() return self.visible ~= false end
function methods:addToUIManager() self.managed = true end
function methods:bringToTop() self.raised = true end
function methods:removeFromUIManager() self.managed = false end
function methods:drawText() end
function methods:drawTextRight() end
function methods:drawRect() end
function methods:titleBarHeight() return 20 end
function methods:getAbsoluteX() return self.x end
function methods:getAbsoluteY() return self.y end
function methods:getYScroll() return self.yscroll or 0 end
function methods:setOnlyNumbers() end
function methods:unfocus() self.unfocused = true end
function methods:getText() return self.value end
function methods:addItem(name, row, tooltip) self.items[#self.items+1]={item=row,text=name,tooltip=tooltip} end
function methods:clear() self.items={} end
function methods:setOnMouseDownFunction(target,callback) self.target,self.onmousedown=target,callback end
local function widget(x,y,w,h)
    return setmetatable({x=x,y=y,width=w,height=h,visible=true,children={},items={}}, {__index=methods})
end
ISPanel = {createChildren=function() end, prerender=function() end}
function ISPanel:derive()
    local class = setmetatable({}, {__index=methods})
    function class:new(x,y,w,h) return setmetatable(widget(x,y,w,h), {__index=class}) end
    return class
end
ISCollapsableWindow = {new=function(_,...) return widget(...) end}
ISScrollingListBox = {new=function(_,...) local list=widget(...);list.vscroll=widget(0,0,17,100);return list end}
ISInventoryItem = {renderScriptItemIcon=function(list) list.icons=(list.icons or 0)+1 end}
NinePatchTexture = {getSharedTexture=function() return {render=function() end} end}
NC_UserConfig = {getSlotAlpha=function(alpha) return alpha end,getInnerPanelAlpha=function(alpha) return alpha end}
NCConfig = {slotPanelBackgroundAlpha=0.8}
ISTextEntryBox = {new=function(_,value,x,y,w,h) local o=widget(x,y,w,h);o.value=value;return o end}
ISButton = {new=function(_,x,y,w,h,label,target,callback)
    local o=widget(x,y,w,h);o.title,o.target,o.onclick=label,target,callback;return o
end}
local function layout()
    return {elements={}, addRow=function(self)
        local row={num=#self.elements+1,setVisible=methods.setVisible,index=function(self) return self.num end}
        return row
    end, setElement=function(self,col,row,button) self.elements[row]=button end}
end
ISHandCraftPanel = {OnCloseWindow=function() return "owner-close" end}
ISCraftRecipePanel = {createDynamicChildren=function(panel) panel.rootTable=layout();return 'native',nil,7 end,
    prerender=function() return true end}
NC_CellBaseCraft = {createChildren=function() return 'created' end, prerender=function() end,
    layoutChildren=function(panel,w,h) panel.baseHeight=h;panel.otherY=h-24;return 'layout',nil,5 end}
NC_HandCraftPanel = {onLogicRecipeChanged=function() return 'recipe' end}
local nativeInput, nativeOutput, nativeBack = {}, {}, 0
Joypad = {BButton=2}
NC_HandcraftWindow = {close=function() return 'close' end,
    getJoypadInputEntries=function() return {nativeInput} end,
    getJoypadOutputEntries=function() return {nativeOutput} end,
    onJoypadDown=function() nativeBack=nativeBack+1 end}
NC_EntityWindow={}
for key,value in pairs(NC_HandcraftWindow) do NC_EntityWindow[key]=value end
local onStart, resets = nil, {}
Events = {OnGameStart={Add=function(f) onStart=f end}}
for _, name in ipairs({'OnMainMenuEnter','OnGameExit','OnPlayerDeath'}) do
    Events[name] = {Add=function(fn) resets[name]=fn end}
end
PZSurvivorToolkit = {Settings={craftChains=function() return enabled end}}
local allChoices={{fullType='Handle',amount=1},{fullType='Plank',amount=1},{fullType='Missing',amount=1}}
local spec = {id='spoon',name='Wooden <Spoon>',inputs={
    {index=0,keep=false,choices=allChoices,allChoices=allChoices},
    {index=1,keep=true,choices={{fullType='Knife',amount=1}}}},outputs={Spoon=1}}
local Recipes = {
    collect=function(panel,overrides)
        local chosen=overrides and overrides.spoon and overrides.spoon[0]
        spec.inputs[1].preference=chosen or nil
        spec.inputs[1].choices=chosen and {{fullType=chosen,amount=1}} or allChoices
        return {recipes={spoon=spec},resources={{fullType='Handle'},{fullType='Handle'},
            {fullType='Plank'},{fullType='Knife'}},accepts=function() return true end},'spoon',{player=player}
    end,
    enqueue=function(who,plan,context) queued=queued+1;return true end
}
local Planner = {plan=function(model,target,count)
    quantity=count
    if spec.inputs[1].preference=='Missing' then return nil,'missing','Missing' end
    local material=spec.inputs[1].preference or (changedMaterial and 'Plank' or 'Handle')
    return {target='spoon',count=count,steps={{recipe=spec,inputs={
        [0]={fullType=material,amount=count,resourceIds={changedId},generated=0},
        [1]={fullType='Knife',amount=1,resourceIds={42},generated=0},
    }}},consumed={Handle=count}}
end}
require = function(name)
    if name=='PZSurvivorToolkit/UIStyle' then
        return dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'..name..'.lua')
    end
    if name=='PZSurvivorToolkit/CraftChainRecipes' then return Recipes end
    if name=='PZSurvivorToolkit/CraftPlanner' then return Planner end
end
local Chains=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/CraftChains.lua'))()
local function panel()
    return setmetatable({logic={getPlayer=function() return player end,getRecipe=function() return recipe end},
        xuiRecalculateLayout=function(self) self.recalculated=true end,
        calculateLayout=function(self,w,h) NC_CellBaseCraft.layoutChildren(self,w,h) end,
        width=500,height=400}, {__index=methods})
end
local function rows(view,kind)
    local result={}
    for _,item in ipairs(view.preview.items) do if item.item.kind==kind then result[#result+1]=item.item end end
    return result
end
onStart();Chains.install()
local p=panel()
local a,b,c=ISCraftRecipePanel.createDynamicChildren(p)
check(a=='native' and b==nil and c==7,'native return tuple retained')
check(#p.rootTable.elements==1 and p.pzstPlanButton.onclick==Chains.open,'single native planning row')
ISCraftRecipePanel.createDynamicChildren(p)
check(#p.rootTable.elements==1,'recipe changes rebuild without accumulating buttons')
enabled=false;ISCraftRecipePanel.prerender(p)
check(not p.pzstPlanButton.visible and not p.pzstPlanButton.pzstRow.visible,'disabled native option removes reserved row')
enabled=true;ISCraftRecipePanel.prerender(p)
check(p.pzstPlanButton.visible and p.pzstPlanButton.pzstRow.visible,'reenabling restores native row')
local nc=panel()
NC_CellBaseCraft.createChildren(nc)
a,b,c=NC_CellBaseCraft.layoutChildren(nc,500,400)
check(a=='layout' and b==nil and c==5 and nc.baseHeight==370 and nc.pzstPlanButton.y==374,'NC reserves only one planning row')
-- Another toolbar wrapper (Wishlist) may be installed before or after ours.
local previous=NC_CellBaseCraft.layoutChildren
NC_CellBaseCraft.layoutChildren=function(panel,w,h) previous(panel,w,h-24);panel.wishlistY=h-20 end
NC_CellBaseCraft.layoutChildren(nc,500,400)
check(nc.pzstPlanButton.y+nc.pzstPlanButton.height<=nc.wishlistY,'toolbar wrappers compose without overlapping')
enabled=false;NC_CellBaseCraft.prerender(nc)
check(nc.baseHeight==376 and not nc.pzstPlanButton.visible,'disable restores NC space while preserving other toolbar')
check(Chains.open(p)==nil,'disabled planning opens nothing')
enabled=true
local view=Chains.open(p)
check(view.plan and view.window.managed and view.window.raised and view.window.backgroundColor.a==1 and quantity==1,
    'native fallback previews one final recipe execution in opaque window')
local steps=rows(view,'step')
check(#steps==1 and steps[1].script and steps[1].step==1,'ordered step has an item icon')
for _,entry in ipairs(view.preview.items) do check(not entry.tooltip:find('<Spoon>',1,true),'tooltip cannot inject recipe rich text') end
view.quantity.value='2';view:prerender()
check(not view.start.enable,'editing quantity invalidates displayed confirmation')
view:startPlan()
check(queued==0 and quantity==2 and view.plan.count==2 and view.window.managed,'changed quantity shows fresh preview before queueing')
check(rows(view,'output')[1].amount==2,'final output is per-recipe output times runs')
changedMaterial=true;view:startPlan()
check(queued==0 and rows(view,'notice')[1].name:find('ReviewChanged',1,true),'changed ingredients require review')
changedId=2;view:startPlan()
check(queued==0,'same-type replacement with a different identity requires review')
view:startPlan()
check(queued==1 and view.closed and not view.window.managed,'confirmed unchanged plan queues once and closes')
view=Chains.open(p)
recipe={};view:startPlan()
check(queued==1 and not view.plan,'changing selected recipe cannot queue a different target')
view=Chains.open(p)
view.quantity.value='0';view:refresh()
check(not view.plan and not view.start.enable,'invalid counts cannot plan or enqueue')
view.quantity.value='1';view:refresh()
enabled=false;view:prerender()
check(view.closed and not view.window.managed and view.quantity.unfocused,'disabling releases quantity focus and removes preview')
enabled=true;view=Chains.open(p);dead=true;view:startPlan()
check(queued==1 and not view.plan,'dead character cannot confirm an old plan')
view:close();dead=false

view=Chains.open(p)
check(ISHandCraftPanel.OnCloseWindow({logic=p.logic})=='owner-close' and view.closed and not view.window.managed,
    'closing native crafting owner releases its floating plan')

local tooltipCount=0
local slot={removeTooltip=function() tooltipCount=tooltipCount+1 end}
nc.craftInputPanel=widget();nc.craftInputPanel.inputItems={slot}
nc.recipeInfoPanel=widget()
nc.craftResultPanel=widget();nc.craftResultPanel.craftoutputPanel={outputItems={slot}}
local hand=panel();hand.cellBaseCraft=nc
hand.logic.showManual,hand.logic.inputFilter=true,{}
hand.logic.setShowManualSelectInputs=function(self,value) self.showManual=value end
hand.logic.setManualSelectInputScriptFilter=function(self,value) self.inputFilter=value end
hand.MainPanel={HandCraftPanel=hand,setJoypadFocusElement=function(self,element) self.focusCleared=element==nil end}
hand.closeInputSwitchPanel=function(self) self.inputPickerClosed=true end
hand.closeOutputSwitchPanel=function(self) self.outputPickerClosed=true end
nc.HandCraftPanel=hand
view=Chains.open(hand)
check(view.cell==nc and not view.window and nc.pzstPlanView==view,'Neat plan is a child, not a floating window')
check(not nc.craftInputPanel.visible and not nc.recipeInfoPanel.visible and not nc.craftResultPanel.visible
    and not nc.pzstPlanButton.visible,'ordinary controls hidden while plan open')
check(tooltipCount==2 and hand.inputPickerClosed and hand.outputPickerClosed,'owned tooltips and separate pickers close on entry')
check(hand.logic.showManual==false and hand.logic.inputFilter==nil,'closing picker resets native state so the next ingredient click can reopen it')
local owner={HandCraftPanel=hand}
check(hand.MainPanel.focusCleared and #NC_HandcraftWindow.getJoypadInputEntries(owner)==0
    and #NC_HandcraftWindow.getJoypadOutputEntries(owner)==0,'controller cannot refocus or activate hidden native slots')
check(view.height<=nc.wishlistY and view.start.y+view.start.height<=view.height,'plan controls fit above independent Wishlist footer')
NC_CellBaseCraft.layoutChildren(nc,290,310)
check(view.width==290 and view.height==286 and view.preview.height>0,'embedded content follows parent resize')
view.preview.tooltipUI=widget();view.preview.tooltipUI:addToUIManager()
view:close()
check(view.closed and not nc.pzstPlanView and nc.craftInputPanel.visible and nc.pzstPlanButton.visible,'Back restores recipe controls')
check(not view.preview.tooltipUI.managed and not view.preview.tooltipUI.visible,'closing removes tooltip from UIManager')
check(NC_HandcraftWindow.getJoypadInputEntries(owner)[1]==nativeInput
    and NC_HandcraftWindow.getJoypadOutputEntries(owner)[1]==nativeOutput,'native controller entries return after Back')
view=Chains.open(hand);NC_HandcraftWindow.onJoypadDown(owner,Joypad.BButton)
check(view.closed and nativeBack==0,'controller Back closes plan before its parent')
NC_HandcraftWindow.onJoypadDown(owner,Joypad.BButton)
check(nativeBack==1,'ordinary controller Back remains native')
view=Chains.open(nc);recipe={};NC_HandCraftPanel.onLogicRecipeChanged(hand)
check(view.closed and not nc.pzstPlanView,'native recipe change closes stale embedded plan')
view=Chains.open(hand);enabled=false;NC_CellBaseCraft.prerender(nc)
check(view.closed and not nc.pzstPlanButton.visible and nc.craftInputPanel.visible,'disabling restores recipe but hides planning entry')
enabled=true;NC_CellBaseCraft.prerender(nc)
view=Chains.open(hand);check(#nc.children==2,'repeated opening has only one plan child plus entry button')
NC_HandcraftWindow.close({HandCraftPanel=hand})
check(view.closed and #nc.children==1,'closing native owner releases plan child')

-- Presentation uses consumed stock, not every intermediate input; tools are reused across steps.
view=Chains.open(hand)
local toolSpec={id='cut',name='Cut',inputs={{index=0,keep=true,choices={{fullType='Knife',amount=1}}},
    {index=1,keep=true,choices={{fullType='Knife',amount=1}}}},outputs={Handle=12}}
local plan={target='spoon',count=2,consumed={Log=1},steps={
 {recipe=toolSpec,inputs={[0]={fullType='Knife',amount=1,resourceIds={41},generated=0},[1]={fullType='Knife',amount=1,resourceIds={42},generated=0}}},
 {recipe=spec,inputs={[0]={fullType='Handle',amount=2,resourceIds={},generated=2},[1]={fullType='Knife',amount=1,resourceIds={42},generated=0}}},
}}
view:showPlan(plan,{},nil)
check(#rows(view,'material')==1 and rows(view,'material')[1].fullType=='Log' and rows(view,'material')[1].amount==1,
    'intermediate handles are not counted again as materials from stock')
check(#rows(view,'tool')==1 and rows(view,'tool')[1].amount==2,'sum simultaneous tools then reuse between steps')
view.preview:setHeight(1000)
local y=0
for _,item in ipairs(view.preview.items) do y=view.preview:doDrawItem(y,item) end
check(view.preview.icons==9,'output, stock, tools, both steps and their inputs render icons')
view:close()
local entity={HandCraftPanel=hand,setJoypadFocusElement=hand.MainPanel.setJoypadFocusElement}
hand.MainPanel={parent=entity}
view=Chains.open(hand)
check(entity.focusCleared and #NC_EntityWindow.getJoypadInputEntries(entity)==0
    and #NC_EntityWindow.getJoypadOutputEntries(entity)==0,'workbench copy of controller methods has identical hidden-slot protection')
NC_EntityWindow.onJoypadDown(entity,Joypad.BButton)
check(view.closed,'workbench controller Back closes its embedded plan')
view=Chains.open(hand);NC_EntityWindow.close(entity)
check(view.closed,'workbench entity close releases its embedded plan')

changedMaterial=false
view=Chains.open(hand)
local inputRow=rows(view,'input')[1]
check(inputRow.amount==1 and inputRow.detail:find('Allocation1,1,0',1,true),'ingredient row distinguishes needed, stock and generated counts')
view.preview.onmousedown(view.preview.target,inputRow)
local menu=view.choiceMenu
check(menu.options[1].checked and #menu.options==4,'ingredient click opens Auto and every material alternative')
check(menu.options[2].name:find('Handle',1,true) and menu.options[2].iconTexture=='Handle-icon',
    'available choices sort first with native item icons')
local choosePlank=menu.options[3]
choosePlank.onSelect(choosePlank.target,choosePlank.selection)
check(menu.hidden and view.overrides.spoon[0]=='Plank' and view.plan.steps[1].inputs[0].fullType=='Plank',
    'selecting a material rebuilds the whole plan and closes the popup')
view:openChoices(rows(view,'input')[1]);menu=view.choiceMenu
check(menu.options[3].checked and not menu.options[1].checked,'selected material is checked on reopening')
view:selectInput({recipeId='spoon',inputIndex=0,fullType='Missing'})
check(not view.plan and not view.start.enable and #rows(view,'input')==2,
    'unavailable choice disables execution but retains editable ingredient rows')
view:openChoices(rows(view,'input')[1]);menu=view.choiceMenu
local auto=menu.options[1];auto.onSelect(auto.target,auto.selection)
check(view.plan and view.overrides.spoon[0]==false and rows(view,'input')[1].mode:find('Auto',1,true),
    'Auto recovers from an impossible material choice')
local originalPlan=view.plan
view:selectInput({recipeId='spoon',inputIndex=0,fullType='NotAnAlternative'})
check(view.plan==originalPlan,'unknown material cannot create an override')
local collect=Recipes.collect
local middle={id='handles',name='Handles',inputs={{index=0,choices=allChoices,allChoices=allChoices}},outputs={Handle=1}}
view.model.recipes.handles=middle
view.lastPlan.steps[#view.lastPlan.steps+1]={recipe=middle}
view.overrides.handles={[0]='Plank'}
Recipes.collect=function(panel,overrides)
    if overrides.handles then return nil,'UnsupportedSelection' end
    return collect(panel,overrides)
end
view:refresh()
check(not view.plan and #rows(view,'input')==3,'unavailable intermediate recipe retains choices for recovery')
view:selectInput({recipeId='handles',inputIndex=0,fullType=false})
check(view.plan and not view.overrides.handles,'Auto releases an unavailable intermediate recipe constraint')
Recipes.collect=collect
view:openChoices(rows(view,'input')[1]);menu=view.choiceMenu
view:close()
check(menu.hidden and not view.model and not view.overrides,'closing releases menus, choices and inventory snapshots')
menu.options[3].onSelect(view,menu.options[3].selection)
check(view.closed and not view.plan,'old popup callback cannot change a closed plan')
for _, name in ipairs({'OnMainMenuEnter','OnGameExit','OnPlayerDeath'}) do
    view=Chains.open(hand)
    view:openChoices(rows(view,'input')[1]);menu=view.choiceMenu
    resets[name](name=='OnPlayerDeath' and player or nil)
    check(view.closed and menu.hidden and not nc.pzstPlanView and not view.model and not view.context,
        'shutdown releases registered views, menus and inventory snapshots')
    local reopened=Chains.open(hand)
    check(reopened~=view and not reopened.closed and #nc.children==2,'shutdown permits a fresh bound plan view')
    reopened:close()
end
print('Craft-chain UI: '..checks..' checks passed (icons, accounting, embedding, changes, layout and lifecycle).')
