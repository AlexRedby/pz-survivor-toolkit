-- Pure protocol: all receipts retain their producer, role and authoritative IDs.
local M={producer='cart-mp-inventory-equip-v1',cartType='SaucedWheelbarrow.WheelbarrowWood'}
local variants={['female-empty']={female=true,load='empty'},['female-full']={female=true,load='full'},
 ['male-empty']={female=false,load='empty'},['male-full']={female=false,load='full'}}
function M.variant(name)
 local value=assert(variants[name],'Unknown cart_inventory_equip_variant');return {name=name,female=value.female,load=value.load}
end
function M.match(row,spec,actor)
 assert(type(row)=='table' and row.producer==M.producer and row.actor==actor,'Wrong inventory-equip producer/actor')
 assert(row.id==spec.id and row.ownerID==spec.ownerID and row.variant==spec.variant and row.female==spec.female,
  'Inventory-equip authoritative identity/sex differs')
 assert(row.cartType==M.cartType and row.cargoIDs==spec.cargoIDs and row.cargoCount==spec.cargoCount
  and type(row.cargoWeight)=='number' and math.abs(row.cargoWeight-spec.cargoWeight)<.001,'Inventory-equip cargo changed')
 assert(row.worldCount==0 and row.worldAttached==false,'Inventory-equip cart entered world')
 if actor=='client2' then
  assert(row.inventoryCount==nil and row.inventoryScope=='remote-hand-snapshot','Observer claimed authoritative inventory')
 else assert(row.inventoryScope=='owner-inventory' and row.inventoryCount==1,'Exact owner inventory identity lost') end
 return true
end
function M.settled(row,spec,actor)
 M.match(row,spec,actor)
 assert(row.phase=='settled-tail' and row.primaryID==spec.id and row.secondaryID==spec.id and row.handSameItem==true,
  'Inventory-equip exact held endpoint missing')
 assert(row.nativeActions==0 and row.hasPath==false,'Inventory-equip native action/path did not terminate')
 if actor=='server' then assert(row.luaActions==nil and row.queueScope=='native-server-only','Server must expose native-only queue scope')
 else assert(row.luaActions==0,'Inventory-equip Lua queue did not terminate') end
 assert(row.pantsType=='Base.Trousers_JeanBaggy' and row.wornCount==3
  and row.pantsModel=='skinned/clothes/'..(spec.female and 'kate' or 'bob')..'_trousers','Native outfit model differs')
 return true
end
function M.nativeTerminal(row)
 -- updateInternal clears forceComplete after perform and queue removal, before
 -- Lua OnTick. Exact canonical force-completion is checked in the native trace.
 assert(row.actionType=='ISCartEquipAction','Terminal equip action type changed')
 assert(row.duration==30 and row.nativeMaxTime==30,'Terminal equip duration changed')
 assert(type(row.nativeFinished)=='boolean' and type(row.nativeForceComplete)=='boolean','Terminal native flags missing')
 assert(type(row.nativeTime)=='number' and row.nativeTime>=30,'Terminal native time below equip duration')
 assert(row.nativeProgress==1,'Terminal native progress is incomplete')
 return true
end
return M
