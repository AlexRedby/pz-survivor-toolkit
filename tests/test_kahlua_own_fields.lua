-- Kahlua rawget traverses metatables; pairs enumerates delegate-own entries.
-- Installed native sources and existing focused fixture builders exercise the
-- real adapters under that verified engine lookup contract.
if not NativeActionRoot then print('SKIP Kahlua own-field regressions: supply --game'); return end
local function read(path)
    local file=assert(io.open(path));local value=file:read('*a');file:close();return value:gsub('\r','')
end
local client=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/'
local support=read(ProjectRoot..'/tests/support/action_queue_native.lua')
support=support:gsub('return setmetatable%(class,{__index=self}%)',
    'self.__index=self; return setmetatable(class,self)')
local function environment()
    local env=setmetatable({}, {__index=_G});env._G=env
    local nativeLoadstring=loadstring
    env.loadstring=function(source,name)
        local fn,message=nativeLoadstring(source,name)
        if fn then setfenv(fn,env) end
        return fn,message
    end
    env.loadfile=function(path)
        local source=path:find('/tests/support/action_queue_native.lua',1,true) and support or read(path)
        return env.loadstring(source,'@'..path)
    end
    env.dofile=function(path) return assert(env.loadfile(path))() end
    local luaRawget=rawget
    env.rawget=function(owner,key)
        local value=luaRawget(owner,key)
        if value~=nil then return value end
        local meta=getmetatable(owner)
        return meta and env.rawget(meta,key) or nil
    end
    return env
end
local function prefix(name,boundary,transform)
    local source=read(ProjectRoot..'/tests/'..name)
    local finish=assert(source:find(boundary,1,true),'fixture setup boundary missing: '..name)
    source=source:sub(1,finish-1)
    return transform and transform(source) or source
end
local function run(source,body)
    local env=environment()
    return assert(env.loadstring(source..'\n'..body,'@tests/kahlua-own-fields-fixture'))(),env
