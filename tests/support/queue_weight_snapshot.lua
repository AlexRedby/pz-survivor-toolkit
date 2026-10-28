-- Development-only synchronous batch prototype, not a runtime permission path.
-- Original Weights arithmetic is instrumented in memory, never copied/replaced
-- on disk. Unknown topology yields no partially publishable weight maps.
-- capture(actor,{containers={},items={}},{nodes=25000,edges=50000,depth=64})
-- -> {status='complete'|'unsupported'|'limited',containers?,items?,counters,reason?}
-- Explicit roots may overlap. Multiple actual ownership edges may not. Such
-- invalid graphs are deliberately outside parity with legacy native shortcuts.
local Snapshot={}
local path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueWeights.lua'
local function read(path)
    if NativeReadText then return NativeReadText(path)end
    local file=assert(io.open(path));local text=file:read('*a');file:close();return text
end
local function replace(text,old,new)
    local first,last=text:find(old,1,true)
    assert(first and not text:find(old,last+1,true),'snapshot instrumentation anchor changed')
    return text:sub(1,first-1)..new..text:sub(last+1)
end
local source=read(path):gsub('\r','')
source=replace(source,'local Weights = {}','local Weights = {}\nlocal captured')
source=replace(source,'local function entries(container)','local function nativeEntries(container)')
source=replace(source,'local function free(value,seen)',[[local function entries(container)
    if captured then
        local node=captured.nodes[container]
        if node and node.list then return node.list,#node.children end
        return
    end
    return nativeEntries(container)
end
local function free(value,seen)]])
source=replace(source,'function Weights.factoryFree(value) return free(value,{}) end',[[function Weights.factoryFree(value)
    if captured then local node=captured.nodes[value];return node and node.factoryFree or false end
    return free(value,{})
end]])
source=replace(source,'\nreturn Weights','\n'..[[
local originalItem,originalContents,originalMultiplier=boundItem,boundContents,multiplier
boundItem=function(item,mode,context)
    if not captured then return originalItem(item,mode,context)end
    local modes=captured.itemWeights[mode]
    if not modes then modes={};captured.itemWeights[mode]=modes end
    local cached=modes[item]
    if cached~=nil then
        captured.counters.itemWeightHits=captured.counters.itemWeightHits+1
        if type(cached)=='number'then return cached,cached end
        return cached.upper,cached.lower
    end
    local upper,lower=originalItem(item,mode,context)
    if upper~=nil and upper==lower then modes[item]=upper else modes[item]={upper=upper,lower=lower}end
    return upper,lower
end
boundContents=function(container,context)
    if not captured then return originalContents(container,context)end
    local cached=captured.contents[container]
    if cached then captured.counters.contentsHits=captured.counters.contentsHits+1;return cached.upper,cached.lower end
    local upper,lower=originalContents(container,context)
    captured.contents[container]={upper=upper,lower=lower}
    return upper,lower
end
multiplier=function(actor)
    if not captured then return originalMultiplier(actor)end
    if actor~=captured.actor then return end
    if not captured.multiplier then captured.multiplier={value=originalMultiplier(actor)}end
    return captured.multiplier.value
end
return Weights,function(value)captured=value end]])
local namespace=PZSurvivorToolkit
PZSurvivorToolkit=namespace or {}
local previous=PZSurvivorToolkit.ActionQueueWeights
local weights,setCaptured=assert(loadstring(source,'@'..path))()
PZSurvivorToolkit.ActionQueueWeights=previous
PZSurvivorToolkit=namespace
local defaults={nodes=25000,edges=50000,depth=64}
local busy
local freeLeaf={factoryFree=true,height=0}
local affectedLeaf={factoryFree=false,height=0}
local function plain(value)return type(value)=='table'and getmetatable(value)==nil end
local function finite(value)return type(value)=='number'and value==value and value>-math.huge and value<math.huge end
local function method(value,name)return value and type(value[name])=='function'end
local function identity(value)return type(value)=='table'or type(value)=='userdata'end
local function array(value,limit)
    if not plain(value)then return end
    local count,maximum=0,0
    for index in pairs(value)do
        if not finite(index)or index<1 or index%1~=0 then return end
        count=count+1;maximum=math.max(maximum,index)
        if count>limit then return false end
    end
    if maximum~=count then return end
    return count
