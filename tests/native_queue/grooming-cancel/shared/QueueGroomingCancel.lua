-- Disposable setup ends at baseline. All later helpers only observe native state.
local F={cases={'borrowed-scissors','style-no-tool','styled-scissors','beard-trim','dye-hair','dye-beard'}}
function F.baseCase(caseID)return (caseID:gsub('^active%-',''))end
function F.active(caseID)return caseID:sub(1,7)=='active-'end
function F.haircut(caseID)caseID=F.baseCase(caseID);return caseID=='borrowed-scissors'or caseID=='style-no-tool'or caseID=='styled-scissors'end
function F.borrowed(state)return state.scissors or state.razor or state.dye end
local function id(item)return item and item:getID()or false end
local function find(container,wanted)
 local items=container:getItems()
 for i=0,items:size()-1 do
  local item=items:get(i);if item:getID()==wanted then return item end
  if instanceof(item,'InventoryContainer')then local found=find(item:getItemContainer(),wanted);if found then return found end end
 end
end
function F.find(player,wanted)return find(player:getInventory(),wanted)end
function F.refresh(state)
 for name,wanted in pairs(state.ids.items)do
  local item=F.find(state.player,wanted)
  if not item or item:getFullType()~=state.ids.types[name]then return false end
  state[name]=item
 end
 return true
end
function F.appearance(player)
 local visual=player:getHumanVisual();local color=visual:getHairColor();local beard=visual:getBeardColor()
 return {model=visual:getHairModel(),nonAttached=visual:getNonAttachedHair()or false,
  color={r=color:getRedFloat(),g=color:getGreenFloat(),b=color:getBlueFloat()},beardModel=visual:getBeardModel()or'',
  beardColor={r=beard:getRedFloat(),g=beard:getGreenFloat(),b=beard:getBlueFloat()}}
end
function F.fluid(item)
 local fluid=assert(item:getFluidContainer(),'native dye fluid container missing');local color=fluid:getColor()
 return {id=item:getID(),amount=fluid:getAmount(),color={r=color:getR(),g=color:getG(),b=color:getB()}}
