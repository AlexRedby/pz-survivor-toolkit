-- Pure protocol: all receipts retain their producer, role and authoritative IDs.
local M={producer='cart-mp-inventory-equip-v1',cartType='SaucedWheelbarrow.WheelbarrowWood'}
local variants={['female-empty']={female=true,load='empty'},['female-full']={female=true,load='full'},
 ['male-empty']={female=false,load='empty'},['male-full']={female=false,load='full'}}
function M.variant(name)
 local value=assert(variants[name],'Unknown cart_inventory_equip_variant');return {name=name,female=value.female,load=value.load}
end
local function matchReason(row,spec,actor)
 if type(row)~='table' or type(spec)~='table' or row.producer~=M.producer or row.actor~=actor then
  return 'identity: Wrong inventory-equip producer/actor' end
 if row.id~=spec.id or row.ownerID~=spec.ownerID or row.variant~=spec.variant or row.female~=spec.female then
  return 'identity: Inventory-equip authoritative identity/sex differs' end
 if row.cartType~=M.cartType or row.cargoIDs~=spec.cargoIDs or row.cargoCount~=spec.cargoCount
  or type(row.cargoWeight)~='number' or type(spec.cargoWeight)~='number'
  or not (math.abs(row.cargoWeight-spec.cargoWeight)<.001) then return 'cargo: Inventory-equip cargo changed' end
 if row.worldCount~=0 or row.worldAttached~=false then return 'world: Inventory-equip cart entered world' end
 if actor=='client2' then
  if row.inventoryCount~=nil or row.inventoryScope~='remote-hand-snapshot' then return 'inventory: Observer claimed authoritative inventory' end
 elseif row.inventoryScope~='owner-inventory' or row.inventoryCount~=1 then return 'inventory: Exact owner inventory identity lost' end
end
function M.match(row,spec,actor)
 local reason=matchReason(row,spec,actor);assert(not reason,reason);return true
end
-- Poll actual worn state without using an assertion as a normal loading signal.
function M.outfitReady(row,spec)
 if type(row)~='table' or type(spec)~='table' or type(spec.female)~='boolean' then return false,'outfit: Native outfit snapshot unavailable' end
 if row.female~=spec.female then return false,'outfit: Native wearer sex pending' end
 if row.wornCount~=3 then return false,'outfit: Native three-clothing outfit pending' end
 if row.pantsType~='Base.Trousers_JeanBaggy' then return false,'outfit: Native JeanBaggy trousers pending' end
 if row.pantsModel~='skinned/clothes/'..(spec.female and 'kate' or 'bob')..'_trousers' then return false,'outfit: Native trousers model pending' end
 return true
end
function M.settledReady(row,spec,actor)
 local reason=matchReason(row,spec,actor);if reason then return false,reason end
 if row.phase~='settled-tail' or row.primaryID~=spec.id or row.secondaryID~=spec.id or row.handSameItem~=true then
  return false,'endpoint: Inventory-equip exact held endpoint missing' end
 if row.nativeActions~=0 or row.hasPath~=false then return false,'actions: Inventory-equip native action/path did not terminate' end
 if actor=='server' then
  if row.luaActions~=nil or row.queueScope~='native-server-only' then return false,'queue: Server must expose native-only queue scope' end
 elseif row.luaActions~=0 then return false,'queue: Inventory-equip Lua queue did not terminate' end
 return M.outfitReady(row,spec)
end
function M.settled(row,spec,actor)
 local ready,reason=M.settledReady(row,spec,actor);assert(ready,reason);return true
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
