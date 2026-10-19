local selection=require 'QueueTestSelection'
local F=require 'ContainerConfigurationFixture'
local Controls=require 'PZSurvivorToolkit/ContainerAppearanceControls'
local Menus=require 'PZSurvivorToolkit/ContainerConfigurationMenus'
local JSON=require 'QueueHealthEvents'
local started,done,since,nextAt,phase=false,false,0,0,'prepare'
local packet,obj,picker,role,go,observe,finished,localReceipt
local menuClasses=0
local function emit(event,value) print('[CONTAINER_CONFIG] '..event..' '..JSON.encode(value))end
local function close()if LootSorter._picker then LootSorter._picker:closePicker()end end
local function shot(name)
 getCore():TakeFullScreenshot('container-config-'..name..'.png')
 emit('SHOT',{name=name,role=role})
end
local function checkControls()
 assert(picker.appearanceName and picker.appearanceIcon and picker.appearanceColor and picker.appearanceReset,'Unified appearance fields absent')
 assert(picker.listbox and picker.btnSave and picker.toolkitTagRuleButton,'Sorting fields absent')
 assert(picker.appearanceName:getInternalText()==F.legacy,'Legacy BC name missing')
 assert(picker.toolkitAppearance.icon.value=='Base.Screwdriver','Legacy BC icon missing')
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
  if not F.legacyRead(obj,player)then return end
  if isClient()then sendClientCommand(F.module,'Ready',{})end
  phase=role=='client1' and 'start' or 'observe'
 elseif phase=='start'then
  if not go then return end
  print('[CONTAINER_CONFIG_DIAG] editing local='..tostring(player:getUsername())..' specific='..tostring(getSpecificPlayer(0):getUsername())..' role='..tostring(role))
  probeMenus()
  LootSorter.openPicker(obj,0,0);picker=assert(LootSorter._picker);checkControls()
  emit('LEGACY',{name=F.legacy,role=role,menuClasses=menuClasses})
  picker.appearanceName:setText(F.name)
  Controls.chooseIcon(picker)
  assert(picker.toolkitIconPicker and #picker.toolkitIconPicker.list.items>0,'Real icon chooser absent/empty')
  phase='icon';nextAt=getTimestampMs()+1200
 elseif phase=='icon'then
  shot('icon')
  local chooser=assert(picker.toolkitIconPicker);local selected
  for i,row in ipairs(chooser.list.items)do
   local icon=row.item.icon
   if icon.kind=='container' and icon.value=='crate' then selected=i end
  end
  assert(selected,'Crate absent from real BC catalogue')
  chooser.list.selected=selected;chooser:choose()
  assert(not picker.toolkitIconPicker and picker.toolkitAppearance.icon.value=='crate','Real icon callback did not commit draft')
  Controls.chooseColor(picker)
  local popup=assert(picker.toolkitColorPicker)
  popup.pickedRGB={r=F.color.r,g=F.color.g,b=F.color.b}
  popup:onSave()
  assert(picker.toolkitAppearance.color and picker.toolkitAppearance.color.r==F.color.r,'Native color Save did not commit draft')
  picker.selectedCats={[packet.category]=true};picker.selectedItems={};picker.selectedPresets={};picker.selection=picker.selectedCats;picker:setPriority(6)
  picker.toolkitTagRule={mode='all',include={'food','perishable'},exclude={'meat'}}
  picker.toolkitTagRuleTouched=true
  picker.needRebuild=true
  phase='edit';nextAt=getTimestampMs()+1200
 elseif phase=='edit'then
  shot('edit')
  picker.btnSave.onclick(picker)
  emit('SAVE',{count=1,role=role})
  phase='saved'
 elseif phase=='saved'then
  if LootSorter._picker==picker then return end
  localReceipt=F.receipt(obj,player,packet.category)
  if not F.matches(localReceipt)then return end
  LootSorter.openPicker(obj,0,0);picker=assert(LootSorter._picker)
  assert(picker.appearanceName:getInternalText()==F.name and picker.selectedCats[packet.category]
   and picker.toolkitAppearance.icon.value=='crate' and picker.toolkitAppearance.color.r==F.color.r
   and picker.priority==6 and picker.toolkitTagRule.include[2]=='perishable','Reopen lost unified fields')
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
   and picker.toolkitAppearance.icon.value=='crate' and picker.toolkitAppearance.color.b==F.color.b,'Observer editor differs')
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
