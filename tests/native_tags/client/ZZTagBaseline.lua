local config=require 'QueueTestSelection'
local json=require 'TagTestEvents'
local Fixture=require 'TagFixture'
local read=assert(getFileReader('smoke-user.txt',false));local user=read:readLine();read:close()
local read=assert(getFileReader('queue-health-language.txt',false));local language=read:readLine();read:close()
PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(true)
local connected,advanced,started,done=false,false,false,false
local setup,box,picker,source,pane,rulePicker,peer,serverFailure,manualCaptured,batteryCategory,manualCategoryAck
local verified,ruleVerified,staleReply={}, {}, nil
local step,since,lastReady,lastPeer=1,0,0,0
local placement,lastPlacementAck=nil,0
local steps,passed={},{}
local Tags,Rules,presetDialog
local lastSortWait=0
local localReceipts={}
local providerConfigured=false
local bagWearQueued=false
local resuming,awaitingReconnect=false,false
local RECONNECT_FILE='tag-fixture-reconnect.txt'
local RECONNECT_CASE=config.tagRules and 'rule-reconnect' or 'baseline-reconnect'
local PRESET_NAME='Toolkit food '..user
local function reconnectFlag()
 local reader=getFileReader(RECONNECT_FILE,false);if not reader then return end
 local value=reader:readLine();reader:close();return value
end
local function writeReconnect(value)
 local writer=assert(getFileWriter(RECONNECT_FILE,true,false),'reconnect flag writer unavailable')
 writer:write(value);writer:close()
end
local function emit(event)
 event.suite='tags';event.kind='mp';event.mode='toolkit';event.actor=user;json.emit(event)
end
local function pass(id)
 assert(not passed[id],'duplicate case '..id);passed[id]=true
 emit({event='case',id=id,status='passed'});print('[TAG_TEST] PASS '..user..' '..id)
