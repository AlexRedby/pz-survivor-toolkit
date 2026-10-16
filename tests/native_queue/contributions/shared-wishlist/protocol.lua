-- No game: execute the retained fixture's real guards against controlled UI/network doubles.
local root,project=assert(arg[1]),assert(arg[2])
local function event()
 local callbacks={}
 return {Add=function(fn)callbacks[#callbacks+1]=fn end,fire=function(...)for _,fn in ipairs(callbacks)do fn(...)end end}
end
local function events()
 local result={}
 for _,name in ipairs({'OnConnected','OnMainMenuEnter','OnPreUIDraw','OnGameStart','OnServerCommand','OnTick','OnServerStarted','OnClientCommand','OnFillInventoryObjectContextMenu'})do result[name]=event()end
 return result
end
local function load(path,env)return assert(setfenv(assert(loadfile(path)),env))()end
local function client(user,toolkit,clock)
 local output={}
 local env=setmetatable({Events=events(),require=function()end,print=function(line)output[#output+1]=line end},{__index=_G})
 env.getActivatedMods=function()return{contains=function()return toolkit end}end
 env.getTimestampMs=function()return clock.now end
 env.getFileReader=function()
  local lines={user,'full','host','17343','runtime-only','PZSurvivorWishlist'};local i=0
  return{readLine=function()i=i+1;return lines[i]end,close=function()end}
 end
 env.PZSurvivorWishlist={Client={},UI={windows={}}}
 load(root..'/client/ZZWishlist.lua',env)
 return env,output
end
local function spec(env,name)
 for _,s in ipairs(env.WishlistTestFixture.stages)do if s[1]==name then return s end end
 error('missing preserved stage '..name)
end
local function only(env,names)
 local chosen={};for _,name in ipairs(names)do chosen[#chosen+1]=spec(env,name)end
 local stages=env.WishlistTestFixture.stages
 for i=#stages,1,-1 do stages[i]=nil end
 for i,s in ipairs(chosen)do stages[i]=s end
end
local function rectangle(x,y,w,h)
 return {Type='ISButton',getAbsoluteX=function()return x end,getAbsoluteY=function()return y end,
  getWidth=function()return w end,getHeight=function()return h end,getIsVisible=function()return true end}
end

do
 local restored,ready=false,false
 local env=setmetatable({Events=events(),print=function(line)
  if line=='[WISHLIST_TEST] SERVER_READY'then assert(restored,'seed restoration must precede server readiness');ready=true end
 end},{__index=_G})
 env.WishlistSeedRestore=function()restored=true end
 load(root..'/server/ZZWishlist_Server.lua',env);env.Events.OnServerStarted.fire()
 assert(restored and ready)
 ready=false;env.WishlistSeedRestore=function()error('seed restoration failed')end
 assert(not pcall(env.Events.OnServerStarted.fire)and not ready,'failed restoration must not announce readiness')
 print('PASS wishlist fixture reload startup: restore before readiness and fail closed')
end

do
 local env=client('client1',false,{now=0});local separate=env.WishlistTestFixture.separate
 assert(separate(rectangle(50,100,20,20),rectangle(0,100,40,40)),'side-by-side controls are disjoint')
 assert(separate(rectangle(10,150,20,20),rectangle(0,100,40,40)),'vertical gap is disjoint')
 assert(not separate(rectangle(10,110,20,20),rectangle(0,100,40,40)),'overlapping absolute rectangles must fail')
 local b=rectangle(50,100,20,20)
 local window={visible=false,getIsVisible=function(self)return self.visible end,close=function(self)self.visible=false end}
 env.PZSurvivorWishlist.UI.windows[0]=window
 local opened=0
 b.onclick=function()opened=opened+1;window.visible=true end
 local equipped={pzswButton=b,getChildren=function()return{rectangle(0,100,40,40)}end}
 env.getPlayerData=function()return{equipped=equipped}end
 env.getText=function(key)return key end
 spec(env,'sidebar opens wishlist without overlapping existing buttons')[2]()
 assert(opened==1 and not window.visible,'standalone direct sidebar opens and closes Wishlist')
 env=client('client1',true,{now=0});env.getText=function(key)return key end
 env.PZSurvivorWishlist.UI.windows[0]=window
 local hub=rectangle(75,100,20,20);local highlight=rectangle(50,100,20,20)
 local option={name='UI_PZSW_Open',target=0,onSelect=function(num)assert(num==0);opened=opened+1;window.visible=true end}
 local menu={options={option},hideAndChildren=function()end}
 hub.onclick=function()end
 env.getPlayerContextMenu=function()return menu end
 equipped={toolkitToolsButton=hub,toolkitHighlightButton=highlight,getChildren=function()return{rectangle(0,100,40,40)}end}
 env.getPlayerData=function()return{equipped=equipped}end
 local sidebar=spec(env,'sidebar opens wishlist without overlapping existing buttons')[2]
 sidebar();assert(opened==2 and not window.visible,'Toolkit sidebar must execute the real Wishlist hub entry')
 menu.options={option,option};assert(not pcall(sidebar),'duplicate hub entries must fail')
 menu.options={option};equipped.toolkitToolsButton=highlight;assert(not pcall(sidebar),'overlapping sibling controls must fail')
 print('PASS wishlist fixture sidebar: direct/hub actions, absolute rectangles and duplicate guards')
end

do
 local env=client('client1',false,{now=0})
 env.PZSurvivorWishlist.Settings={rowsEnabled=function()return true end,color=function()return{r=.25,g=.85,b=.75}end}
 env.PZSurvivorWishlist.Client.isWanted=function()return true end
 env.instanceof=function(_,kind)return kind=='InventoryItem'end
 env.ISInventoryPane={renderdetails=function()end}
 load(project..'/PZSurvivorWishlist/42/media/lua/client/PZSurvivorWishlist/Inventory.lua',env)
 local inventory=env.PZSurvivorWishlist.Inventory;inventory.install()
 local item={getFullType=function()return'Base.Nails'end}
 local pane={player=0,items={item,item,item},itemHgt=20,headerHgt=20,
  getYScroll=function()return 0 end,getHeight=function()return 60 end,getWidth=function()return 100 end,
  drawRect=function()end,drawRectBorder=function()end}
 local render=env.ISInventoryPane.renderdetails
 pane.renderdetails=render
 env.WishlistTestFixture.checkHighlight({inventoryPane=pane}) -- Three marked rows, only two intersect the viewport.
 pane.renderdetails=function(self,dragged)render(self,dragged);render(self,dragged)end
 assert(not pcall(env.WishlistTestFixture.checkHighlight,{inventoryPane=pane}),'duplicate native overlay calls must fail')
 pane.renderdetails=function()end
 assert(not pcall(env.WishlistTestFixture.checkHighlight,{inventoryPane=pane}),'missing native overlay calls must fail')
 local border,draw=pane.drawRectBorder,inventory.draw
 pane.renderdetails=function()error('native render failure')end
 assert(not pcall(env.WishlistTestFixture.checkHighlight,{inventoryPane=pane}))
 assert(pane.drawRectBorder==border and inventory.draw==draw,'failed render must restore both probes')
 print('PASS wishlist fixture highlights: clipped rows, exactly one overlay, missing/duplicate hooks and cleanup')
end

local completion='peer completion synchronizes and removes owner highlight'
local departure='faction departure revokes access without another list edit'
local factionEdit='faction edit reaches owner'
local function network(names)
 local clock={now=0};local clients,logs,players={}, {}, {}
 local list={id='client1',revision=17,members={client2=true},entries={['Base.Hammer']={amount=7,done=true},['Base.Nails']={amount=5}},faction='WishlistTest'}
 local shared={client1={list},client2={list}}
 local edits,requests,commands={},{},{}
 local server=setmetatable({Events=events(),print=function(line)commands[#commands+1]=line end},{__index=_G})
 local id=0
 server.getCell=function()return{}end
 server.sendAddItemToContainer=function()end
 local container={setType=function()end,setCapacity=function()end,setExplored=function()end,AddItem=function()end}
 server.IsoThumpable={new=function()return{setCanPassThrough=function()end,setIsContainer=function()end,getContainer=function()return container end,
  getModData=function()return{}end,transmitCompleteItemToClients=function()end,transmitModData=function()end}end}
 server.sendServerCommand=function(player,module,command,args)clients[player:getUsername()].Events.OnServerCommand.fire(module,command,args)end
 load(root..'/server/ZZWishlist_Server.lua',server)
 for _,user in ipairs({'client1','client2'})do
  local actor=user
  local env,output=client(actor,true,clock);clients[actor],logs[actor]=env,output
  only(env,names)
  env.PZSurvivorWishlist.Client.state=function()return{lists=shared[actor]}end
  env.PZSurvivorWishlist.Client.isWanted=function()return false end
  env.PZSurvivorWishlist.Client.edit=function(_,action,values)
   edits[#edits+1]={user=actor,action=action,values=values}
   if action=='share'then shared.client2=#values.members>0 and {list}or{}end
  end
  env.sendClientCommand=function(...)
   local args={...}
   if args[1]=='WishlistTest'then
    if args[2]=='Observed'then server.Events.OnClientCommand.fire(args[1],args[2],players[actor],args[3])
    else commands[#commands+1]={user=actor,command=args[2],args=args[3]}end
   else requests[#requests+1]=args[4]end
  end
  local inventory={AddItem=function()id=id+1;return{getID=function()return id end}end}
  players[actor]={getUsername=function()return actor end,getInventory=function()return inventory end,
   getCurrentSquare=function()return{AddSpecialObject=function()end}end}
  env.getPlayer=function()return players[actor]end
 end
 for _,user in ipairs({'client1','client2'})do server.Events.OnClientCommand.fire('WishlistTest','Ready',players[user],{})end
 local send=server.sendServerCommand
 server.sendServerCommand=function()end
 for _,key in ipairs({'completion-observed','faction-edit-observed','faction-revocation-observed'})do
  if key==clients.client1.WishlistTestFixture.stages[1].barrier then break end
  for _,user in ipairs({'client1','client2'})do server.Events.OnClientCommand.fire('WishlistTest','Observed',players[user],{key=key})end
 end
 server.sendServerCommand=send
 for i=#commands,1,-1 do commands[i]=nil end
 return {clock=clock,clients=clients,logs=logs,players=players,server=server,shared=shared,list=list,edits=edits,requests=requests,commands=commands}
end
local function tick(net,user,now)net.clock.now=now;net.clients[user].Events.OnTick.fire()end
do
 local net=network({completion,'explicit revocation removes cached shared list'})
 tick(net,'client1',2000)
 assert(#net.edits==0 and #net.shared.client2==1,'owner must not revoke before peer observes completion')
 tick(net,'client1',11000);assert(#net.edits==0,'wall-clock delay cannot release a joint observation')
 tick(net,'client2',12000);assert(#net.edits==0,'server release precedes client continuation')
 tick(net,'client1',12001);tick(net,'client2',12002)
 assert(#net.edits==1 and #net.shared.client2==0,'revoke runs only after both observations')
 tick(net,'client1',14003);tick(net,'client2',14003)
 assert(#net.requests==1 and net.requests[1].revision==17,'revoked peer retains its valid observed revision for the forged request')
 assert(not table.concat(net.logs.client2,'\n'):find('FAIL',1,true),'peer observation must not race owner revocation')
 net=network({departure});net.shared.client2={}
 tick(net,'client1',7000);assert(#net.edits==0 and #net.shared.client2==0,'regrant cannot race peer revocation observation')
 tick(net,'client2',8000);tick(net,'client1',8001);tick(net,'client2',8002)
 assert(#net.edits==3 and #net.shared.client2==1,'owner restoration follows joint revocation observation')
 net=network({factionEdit})
 tick(net,'client1',2000);assert(#net.commands==0,'faction departure waits for both edit observations')
 tick(net,'client2',2100);tick(net,'client1',2101);tick(net,'client2',2102)
 assert(net.commands[#net.commands].command=='Faction'and net.commands[#net.commands].args.remove,'faction removal runs after both observations')
 print('PASS wishlist fixture joint observations: delayed peer, revoke, valid forged revision and faction regrant ordering')
end
do
 local net=network({completion})
 tick(net,'client1',2000);tick(net,'client1',17000);tick(net,'client1',18000)
 assert(#net.edits==0,'missing peer must never authorize destructive mutation')
 local text=table.concat(net.logs.client1,'\n')
 assert(text:find('FAIL '..completion..' joint observation deadline',1,true))
 assert(text:find('COMPLETE checks=1 failures=1',1,true),'deadline must fail with actual executed count')
 net=network({completion})
 local emit=net.server.Events.OnClientCommand.fire
 emit('WishlistTest','Observed',net.players.client1,{key='faction-revocation-observed'})
 emit('WishlistTest','Observed',{getUsername=function()return'other'end},{key='completion-observed'})
 tick(net,'client1',2000)
 emit('WishlistTest','Observed',net.players.client1,{key='completion-observed'})
 assert(#net.edits==0 and not table.concat(net.commands,'\n'):find('BARRIER_RELEASE',1,true),'wrong stage, unknown actor and duplicate observer cannot release')
 print('PASS wishlist fixture protocol guards: bounded missing peer, ordered keys, exact actors and duplicate observations')
end
