-- Disposable authority setup; checkpoints after baseline only read native state.
require 'Definitions/MakeUpDefinitions'
local F={sp={'preview-close','preview-location','apply-empty','apply-replace'},
 mp={'preview-close','preview-location','apply-empty','apply-replace','cancel-waiting','apply-while-preview'}}
local slots={ItemBodyLocation.MAKE_UP_FULL_FACE,ItemBodyLocation.MAKE_UP_EYES,ItemBodyLocation.MAKE_UP_EYES_SHADOW,ItemBodyLocation.MAKE_UP_LIPS}
function F.same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not F.same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
function F.applies(case)return case:sub(1,6)=='apply-'or case=='cancel-waiting'end
function F.definition(kind)
 for _,v in ipairs(MakeUpDefinitions.makeup)do if v.item==kind then return v end end
 error('native makeup definition missing '..tostring(kind))
end
function F.snapshot(s)
 local p,root=s.player,s.player:getInventory();local items,worn={},{}
 local values=root:getItems()
 for i=0,values:size()-1 do local item=values:get(i);items[#items+1]={id=item:getID(),kind=item:getFullType()}end
 table.sort(items,function(a,b)return a.id<b.id end)
 values=p:getWornItems()
 for i=0,values:size()-1 do
  local v=values:get(i);local item=v:getItem();local found=root:getItemById(item:getID())
  worn[#worn+1]={id=item:getID(),kind=item:getFullType(),slot=tostring(v:getLocation()),root=found~=nil,
   sameReference=found==item,container=item:getContainer()==root and'root'or false}
 end
 table.sort(worn,function(a,b)return a.slot<b.slot end)
 local kit=assert(root:getItemById(s.ids.items.kit),'exact native makeup kit disappeared')
 assert(kit:getFullType()==s.ids.types.kit and kit:getContainer()==root,'makeup kit identity/topology changed')
 return {case=s.ids.case,actor=p:getOnlineID(),root=items,worn=worn,
  kit={id=kit:getID(),kind=kit:getFullType(),uses=kit:getCurrentUses(),maxUses=kit:getMaxUses(),root=true},
  frontPages=p:getAlreadyReadPages(s.ids.types.front),tailPages=p:getAlreadyReadPages(s.ids.types.tail)}
end
function F.resolve(player,ids)
 if isClient()and player:getOnlineID()~=ids.actor then return end
 local root=player:getInventory()
 for name,wanted in pairs(ids.items)do
  local item=root:getItemById(wanted)
  if not item or item:getFullType()~=ids.types[name]or item:getContainer()~=root then return end
 end
 local s={player=player,ids=ids}
 for _,name in ipairs({'front','tail'})do
  local item=root:getItemById(ids.items[name]);item:setAlreadyReadPages(ids[name..'Initial'])
  player:setAlreadyReadPages(item:getFullType(),ids[name..'Initial'])
 end
 player:setPerkLevelDebug(Perks.Woodwork,0);player:setPerkLevelDebug(Perks.Doctor,0)
 local actual=F.snapshot(s);local expected=ids.baseline
 if not F.same(actual.root,expected.root)or not F.same(actual.kit,expected.kit)or #actual.worn~=#expected.worn then return end
 for i,row in ipairs(actual.worn)do
  local before=expected.worn[i]
  if row.id~=before.id or row.kind~=before.kind or row.slot~=before.slot or row.root~=before.root then return end
 end
 return s
end
function F.prepare(player,case,previous)
 assert(not isClient(),'makeup setup requires authority')
 local root=player:getInventory()
 for _,slot in ipairs(slots)do local item=player:getWornItem(slot);if item then player:removeWornItem(item,false)end end
 local remove={}
 for i=0,root:getItems():size()-1 do
  local item=root:getItems():get(i)
  local owned=previous and (item:getID()==previous.items.kit or item:getID()==previous.items.front or item:getID()==previous.items.tail)
  for _,slot in ipairs(slots)do if item:getBodyLocation()==slot then owned=true end end
  if owned then remove[#remove+1]=item end
 end
 for _,item in ipairs(remove)do if isServer()then sendRemoveItemFromContainer(root,item)end;root:Remove(item)end
 player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false);require('QueueEnergyPlacement')(player)
 assert(not player:isTimedActionInstant()and not getDebug(),'ordinary non-debug makeup timing required')
 local ids={case=case,actor=player:getOnlineID(),items={},types={},target='Base.MakeUp_Crow',alternate='Base.MakeUp_RedStripes2',
  different='Base.MakeUp_EyesShadowWhite',oldType='Base.MakeUp_RedStripes1',slot=tostring(ItemBodyLocation.MAKE_UP_EYES),
  otherSlot=tostring(ItemBodyLocation.MAKE_UP_EYES_SHADOW),producer='ISMakeUpUI.onApplyMakeUp',duration=1}
 local function seed(name,kind)
  local item=assert(root:AddItem(kind),'native fixture item absent '..kind);ids.items[name]=item:getID();ids.types[name]=kind;return item
 end
 -- Native Eyes supports both Eyes and EyesShadow; no fabricated All kit.
 local kit=seed('kit','Base.MakeupEyeshadow')
 assert(kit:getMakeUpType()=='Eyes'and kit:getMaxUses()==5,'native Eyes supply definition changed')
 kit:setCurrentUses(kit:getMaxUses());ids.kitUses=kit:getCurrentUses();ids.kitType=kit:getMakeUpType()
 for _,kind in ipairs({ids.target,ids.alternate,ids.different,ids.oldType})do
  local def=F.definition(kind);local script=assert(getScriptManager():FindItem(kind))
  assert(def.makeuptypes[ids.kitType]and script:getLuaCreate()==nil and script:getItemConfig()==nil,'unreviewed native cosmetic producer')
 end
 assert(getScriptManager():FindItem(ids.target):getBodyLocation()==ItemBodyLocation.MAKE_UP_EYES
  and getScriptManager():FindItem(ids.alternate):getBodyLocation()==ItemBodyLocation.MAKE_UP_EYES
  and getScriptManager():FindItem(ids.oldType):getBodyLocation()==ItemBodyLocation.MAKE_UP_EYES
  and getScriptManager():FindItem(ids.different):getBodyLocation()==ItemBodyLocation.MAKE_UP_EYES_SHADOW,'native cosmetic slots changed')
 for _,name in ipairs({'front','tail'})do
  local book=seed(name,name=='front'and'Base.BookCarpentry1'or'Base.BookFirstAid1')
  ids[name..'Total']=book:getNumberOfPages();ids[name..'Initial']=ids[name..'Total']-(name=='front'and 3 or 1)
  book:setAlreadyReadPages(ids[name..'Initial']);player:setAlreadyReadPages(book:getFullType(),ids[name..'Initial'])
 end
 if case~='apply-empty'then local old=seed('old',ids.oldType);player:setWornItem(ItemBodyLocation.MAKE_UP_EYES,old)end
 player:setPerkLevelDebug(Perks.Woodwork,0);player:setPerkLevelDebug(Perks.Doctor,0)
 if isServer()then
  for _,wanted in pairs(ids.items)do sendAddItemToContainer(root,assert(root:getItemById(wanted)))end
  for _,slot in ipairs(slots)do sendClothing(player,slot,player:getWornItem(slot))end
 end
 local s={player=player,ids=ids};ids.baseline=F.snapshot(s);return s
end
function F.output(snapshot,ids)
 local initial={};for _,row in ipairs(ids.baseline.root)do initial[row.id]=true end
 local output
 for _,row in ipairs(snapshot.root)do
  if not initial[row.id]then assert(not output and row.kind==ids.target,'foreign/duplicate output');output=row.id end
 end
 return output or false
end
return F
