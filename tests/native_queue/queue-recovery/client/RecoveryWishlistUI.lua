-- Programmatic native window lifecycle; timings gate observations, not FPS.
require 'PZSurvivorWishlist/UI'
local C,UI=PZSurvivorWishlist.Client,PZSurvivorWishlist.UI
local Gate={}
local TYPE='Base.BookCarpentry1'
local function now()return getTimestampMs()end
local function empty(t)for _ in pairs(t)do return false end;return true end
local function own(t,key)for k,v in pairs(t)do if k==key then return v end end end
function Gate:observe(owner,key,counter)
 local original,raw=assert(owner[key]),own(owner,key)
 local wrapper=function(...)self.counts[counter]=self.counts[counter]+1;return original(...)end
 owner[key]=wrapper;self.restores[#self.restores+1]={owner,key,raw,wrapper}
 return original
end
function Gate:reset(stage)
 self.stage=stage;self.since=now();self.draws=0
 self.counts={carried=0,rows=0,selector=0}
end
function Gate.new()
 local g=setmetatable({stage='sync',since=now(),started=now(),restores={},counts={carried=0,rows=0,selector=0},draws=0,result={}},{__index=Gate})
 C.sync(0);return g
end
function Gate:collapse()
 local w=self.window
 -- Place the window away from the current pointer without moving input/focus.
 w:setX(getMouseX()>=20 and getMouseX()<=620 and 660 or 20)
 w:collapse()
 for _=1,40 do if not w.isCollapsed then w:onMouseMoveOutside(0,0)end end
 assert(w.isCollapsed,'native mouse-exit did not collapse Wishlist')
end
function Gate:expand()
 local w=self.window;local x,y,keep=w:getX(),w:getY(),own(w,'keepOnScreen')
 assert(not w.moving,'native Wishlist drag is active')
 -- Native setX/setY otherwise clamp against the full expanded window size,
 -- leaving a low/right pointer outside the title bar. Move only this fixture
 -- window, then verify native local coordinates before the real hover handler.
 w.keepOnScreen=false
 local ok,error=pcall(function()
  w:setX(x+w:getMouseX()-w:getWidth()/2)
  w:setY(y+w:getMouseY()-w:titleBarHeight()/2)
  local mx,my=w:getMouseX(),w:getMouseY()
  assert(mx>=0 and mx<w:getWidth()and my>=0 and my<w:titleBarHeight(),
   'native title hover alignment failed x='..tostring(mx)..' y='..tostring(my))
  w:onMouseMove(0,0)
  assert(not w.isCollapsed,'native title hover did not expand Wishlist')
  -- Restoring its position moves the title away from the pointer again.
  -- Pin only after native expansion succeeds, before the first expanded draw.
  ISCollapsableWindow.pin(w)
 end)
 w:setX(x);w:setY(y);w.keepOnScreen=keep
 assert(ok,error)
end
function Gate:row()
 local rows=self.window.list.items
 assert(#rows==1 and rows[1].item.fullType==TYPE,'Wishlist rows differ from the authoritative list')
 return rows[1].item
end
function Gate:sample()
 assert(self.draws>=10 and now()-self.since>=1500,'insufficient native UI observation')
 assert(self.counts.carried==0 and self.counts.rows==0 and self.counts.selector==0,'idle Wishlist body performed work')
 return {elapsedMs=now()-self.since,draws=self.draws,carriedCalls=self.counts.carried,rowClears=self.counts.rows,selectorClears=self.counts.selector}
end
function Gate:draw()
 if not self.window or not self.window:getIsVisible()then return end
 self.draws=self.draws+1
 if self.stage=='expanded'then
  local row=self:row();local count=self.originalCarried(0)[TYPE]or 0
  assert(row.amount==7 and count>0 and row.detail==getText('UI_PZSW_Carried',count)..'  |  '..TYPE,'first expanded draw is stale')
  self.result.expanded={amount=7,carried=count,firstDrawFresh=true}
  self.window:close();self.window=UI.open(0);self:reset('reopened')
 elseif self.stage=='reopened'then
  assert(self:row().amount==7 and self.counts.carried>0,'reopened Wishlist did not refresh')
  self.result.reopened=true;assert(C.edit(0,'remove',{fullType=TYPE}));self:reset('removed')
 end
end
function Gate:tick()
 assert(now()-self.started<30000,'Wishlist UI workload timeout '..self.stage)
 local state=C.state(0);assert(not state.error,'Wishlist request failed '..tostring(state.error))
 local list=C.selected(0)
 if self.stage=='sync'then
  if not list or not state.username or state.pending then return end
  assert(list.owner==state.username and empty(list.entries),'fresh personal Wishlist must be empty')
  self.window=UI.open(0)
  self.originalCarried=self:observe(C,'carried','carried')
  self:observe(self.window.list,'clear','rows');self:observe(self.window.selector,'clear','selector')
  self:reset('settle')
 elseif self.stage=='settle'and now()-self.since>=1000 and self.draws>=10 then self:reset('empty')
 elseif self.stage=='empty'and now()-self.since>=1700 and self.draws>=10 then
  self.result.empty=self:sample();assert(C.addItem(0,TYPE,1));self:reset('added')
 elseif self.stage=='added'and list and list.entries[TYPE]and not state.pending and self.draws>0 and #self.window.list.items==1 then
  assert(self:row().amount==1 and self.counts.carried>0,'populated open Wishlist did not count')
  self:collapse();assert(C.edit(0,'set',{fullType=TYPE,amount=7}));self:reset('changed')
 elseif self.stage=='changed'and list and list.entries[TYPE]and list.entries[TYPE].amount==7 and not state.pending then
  assert(self.window.isCollapsed);self:reset('collapsed')
 elseif self.stage=='collapsed'and now()-self.since>=1700 and self.draws>=10 then
  assert(self.window.isCollapsed);self.result.collapsed=self:sample();self:expand();self:reset('expanded')
 elseif self.stage=='removed'and list and empty(list.entries)and not state.pending and self.draws>0 and #self.window.list.items==0 then
  self:reset('removed-idle')
 elseif self.stage=='removed-idle'and now()-self.since>=800 and self.draws>=10 then
  assert(self.counts.carried==0,'empty result still counted inventory')
  self.window:close()
  for _,entry in ipairs(self.restores)do assert(entry[1][entry[2]]==entry[4]);entry[1][entry[2]]=entry[3]end
  self.result.removed,self.result.restored=true,true;return self.result
 end
end
return Gate
