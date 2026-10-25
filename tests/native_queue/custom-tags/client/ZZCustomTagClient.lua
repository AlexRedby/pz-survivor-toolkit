local config=require 'QueueTestSelection'
if config.suite~='custom-tags'then return end
local F=require 'CustomTagFixture'
local C=require 'PZSurvivorToolkit/TagCustomization'
local Client=require 'PZSurvivorToolkit/TagCustomizationClient'
local Tags=require 'PZSurvivorToolkit/ItemTags'
local Catalog=require 'PZSurvivorToolkit/TagEditor'
local Assignment=require 'PZSurvivorToolkit/ItemTagEditor'
local Rules=require 'PZSurvivorToolkit/QuartermasterTagRules'
local Visuals=require 'PZSurvivorToolkit/TagVisuals'
local JSON=require 'QueueHealthEvents'
local started,done,requested,placed,role,state,packet,phase,action,verify,observed,finished
local startedAt,conflictReady,handshakeAt,reloadShot
local function emit(event,data)print('[CUSTOM_TAG_TEST] '..event..' '..JSON.encode(data))end
local function send(command,args)sendClientCommand(F.module,command,args or {})end
local function click(button)assert(button and button.onclick,'Native button callback missing');return button.onclick(button.target,button)end
local function find(menu,key)
 for _,option in ipairs(menu.options or {})do
  if option.pzstKey==key then return option end
  if option.subOption then local sub=menu:getSubMenu(option.subOption);local got=sub and find(sub,key);if got then return got end end
 end
end
local function openFromMenu(key,items)
 local pane=getPlayerLoot(0).inventoryPane
 local menu=assert(ISInventoryPaneContextMenu.createMenu(0,false,items,150,150,pane),'Native item context menu missing')
 local option=assert(find(menu,key),'Custom-tag menu option missing '..key)
 assert(not option.notAvailable,'Custom-tag menu option unavailable')
 local window=assert(option.onSelect(option.target,option.param1,option.param2,option.param3),'Editor callback did not return native window')
 menu:hideAndChildren();return window
end
local function choose(window,id,target)
 for attempt=1,4 do
  if window:state(id)==target then return end
  window:cycle({id=id})
 end
 error('Assignment state did not reach '..target)
end
local function catalog(new,id,name)
 local window=openFromMenu('manageTags',{F.item(state,1)})
 if new then window:newTag()else window:select({id=id})end
 if name then window.nameEntry:setText(name)end
 return window
end
local function assignment(index,scope,id,operation,reset)
 local window=openFromMenu('editItemTags',{F.item(state,index)})
 if scope=='type'then window.scopeCombo.selected=2;window:changeScope()end
 if reset then click(window.resetButton)end
 if id then choose(window,id,operation)end
 return window
end
local function beginAction()
 local window,ownerWindow
 if phase=='Create'or phase=='RetiredCreate'then
  if phase=='Create'then
   ownerWindow=openFromMenu('editItemTags',{F.item(state,1)})
   window=assert(click(ownerWindow.catalogButton),'Nested native tag catalog did not open')
   window:newTag();window.nameEntry:setText(F.text('Main'))
  else window=catalog(true,nil,F.text('Retired'))end
  window.fixtureColor={r=.2,g=.4,b=.6};window.fixtureIcon='Item_Axe'
 elseif phase=='Builtin'then
  window=catalog(false,'tool',F.text('Builtin'))
  window.fixtureColor={r=.4,g=.8,b=.2};window.fixtureIcon='Item_Hammer'
 elseif phase=='TypeAdd'or phase=='TypeFinal'then window=assignment(1,'type',packet.tag,'add')
 elseif phase=='ItemRemove'or phase=='ItemFinal'then window=assignment(1,'item',packet.tag,'remove')
 elseif phase=='ItemDefault'then window=assignment(1,'item',packet.tag,'default')
 elseif phase=='ItemAdd'then window=assignment(4,'item',packet.tag,'add')
 elseif phase=='ItemReset'then window=assignment(4,'item',nil,nil,true)
 elseif phase=='TypeRemove'then window=assignment(1,'type','tool','remove')
 elseif phase=='TypeReset'then window=assignment(1,'type',nil,nil,true)
 elseif phase=='RetiredAssign'then window=assignment(4,'item',packet.retired,'add')
 elseif phase=='RetiredDelete'then
  window=catalog(false,packet.retired)
  click(window.deleteButton);local modal=assert(window.confirmation,'Native delete confirmation missing')
  click(modal.yes);assert(window.draft.deleted,'Delete confirmation did not update draft')
 elseif phase=='Cancel'then
  window=catalog(true,nil,F.text('Cancel'));click(window.cancelButton)
  assert(window.toolkitTagClosed,'Native catalog Cancel did not close')
  window=assignment(4,'item',packet.tag,'add');click(window.cancelButton)
  assert(window.toolkitTagClosed,'Native assignment Cancel did not close')
  send('Done',{phase=phase});action={complete=true};return
 elseif phase=='Conflict'then
  window=assignment(4,'item',packet.tag,'add')
  send('OpenConflict',{});action={window=window,waitConflict=true};return
 else error('Unknown action phase '..tostring(phase))end
 action={window=window,ownerWindow=ownerWindow,saveAt=getTimestampMs()+450}
 if window.fixtureColor then
  click(window.colorButton);assert(window.toolkitColorPicker,'Native color picker failed to open')
  action.pickerStage='color';action.pickerAt=getTimestampMs()+450;action.saveAt=nil
 end
