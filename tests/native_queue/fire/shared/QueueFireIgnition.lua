local Test={cases={
 literature={mode='literature',class='ISLightFromLiterature',duration=100},
 petrol={mode='petrol',class='ISLightFromPetrol',duration=20},
 ['last-match']={mode='petrol',class='ISLightFromPetrol',duration=20,lastMatch=true},
 ['kindle-retry']={mode='kindle',class='ISLightFromKindle',duration=1500},
 ['bbq-fuel']={mode='fuel',class='ISBBQAddFuel',duration=100,bbq=true},
 ['bbq-literature']={mode='literature',class='ISBBQLightFromLiterature',duration=100,bbq=true},
 ['bbq-petrol']={mode='petrol',class='ISBBQLightFromPetrol',duration=20,bbq=true,lastMatch=true},
}}
local selection=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local sessions,trials={},{}
local function count(container,id)
 local n=0
 for i=0,container:getItems():size()-1 do
  local item=container:getItems():get(i)
  if item:getID()==id then n=n+1 end
  if instanceof(item,'InventoryContainer') then n=n+count(item:getItemContainer(),id) end
 end
 return n
end
local function uses(item)return instanceof(item,'DrainableComboItem') and item:getCurrentUses() or 0 end
local function amount(item)local fluid=item:getFluidContainer();return fluid and fluid:getAmount() or 0 end
local function fuel(state)return state.spec.bbq and state.target:getFuelAmount() or state.target.fuelAmt end
local function lit(state)return state.spec.bbq and state.target:isLit() or not state.spec.bbq and state.target.isLit end
function Test.observe()
 for _,state in pairs(sessions) do
  if state.effectFuel==nil and (state.spec.mode=='fuel' and fuel(state)>0 or lit(state)) then
   state.effectFuel=fuel(state)
  end
 end
