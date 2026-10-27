-- Functional production-panel checks; no timing, pixels or physical input claim.
local Gate={}
function Gate.capture(queue,tokens,tokenId)
 local Panel=PZSurvivorToolkit.ActionQueuePanel
 Panel.refresh()
 local view
 local windows=UIManager.getUI()
 for index=0,windows:size()-1 do
  local element=windows:get(index)
  local candidate=element and element.getTable and element:getTable()
  if type(candidate)=='table'and getmetatable(candidate)==Panel and candidate.queue==queue and candidate:getIsVisible()then
   assert(not view,'duplicate visible queue projection panel');view=candidate
  end
 end
 assert(view,'missing visible production queue projection panel')
 local values,current=queue.queue,queue.current
 assert(#values==4 and #tokens==3 and current==values[1],'unexpected projection queue shape')
 local actions,operations,natives={},{},{}
 for index,action in ipairs(values)do
  actions[index],operations[index],natives[index]=action,action.toolkitQueueOperation,action.action
 end
 assert(operations[1]==tokens[1]and operations[2]==tokens[2]and operations[3]==tokens[2]and operations[4]==tokens[3],
  'projection must exercise the common approach and volume operation')
 local visible,originalExpansion=view:getIsVisible(),view.expanded
 local expansion={}
 for token,value in pairs(originalExpansion or{})do expansion[token]=value end
 local result={nativeUI=true,queueCount=4,groups=3,operation=tokenId(tokens[2])}
 local function unchanged()
  assert(queue.queue==values and queue.current==current and #values==4,'projection changed native queue ownership/current')
  for index,action in ipairs(actions)do
   assert(values[index]==action and action.toolkitQueueOperation==operations[index]and action.action==natives[index],
    'projection changed a native action, token or Java allocation')
  end
 end
 local function sample(expanded)
  view:update()
  local projection=assert(view.projection)
  local snapshot=projection.native
  assert(type(snapshot)=='userdata','projection did not use the actual native bridge')
  local rows=view.list.items
  view:update()
  assert(view.projection==projection and projection.stable and projection.native==snapshot and view.list.items==rows,
   'unchanged production update did not reuse native snapshot and rows')
  assert(#projection.groups==3 and view.currentIndex==1 and toolkitQueueViewCurrentIndex(snapshot)==1,
   'native projection current index or group count is stale')
  local expected=expanded and{{1,false,1,1,1,1},{2,true,2,3,2,3},{2,false,2,2,2,3},{3,false,3,3,2,3},{4,false,4,4,4,4}}
   or{{1,false,1,1,1,1},{2,true,2,3,2,3},{4,false,4,4,4,4}}
  assert(#rows==#expected,'wrong visible production projection row count')
  local receipt={currentIndex=view.currentIndex,stableRows=true,rows={}}
  for index,spec in ipairs(expected)do
   local row=rows[index]
   assert(row.item==actions[spec[1]]and not not row.header==spec[2]and row.index==index
    and row.first==spec[3]and row.last==spec[4]and row.groupFirst==spec[5]and row.groupLast==spec[6]
    and row.operation==operations[spec[1]],'wrong production projection row identity/bounds')
   receipt.rows[index]={actionIndex=spec[1],header=not not row.header,first=row.first,last=row.last,
    groupFirst=row.groupFirst,groupLast=row.groupLast,token=tokenId(row.operation)}
  end
  unchanged()
  return receipt
 end
 local ok,error=pcall(function()
  view.expanded=view.expanded or{}
  view.expanded[tokens[2]]=nil;result.collapsed=sample(false)
  view.expanded[tokens[2]]=true;result.expanded=sample(true)
  view:setVisible(false);view:clearSnapshots();view:update()
  assert(not view:getIsVisible()and not view.projection and not view.projectedRows
   and not view.projectedRowCount and not view.currentIndex and #view.list.items==0,
   'hidden native root recreated a released projection or rows')
  for _ in pairs(view.expanded)do error('hidden native root retained an expansion')end
  unchanged();result.hiddenCleared=true
  view:setVisible(true);result.reopenedView=sample(false);result.reopened=true
  result.nativeSnapshot,result.stableReuse,result.actionsUnchanged=true,true,true
 end)
 -- Restore visibility and all prior expansion entries even if a check fails.
 -- Only presentation state changes; actions and their lifecycle stay untouched.
 local restored,restoreError=pcall(function()
  view.expanded=originalExpansion or{}
  for token in pairs(view.expanded)do view.expanded[token]=nil end
  for token,value in pairs(expansion)do view.expanded[token]=value end
  view:setVisible(visible);view:update();unchanged()
  assert(view:getIsVisible()==visible,'projection visibility was not restored')
  for token,value in pairs(expansion)do assert(view.expanded[token]==value,'projection expansion was not restored')end
  for token,value in pairs(view.expanded)do assert(expansion[token]==value,'projection retained a foreign expansion')end
 end)
 assert(ok,error);assert(restored,restoreError)
 result.expansionRestored,result.visibilityRestored=true,true
 return result
end
return Gate
