local O={}
function O.capture(q,moving,target,cancelling,world,cacheState)
 local policy=PZSurvivorToolkit.ActionQueuePolicy
 local probe=assert(tvSpatialProbe,'TV spatial JVM timing probe missing')
 local bindings={getGameFilesInput,getModFileReader,toolkitQueueSpatialNoMovement,toolkitQueueSpatialApiMatches,
  policy.previewMove,policy.previewCancel,policy.evaluateMove,policy.evaluateCancel}
 local list,current,generation=q.queue,q.current,q.toolkitOperationGeneration
 local actions={};for i,action in ipairs(list)do actions[i]={action=action,native=action.action,token=action.toolkitQueueOperation}end
 local before=world()
 local function unchanged()
  assert(q.queue==list and q.current==current and q.toolkitOperationGeneration==generation and #list==#actions,
   'TV timing changed queue ownership')
  for i,row in ipairs(actions)do assert(list[i]==row.action and row.action.action==row.native
   and row.action.toolkitQueueOperation==row.token,'TV timing changed action/operation binding')end
  local now={getGameFilesInput,getModFileReader,toolkitQueueSpatialNoMovement,toolkitQueueSpatialApiMatches,
   policy.previewMove,policy.previewCancel,policy.evaluateMove,policy.evaluateCancel}
  for i,value in ipairs(bindings)do assert(now[i]==value,'TV timing replaced a production API')end
  assert(world()==before,'TV timing changed native device/inventory facts')
 end
 local entries={
  {name='previewMove',kind='advisory',call=function()return policy.previewMove(q,moving,target,false)end},
  {name='evaluateMove',kind='authoritative',call=function()return policy.evaluateMove(q,moving,target,false)end},
  {name='previewCancel',kind='advisory',call=function()return policy.previewCancel(q,cancelling,true)end},
  {name='evaluateCancel',kind='authoritative',call=function()return policy.evaluateCancel(q,cancelling,true)end},
 }
 local result={schema=1,scope='bounded-live-pending-device-entrypoints',timer='System.nanoTime',units='ms',
  cacheState=cacheState or 'warm-after-positive-bank',
  firstUseScope=cacheState=='cold-positive'and'first-positive-device-query-before-other-policy-probes'
   or'source-cache-warmed-by-cold-positive-bank',warmSamples=3,
  queueCount=#list,readOnly=true,bindingsUnchanged=true,disabledBeforeEdit=false,metrics={},
  completeEditMeasured=false,inputFrameMeasured=false,positiveTimingClaim=false,timerOverhead='included-not-subtracted'}
 local function sample(entry)
  assert(probe('begin'))
  local started=probe('clock');local ok,decision=pcall(entry.call);local elapsed=probe('clock')-started
  local counts=probe('end')
  assert(ok,tostring(decision));assert(type(decision)=='table','TV timing decision missing')
  local allowed
  if entry.kind=='advisory'then
   assert(decision.allowed==nil and decision.snapshot==nil,'preview acquired authoritative output')
   allowed=decision.reason==nil
  else assert(type(decision.allowed)=='boolean','authoritative decision missing');allowed=decision.allowed end
  assert(type(elapsed)=='number'and elapsed>=0 and elapsed<math.huge and counts.active==false,'TV timing probe invalid')
  unchanged()
  return {milliseconds=elapsed,allowed=allowed,reason=decision.reason or false,counts=counts}
 end
 for _,entry in ipairs(entries)do
  local metric={name=entry.name,decisionKind=entry.kind,first=sample(entry),warm={}}
  for i=1,3 do
   local value=sample(entry)
   assert(value.allowed==metric.first.allowed and value.reason==metric.first.reason,'TV timing decision changed')
   metric.warm[i]=value
  end
  result.metrics[#result.metrics+1]=metric
 end
 result.disabledBeforeEdit=probe('status').active==false;assert(result.disabledBeforeEdit)
 unchanged();return result
end
return O
