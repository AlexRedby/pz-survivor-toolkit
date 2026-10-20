local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true,'CartMotionConfig.disposable must be true')
assert(getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable single-player CartTestArea save required')
assert(CartTestArea and cartLabDrive and cartLabGait,'Load test-area.lua and the Java fixture first')
assert(getPlayer(),'Live actor required')
require 'SaucedCarts/Core'
require 'SaucedCarts/CartVisuals'
if CartLabTick then Events.OnTick.Remove(CartLabTick) end
if CartLabGate then Events.OnPlayerUpdate.Remove(CartLabGate) end
local player=getPlayer()
local expectedCart=config.cartType or 'SaucedWheelbarrow.WheelbarrowWood'
assert(expectedCart=='SaucedWheelbarrow.WheelbarrowWood' or expectedCart=='SaucedWheelbarrow.WheelbarrowMetal','Unsupported bootstrap cart type')
-- Capture UI state begin: test-only, no keybind/options files are written.
require 'ISUI/ISUIHandler'
assert(config.hideUI==nil or type(config.hideUI)=='boolean','CartMotionConfig.hideUI must be boolean')
assert(cartLabCaptureUIRender and cartLabCaptureUIVisible and cartLabCaptureUIKeyBound,'Capture UI render bridge required')
if CartLabCaptureUITick then Events.OnTick.Remove(CartLabCaptureUITick) end
if CartLabCaptureUIRestore then
 Events.OnMainMenuEnter.Remove(CartLabCaptureUIRestore)
 CartLabCaptureUIRestore()
end
local captureUISaved
CartLabCaptureUIHidden=false
CartLabCaptureUIKey=Keyboard.KEY_F9
if cartLabCaptureUIKeyBound(CartLabCaptureUIKey) then
 print('[CART_CAPTURE_UI] F9 is already bound; use cartLabCaptureUI(boolean hidden)')
 CartLabCaptureUIKey=nil
end
local function captureUIWorld()
 return config.disposable==true and getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer()
end
CartLabCaptureUIRestore=function()
 cartLabCaptureUIRender(false)
 if not captureUISaved then CartLabCaptureUIHidden=false;return end
 ISUIHandler.setVisibleAllUI(true)
 local ui=UIManager.getUI()
 for i=0,ui:size()-1 do
  local element=ui:get(i);local visible=captureUISaved.elements[element]
  if visible~=nil then element:setVisible(visible) end
 end
 ISUIHandler.visibleUI=captureUISaved.visibleUI
 ISUIHandler.allUIVisible=captureUISaved.allUIVisible
 UIManager.setVisibleAllUI(captureUISaved.nativeVisible)
 captureUISaved=nil;CartLabCaptureUIHidden=false
 print('[CART_CAPTURE_UI] hidden=false')
end
function cartLabCaptureUI(hidden)
 assert(type(hidden)=='boolean','cartLabCaptureUI requires a boolean')
 assert(captureUIWorld(),'Capture UI requires disposable single-player CartTestArea')
 if hidden==CartLabCaptureUIHidden then return end
 if not hidden then CartLabCaptureUIRestore();return end
 local saved={elements={},visibleUI={},allUIVisible=ISUIHandler.allUIVisible,nativeVisible=cartLabCaptureUIVisible()}
 for i,value in ipairs(ISUIHandler.visibleUI) do saved.visibleUI[i]=value end
 local ui=UIManager.getUI()
 for i=0,ui:size()-1 do local element=ui:get(i);saved.elements[element]=element:isVisible() end
 captureUISaved=saved
 ISUIHandler.allUIVisible=false;ISUIHandler.setVisibleAllUI(false)
 cartLabCaptureUIRender(true);CartLabCaptureUIHidden=true
 print('[CART_CAPTURE_UI] hidden=true toggle='..tostring(CartLabCaptureUIKey or 'callable-only'))
end
CartLabCaptureUITick=function()
 if not captureUIWorld() then CartLabCaptureUIRestore();Events.OnTick.Remove(CartLabCaptureUITick) end
end
Events.OnTick.Add(CartLabCaptureUITick)
Events.OnMainMenuEnter.Add(CartLabCaptureUIRestore)
-- Capture UI state end.
if config.authoredClip~=nil then player:setVariable('ToolkitWoodCartClipPilot',config.authoredClip) end
if config.authoredClip~=false then assert(cartLabClipInfo('Toolkit_WoodCart_Pickup')~='missing','Authored cart clip missing') end
player:setGodMod(true);player:setNoClip(false,true)
local cart=player:getPrimaryHandItem()
local finished=true
cartLabDrive(-1);cartLabGait(0);setGameSpeed(1)
local function refresh()
 player:getInventory():setDrawDirty(true)
 local data=getPlayerData(player:getPlayerNum())
 data.playerInventory:refreshBackpacks();data.lootInventory:refreshBackpacks()
 data.characterInfo:setVisible(false)
 data.playerInventory:setNewContainer(cart and cart:getInventory() or player:getInventory())
end
local function equip(spec)
 if cart and cart:getContainer()==player:getInventory() then
  player:setPrimaryHandItem(nil);player:setSecondaryHandItem(nil);SaucedCarts.clearCartPose(player);player:getInventory():Remove(cart)
 end
 cart=nil
 if spec.kind then
  cart=assert(player:getInventory():AddItem(spec.kind))
  player:setPrimaryHandItem(cart);player:setSecondaryHandItem(cart);SaucedCarts.applyCartPose(player)
  if spec.full then local cargo=cart:getInventory():AddItem('Base.Log');cargo:setActualWeight(cart:getInventory():getEffectiveCapacity(player));cargo:setCustomWeight(true) end
  SaucedCarts.updateCartVisual(cart,player,true)
 end
 refresh()
end
if CartLabKey then Events.OnKeyPressed.Remove(CartLabKey) end
local selected,full,bare=1,false,false
local kinds={'SaucedCarts.ShoppingCart','SaucedWheelbarrow.WheelbarrowWood','SaucedWheelbarrow.WheelbarrowMetal'}
CartLabKey=function(key)
 if not finished or not player or not isIngameState() then return end
 if CartLabCaptureUIKey and key==CartLabCaptureUIKey then cartLabCaptureUI(not CartLabCaptureUIHidden);return end
 if key~=Keyboard.KEY_F5 and key~=Keyboard.KEY_F6 and key~=Keyboard.KEY_F7 then return end
 if player:hasTimedActions() then return end
 if key==Keyboard.KEY_F5 then selected=selected%3+1;bare=false
 elseif key==Keyboard.KEY_F6 then full=not full;bare=false
 else bare=not bare end
 equip(bare and {} or {kind=kinds[selected],full=full})
 print('[CART_LAB] HOTKEY item='..(cart and cart:getFullType() or 'bare')..' cargo='..(cart and cart:getInventory():getCapacityWeight() or 0))
end
Events.OnKeyPressed.Add(CartLabKey)
require 'ISUI/ISPanel'
if CartLabHUD then CartLabHUD:removeFromUIManager() end
CartLabHUD=ISPanel:new(65,getCore():getScreenHeight()-85,610,55)
CartLabHUD:initialise();CartLabHUD:addToUIManager()
CartLabHUD.prerender=function(self)
 if not player then return end
 self:drawRect(0,0,self.width,self.height,.85,0,0,0)
 local item=player:getPrimaryHandItem()
 local status='Bare hands'
 if item and instanceof(item,'InventoryContainer') then status=item:getFullType()..'   '..string.format('%.1f / %d',item:getInventory():getCapacityWeight(),item:getInventory():getEffectiveCapacity(player)) end
 self:drawText(status,10,5,1,1,1,1,UIFont.Small)
 self:drawText('F5: cart   F6: empty/full   F7: bare hands'..(CartLabCaptureUIKey and '   F9: capture UI' or '')..'   WASD: move',10,28,1,1,1,1,UIFont.Small)
end
cartLabCaptureUI(config.hideUI~=false)

print('[CART_LAB] MANUAL_READY')

if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end

CartLabKey(Keyboard.KEY_F5);CartLabKey(Keyboard.KEY_F5);CartLabKey(Keyboard.KEY_F5)

local woodSince=getTimestampMs()
local woodReady
woodReady=function()
 if getTimestampMs()-woodSince<3000 then return end
 Events.OnTick.Remove(woodReady)
 local ok,err=pcall(function()
  assert(cartLabChunkWidth()>=200,'[CART_TEST_AREA] native chunk window too small')
  print('[CART_TEST_AREA] CHUNK_WINDOW tiles='..cartLabChunkWidth()..' screen='..getCore():getScreenWidth()..'x'..getCore():getScreenHeight())
  CartTestArea.prepare()
  local p=assert(getPlayer())
  local x,y,z=CartTestArea.x,CartTestArea.y,CartTestArea.z
  cartLabDrive(0)
  p:setX(x);p:setY(y);p:setZ(z);p:setNextX(x);p:setNextY(y);p:setLastX(x);p:setLastY(y)
  p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow()
  p:setTargetAndCurrentDirection(-.70710678,.70710678)
  for i=1,3 do
   local item=p:getPrimaryHandItem()
   if item and item:getFullType()==expectedCart then break end
   CartLabKey(Keyboard.KEY_F5)
  end
  assert(p:getPrimaryHandItem():getFullType()==expectedCart)
  if p:getPrimaryHandItem():getInventory():getCapacityWeight()>0 then CartLabKey(Keyboard.KEY_F6) end
  CartTestArea.check(p);cartLabDrive(-1)
  getCore():setAutoZoom(0,false)
  for i=1,12 do getCore():doZoomScroll(0,-1) end
  getCore():TakeFullScreenshot((config.cartVariant=='metal-wheelbarrow' and 'metal' or 'wood')..'-bootstrap-ready.png')
  print('[WOOD_PROTOTYPE] BOOTSTRAP_READY side=-.70710678,+.70710678 cartType='..expectedCart)
 end)
 if not ok then cartLabDrive(-1);print('[WOOD_PROTOTYPE] BOOTSTRAP_FAIL '..tostring(err)) end
end
Events.OnTick.Add(woodReady)
