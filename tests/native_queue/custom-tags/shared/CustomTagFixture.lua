local Spawn=require 'PinnedItemsFixture'
local C=require 'PZSurvivorToolkit/TagCustomization'
local Tags=require 'PZSurvivorToolkit/ItemTags'
local Categories=require 'PZSurvivorToolkit/ItemCategories'
local JSON=require 'QueueHealthEvents'
local F={module='CustomTagTest',store='PZSTCustomTagFixture',types={'Base.Screwdriver','Base.Screwdriver','Base.PetrolCan','Base.Hammer'}}
function F.text(key)
 local id='UI_CustomTagFixture_'..key
 local value=getText(id)
 assert(value~=id,'Native fixture Unicode translation missing '..id)
 return value
end
F.phases={'Create','Builtin','TypeAdd','ItemRemove','ItemDefault','ItemAdd','ItemReset','TypeRemove','TypeReset',
 'TypeFinal','ItemFinal','Cancel','Conflict','RetiredCreate','RetiredAssign','RetiredDelete'}
function F.contains(tags,id)for _,value in ipairs(tags)do if value==id then return true end end;return false end
function F.prepare(player)
 assert(not getActivatedMods():contains('organizedCategories_core'),'External OC is still active')
 Spawn.types=F.types
 local vehicle,container=Spawn.spawn(player,true,6)
 vehicle:getModData().PZSTCustomTagFixture=true
 local area=assert(vehicle:getAreaCenter(vehicle:getPartById('TruckBed'):getArea()))
 local packet={truckId=vehicle:getId(),x=area:getX(),y=area:getY(),ids={},categories={},scripts={}}
 for index=0,container:getItems():size()-1 do
  local item=container:getItems():get(index);Categories.prepareItem(item)
  packet.ids[#packet.ids+1]=item:getID();packet.categories[#packet.categories+1]=item:getDisplayCategory() or ''
  packet.scripts[#packet.scripts+1]=item:getScriptItem():getDisplayCategory() or ''
 end
 return {vehicle=vehicle,container=container,packet=packet}
end
function F.resolve(packet)
 local function matches(vehicle)
  local part=vehicle and instanceof(vehicle,'BaseVehicle')and vehicle:getPartById('TruckBed')
  local container=part and part:getItemContainer()
  return container and container:getItemById(packet.ids[1])and container
 end
 local vehicle=getVehicleById(packet.truckId);local container=matches(vehicle)
 if not container then
  for dx=-8,8 do for dy=-8,8 do
   local square=getCell():getGridSquare(math.floor(packet.x)+dx,math.floor(packet.y)+dy,0)
   if square and not container then
    local moving=square:getMovingObjects()
    for index=0,moving:size()-1 do
     local candidate=moving:get(index);local found=matches(candidate)
     if found then vehicle,container=candidate,found;break end
    end
   end
  end end
 end
 if not container then return end
 for _,id in ipairs(packet.ids)do if not container:getItemById(id)then return end end
 -- DisplayCategory is a prepared runtime projection, not a serialized native
 -- item field. Establish it once after native load, then phase checks never
 -- prepare again so custom-tag edits cannot conceal category writes.
 local raw,prepared={},{}
 for _,id in ipairs(packet.ids)do
  local item=container:getItemById(id);raw[#raw+1]=item:getDisplayCategory()or ''
  Categories.prepareItem(item);prepared[#prepared+1]=item:getDisplayCategory()or ''
 end
 print('[CUSTOM_TAG_TEST] CATEGORY_BASELINE '..JSON.encode({role=isServer()and 'server'or 'client',raw=raw,prepared=prepared}))
 packet.truckId=vehicle:getId()
 return {vehicle=vehicle,container=container,packet=packet}
end
function F.item(state,index)return state.container:getItemById(state.packet.ids[index])end
function F.baseCheck(state)
 assert(state.container:getItems():size()==4,'Native items lost/duplicated')
 for index,id in ipairs(state.packet.ids)do
  local item=assert(F.item(state,index),'Exact native fixture ID missing')
  assert(item:getID()==id and item:getFullType()==F.types[index],'Native identity changed')
  assert((item:getDisplayCategory()or '')==state.packet.categories[index],'Instance DisplayCategory changed')
  assert((item:getScriptItem():getDisplayCategory()or '')==state.packet.scripts[index],'ScriptItem loot category changed')
 end
end
function F.check(phase,state)
 F.baseCheck(state)
 local packet=state.packet;local tag=packet.tag
 if phase=='Create'then
  local definition=tag and C.definition(tag)
  return definition and definition.name==F.text('Main')and definition.icon=='Item_Axe'and math.abs(definition.color.r-.2)<.00001
 end
 if not tag or not C.isActive(tag)then return false end
 local tool=C.definition('tool')
 local expectedName=(phase=='Conflict'or phase=='RetiredCreate'or phase=='RetiredAssign'or phase=='RetiredDelete'or phase=='Reload')and F.text('Shared')or F.text('Builtin')
 if not tool or tool.name~=expectedName or tool.icon~='Item_Hammer'or math.abs(tool.color.r-.4)>.00001 then return false end
 local one,two,hammer=F.item(state,1),F.item(state,2),F.item(state,4)
 local first,second,last=Tags.forItem(one),Tags.forItem(two),Tags.forItem(hammer)
 local typeDelta=C.typeDelta(one:getFullType())
 if phase=='Builtin'then return true end
 if phase=='TypeReset'then return not C.hasEntries(typeDelta)and F.contains(first,'tool')and not F.contains(first,tag)end
 if typeDelta[tag]~='add'then return false end
 if phase=='TypeRemove'then return not F.contains(first,'tool')and typeDelta.tool=='remove'end
 if not F.contains(first,'tool')then return false end
 if phase=='ItemRemove'or phase=='ItemFinal'or phase=='Cancel'or phase=='Conflict'or phase=='RetiredCreate'
  or phase=='RetiredAssign'or phase=='RetiredDelete'or phase=='Reload'then
  if F.contains(first,tag)or C.itemDelta(one)[tag]~='remove'then return false end
 else if not F.contains(first,tag)then return false end end
 if not F.contains(second,tag)then return false end
 if phase=='ItemAdd'then return F.contains(last,tag)and C.itemDelta(hammer)[tag]=='add'end
 if phase=='ItemDefault'and C.itemDelta(one)[tag]~=nil then return false end
 if phase=='ItemReset'and C.hasEntries(C.itemDelta(hammer))then return false end
 if phase=='RetiredCreate'then return packet.retired and C.isActive(packet.retired)and C.definition(packet.retired).name==F.text('Retired')end
 if phase=='RetiredAssign'then return packet.retired and F.contains(last,packet.retired)end
 if phase=='RetiredDelete'or phase=='Reload'then
  if not packet.retired or C.isActive(packet.retired)or not C.isValidId(packet.retired)then return false end
  local rule=assert(Tags.normalizeRule({mode='all',include={packet.retired},exclude={}}))
  if #rule.include~=1 or Tags.matchesRule(last,rule)or F.contains(last,packet.retired)then return false end
  if C.itemDelta(hammer)[packet.retired]~='add'then return false end
 end
 return true
end
function F.receipt(role,state)
 return {role=role,tag=state.packet.tag,retired=state.packet.retired,revision=C.getRevision(),ids=state.packet.ids,
  truckId=state.packet.truckId,shared=true,exact=true,tombstone=true,categoriesUnchanged=true,
  noOC=not getActivatedMods():contains('organizedCategories_core')}
end
return F
