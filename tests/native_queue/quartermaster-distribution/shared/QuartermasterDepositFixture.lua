local F = {module = 'QuartermasterDepositTest', nailWeight = .0625, ballastWeight = .875}
local function weighted(container, weight)
 local item = assert(container:AddItem('Base.Nails'))
 item:setCustomWeight(true); item:setActualWeight(weight); item:setWeight(weight)
 assert(item:getActualWeight() == weight and item:getWeight() == weight, 'custom fixture weight differs')
 if isServer() then sendAddItemToContainer(container, item) end
 return item
end
function F.prepare(player, point, kind)
 assert(player:getCurrentSquare() and math.abs(player:getX()-point.x)<2 and math.abs(player:getY()-point.y)<2,
  'deposit actor has not reached fixture origin')
 local state = {player = player, boxes = {}, ids = {}, kind = kind, ballastId = false}
 for index, offset in ipairs({{-1,0},{1,0},{0,1}}) do
  local sq = assert(getCell():getGridSquare(point.x+offset[1],point.y+offset[2],point.z))
  assert(sq:canStand() and sq:isFree(true), 'deposit crate tile occupied')
  local obj = IsoThumpable.new(getCell(),sq,'carpentry_01_16',false,{})
  obj:setBlockAllTheSquare(true); obj:setIsContainer(true)
  local container = assert(obj:getContainer())
  container:setType('crate'); container:setExplored(true)
  container:setCapacity(index == 2 and (kind == 'mp' and 0 or 2) or 100)
  obj:getModData().PZSTDepositFixture = true; sq:AddSpecialObject(obj)
  state.boxes[index] = obj
  if isServer() then obj:transmitCompleteItemToClients(); obj:transmitModData() end
 end
 for i = 1, 3 do state.ids[i] = weighted(state.boxes[1]:getContainer(), F.nailWeight):getID() end
 if kind == 'sp' then state.ballastId = weighted(state.boxes[2]:getContainer(), F.ballastWeight):getID() end
 return state
end
function F.descriptor(state)
 local packet = {kind = state.kind, ids = state.ids, ballastId = state.ballastId, boxes = {}}
 for i, obj in ipairs(state.boxes) do
  local sq = obj:getSquare()
  packet.boxes[i] = {x=sq:getX(),y=sq:getY(),z=sq:getZ(),index=obj:getObjectIndex()}
 end
 return packet
end
function F.resolve(packet)
 local boxes = {}
 for i, point in ipairs(packet.boxes) do
  local sq = getCell():getGridSquare(point.x,point.y,point.z)
  if not sq or point.index >= sq:getObjects():size() then return end
  local obj = sq:getObjects():get(point.index)
  if not obj or not obj:hasModData() or not obj:getModData().PZSTDepositFixture then return end
  boxes[i] = obj
 end
 for _, id in ipairs(packet.ids) do if not boxes[1]:getContainer():getItemById(id) then return end end
 if packet.ballastId and not boxes[2]:getContainer():getItemById(packet.ballastId) then return end
 return boxes
end
function F.receipt(player, boxes, packet)
 local destinations = packet.kind == 'sp' and {2,1,3} or {1,1,3}
 local expected, found = {}, {}
 for i, id in ipairs(packet.ids) do expected[id] = {container=destinations[i],weight=F.nailWeight} end
 if packet.ballastId then expected[packet.ballastId] = {container=2,weight=F.ballastWeight} end
 local count = 0
 for index, obj in ipairs(boxes) do
  local container, items = obj:getContainer(), obj:getContainer():getItems()
  for i = 0, items:size()-1 do
   local item = items:get(i); local id = item:getID(); local target = expected[id]
   assert(target and not found[id], 'unknown/duplicated item in owned deposit crates')
   assert(item:getContainer() == container, 'deposit item/container identity differs')
   assert(item:getActualWeight() == target.weight and item:getWeight() == target.weight, 'deposit item weight changed')
   found[id] = index; count = count+1
  end
 end
 for id, target in pairs(expected) do
  assert(not player:getInventory():getItemById(id), 'deposit fixture item leaked into actor inventory')
  if found[id] ~= target.container then return end
 end
 assert(count == (packet.kind == 'sp' and 4 or 3), 'deposit item conservation count differs')
 local limited, tail = boxes[2]:getContainer(), boxes[3]:getContainer()
 local capacity = packet.kind == 'sp' and 1 or 0
 local weight = packet.kind == 'sp' and F.ballastWeight+F.nailWeight or 0
 assert(limited:getCapacity() == capacity and limited:getEffectiveCapacity(player) == capacity,
  'deposit final native capacity differs')
 assert(limited:getCapacityWeight() == weight and weight <= capacity, 'deposit overfilled limited destination')
 assert(tail:getCapacityWeight() == F.nailWeight, 'independent destination has wrong weight')
 return {kind=packet.kind,ids=packet.ids,ballastId=packet.ballastId,destinations=destinations,
  sourceCount=boxes[1]:getContainer():getItems():size(),limitedCapacity=capacity,limitedWeight=weight,
  tailWeight=tail:getCapacityWeight(),conserved=count}
end
function F.cleanup(state)
 for _, obj in ipairs(state.boxes) do
  assert(obj:hasModData() and obj:getModData().PZSTDepositFixture, 'refusing foreign deposit cleanup')
  obj:getSquare():transmitRemoveItemFromSquare(obj)
 end
end
return F
