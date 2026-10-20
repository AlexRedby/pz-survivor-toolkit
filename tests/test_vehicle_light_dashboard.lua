local start
local scaleKey = '1x'
YourDash = {GetScaleKey=function() return scaleKey end}
local sizes = {
 standard={{15,12},{21,16},{28,21},{40,31}},
 heavy={{23,18},{30,24},{42,34},{60,48}},
 sport={{71,67},{94,89},{132,125},{188,178}},
}
local scales = {'0.75x','1x','1.4x','2x'}
local highTextures = {}
for family, variants in pairs(sizes) do
 for index, size in ipairs(variants) do
  local w,h=size[1],size[2]
  highTextures['media/ui/PZSurvivorToolkit/beams/'..family..'/'..scales[index]..'/high.png'] = {
   getWidthOrig=function() return w end,getHeightOrig=function() return h end}
 end
end
getTexture=function(path) return highTextures[path] end
getActivatedMods=function() return {contains=function(_,id) return id=='NepHighBeams' end} end
require=function() end
getText=function(k) return k end
getCore=function() return {getBadHighlitedColor=function() return {getR=function() return .9 end,getG=function() return .1 end,getB=function() return .2 end} end} end
Events={OnGameStart={Add=function(fn) start=fn end}}
PZSurvivorToolkit={}
ISVehicleDashboard={prerender=function() end}
dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleLightDashboard.lua')
local D=PZSurvivorToolkit.VehicleLightDashboard
local v={on=false,charge=1,data={},getHeadlightsOn=function(self) return self.on end,
 getBatteryCharge=function(self) return self.charge end,getModData=function(self) return self.data end,
 getHeadlightCanEmmitLight=function() return true end}
