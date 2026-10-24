local selection=require 'QueueTestSelection'
local F=require 'ContainerConfigurationFixture'
local Controls=require 'PZSurvivorToolkit/ContainerAppearanceControls'
local Menus=require 'PZSurvivorToolkit/ContainerConfigurationMenus'
local Tags=require 'PZSurvivorToolkit/ItemTags'
local Visuals=require 'PZSurvivorToolkit/TagVisuals'
local Helpers=require 'BetterContainers/Helpers'
local JSON=require 'QueueHealthEvents'
local started,done,since,nextAt,phase=false,false,0,0,'prepare'
local packet,obj,picker,role,go,observe,finished,localReceipt
local menuClasses=0
local function emit(event,value) print('[CONTAINER_CONFIG] '..event..' '..JSON.encode(value))end
local function close()if LootSorter._picker then LootSorter._picker:closePicker()end end
local function shot(name)
 local list=assert(picker.listbox);local scroll=assert(list.vscroll)
 assert(scroll:getX()==list:getWidth()-16 and scroll:getY()==0
  and scroll:getHeight()==list:getHeight(),'Native scrollbar frame differs from list: '..name)
 getCore():TakeFullScreenshot('container-config-'..name..'.png')
 emit('SHOT',{name=name,role=role,width=picker:getWidth(),height=picker:getHeight()})
end
local function checkControls()
 assert(picker.appearanceName and picker.appearanceIcon and picker.appearanceColor and picker.appearanceReset,'Unified appearance fields absent')
 assert(picker.listbox and picker.btnSave and picker.toolkitTagRuleButton,'Sorting fields absent')
 assert(picker.appearanceName:getInternalText()=='' and not picker.toolkitAppearance.icon
  and not picker.toolkitAppearance.color,'New fixture did not start with blank appearance')
end
local function sameColor(color,style)
 return color and color.r==style.r and color.g==style.g and color.b==style.b
end
local function clickRow(key,tag)
 picker:rebuild()
 for _,row in ipairs(picker.listbox.items)do
  if tag and row.item.tag==tag or key and row.item.key==key then
   assert(not row.item.requiresRule,'Fixture tag unexpectedly requires a rule')
   picker.listbox.onmousedown(picker,row.item);return
  end
 end
 error('Actual sorting row missing: '..tostring(tag or key))
end
local function pickColor()
 Controls.chooseColor(picker)
 local popup=assert(picker.toolkitColorPicker)
 popup.pickedRGB={r=F.color.r,g=F.color.g,b=F.color.b};popup:onSave()
 assert(sameColor(picker.toolkitAppearance.color,F.color),'Native color Save did not commit draft')
end
local function checkTagIcon()
 local icon=picker.toolkitAppearance.icon
 assert(icon and icon.kind=='pzst-tag' and icon.value==F.tag,'Tag icon descriptor missing')
 local texture=assert(Visuals.get(F.tag).texture,'Real tag texture missing')
 assert(Helpers.getIconTexture(icon)==texture,'BC helper did not resolve persisted tag icon')
end
local function probeMenus()
 local page=assert(getPlayerLoot(0));page:refreshBackpacks()
 local button
 for _,candidate in ipairs(page.backpacks or {})do
  if candidate.inventory==obj:getContainerByIndex(0)then button=candidate end
 end
 assert(button,'Actual world container button missing')
 Menus.install()
 local seen={}
 for _,class in pairs({ISInventoryPage,CleanUI_Clean_ISInventoryPage,CleanUI_Vanilla_ISInventoryPage})do
  if not seen[class] then
   seen[class]=true;local old=button.mouseOver;button.mouseOver=true
   class.onBackpackRightMouseDown(button,0,0);button.mouseOver=old
   local menu=assert(getPlayerContextMenu(0));local found,n=nil,0
   for _,option in ipairs(menu.options)do
    if option.onSelect==LootSorter.onConfigureContainer then found=option;n=n+1 end
    for _,other in pairs({ISInventoryPage,CleanUI_Clean_ISInventoryPage,CleanUI_Vanilla_ISInventoryPage})do
     assert(option.onSelect~=other.onRenameContainer,'Duplicate native rename remains')
    end
   end
   assert(n==1 and found.target==obj and found.param1==0,'Unified container action missing/duplicated')
   found.onSelect(found.target,found.param1,found.param2)
   assert(LootSorter._picker and LootSorter._picker.targetObj==obj,'Button route opened wrong editor')
   close();menu:closeAll();menuClasses=menuClasses+1
  end
 end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~=F.module then return end
 if command=='Prepared'then packet=args.target;role=args.role elseif command=='Start'then go=true
 elseif command=='Observe'then observe=true elseif command=='Done'then finished=true end
