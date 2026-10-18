local JSON=require 'QueueHealthEvents'
local states={}
local function send(player,command,value)
 print('[FORGE_TEST] '..command..' '..JSON.encode(value))
 sendServerCommand(player,'ForgeTest',command,value)
end
local function item(root,kind,ids)
 local value=assert(root:AddItem(kind),'fixture item missing '..kind)
 ids[#ids+1]=value:getID();sendAddItemToContainer(root,value);return value
end
local function outputs(root,kind)
 local result={}
 for i=0,root:getItems():size()-1 do local value=root:getItems():get(i)
  if value:getFullType()==kind then result[#result+1]=value:getID()end
 end
 return result
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='ForgeTest'then return end
 local ok,problem=pcall(function()
  local key=player:getOnlineID();local root=player:getInventory()
  if command=='Prepare'then
   local prior=states[key]
   if prior then
    for _,id in ipairs(prior.items)do local value=root:getItemById(id)
     if value then player:removeFromHands(value);sendRemoveItemFromContainer(root,value);root:Remove(value)end
    end
    if prior.forge then prior.square:transmitRemoveItemFromSquare(prior.forge)end
    if prior.clutter and prior.clutter:getObjectIndex()>=0 then prior.square:transmitRemoveItemFromSquare(prior.clutter)end
   end
   local state={case=args.case,items={},materials={},tools={}};states[key]=state
   local hand=args.case=='handcraft'
   state.outputKind=hand and 'Base.Plank'or 'Base.CrudeBlade';state.expected=hand and 3 or 1
   state.baseline=outputs(root,state.outputKind)
   local materialKinds=hand and {'Base.Log'}or {'Base.Charcoal','Base.IronBarQuarter'}
   local toolKinds=hand and {'Base.Saw'}or {'Base.Hammer','Base.Tongs'}
   for _,kind in ipairs(materialKinds)do state.materials[#state.materials+1]=item(root,kind,state.items):getID()end
   for _,kind in ipairs(toolKinds)do state.tools[#state.tools+1]=item(root,kind,state.items):getID()end
   local result={case=state.case,materials=state.materials,tools=state.tools,baseline=state.baseline,
    outputKind=state.outputKind,expected=state.expected}
   if not hand then
    local here=player:getSquare();local square=assert(getCell():getGridSquare(here:getX()+1,here:getY(),here:getZ()))
    state.square=square
    if args.case=='forge-shift'then
     local clutter=IsoObject.new(getCell(),square,'carpentry_02_40')
     square:AddTileObject(clutter);clutter:transmitCompleteItemToClients();state.clutter=clutter
    end
    local forge=IsoThumpable.new(getCell(),square,'crafted_01_61',false,{})
    forge:getModData().ForgeTestCase=state.case
    GameEntityFactory.CreateIsoObjectEntity(forge,assert(getScriptManager():getGameEntityScript('Base.Forge_Primitive_Forge')),true)
    square:AddSpecialObject(forge);forge:transmitCompleteItemToClients();state.forge=forge
    assert(forge:getComponent(ComponentType.CraftBench),'native Primitive Forge has no CraftBench')
    result.x,result.y,result.z=square:getX(),square:getY(),square:getZ()
    result.index=forge:getObjectIndex();result.entityID=forge:getEntityNetID()
    result.expectedIndex=result.index-(state.clutter and 1 or 0)
   end
   send(player,'Prepared',result)
  elseif command=='Shift'then
   local state=assert(states[key]);assert(state.case=='forge-shift'and state.clutter)
   state.square:transmitRemoveItemFromSquare(state.clutter)
   -- Do not refresh the forge ID here: this is the native removal being tested.
   send(player,'Shifted',{case=state.case,index=state.forge:getObjectIndex()})
  elseif command=='Verify'then
   local state=assert(states[key]);local remaining={};local tools={};local fresh={};local baseline={}
   for _,id in ipairs(state.baseline)do baseline[id]=true end
   for _,id in ipairs(state.materials)do if root:getItemById(id)then remaining[#remaining+1]=id end end
   for _,id in ipairs(state.tools)do if root:getItemById(id)then tools[#tools+1]=id end end
   for _,id in ipairs(outputs(root,state.outputKind))do if not baseline[id]then fresh[#fresh+1]=id end end
   send(player,'Verified',{case=state.case,remaining=remaining,tools=tools,outputs=fresh,
    consumed=#state.materials-#remaining,expectedConsumed=#state.materials,expected=state.expected,
    exactEffects=#remaining==0 and #tools==#state.tools and #fresh==state.expected})
  end
 end)
 if not ok then send(player,'Failed',{error=tostring(problem)})end
end)
