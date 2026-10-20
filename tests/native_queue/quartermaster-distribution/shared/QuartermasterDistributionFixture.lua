local Fixture={presetName='PZST distribution preset'}
local Presets=require 'PZSurvivorToolkit/QuartermasterPresets'
local Rules=require 'PZSurvivorToolkit/QuartermasterTagRules'
local kinds={'Base.Nails','Base.Apple','Base.LargeStone','Base.Apple'}
function Fixture.empty(values)
 for _ in pairs(values)do return false end
 return true
end
function Fixture.place(player)
 local origin=player:getCurrentSquare()
 for radius=2,16 do for dx=-radius,radius do for dy=-radius,radius do
  if math.abs(dx)==radius or math.abs(dy)==radius then
   local x,y,z=origin:getX()+dx,origin:getY()+dy,origin:getZ()
   local clear=true
   for a=-2,6 do for b=-1,1 do
    local sq=getCell():getGridSquare(x+a,y+b,z)
    if not sq or not sq:canStand() or not sq:isFree(false) or sq:getRoom() or sq:getObjects():size()>1 then clear=false end
   end end
   if clear then
    player:teleportTo(x,y,z);player:setX(x+0.5);player:setY(y+0.5)
    player:setLastX(x+0.5);player:setLastY(y+0.5);player:setCurrentSquareFromPosition()
    return {x=x,y=y,z=z}
   end
  end
 end end end
 error('No clear loaded strip for distribution fixture')
end
local function counts(container,result)
 result=result or {}
 for i=0,container:getItems():size()-1 do
  local item=container:getItems():get(i);local id=item:getID();result[id]=(result[id] or 0)+1
  if instanceof(item,'InventoryContainer')then counts(item:getInventory(),result)end
 end
 return result
