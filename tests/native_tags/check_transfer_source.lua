assert(NativePZLuaRoot,'Set NativePZLuaRoot to the installed game media/lua path')
require=function() return {} end
ISInventoryPage={}
ISBaseTimedAction={derive=function(_,name) return {Type=name} end}
getTimestampMs=function() return 0 end
isClient=function() return true end
getCore=function() return {getGameMode=function() return 'Sandbox' end} end
CharacterTrait={DEXTROUS='dextrous',ALL_THUMBS='all_thumbs'}
local inventory={}
local player={getInventory=function() return inventory end,hasTrait=function() return false end,
 isWearingAwkwardGloves=function() return false end,isTimedActionInstant=function() return false end}
local source={getType=function() return 'Schoolbag' end,isInCharacterInventory=function() return true end,
 isVehicleSeat=function() return false end,contains=function() return true end}
local destination={seat=false,getType=function() return 'crate' end,isInCharacterInventory=function() return false end,
 isVehicleSeat=function(self) return self.seat end}
local item={getActualWeight=function() return 0.1 end,isFavorite=function() return false end,
 getFullType=function() return 'Base.Battery' end,getIsCraftingConsumed=function() return false end}
local listedCalls,consistencyCalls=0,0
ISInventoryPaneContextMenu={getContainers=function()
 listedCalls=listedCalls+1
 return {contains=function() return false end}
end}
ISTradingUI={GetUIForPlayer=function() end}
getServerOptions=function() return {getInteger=function() return 0 end} end
isItemTransactionConsistent=function(actualItem,actualSource,actualDestination)
 assert(actualItem==item and actualSource==source and actualDestination==destination)
 consistencyCalls=consistencyCalls+1;return true
end
dofile(NativePZLuaRoot..'/client/TimedActions/ISInventoryTransferAction.lua')
local action=ISInventoryTransferAction:new(player,item,source,destination)
assert(not action.isTransferIntoVehicleSeatFromOutside and action:isValid(),'normal carried bag->crate transfer rejected')
assert(listedCalls==0 and consistencyCalls==1,'normal MP transfer required visible/worn source membership')
destination.seat=true
action=ISInventoryTransferAction:new(player,item,source,destination)
assert(action.isTransferIntoVehicleSeatFromOutside and not action:isValid() and listedCalls==1,
 'vehicle-only visible-container guard was not exercised')
print('Native transfer-source check passed: ordinary carried bag->crate validates without UI membership; vehicle-seat-only guard remains active (transaction consistency stubbed).')

-- Inventory tabs have a separate equipped-bag requirement. Exercise the same
-- native Wear callback used by the fixture, including its ordinary timed action.
local file=assert(io.open(NativePZLuaRoot..'/client/ISUI/ISInventoryPaneContextMenu.lua'))
local nativeMenu=file:read('*a');file:close()
for _,name in ipairs({'onWearItems','wearItem'}) do
 local code=assert(nativeMenu:match('ISInventoryPaneContextMenu%.'..name..' = function.-\nend'),'native wear callback absent '..name)
 assert(loadstring(code))()
end
ItemBodyLocation={HAT='Hat',FULL_HAT='FullHat'}
ISInventoryPane={getActualItems=function(items) return items end}
getSpecificPlayer=function(number) assert(number==0);return player end
local bag={getBodyLocation=function() end,canBeEquipped=function() return 'Back' end}
local transferred,queued=0,{}
ISInventoryPaneContextMenu.transferIfNeeded=function(actualPlayer,actualBag)
 assert(actualPlayer==player and actualBag==bag);transferred=transferred+1
end
ISWearClothing={new=function(_,actualPlayer,actualBag,time)
 assert(actualPlayer==player and actualBag==bag and time==50,'fixture bypassed ordinary Wear callback duration')
 return {Type='ISWearClothing',item=actualBag,maxTime=time}
end}
ISTimedActionQueue={add=function(action) queued[#queued+1]=action end}
ISInventoryPaneContextMenu.onWearItems({bag},0)
assert(transferred==1 and #queued==1 and queued[1].item==bag,'native Wear did not queue exactly the owned bag')
print('Native inventory-source wear check passed: real Wear callback queues ordinary ISWearClothing for the owned bag only.')
