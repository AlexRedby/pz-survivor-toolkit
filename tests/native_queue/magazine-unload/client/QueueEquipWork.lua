-- Actual UIManager draws and native pointer getters; widget events are
-- programmatic, never OS mouse/focus manipulation or permission caching.
local W={}
local Proof=require 'PZSurvivorToolkit/SourceProof'
local pointerX,pointerY,pointerOver,pointerWatch
local function pack(...)return{n=select('#',...),...}end
local function panelFor(queue,optional)
 PZSurvivorToolkit.ActionQueuePanel.refresh()
 local windows=UIManager.getUI();local found
 for index=0,windows:size()-1 do
  local element=windows:get(index);local view=element and element.getTable and element:getTable()
  if view and getmetatable(view)==PZSurvivorToolkit.ActionQueuePanel and view.queue==queue and view:getIsVisible()then
   assert(not found,'duplicate live queue panel');found=view
  end
 end
 if optional then return found end
 return assert(found,'live queue panel unavailable')
end
local function rowFor(list,action)
 for _,row in ipairs(list.items)do if row.item==action and not row.header then return row end end
 error('native singleton row missing')
end
local function verifyPointer(list)
 assert(pointerWatch()and list.getMouseX==pointerX and list.getMouseY==pointerY
  and list.isMouseOver==pointerOver,'native pointer getter replaced')
end
local function align(panel,row,cancel,after)
 local list=panel.list;verifyPointer(list)
 local x=cancel and list:cancelX()+12 or 80
 local y=list:topOfItem(row.index)+(after and row.height-3 or row.height/2)
 panel.keepOnScreen=false
 panel:setX(panel:getX()+list:getMouseX()-x)
 panel:setY(panel:getY()+list:getMouseY()-y)
 assert(math.abs(list:getMouseX()-x)<1 and math.abs(list:getMouseY()-y)<1
  and list:isMouseOver()and list:rowUnderMouse(list:getMouseX(),list:getMouseY())==row,'native pointer alignment failed')
 return list:getMouseX(),list:getMouseY()
end
local function away(panel)
 local width=getCore():getScreenWidth()
 panel.keepOnScreen=false;panel:setX(getMouseX()<width/2 and width-panel.width-20 or 20);panel:setY(20)
 assert(not panel.list:isMouseOver(),'idle panel still hovered')
end
local function changed(before,queue)
 if #before~=#queue.queue then return true end
 for index,action in ipairs(before)do if queue.queue[index]~=action then return true end end
 return false
