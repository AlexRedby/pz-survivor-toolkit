"""Actual work helper/Panel handlers with explicit UI/clock/source-proof doubles.

No game, native renderer, OS input, callback provenance or timing claim is made.
The stationary-pointer model shares base geometry methods by identity so replacing
pointer getters cannot manufacture the helper's native-coordinate assertions.
"""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

PROJECT = Path(__file__).resolve().parents[1]
HARNESS = r'''
local cursorX,cursorY=170,260
local s={time=0,draws=0,moves=0,cancels=0,pressed=0,released=0,outside=0,uiLookups=0,refreshCalls=0,registered=true,pendingRegistration=false,canStart=true,marks={},captureCalls=0,sourceMatches=0,apiReady=false,sourceOK=true,rejectedLargeOwner=0}
function getMouseX()return cursorX end
function getMouseY()return cursorY end
function getCore()return{getScreenWidth=function()return 1280 end}end
ISBaseObject={};ISBaseObject.__index=ISBaseObject
ISUIElement=setmetatable({},ISBaseObject);ISUIElement.__index=ISUIElement
local function unrelatedUiMethod()end
for index=1,226 do ISUIElement['unrelatedUiMethod'..index]=unrelatedUiMethod end
function toolkitLuaMetatableMatches(value,expected)return type(value)=='table'and getmetatable(value)==expected end
function ISUIElement:getMouseX()return getMouseX()-(self.parent.x+self.offsetX)-self.scrollX end
function ISUIElement:getMouseY()return getMouseY()-(self.parent.y+self.offsetY)-self.scrollY end
function ISUIElement:isMouseOver()
 local x,y=self:getMouseX(),self:getMouseY()
 return x>=0 and x<self.width and y>=0 and y<self.height
end
local originalX,originalY,originalOver=ISUIElement.getMouseX,ISUIElement.getMouseY,ISUIElement.isMouseOver
-- Explicit metadata/source doubles: they do not qualify actual native UI bodies.
local proof={}
function proof.captureBindings(specifications)
 s.captureCalls=s.captureCalls+1;assert(s.apiReady,'binding capture ran during module load before game APIs were ready')
 local bindings,owners={},{}
 for _,spec in ipairs(specifications)do
  -- Mirror the relevant SourceProof boundary: inherited/exact owners require
  -- a bounded own-field scan; selected plain owners do not scan the whole class.
  if getmetatable(spec.owner)~=nil or spec.exact then
   local fields=0;for _ in pairs(spec.owner)do fields=fields+1 end
   if fields>128 then s.rejectedLargeOwner=s.rejectedLargeOwner+1;return nil end
  end
  owners[#owners+1]={owner=spec.owner,meta=getmetatable(spec.owner)}
  for _,key in ipairs(spec.keys)do bindings[#bindings+1]={owner=spec.owner,key=key,value=spec.owner[key]}end
 end
 return function()
  for _,owner in ipairs(owners)do if getmetatable(owner.owner)~=owner.meta then return false end end
  for _,binding in ipairs(bindings)do if binding.owner[binding.key]~=binding.value then return false end end;return true
 end
end
function proof.matches(path,adler,mod,algorithm)
 assert(path=='media/lua/client/ISUI/ISUIElement.lua'and adler==1904087254 and mod==nil and algorithm==true)
 s.sourceMatches=s.sourceMatches+1;return s.sourceOK
end
function proof.closure(callback,source)return type(callback)=='function'and source=='ISUIElement.lua'end
require=function(name)assert(name=='PZSurvivorToolkit/SourceProof');return proof end
function equipWorkNowMs()s.time=s.time+0.01;return s.time end
function equipWorkMark(stage)s.phase=stage;s.marks[#s.marks+1]=stage or false;return true end
function equipWorkSnapshot()return{schema=1,stage=s.phase,droppedCalls=0,droppedPaths=0}end
local front={name='front',isStarted=function()return true end}
local a,b,tail={name='a'},{name='b'},{name='tail'}
local queue={queue={front,a,b,tail},current=front}
local Panel={};Panel.__index=Panel
local panel=setmetatable({x=310,y=90,width=360,height=240,keepOnScreen=true,queue=queue},Panel)
function Panel:getX()return self.x end
function Panel:getY()return self.y end
function Panel:setX(value)self.x=value end
function Panel:setY(value)self.y=value end
function Panel:getIsVisible()return true end
local List={};List.__index=List;setmetatable(List,{__index=ISUIElement})
local list=setmetatable({parent=panel,width=344,height=180,offsetX=8,offsetY=30,scrollX=0,scrollY=0,items={}},List);panel.list=list
function List:cancelX()return self.width-40 end
function List:topOfItem(index)return(index-1)*24 end
function List:rowAt(x,y)return math.floor(y/24)+1 end
function List:rowUnderMouse(x,y)
 if x<0 or x>=self.width-14 or y<0 or y>=self.height then return end
 local row=self.items[self:rowAt(x,y)]
 if row and queue.queue[row.first]==row.item then return row end
end
function Panel:update()
 list.items={}
 for index,action in ipairs(self.queue.queue)do list.items[index]={item=action,index=index,first=index,last=index,height=24}end
end
panel:update()
function Panel.refresh()
 s.refreshCalls=s.refreshCalls+1
 if panel.queue~=queue then
  -- Native AddUI stages a replacement; getUI sees it only after a UI update.
  panel.queue=queue;s.registered=false;s.pendingRegistration=true
 end
end
PZSurvivorToolkit={ActionQueuePanel=Panel,ActionQueue={},ActionQueuePolicy={}}
local toolkit=PZSurvivorToolkit
function toolkit.ActionQueue.moveReason(q,action)assert(q==queue);return not s.canStart and 'unsupported' or nil end
function toolkit.ActionQueue.move(q,action,target,after)
 assert(q==queue and list.dragging and list.dragAction==action,'move did not originate from captured handler gesture')
 s.moves=s.moves+1
 if not s.canCommit then return false end
 local position
 for index,value in ipairs(q.queue)do if value==action then position=index end end
 table.remove(q.queue,assert(position))
 for index,value in ipairs(q.queue)do if value==target then table.insert(q.queue,index+(after and 1 or 0),action);return true end end
 error('missing move target')
end
function toolkit.ActionQueue.cancel(q,action)
 assert(q==queue and list.pressedCancel==action,'cancel did not originate from captured handler press')
 s.cancels=s.cancels+1
 if not s.canCommit then return false end
 for index,value in ipairs(q.queue)do if value==action then table.remove(q.queue,index);return true end end
 error('missing cancel item')
end
function toolkit.ActionQueuePolicy.evaluateCancel(q,action)return{allowed=s.canCommit,reason=not s.canCommit and 'unavailable' or nil}end
function toolkit.ActionQueuePolicy.evaluateMove(q,action,target,after)return{allowed=s.canCommit,reason=not s.canCommit and 'unavailable' or nil}end
local base={}
function base.onMouseDown(self,x,y)s.pressed=s.pressed+1;self.selected=self:rowAt(x,y)end
function base.onMouseMove(self,dx,dy)self.mouseoverselected=self:rowAt(self:getMouseX(),self:getMouseY())end
function base.onMouseUp(self,x,y)s.released=s.released+1 end
function base.onMouseUpOutside(self,x,y)s.outside=s.outside+1 end
local chunk=assert(loadstring('local List,Toolkit,ISScrollingListBox,cancelsOperation,cancelRejected=...\n'..panel_handlers..'\nreturn List'))
chunk(List,toolkit,base,function()return false end,function(self,row,reason)self.cancelFeedback=reason end)
local function delegate(self,y,row,alternate)
 assert(self==list and type(y)=='number'and row.item,'draw delegation arguments changed')
 s.draws=s.draws+1
 if self:isMouseOver()and self:rowUnderMouse(self:getMouseX(),self:getMouseY())==row then self.previewText={}end
 return y+row.height,nil,false
end
list.doDrawItem=delegate
UIManager={update=function()error('helper forced a native UI update')end,getUI=function()
 assert(s.refreshCalls>s.uiLookups,'native panel inventory looked up before production refresh')
 s.uiLookups=s.uiLookups+1
 return{size=function()return s.registered and 1 or 0 end,get=function(_,index)assert(index==0);return{getTable=function()return panel end}end}
end}
local W=assert(loadfile(work_path))()
assert(s.captureCalls==0,'module loading captured native bindings eagerly');s.apiReady=true;s.factory=W
s.proof=proof;s.work=W.new({mode=mode or'toolkit',kind='sp'});s.queue=queue;s.front=front;s.a=a;s.b=b;s.tail=tail;s.panel=panel;s.list=list;s.delegate=delegate
s.canCommit=true
function s:flushUi()
 if self.pendingRegistration then self.registered=true;self.pendingRegistration=false end
end
function s:draw()
 self:flushUi();self.panel:update()
 for index,row in ipairs(list.items)do
  local value,middle,last=list:doDrawItem((index-1)*24,row,false)
  assert(value==index*24 and middle==nil and last==false,'wrapper did not preserve delegated nil/multiple returns')
 end
end
function s:advance(milliseconds)self.time=self.time+milliseconds end
function s:assertPointer()
 assert(getMouseX()==170 and getMouseY()==260,'helper changed the stationary pointer')
 assert(ISUIElement.getMouseX==originalX and ISUIElement.getMouseY==originalY and ISUIElement.isMouseOver==originalOver)
 assert(list.getMouseX==originalX and list.getMouseY==originalY and list.isMouseOver==originalOver,'helper replaced base pointer getters')
end
return s
'''