end
function F.snapshot(state)
 assert(F.refresh(state),'exact grooming item replica unavailable')
 local player=state.player;local rows,worn={},{}
 local function scan(container,parent)
  local values=container:getItems()
  for i=0,values:size()-1 do
   local item=values:get(i);rows[#rows+1]={id=item:getID(),kind=item:getFullType(),container=parent,favorite=item:isFavorite()}
   if instanceof(item,'InventoryContainer')then scan(item:getItemContainer(),item:getID())end
  end
 end
 scan(player:getInventory(),'root');table.sort(rows,function(a,b)return a.id<b.id end)
 local values=player:getWornItems()
 for i=0,values:size()-1 do local v=values:get(i);worn[#worn+1]={id=v:getItem():getID(),location=tostring(v:getLocation())}end
 table.sort(worn,function(a,b)return a.location<b.location end)
 return {case=state.ids.case,male=not player:isFemale(),items=rows,primary=id(player:getPrimaryHandItem()),secondary=id(player:getSecondaryHandItem()),worn=worn,
  torchActive=state.torch:isActivated(),frontPages=player:getAlreadyReadPages(state.front:getFullType()),
  tailPages=player:getAlreadyReadPages(state.tail:getFullType()),appearance=F.appearance(player),
  gel=state.gel and{id=state.gel:getID(),uses=state.gel:getCurrentUses()}or false,dye=state.dye and F.fluid(state.dye)or false}
end
function F.same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)=='number'then return math.abs(a-b)<.00001 end
 if type(a)~='table'then return a==b end
 for key,value in pairs(a)do if not F.same(value,b[key])then return false end end
 for key in pairs(b)do if a[key]==nil then return false end end
 return true
end
function F.sameSetup(a,b)
 local left,right={},{}
 for key,value in pairs(a)do if key~='appearance'then left[key]=value end end
 for key,value in pairs(b)do if key~='appearance'then right[key]=value end end
 if isClient()and b.dye then right.dye={id=b.dye.id,amount=b.dye.amount,color=F.fluidWireColor(b.dye.color)}end
 return F.same(left,right)and a.appearance.model==b.appearance.model and a.appearance.nonAttached==b.appearance.nonAttached and a.appearance.beardModel==b.appearance.beardModel
end
local function styles(player,caseID)
 local owner=getHairStylesInstance();local values=player:isFemale()and owner:getAllFemaleStyles()or owner:getAllMaleStyles()
 local list={};for i=0,values:size()-1 do list[#list+1]=values:get(i)end
 table.sort(list,function(a,b)return a:getName()<b:getName()end)
 local target
 if caseID=='style-no-tool'then
  for _,style in ipairs(list)do if style:isAttachedHair()and style:getName()~=''and not style:isNoChoose()then target=style;break end end
 else
  local name=caseID=='styled-scissors'and'MohawkFan'or(player:isFemale()and'Bob'or'CrewCut')
  target=player:isFemale()and owner:FindFemaleStyle(name)or owner:FindMaleStyle(name)
 end
 assert(target and target:getName()~='','required actual actor-native hairstyle unavailable')
 local initial
 for _,style in ipairs(list)do
  local name=style:getName();local plain=name~=''
  for _,part in ipairs({'Bald','Mohawk','Spike','Greased','Buffont'})do if name:find(part,1,true)then plain=false end end
  local offered=target:isAttachedHair()and target:getLevel()<=style:getLevel()or not target:isAttachedHair()and target:getLevel()<style:getLevel()
  local trims=style:getTrimChoices()
  for i=0,trims:size()-1 do if trims:get(i)==target:getName()then offered=true end end
  if plain and offered and not style:isAttachedHair()and not style:isNoChoose()and name~=target:getName()
   and style:getLevel()>=target:getLevel()and(not initial or style:getLevel()>initial:getLevel())then initial=style end
 end
 assert(initial,'no genuine long hair baseline for selected actor-native style')
 return initial:getName(),target:getName(),initial:getLevel(),target:getLevel(),target:isAttachedHair()
end
local function clearHead(player)
 local items=player:getWornItems();local remove={}
 for i=0,items:size()-1 do
  local row=items:get(i);local slot=tostring(row:getLocation())
  if slot:find('hat',1,true)or slot:find('head',1,true)or slot:find('mask',1,true)then remove[#remove+1]={item=row:getItem(),location=row:getLocation()}end
 end
 for _,row in ipairs(remove)do player:removeWornItem(row.item,false);if isServer()then sendClothing(player,row.location,nil)end end
end
local function equipment(state)
 local p=state.player;clearHead(p)
 p:setWornItem(state.bag:canBeEquipped(),state.bag)
 if state.hat then p:setWornItem(state.hat:getBodyLocation(),state.hat)end
 if state.mask then p:setWornItem(state.mask:getBodyLocation(),state.mask)end
 p:setPrimaryHandItem(state.torch);p:setSecondaryHandItem(state.secondary)
 state.torch:setUsedDelta(1);state.torch:setActivated(true)
 local visual=p:getHumanVisual();visual:setHairModel(state.ids.initialStyle);visual:setNonAttachedHair(nil)
 if state.ids.initialBeard then visual:setBeardModel(state.ids.initialBeard)end
 p:resetModel()
 for _,name in ipairs({'front','tail'})do
  local book=state[name];local pages=state.ids[name..'Initial'];book:setAlreadyReadPages(pages);p:setAlreadyReadPages(book:getFullType(),pages)
 end
 p:setPerkLevelDebug(Perks.Woodwork,0);p:setPerkLevelDebug(Perks.Doctor,0)
end
function F.prepare(player,caseID,previous)
 local selectedCase=caseID;caseID=F.baseCase(caseID)
 assert(not isClient(),'grooming prepare requires authority')
 assert(not player:isFemale(),'grooming fixture requires native male character creation')
 if previous then
  for _,wanted in pairs(previous.items)do
   local item=F.find(player,wanted)
   if item then
    if player:isEquippedClothing(item)then player:removeWornItem(item,false)end
    if player:getPrimaryHandItem()==item then player:setPrimaryHandItem(nil)end
    if player:getSecondaryHandItem()==item then player:setSecondaryHandItem(nil)end
    local container=item:getContainer();container:Remove(item);if isServer()then sendRemoveItemFromContainer(container,item)end
   end
  end
 end
 player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false);require('QueueEnergyPlacement')(player)
 local root=player:getInventory();local initial,target,initialLevel,targetLevel,targetAttached=styles(player,F.haircut(caseID)and caseID or'borrowed-scissors')
 local actionKind,producer,borrowed='ISCutHair','ISCharacterScreen.onCutHair',caseID~='style-no-tool'and'scissors'or false
 local initialBeard,targetBeard,beardInitialLevel,beardTargetLevel=false,false,false,false
 if not F.haircut(caseID)then
  target,targetLevel,targetAttached=initial,initialLevel,false
  initialBeard='LongScruffy'
  local beard=assert(getBeardStylesInstance():FindStyle(initialBeard),'native initial beard missing')
  beardInitialLevel=beard:getLevel()
  if caseID=='beard-trim'then
   actionKind,producer,borrowed='ISTrimBeard','ISCharacterScreen.onTrimBeard','razor';targetBeard='Moustache'
   local trim=assert(getBeardStylesInstance():FindStyle(targetBeard),'native trim target missing');beardTargetLevel=trim:getLevel()
   assert(beardTargetLevel<beardInitialLevel,'beard transition is not offered by actual native menu')
  else actionKind,producer,borrowed='ISDyeHair','ISInventoryPaneContextMenu.onDyeHair','dye'end
 end
 local ids={case=selectedCase,actor=player:getOnlineID(),male=true,items={},types={},initialStyle=initial,targetStyle=target,
  initialLevel=initialLevel,targetLevel=targetLevel,targetAttached=targetAttached,duration=actionKind=='ISDyeHair'and 120 or(targetAttached and 100 or 300),
  actionKind=actionKind,producer=producer,borrowed=borrowed,initialBeard=initialBeard,targetBeard=targetBeard,
  beardInitialLevel=beardInitialLevel,beardTargetLevel=beardTargetLevel}
 local state={player=player,ids=ids}
 local function seed(name,kind,container)
  local item=assert((container or root):AddItem(kind));state[name]=item;ids.items[name]=item:getID();ids.types[name]=kind;return item
 end
 seed('bag','Base.Bag_Schoolbag'):setFavorite(true)
 seed('content','Base.Paperclip',state.bag:getItemContainer())
 seed('front','Base.BookCarpentry1');seed('tail','Base.BookFirstAid1')
 seed('torch','Base.Torch');seed('secondary','Base.Screwdriver')
 if borrowed=='scissors'then seed('scissors','Base.Scissors',state.bag:getItemContainer()):setFavorite(true)end
 if borrowed=='razor'then seed('razor','Base.Razor',state.bag:getItemContainer()):setFavorite(true)end
 if borrowed=='dye'then
  seed('dye','Base.HairDyeCommon',state.bag:getItemContainer()):setFavorite(true)
  assert(F.fluid(state.dye).amount==1,'native dye must start with its full1.0fluid')
 end
 if caseID=='borrowed-scissors'or caseID=='dye-hair'then seed('hat','Base.Hat_BaseballCap')end
 if caseID=='dye-beard'then seed('mask','Base.Hat_DustMask')end
 if caseID=='styled-scissors'then
  seed('gel','Base.Hairgel');state.gel:setCurrentUses(state.gel:getMaxUses());assert(state.gel:getCurrentUses()==20,'native Hairgel must start at20uses')
 end
 for _,name in ipairs({'front','tail'})do ids[name..'Total']=state[name]:getNumberOfPages();ids[name..'Initial']=ids[name..'Total']-(name=='front'and 3 or 1)end
 equipment(state)
 if isServer()then
  for _,wanted in pairs(ids.items)do local item=assert(F.find(player,wanted));if item:getContainer()==root then sendAddItemToContainer(root,item)end end
  sendClothing(player,state.bag:canBeEquipped(),state.bag)
  if state.hat then sendClothing(player,state.hat:getBodyLocation(),state.hat)end
  if state.mask then sendClothing(player,state.mask:getBodyLocation(),state.mask)end
  sendEquip(player);sendHumanVisual(player);syncItemActivated(player,state.torch)
 end
 ids.baseline=F.snapshot(state);return state
end
local resolved={}
function F.resolve(player,ids)
 local state=resolved[ids]or{player=player,ids=ids}
 if isClient()and player:getOnlineID()~=ids.actor or not F.refresh(state)then return end
 if not resolved[ids]then
  equipment(state)
  player:resetModel();if isClient()then player:updateHandEquips();sendHumanVisual(player)end
  resolved[ids]=state
 end
 if not F.sameSetup(F.snapshot(state),ids.baseline)then return end
 return state
end
function F.source(state,container)
 local owner=container and container:getContainingItem()
 return owner and owner:getID()==state.ids.items.bag and owner:getFullType()==state.ids.types.bag
end
local function clone(value)
 if type(value)~='table'then return value end
 local result={};for key,v in pairs(value)do result[key]=clone(v)end;return result
end
local function float32(value)
 local sample=Color.new();sample:set(value,0,0,1);return sample:getR()
end
function F.fluidWireColor(color)
 local result={}
 for key,value in pairs(color)do
  local biased=float32(float32(value*255)-128)
  local packed=biased<0 and math.ceil(biased)or math.floor(biased)
  result[key]=float32((packed+128)/255)
 end
 return result
end
local function visualColor(color,remote)
 if not remote then return clone(color)end
 local value=ImmutableColor.new(color.r,color.g,color.b,1)
 local packed=ImmutableColor.new(value:getRedInt()/255,value:getGreenInt()/255,value:getBlueInt()/255,1)
 return {r=packed:getRedFloat(),g=packed:getGreenFloat(),b=packed:getBlueFloat()}
end
function F.expectedAppearance(state,baseline,native,remote,authority)
 local result=clone(baseline.appearance);local ids=state.ids
 if not native then return result end
 if ids.actionKind=='ISCutHair'then result.model=ids.targetStyle;result.nonAttached=ids.targetAttached and ids.initialStyle or false
 elseif ids.actionKind=='ISTrimBeard'then result.beardModel=ids.targetBeard
 elseif F.baseCase(ids.case)=='dye-hair'then result.color=visualColor((remote and authority or baseline).dye.color,remote)
 else result.beardColor=visualColor((remote and authority or baseline).dye.color,remote)end
 return result
end
function F.effectsMatch(state,value,baseline,native,remote,authority)
 if not F.same(value.appearance,F.expectedAppearance(state,baseline,native,remote,authority))then return false end
 if state.gel and value.gel.uses~=(native and 19 or 20)then return false end
 if state.dye then
  local expected=clone(baseline.dye);if native then expected.amount=math.max(0,expected.amount-.5)end
  if not F.same(value.dye,expected)then return false end
 end
 return true
end
function F.restored(state,snapshot)
 local baseline=state.ids.baseline
 return F.same(snapshot.items,baseline.items)and snapshot.primary==baseline.primary and snapshot.secondary==baseline.secondary
  and F.same(snapshot.worn,baseline.worn)and snapshot.torchActive==true
end
return F