end
local function order(queue)local result={};for _,action in ipairs(queue.queue)do result[#result+1]=action end;return result end
function W.new(config)
 -- Capture only after the native bridge is ready, never during Lua directory loading.
 if not pointerWatch then
  pointerX,pointerY,pointerOver=ISUIElement.getMouseX,ISUIElement.getMouseY,ISUIElement.isMouseOver
  -- The native UI class exceeds captureBindings' bounded inherited-owner scan.
  -- Freeze the plain root/base bindings, then check its exact native parent and
  -- the retained selected methods directly; never widen runtime capture limits.
  local base,element,meta=ISBaseObject,ISUIElement,toolkitLuaMetatableMatches
  local watch=assert(Proof.captureBindings({{owner=_G,keys={'ISUIElement','ISBaseObject','toolkitLuaMetatableMatches'}},
   {owner=base,keys={'__index','getMouseX','getMouseY','isMouseOver'}}}),'native UI root binding capture unavailable')
  pointerWatch=function()
   return watch()and meta(element,base)==true and element.getMouseX==pointerX
    and element.getMouseY==pointerY and element.isMouseOver==pointerOver
  end
 end
 assert(Proof.matches('media/lua/client/ISUI/ISUIElement.lua',1904087254,nil,true)and pointerWatch()
  and Proof.closure(pointerX,'ISUIElement.lua')and Proof.closure(pointerY,'ISUIElement.lua')and Proof.closure(pointerOver,'ISUIElement.lua'),'native UI pointer source changed')
 assert(type(equipWorkNowMs)=='function'and type(equipWorkMark)=='function'and type(equipWorkSnapshot)=='function','work probe not installed')
 local clock,mark,snapshot=equipWorkNowMs,equipWorkMark,equipWorkSnapshot
 local self={config=config,result={schema=1,input='programmatic-native-widget-handlers',osEventRouting=false,
  pointerGettersReplaced=false,requestsFocus=false,renderer='native-UIManager',phases={}},stage=nil,started=clock()}
 function self:panelReady(queue)return panelFor(queue,true)~=nil end
 function self:check()
  assert(equipWorkNowMs==clock and equipWorkMark==mark and equipWorkSnapshot==snapshot,'work probe API rebound')
 end
 function self:arm()self:check();assert(mark(config.mode=='native'and'queue-disabled-before-commands'or'before-first-equip-command')==true,'work phase acquisition failed')end
 function self:sample(name)
  self:check();local value=snapshot();assert(value.schema==1 and value.droppedCalls==0 and value.droppedPaths==0,'incomplete native work observation')
  local result={name=name,metrics=value}
  if self.stats then
   result.panel={draws=self.stats.draws,drawMs=self.stats.total,maxDrawMs=self.stats.maximum,previewRebuilds=self.stats.previews}
   result.ticks={count=self.stats.ticks,totalMs=self.stats.tickTotal,maxMs=self.stats.tickMax}
  end
  self.result.phases[#self.result.phases+1]=result;return result
 end
 function self:beginStage(name)
  self:check();assert(mark(name)==true,'work phase acquisition failed');self.stage=name;self.since=clock()
  self.stats={draws=0,total=0,maximum=0,previews=0,ticks=0,tickTotal=0,tickMax=0,lastTick=nil}
 end
 function self:attach(queue)
  local panel=panelFor(queue);panel:update();self.panel=panel
  self.position={x=panel:getX(),y=panel:getY(),keep=panel.keepOnScreen}
  away(panel);local list=panel.list;verifyPointer(list)
  local draw=assert(list.doDrawItem);self.originalDraw=draw
  self.draw=function(...)
   local stage=self.stage;local previous=list.previewText;local before=clock();local result=pack(draw(...))
   if stage and stage==self.stage and self.stats then
    local elapsed=clock()-before;local stats=self.stats;stats.draws=stats.draws+1;stats.total=stats.total+elapsed;stats.maximum=math.max(stats.maximum,elapsed)
    if list.previewText~=previous then stats.previews=stats.previews+1 end
   end
   return unpack(result,1,result.n)
  end
  list.doDrawItem=self.draw
 end
 function self:handler(name,...)
  local list=self.panel.list;local before=clock();list[name](list,...);return clock()-before
 end
 function self:drag(queue,action,target,canEdit)
  self:sample('before-first-equip-command');self:attach(queue)
  self:beginStage('first-drag')
  local list=self.panel.list;local from,to=rowFor(list,action),rowFor(list,target)
  local before=order(queue);local x,y=align(self.panel,from,false)
  local press=self:handler('onMouseDown',x,y);assert(list.dragAction==action,'native drag press did not capture action')
  x,y=align(self.panel,to,false);self:handler('onMouseMove',0,0)
  assert(list.dragging and list.dropTarget==target,'native drag target not acquired')
  local release=self:handler('onMouseUp',x,y);assert(not list.dragAction,'native drag gesture survived release')
  local moved=changed(before,queue);assert(moved==canEdit,'native drag commit differs from mode contract')
  self.result.cold={pressMs=press,releaseMs=release,committed=moved,scope='first-timed-widget-gesture-not-OS-routing',sourceScope='first-family-enqueue-and-gesture-not-filesystem-cold',nativeHitTesting=true}
  self:sample('first-drag');self.actions={moving=action,target=target};self:beginStage('idle-visible');away(self.panel)
  if moved then return true end
  local decision=PZSurvivorToolkit.ActionQueuePolicy.evaluateMove(queue,action,target,false)
  assert(not decision.allowed,'post-release protected decision became allowed')
  return false,decision.reason
 end
 function self:native(queue)
  self:sample('queue-disabled-before-commands');self:beginStage('queue-disabled')
 end
 function self:tick(queue,front)
  self:check();assert(clock()-self.started<45000,'work sampling exceeded native hold')
  assert(queue.current==front and front:isStarted(),'native front finished before work sampling')
  local stats=self.stats;local timestamp=clock()
  if stats.lastTick then local gap=timestamp-stats.lastTick;stats.ticks=stats.ticks+1;stats.tickTotal=stats.tickTotal+gap;stats.tickMax=math.max(stats.tickMax,gap)end
  stats.lastTick=timestamp
  if self.stage=='queue-disabled'then
   if timestamp-self.since<2400 then return false end
   self:sample(self.stage);assert(mark(nil)==true,'work phase release failed');self.stage=nil;self.stats=nil;self.result.observerReleased=true;return true
  end
  local panel,list=self.panel,self.panel.list;verifyPointer(list)
  local moving,target=rowFor(list,self.actions.moving),rowFor(list,self.actions.target)
  if self.stage=='idle-visible'then away(panel)
  elseif self.stage=='steady-move'then align(panel,target,false)
  elseif self.stage=='steady-cancel'then align(panel,target,true)
  elseif self.stage=='changing-drag'then
   local row=stats.ticks%2==0 and rowFor(list,front)or target
   align(panel,row,false,stats.ticks%2~=0);self:handler('onMouseMove',0,0)
   assert(list.dragging,'changing-target drag was lost')
  end
  local duration=self.stage=='idle-visible'and 400 or self.stage=='changing-drag'and 1000 or 800
  if timestamp-self.since<duration or stats.draws<4 then return false end
  self:sample(self.stage)
  if self.stage=='idle-visible'then self:beginStage('steady-move')
  elseif self.stage=='steady-move'then self:beginStage('steady-cancel')
  elseif self.stage=='steady-cancel'then
   local x,y=align(panel,moving,false);self:handler('onMouseDown',x,y)
   assert(list.dragAction==self.actions.moving,'changing drag press failed');self:beginStage('changing-drag')
  else
   self:handler('onMouseUpOutside',-1,-1);assert(not list.dragAction,'preview drag was not cleared')
   assert(list.doDrawItem==self.draw,'work draw observer rebound');list.doDrawItem=self.originalDraw
   panel:setX(self.position.x);panel:setY(self.position.y);panel.keepOnScreen=self.position.keep
   assert(mark(nil)==true,'work phase release failed');self.stage=nil
   self.result.observerReleased=true
   self.actions,self.panel,self.position,self.originalDraw,self.draw,self.stats=nil,nil,nil,nil,nil,nil
   return true
  end
  return false
 end
 function self:cancel(queue,action,canEdit)
  self:check();self.panel=panelFor(queue);self.panel:update();local panel,list=self.panel,self.panel.list
  local position={x=panel:getX(),y=panel:getY(),keep=panel.keepOnScreen};local row=rowFor(list,action);local before=order(queue)
  assert(mark('cancel-click')==true,'cancel work phase acquisition failed');local x,y=align(panel,row,true);local press=self:handler('onMouseDown',x,y)
  local release=self:handler('onMouseUp',x,y);local accepted=changed(before,queue);assert(accepted==canEdit,'native cancel commit differs from mode contract')
  self.result.cancel={pressMs=press,releaseMs=release,committed=accepted,nativeHitTesting=true,metrics=snapshot()};assert(mark(nil)==true,'cancel work phase release failed')
  panel:setX(position.x);panel:setY(position.y);panel.keepOnScreen=position.keep;self.panel=nil
  if accepted then return true end
  local decision=PZSurvivorToolkit.ActionQueuePolicy.evaluateCancel(queue,action)
  assert(not decision.allowed,'post-release cancel became allowed');return false,decision.reason
 end
 return self
end
return W