end
Events.OnTick.Add(function()if not isClient() then Test.observe() end end)
function Test.prepare(player,case)
 local name=player:getUsername()
 assert(not sessions[name],'duplicate ignition preparation')
 local spec=assert(Test.cases[case],'unknown ignition case')
 require 'Camping/SCampfireSystem'
 require 'Camping/ISCampingMenu'
 local origin=require('QueueEnergyPlacement')(player)
 local square=assert(getCell():getGridSquare(origin:getX()+1,origin:getY(),origin:getZ()))
 local object=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
 object:setCanPassThrough(true);object:setIsContainer(true)
 local crate=assert(object:getContainer());crate:setType('crate');crate:setCapacity(100);crate:setExplored(true)
 object:getModData().QueueFireOwner=name;square:AddSpecialObject(object)
 local state={spec=spec,player=player,object=object,crate=crate,resources={}}
 local root=player:getInventory()
 local function add(role,kind,options)
  options=options or {}
  local item=assert((options.root and root or crate):AddItem(kind),'missing ignition item '..kind)
  if options.uses then item:setCurrentUses(options.uses) end
  if role=='petrol' then local fluid=assert(item:getFluidContainer());fluid:Empty();fluid:addFluid(Fluid.Petrol,2) end
  local resource={role=role,id=item:getID(),kind=kind,condition=item:getCondition(),initialUses=uses(item),initialAmount=amount(item),
   expectedUse=options.use or 0,expectedAmountDelta=role=='petrol' and ZomboidGlobals.LightFromPetrolAmount or 0,
   consumed=options.consumed==true,optionalConsume=options.optional==true,returnToSource=options.returns==true,
   source=options.root and 'root' or 'crate'}
  state.resources[#state.resources+1]=resource
  if options.root and isServer() then sendAddItemToContainer(root,item) end
  return item
 end
 local primary
 if spec.mode=='fuel' then primary=add('fuel','Base.Log',{consumed=true})
 elseif spec.mode=='literature' then
  primary=add('tinder','Base.SheetPaper2',{consumed=true})
  add('starter','Base.Matches',{uses=2,use=1,returns=true})
 elseif spec.mode=='petrol' then
  add('starter','Base.Matches',{uses=spec.lastMatch and 1 or 2,use=1,consumed=spec.lastMatch,returns=true})
  add('petrol','Base.PetrolCan')
 else
  add('plank','Base.PercedWood',{returns=true})
  add('stick','Base.WoodenStick2',{optional=true,returns=true})
  for i=1,3 do add('reserve'..i,'Base.WoodenStick2',{root=true,optional=true}) end
 end
 if isServer() then object:transmitCompleteItemToClients() end
 local initialFuel=spec.mode~='fuel' and 360 or 0
 local target
 if spec.bbq then
  target=IsoBarbecue.new(getCell(),square,getSprite('appliances_cooking_01_35'))
  square:AddTileObject(target);target:setFuelAmount(initialFuel)
  assert(not target:isPropaneBBQ(),'ignition fixture requires charcoal BBQ')
  if isServer() then target:transmitCompleteItemToClients() end
 else
  target=assert(SCampfireSystem.instance:addCampfire(square));if initialFuel>0 then target:addFuel(initialFuel) end
 end
 local book=assert(root:AddItem('Base.BookCarpentry1'))
 book:setAlreadyReadPages(book:getNumberOfPages()-1);player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 if isServer() then sendAddItemToContainer(root,book) end
 local key=name..':'..case;trials[key]=(trials[key] or 0)+1
 assert(trials[key]<=(spec.mode=='kindle' and 8 or 1),'ignition trial limit exceeded')
 local ids={case=case,trial=trials[key],book=book:getID(),actionType=spec.class,nativeDuration=spec.duration,
  x=square:getX(),y=square:getY(),z=square:getZ(),objectIndex=spec.bbq and target:getObjectIndex() or target:getIsoObject():getObjectIndex(),
  crateX=square:getX(),crateY=square:getY(),crateZ=square:getZ(),crateIndex=object:getObjectIndex(),
  spawn={x=origin:getX()+0.5,y=origin:getY()+0.5,z=origin:getZ()},resources=state.resources,initialFuel=initialFuel,
  expectedFuel=initialFuel+(primary and (spec.bbq and math.floor(ISCampingMenu.getFuelDurationForItem(primary)) or ISCampingMenu.getFuelDurationForItem(primary)) or 0)}
 state.target,state.ids=target,ids;sessions[name]=state
 assert(not lit(state),'ignition target starts lit')
 print('[FIRE_TEST] PREPARED '..JSON.encode(ids));return ids
end
function Test.verify(player,case)
 local name=player:getUsername();local state=assert(sessions[name],'missing ignition session')
 assert(state.ids.case==case,'out-of-order ignition receipt');Test.observe()
 local enabled=selection.mode=='toolkit'
 local wantedLit=state.spec.mode~='fuel'
 local root=player:getInventory();local resources={}
 local exhausted=state.spec.mode=='kindle'
 for _,entry in ipairs(state.resources) do
  local sc,rc=count(state.crate,entry.id),count(root,entry.id)
  local consumed=sc+rc==0
  if sc+rc>1 or consumed~=entry.consumed and not entry.optionalConsume then return nil,'ignition resource conservation differs '..entry.role end
  local item=state.crate:getItemById(entry.id) or root:getItemById(entry.id)
  if item then
   if item:getFullType()~=entry.kind or item:getCondition()~=entry.condition
    or uses(item)~=entry.initialUses-entry.expectedUse or math.abs(amount(item)-(entry.initialAmount-entry.expectedAmountDelta))>0.000001 then
    return nil,'ignition exact resource delta differs '..entry.role
   end
   local wantedSource=entry.source=='crate' and entry.returnToSource and enabled
   if wantedSource and sc~=1 or (entry.source=='root' or entry.role=='petrol') and rc~=1 then return nil,'ignition exact return differs '..entry.role..' source='..sc..' root='..rc end
  end
  if entry.optionalConsume and not consumed then exhausted=false end
  resources[#resources+1]={role=entry.role,id=entry.id,kind=entry.kind,sourceCount=sc,rootCount=rc,
   condition=item and item:getCondition() or entry.condition,uses=item and uses(item) or 0,amount=item and amount(item) or 0,consumed=consumed}
 end
 -- Native Kindle can exhaust every stick without lighting; that is a valid terminal outcome.
 local spentSticks=exhausted and not lit(state) and fuel(state)==state.ids.initialFuel
 if spentSticks then state.effectFuel=state.ids.initialFuel end
 if (lit(state)~=wantedLit and not spentSticks) or state.effectFuel~=state.ids.expectedFuel then return nil,'native ignition/fuel effect differs' end
 local book=root:getItemById(state.ids.book)
 if not book or book:getContainer()~=root then return nil,'ignition reader identity lost' end
 local read=book:getAlreadyReadPages()==book:getNumberOfPages()
 if enabled and not read then return nil,'ignition independent reader incomplete' end
 local result={case=case,trial=state.ids.trial,bookId=state.ids.book,resources=resources,lit=lit(state),
  effectFuel=state.effectFuel,fuel=fuel(state),tailRead=read}
 print('[FIRE_TEST] AUTHORITY '..JSON.encode(result))
 sessions[name]=nil
 if state.spec.bbq then state.target:getSquare():transmitRemoveItemFromSquare(state.target)
 else SCampfireSystem.instance:removeCampfire(state.target) end
 assert(state.object:getModData().QueueFireOwner==name,'foreign ignition crate cleanup refused')
 state.object:getSquare():transmitRemoveItemFromSquare(state.object)
 -- Retired trial inputs must not be selected by a later native Kindle retry.
 for _,entry in ipairs(state.resources) do
  local item=root:getItemById(entry.id)
  if item and item:getContainer()==root then root:Remove(item);if isServer() then sendRemoveItemFromContainer(root,item) end end
 end
 return result
end
return Test