end
local function consumers()
 local rule=assert(Tags.normalizeRule({mode='all',include={packet.tag},exclude={}}))
 local one,two,hammer=F.item(state,1),F.item(state,2),F.item(state,4)
 assert(not Rules.matches({cats={},rules={rule}},{ref=one,cat=one:getDisplayCategory()}),'Quartermaster accepted excluded exact instance')
 assert(Rules.matches({cats={},rules={rule}},{ref=two,cat=two:getDisplayCategory()}),'Quartermaster lost type assignment')
 local retired=assert(Tags.normalizeRule({mode='all',include={packet.retired},exclude={}}))
 assert(not Rules.matches({cats={},rules={retired}},{ref=hammer,cat=hammer:getDisplayCategory()}),'Retired include widened Quartermaster')
 local pane=getPlayerLoot(0).inventoryPane
 pane.toolkitCategory,pane.toolkitTag=nil,nil;pane.toolkitTagRule=rule;pane:refreshContainer();pane:prerender()
 assert(pane.toolkitVisibleItems and pane.toolkitVisibleItems[two]and not pane.toolkitVisibleItems[one]
  and not pane.toolkitVisibleItems[hammer],'Native inventory filter did not follow effective exact/type tags')
 pane.toolkitTagRule=retired;pane:refreshContainer();pane:prerender()
 for item in pairs(pane.toolkitVisibleItems or {})do error('Retired include widened native filter '..item:getID())end
 pane.toolkitTagRule=nil;pane:refreshContainer()
 local visual=Visuals.get('tool')
 assert(visual.icon=='Item_Hammer'and math.abs(visual.r-.4)<.00001 and Tags.label('tool')==F.text('Shared'),'Shared built-in label/color/icon not rendered')
 emit('CONSUMERS',{role=role,filter=true,quartermaster=true,retiredInclude=false})
