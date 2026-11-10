local P=require 'QueueEnergyPlacement'
local F={names={'front','target','cancelled','tail','unrelated'},loads={front=5,target=3,cancelled=4,tail=2,unrelated=6}}
local AMMO='Base.Bullets9mm';local OTHER='Base.ShotgunShells'
function F.ownStartGuard(action)
 -- Installed Kahlua rawget follows __index; pairs enumerates only owned slots.
 for key,value in pairs(action)do if key=='isValidStart'then return value end end
end
function F.equal(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for key,value in pairs(a)do if not F.equal(value,b[key])then return false end end
 for key in pairs(b)do if a[key]==nil then return false end end
 return true
end
local function inventory(player)
 local found,ammo={},{}
 local root=player:getInventory()
 local function scan(container,path)
  local items=container:getItems()
  for i=0,items:size()-1 do
   local item=items:get(i);local id=item:getID();assert(not found[id],'duplicate actor inventory ID')
   assert(item:getContainer()==container,'inventory owner mismatch');found[id]={item=item,root=container==root,path=path}
   local kind=item:getFullType()
   if kind==AMMO or kind==OTHER then
    ammo[#ammo+1]={id=id,type=kind,class=getClassSimpleName(item),uses=item:getCurrentUses(),factoryCount=item:getCount(),root=container==root,path=path}
   end
   if instanceof(item,'InventoryContainer')then
    local nextPath={};for _,ancestor in ipairs(path)do nextPath[#nextPath+1]=ancestor end;nextPath[#nextPath+1]=id
    scan(item:getItemContainer(),nextPath)
   end
  end
 end
 scan(root,{});table.sort(ammo,function(a,b)return a.id<b.id end);return found,ammo
end
function F.snapshot(s)
 local found,ammo=inventory(s.player);local value={case=s.ids.case,magazines={},ammo=ammo,looseUnits=0,loadedUnits=0}
 for _,entry in ipairs(ammo)do if entry.type==AMMO then value.looseUnits=value.looseUnits+entry.uses end end
 for _,name in ipairs(F.names)do
  local spec=s.ids.magazines[name];local entry=found[spec.id];local item=entry and entry.item
  if item then s.items[name]=item end
  local ammoType=item and item:getAmmoType()
  local record={id=spec.id,present=item~=nil,type=item and item:getFullType()or false,class=item and getClassSimpleName(item)or false,
   loaded=item and item:getCurrentAmmoCount()or -1,maxAmmo=item and item:getMaxAmmo()or -1,
   ammoType=ammoType and ammoType:getItemKey()or false,factoryCount=item and item:getCount()or -1,
   condition=item and item:getCondition()or -1,actorCount=item and 1 or 0,rootCount=entry and entry.root and 1 or 0,
   equipped=item and s.player:isEquipped(item)or false,favorite=item and item:isFavorite()or false}
  value.magazines[name]=record;if item then value.loadedUnits=value.loadedUnits+record.loaded end
 end
 value.totalUnits=value.loadedUnits+value.looseUnits;return value
end
function F.prepare(player,case,mode,placement,proof,previous)
 assert((case=='direct'or case=='bulk')and P.atCentered(player,placement))
 if previous then F.dispose(previous)end
 local root=player:getInventory();local ids={case=case,mode=mode,origin=placement,placementProof=proof,magazines={},seedAmmo={},ammoUnit='currentUses'}
 local state={player=player,ids=ids,items={}}
 local owned={}
 for _,name in ipairs(F.names)do
  local item=assert(root:AddItem('Base.9mmClip'));local ammo=assert(item:getAmmoType())
  assert(getClassSimpleName(item)=='ComboItem'and item:getMaxAmmo()==15 and ammo:getItemKey()==AMMO
   and item:getCount()==1 and not player:isEquipped(item)and not item:isFavorite(),'plain root magazine factory differs')
  item:setCurrentAmmoCount(F.loads[name]);state.items[name]=item;owned[#owned+1]=item
  ids.magazines[name]={id=item:getID(),type=item:getFullType(),class=getClassSimpleName(item),loaded=F.loads[name],
   maxAmmo=item:getMaxAmmo(),ammoType=ammo:getItemKey(),factoryCount=item:getCount(),condition=item:getCondition()}
 end
 for i=1,2 do local item=assert(root:AddItem(AMMO));assert(item:getCurrentUses()==1 and item:getCount()==5,'native loose round unit differs')
  ids.seedAmmo[i]=item:getID();owned[#owned+1]=item end
 local other=assert(root:AddItem(OTHER));assert(other:getCurrentUses()==1 and other:getCount()==6,'unrelated ammo factory differs')
 ids.otherAmmo=other:getID();owned[#owned+1]=other
 state.input=F.snapshot(state);ids.initialAmmo=state.input.ammo
 if isServer()then for _,item in ipairs(owned)do sendAddItemToContainer(root,item)end end
 return state
end
function F.baseline(s)
 local value=F.snapshot(s)
 for _,name in ipairs(F.names)do
  local record=value.magazines[name];local spec=s.ids.magazines[name]
  if not record.present or record.rootCount~=1 or record.actorCount~=1 or record.loaded~=spec.loaded
   or record.class~=spec.class or record.type~=spec.type or record.ammoType~=spec.ammoType
   or record.maxAmmo~=spec.maxAmmo or record.factoryCount~=spec.factoryCount or record.condition~=spec.condition
   or record.equipped or record.favorite then return end
 end
 if not F.equal(value.ammo,s.ids.initialAmmo)then return end
 return value
end
function F.resolve(player,ids)
 if not P.atCentered(player,ids.origin)then return end
 local state={player=player,ids=ids,items={}}
 if F.baseline(state)then return state end
end
function F.verify(s)
 local value=F.snapshot(s);local editing=s.ids.mode=='toolkit'
 for _,name in ipairs(F.names)do
  local record=value.magazines[name];local spec=s.ids.magazines[name]
  local wanted=(name=='unrelated'or editing and name=='cancelled')and spec.loaded or 0
  if not record.present or record.loaded~=wanted or record.actorCount~=1 or record.rootCount~=1
   or record.type~=spec.type or record.class~=spec.class or record.maxAmmo~=spec.maxAmmo
   or record.ammoType~=spec.ammoType or record.factoryCount~=spec.factoryCount or record.condition~=spec.condition
   or record.equipped or record.favorite then return end
 end
 local initial={};for _,entry in ipairs(s.ids.initialAmmo)do initial[entry.id]=entry end
 local produced=0
 for _,entry in ipairs(value.ammo)do
  local prior=initial[entry.id]
  if prior then if not F.equal(prior,entry)then return end;initial[entry.id]=nil
  else
   if entry.type~=AMMO or entry.class~='ComboItem'or entry.uses~=1 or entry.factoryCount~=5 or not entry.root or #entry.path~=0 then return end
   produced=produced+1
  end
 end
 for _ in pairs(initial)do return end
 local decrement=0;for _,name in ipairs(F.names)do decrement=decrement+s.ids.magazines[name].loaded-value.magazines[name].loaded end
 if produced~=decrement or value.totalUnits~=s.input.totalUnits then return end
 return value
end
function F.dispose(s)
 local final=assert(F.verify(s),'unverified magazine fixture cleanup');local root=s.player:getInventory();local remove={}
 for _,name in ipairs(F.names)do remove[s.ids.magazines[name].id]=true end
 for _,id in ipairs(s.ids.seedAmmo)do remove[id]=true end;remove[s.ids.otherAmmo]=true
 local initial={};for _,entry in ipairs(s.ids.initialAmmo)do initial[entry.id]=true end
 for _,entry in ipairs(final.ammo)do if not initial[entry.id]then remove[entry.id]=true end end
 for id in pairs(remove)do
  local item=assert(root:getItemById(id));assert(item:getContainer()==root,'cleanup item left root')
  root:Remove(item);if isServer()then sendRemoveItemFromContainer(root,item)end
 end
end
return F
