local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local callbacks, modules = {}, {}
Events = {}
for _, name in ipairs({'OnClientCommand','OnServerCommand','OnInitGlobalModData','OnReceiveGlobalModData','OnGameStart','OnCreatePlayer','OnTick'}) do
    callbacks[name] = {}
    Events[name] = {Add=function(fn) callbacks[name][#callbacks[name]+1]=fn end}
end
local client, server = false, true
isClient=function() return client end
isServer=function() return server end
require=function(name)
    if modules[name] ~= nil then return modules[name] end
    for _, tier in ipairs({'shared','server','client'}) do
        local file=io.open(root..tier..'/'..name..'.lua','r')
        if file then file:close();local result=dofile(root..tier..'/'..name..'.lua');modules[name]=result;return result end
    end
    error('unknown module '..name)
end
local function list(values) return {size=function() return #values end,get=function(_,index) return values[index+1] end} end
instanceof=function(value, class) return value and value.class == class end
local function square(x,y,z)
    local s={x=x,y=y,z=z,objects={},bodies={}}
    function s:getX() return self.x end;function s:getY() return self.y end;function s:getZ() return self.z end
    function s:getObjects() return list(self.objects) end;function s:getStaticMovingObjects() return list(self.bodies) end
    function s:isBlockedTo() return self.blocked end
    return s
end
local here, near, far = square(10,10,0),square(11,10,0),square(20,10,0)
getCell=function() return {getGridSquare=function(_,x,y,z)
    for _,s in ipairs({here,near,far}) do if s.x==x and s.y==y and s.z==z then return s end end
end} end
local function player(id)
    local p={online=id,square=here}
    function p:getOnlineID() return self.online end;function p:isDead() return self.dead end
    function p:getCurrentSquare() return self.square end;function p:getInventory() return self.inventory end
    function p:canAccessContainer(c) return not c.locked end
    return p
end
local first, second = player(7),player(8)
local function container(owner,s)
    local c={values={},owner=owner,square=s}
    function c:isInCharacterInventory(p) return self.owner==p end
    function c:getItemWithIDRecursiv(id) for _,v in ipairs(self.values) do if v.id==id then return v end end end
    function c:getVehiclePart() return nil end;function c:getContainingItem() return nil end
    function c:getSourceGrid() return self.square end;function c:getParent() return self.parent end
    return c
end
first.inventory,second.inventory=container(first),container(second)
local crate,remote=container(nil,near),container(nil,far)
for _, c in ipairs({crate,remote}) do
    local object={getContainerCount=function() return 1 end,getContainerByIndex=function() return c end,getSquare=function() return c.square end}
    c.parent=object;c.square.objects[#c.square.objects+1]=object
end
local function item(id,c,fullType)
    local i={id=id,source=c,fullType=fullType or 'Base.Apple',data={untouched=42}}
    function i:getID() return self.id end;function i:getContainer() return self.source end
    function i:getOutermostContainer() return self.outer or self.source end;function i:getWorldItem() return self.world end
    function i:getFullType() return self.fullType end;function i:hasModData() return next(self.data)~=nil end
    function i:getModData() return self.data end
    if c then c.values[#c.values+1]=i end
    return i
end
local mine,held,other,collision=item(1,first.inventory),item(2,crate),item(3,remote),item(1,second.inventory)
SafeHouse={isSafehouseAllowLoot=function(s) return not s.denied end}
local stores,world={},'one'
ModData={getOrCreate=function(key)
    stores[world]=stores[world] or {};stores[world][key]=stores[world][key] or {};return stores[world][key]
end}
local uuid=0
getRandomUUID=function() uuid=uuid+1;return string.format('00000000-0000-4000-8000-%012x',uuid) end
local wire,syncs={},{}
sendServerCommand=function(...) wire[#wire+1]={...} end
syncItemModData=function(p,i) syncs[#syncs+1]={p,i} end
local C=require 'PZSurvivorToolkit/TagCustomization'
local A=require 'PZSurvivorToolkit/TagCustomizationAuthority'
local seq=0
local function apply(command,args)
    seq=seq+1;args.request=seq;if args.baseRevision==nil then args.baseRevision=C.getRevision() end
    return A.applyRequest(first,command,args)
end
local function edit(id,definition,revision) return apply('Edit',{id=id,definition=definition,baseRevision=revision}) end
local function assign(items,scope,changes,reset) return apply('Assign',{items=items,scope=scope,changes=changes,reset=reset or false}) end
local own,nearby,away={id=1,inv=true},{id=2,x=11,y=10,z=0},{id=3,x=20,y=10,z=0}
assert(C.synced() and C.getRevision()==0)
local status,payload=edit(nil,{name='Expedition',color={r=.2,g=.4,b=.6},icon='Item_Axe'})
local tag=payload.id
assert(status=='accepted' and C.customId(tag) and C.getRevision()==1 and C.catalog().nextId==2)
assert(C.isActive(tag) and #C.customIds()==1)
local definition=C.definition(tag);definition.color.r=1
assert(C.definition(tag).color.r==.2,'definition callers cannot mutate the saved catalog')
assert(edit('food',{color={r=1,g=0,b=0},icon='media/ui/Entity/keep_item_icon.png'})=='accepted')
assert(C.definition('food').name==nil,'color edits do not freeze a translated built-in label')
assert(edit('food',{icon=false})=='accepted' and C.definition('food').icon==nil)
assert(edit('food',false)=='accepted' and C.definition('food')==nil,'full built-in reset restores defaults')
local revision=C.getRevision()
assert(edit(tag,{name='Late edit'},revision-1)=='conflict' and C.definition(tag).name=='Expedition')
assert(A.applyRequest(first,'Edit',{request=seq,baseRevision=revision,id=tag,definition={name='Replay'}})=='rejected')
for _, bad in ipairs({{name=string.rep('x',81)},{name='bad\nline'},{icon='../escape.png'},{icon='media/ui/../x.png'},
        {color={r=0/0,g=0,b=0}},{color={r=math.huge,g=0,b=0}},{unknown='x'}}) do
    assert(edit(tag,bad)=='rejected' and C.getRevision()==revision,'invalid definition rejected without mutation')
end
assert(edit(tag,{name=string.rep('\208\175',80)})=='accepted','names use Unicode character bounds')
assert(edit(tag,{name=false})=='rejected','custom tag cannot lose its name')
assert(assign({own},'type',{food='remove',[tag]='add'})=='accepted')
assert(C.typeDelta('BASE.APPLE').food=='remove' and C.itemDelta(mine).food==nil)
local base={'food','perishable'};base.legacyCategory='Food';base.itemSignature='dynamic';base.details={safe=true}
local projected=C.project(base,'Base.Apple',mine)
assert(projected[1]=='perishable' and projected[2]==tag and projected.legacyCategory=='Food' and projected.itemSignature=='dynamic')
projected.details.safe=false;assert(base.details.safe and base[1]=='food','projection is isolated and keeps dynamic provenance')
assert(assign({own},'item',{food='add',perishable='remove'})=='accepted')
projected=C.project(base,'Base.Apple',mine)
assert(projected[1]==tag and projected[2]=='food' and mine.data.untouched==42,'instance delta layers over type delta')
assert(assign({own},'item',{food='default'})=='accepted' and C.itemDelta(mine).food==nil)
assert(assign({own},'item',{food='add'},true)=='accepted' and C.itemDelta(mine).perishable==nil,'reset clears scope then applies draft')
revision=C.getRevision();local before=C.snapshot();local delta=C.itemDelta(mine)
assert(assign({own,away},'item',{food='remove'})=='rejected' and C.getRevision()==revision and C.itemDelta(mine).food==delta.food,
    'one inaccessible item rejects the full edit before touching accessible items')
crate.locked=true;assert(assign({nearby},'type',{food='add'})=='rejected');crate.locked=nil
near.denied=true;assert(assign({nearby},'type',{food='add'})=='rejected');near.denied=nil
held.outer=remote;assert(assign({nearby},'item',{food='add'})=='rejected');held.outer=nil
assert(assign({{id=2,inv=true}},'type',{food='add'})=='rejected','type edits require an accessible real item, not forged ownership')
assert(apply('Assign',{items={own},scope='type',changes={food='add'},reset=false,fullType='Base.Remote'})=='rejected')
assert(apply('Assign',{items={[2]=own},scope='item',changes={},reset=false})=='rejected')
first.dead=true;assert(assign({own},'item',{food='remove'})=='rejected');first.dead=nil
local retiredName=C.definition(tag).name
assert(edit(tag,false)=='accepted' and not C.isActive(tag) and C.definition(tag).deleted and C.definition(tag).name==retiredName)
assert(C.catalog().definitions[tag].deleted and C.isValidId(tag),'tombstone identity stays valid for durable saved rules')
assert(C.typeDelta('Base.Apple')[tag]=='add' and #C.project({'perishable'},'Base.Apple',nil)==1,'deleted ids stay referenced but cannot classify')
assert(assign({own},'item',{[tag]='add'})=='rejected','deleted or unknown custom tags cannot be assigned')
assert(assign({own},'item',{[tag]='default'})=='accepted','retired deltas can still be cleared')
status,payload=edit(nil,{name='Other'});local newer=payload.id
assert(status=='accepted' and newer~=tag and C.catalog().nextId==3)
assert(edit(tag,{name='Resurrect'})=='rejected','retired IDs cannot be reused')
local tooMany={};for index=1,C.MAX_ITEMS+1 do tooMany[index]=own end
assert(assign(tooMany,'item',{})=='rejected')
local manyChanges={};for index=1,C.MAX_CHANGES+1 do manyChanges['category:'..index]='add' end
assert(assign({own},'type',manyChanges)=='rejected')
local saved=C.catalog();local previous=C.getRevision()
world='two';assert(C.getRevision()==0 and #C.customIds()==0,'SP save change never reads cached prior-world catalog')
world='one';assert(C.catalog()==saved and C.getRevision()==previous and C.catalog().definitions[tag].deleted,'world reload keeps tombstones and deltas')
-- A save/catalog at its capacity is rejected atomically rather than silently trimmed.
local capped=C.copy(saved)
for index=1,C.MAX_TYPES do capped.types['base.type'..index]={food='add'} end
capped.types['base.apple']=nil
local live=C.catalog();for key in pairs(live) do live[key]=nil end;for key,value in pairs(capped) do live[key]=value end
revision=C.getRevision();assert(assign({own},'type',{food='add'})=='rejected' and C.getRevision()==revision)
for key in pairs(live) do live[key]=nil end;for key,value in pairs(before) do live[key]=value end
-- Shared read readiness does not require a native square; writes still do.
first.square=nil;local countBefore=#wire
for _,fn in ipairs(callbacks.OnClientCommand)do fn(C.MODULE,'Refresh',first,{})end
assert(#wire==countBefore+1 and wire[#wire][3]=='State','catalog read required admitted square')
assert(edit('food',{name='Too early'})=='rejected','write bypassed native player readiness')
first.square=here
-- Network clients only mutate after authoritative State, with inventory owner binding.
for _,fn in ipairs(callbacks.OnInitGlobalModData) do fn() end
seq=0
client,server=true,false
local players={first,second}
getSpecificPlayer=function(n) return players[n+1] end
getNumActivePlayers=function() return #players end
local sent={}
sendClientCommand=function(p,module,command,args) sent[#sent+1]={player=p,module=module,command=command,args=args} end
local now=1000
getTimestampMs=function()return now end
local Client=require 'PZSurvivorToolkit/TagCustomizationClient'
local changes=0;Client.onChange(function() changes=changes+1 end)
assert(not C.synced())
Client.refresh();assert(#sent==2 and sent[1].command=='Refresh')
for _,fn in ipairs(callbacks.OnTick)do fn()end
assert(#sent==4,'unsynced ready client did not retry catalog read')
now=1500;for _,fn in ipairs(callbacks.OnTick)do fn()end
assert(#sent==4,'catalog retry ignored interval')
now=2000;first.square=nil;second.dead=true
for _,fn in ipairs(callbacks.OnTick)do fn()end
assert(#sent==4,'catalog retry sent before a local actor was ready')
first.square=here;second.dead=nil
now=3000;for _,fn in ipairs(callbacks.OnTick)do fn()end
assert(#sent==6,'catalog retry did not recover from delayed admission')
Client.receive('State',{catalog=before})
assert(C.synced() and C.getRevision()==before.revision)
now=5000;local sentAtReady=#sent
for _,fn in ipairs(callbacks.OnTick)do fn()end
assert(#sent==sentAtReady,'catalog retry continued after readiness')
local calls={}
local oldName=C.definition(tag).name
Client.edit(0,tag,{name='Network'},function(s,p) calls[#calls+1]={s,p} end,C.getRevision())
local net=sent[#sent]
assert(net.command=='Edit' and C.definition(tag).name==oldName and #calls==0,'UI callback sends without optimistic state')
-- Server processes that exact packet; deliberately restore local cached view before receiving its state.
client,server=false,true;wire={}
local netStatus,netResult=A.applyRequest(net.player,net.command,net.args)
assert(netStatus=='accepted')
local state=wire[#wire-1][3]
client,server=true,false
assert(C.definition(tag).name==oldName)
Client.receive('State',state);Client.receive('Result',netResult)
assert(C.definition(tag).name=='Network' and #calls==1 and calls[1][1]=='accepted')
local expected=C.getRevision()-1
Client.edit(0,tag,{name='Stale'},function(s,p) calls[#calls+1]={s,p} end,expected)
net=sent[#sent];assert(net.args.baseRevision==expected)
client,server=false,true;netStatus,netResult=A.applyRequest(first,'Edit',net.args)
client,server=true,false;Client.receive('Result',netResult)
assert(netStatus=='conflict' and calls[#calls][1]=='conflict' and C.definition(tag).name=='Network')
local catalog=C.snapshot();catalog.revision=catalog.revision+1
local firstDelta,secondDelta=C.itemDelta(mine),C.itemDelta(collision)
Client.receive('State',{catalog=catalog,owner=7,items={{locator=own,delta={food='remove'}}}})
assert(C.itemDelta(mine).food=='remove' and C.itemDelta(collision).food==secondDelta.food,'owner inventory locator never resolves into observer inventory')
local older=C.copy(catalog);older.revision=older.revision-1
Client.receive('State',{catalog=older,owner=7,items={{locator=own,delta={food='add'}}}})
assert(C.getRevision()==catalog.revision and C.itemDelta(mine).food=='remove','old State cannot roll back catalog or known item')
local loose=item(4,nil)
loose.world={class='IsoWorldInventoryObject',getItem=function() return loose end,getSquare=function() return near end}
near.objects[#near.objects+1]=loose.world
local cacheToken,serverRevision=C.cacheRevision(),C.getRevision()
Client.receive('State',{catalog=older,owner=7,items={{locator={id=4,x=11,y=10,z=0},delta={food='add'}}}})
assert(C.getRevision()==serverRevision and C.cacheRevision()~=cacheToken,
    'delayed unrelated item State changed effective tags without invalidating local consumers')
assert(C.itemDelta(loose).food=='add','older catalog State still delivers first update for unrelated loose item')
Client.receive('State',{catalog=catalog,owner=8,items={{locator=own,delta={food='add'}}}})
assert(C.itemDelta(collision).food=='add' and C.itemDelta(mine).food=='remove')
assert(changes>0)
for _,fn in ipairs(callbacks.OnGameStart) do fn() end
assert(not C.synced() and C.getRevision()==0,'new client world clears received catalog')
client,server=false,false
-- SP uses the same authority transaction/callback path and save store.
local callbackStatus
Client.edit(0,'food',{name='Supply'},function(s) callbackStatus=s end)
assert(callbackStatus=='accepted' and C.definition('food').name=='Supply')
print('Custom tags: world persistence, UUID tombstones, deltas, atomic authority, replay/conflicts and client/SP callbacks passed.')