end
local function add(fn) steps[#steps+1]=fn end
local function shot(name) getCore():TakeFullScreenshot('tag-'..user..'-'..language..'-'..name..'.png') end
local function idle()
 local player=getPlayer()
 return not player:hasTimedActions() and #ISTimedActionQueue.getTimedActionQueue(player).queue==0
end
local function rowsContain(id)
 for _,group in ipairs(pane.itemslist) do
  for _,item in ipairs(group.items or {}) do if item:getID()==id then return true end end
 end
 return false
end
local function filterTrace(case,phase)
 local owned={}
 for _,key in ipairs({'battery','apple','beans','steak'}) do if setup[key] then owned[setup[key]]=true end end
 local function groups(rows)
  local result={}
  for _,group in pairs(rows or {}) do
   local ids,seen={},{}
   for _,item in ipairs(group.items or {}) do
    local id=item:getID()
    if owned[id] and not seen[id] then ids[#ids+1]=id;seen[id]=true end
   end
   if #ids>0 then
    table.sort(ids);result[#result+1]={cat=group.cat,ids=ids,matchesSearch=group.matchesSearch==nil and 'absent' or group.matchesSearch}
   end
  end
  return result
 end
 local owner=rulePicker.owner
 local containing=owner and owner.inventory and owner.inventory:getContainingItem()
 local visible,seen={},{}
 for _,group in ipairs(groups(pane.itemslist)) do
  for _,id in ipairs(group.ids) do if not seen[id] then visible[#visible+1]=id;seen[id]=true end end
 end
 table.sort(visible)
 print('[TAG_FILTER] '..json.encode({actor=user,case=case,phase=phase,
  tagsEnabled=Tags.enabled(),inventoryFilters=PZSurvivorToolkit.Settings.inventoryFilters(),
  pickerRemoved=rulePicker.removed or false,pickerVisible=rulePicker:getIsVisible(),
  pickerClosed=rulePicker.removed or not rulePicker:getIsVisible(),
  ownerRemoved=owner and owner.removed or false,ownerVisible=owner and owner:getIsVisible(),
  ownerReallyVisible=owner and owner:isReallyVisible(),ownerIsPane=owner==pane,
  ownerClosed=not owner or owner.removed or not owner:getIsVisible() or not owner:isReallyVisible(),
  ownerInventoryID=containing and containing:getID() or false,ownerInventoryIsSource=owner and owner.inventory==source,
  incomingRule=rulePicker.rule,paneRule=pane.toolkitTagRule or false,
  rawGroups=groups(pane.itemindex),unfilteredGroups=groups(pane.toolkitUnfilteredRows),
  visibleGroups=groups(pane.itemslist),visibleIDs=visible}))
end
local function applyInventoryRule(case)
 filterTrace(case,'beforeApply')
 assert(pane.inventory==source,'inventory pane lost equipped fixture source before '..case)
 rulePicker.applyButton.onclick(rulePicker)
 filterTrace(case,'afterApply')
end
local function expectVisible(keys,case)
 pane:refreshContainer()
 if case then filterTrace(case,'afterRefresh') end
 local wanted={};for _,key in ipairs(keys) do wanted[key]=true end
 for _,key in ipairs({'battery','apple','beans','steak'}) do
  assert(rowsContain(setup[key])==(wanted[key] or false),'inventory rule visibility '..key)
 end
end
local function categoryMenu()
 pane:prerender()
 local button=assert(pane.toolkitCategoryButton,'native category button missing')
 local menu,original= nil,ISContextMenu.get
 ISContextMenu.get=function(...) menu=original(...);return menu end
 local ok,err=pcall(button.onclick,pane,button)
 ISContextMenu.get=original
 assert(ok,err);assert(menu,'native category menu missing')
 return menu
end
local function optionKey(menu,key)
 for _,option in ipairs(menu.options) do if option.pzstKey==key then return option end end
 error('native menu option missing '..key)
end
local function invoke(menu,option)
 assert(not option.notAvailable and option.onSelect,'native menu option disabled')
 local result=option.onSelect(option.target,option.param1,option.param2)
 menu:hideAndChildren();return result
end
local function presetMenu()
 local root=categoryMenu()
 return root,root:getSubMenu(optionKey(root,'tagPresets').subOption)
end
local function storedPreset()
 local list,err=require('PZSurvivorToolkit/TagFilterPresets').list();assert(list,err)
 for _,entry in ipairs(list) do if entry.name==PRESET_NAME then return entry.rule end end
end
local function openInventoryRule()
 local menu=categoryMenu()
 local option
 for _,entry in ipairs(menu.options) do if entry.name==getText('UI_PZST_TagRule') then option=entry;break end end
 assert(option and option.onSelect,'combined rule entry missing')
 option.onSelect(option.target);menu:hideAndChildren()
 rulePicker=assert(pane.toolkitRulePicker,'combined inventory picker missing')
end
local function selectRule(include,exclude,mode)
 rulePicker.clearButton.onclick(rulePicker)
 for _,spec in ipairs({{include,1},{exclude,2}}) do
  for _,id in ipairs(spec[1]) do
   local row
   for _,entry in ipairs(rulePicker.entries) do if entry.id==id then row=entry;break end end
   assert(row,'picker tag missing '..id)
   for count=1,spec[2] do rulePicker.list.onmousedown(rulePicker,row) end
  end
 end
 if mode=='any' then rulePicker.modeButton.onclick(rulePicker) end
 assert(rulePicker.rule.mode==(mode or 'all'),'picker mode changed')
end
local function ownEffective()
 local own,reason=Fixture.sortTarget(getPlayer(),box)
 if not own and getTimestampMs()-lastSortWait>1000 then
  lastSortWait=getTimestampMs();print('[TAG_SORT_WAIT] actor='..user..' reason='..tostring(reason))
 end
 return own
end
local function sortSource()
 if not ownEffective() then return false end
 local player=getPlayer();local start=player:getCurrentSquare()
 assert(start and start:canStand(),'native sort starts on blocked/unsupported floor')
 local stand=AdjacentFreeTileFinder.Find(box:getSquare(),player)
 assert(stand and stand:canStand() and stand:canReachTo(box:getSquare()),'native crate stand tile is unreachable')
 LootSorter.DEBUG=true
 local before=LootSorter._sortRunSeq or 0
 local constructor=LootSorter.WalkAction.new
 LootSorter.WalkAction.new=function(self,...)
  return Fixture.traceWalk(constructor(self,...),function(value)
   value.actor=user;print('[TAG_WALK] '..json.encode(value))
  end)
 end
 local ok,err=pcall(LootSorter.sort,source,0)
 LootSorter.WalkAction.new=constructor
 assert(ok,err)
 assert((LootSorter._sortRunSeq or 0)>before,'native sort did not enter planner after readiness')
 local queue=ISTimedActionQueue.getTimedActionQueue(getPlayer())
 print('[TAG_SORT_STARTED] actor='..user..' run='..LootSorter._sortRunSeq..' queue='..#queue.queue)
 return true
end
local function awaitReceipt(phase)
 local status,reason,ids=Fixture.receipt(source,box:getContainerByIndex(0),setup,phase)
 assert(status~='invalid',reason)
 local prior=localReceipts[phase]
 if not prior or prior.status~=status then
  localReceipts[phase]={status=status,since=getTimestampMs()}
  print('[TAG_LOCAL_RECEIPT] '..json.encode({phase=phase,status=status,reason=reason,ids=ids}))
 end
 if status=='pending' then assert(getTimestampMs()-localReceipts[phase].since<15000,'local receipt timeout '..phase..' '..tostring(reason)) end
 if verified[phase] and status=='ready' then return true end
 if getTimestampMs()-lastReady>1000 then lastReady=getTimestampMs();sendClientCommand('TagBaseline','Verify',{phase=phase}) end
 return false
end
add(function()
 if not setup then
  if getTimestampMs()-lastReady>1000 then lastReady=getTimestampMs();sendClientCommand('TagBaseline','Ready',{}) end
  return
 end
 box=Fixture.object(setup,user);if not box then return end
 local inv=getPlayer():getInventory()
 if setup.source then
  local bag=Fixture.find(inv,setup.source);if not bag then return end
  assert(bag:getModData().PZSTTagFixtureOwner==user,'source bag owner missing')
  source=bag:getInventory()
  for _,key in ipairs(config.tagRules and {'battery','apple','beans','steak'} or {'battery','apple'}) do
   if not Fixture.find(source,setup[key]) then return end
  end
 else
  source=inv;if not Fixture.find(source,setup.battery) or not Fixture.find(source,setup.apple) then return end
 end
 assert(source:isInCharacterInventory(getPlayer()),'fixture source bag is not carried')
 Tags=require 'PZSurvivorToolkit/ItemTags'
 local battery=assert(Fixture.find(source,setup.battery),'fixture Battery missing')
 batteryCategory=battery:getDisplayCategory() or battery:getCategory()
 assert(type(batteryCategory)=='string' and Tags.matches(Tags.forItem(battery),{'electrical'}),'native Battery lacks electrical tag')
 if config.tagRules then Rules=require 'PZSurvivorToolkit/QuartermasterTagRules' end
 LootSorter.openPicker(box,0,0);picker=assert(LootSorter._picker)
 picker.filter:setText(Tags.label('electrical'));picker:rebuild()
 assert(#picker.listbox.items==1,'electrical row missing')
 picker.listbox.onmousedown(picker,picker.listbox.items[1].item)
 assert(picker.selectedCats.toolElectrical and picker.selectedCats.craftingElectrical_material and picker.selectedCats[batteryCategory])
 picker.btnSave.onclick(picker)
 return true
end)
add(function()
 local cats=LootSorter.getBoxCats(box,0)
 if not cats or not cats[batteryCategory] then return end
 if not manualCategoryAck then
  if getTimestampMs()-lastReady>1000 then
   lastReady=getTimestampMs();sendClientCommand('TagBaseline','ManualCategory',{category=batteryCategory})
  end
  return
 end
 pass('configure');LootSorter.openPicker(box,0,0);picker=LootSorter._picker
 assert(picker.selectedCats.toolElectrical and picker.selectedCats.craftingElectrical_material and picker.selectedCats[batteryCategory])
 picker:closePicker();pass('reopen')
 return true
end)
if config.tagRules then
 add(function()
  local player=getPlayer();local bag=assert(Fixture.find(player:getInventory(),setup.source),'owned source bag missing before wear')
  if not player:isEquipped(bag) then
   if not bagWearQueued then
    assert(idle(),'fixture bag wear requires idle native queue')
    assert(bag:canBeEquipped() and not player:getWornItem(bag:canBeEquipped()),'fixture bag would replace original worn equipment')
    ISInventoryPaneContextMenu.onWearItems({bag},0);bagWearQueued=true
    print('[TAG_BAG_WEAR] actor='..user..' id='..bag:getID()..' phase=queued')
   end
   return false
  end
  if not idle() then return false end
  assert(player:getWornItem(bag:canBeEquipped())==bag,'fixture source bag did not reach native worn slot')
  assert(type(config.textureNames)=='table' and #config.textureNames>0,'immutable TagVisuals texture list missing')
  for _,name in ipairs(config.textureNames) do assert(getTexture(name),'tag texture missing '..name) end
  print('[TAG_TEXTURES] actor='..user..' checked='..#config.textureNames);pass('icons')
  local page=getPlayerInventory(0);page:setVisible(true);page.isCollapsed=false;page:setPinned()
  page:setX(35);page:setY(70);page:setWidth(1000);page:setHeight(650);page:setMaxDrawHeight(650)
  page:refreshBackpacks();page:setNewContainer(source)
  pane=page.inventoryPane;pane:setVisible(true);pane:setMode('details')
  assert(pane.inventory==source,'inventory pane did not select carried fixture bag')
  pane.toolkitCategory,pane.toolkitTag,pane.toolkitTagRule=nil,nil,nil
  pane:refreshContainer()
  assert(Tags.matchesRule(Fixture.find(source,setup.apple):getDisplayCategory(),Fixture.rule()),'native Apple category differs')
  assert(not Tags.matchesRule(Fixture.find(source,setup.steak):getDisplayCategory(),Fixture.rule()),'native Steak category differs')
  openInventoryRule();selectRule({'food','perishable'},{},'all')
  assert(rulePicker.matchCount==2,'all preview expected Apple and Steak')
  return true
 end)
 add(function() shot('inventory-all');applyInventoryRule('inventory-all');expectVisible({'apple','steak'},'inventory-all');pass('inventory-all')
  openInventoryRule();selectRule({'perishable','electrical'},{},'any');assert(rulePicker.matchCount==3,'any preview expected three items');return true end)
 add(function() shot('inventory-any');applyInventoryRule('inventory-any');expectVisible({'apple','steak','battery'},'inventory-any');pass('inventory-any')
  openInventoryRule();selectRule({'food','perishable'},{'meat'},'all');assert(rulePicker.matchCount==1,'exclude preview expected only Apple');return true end)
 add(function() shot('inventory-exclude');applyInventoryRule('inventory-exclude');expectVisible({'apple'},'inventory-exclude');pass('inventory-exclude')
  return true end)
 add(function()
  local root,menu=presetMenu()
  presetDialog=assert(invoke(root,optionKey(menu,'tagPresetSave')),'native preset name dialog missing')
  presetDialog.entry:setText(PRESET_NAME);presetDialog:updateButtons()
  return true
 end)
 add(function()
  shot('preset-save');presetDialog:onClick(presetDialog.yes)
  assert(Fixture.sameRule(storedPreset()),'saved preset failed native file readback')
  pass('preset-save')
  openInventoryRule();selectRule({'food','electrical'},{},'all');assert(rulePicker.matchCount==0,'no-match preview expected zero')
  assert(#rulePicker.preview.items==1 and rulePicker.preview.items[1].item==false,'empty preview placeholder missing');return true end)
 add(function() shot('inventory-empty');applyInventoryRule('inventory-empty');expectVisible({},'inventory-empty');pass('inventory-empty')
  local root,menu=presetMenu()
  invoke(root,optionKey(menu,'tagPreset:'..PRESET_NAME))
  assert(Fixture.sameRule(pane.toolkitTagRule),'saved preset did not apply through inventory menu')
  expectVisible({'apple'},'preset-apply');return true
 end)
 add(function()
  shot('preset-apply');pass('preset-apply')
  pane.toolkitTagRule=nil;pane:refreshContainer()
  sendClientCommand('TagBaseline','CaptureManual',{});return true
 end)
 add(function()
  if not manualCaptured then
   if getTimestampMs()-lastReady>1000 then lastReady=getTimestampMs();sendClientCommand('TagBaseline','CaptureManual',{}) end
   return
  end
  LootSorter.openPicker(box,0,0);picker=assert(LootSorter._picker)
  local before={};for category,value in pairs(picker.selectedCats) do before[category]=value end
  picker.toolkitTagRuleButton.onclick(picker)
  rulePicker=assert(picker.toolkitRulePicker,'Quartermaster combined picker missing')
  selectRule({'food','perishable'},{'meat'},'all')
  assert(rulePicker.matchCount>0,'Quartermaster category preview empty')
  picker.fixtureManualBefore=before
  return true
 end)
 add(function() shot('quartermaster-rule-preview');rulePicker.applyButton.onclick(rulePicker)
  assert(Fixture.sameRule(picker.toolkitTagRule),'Quartermaster rule UI failed')
  for category,value in pairs(picker.fixtureManualBefore) do assert(picker.selectedCats[category]==value,'precise category selection stripped') end
  picker.btnSave.onclick(picker);return true
 end)
 add(function()
  if LootSorter._picker==picker then return end
  if not Fixture.sameRule(Rules.getBox(box,0)) then return end
  sendClientCommand('TagBaseline','VerifyRule',{phase='saved'});return true
 end)
 add(function()
  if not ruleVerified.saved then return end
  pass('rule-save');LootSorter.openPicker(box,0,0);picker=assert(LootSorter._picker)
  assert(Fixture.sameRule(picker.toolkitTagRule) and picker.selectedCats[batteryCategory],'reopened dynamic/manual state differs')
  picker.toolkitTagRuleButton.onclick(picker);rulePicker=assert(picker.toolkitRulePicker)
  assert(Fixture.sameRule(rulePicker.rule) and rulePicker.matchCount>0,'reopened rule preview differs')
  return true
 end)
 add(function() shot('quartermaster-rule-reopen');rulePicker.cancelButton.onclick(rulePicker);picker:closePicker();pass('rule-reopen')
  local revision=Rules.getBoxRevision(box,0)
  assert(revision>0,'rule revision missing')
  Rules.saveBox(box,0,{mode='all',include={'electrical'},exclude={}},getPlayer(),function(verdict) staleReply=verdict end,revision-1)
  return true
 end)
 add(function()
  if not staleReply then return end
  assert(staleReply=='stale' and Fixture.sameRule(Rules.getBox(box,0)),'stale rule request changed client state')
  sendClientCommand('TagBaseline','VerifyRule',{phase='stale'});return true
 end)
 add(function()
  if not ruleVerified.stale then return end
  pass('rule-stale');return true
 end)
 add(function()
  if getTimestampMs()-lastPeer>1000 then
   lastPeer=getTimestampMs();sendClientCommand('TagBaseline','Peers',{})
   local square=peer and getCell():getGridSquare(peer.x,peer.y,peer.z)
   local objects=square and square:getObjects()
   local object=peer and Fixture.object(peer,peer.owner)
   print('[TAG_PEER_WAIT] '..json.encode({actor=user,packet=peer or false,
    squareLoaded=square~=nil,objects=objects and objects:size() or false,
    objectResolved=object~=nil,rule=object and Rules.getBox(object,0) or false,
    revision=object and Rules.getBoxRevision(object,0) or false}))
  end
  if not peer then
   return
  end
  local other=Fixture.object(peer,peer.owner);if not other then return end
  if not Fixture.sameRule(Rules.getBox(other,0)) then return end
  assert(Rules.getBoxRevision(other,0)>=peer.revision,'peer rule revision absent')
  assert(LootSorter.getBoxCats(other,0)[peer.manualCategory],'peer native categories absent')
  pass('rule-peer')
  PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ItemTags'):setValue(false)
  return true
 end)
 add(function()
  if Tags.enabled() then return end
  local own=ownEffective();if not own then return end
  assert(own.cats[batteryCategory] and not own.cats.foodPerishable_fruit,'disabled tags still expanded dynamic rule')
  return sortSource()
 end)
 add(function() if not idle() then return end;if not awaitReceipt('disabled') then return end
  PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ItemTags'):setValue(true);return true end)
 add(function()
  if not Tags.enabled() then return end
  local own=ownEffective();if not own then return end
  assert(own.cats[batteryCategory] and own.cats.foodPerishable_fruit and not own.cats.foodPerishable_meat,
   're-enabled dynamic rule/manual selection changed')
  return sortSource()
 end)
 add(function() if not idle() then return end;if not awaitReceipt('enabled') then return end
  pass('rule-toggle');pass('sort');return true end)
else
 add(function() return sortSource() end)
 add(function() if not idle() then return end;return awaitReceipt('baseline') end)
 add(function() pass('sort');shot('baseline');return true end)
end
local function complete()
 local count=0;for _ in pairs(passed) do count=count+1 end
 assert(count==#config.cases,'case count differs '..count..'/'..#config.cases)
 for _,id in ipairs(config.cases) do assert(passed[id],'case did not run '..id) end
 emit({event='complete',cases=config.cases,expected=#config.cases,performed=count,skipped=0,failed=0});done=true
 return true
end
add(function()
 assert(config.cases[#config.cases]==RECONNECT_CASE,'cases must end with reconnect')
 for _,id in ipairs(config.cases) do if id~=RECONNECT_CASE then assert(passed[id],'pre-reconnect case missing '..id) end end
 writeReconnect('pending');print('[TAG_RECONNECT] actor='..user..' phase=disconnect')
 started,awaitingReconnect=false,true
 getCore():exitToMenu()
 return false
end)
local resumeSteps={}
resumeSteps[1]=function()
 if not setup then
  if getTimestampMs()-lastReady>1000 then lastReady=getTimestampMs();sendClientCommand('TagBaseline','Ready',{reconnect=true}) end
  return
 end
 box=Fixture.object(setup,user);if not box then return end
 local bag=Fixture.find(getPlayer():getInventory(),setup.source);if not bag then return end
 assert(bag:getModData().PZSTTagFixtureOwner==user,'reconnected fixture bag owner differs')
 source=bag:getInventory()
 batteryCategory=setup.manualCategory
 assert(type(batteryCategory)=='string' and LootSorter.getBoxCats(box,0)[batteryCategory],'reconnect lost native manual category')
 if not config.tagRules then
  sendClientCommand('TagBaseline','Verify',{phase='baseline'})
  return true
 end
 assert(Fixture.sameRule(storedPreset()),'inventory preset missing after reconnect disk read')
 Tags=require 'PZSurvivorToolkit/ItemTags';Rules=require 'PZSurvivorToolkit/QuartermasterTagRules'
 if not Fixture.sameRule(Rules.getBox(box,0)) then return end
 assert(type(setup.revision)=='number' and setup.revision>0,'server reconnect rule revision absent')
 assert(Rules.getBoxRevision(box,0)==setup.revision,'reconnect rule revision changed')
 LootSorter.openPicker(box,0,0);picker=assert(LootSorter._picker)
 assert(Fixture.sameRule(picker.toolkitTagRule) and picker.selectedCats[batteryCategory],'reopened rule after reconnect differs')
 sendClientCommand('TagBaseline','VerifyRule',{phase='reconnect'})
 sendClientCommand('TagBaseline','Verify',{phase='enabled'})
 return true
end
resumeSteps[2]=function()
 if not config.tagRules then
  if not awaitReceipt('baseline') then return end
  shot('baseline-reconnect');writeReconnect('done');pass(RECONNECT_CASE)
  print('[TAG_RECONNECT] actor='..user..' phase=verified baseline=true')
  return true
 end
 if not ruleVerified.reconnect or not awaitReceipt('enabled') then return end
 assert(ruleVerified.reconnect.revision==setup.revision,'authoritative revision changed after reconnect')
 shot('quartermaster-rule-reconnect');picker:closePicker()
 local page=getPlayerInventory(0);page:setVisible(true);page.isCollapsed=false;page:setPinned()
 page:refreshBackpacks();page:setNewContainer(source);pane=page.inventoryPane;pane:setVisible(true)
 assert(pane.inventory==source,'reconnect preset menu lost fixture source')
 local root,menu=presetMenu()
 local deletes=menu:getSubMenu(optionKey(menu,'tagPresetDelete').subOption)
 invoke(root,optionKey(deletes,'tagPresetDelete:'..PRESET_NAME))
 assert(not storedPreset(),'preset deletion did not persist after reconnect')
 writeReconnect('done');print('[TAG_RECONNECT] actor='..user..' phase=verified revision='..setup.revision)
 pass(RECONNECT_CASE)
 return true
end
resumeSteps[3]=complete
local function beginResume()
 resuming,awaitingReconnect=true,false
 connected,advanced,started,done=false,false,false,false
 setup,box,picker,source,pane,rulePicker,peer,serverFailure,manualCaptured,batteryCategory,manualCategoryAck=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
 verified,ruleVerified,staleReply={}, {}, nil
 localReceipts={}
 step,since,lastReady,lastPeer=1,getTimestampMs(),0,0
 placement,lastPlacementAck=nil,0
 steps,passed=resumeSteps,{}
 for _,id in ipairs(config.cases) do if id~=RECONNECT_CASE then passed[id]=true end end
end
if reconnectFlag()=='pending' then beginResume() end
local function connect()
 if connected or isClient() or not MainScreen.instance or not ConnectToServer.instance then return end
 connected=true
 ConnectToServer.instance:connect(MainScreen.instance,'Tag baseline',user,'smoke-local-only','127.0.0.1','',tostring(config.port),'',false,true,1)
end
Events.OnMainMenuEnter.Add(function()
 if not resuming and reconnectFlag()=='pending' then beginResume() end
 connect()
end)
Events.OnPreUIDraw.Add(function()
 if (not connected and not isClient()) or advanced or isIngameState() or not MainScreen.instance or not MapSpawnSelect.instance then return end
 if MainScreen.instance.charCreationProfession:getIsVisible() or MapSpawnSelect.instance:getIsVisible() then
  advanced=true;MapSpawnSelect.instance:useDefaultSpawnRegion();MapSpawnSelect.instance:setVisible(false)
  MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'});MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
 end
end)
Events.OnGameStart.Add(function()
 started=true;providerConfigured=false;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false)
 getCore():setOptionAutoDrink(false);getPlayer():setAutoDrink(false);getPlayer():setGodMod(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
 print('[QUEUE_TEST] NATIVE_CONNECTED '..user)
 if not resuming then emit({event='setup',cases=config.cases,expected=#config.cases,language=language,nativeDurations=true,queueEnabled=true})
 else print('[TAG_RECONNECT] actor='..user..' phase=connected') end
end)
Events.OnServerCommand.Add(function(module,command,args)
 if module~='TagBaseline' then return end
 local ok,err=pcall(function()
  if command=='Setup' then setup=args;placement=nil
  elseif command=='Verified' then assert(args.ok,'authority receipt failed');verified[args.phase]=args
   print('[TAG_CLIENT_RECEIPT] '..json.encode({phase=args.phase,ids=args.ids}))
  elseif command=='ManualCategory' then assert(args.ok,'native manual category audit failed');manualCategoryAck=true
  elseif command=='ManualCaptured' then assert(args.ok,'manual snapshot failed');manualCaptured=true
  elseif command=='RuleVerified' then assert(args.ok,'rule authority failed');ruleVerified[args.phase]=args
  elseif command=='Peer' then peer=args
  elseif command=='Placement' then placement=args
  elseif command=='Position' then Fixture.position(getPlayer(),args.x,args.y,args.z)
  elseif command=='Error' then serverFailure=args.reason end
 end)
 if not ok then serverFailure=tostring(err) end
end)
Events.OnTick.Add(function()
 if done then return end
 if awaitingReconnect and not isIngameState() then beginResume() end
 if not started then if resuming then connect() end;return end
 local now=getTimestampMs()
 local ok,err=pcall(function()
  assert(not serverFailure,serverFailure)
  assert(now-since<120000,'tag stage timeout '..step)
  if now-since<1000 then return end
  if placement and now-lastPlacementAck>1000 then
   if Fixture.placementLoaded(placement) then
    lastPlacementAck=now
    sendClientCommand('TagBaseline','PlacementReady',{signature=placement.signature})
    print('[TAG_PLACEMENT_READY] actor='..user..' signature='..placement.signature)
   end
  end
  if not providerConfigured then
   local panel=assert(PZAPI.ModOptions:getOptions('BetterContainers'),'BetterContainers options missing')
   assert(panel:getOption('showAdvancedDisplayCategories'),'BetterContainers category option missing'):setValue(false)
   panel.apply()
   assert(require('BetterContainers/_Options').showAdvancedDisplayCategories==false,'BetterContainers advanced categories remain enabled')
   providerConfigured=true
   print('[TAG_TEST] CATEGORY_PROVIDER organizedCategories BC_advanced=false')
   return
  end
  if steps[step]() then step=step+1;since=now end
 end)
 if not ok then done=true;print('[QUEUE_TEST] FAIL tag client '..tostring(err));emit({event='error',reason=tostring(err)}) end
end)
