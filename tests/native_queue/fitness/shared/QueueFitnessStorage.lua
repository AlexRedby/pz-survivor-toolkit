-- Disposable native fixture evidence only. Never changes action callbacks or effects.
local S={}
local seen=setmetatable({},{__mode='k'})
local function identity(item)return item and item:getID()or false end
local function inner(item)return item:getItemContainer()end
local function matches(item,ref)return item and item:getID()==ref.id and item:getFullType()==ref.kind end
local function clock()
 local time=getGameTime();local hour=time:getTimeOfDay()
 return(time:getNightsSurvived()*24+(hour>=7 and hour-7 or hour+17))*3600000
end
local function clocks(row)
 local ok,problem=pcall(function()
  row.frameNo=getWorld():getFrameNo()
  if isServer()then row.serverTimeMS=GameTime.getServerTimeMills()end
 end)
 if not ok then row.clockError=tostring(problem)end
 return row
end
local function scan(container,parent,rows,found)
 local items=container:getItems()
 for i=0,items:size()-1 do
  local item=items:get(i)
  rows[#rows+1]={id=item:getID(),kind=item:getFullType(),container=parent,favorite=item:isFavorite()}
  local list=found[item:getID()]or{};found[item:getID()]=list
  list[#list+1]={item=item,endpoint=parent}
  if instanceof(item,'InventoryContainer')then scan(inner(item),item:getID(),rows,found)end
 end
end
local function root(player,ref)
 local inventory=player:getInventory();local item=inventory:getItemById(ref.id)
 return matches(item,ref)and item:getContainer()==inventory and item or nil
end
local function sorted(rows)
 table.sort(rows,function(a,b)
  if a.id~=b.id then return a.id<b.id end
  if a.kind~=b.kind then return a.kind<b.kind end
  return tostring(a.container)<tostring(b.container)
 end)
 return rows
end
function S.matches(id)return id=='multi-storage'or id=='multi-storage-closed'end
function S.coreType(id,name,default)return S.matches(id)and name=='hammer'and 'Base.Bag_Satchel'or default end
function S.propContainer(state)return assert(state.items.hammer,'multi-storage source absent'):getItemContainer()end
function S.prepare(state)
 if not S.matches(state.case)then return end
 local player,items=state.player,state.items
 local bag,carrier=assert(items.bag),assert(items.hammer)
 assert(bag:getFullType()=='Base.Bag_Schoolbag'and carrier:getFullType()=='Base.Bag_Satchel','multi-storage core types differ')
 local fanny=assert(player:getInventory():AddItem('Base.Bag_FannyPackFront'))
 items.fanny=fanny
 local spec={bags={},markers={},prop={id=items.dumbbell:getID(),kind='Base.DumbBell',bag=carrier:getID(),favorite=true}}
 for _,name in ipairs({'bag','hammer','fanny'})do
  local item=items[name];item:setFavorite(true)
  local slot=name~='hammer'and item:canBeEquipped()or false
  spec.bags[#spec.bags+1]={name=name,id=item:getID(),kind=item:getFullType(),slot=slot and tostring(slot)or false,
   primary=name=='hammer',secondary=false,favorite=true}
  local marker=assert(inner(item):AddItem('Base.Pencil'));items['multiMarker'..#spec.bags]=marker
  spec.markers[#spec.markers+1]={id=marker:getID(),kind='Base.Pencil',bag=item:getID()}
  if slot then player:setWornItem(slot,item)end
 end
 assert(items.dumbbell:getContainer()==inner(carrier),'multi-storage prop must be created in held carrier')
 items.dumbbell:setFavorite(true)
 player:setPrimaryHandItem(carrier);player:setSecondaryHandItem(items.screwdriver)
 local square=player:getCurrentSquare()
 spec.origin=square and{x=square:getX(),y=square:getY(),z=square:getZ()}or false
 state.ids.multiStorage=spec
 if isServer()then
  sendAddItemToContainer(player:getInventory(),fanny)
  sendClothing(player,fanny:canBeEquipped(),fanny)
 end
end
function S.snapshot(player,spec)
 assert(spec and type(spec.bags)=='table'and spec.prop,'multi-storage specification absent')
 local rows,found={},{};scan(player:getInventory(),'root',rows,found)
 local wanted={};for _,ref in ipairs(spec.bags)do wanted[ref.id]=true end
 for _,ref in ipairs(spec.markers)do wanted[ref.id]=true end;wanted[spec.prop.id]=true
 local squares,known={},{}
 local function square(value)if value and not known[value]then known[value]=true;squares[#squares+1]=value end end
 square(player:getCurrentSquare())
 if spec.origin and getCell then square(getCell():getGridSquare(spec.origin.x,spec.origin.y,spec.origin.z))end
 for _,sq in ipairs(squares)do
  local objects=sq:getWorldObjects()
  for i=0,objects:size()-1 do
   local object=objects:get(i)
   local item=instanceof(object,'IsoWorldInventoryObject')and object:getItem()
   if item and wanted[item:getID()]then
    rows[#rows+1]={id=item:getID(),kind=item:getFullType(),container='world',favorite=item:isFavorite()}
    local list=found[item:getID()]or{};found[item:getID()]=list
    list[#list+1]={item=item,endpoint='world',world={x=sq:getX(),y=sq:getY(),z=sq:getZ(),
     linked=object:getSquare()==sq and item:getWorldItem()==object}}
    if instanceof(item,'InventoryContainer')then scan(inner(item),item:getID(),rows,found)end
   end
  end
 end
 local bags={}
 for _,ref in ipairs(spec.bags)do
  local list=found[ref.id]or{};local actual=list[1];local item=actual and actual.item
  local contents={}
  if item and instanceof(item,'InventoryContainer')then scan(inner(item),ref.id,contents,{})end
  bags[#bags+1]={id=ref.id,kind=item and item:getFullType()or false,favorite=item and item:isFavorite()or false,
   endpoint=actual and actual.endpoint or false,occurrences=#list,contents=sorted(contents),world=actual and actual.world or false}
 end
 local list=found[spec.prop.id]or{};local actual=list[1];local item=actual and actual.item
 local worn={};local entries=player:getWornItems()
 for i=0,entries:size()-1 do local entry=entries:get(i)
  worn[#worn+1]={location=tostring(entry:getLocation()),id=entry:getItem():getID()}
 end
 table.sort(worn,function(a,b)return a.location<b.location end)
 return {bags=bags,items=sorted(rows),primary=identity(player:getPrimaryHandItem()),secondary=identity(player:getSecondaryHandItem()),worn=worn,
  prop={id=spec.prop.id,kind=item and item:getFullType()or false,favorite=item and item:isFavorite()or false,
   endpoint=actual and actual.endpoint or false,occurrences=#list}}
end
function S.resolveReady(state)
 if not S.matches(state.case)then return true end
 local spec=state.ids.multiStorage;if not spec then return false end
 local snapshot=S.snapshot(state.player,spec)
 if snapshot.primary~=state.ids.items.hammer or snapshot.secondary~=state.ids.items.screwdriver then return false end
 for i,ref in ipairs(spec.bags)do
  local item=root(state.player,ref);local bag=snapshot.bags[i]
  if not item or bag.occurrences~=1 or not item:isFavorite()then return false end
  if ref.slot and tostring(item:canBeEquipped())~=ref.slot then return false end
  if ref.slot and state.player:getWornItem(item:canBeEquipped())~=item then return false end
  state.items[ref.name]=item
 end
 for i,ref in ipairs(spec.markers)do
  local count=0
  for _,row in ipairs(snapshot.items)do if row.id==ref.id then
   if row.kind~=ref.kind or row.container~=ref.bag then return false end;count=count+1
  end end
  if count~=1 then return false end
 end
 local prop=snapshot.prop
 return prop.occurrences==1 and prop.kind==spec.prop.kind and prop.endpoint==spec.prop.bag and prop.favorite==true
end
function S.release(state)
 if not S.matches(state.case)then return end
 local player=state.player
 -- Called only by the owner's existing post-receipt idle fixture cleanup.
 player:setPrimaryHandItem(nil);player:setSecondaryHandItem(nil)
 for _,ref in ipairs(state.ids.multiStorage.bags)do
  local item=root(player,ref)
  if item and ref.slot then
   if player:getWornItem(item:canBeEquipped())==item then player:removeWornItem(item,false)end
   if isServer()then sendClothing(player,item:canBeEquipped(),player:getWornItem(item:canBeEquipped()))end
  end
 end
 if isServer()then sendEquip(player)end
end
function S.removePrevious(previous)
 if not previous or not previous.ids.multiStorage then return end
 assert(previous.verified,'unverified previous multi-storage fixture')
 local player=previous.player;local rows,found={},{};scan(player:getInventory(),'root',rows,found)
 local refs={};for _,ref in ipairs(previous.ids.multiStorage.markers)do refs[#refs+1]=ref end
 for _,ref in ipairs(previous.ids.multiStorage.bags)do if ref.name=='fanny'then refs[#refs+1]=ref end end
 local removals={}
 for _,ref in ipairs(refs)do
  local list=found[ref.id]or{};assert(#list==1 and matches(list[1].item,ref),'previous multi-storage item missing, duplicated or wrong type')
  local item=list[1].item;assert(not player:isEquipped(item),'previous multi-storage equipment still worn/held')
  removals[#removals+1]=item
 end
 for _,item in ipairs(removals)do
  local container=item:getContainer();container:Remove(item)
  if isServer()then sendRemoveItemFromContainer(container,item)end
 end
 seen[previous]=nil
end
local function linkedWorld(player,spec,item)
 local world=item:getWorldItem();local square=world and world:getSquare()
 if not square or world:getItem()~=item then return false end
 local here=player:getCurrentSquare();local origin=spec.origin
 if square~=here and not(origin and square:getX()==origin.x and square:getY()==origin.y and square:getZ()==origin.z)then return false end
 local objects=square:getWorldObjects()
 for i=0,objects:size()-1 do if objects:get(i)==world then return true end end
 return false
end
local function refFor(spec,id)
 for _,ref in ipairs(spec.bags)do if ref.id==id then return ref end end
end
-- One native transfer can consume several child Lua actions. Capture only the
-- real queueList after its original merge; never invent extra begin callbacks.
local function sequence(value,nonempty)
 if type(value)~='table'then return false end
 local count=0
 for key in pairs(value)do
  if type(key)~='number'or key%1~=0 or key<1 or key>#value then return false end
  count=count+1
 end
 return count==#value and (not nonempty or count>0)
end
function S.observeMembers(state,action,capture,callback)
 local witness,spec=capture.witness,state.ids.multiStorage
 local groups=action.queueList
 if not sequence(groups,false)then witness.membersError='invalid native queueList';return end
 local batch,new={},{}
 for _,group in ipairs(groups)do
  if type(group)~='table'or not sequence(group.items,true)then witness.membersError='invalid native group';return end
  for _,item in ipairs(group.items)do
   if group.type~=item:getFullType()then witness.membersError='native group type differs';return end
   local id=item:getID();local ref=witness.phase=='recovery'and refFor(spec,id)or spec.prop
   if not ref or not matches(item,ref)or batch[id]then witness.membersError='foreign or duplicate native member';return end
   batch[id]=true
   if not capture.members[id]then
    if witness.phase=='recovery'then
     local world=item:getWorldItem()
     if item:getContainer()~=action.srcContainer or not world or world:getItem()~=item or not world:getSquare()
      or not world:getSquare():getWorldObjects():contains(world)then witness.membersError='unlinked native world member';return end
    elseif root(state.player,ref)~=item then witness.membersError='native return member not in root';return end
    new[#new+1]={id=id,kind=item:getFullType(),source=witness.source,destination=witness.destination}
   end
  end
 end
 if #new>0 then
  witness.members=witness.members or {}
  for _,ref in ipairs(new)do capture.members[ref.id]=true;witness.members[#witness.members+1]=ref end
  local now,snapshot=clock(),S.snapshot(state.player,spec)
  local ids={};for _,ref in ipairs(new)do ids[#ids+1]=ref.id end
  witness.memberCaptures=witness.memberCaptures or {}
  witness.memberCaptures[#witness.memberCaptures+1]=clocks({members=ids,callback=callback,nativeClock=now,snapshot=snapshot})
  witness.membersCallback=callback;witness.membersNativeClock=now;witness.membersSnapshot=snapshot
 end
end
function S.observeStart(state,action,callback)
 if not state or not S.matches(state.case)or not action or action.character~=state.player or not action.item then return end
 local observed=seen[state]or setmetatable({},{__mode='k'});seen[state]=observed
 local previous=observed[action]
 if previous then
  if callback=='ISInventoryTransferAction.checkQueueList'and previous.witness.phase~='placement'then
   if action.srcContainer~=previous.source or action.destContainer~=previous.destination then previous.witness.membersError='changed native endpoints';return end
   S.observeMembers(state,action,previous,callback)
  end
  return
 end
 if callback then return end
 local player,spec=state.player,state.ids.multiStorage;if not spec then return end
 local item=action.item;local inventory=player:getInventory();local ref=refFor(spec,item:getID())
 local phase,source,destination
 if action.Type=='ISDropWorldItemAction'and getmetatable(action)==ISDropWorldItemAction then
  if not ref or not matches(item,ref)or root(player,ref)~=item or not action.isPlaceItem then return end
  phase,source,destination='placement','root','world'
 elseif action.Type=='ISInventoryTransferAction'and getmetatable(action)==ISInventoryTransferAction then
  if ref and matches(item,ref)and action.srcContainer and action.srcContainer:getType()=='floor'and action.destContainer==inventory then
   local snapshot=S.snapshot(player,spec);local bag
   for _,candidate in ipairs(snapshot.bags)do if candidate.id==ref.id then bag=candidate end end
   if not bag or bag.occurrences~=1 or bag.endpoint~='world'or not bag.world or not bag.world.linked
    or item:getContainer()~=action.srcContainer or not linkedWorld(player,spec,item)then return end
   phase,source,destination='recovery','world','root'
  elseif matches(item,spec.prop)and root(player,spec.prop)==item and action.srcContainer==inventory then
   local carrier=refFor(spec,spec.prop.bag);local bag=carrier and root(player,carrier)
   if not bag or action.destContainer~=inner(bag)then return end
   phase,source,destination='return','root',spec.prop.bag
  else return end
 else return end
 local witness=clocks({phase=phase,id=item:getID(),kind=item:getFullType(),source=source,destination=destination,
  callback='ISBaseTimedAction.begin',nativeClock=clock(),snapshot=S.snapshot(player,spec)})
 local capture={witness=witness,source=action.srcContainer,destination=action.destContainer,members={}}
 observed[action]=capture
 if phase~='placement'then S.observeMembers(state,action,capture,'ISBaseTimedAction.begin')end
 return witness
end
function S.placement(state,action,callback,succeeded)
 if not state or not S.matches(state.case)or not action or action.character~=state.player
  or callback~='ISDropWorldItemAction.complete'or action.Type~='ISDropWorldItemAction'
  or getmetatable(action)~=ISDropWorldItemAction or not action.item then return end
 local spec=state.ids.multiStorage;local ref=refFor(spec,action.item:getID())
 if not ref or not matches(action.item,ref)then return end
 if isServer()then
  -- The wire schema contains native constructor arguments, not this client flag.
  local sq=action.sq
  if action.isMultiple~=false or not sq or not sq.getX or not sq.getY or not sq.getZ or sq:getX()~=spec.origin.x
   or sq:getY()~=spec.origin.y or sq:getZ()~=spec.origin.z then return end
 elseif action.isPlaceItem~=true then return end
 local snapshot=S.snapshot(state.player,spec);local placed
 for _,bag in ipairs(snapshot.bags)do if bag.id==ref.id then placed=bag end end
 if not placed or placed.occurrences~=1 or placed.endpoint~='world'or not placed.world or not placed.world.linked
  or placed.world.x~=spec.origin.x or placed.world.y~=spec.origin.y or placed.world.z~=spec.origin.z then return end
 return clocks({phase='placement',id=ref.id,kind=ref.kind,callback=callback,succeeded=succeeded==true,
  nativeClock=clock(),snapshot=snapshot})
end
return S