assert(D.mode(nil)=='off' and D.mode(v)=='off')
v.on=true;assert(D.mode(v)=='low');v.data.NepHB={highBeamsOn=true};assert(D.mode(v)=='high')
v.on=false;assert(D.mode(v)=='off','stored high selection must not show high with lamps off')
v.on=true;v.charge=0;assert(D.mode(v)=='off','no powered indicator with empty battery');v.charge=1
local function image(w,h)
 local o={x=12,y=34,width=w,height=h,backgroundColor={r=1,g=1,b=1,a=.37},texture={getWidthOrig=function() return w end,getHeightOrig=function() return h end},onclick='nativeClick',target='nativeTarget',draws={}}
 function o:drawLine() error('Do not replace authored soft artwork with vector lines') end
 function o:drawTextureScaled(...) self.draws[#self.draws+1]={...} end
 function o:prerender()
  self.nativePre=true;self.stockPainted=self.texture~=nil
  if self.texture then local c=self.backgroundColor;self:drawTextureScaled(self.texture,0,0,self.width,self.height,c.a,c.r,c.g,c.b) end
 end
 function o:render() self.nativeRender=true;self.renderTexture=self.texture end
 function o:getX() return self.x end
 function o:getY() return self.y end
 function o:setX(x) self.x=x end
 function o:setY(y) self.y=y end
 function o:setWidth(w) self.width=w end
 function o:setHeight(h) self.height=h end
 function o:onMouseUp(x,y) if self.onclick then return self.onclick(self.target,self) end end
 return o
end
for _,family in ipairs({'standard','heavy','sport'}) do
 for index,key in ipairs(scales) do
  scaleKey=key
  local size=sizes[family][index]
  local lamp=image(size[1],size[2]); local originalTexture=lamp.texture
  local highTexture=getTexture('media/ui/PZSurvivorToolkit/beams/'..family..'/'..key..'/high.png')
  if family=='heavy' then lamp.__offTexture='nativeOff' end
  local nativePre=lamp.prerender
  local knob=image(40,40);local knobTexture=knob.texture
  local dash={vehicle=v,warnLightTex=lamp,lightsTex=knob,__YourDashFamily=family,__warn_light=originalTexture}
  D.bind(dash);local render=lamp.render;local knobPre=knob.prerender;local knobRender=knob.render
  D.bind(dash);assert(lamp.render==render and knob.prerender==knobPre,'do not nest hooks per frame')
  knob.backgroundColor={r=.2,g=.3,b=1,a=.65}
  knob:prerender();knob:render()
  assert(knob.nativePre and not knob.stockPainted,'no blue duplicate underneath the authored switch')
  assert(knob.render==knobRender and knob.renderTexture==knobTexture and knob.texture==knobTexture,'keep authored switch render and texture')
  assert(knob.backgroundColor.a==.65 and knob.width==40 and knob.height==40 and knob.onclick=='nativeClick','keep switch state/hitbox/control')
  lamp:prerender();lamp:render()
  assert(lamp.prerender==nativePre and lamp.stockPainted,'keep the original warning prerender and soft alpha pass')
  local high=lamp.draws[#lamp.draws]
  assert(high[1]==highTexture and high[2]==0 and high[3]==0 and high[4]==size[1] and high[5]==size[2],'matching horizontal high PNG, original bounds and scale')
  assert(high[6]==.37 and high[7]==1 and high[8]==1 and high[9]==1,'high retains original untinted blue and native fade')
  assert(lamp.draws[1][1]==highTexture and lamp.draws[1][7]==1 and lamp.draws[1][8]==1 and lamp.draws[1][9]==1,'both native high passes match original')
  if lamp.__offTexture then assert(lamp.draws[2][1]=='nativeOff' and lamp.draws[2][6]==1,'retain native unlit heavy artwork') end
  v.data.NepHB.highBeamsOn=false;D.bind(dash);lamp.draws={};lamp:prerender();lamp:render()
  local low=lamp.draws[#lamp.draws]
  assert(low[1]==originalTexture and lamp.draws[1][1]==originalTexture and low[4]==high[4] and low[5]==high[5] and low[6]==high[6],'low keeps original pixels, dimensions and alpha')
  assert(low[7]==.4 and low[8]==1 and low[9]==.35 and lamp.draws[1][7]==.4 and lamp.draws[1][9]==.35,'tint BOTH native passes green without blue underlay')
  assert(lamp.x==12 and lamp.y==34,'do not move or resize the native slot')
  v.on=false;D.bind(dash);lamp.backgroundColor.a=.05;lamp.draws={};lamp:render()
  assert(lamp.draws[#lamp.draws][6]==.05 and lamp.draws[#lamp.draws][8]==1,'retain the native last-mode fade-out')
  v.on=true;v.data.NepHB.highBeamsOn=true
 end
end
local native=image(60,60);local nativeTexture=native.texture;local dash={vehicle=v,lightsTex=native};local originalPre=native.prerender
D.bind(dash);native:prerender()
assert(native.prerender==originalPre and native.stockPainted and native.texture==nativeTexture,'stock fallback keeps its original artwork/render')
v.getHeadlightCanEmmitLight=function() return false end
native.backgroundColor={r=.2,g=.3,b=1,a=.37};D.bind(dash);native.draws={};native:prerender()
local bad=native.draws[1];assert(bad[7]==.9 and bad[8]==.1 and bad[9]==.2,'preserve native failure color after Nep tint')
local failedSwitch=image(40,40);local failedTexture=failedSwitch.texture;failedSwitch.prerender=function() error('switch failure') end
D.bind({vehicle=v,warnLightTex=image(21,16),lightsTex=failedSwitch})
local switchOK=pcall(failedSwitch.prerender,failedSwitch)
assert(not switchOK and failedSwitch.texture==failedTexture,'restore physical switch texture on upstream error')
-- A live dashboard can change texture set without replacing the warning image.
scaleKey='1x';v.getHeadlightCanEmmitLight=function() return true end
local changing=image(21,16);local changingDash={vehicle=v,warnLightTex=changing,__YourDashFamily='standard',__warn_light=changing.texture}
D.bind(changingDash);local oldHigh=changing.texture
scaleKey='2x';local newer=image(188,178).texture
changingDash.__YourDashFamily='sport';changingDash.__warn_light=newer;changing.width=188;changing.height=178
D.bind(changingDash);assert(changing.texture~=oldHigh and changing.texture:getWidthOrig()==188,'refresh high after family/scale switch')
v.on=false;D.bind(changingDash);assert(changing.texture==changing.__toolkitBeamHighTexture,'high retains its matching texture during native fade-out')
v.on=true;v.data.NepHB.highBeamsOn=false;D.bind(changingDash);assert(changing.texture==newer,'restore current original on low')
v.data.NepHB.highBeamsOn=true
local missing=image(21,16);local missingOriginal=missing.texture
D.bind({vehicle=v,warnLightTex=missing,__YourDashFamily='unknown'})
assert(missing.texture==missingOriginal,'missing high artwork falls back to original')
local wrong=image(22,17);local wrongOriginal=wrong.texture;scaleKey='1x'
D.bind({vehicle=v,warnLightTex=wrong,__YourDashFamily='standard'})
assert(wrong.texture==wrongOriginal,'do not distort an unmatched native warning texture')
-- The STANDARD control cycles power through the existing dashboard callback
-- and changes beam state through Nep's public API, not a parallel selection.
local speed, speedResets, nativeClicks, activations, deactivations = 1, 0, 0, 0, 0
getGameSpeed=function() return speed end
setGameSpeed=function(value) speed=value;speedResets=speedResets+1 end
NepHBO7={
 activateHighBeams=function(vehicle) activations=activations+1;vehicle.data.NepHB.highBeamsOn=true end,
 deactivateHighBeams=function(vehicle) deactivations=deactivations+1;vehicle.data.NepHB.highBeamsOn=false end,
}
v.on=false;v.charge=1;v.data.NepHB.highBeamsOn=true
local rotary=image(48,33)
local rotaryNativeRender=rotary.render
local requestedPower
local rotaryDash={vehicle=v,character={},lightsTex=rotary,warnLightTex=image(21,16),__YourDashFamily='standard',draws={}}
-- YourDash's native alarm/pending state contract. Actual power acknowledges
-- separately, so a click cannot be mistaken for an already received command.
function rotaryDash:_YourDashGetHeadlightSwitchState()
 if self.alarm then
  if self.__YourDashHeadlightSwitchOn==nil then self.__YourDashHeadlightSwitchOn=v.on end
  return self.__YourDashHeadlightSwitchOn==true
 end
 if (self.__YourDashHeadlightSwitchPending or 0)>0 and v.on~=(self.__YourDashHeadlightSwitchOn==true) then
  return self.__YourDashHeadlightSwitchOn==true
 end
 self.__YourDashHeadlightSwitchPending=0;self.__YourDashHeadlightSwitchOn=v.on
 return v.on
end
function rotaryDash:drawTextureScaled(...) self.draws[#self.draws+1]={...} end
local function nativeClick(dash)
 if getGameSpeed()==0 then return end
 dash.__YourDashHeadlightSwitchOn=not dash:_YourDashGetHeadlightSwitchState()
 dash.__YourDashHeadlightSwitchPending=1
 if getGameSpeed()>1 then setGameSpeed(1) end
 -- Exact native onToggleHeadlights command: it reads actual power, never the
 -- optimistic switch cache above. Simulate its acknowledgement separately.
 nativeClicks=nativeClicks+1;requestedPower=not v.on
end
rotary.onclick=nativeClick;rotary.target=rotaryDash
scaleKey='1x'
local mark={getWidthOrig=function() return 98 end,getHeightOrig=function() return 133 end}
rotaryDash.backgroundTex=image(745,172)
highTextures['media/ui/PZSurvivorToolkit/beams/standard/1x/light-panel.png']=mark
D.bind(rotaryDash)
local rotaryClick, rotaryRender=rotary.onclick,rotary.render
assert(rotaryClick~=nativeClick and rotaryDash.__lightKnobAngle==0,'standard has a third-position callback, begins at OFF even if Nep remembered high')
D.bind(rotaryDash)
assert(rotary.onclick==rotaryClick and rotary.render==rotaryRender,'do not nest rotary hooks per frame')
rotary:render()
local label=rotaryDash.draws[1]
assert(rotary.nativeRender and label[1]==mark and label[4]==98 and label[5]==133,'keep authored knob render and native faceplate patch dimensions')
assert(label[2]==rotaryDash.backgroundTex.x and label[3]==rotaryDash.backgroundTex.y,'anchor printed symbols to the actual faceplate')
assert(label[6]==1 and label[7]==nil,'preserve original neutral print colour and soft edges')
local knobSizes={{36,24},{48,33},{66,45},{95,65}}
local nominalScales={.75,1,1.4,2}
for index,key in ipairs(scales) do
 scaleKey=key
 local size=sizes.standard[index]
 highTextures['media/ui/PZSurvivorToolkit/beams/standard/'..key..'/light-panel.png']={
  getWidthOrig=function() return math.floor(98*nominalScales[index]+.5) end,getHeightOrig=function() return math.floor(133*nominalScales[index]+.5) end}
 rotary.width=knobSizes[index][1];rotary.height=knobSizes[index][2]
 rotary.x=66*nominalScales[index];rotary.y=130*nominalScales[index]
 rotaryDash.draws={};D.bind(rotaryDash);rotary:render()
 local scaledMark=rotaryDash.draws[1]
 assert(scaledMark[4]==math.floor(98*nominalScales[index]+.5),'patch uses active authored export size')
 assert(scaledMark[2]==rotaryDash.backgroundTex.x and scaledMark[3]==rotaryDash.backgroundTex.y,'patch stays background-relative at every scale')
end
scaleKey='1x';rotary.width=48;rotary.height=33;rotary.x=12;rotary.y=34

speed=4;rotary.onclick(rotaryDash);D.bind(rotaryDash)
assert(nativeClicks==1 and deactivations==1 and activations==0 and requestedPower==true,'OFF -> LOW clears remembered high and uses native power callback exactly once')
assert(speed==1 and speedResets==1 and rotaryDash.__lightKnobAngle==45 and not v.on,'pending native command immediately turns knob to LOW')
rotary.onclick(rotaryDash);rotary.onclick(rotaryDash);D.bind(rotaryDash)
assert(nativeClicks==1 and deactivations==1 and activations==0 and requestedPower==true,'rapid clicks before ON acknowledgement send no duplicate power command or beam change')
assert(rotaryDash.__lightKnobAngle==45 and rotaryDash.__YourDashHeadlightSwitchOn==true,'pending ON keeps the optimistic LOW selection')
v.on=true;D.bind(rotaryDash)
assert(rotaryDash.__YourDashHeadlightSwitchPending==0 and D.mode(v)=='low','acknowledged native power yields low')
speed=3;rotary.onclick(rotaryDash);D.bind(rotaryDash)
assert(activations==1 and nativeClicks==1 and v.on and D.mode(v)=='high','LOW -> HIGH uses Nep API without toggling native power')
assert(speed==1 and speedResets==2 and rotaryDash.__lightKnobAngle==90,'HIGH has its own rotary position and native fast-forward behavior')
rotary.onclick(rotaryDash);D.bind(rotaryDash)
assert(nativeClicks==2 and deactivations==2 and requestedPower==false and not v.data.NepHB.highBeamsOn,'HIGH -> OFF restores low beam geometry and requests native power off')
assert(rotaryDash.__lightKnobAngle==0 and v.on,'pending native off remains at OFF before authoritative acknowledgement')
rotary.onclick(rotaryDash);rotary.onclick(rotaryDash);D.bind(rotaryDash)
assert(nativeClicks==2 and deactivations==2 and activations==1 and requestedPower==false,'rapid clicks before OFF acknowledgement cannot send ON again or change beams')
assert(rotaryDash.__lightKnobAngle==0 and rotaryDash.__YourDashHeadlightSwitchOn==false,'pending OFF preserves optimistic OFF selection')
v.on=false;D.bind(rotaryDash)
-- An expired upstream pending timer must recover from a lost/rejected command
-- using actual power rather than leave the rotary permanently locked.
local expiryNative,expiryHigh,expiryLow=nativeClicks,activations,deactivations
rotary.onclick(rotaryDash)
assert(nativeClicks==expiryNative+1 and requestedPower==true and not v.on,'expiry setup sends native ON while actual power remains off')
rotaryDash.__YourDashHeadlightSwitchPending=0
rotary.onclick(rotaryDash);D.bind(rotaryDash)
assert(nativeClicks==expiryNative+2 and requestedPower==true and activations==expiryHigh and deactivations==expiryLow+2,'expired ON resyncs to actual OFF and permits native ON retry')
v.on=true;D.bind(rotaryDash);rotary.onclick(rotaryDash);rotary.onclick(rotaryDash)
assert(nativeClicks==expiryNative+3 and requestedPower==false and v.on,'expiry setup sends native OFF while actual power remains on')
rotaryDash.__YourDashHeadlightSwitchPending=0
rotary.onclick(rotaryDash);D.bind(rotaryDash)
assert(nativeClicks==expiryNative+3 and activations==expiryHigh+2 and rotaryDash.__lightKnobAngle==90,'expired OFF resyncs to actual LOW and permits Nep HIGH without another power command')
v.on=false;v.data.NepHB.highBeamsOn=false;rotaryDash.__YourDashHeadlightSwitchPending=0;D.bind(rotaryDash)
-- Native key/radial power and Nep key/radial beams remain the source of truth.
v.on=true;D.bind(rotaryDash);assert(rotaryDash.__lightKnobAngle==45,'external headlights on reflects LOW')
v.data.NepHB.highBeamsOn=true;D.bind(rotaryDash);assert(rotaryDash.__lightKnobAngle==90,'external Nep high reflects HIGH')
v.data.NepHB.highBeamsOn=false;D.bind(rotaryDash);assert(rotaryDash.__lightKnobAngle==45,'external Nep low reflects LOW')
v.on=false;D.bind(rotaryDash);assert(rotaryDash.__lightKnobAngle==0,'external power off reflects OFF')
local beforeNative,beforeHigh,beforeLow=nativeClicks,activations,deactivations
speed=0;rotary.onclick(rotaryDash);D.bind(rotaryDash)
assert(nativeClicks==beforeNative and activations==beforeHigh and deactivations==beforeLow and rotaryDash.__lightKnobAngle==0,'paused OFF click changes neither API nor optimistic state')
v.on=true;v.data.NepHB.highBeamsOn=false;D.bind(rotaryDash);rotary.onclick(rotaryDash)
assert(activations==beforeHigh and not v.data.NepHB.highBeamsOn,'paused LOW click cannot activate high')
v.data.NepHB.highBeamsOn=true;D.bind(rotaryDash);rotary.onclick(rotaryDash)
assert(nativeClicks==beforeNative and deactivations==beforeLow and v.data.NepHB.highBeamsOn,'paused HIGH click cannot power off or clear high')
speed=1;v.charge=0;D.bind(rotaryDash)
assert(D.mode(v)=='off' and rotaryDash.__lightKnobAngle==90,'unpowered warning is off while physical selector stays HIGH')
v.charge=1
-- Alarm flashes must never rotate the physical selection. The native callback
-- still owns its optimistic cache when the driver changes power during alarm.
rotaryDash.alarm=true;rotaryDash.__YourDashHeadlightSwitchOn=true
v.on=false;D.bind(rotaryDash);assert(rotaryDash.__lightKnobAngle==90,'alarm dark phase preserves HIGH selection')
v.on=true;D.bind(rotaryDash);assert(rotaryDash.__lightKnobAngle==90,'alarm bright phase preserves HIGH selection')
rotary.onclick(rotaryDash);D.bind(rotaryDash)
assert(nativeClicks==beforeNative+1 and rotaryDash.__YourDashHeadlightSwitchOn==false and rotaryDash.__lightKnobAngle==0,'alarm power click uses native optimistic cache')
v.on=false;D.bind(rotaryDash);v.on=true;D.bind(rotaryDash)
assert(rotaryDash.__lightKnobAngle==0,'alarm flashes after click preserve OFF selection')
rotaryDash.alarm=false;rotaryDash.__YourDashHeadlightSwitchPending=0
rotaryDash.backgroundTex=nil -- This fallback case has no heavy rocker artwork.
for _,family in ipairs({'heavy','sport'}) do
 rotaryDash.__YourDashFamily=family;D.bind(rotaryDash)
 assert(rotary.render==rotaryNativeRender,'family switch restores native heavy/sport rendering')
 if family=='sport' then
  assert(rotary.onclick==rotary.__toolkitBeamPushClick and rotary.__toolkitBeamPushNativeClick==nativeClick,'standard to sport installs the push cycle around the native callback')
 else
  assert(rotary.onclick==nativeClick,'heavy without rocker art retains native callback')
 end
end
rotaryDash.__YourDashFamily='standard';D.bind(rotaryDash)
assert(rotary.onclick~=nativeClick,'returning to STANDARD reinstalls rotary control')
local originalApi=NepHBO7;NepHBO7=nil;D.bind(rotaryDash)
assert(rotary.onclick==nativeClick and rotary.render==rotaryNativeRender,'missing Nep API keeps native power control and artwork')
NepHBO7=originalApi
rotaryDash.vehicle=nil;D.onClickRotary(rotaryDash,nativeClick)
assert(nativeClicks==beforeNative+1,'detached standard control performs no action')
-- The sport button cycles through the same three selections, while its native
-- image, bulb/six-dot panel and momentary press/release rendering stay intact.
v.on=false;v.data.NepHB.highBeamsOn=true;speed=1
local push=image(94,89);local pushTexture=push.texture
local pushPanel=image(735,180);local pushPanelTexture=pushPanel.texture
local pushPanelRender=pushPanel.render
local pushImageUp=push.onMouseUp
function push:onMouseDown(x,y) self.pressed=true;return true end
function push:onMouseUp(x,y)
 self.pressed=false;self.releaseX=x;self.releaseY=y
 return pushImageUp(self,x,y)
end
function push:render()
 self.nativeRender=true
 self.paintedWidth=self.width*(self.pressed and .9 or 1)
 self.renderTexture=self.texture
end
local pushNativeRender,pushNativeDown,pushNativeUp=push.render,push.onMouseDown,push.onMouseUp
local sport={vehicle=v,character={},lightsTex=push,warnLightTex=image(94,89),backgroundTex=pushPanel,
 __YourDashFamily='sport',__lightKnobAngle=17,_YourDashGetHeadlightSwitchState=rotaryDash._YourDashGetHeadlightSwitchState}
push.onclick=nativeClick;push.target=sport
D.bind(sport)
local pushClick,pushPre=push.onclick,push.prerender
D.bind(sport)
assert(push.onclick==pushClick and push.prerender==pushPre and pushClick==push.__toolkitBeamPushClick,'repeated sport binding does not nest the cycle callback')
assert(push.__toolkitBeamPushNativeClick==nativeClick and push.target==sport,'sport wrapper retains native callback and ISImage target')
assert(push.render==pushNativeRender and push.onMouseDown==pushNativeDown and push.onMouseUp==pushNativeUp,'sport preserves native render and press/release handlers')
assert(push.texture==pushTexture and push.x==12 and push.y==34 and push.width==94 and push.height==89,'sport preserves native button texture, position and hitbox')
assert(pushPanel.render==pushPanelRender and pushPanel.texture==pushPanelTexture and sport.__lightKnobAngle==17,'sport preserves bulb/six-dot artwork without rotary panel or angle changes')
local function sportClick()
 push:onMouseDown(23,37);push:prerender();push:render()
 assert(push.pressed and math.abs(push.paintedWidth-84.6)<.0001 and push.renderTexture==pushTexture,'native sport press keeps its momentary rendering')
 push:onMouseUp(23,37);D.bind(sport);push:render()
 assert(not push.pressed and push.paintedWidth==94 and push.releaseX==23 and push.releaseY==37,'native sport release restores the unpressed button')
end
local pn,pa,pd,ps=nativeClicks,activations,deactivations,speedResets
speed=4;sportClick()
assert(nativeClicks==pn+1 and deactivations==pd+1 and activations==pa and requestedPower==true,'sport OFF -> LOW clears remembered high and requests native ON once')
assert(speed==1 and speedResets==ps+1 and not v.on and D.switchMode(sport)=='low','sport uses optimistic LOW and native fast-forward reset before ON ACK')
sportClick();sportClick()
assert(nativeClicks==pn+1 and deactivations==pd+1 and activations==pa,'sport pending ON ignores repeated releases without extra power or beam changes')
v.on=true;D.bind(sport)
assert(D.switchMode(sport)=='low' and sport.__YourDashHeadlightSwitchPending==0 and D.mode(v)=='low','sport acknowledges native ON as LOW')
speed=3;sportClick()
assert(nativeClicks==pn+1 and activations==pa+1 and v.on and D.mode(v)=='high','sport LOW -> HIGH uses Nep API without a native power toggle')
assert(speed==1 and speedResets==ps+2,'sport beam-only step preserves native fast-forward behavior')
sportClick()
assert(nativeClicks==pn+2 and deactivations==pd+2 and requestedPower==false and v.on and D.switchMode(sport)=='off','sport HIGH -> OFF clears high and awaits native OFF ACK')
sportClick();sportClick()
assert(nativeClicks==pn+2 and deactivations==pd+2 and activations==pa+1,'sport pending OFF cannot accidentally request ON again')
v.on=false;D.bind(sport)
assert(D.switchMode(sport)=='off' and sport.__YourDashHeadlightSwitchPending==0,'sport acknowledges native OFF')
-- The shared cycle must also recover when native pending power expires.
pn,pa,pd=nativeClicks,activations,deactivations
sportClick();sport.__YourDashHeadlightSwitchPending=0;sportClick()
assert(nativeClicks==pn+2 and requestedPower==true and activations==pa and deactivations==pd+2,'sport retries expired ON from actual OFF')
v.on=true;D.bind(sport);sportClick();sportClick()
sport.__YourDashHeadlightSwitchPending=0;sportClick()
assert(nativeClicks==pn+3 and requestedPower==false and activations==pa+2 and D.switchMode(sport)=='high','sport expires rejected OFF to actual LOW and then selects HIGH without toggling power')
sport.__YourDashHeadlightSwitchPending=0
pn,pa,pd=nativeClicks,activations,deactivations
speed=0
for _,mode in ipairs({'off','low','high'}) do
 v.on=mode~='off';v.data.NepHB.highBeamsOn=mode=='high';D.bind(sport);sportClick()
 assert(nativeClicks==pn and activations==pa and deactivations==pd and D.switchMode(sport)==mode,'paused sport releases preserve '..mode..' and send no commands')
end
speed=1;v.on=false;v.data.NepHB.highBeamsOn=false;D.bind(sport)
local replacementCalls=0
local function replacement(dash,img)
 replacementCalls=replacementCalls+1
 assert(dash==sport and img==push,'sport wrapper forwards real ISImage callback arguments')
 return nativeClick(dash)
end
push.onclick=replacement;D.bind(sport)
assert(push.onclick==push.__toolkitBeamPushClick and push.__toolkitBeamPushNativeClick==replacement,'sport rebind wraps a replaced native callback')
sportClick()
assert(replacementCalls==1 and nativeClicks==pn+1,'sport executes replacement callback exactly once on power change')
v.on=true;D.bind(sport);sportClick()
assert(replacementCalls==1 and activations==pa+1,'sport beam-only click never calls the replaced power callback')
sport.__YourDashHeadlightSwitchPending=0
sport.__YourDashFamily='standard';D.bind(sport)
assert(push.onclick==push.__toolkitBeamRotaryClick and push.__toolkitBeamNativeClick==replacement,'sport to standard releases push before wrapping the native callback')
sport.__YourDashFamily='sport';D.bind(sport)
assert(push.onclick==push.__toolkitBeamPushClick and push.__toolkitBeamPushNativeClick==replacement and push.render==pushNativeRender,'standard to sport removes rotary wrapper and restores native rendering')
sport.backgroundTex=nil -- Exercise the heavy fallback without rocker artwork.
sport.__YourDashFamily='heavy';D.bind(sport)
assert(push.onclick==replacement and push.render==pushNativeRender and push.onMouseUp==pushNativeUp,'sport to heavy fallback restores native control')
sport.__YourDashFamily='sport';D.bind(sport)
sport.__YourDashFamily='unknown';D.bind(sport)
assert(push.onclick==replacement,'sport to unsupported family releases the push cycle')
sport.__YourDashFamily='sport';D.bind(sport)
NepHBO7=nil;D.bind(sport)
assert(push.onclick==replacement and push.render==pushNativeRender and push.texture==pushTexture,'missing Nep API releases sport callback and preserves native artwork')
NepHBO7=originalApi;D.bind(sport)
assert(push.onclick==push.__toolkitBeamPushClick and push.__toolkitBeamPushNativeClick==replacement,'restored Nep API wraps native sport callback again')
sport.vehicle=nil;pn,pa,pd=nativeClicks,activations,deactivations;sportClick()
assert(nativeClicks==pn and activations==pa and deactivations==pd,'detached sport release changes no power or beam state')
-- The truck rocker reuses the real ISImage callback contract: onMouseUp gives
-- onclick the target and image, not its local coordinates. Preserve the event's
-- local Y while delegating so the two halves work without polling mouse state.
local rockerDimensions={{22,41},{29,55},{41,77},{58,110}}
for i,key in ipairs(scales) do
 local size=rockerDimensions[i]
 for _,mode in ipairs({'off','low','high'}) do
  highTextures['media/ui/PZSurvivorToolkit/beams/heavy/'..key..'/rocker-'..mode..'.png']={
   getWidthOrig=function() return size[1] end,getHeightOrig=function() return size[2] end}
 end
 highTextures['media/ui/PZSurvivorToolkit/beams/heavy/'..key..'/light-panel.png']={
  getWidthOrig=function() return 75*nominalScales[i] end,getHeightOrig=function() return 132*nominalScales[i] end}
end
v.on=false;v.data.NepHB.highBeamsOn=false;speed=1
local rocker=image(84,48);local rockerOriginal=rocker.texture
local rockerNativeRender,rockerNativeUp=rocker.render,rocker.onMouseUp
local bg=image(735,180);local bgRender=bg.render
local truck={vehicle=v,character={},lightsTex=rocker,warnLightTex=image(30,24),backgroundTex=bg,
 __YourDashFamily='heavy',_YourDashGetHeadlightSwitchState=rotaryDash._YourDashGetHeadlightSwitchState}
rocker.onclick=nativeClick;rocker.target=truck;scaleKey='1x'
D.bind(truck)
local click,draw,up=rocker.onclick,rocker.render,rocker.onMouseUp
D.bind(truck)
assert(rocker.onclick==click and rocker.render==draw and rocker.onMouseUp==up,'do not nest truck callbacks')
for i,key in ipairs(scales) do
 scaleKey=key;D.bind(truck)
 local size=rockerDimensions[i]
 assert(rocker.width==size[1] and rocker.height==size[2],'truck hitbox matches active sprite')
 assert(rocker.x==bg.x+math.floor(45*nominalScales[i]+.5) and rocker.y==bg.y+math.floor(124*nominalScales[i]+.5),'anchor truck rocker to its own background at each scale')
 rocker.draws={};rocker:render();local r=rocker.draws[1]
 assert(#rocker.draws==1 and r[1]==rocker.texture and r[2]==0 and r[3]==0 and r[4]==size[1] and r[5]==size[2],'one untinted sprite replaces the original knob without rotation, duplicate or press shrink')
 assert(r[6]==1,'switch stays visible independently of the warning-light alpha')
 bg.draws={};bg:render()
 assert(bg.nativeRender and bg.draws[1][1]==getTexture('media/ui/PZSurvivorToolkit/beams/heavy/'..key..'/light-panel.png'),'cleanup follows all original background layers')
end
scaleKey='1x';D.bind(truck)
local function truckClick(upper)
 rocker:onMouseUp(rocker.width*.5,rocker.height*(upper and .25 or .75))
 assert(rocker.__toolkitBeamClickY==nil,'release temporary input coordinates')
 D.bind(truck)
end
local n,a,d=nativeClicks,activations,deactivations
truckClick(false);assert(nativeClicks==n and activations==a and deactivations==d,'bottom at OFF has no effect')
truckClick(true);assert(nativeClicks==n+1 and requestedPower==true and D.switchMode(truck)=='low','top at OFF requests native LOW')
truckClick(true);truckClick(false)
assert(nativeClicks==n+1 and activations==a and D.switchMode(truck)=='low','pending native ON cannot be reversed or duplicated')
v.on=true;D.bind(truck);speed=3;truckClick(true)
assert(nativeClicks==n+1 and activations==a+1 and D.switchMode(truck)=='high' and speed==1,'top at LOW selects HIGH without toggling power')
truckClick(true);assert(activations==a+1,'top at HIGH stops at its detent')
truckClick(false);assert(nativeClicks==n+1 and D.switchMode(truck)=='low','bottom at HIGH selects LOW without a native power command')
truckClick(false);assert(nativeClicks==n+2 and requestedPower==false and D.switchMode(truck)=='off','bottom at LOW requests native OFF')
truckClick(true);assert(nativeClicks==n+2 and activations==a+1,'pending OFF cannot accidentally send ON')
v.on=false;truck.__YourDashHeadlightSwitchPending=0;D.bind(truck)
for _,mode in ipairs({'off','low','high'}) do
 v.on=mode~='off';v.data.NepHB.highBeamsOn=mode=='high';D.bind(truck)
 assert(rocker.texture==getTexture('media/ui/PZSurvivorToolkit/beams/heavy/1x/rocker-'..mode..'.png'),'hotkey/radial changes select the corresponding truck sprite')
end
n,a,d=nativeClicks,activations,deactivations
speed=0;truckClick(false)
assert(nativeClicks==n and activations==a and deactivations==d and D.switchMode(truck)=='high','pause changes neither truck state nor commands')
speed=1;v.charge=0;D.bind(truck)
assert(D.mode(v)=='off' and rocker.texture==getTexture('media/ui/PZSurvivorToolkit/beams/heavy/1x/rocker-high.png'),'empty battery extinguishes lamp but preserves the physical high position')
v.charge=1;truck.alarm=true;truck.__YourDashHeadlightSwitchOn=true;v.on=false;D.bind(truck)
assert(D.switchMode(truck)=='high','truck position ignores alarm flashes')
truck.alarm=false;truck.__YourDashHeadlightSwitchPending=0;truck.vehicle=nil;truckClick(true)
assert(nativeClicks==n and activations==a and deactivations==d,'detached truck control does nothing')
truck.vehicle=v;NepHBO7=nil;D.bind(truck)
assert(rocker.onclick==nativeClick and rocker.onMouseUp==rockerNativeUp and rocker.render==rockerNativeRender,'missing beam API restores native truck handlers')
assert(rocker.texture==rockerOriginal and rocker.width==84 and bg.render==bgRender,'fallback restores native art, bounds and complete background')
NepHBO7=originalApi;D.bind(truck)
truck.__YourDashFamily='sport';D.bind(truck)
assert(rocker.onclick==rocker.__toolkitBeamPushClick and rocker.__toolkitBeamPushNativeClick==nativeClick and rocker.render==rockerNativeRender and bg.render==bgRender,'heavy to sport restores native rendering and wraps the native callback in the push cycle')
truck.__YourDashFamily='standard';D.bind(truck)
assert(rocker.onclick==rocker.__toolkitBeamRotaryClick,'heavy to standard restores the rotary instead of nesting truck behavior')
truck.__YourDashFamily='heavy';D.bind(truck)
assert(rocker.onclick==rocker.__toolkitBeamRockerClick and rocker.__toolkitBeamRockerNative.click==nativeClick,'returning to truck wraps the native callback, never the rotary wrapper')
print('PASS beam dashboard: native soft indicators, standard rotary, sport push cycle, truck rocker at four scales, native power ACK/guards/alarm, external state and family/API fallback')
