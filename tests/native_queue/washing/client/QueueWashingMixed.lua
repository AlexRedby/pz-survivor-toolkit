local B=require 'QueueWashingBodyFixture'
local F=require 'QueueWashingFixture'
local M={}
function M.selectMenu(root,player,state,ids)
 local selected,index,option;local visited={};local wanted={};for _,meta in ipairs(ids.garments)do wanted[meta.id]=meta.kind end
 local function walk(menu,depth)
  if depth>8 or visited[menu]then return end;visited[menu]=true
  for i,value in ipairs(menu.options)do
   local data=value.param3;local exact=value.target==player and value.param1==state.sink and value.param4==false and value.param5==root
    and value.param6==nil and type(value.onSelect)=='function'and not value.notAvailable and not value.isDisabled
    and type(data)=='table'and not getmetatable(data)and data.washYourself==true and data.cleanBandages==(ids.bandage~=nil)
   if exact then
    local keys=0;for key in pairs(data)do if key~='washYourself'and key~='regularItems'and key~='cleanBandages'then exact=false end;keys=keys+1 end
    local items=data.regularItems;exact=exact and keys==3 and type(items)=='table'and not getmetatable(items)and #items==#ids.garments
    if exact then
     local seen,count={},0
     for key,item in pairs(items)do
      count=count+1
      if type(key)~='number'or key%1~=0 or key<1 or key>#items or not instanceof(item,'Clothing')or not wanted[item:getID()]
       or wanted[item:getID()]~=item:getFullType()or seen[item:getID()]or item:getContainer()~=state.source or item:getItemAfterCleaning()~=nil and item:getItemAfterCleaning()~=''then exact=false
      else seen[item:getID()]=true end
     end
     exact=exact and count==#ids.garments
    end
    local soap=value.param2
    exact=exact and soap and soap.size and soap.get and soap:size()==1 and soap:get(0)==state.soap
   end
   if exact then assert(not selected,'ambiguous real mixed All menu');selected,index,option=menu,i,value end
   if value.subOption then walk(menu:getSubMenu(value.subOption),depth+1)end
  end
 end
 walk(root,0);return selected,index,option
end
function M.assertBodyQueued(run)
 assert(#run.records==1 and run.records[1].kind=='ISWashYourself','real mixed All lost its native body action during approach preparation before any washing effect')
 return true
end
function M.paidBody(player,state,ids)
 local snapshot=B.snapshot(player);local uses=state.soap:getCurrentUses();local amount=state.sink:getFluidAmount()
 if state.root:getItemById(ids.makeup.id)or #snapshot.makeupIds~=0 or uses~=ids.soap.uses-ids.requiredSoap
  or math.abs(amount-(ids.sink.amount-ids.requiredWater))>.00001 then return end
 for _,part in ipairs(snapshot.parts)do if part.blood~=0 or part.dirt~=0 then return end end
 local garments={}
 for _,meta in ipairs(ids.garments)do
  local item=state.root:getItemById(meta.id)
  if not item or item:getFullType()~=meta.kind or math.abs(item:getBloodLevel()-meta.blood)>.00001 or math.abs(item:getDirtiness()-meta.dirt)>.00001
   or item:getWetness()~=0 or item:getContainer()~=state.root and item:getContainer()~=state.source then return end
  local value=F.snapshot(item);value.rootCount=item:getContainer()==state.root and 1 or 0;value.sourceCount=item:getContainer()==state.source and 1 or 0
  garments[#garments+1]=value
 end
 local bandage;if ids.bandage then bandage=require('QueueWashingBandageFixture').paidInput(player,ids);if not bandage then return end end
 return{body=snapshot,soapUses=uses,waterAmount=amount,makeupRootAbsent=true,garments=garments,bandage=bandage}
end
return M
