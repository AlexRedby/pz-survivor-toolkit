if not NativeActionRoot then print('Native makeup removal sync SKIP (pass --native-action-root).');return end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r','') end
    local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
local function reader(text)
    local cursor=1
    return {close=function()end,readLine=function()
        if cursor>#text then return end
        local boundary=text:find('\n',cursor,true)or #text+1
        local line=text:sub(cursor,boundary-1);cursor=boundary+1;return line
    end}
end
local function list(values)
    return {size=function()return #values end,get=function(_,i)return values[i+1]end,isEmpty=function()return #values==0 end}
end
local function setup(options)
    options=options or{}
    local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    f.native('shared/TimedActions/ISWashClothing.lua');f.native('shared/TimedActions/ISWashYourself.lua')
    local client,server=options.client or false,options.server~=false
    isClient=function()return client end;isServer=function()return server end
    getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    getGameFilesInput=function(path)
        local text=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
        if options.changedSource then text=text..'-- unknown source\n'end
        return reader(text)
    end
    local actor=f.player;actor.class='IsoPlayer';local root=actor:getInventory();root.class='ItemContainer';root.values={}
    function root:getParent()return actor end;function root:getContainingItem()return nil end
    function root:getItems()return list(self.values)end
    function root:getItemById(id)for _,item in ipairs(self.values)do if item:getID()==id then return item end end end
    function root:getSoapList()return list({})end
    function root:Remove(item)
        for i,value in ipairs(self.values)do if value==item then table.remove(self.values,i);item.container=nil;return end end
    end
    local worn={};local removals=0;function actor:getWornItem(slot)return worn[slot]end
    function actor:removeWornItem(item)removals=removals+1;for slot,value in pairs(worn)do if value==item then worn[slot]=nil end end end
    local blood,dirt={[0]=.15},{[0]=.10,[1]=.10}
    local visual={getBlood=function(_,part)return blood[part]or 0 end,getDirt=function(_,part)return dirt[part]or 0 end,
        setBlood=function(_,part,value)blood[part]=value end,setDirt=function(_,part,value)dirt[part]=value end}
    function actor:getHumanVisual()return visual end
    function actor:getStats()return{remove=function()end}end
    ItemBodyLocation={MAKE_UP_FULL_FACE=1,MAKE_UP_EYES=2,MAKE_UP_EYES_SHADOW=3,MAKE_UP_LIPS=4}
    BloodBodyPartType={MAX={index=function()return 18 end},FromIndex=function(i)return i end}
    CharacterStat={UNHAPPINESS=1}
    local source={amount=2,getFluidAmount=function(self)return self.amount end,
        useFluid=function(self,amount)self.amount=self.amount-amount;return amount end,transmitModData=function()end}
    local visuals=0;sendHumanVisual=function(actual)assert(actual==actor);visuals=visuals+1 end
    local sent={};sendRemoveItemFromContainer=function(container,item)
        assert(container==root and root:getItemById(item:getID())==nil and actor:getWornItem(item:getBodyLocation())==nil,
            'notification preceded actual native root/worn removal')
        sent[#sent+1]={root=container,item=item}
    end
    local function makeup(id,slot)
        local item={class='Clothing',id=id,slot=slot,container=root}
        function item:getID()return self.id end;function item:getFullType()return 'Base.MakeUp_Test'..self.slot end
        function item:getContainer()return self.container end;function item:getBodyLocation()return self.slot end
        root.values[#root.values+1]=item;worn[slot]=item;return item
    end
    local native=ISWashYourself.removeMakeup
    if options.foreign then ISWashYourself[options.foreign]=function()end end
    local before=ISWashYourself.removeMakeup
    if not options.unpatched then assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/server/PZSurvivorToolkit/WashMakeupSync.lua'))() end
    local action=ISWashYourself:new(actor,source)
    return{actor=actor,root=root,worn=worn,makeup=makeup,sent=sent,action=action,native=native,before=before,source=source,blood=blood,dirt=dirt,
        visuals=function()return visuals end,removals=function()return removals end,mode=function(c,s)client,server=c,s end}
end
local baseline=setup({unpatched=true});local old=baseline.makeup(10,2)
baseline.action:removeMakeup(old)
assert(not baseline.root:getItemById(10)and not baseline.worn[2]and #baseline.sent==0,'actual native source demonstrates the missing server inventory notification')
local f=setup();local savedComplete,savedDuration=ISWashYourself.complete,ISWashYourself.getDuration
local items={};for slot=1,4 do items[slot]=f.makeup(10+slot,slot)end
assert(f.action:complete()==true and #f.sent==4 and #f.root.values==0 and f.source.amount==0 and f.visuals()==1 and f.removals()==4)
for i=1,4 do assert(f.sent[i].item==items[i]and f.sent[i].root==f.root and not f.worn[i])end
assert(f.blood[0]==0 and f.dirt[0]==0 and f.dirt[1]==0,'water/body native effects changed')
assert(ISWashYourself.complete==savedComplete and ISWashYourself.getDuration==savedDuration,'native effect/duration callbacks replaced')
for _,item in ipairs(items)do f.action:removeMakeup(item)end
assert(#f.sent==4 and f.removals()==8,'repeated helper call duplicated a physical removal notification')
for _,options in ipairs({{server=false},{server=false,client=true},{server=true,client=true},{changedSource=true},{foreign='complete'},{foreign='removeAllMakeup'}})do
    local value=setup(options);assert(ISWashYourself.removeMakeup==value.before,'unsupported realm/source installed wrapper')
    local item=value.makeup(20,2);value.action:removeMakeup(item);assert(#value.sent==0 and not value.root:getItemById(20))
end
local function rejected(change)
    local value=setup();local item=value.makeup(30,2);change(value,item)
    value.action:removeMakeup(item);assert(#value.sent==0,'unknown/foreign ownership received notification')
end
rejected(function(v)v.action.complete=function()return true end end)
rejected(function(v)v.action.onCompleteFunc=function()end end)
rejected(function(v)ISWashYourself.complete=function()return true end end)
rejected(function(v)ISWashYourself.extraHelper=function()end end)
rejected(function()ISWashYourself={}end)
rejected(function(v,item)item.container={}end)
rejected(function(v,item)v.root.values[#v.root.values+1]=item end)
rejected(function(v,item)v.worn[2]={}end)
rejected(function(v)local item=v.root.values[1];item.slot=99;v.worn[2]=nil;v.worn[99]=item end)
rejected(function(v)v.root.getParent=function()return{}end end)
rejected(function(v)v.mode(false,false)end)
rejected(function()sendRemoveItemFromContainer=function()error('unknown packet function called')end end)
local failed=setup();local failureItem=failed.makeup(39,2);failed.root.Remove=function()error('native removal failed')end
local ok,message=pcall(failed.action.removeMakeup,failed.action,failureItem)
assert(not ok and tostring(message):find('native removal failed',1,true)and #failed.sent==0 and failed.removals()==1,'native failure replayed or received notification')
local value=setup();local item=value.makeup(40,2);value.root.Remove=function()end
value.action:removeMakeup(item);assert(value.root:getItemById(40)==item and #value.sent==0,'missing native physical removal got a packet')
print('Native body makeup removal sync tests passed.')