class EquipWorkUiTests(unittest.TestCase):
    def model(self, mode='toolkit'):
        lua = LuaRuntime(unpack_returned_tuples=True)
        source = (PROJECT / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueuePanel.lua').read_text()
        lua.globals().panel_handlers = source[source.index('function List:clearGesture()'):source.index('function Panel.icon')]
        lua.globals().work_path = str(PROJECT / 'tests/native_queue/magazine-unload/client/QueueEquipWork.lua')
        lua.globals().mode = mode
        lua.globals().s = lua.execute(HARNESS)
        return lua

    def test_module_defers_binding_capture_until_ready_constructor_and_keeps_guards(self):
        self.model().execute(r'''
assert(s.captureCalls>0 and s.sourceMatches>0,'ready constructor did not capture/source-check native pointer methods')
s.sourceOK=false
local ok,reason=pcall(function()s.factory.new({mode='toolkit',kind='sp'})end)
assert(not ok and tostring(reason):find('native UI pointer source changed',1,true),'constructor ignored a changed native pointer source')
s.sourceOK=true;s.work:arm()
local saved=ISUIElement.getMouseX
ISUIElement.getMouseX=function(self)return saved(self)end
ok,reason=pcall(function()s.work:drag(s.queue,s.b,s.a,true)end)
assert(not ok and tostring(reason):find('native pointer getter replaced',1,true),'deferred capture did not retain initial getter identity')
assert(s.moves==0 and s.queue.queue[2]==s.a and s.queue.queue[3]==s.b and not s.work.result.cold)
ISUIElement.getMouseX=saved;s:assertPointer()
''')

    def test_large_inherited_ui_class_uses_selected_plain_dependencies(self):
        self.model().execute(r'''
assert(getmetatable(ISUIElement)==ISBaseObject and toolkitLuaMetatableMatches(ISBaseObject,nil))
local fields=0;for _ in pairs(ISUIElement)do fields=fields+1 end
assert(fields>128 and s.rejectedLargeOwner==0,'constructor tried to capture the oversized inherited UI class')
assert(s.proof.captureBindings({{owner=ISUIElement,keys={'getMouseX','getMouseY','isMouseOver'}}})==nil,
 'model widened inherited-owner captureBindings to hide the native class-size failure')
assert(s.rejectedLargeOwner==1)
s.work:arm();assert(s.work:drag(s.queue,s.b,s.a,true));s:assertPointer()
setmetatable(ISUIElement,{__index=ISBaseObject})
assert(not pcall(function()s.factory.new({mode='toolkit',kind='sp'})end),'lookalike UI parent gained native ancestry')
setmetatable(ISUIElement,ISBaseObject)
setmetatable(ISBaseObject,{})
assert(not pcall(function()s.factory.new({mode='toolkit',kind='sp'})end),'nonplain native base retained pointer proof')
setmetatable(ISBaseObject,nil)
ISBaseObject.getMouseX=function()error('base getter shadow executed')end
local ok,reason=pcall(function()s.factory.new({mode='toolkit',kind='sp'})end)
assert(not ok and tostring(reason):find('native UI pointer source changed',1,true),'selected base getter binding was not retained')
''')

    def test_stationary_pointer_alignment_and_real_handler_reorder(self):
        self.model().execute(r'''
s.work:arm();assert(s.work:drag(s.queue,s.b,s.a,true))
assert(s.queue.queue[1]==s.front and s.queue.queue[2]==s.b and s.queue.queue[3]==s.a and s.queue.queue[4]==s.tail)
assert(s.pressed==1 and s.released==1 and s.moves==1,'cold helper bypassed delegated handlers')
assert(s.refreshCalls==1 and s.uiLookups==1,'helper did not refresh before looking up the live panel')
assert(not s.list.dragAction and s.work.result.cold.nativeHitTesting and s.work.result.cold.committed)
assert(s.panel.x~=310 or s.panel.y~=90,'alignment did not move the owned model window')
s:assertPointer()
''')

    def test_new_queue_panel_waits_for_native_ui_inventory_registration(self):
        self.model().execute(r'''
s.panel.queue={queue={}}
assert(s.work:panelReady(s.queue)==false,'new AddUI staging was treated as immediate registration')
assert(s.refreshCalls==1 and s.uiLookups==1 and not s.registered and s.pendingRegistration)
assert(s.moves==0 and s.pressed==0 and s.queue.queue[2]==s.a and s.queue.queue[3]==s.b,'missing live UI manufactured a gesture')
assert(s.work.panel==nil and s.work.actions==nil and s.work.draw==nil and s.phase==nil,'readiness probe retained scene references or started timing')
-- This represents the framework's next native UI update, never a helper-forced update.
s:flushUi();assert(s.work:panelReady(s.queue)==true)
assert(s.refreshCalls==2 and s.uiLookups==2 and s.work.panel==nil)
s.work:arm();assert(s.work:drag(s.queue,s.b,s.a,true));assert(s.refreshCalls==3 and s.uiLookups==3)
s:assertPointer()
''')

    def test_refused_press_is_not_promoted_to_drag_capture_or_queue_mutation(self):
        self.model().execute(r'''
s.work:arm();s.canStart=false
local ok,reason=pcall(function()s.work:drag(s.queue,s.b,s.a,false)end)
assert(not ok and tostring(reason):find('native drag press did not capture action',1,true))
assert(s.pressed==1 and s.released==0 and s.moves==0 and not s.list.dragAction and not s.list.dragging)
assert(s.queue.queue[2]==s.a and s.queue.queue[3]==s.b and not s.work.result.cold,'refused press acquired gesture evidence')
s:assertPointer()
''')

    def test_draw_wrapper_delegates_then_restores_and_releases_scene_references(self):
        self.model().execute(r'''
s.work:arm();assert(s.work:drag(s.queue,s.b,s.a,true));assert(s.list.doDrawItem~=s.delegate)
local finished=false
for iteration=1,24 do
 s:advance(500);s:draw()
 if s.work:tick(s.queue,s.front)then finished=true;break end
end
assert(finished,'bounded model phases did not finish')
assert(s.draws>0 and s.work.result.observerReleased and s.list.doDrawItem==s.delegate)
assert(s.panel.x==310 and s.panel.y==90 and s.panel.keepOnScreen==true,'owned panel placement was not restored')
assert(s.work.actions==nil and s.work.panel==nil and s.work.position==nil and s.work.originalDraw==nil and s.work.draw==nil and s.work.stats==nil)
assert(s.work.stage==nil and s.phase==nil and not s.list.dragAction and not s.list.dragging)
assert(s.moves==1 and s.outside==1,'changing-target preview committed a second reorder')
local before=s.draws;s:draw();assert(s.draws>before,'restored delegate no longer draws')
s:assertPointer()
''')

    def test_cancel_uses_press_release_and_clears_panel_and_measurement_scope(self):
        self.model().execute(r'''
assert(s.work:cancel(s.queue,s.b,true))
assert(s.cancels==1 and s.pressed==0 and s.released==1 and s.queue.queue[3]==s.tail)
assert(s.work.result.cancel.committed and s.work.result.cancel.metrics.stage=='cancel-click')
assert(s.work.panel==nil and s.phase==nil and not s.list.pressedCancel)
assert(s.panel.x==310 and s.panel.y==90 and s.panel.keepOnScreen==true)
assert(s.list.doDrawItem==s.delegate,'cancel attached a persistent draw observer')
s:assertPointer()
''')

    def test_queue_disabled_model_never_attaches_panel_or_retains_it(self):
        self.model('native').execute(r'''
s.work:arm();s.work:native(s.queue);s:advance(2500)
assert(s.work:tick(s.queue,s.front))
assert(s.uiLookups==0 and s.refreshCalls==0 and s.draws==0 and s.moves==0 and s.cancels==0)
assert(s.work.result.observerReleased and s.work.panel==nil and s.work.actions==nil and s.work.draw==nil and s.work.stats==nil and s.phase==nil)
assert(s.panel.x==310 and s.panel.y==90 and s.list.doDrawItem==s.delegate)
s:assertPointer()
''')


if __name__ == '__main__': unittest.main()
