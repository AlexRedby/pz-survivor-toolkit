-- Registration only: none of the game callbacks or stage bodies is executed.
local root=assert(arg[1])
local function event() return {Add=function() end} end
require=function() end
for _,case in ipairs({{'crafting','chains',20},{'ui','chains',28},{'alternatives','alternatives',23}}) do
 Events={OnConnected=event(),OnMainMenuEnter=event(),OnPreUIDraw=event(),OnConnectFailed=event(),
  OnGameStart=event(),OnServerCommand=event(),OnTick=event(),OnServerStarted=event(),OnClientCommand=event()}
 PZSurvivorToolkit={CraftPlanner={},CraftChainRecipes={}}
 ISHandcraftAction={performRecipe=function() end}
 getFileReader=function(name)
  assert(name=='craft-fixture.txt')
  local lines={'client1',case[1],'configured-host','12345','runtime-only'};local i=0
  return {readLine=function() i=i+1;return lines[i] end,close=function() end}
 end
 assert(loadfile(root..'/client/'..case[2]..'.lua'))()
 assert(CraftIntakeFixture.stageCount==case[3],case[1]..' unexpected stage count')
 for _,name in ipairs(CraftIntakeFixture.stageNames)do print('STAGE\t'..case[1]..'\t'..name)end
 assert(loadfile(root..'/server/'..case[2]..'.lua'))()
 print('PASS craft stage registration '..case[1]..' checks='..case[3])
end
