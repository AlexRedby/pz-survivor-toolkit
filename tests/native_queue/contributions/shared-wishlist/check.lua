-- Registration/count check only: no stage body or game callback is executed.
local root=assert(arg[1])
local function event()return {Add=function()end}end
for _,case in ipairs({{'full',false,33},{'standalone',true,26},{'reload',false,5},{'reload',true,5},{'visual',true,11}})do
 Events={OnConnected=event(),OnMainMenuEnter=event(),OnPreUIDraw=event(),OnGameStart=event(),OnServerCommand=event(),OnTick=event(),OnServerStarted=event(),OnClientCommand=event()}
 getActivatedMods=function()return {contains=function()return not case[2]end}end
 getFileReader=function(name)
  assert(name=='wishlist-fixture.txt')
  local lines={'client1',case[1],'configured-host','12345','runtime-only','PZSurvivorWishlist'};local i=0
  return {readLine=function()i=i+1;return lines[i]end,close=function()end}
 end
 assert(loadfile(root..'/client/ZZWishlist.lua'))()
 assert(WishlistTestFixture.stageCount==case[3],case[1]..' count '..WishlistTestFixture.stageCount)
 for _,name in ipairs(WishlistTestFixture.stageNames)do print('STAGE\t'..case[1]..'\t'..name)end
 assert(loadfile(root..'/server/ZZWishlist_Server.lua'))()
 print('PASS wishlist stage registration '..case[1]..' checks='..case[3])
end