end)
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();local player=getPlayer()
 player:setGodMod(true);player:setGhostMode(true)
 if selection.kind=='sp' then role='client1' end
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
local function tick()
 local player=getPlayer()
 if phase=='prepare'then
  if isClient() then sendClientCommand(F.module,'Prepare',{})else obj,packet=F.prepare(player);emit('PREPARED',packet);go=true end
  phase='resolve'
 elseif phase=='resolve'then
  if not packet then return end
  -- Both native clients use the common disposable startup spawn. Move only this test actor near the owned crate.
  if math.abs(player:getX()-packet.x)>3 or math.abs(player:getY()-packet.y)>3 then
   player:teleportTo(packet.x+1.5,packet.y+0.5,packet.z);return
  end
  obj=obj or F.resolve(packet);if not obj then return end
  if not F.blankRead(obj,player)then return end
  if isClient()then sendClientCommand(F.module,'Ready',{})end
  phase=role=='client1' and 'start' or 'observe'
 elseif phase=='start'then
  if not go then return end
  print('[CONTAINER_CONFIG_DIAG] editing local='..tostring(player:getUsername())..' specific='..tostring(getSpecificPlayer(0):getUsername())..' role='..tostring(role))
  probeMenus()
  LootSorter.openPicker(obj,0,0);picker=assert(LootSorter._picker);checkControls()
  phase='empty';nextAt=getTimestampMs()+1200
 elseif phase=='empty'then
  shot('empty')
  picker.filter:setText(Tags.label(F.tag))
  phase='search';nextAt=getTimestampMs()+1200
 elseif phase=='search'then
  assert(picker.listbox.count>0,'Known tag search returned no rows')
  shot('search')
  picker.filter:setText('pzst-no-matching-entry-20261024')
  phase='no-results';nextAt=getTimestampMs()+1200
 elseif phase=='no-results'then
  assert(picker.listbox.count==0,'Unmatched search kept rows')
  assert(picker.emptyListKey=='NoMatches','Empty search guidance absent')
  shot('no-results')
  picker.filter:setText('');picker.onlyChecked=true;picker.needRebuild=true
  phase='checked';nextAt=getTimestampMs()+1200
 elseif phase=='checked'then
  assert(picker.listbox.count==0,'Blank selection acquired checked rows')
  assert(picker.emptyListKey=='NoSelected','Empty selection guidance absent')
  shot('checked')
  picker.onlyChecked=false;picker.needRebuild=true;picker:setMode('items')
  phase='items';nextAt=getTimestampMs()+1200
 elseif phase=='items'then
  shot('items')
  picker:setMode('presets')
  phase='presets';nextAt=getTimestampMs()+1200
 elseif phase=='presets'then
  if picker.listbox.count==0 then
   assert(picker.emptyListKey=='NoPresets','Empty preset guidance absent')
  end
  shot('presets')
  picker:setMode('cats');picker:onTagRule()
  phase='rule';nextAt=getTimestampMs()+1200
 elseif phase=='rule'then
  assert(picker.toolkitRulePicker,'Tag rule editor absent')
  shot('rule')
  picker.toolkitRulePicker:close();Controls.chooseColor(picker)
  phase='color';nextAt=getTimestampMs()+1200
 elseif phase=='color'then
  assert(picker.toolkitColorPicker,'Native color picker absent')
  shot('color')
  picker.toolkitColorPicker:removeSelf();picker.toolkitColorPicker=nil
  phase='choose-item'
 elseif phase=='choose-item'then
  picker:setMode('items')
  local script=assert(getScriptManager():FindItem(F.item))
  clickRow(script:getDisplayName())
  local itemType=assert(LootSorter.getItemFullType(script:getDisplayName()))
  local primary=assert(Tags.forScriptItem(assert(getScriptManager():FindItem(itemType)))[1],'Exact item primary tag missing')
  assert(picker.appearanceName:getInternalText()=='' and picker.toolkitAppearance.icon.kind=='item'
   and picker.toolkitAppearance.icon.value==itemType
   and sameColor(picker.toolkitAppearance.color,Visuals.get(primary)),'Exact item defaults differ')
  Controls.chooseIcon(picker)
  assert(picker.toolkitIconPicker and #picker.toolkitIconPicker.list.items>0,'Real icon chooser absent/empty')
  phase='icon';nextAt=getTimestampMs()+1200
 elseif phase=='icon'then
  shot('icon')
  local chooser=assert(picker.toolkitIconPicker);local selected
  local crateTexture=assert(Helpers.getIconTexture({kind='container',value='crate'}))
  for i,row in ipairs(chooser.list.items)do
   if row.item.texture==crateTexture then selected=i end
  end
  assert(selected,'Crate image absent from real BC catalogue')
  local chosen=chooser.list.items[selected].item.icon
  chooser.list.selected=selected;chooser:choose()
  local committed=picker.toolkitAppearance.icon
  assert(not picker.toolkitIconPicker and committed.kind==chosen.kind and committed.value==chosen.value
   and Helpers.getIconTexture(committed)==crateTexture,'Real icon callback did not commit draft')
  picker.appearanceName:setText('Cancelled item draft');pickColor()
  picker:closePicker();assert(F.blankRead(obj,player),'Item draft Cancel persisted appearance')
  LootSorter.openPicker(obj,0,0);picker=assert(LootSorter._picker);checkControls()
  clickRow(nil,F.tag)
  assert(picker.appearanceName:getInternalText()==Tags.label(F.tag)
   and sameColor(picker.toolkitAppearance.color,Visuals.get(F.tag)),'First tag did not seed label/color')
  checkTagIcon()
  clickRow(nil,'medical')
  assert(picker.appearanceName:getInternalText()==Tags.label(F.tag)
   and sameColor(picker.toolkitAppearance.color,Visuals.get(F.tag)),'Second tag changed initial defaults')
  checkTagIcon()
  picker.appearanceName:setText(F.name);pickColor()
  assert(picker.appearanceName:getInternalText()==F.name,'Manual name override missing')
  emit('DEFAULTS',{tag=F.tag,item=F.item,role=role,menuClasses=menuClasses})
  picker.selectedCats={[packet.category]=true};picker.selectedItems={};picker.selectedPresets={};picker.selection=picker.selectedCats;picker:setPriority(6)
  picker.toolkitTagRule={mode='all',include={'food','perishable'},exclude={'meat'}}
  picker.toolkitTagRuleTouched=true
  picker.needRebuild=true
  phase='edit';nextAt=getTimestampMs()+1200
 elseif phase=='edit'then
  shot('edit')
  picker:setWidth(420);picker:setHeight(600);picker:layout()
  phase='minimum';nextAt=getTimestampMs()+1200
 elseif phase=='minimum'then
  assert(picker:getWidth()==420 and picker:getHeight()==600,'Minimum editor size differs')
  shot('minimum')
  picker:setWidth(480);picker:setHeight(700);picker:layout()
  picker.btnSave.onclick(picker)
  emit('SAVE',{count=1,role=role})
  phase='saved'
 elseif phase=='saved'then
  if LootSorter._picker==picker then return end
  localReceipt=F.receipt(obj,player,packet.category)
  if not F.matches(localReceipt)then return end
  LootSorter.openPicker(obj,0,0);picker=assert(LootSorter._picker)
  assert(picker.appearanceName:getInternalText()==F.name and picker.selectedCats[packet.category]
   and picker.toolkitAppearance.icon.value==F.tag and picker.toolkitAppearance.color.r==F.color.r
   and picker.priority==6 and picker.toolkitTagRule.include[2]=='perishable','Reopen lost unified fields')
  checkTagIcon()
  picker.appearanceName:setText('Cancelled draft');picker:setPriority(99);picker.selectedCats={}
  picker.toolkitAppearance={};picker.toolkitAppearanceTouched=true;picker:closePicker()
  localReceipt=F.receipt(obj,player,packet.category);assert(F.matches(localReceipt),'Cancel changed stored fields')
  emit('LOCAL',localReceipt)
  if isClient()then sendClientCommand(F.module,'Verify',{})else
   emit('AUTHORITY',localReceipt);F.cleanup(obj);finished=true
  end
  phase='finish'
 elseif phase=='observe'then
  if not observe then return end
  local result=F.receipt(obj,player,packet.category);if not F.matches(result)then return end
  LootSorter.openPicker(obj,0,0);picker=assert(LootSorter._picker)
  assert(picker.appearanceName:getInternalText()==F.name and picker.selectedCats[packet.category]
   and picker.toolkitAppearance.icon.value==F.tag and picker.toolkitAppearance.color.b==F.color.b,'Observer editor differs')
  checkTagIcon()
  phase='observer-shot';nextAt=getTimestampMs()+1200
 elseif phase=='observer-shot'then
  shot('observer')
  local result=F.receipt(obj,player,packet.category);assert(F.matches(result),'Observer fields changed')
  close();emit('OBSERVER',result);sendClientCommand(F.module,'Observed',{});phase='finish'
 elseif phase=='finish'and finished then
  emit('COMPLETE',{case='edit',role=role});done=true
 end
end
Events.OnTick.Add(function()
 if not started or done or not isIngameState() or getTimestampMs()<nextAt then return end
 local ok,err=pcall(function()assert(getTimestampMs()-since<180000,'Timeout phase='..phase);tick()end)
 if not ok then done=true;print('[CONTAINER_CONFIG] FAIL '..tostring(role)..' '..tostring(err))end
end)
