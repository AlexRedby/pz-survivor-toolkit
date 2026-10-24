-- Transient diagnostics control: no saved recording preference and no polling renewal.
local options = {buttons={}, titles={}}
function options:addTitle(title) self.titles[#self.titles+1]=title end
function options:addButton(id, title, tip, callback)
    self.buttons[id]={callback=callback, title=title, tip=tip}
end
PZAPI={ModOptions={getOptions=function() return options end}}
require=function() end
getText=function(key) return key end
UIFont={Small=1}
getTextManager=function() return {getFontHeight=function() return 16 end} end
getCore=function() return {getScreenWidth=function() return 1280 end} end
ISCollapsableWindow={}
function ISCollapsableWindow:derive()
    local class={};class.__index=class;return setmetatable(class,{__index=self})
end
function ISCollapsableWindow:new(x,y,w,h)
    return setmetatable({x=x,y=y,width=w,height=h},self)
end
function ISCollapsableWindow:initialise() end
function ISCollapsableWindow:instantiate() self:createChildren() end
function ISCollapsableWindow:createChildren() end
function ISCollapsableWindow:addChild(child) child.parent=self end
function ISCollapsableWindow:addToUIManager() self.visible=true end
function ISCollapsableWindow:bringToTop() self.top=true end
function ISCollapsableWindow:prerender() end
function ISCollapsableWindow:close() self.visible=false end
function ISCollapsableWindow:removeFromUIManager() self.removed=true end
function ISCollapsableWindow:titleBarHeight() return 24 end
function ISCollapsableWindow:resizeWidgetHeight() return 12 end
function ISCollapsableWindow:setHeight(h) self.height=h end
ISTickBox={}
function ISTickBox:new(x,y,w,h,_,target,callback)
    local box={x=x,y=y,width=w,height=h,target=target,callback=callback}
    function box:initialise() end
    function box:addOption(name) self.name=name end
    function box:setSelected(index,value) assert(index==1);self.selected=value end
    function box:disableOption(name,value) assert(name==self.name);self.disabled=value end
    function box:click(value) assert(not self.disabled);self.callback(self.target,1,value) end
    return box
end
ISRichTextPanel={}
function ISRichTextPanel:new(x,y,w,h)
    return {x=x,y=y,width=w,height=h,initialise=function() end,
        paginate=function(self) self.height=210 end,getHeight=function(self) return self.height end}
end
local Window=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleDiagnostics.lua')
assert(options.buttons.VehicleDiagnostics and not options.addTickBox,'only entry button belongs in saved settings')
local missing=options.buttons.VehicleDiagnostics.callback()
assert(missing.traceStatus=='unavailable' and missing.record.disabled)
missing:close()
local status,calls='off',{}
toolkitVehicleTraceStatus=function() return status end
toolkitVehicleTraceSet=function(value) calls[#calls+1]=value;status=value and 'active' or 'off';return status end
local window=Window.show()
assert(window.traceStatus=='off' and not window.record.selected and not window.record.disabled)
window.record:click(true)
assert(window.traceStatus=='active' and window.record.selected and #calls==1)
for i=1,100 do window:prerender() end
assert(#calls==1,'rendering must not renew or restart recording')
window:close()
assert(status=='active' and #calls==1,'closing the window leaves bounded recording running')
assert(window.removed,'closed windows must not accumulate in the UI manager')
window=Window.show()
assert(window.record.selected,'reopening reflects the actual process status')
status='expired';window:prerender()
assert(not window.record.selected and not window.record.disabled)
window.record:click(true)
assert(#calls==3 and calls[2]==false and calls[3]==true and window.traceStatus=='active')
window.record:click(false)
assert(status=='off' and not window.record.selected)
status='unsupported';window:prerender()
assert(window.record.disabled and not window.record.selected)
status='unexpected';window:prerender()
assert(window.traceStatus=='error' and window.record.disabled)
status='off';window:prerender()
toolkitVehicleTraceSet=function() error('bridge failure') end
window.record:click(true)
assert(not window.record.disabled and not window.record.selected and window.info.text:find('error'))
window:prerender()
assert(not window.record.disabled,'a temporary setter failure must allow retry')
toolkitVehicleTraceSet=function(value) status=value and 'active' or 'off';error('failure after side effect') end
window.record:click(true)
assert(window.record.selected and window.traceStatus=='active','show actual recording even if setter throws after starting')
toolkitVehicleTraceSet=function(value) status=value and 'active' or 'off';return status end
window.record:click(false)
assert(not window.record.selected and not window.operationError and window.traceStatus=='off')
window:close()
toolkitVehicleTraceStatus=function() error('status failure') end
assert(Window.show().traceStatus=='error')
print('PASS vehicle diagnostics: transient checkbox, status, limits, restart, missing/error bridge')