end
Events.OnServerCommand.Add(function(module,command,args)
 if module==C.MODULE and command=='Result'then
  emit('RESULT',{role=role or 'unknown',status=args.status,reason=args.reason or '',request=args.request,revision=args.revision})
 end
 if module~=F.module then return end
 if command=='Prepared'then packet=args.packet;role=args.role
 elseif command=='Action'then phase=args.phase;packet=args.packet;action=nil;verify=nil;observed=nil
 elseif command=='Verify'then verify=args;packet=args.packet
 elseif command=='Bump'then
  Client.edit(0,'tool',{name=F.text('Shared')},function(status)send('BumpDone',{status=status})end)
 elseif command=='ConflictSave'then conflictReady=true
 elseif command=='Finish'then packet=args.packet;finished=true end
end)
Events.OnGameStart.Add(function()
 started=true;startedAt=getTimestampMs();getPlayer():setGodMod(true);getPlayer():setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
 if getPlayerInfoPanel and getPlayerInfoPanel(0)then getPlayerInfoPanel(0):setVisible(false)end
end)
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,err=pcall(function()
  if not requested then requested=true;send('Prepare',{});return end
  if not packet then return end
  if not state then
   local player=getPlayer()
   if not placed then
    player:teleportTo(math.floor(packet.x),math.floor(packet.y),0)
    player:setX(packet.x);player:setY(packet.y);player:setNextX(packet.x);player:setNextY(packet.y)
    player:setLastX(packet.x);player:setLastY(packet.y);placed=true
   end
   state=C.synced()and F.resolve(packet)or nil
   if not state or not C.synced()then
    if not handshakeAt or getTimestampMs()-handshakeAt>5000 then
     handshakeAt=getTimestampMs()
     local vehicle=getVehicleById(packet.truckId)
     local part=vehicle and vehicle:getPartById('TruckBed')
     local container=part and part:getItemContainer()
     local matching=0
     if container then for _,id in ipairs(packet.ids)do if container:getItemById(id)then matching=matching+1 end end end
     emit('HANDSHAKE',{role=role,synced=C.synced(),vehicle=vehicle~=nil,
      count=container and container:getItems():size()or -1,matching=matching,revision=C.getRevision()})
    end
    state=nil;return
   end
   assert(Tags.enabled(),'Native tag setting disabled')
   local loot=getPlayerLoot(0);loot:refreshBackpacks();loot:setForceSelectedContainer(state.container)
   for index,page in ipairs({getPlayerInventory(0),loot})do
    page:setVisible(true);page.isCollapsed=false;page:setPinned();page:setX(index==1 and 25 or 805);page:setY(50)
    page:setWidth(750);page:setHeight(500);page:setMaxDrawHeight(500);page.inventoryPane:setVisible(true)
   end
   emit('READY',{role=role,revision=C.getRevision(),synced=C.synced(),count=state.container:getItems():size()});send('Ready',{});return
  end
  state.packet=packet
  if finished then
   if not F.check('Reload',state)then return end
   if config.cases[1]=='reload'and role=='client2'and not (reloadShot and reloadShot.complete)then
    if not reloadShot then
     local owner=openFromMenu('editItemTags',{F.item(state,1)})
     owner.search:setText(F.text('Main'));owner:reloadList()
     local window=assert(click(owner.catalogButton),'Reload nested catalog did not open')
     window:select({id='tool'});window.search:setText(F.text('Shared'));window:reloadList()
     reloadShot={owner=owner,window=window,at=getTimestampMs()+650,stage='catalog'}
    elseif getTimestampMs()>=reloadShot.at then
     if reloadShot.stage=='catalog'then
      getCore():TakeFullScreenshot('custom-tags-reload-ru-catalog.png');reloadShot.window:close()
      reloadShot.stage='assignment';reloadShot.at=getTimestampMs()+650
     else
      getCore():TakeFullScreenshot('custom-tags-reload-ru-assignment.png');reloadShot.owner:close()
      reloadShot.complete=true
     end
    end
    return
   end
   consumers()
   if config.cases[1]=='edit'and role=='client1'then emit('UI',{catalog=true,assignment=true,cancel=true,conflict=true,color=true,icon=true})end
   emit(config.cases[1]=='reload'and 'PERSISTED'or 'VERIFIED',F.receipt(role,state))
   emit('COMPLETE',{case=config.cases[1],role=role});done=true;return
  end
  if verify and observed~=verify.phase and C.getRevision()>=verify.revision then
   if not F.check(verify.phase,state)then return end
   emit('CHECK',{role=role,phase=verify.phase,passed=true,revision=C.getRevision()})
   observed=verify.phase;send('Observed',{phase=verify.phase});return
  end
  if role=='client1'and phase and not verify then
   if not action then beginAction();return end
   if action.complete then return end
   local window=action.window
   if action.waitConflict then
    if not conflictReady then return end
    action.waitConflict=false;action.saveAt=getTimestampMs()+450
   end
   if action.pickerStage and getTimestampMs()>=action.pickerAt then
    if action.pickerStage=='color'then
     local picker=assert(window.toolkitColorPicker)
     if phase=='Create'then getCore():TakeFullScreenshot('custom-tags-color.png')end
     local color=window.fixtureColor
     picker:setInitialColor(ColorInfo.new(color.r,color.g,color.b,1));picker:picked(true)
     assert(window.draft.colorTouched,'Native color callback did not update draft')
     click(window.iconButton);assert(window.toolkitIconPicker,'Native icon selector failed to open')
     action.pickerStage='icon';action.pickerAt=getTimestampMs()+450
    else
     local picker=assert(window.toolkitIconPicker)
     local selected
     for index,row in ipairs(picker.list.items)do if row.item.icon==window.fixtureIcon then selected=index;break end end
     assert(selected,'Requested real icon absent from native selector')
     picker.list.selected=selected;picker.list:ensureVisible(selected)
     if phase=='Create'then getCore():TakeFullScreenshot('custom-tags-icon.png')end
     click(picker.selectButton)
     assert(window.draft.iconTouched and window.draft.icon==window.fixtureIcon,'Native icon callback did not update draft')
     action.pickerStage=nil;action.saveAt=getTimestampMs()+450
    end
    return
   end
   if action.saveAt and getTimestampMs()>=action.saveAt then
    if phase=='Create'and not action.createAssigned then getCore():TakeFullScreenshot('custom-tags-catalog.png')end
    if phase=='TypeAdd'then getCore():TakeFullScreenshot('custom-tags-assignment.png')end
    if window.nameEntry and (phase=='Create'or phase=='Builtin'or phase=='RetiredCreate')then
     local name=window.nameEntry:getInternalText()
     if phase=='Create'then assert(#name==5 and string.byte(name,1)==1055,'Native Unicode input lost Cyrillic code units')end
     local definition={name=name,color=window.draft.color,icon=window.draft.icon}
     local valid,reason=C.normalizeDefinition(definition,true)
     emit('SAVE',{phase=phase,normalized=valid~=nil,reason=reason or '',length=#name,first=string.byte(name,1)})
    end
    click(window.saveButton);action.saveAt=nil;action.saved=true;return
   end
   if action.saved and not window.pending then
    if phase=='Conflict'then
     assert(not window.toolkitTagClosed and window.status==getText('UI_PZST_TagEdit_Conflict'),'Stale assignment draft was not retained as conflict')
     assert(window:state(packet.tag)=='add','Conflict lost assignment draft')
     getCore():TakeFullScreenshot('custom-tags-conflict.png')
    elseif phase=='Create'then
     if not action.createAssigned then
      local created=window.selectedId;assert(C.customId(created)and C.definition(created).name==F.text('Main'),'Native catalog Save failed')
      packet.tag=created;window:close()
      local owner=assert(action.ownerWindow,'Nested assignment owner disappeared')
      assert(owner.baseRevision==C.getRevision(),'Own catalog acceptance did not safely rebase parent assignment')
      choose(owner,created,'add')
      action.window,action.ownerWindow=owner,nil
      action.createAssigned=true;action.saved=false;action.saveAt=getTimestampMs()+450
      return
     else
      assert(window.toolkitTagClosed and C.itemDelta(F.item(state,1))[packet.tag]=='add',
       'Same original assignment window could not save its newly created tag')
     end
    elseif phase=='RetiredCreate'then
     local created=window.selectedId;assert(C.customId(created)and C.definition(created).name==F.text('Retired'),'Second custom creation failed')
     packet.retired=created
    elseif phase=='Builtin'then assert(C.definition('tool').name==F.text('Builtin'),'Built-in native Save failed')
    elseif phase=='RetiredDelete'then assert(not C.isActive(packet.retired),'Native custom deletion failed')
    else assert(window.toolkitTagClosed,'Native assignment Save did not close after acceptance')end
    window:close();if action.ownerWindow then action.ownerWindow:close()end;action.complete=true
    send('Done',{phase=phase,tag=phase=='Create'and packet.tag or nil,retired=phase=='RetiredCreate'and packet.retired or nil})
   end
  end
  assert(getTimestampMs()-startedAt<800000,'Custom-tag client lifecycle timeout')
 end)
 if not ok then done=true;emit('FAIL',{role=role or 'unknown',error=tostring(err)})end
end)
