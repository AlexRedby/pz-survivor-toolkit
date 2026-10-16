local config=require 'QueueTestSelection'

local function rooms(grid)
 local found=ArrayList.new()
 grid:getRoomsIntersecting(10707,9484,1,4,found)
 local result={}
 for i=0,found:size()-1 do
  local room=found:get(i)
  if room:getName()=='hall' and room:getZ()==0 and room:getX()==10707 and room:getY()==9484
   and room:getW()==1 and room:getH()==4 then result[#result+1]=room end
 end
 assert(#result==2 and result[1]~=result[2],'expected two distinct exact hall rooms')
 table.sort(result,function(a,b) return a:getID()<b:getID() end)
 assert(result[1]:getID()~=result[2]:getID(),'hall room IDs must be distinct')
 return result
end

local function checkRoomStates(mode)
 assert(mode=='migrate' or mode=='reload','unsupported room state mode')
 local grid=getWorld():getMetaGrid()
 local before=rooms(grid)
 local baseID,accessID=before[1]:getID(),before[2]:getID()
 print('[ROOM_STATE_TEST] BEFORE mode='..mode..' base='..tostring(baseID)
  ..' explored='..tostring(before[1]:isExplored())..' roof='..tostring(before[1]:isRoofFixed())
  ..' access='..tostring(accessID)..' explored='..tostring(before[2]:isExplored())
  ..' roof='..tostring(before[2]:isRoofFixed()))
 if mode=='migrate' then
  before[1]:setExplored(true);before[1]:setRoofFixed(false)
  before[2]:setExplored(false);before[2]:setRoofFixed(true)
  grid:save()
  grid:load()
 end
 local after=rooms(grid)
 assert(after[1]:getID()==baseID and after[2]:getID()==accessID,'room IDs changed during roundtrip')
 assert(after[1]:isExplored() and not after[1]:isRoofFixed(),'base hall flags were not preserved')
 assert(not after[2]:isExplored() and after[2]:isRoofFixed(),'access hall flags were not preserved')
 print('[ROOM_STATE_TEST] COMPLETE mode='..mode)
end

Events.OnServerStarted.Add(function()
 local mode=config.options and config.options.room_state_roundtrip
 if mode then
  local ok,error=pcall(checkRoomStates,mode)
  if not ok then print('[ROOM_STATE_TEST] FAIL '..tostring(error));return end
 end
 print('[STARTUP_TEST] SERVER_READY')
end)