end
function Snapshot.capture(actor,request,limits)
    local counters={nodes=0,edges=0,itemReads=0,containerReads=0,itemWeightHits=0,contentsHits=0}
    local result={status='unsupported',reason='request',counters=counters}
    if busy then busy.invalidated=true;result.reason='reentrant';return result end
    if not plain(request)or limits~=nil and not plain(limits)then return result end
    for key in pairs(request)do if key~='containers'and key~='items'then return result end end
    local bounds={}
    for key,value in pairs(limits or {})do
        if defaults[key]==nil or not finite(value)or value<0 or value%1~=0 or value>1000000 then
            result.reason='limits';return result
        end
        bounds[key]=value
    end
    for key,value in pairs(defaults)do if bounds[key]==nil then bounds[key]=value end end
    -- Depth is an execution-stack guard as well as a resource bound. Refuse an
    -- attempted override above the tested ceiling before recursive capture.
    if bounds.depth>64 then result.reason='limits';return result end
    local requests={containers=request.containers==nil and {}or request.containers,
        items=request.items==nil and {}or request.items}
    local counts={}
    for key,value in pairs(requests)do
        counts[key]=array(value,bounds.nodes)
        if counts[key]==false then result.status,result.reason='limited','nodes';return result end
        if counts[key]==nil then return result end
        for i=1,counts[key]do if not identity(value[i])then return result end end
    end
    local state={actor=actor,nodes={},parents={},itemWeights={},contents={},counters=counters}
    busy=state
    local function fail(status,reason)result.status,result.reason=status,reason;return false end
    local function spend(key)
        if counters[key]>=bounds[key]then return fail('limited',key)end
        counters[key]=counters[key]+1;return true
    end
    local function list(children)
        return {size=function()return #children end,get=function(_,index)return children[index+1]end}
    end
    local visit
    visit=function(value,parent,depth)
        if depth>bounds.depth then return fail('limited','depth')end
        local node=state.nodes[value]
        if node then
            if node.visiting then return fail('unsupported','cycle')end
            if depth+node.height>bounds.depth then return fail('limited','depth')end
            if parent then
                if state.parents[value]then return fail('unsupported','alias')end
                state.parents[value]=parent
            end
            return node
        end
        if not spend('nodes')then return false end
        state.parents[value]=parent
        if instanceof(value,'InventoryContainer')then
            node={visiting=true,factoryFree=true,height=0};state.nodes[value]=node
            if not method(value,'getInventory')then return fail('unsupported','inventory')end
            local container=value:getInventory()
            if not instanceof(container,'ItemContainer')then return fail('unsupported','inventory')end
            if not spend('edges')then return false end
            local child=visit(container,node,depth+1)
            if not child then return false end
            node.factoryFree=child.factoryFree;node.height=child.height+1
        elseif instanceof(value,'ItemContainer')then
            node={visiting=true,factoryFree=true,height=0,children={}};state.nodes[value]=node
            if not method(value,'getItems')then return fail('unsupported','items')end
            local values=value:getItems();counters.containerReads=counters.containerReads+1
            if not method(values,'size')or not method(values,'get')then return fail('unsupported','items')end
            local count=values:size()
            if not finite(count)or count<0 or count%1~=0 then return fail('unsupported','items')end
            if count>bounds.edges-counters.edges then return fail('limited','edges')end
            for i=0,count-1 do
                if not spend('edges')then return false end
                local item=values:get(i);counters.itemReads=counters.itemReads+1
                if not instanceof(item,'InventoryItem')then return fail('unsupported','item')end
                node.children[#node.children+1]=item
                local child=visit(item,node,depth+1)
                if not child then return false end
                node.factoryFree=node.factoryFree and child.factoryFree
                node.height=math.max(node.height,child.height+1)
            end
            node.list=list(node.children)
        elseif instanceof(value,'InventoryItem')then
            local safe=not instanceof(value,'Food')or method(value,'haveExtraItems')and not value:haveExtraItems()
            node=safe and freeLeaf or affectedLeaf;state.nodes[value]=node
            return node
        else return fail('unsupported','object')end
        node.visiting=nil
        return node
    end
    local function capture()
        -- Capture the union before invoking any aggregate getter or publishing
        -- weights. Repeated explicit requests never create ownership edges.
        for _,kind in ipairs({'containers','items'})do
            for i=1,counts[kind]do
                local value=requests[kind][i]
                if kind=='containers'and not instanceof(value,'ItemContainer')
                    or kind=='items'and not instanceof(value,'InventoryItem')then return false end
                if not visit(value,nil,0)then return false end
            end
        end
        if state.invalidated then return fail('unsupported','reentrant')end
        local containers,items={},{}
        setCaptured(state)
        for _,kind in ipairs({'containers','items'})do
            local output=kind=='containers'and containers or items
            for i=1,counts[kind]do
                local value=requests[kind][i]
                if not output[value]then
                    local upper,lower
                    if kind=='containers'then upper,lower=weights.capacity(value,actor)
                    else upper,lower=weights.unequipped(value)end
                    if not finite(upper)or not finite(lower)or upper<0 or lower<0 or lower>upper then
                        return fail('unsupported','weight')
                    end
                    output[value]={upper=upper,lower=lower}
                end
            end
        end
        if state.invalidated then return fail('unsupported','reentrant')end
        result.status,result.reason,result.containers,result.items='complete',nil,containers,items
        return true
    end
    local ok=pcall(capture)
    setCaptured(nil);busy=nil
    if not ok then
        result.status,result.reason='unsupported','getter_error';result.containers,result.items=nil,nil
    end
    return result
end
return Snapshot
