local Cart={types={'SaucedCarts.ShoppingCart','SaucedWheelbarrow.WheelbarrowWood','SaucedWheelbarrow.WheelbarrowMetal'},
 phases={'pickup-first','drop','pickup-repeat'}}
local JSON=require 'QueueHealthEvents'
function Cart.selected(config)
 return config.suite=='equipment' and config.cases and config.cases[1]=='cart-pickup'
end
function Cart.validate(config)
 assert(Cart.selected(config) and #config.cases==1 and config.kind=='mp' and config.clients==1
  and config.options and config.options.mp_host==true,'isolated one-client Host cart-pickup selection required')
 assert(config.mode=='native' or config.mode=='toolkit','invalid cart queue mode')
 for _,id in ipairs({'PZSurvivorToolkit','PZToolkitJavaPatches','ZombieBuddy','SaucedCarts','saucedwheelbarrow'}) do
  assert(getActivatedMods():contains(id),'cart fixture requires '..id)
 end
end
local function id(item) return item and item:getID() or -1 end
function Cart.inspect(player,spec)
 local inventory=player:getInventory();local item,count,worldCount=nil,0,0
 local contents=inventory:getItems()
 for i=0,contents:size()-1 do local entry=contents:get(i)
  if entry:getID()==spec.id then count=count+1;item=entry end
 end
 local seen={}
 for _,point in ipairs({spec, {x=math.floor(player:getX()),y=math.floor(player:getY()),z=player:getZ()}}) do
  for x=point.x-2,point.x+2 do for y=point.y-2,point.y+2 do
   local square=getCell():getGridSquare(x,y,point.z)
   if square and not seen[square] then
    seen[square]=true;local objects=square:getWorldObjects()
    for i=0,objects:size()-1 do local entry=objects:get(i):getItem()
     if entry and entry:getID()==spec.id then worldCount=worldCount+1;item=entry end
    end
   end
  end end
 end
 local cargoOK=false;local cargoID=-1;local cargoWeight=-1
 if item then
  assert(item:getFullType()==spec.type,'cart ID changed type')
  local cargo=item:getInventory():getItems()
  if cargo:size()==1 then local child=cargo:get(0);cargoID=child:getID();cargoWeight=child:getActualWeight()
   cargoOK=cargoID==spec.cargo and child:getFullType()=='Base.Nails' and math.abs(cargoWeight-spec.weight)<.001
  end
 end
 local row={id=spec.id,type=spec.type,cargoID=cargoID,cargoWeight=cargoWeight,cargoPreserved=cargoOK,
  inventoryCount=count,worldCount=worldCount,primaryID=id(player:getPrimaryHandItem()),secondaryID=id(player:getSecondaryHandItem()),
  aiming=player:isAiming(),worldAttached=item and item:getWorldItem()~=nil or false}
 return row,item
end
function Cart.matches(row,ground)
 if not row.cargoPreserved then return false end
 if ground then return row.inventoryCount==0 and row.worldCount==1 and row.worldAttached
  and row.primaryID==-1 and row.secondaryID==-1 end
 return row.inventoryCount==1 and row.worldCount==0 and not row.worldAttached
  and row.primaryID==row.id and row.secondaryID==row.id
end
function Cart.pickup(action)
 if not action then return false end
 local class,duration
 if action.Type=='ISCartPickupAction' then class,duration=ISCartPickupAction,50
 elseif action.Type=='ToolkitWoodCartPickup' then class,duration=ToolkitWoodCartPickup,88
 else return false end
 assert(class and action.getDuration==class.getDuration and action:getDuration()==duration,'cart native/custom duration replaced')
 return true
end
function Cart.marker(kind,row) print('[CART_PICKUP] '..kind..' '..JSON.encode(row)) end
function Cart.receipt(player,spec,phase,actor)
 local row=Cart.inspect(player,spec)
 assert(Cart.matches(row,phase=='drop'),'exact cart/cargo ownership differs at '..phase)
 assert(not row.aiming,'unexpected aim input in baseline cart fixture')
 row.phase=phase;row.actor=actor;row.index=spec.index
 return row
end
return Cart