end
local radio=prefix('test_action_queue_edit_adapters.lua','\ndo\n    local s = setup()')
run(radio, [[
    local native=setup()
    assert(native.adapters.radio(native.action('SetVolume',.25)), 'native radio must retain its contract')
    local foreign=setup('base')
    assert(not foreign.adapters.radio(foreign.action('SetVolume',.25)),
        'foreign inherited invoke must not bypass its native-origin check')
]])
local media=prefix('test_action_queue_media.lua','\nlocal function nativeCancelHelpers',function(source)
    local marker=" local media=f.project('ActionQueueMedia');"
    local at=assert(source:find(marker,1,true))
    return source:sub(1,at-1)..[[
 if foreignCallback=='inherited' then
  getmetatable(ISDeviceMediaAction).update=function() error('foreign inherited update must not execute') end
 end
]]..source:sub(at)
end)
run(media, [[
    for _,wrapped in ipairs({false,true}) do
        local s=setup(wrapped)
        assert(s.installed and s.media.matches(ISDeviceMediaAction:new(s.f.player,false,s.item,s.square)),
            'native and supported owned TV media callbacks must retain their contract')
    end
    local s=setup(false,nil,'inherited')
    assert(not s.installed and not s.media.matches(ISDeviceMediaAction:new(s.f.player,false,s.item,s.square)),
        'foreign inherited media update must not install or receive queue permissions')
]])
local items=prefix('test_action_queue_item_edit_adapters.lua','\nend\ndo\n')..'\nend\n'
run(items, [[
    local s=setup()
    assert(s.adapters.drink(s.drink()) and s.adapters.food(s.eat(s.food())) and s.adapters.transfer(s.transfer()),
        'native item adapters must retain their contracts')
    for _,case in ipairs({{'ISEatFoodAction','isValid','food'}, {'ISInventoryTransferAction','isValid','transfer'}}) do
        s=setup(nil,nil,nil,{owner=case[1],name=case[2],inherited=true})
        local admitted
        if case[3]=='food' then admitted=s.adapters.food(s.eat(s.food())) else admitted=s.adapters.transfer(s.transfer()) end
        assert(not admitted, 'deleted preloaded own '..case[1]..'.'..case[2]..' must not inherit permission')
    end
    s=setup()
    local own=ISEatFoodAction.isValid
    ISEatFoodAction.isValid=nil
    assert(not s.adapters.food(s.eat(s.food())), 'deleted own callback must be rejected on a later inspection')
    ISEatFoodAction.isValid=own
    assert(s.adapters.food(s.eat(s.food())), 'restoring exact own callback must restore permission')
]])
local health=prefix('test_action_queue_health.lua','\nlocal body=part()')
run(health, [[
    assert(health.inspect(request(part(),'HApplyBandage','Base.Bandage')), 'native bandage producer remains supported')
]])
local missing=assert(health:find("local health=f.project('ActionQueueHealth')",1,true))
health=health:sub(1,missing-1)..'ISApplyBandage.new=nil\n'..health:sub(missing)
run(health, [[
    assert(not health.inspect(request(part(),'HApplyBandage','Base.Bandage')),
        'deleted own medical constructor must not inherit a base constructor permission')
]])
local recovery=prefix('test_action_queue_recovery_adapters.lua','\nlocal function capture(s,action,active)')
run(recovery, [[
    local s=setup();local action=s.book()
    assert(s.recovery.capture(action,false), 'native read recovery must retain its contract')
    ISBaseObject.invoke=function() error('foreign ancestor helper must not execute') end
    assert(not s.recovery.capture(action,false), 'foreign inherited recovery lifecycle must not receive native permission')
    ISBaseObject.invoke=nil
    assert(s.recovery.capture(action,false), 'removing the foreign inherited helper must restore native recovery')
    local nativeUpdate=ISReadABook.update
    ISReadABook.update=function() error('later foreign own callback must not execute') end
    assert(not s.recovery.capture(action,false), 'later foreign child callbacks must remain denied')
    ISReadABook.update=nativeUpdate
    assert(s.recovery.capture(action,false), 'restoring the native child callback restores recovery')
]])
print('PASS Kahlua provenance: native/owned positives; foreign inherited radio/media/recovery and missing own item/medical callbacks rejected')

local tagSetup=prefix('test_inventory_tags.lua','\nfor _,case in ipairs(')
-- Match native ISBaseObject/ISUIElement instance inheritance, not a Lua-only
-- proxy metatable containing an __index field.
tagSetup=tagSetup:gsub('local function pane%(c, clean%)\n','local function pane(c, clean)\n    c.__index=c\n',1)
tagSetup=tagSetup:gsub('}, {__index=c}%)','}, c)',1)
run(tagSetup, [[
    local function own(owner,key)
        for name,value in pairs(owner) do if name==key then return value end end
    end
    local p=pane(native,false)
    p:renderdetails(false)
    assert(own(p,'drawText')==nil and own(p,'drawTextRight')==nil, 'render must not materialize inherited drawing methods')
    local calls=0
    native.drawText=function() calls=calls+1 end
    native.drawTextRight=function() calls=calls+1 end
    p:drawText('later class draw',0,0);p:drawTextRight('later class right',0,0)
    assert(calls==2, 'later class drawing replacements must remain visible after tag rendering')
    local ownLeft,ownRight=function() calls=calls+1 end,function() calls=calls+1 end
    p.drawText,p.drawTextRight=ownLeft,ownRight
    p:renderdetails(false)
    assert(own(p,'drawText')==ownLeft and own(p,'drawTextRight')==ownRight, 'genuine own callbacks must survive success')
    p.fail=true;assert(not pcall(p.renderdetails,p,false))
    assert(own(p,'drawText')==ownLeft and own(p,'drawTextRight')==ownRight, 'genuine own callbacks must survive failure')
    p.drawText,p.drawTextRight=nil,nil
    assert(not pcall(p.renderdetails,p,false))
    assert(own(p,'drawText')==nil and own(p,'drawTextRight')==nil, 'inherited callbacks must remain inherited after failure')
]])
print('PASS Kahlua tag rendering: inherited/own callbacks, success/error restoration and late class replacements')

