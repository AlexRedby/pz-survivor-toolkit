require 'TimedActions/Animals/ISRemoveAnimalFromTrailer'
local complete=ISRemoveAnimalFromTrailer.complete
ISRemoveAnimalFromTrailer.complete=function(self)
 local ids={};local list=self.vehicle:getAnimals()
 for i=0,list:size()-1 do local a=list:get(i);ids[#ids+1]=a:getAnimalID()..'/'..a:getOnlineID()..'/'..tostring(a==self.animal) end
 print('[ANIMAL_TRAILER] COMPLETE_ENTER server='..tostring(isServer())..' grab='..tostring(self.grab)..' target='..tostring(self.animal and self.animal:getAnimalID())..' list='..table.concat(ids,','))
 local result=complete(self)
 print('[ANIMAL_TRAILER] COMPLETE_EXIT result='..tostring(result)..' count='..list:size()..' hand='..tostring(self.character:getPrimaryHandItem()))
 return result
end

local function label(it) return it and (it:getFullType()..'#'..it:getID()) or 'nil' end
local forceDrop=forceDropHeavyItems
forceDropHeavyItems=function(p)
 print('[ANIMAL_TRAILER] FORCE_DROP server='..tostring(isServer())..' before='..label(p:getPrimaryHandItem())..'/'..label(p:getSecondaryHandItem()))
 local result=forceDrop(p)
 print('[ANIMAL_TRAILER] FORCE_DROP_DONE server='..tostring(isServer())..' after='..label(p:getPrimaryHandItem())..'/'..label(p:getSecondaryHandItem()))
 return result
end
Events.OnEquipPrimary.Add(function(p,it) if instanceof(p,'IsoPlayer') then print('[ANIMAL_TRAILER] EQUIP_PRIMARY server='..tostring(isServer())..' user='..p:getUsername()..' item='..label(it)) end end)
Events.OnEquipSecondary.Add(function(p,it) if instanceof(p,'IsoPlayer') then print('[ANIMAL_TRAILER] EQUIP_SECONDARY server='..tostring(isServer())..' user='..p:getUsername()..' item='..label(it)) end end)
