-- Observe the real personal-page quick buttons without replacing UI methods or
-- forcing hidden discovery after a remote replacement.
local N=require 'WarehouseWorkloadNative'
local A={}
local watched
local optionNames={'transferMethod','transferButtonLayout'}
local function option(name)
 return assert(assert(PZAPI.ModOptions:getOptions('CleanUI')):getOption(name),'native CleanUI option missing: '..name)
end
function A.save()
 local out={};for _,name in ipairs(optionNames)do out[name]=option(name):getValue()end;return out
end
function A.configure(method)
 method=method or'1';assert(method=='1'or method=='2','unsupported native transfer method')
 option('transferMethod'):setValue(tonumber(method));option('transferButtonLayout'):setValue(2)
 assert(CleanUI_getTransferMethod()==method and CleanUI_getTransferButtonLayout()=='2','native split options not applied')
end
function A.restore(saved)
 if not saved then return end
 local out={};for _,name in ipairs(optionNames)do
  option(name):setValue(saved[name]);local actual=option(name):getValue();assert(actual==saved[name],'native quick option not restored')
  out[name]={expected=saved[name],actual=actual}
 end;watched=nil;return out
end
local function category(item)local value=item:getDisplayCategory();return value and value~=''and value or'Other'end
local function candidate(run,id)return assert(run.player:getInventory():getItemById(id),'personal affinity candidate missing')end
function A.begin(run)
 local p=run.phase
 assert(type(p.oldCategory)=='string'and type(p.newCategory)=='string'and p.oldCategory~=p.newCategory,'affinity probe categories missing/identical')
 if run.player:getUsername()=='client1'then local old=candidate(run,p.oldCandidateId);local new=candidate(run,p.newCandidateId)
  assert(old:getFullType()=='Base.Bandage'and new:getFullType()=='Base.Screwdriver','affinity probe candidate types differ')
  if category(old)~=p.oldCategory or category(new)~=p.newCategory then return nil end
 end
 run.affinity={frames=0,kind=p.affinityKind,oldCategory=p.oldCategory,newCategory=p.newCategory,samples={}}
 watched=run;return true