local generators=read(client..'ActionQueueGenerators.lua')
local first=assert(generators:find('local completed, ownCompleted = queue.onCompleted',1,true))
local last=assert(generators:find('return result',first,true))+#'return result'
local scope=generators:sub(first,last-1)
for _,own in ipairs({false,true}) do
    for _,fails in ipairs({false,true}) do
        local env=environment()
        env.Proof=assert(env.loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
        local later,earlier=0,0
        local class={onCompleted=function() earlier=earlier+1 end};class.__index=class
        local queue=setmetatable({},class)
        local ownCallback=own and function() earlier=earlier+1 end or nil
        queue.onCompleted=ownCallback
        local action={toolkitQueueOperation={}}
        env.action,env.pendingPerform=action,{}
        env.perform=function()
            queue:onCompleted(action)
            assert(env.pendingPerform[action]==queue, 'native completion must remain deferred inside the perform scope')
            if fails then error('expected native perform failure') end
            return 'native result'
        end
        env.Operations={runWith=function(token,callback,current)
            assert(token==action.toolkitQueueOperation and current==action)
            return callback(current)
        end}
        local wrap=assert(env.loadstring('return function(queue,...) '..scope..' end'))()
        local ok,result=pcall(wrap,queue)
        assert(ok~=fails and (fails or result=='native result'))
        local restored
        for name,value in pairs(queue) do if name=='onCompleted' then restored=value end end
        assert(restored==ownCallback, 'generator scope did not restore the genuine own callback value')
        if fails then assert(env.pendingPerform[action]==nil, 'failed native perform leaked its deferred completion') end
        class.onCompleted=function() later=later+1 end
        queue:onCompleted({})
        assert(own and later==0 and earlier==1 or not own and later==1 and earlier==0,
            'restored completion must preserve own callbacks or follow later class replacements')
    end
end
print('PASS Kahlua generator completion scope: native deferral, own/inherited restoration, errors and late class callbacks')

-- Count only the ownership scan, not nested inventory contents. The exact
-- product capture statements are executed without native drawing overhead.
local tags=read(client..'InventoryTags.lua')
local captureFrom=assert(tags:find('local savedText, savedRight\n',1,true))
local captureTo=assert(tags:find('        local draw, drawRight',captureFrom,true))
local capture=tags:sub(captureFrom,captureTo-1)
for _,fields in ipairs({64,128,256}) do
    local model={}
    for i=1,fields do model['field'..i]=i end
    model.items={};model.itemslist={}
    local visits,passes=0,0
    local env=environment()
    env.pairs=function(owner)
        assert(owner==model, 'ownership capture must not inspect nested items')
        passes=passes+1
        local iterator,state,key=pairs(owner)
        return function(s,k)
            local name,value=iterator(s,k)
            if name then visits=visits+1 end
            return name,value
        end,state,key
    end
    local captureOwn=assert(env.loadstring('return function(pane) '..capture..' return savedText,savedRight end'))()
    for _,items in ipairs({2400,4800}) do
        for i=1,items do model.items[i]=i end
        visits,passes=0,0
        for _=1,60 do captureOwn(model) end
        assert(passes==60 and visits==60*(fields+2), 'capture must perform exactly one own-field pass per scope')
    end
    env.pairs=pairs
    local start=os.clock()
    for _=1,10000 do captureOwn(model) end
    print('Kahlua own-field scan benchmark (Lua51 only): '..(fields+2)..' fields, 10000 scopes, '..string.format('%.1f',(os.clock()-start)*1000)..' ms')
end
print('PASS tag ownership scan: one pane-field pass per render, independent of 2400/4800 nested items')