end
function Fixture.prepare(player,point)
 assert(math.abs(player:getX()-point.x)<2 and math.abs(player:getY()-point.y)<2,'actor has not reached fixture origin')
 local state={player=player,boxes={},ids={},original=counts(player:getInventory())}
 for _,dx in ipairs({-1,3,5})do
  local square=assert(getCell():getGridSquare(point.x+dx,point.y,point.z))
  assert(square:canStand() and square:isFree(true),'fixture crate tile is occupied')
  local box=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
  box:setBlockAllTheSquare(true);box:setIsContainer(true)
  local container=assert(box:getContainer());container:setType('crate');container:setCapacity(100);container:setExplored(true)
  box:getModData().PZSTDistributionFixture=true;square:AddSpecialObject(box)
  state.boxes[#state.boxes+1]=box
  if isServer()then box:transmitCompleteItemToClients();box:transmitModData()end
 end
 local source=state.boxes[1]:getContainer()
 for index,kind in ipairs(kinds)do
  local item=assert(source:AddItem(kind));item:setFavorite(index==4);state.ids[index]=item:getID()
  if isServer()then sendAddItemToContainer(source,item)end
 end
 return state
end
function Fixture.descriptor(state)
 local result={ids=state.ids,boxes={}}
 for _,box in ipairs(state.boxes)do
  local sq=box:getSquare();result.boxes[#result.boxes+1]={x=sq:getX(),y=sq:getY(),z=sq:getZ(),index=box:getObjectIndex()}
 end
 return result
end
function Fixture.resolve(packet)
 local boxes={}
 for _,point in ipairs(packet.boxes)do
  local sq=getCell():getGridSquare(point.x,point.y,point.z)
  if not sq or point.index>=sq:getObjects():size()then return end
  local box=sq:getObjects():get(point.index)
  if not box or not box:hasModData() or not box:getModData().PZSTDistributionFixture then return end
  boxes[#boxes+1]=box
 end
 for _,id in ipairs(packet.ids)do if not boxes[1]:getContainer():getItemById(id)then return end end
 return boxes
end
function Fixture.pasteReceipt(boxes)
 local source,target=boxes[2]:getModData(),boxes[3]:getModData()
 local expected=assert(source.LSBoxItems and source.LSBoxItems['0'],'source designation missing')
 local actual=assert(target.LSBoxItems and target.LSBoxItems['0'],'pasted item designation missing')
 local count=0
 for key,value in pairs(expected)do count=count+1;assert(actual[key]==value,'paste changed selected item')end
 for key in pairs(actual)do assert(expected[key],'paste added an item')end
 assert(count==1 and target.LSBoxPriority and target.LSBoxPriority['0']==5,'paste lost selection/priority')
 assert(not(target.PZSTQuartermasterTagRules and target.PZSTQuartermasterTagRules['0']),'native-only paste gained a rule')
 local revision=assert(target.PZSTQuartermasterTagRulesRevisions and target.PZSTQuartermasterTagRulesRevisions['0'],
  'paste bypassed authority revision')
 return {revision=revision,priority=5,items=count}
end
function Fixture.receipt(player,boxes,ids,original)
 local pools={counts(boxes[1]:getContainer()),counts(boxes[2]:getContainer()),counts(boxes[3]:getContainer()),counts(player:getInventory())}
 local rows={}
 for i,id in ipairs(ids)do
  local target=i==1 and 2 or i==2 and 3 or 1
  local total=0;for _,pool in ipairs(pools)do total=total+(pool[id]or 0)end
  assert(total<=1,'duplicate distribution item '..id)
  if total~=1 or pools[target][id]~=1 then return nil,'awaiting distribution item '..id end
  rows[#rows+1]={id=id,container=target}
 end
 if original then
  for id,count in pairs(original)do assert(pools[4][id]==count,'pre-existing player inventory changed')end
  for id,count in pairs(pools[4])do assert(original[id]==count,'distribution left carried items')end
 end
 -- Confirm the editor's complete field write on both the actor and Host authority, including
 -- clearing the pasted item designation while retaining the accepted rule (a linked preset in Host).
 local md2,md3=boxes[2]:getModData(),boxes[3]:getModData()
 local item=boxes[2]:getContainer():getItemById(ids[1])
 local items2=md2.LSBoxItems and md2.LSBoxItems['0']
 local rule=Rules.getBox(boxes[3],0)
 if isClient() or isServer()then
  local preset=Presets.native()[Fixture.presetName]
  local links=md3.LSBoxPresets and md3.LSBoxPresets['0']
  if not preset or preset.rev~=2 or not links or links[Fixture.presetName]~=preset.gen
   or not Fixture.empty(preset.cats) or not Fixture.empty(preset.items) or rule then return nil,'awaiting complete linked preset' end
  rule=Rules.getPreset(Fixture.presetName,preset)
 end
 if not items2 or not items2[item:getDisplayName()] or not md2.LSBoxPriority or md2.LSBoxPriority['0']~=5
  or (md3.LSBoxItems and md3.LSBoxItems['0']) or not md3.LSBoxPriority or md3.LSBoxPriority['0']~=7
  or not rule or rule.mode~='all' or #rule.include~=2 or rule.include[1]~='food' or rule.include[2]~='perishable'
  or #rule.exclude~=1 or rule.exclude[1]~='meat' then return nil,'awaiting complete saved designations' end
 local favorite=boxes[1]:getContainer():getItemById(ids[4])
 assert(favorite and favorite:isFavorite(),'favorite flag lost')
 return {items=rows,moved=2,retained=2,favorite=true}
end
function Fixture.cleanup(state)
 if isServer()then
  local preset=assert(Presets.native()[Fixture.presetName])
  assert(LootSorter.serverFns.removePreset(state.player,{name=Fixture.presetName,baseGen=preset.gen})=='ok')
 end
 for _,box in ipairs(state.boxes)do
  assert(box:getModData().PZSTDistributionFixture,'refusing foreign crate cleanup')
  box:getSquare():transmitRemoveItemFromSquare(box)
 end
end
return Fixture