end
Events.OnPostUIDraw.Add(function()
 if watched and getPlayerInventory(watched.player:getPlayerNum()):getIsVisible()then watched.affinity.frames=watched.affinity.frames+1 end
end)
local function aggregate(run)
 local row=N.aggregateObservation(run);row.items={};local values=N.aggregate(run.player):getItems()
 for i=0,values:size()-1 do local item=values:get(i)
  row.items[#row.items+1]={id=item:getID(),ft=item:getFullType(),rawCategory=category(item)}
 end
 table.sort(row.items,function(a,b)return a.id<b.id end);return row
end
function A.ready(run)
 local state=assert(run.affinity)
 if not state.physicalAt then state.physicalAt=getTimestampMs();state.physicalFrame=state.frames end
 local observation=aggregate(run)
 if #state.samples<16 then
  state.samples[#state.samples+1]={frame=state.frames,elapsedMs=getTimestampMs()-state.physicalAt,
   actualIds=observation.actualIds,expectedIds=observation.expectedIds,fresh=observation.fresh,items=observation.items}
 end
 -- A real visible personal page has multiple ordinary prerender opportunities.
 -- No refresh, discovery, visibility toggle or event is manufactured here.
 return state.frames-state.physicalFrame>=3 and getTimestampMs()-state.physicalAt>=500
end
function A.proof(run)
 local state=assert(run.affinity);local loot=getPlayerLoot(run.player:getPlayerNum());local personal=getPlayerInventory(run.player:getPlayerNum())
 assert(personal:getIsVisible()and not loot:getIsVisible(),'affinity visibility changed')
 return {kind=state.kind,personalVisible=true,lootHidden=true,naturalFrames=state.frames-state.physicalFrame,
  settledMs=getTimestampMs()-state.physicalAt,oldCategory=state.oldCategory,newCategory=state.newCategory,
  samples=state.samples,aggregate=aggregate(run),forcedRefresh=false}
end
function A.dispatch(run)
 local p=run.phase;local personal=getPlayerInventory(run.player:getPlayerNum());local loot=getPlayerLoot(run.player:getPlayerNum())
 local physicalMode=p.transferMethod~=nil
 local target=physicalMode and run.state.stores[3]or N.aggregate(run.player);local root=run.player:getInventory()
 assert(personal:getIsVisible()and not loot:getIsVisible(),'personal quick requires visible source and hidden target')
 assert(personal.inventoryPane.inventory==root and loot.inventoryPane.inventory==target,'personal quick source/aggregate binding changed')
 assert(CleanUI_getTransferMethod()==(p.transferMethod or'1')and CleanUI_getTransferButtonLayout()=='2','quick options drifted')
 local old,new=candidate(run,p.oldCandidateId),candidate(run,p.newCandidateId)
 local oldCategory,newCategory=category(old),category(new)
 local physicalOld,physicalNew,physicalOldAffinity,physicalNewAffinity=0,0,0,0
 local physicalRows={}
 for _,container in ipairs(physicalMode and{target}or run.state.stores)do
  for i=0,container:getItems():size()-1 do local item=container:getItems():get(i)
   if physicalMode then physicalRows[#physicalRows+1]={id=item:getID(),ft=item:getFullType(),rawCategory=category(item)}end
   local a=p.affinityKind=='type'and item:getFullType()==old:getFullType()or p.affinityKind=='category'and category(item)==oldCategory
   local b=p.affinityKind=='type'and item:getFullType()==new:getFullType()or p.affinityKind=='category'and category(item)==newCategory
   if item:getFullType()==old:getFullType()then physicalOld=physicalOld+1 end
   if item:getFullType()==new:getFullType()then physicalNew=physicalNew+1 end
   if a then physicalOldAffinity=physicalOldAffinity+1 end;if b then physicalNewAffinity=physicalNewAffinity+1 end
  end
 end
 assert(physicalOld==0 and physicalNew==1,'physical stock does not distinguish old/new affinity')
 local handler=assert(ISInventoryPageTransferHandler);local selected={}
 local physical=assert(run.state.stores[3]);local hotbar=getPlayerHotbar(run.player:getPlayerNum())
 local function attached(item)return hotbar and hotbar:isInHotbar(item)==true or false end
 local oldEligible,newEligible=handler.canTransferItem(old,target,run.player),handler.canTransferItem(new,target,run.player)
 local oldAllowed,newAllowed=target:isItemAllowed(old)==true,target:isItemAllowed(new)==true
 local physicalOldEligible,physicalNewEligible=handler.canTransferItem(old,physical,run.player),handler.canTransferItem(new,physical,run.player)
 assert(physicalOldEligible and physicalNewEligible and not old:isFavorite()and not new:isFavorite()
  and not old:isEquipped()and not new:isEquipped()and not attached(old)and not attached(new),'affinity candidate protection differs')
 local blocked=not oldAllowed and not newAllowed and not oldEligible and not newEligible
 assert(blocked or oldAllowed and newAllowed and oldEligible and newEligible,'affinity candidates differ in ordinary native eligibility')
 assert(physicalMode or blocked or physicalOldAffinity==0 and physicalNewAffinity==1,'physical stock does not distinguish affinity')
 local metadata={};for _,entry in ipairs(p.items or{})do metadata[entry.id]=entry end
 local destinations=physicalMode and p.transferMethod=='2'and handler.getNearbyTransferContainers(personal)or{target}
 for _,destination in ipairs(destinations)do
  if physicalMode then local owned=false;for _,container in ipairs(run.state.stores)do if destination==container then owned=true end end
   assert(owned,'physical quick discovered a foreign destination')end
  for i=0,destination:getItems():size()-1 do local item=destination:getItems():get(i)
   selected[p.affinityKind=='type'and item:getFullType()or category(item)]=true
   -- Admission may prepare the fixed owned stock during the real callback.
   -- Include its authority category only in this conservative original-item
   -- safety guard; observations/admission evidence still use actual raw values.
   if physicalMode and p.affinityKind=='category'then local entry=assert(metadata[item:getID()],'foreign physical affinity stock')
    selected[entry.cat]=true end
  end
 end
 for i=0,root:getItems():size()-1 do local item=root:getItems():get(i)
  if selected[p.affinityKind=='type'and item:getFullType()or category(item)]and handler.canTransferItem(item,target,run.player)then
   assert(run.owned[item:getID()],'personal quick could transfer an original/unowned item')
  end
 end
 local byType=p.affinityKind=='type';local callbackName=byType and'onTransferByNameClick'or'onTransferByCategoryClick'
 local button=assert(byType and personal.transferByNameButton or personal.transferByCategoryButton,'personal split button absent')
 assert(button.target==personal and button.onclick==personal[callbackName]and button:getIsVisible(),'installed visible personal quick binding differs')
 local before=aggregate(run);button.onclick(button.target,button)
 assert(not loot:getIsVisible(),'personal quick exposed hidden loot')
 N.observe(run);local selectedId,count
 count=0
 for action,record in pairs(run.actions)do if record.step=='personal-quick'and action.Type=='ISInventoryTransferAction'then
  count=count+1;selectedId=action.item:getID()
  assert((selectedId==p.oldCandidateId or selectedId==p.newCandidateId)and action.srcContainer==root,'personal quick selected another source/item')
  local owned=false;for _,container in ipairs(run.state.stores)do if action.destContainer==container then owned=true end end
  assert(owned,'personal quick targeted a foreign endpoint')
 end end
 local details={};for _,item in ipairs(before.items)do details[#details+1]=item.ft..'/'..item.rawCategory end
 assert(physicalMode and(count==0 or count==1)or not physicalMode and count==(blocked and 0 or 1),'personal quick admitted '..count..' candidates; source categories='..oldCategory..'/'..newCategory..'; target='..table.concat(details,','))
 local afterRows={};if physicalMode then for i=0,target:getItems():size()-1 do local item=target:getItems():get(i)
  afterRows[#afterRows+1]={id=item:getID(),ft=item:getFullType(),rawCategory=category(item)}end
  table.sort(physicalRows,function(a,b)return a.id<b.id end);table.sort(afterRows,function(a,b)return a.id<b.id end)end
 local proof={installedButton=true,dispatched=true,callback=callbackName,kind=p.affinityKind,source='client1',selectedId=selectedId,
  oldCandidateId=p.oldCandidateId,newCandidateId=p.newCandidateId,physicalOld=physicalOld,physicalNew=physicalNew,
  physicalOldAffinity=physicalOldAffinity,physicalNewAffinity=physicalNewAffinity,
  oldEligible=oldEligible,newEligible=newEligible,targetOldAllowed=oldAllowed,targetNewAllowed=newAllowed,
  physicalOldAllowed=physical:isItemAllowed(old)==true,physicalNewAllowed=physical:isItemAllowed(new)==true,
  physicalOldEligible=physicalOldEligible,physicalNewEligible=physicalNewEligible,
  oldFavorite=old:isFavorite()==true,newFavorite=new:isFavorite()==true,
  oldEquipped=old:isEquipped()==true,newEquipped=new:isEquipped()==true,oldHotbar=attached(old),newHotbar=attached(new),
  targetType=target:getType(),targetOnlyAcceptCategory=target:getOnlyAcceptCategory(),targetCapacity=target:getCapacity(),
  targetMode=physicalMode and'physical'or nil,physicalBefore=physicalMode and physicalRows or nil,physicalAfter=physicalMode and afterRows or nil,
  oldCategory=oldCategory,newCategory=newCategory,personalVisible=true,hiddenBefore=true,hiddenAfter=true,
  transferMethod=CleanUI_getTransferMethod(),buttonLayout=CleanUI_getTransferButtonLayout(),before=before,after=aggregate(run)}
 run.affinity.dispatch={blocked=physicalMode and count==0 or blocked,physical=physicalMode,at=getTimestampMs(),frame=run.affinity.frames,proof=proof};return proof
end
function A.done(run)
 local p=run.phase;local root=run.player:getInventory()
 local dispatch=assert(run.affinity.dispatch,'personal quick has not been dispatched')
 if dispatch.blocked or dispatch.physical then
  dispatch.proof.completionFrames=run.affinity.frames-dispatch.frame;dispatch.proof.completionMs=getTimestampMs()-dispatch.at
  if dispatch.blocked then assert(root:getItemById(p.oldCandidateId)and root:getItemById(p.newCandidateId),'blocked callback changed candidate endpoints')end
  local effect=dispatch.blocked or(root:getItemById(p.oldCandidateId)~=nil)~=(root:getItemById(p.newCandidateId)~=nil)
  return effect and dispatch.proof.completionFrames>=3 and dispatch.proof.completionMs>=500 and N.idle(run.player)
 end
 return (root:getItemById(p.oldCandidateId)~=nil)~=(root:getItemById(p.newCandidateId)~=nil)
end
return A
