-- World doubles only. All sweep, cache, Core and Client code is external source.
local function noop() end
function require() end
function print() end
Events = {}
for _, name in ipairs({'OnTick','LoadChunk','OnGameBoot','OnServerCommand'}) do
    Events[name] = { Add = function(fn) Events[name].callback = fn end }
end
local px, py, pz = 10000, 10000, 0
local player = {getX=function() return px end,getY=function() return py end,getZ=function() return pz end}
local players = {player}
function getNumActivePlayers() return #players end
function getSpecificPlayer(i) return players[i+1] end
local calls, objects, auto = 0, 0, 0
local mask, revision = 'empty', 0
local emptyObjects = {size=function() return 0 end}
local ordinary = {getContainerCount=function() return 0 end}
local container = {getType=function() return 'fridge' end}
local fridge = {getContainerCount=function() return 1 end,
    getContainerByIndex=function() return container end,
    hasModData=function() return false end,
    getModData=function() return {} end}
local ordinaryObjects = {size=function() return 1 end,get=function() objects=objects+1; return ordinary end}
local fridgeObjects = {size=function() return 1 end,get=function() objects=objects+1; auto=auto+1; return fridge end}
local emptySquare = {getObjects=function() return emptyObjects end}
local ordinarySquare = {getObjects=function() return ordinaryObjects end}
local fridgeSquare = {getObjects=function() return fridgeObjects end}
function getSquare(x,y,z)
    calls = calls + 1
    if mask == 'unloaded' then return nil end
    if mask == 'late' then if revision == 0 then return nil end; return emptySquare end
    if mask == 'ordinary' then return ordinarySquare end
    if mask == 'fridge' then return fridgeSquare end
    if mask == 'mixed' then
        if (x+y)%7 == 0 then return nil end
        if x%31 == 0 and y%17 == 0 then return fridgeSquare end
        return ordinarySquare
    end
    return emptySquare
end
local function resetCounts() calls, objects, auto = 0,0,0 end
function fixtureCheck()
    local t, c = Events.OnTick.callback, Events.LoadChunk.callback
    for i=1,119 do t() end
    assert(calls == 0, 'early periodic sweep')
    t(); assert(calls == 961, 'first periodic sweep')
    resetCounts(); c(); t(); assert(calls == 0, 'warm cache miss')
    mask='fridge'; c(); t(); assert(calls == 0, 'changed stale-negative semantics')
    -- Different elevation must not share negatives. Fridges remain uncached.
    pz=-1; c(); t(); assert(calls == 961 and objects == 961, 'elevation or fridge classification')
    resetCounts(); c(); t(); assert(calls == 961, 'fridge cached')
    -- Missing squares must be retried, then cached once loaded.
    pz=2; mask='late'; revision=0; resetCounts(); c(); t(); assert(calls == 961, 'unloaded first')
    revision=1; resetCounts(); c(); t(); assert(calls == 961, 'unloaded cached')
    resetCounts(); c(); t(); assert(calls == 0, 'loaded empty not cached')
    -- Consecutive load nudges each permit a sweep, including addToWorld race.
    pz=3; mask='unloaded'; resetCounts(); c(); c(); t(); assert(calls == 961, 'load nudge')
    c(); t(); assert(calls == 1922, 'consecutive load nudge')
    -- Load nudge resets periodic counter without changing its 120-tick interval.
    resetCounts(); for i=1,119 do t() end; assert(calls == 0, 'counter not reset')
    t(); assert(calls == 961, 'period after nudge')
    -- Negative coordinates and large separated axes have distinct membership.
    mask='empty'; local centers={{-10000,-10000,0},{-10000,10000,0},{10000,-10000,0},
        {2147483600,2147483600,31},{-2147483600,-2147483600,-32},{0,0,0}}
    for _, v in ipairs(centers) do
        px,py,pz=v[1],v[2],v[3]; resetCounts(); c(); t(); assert(calls==961, 'coordinate alias')
        resetCounts(); c(); t(); assert(calls==0, 'coordinate negative lost')
    end
    pz=-1*0; resetCounts(); c(); t(); assert(calls==0, 'signed-zero cache identity')
    -- Two distinct players visit the union; overlapping cached squares are skipped.
    px,py,pz=20000,20000,0
    players={player,{getX=function() return px+1 end,getY=function() return py end,getZ=function() return pz end}}
    resetCounts(); c(); t(); assert(calls==992, 'split screen cache overlap')
    return 'cadence,load-race,negative-membership,unloaded,fridge,stale-negative,axes,split-screen:PASS'
end
function fixturePrepare(label)
    mask = label=='mixed' and 'mixed' or 'empty'
    px,py,pz = 10000,10000,0
    if label=='warm' or label=='mixed' then Events.LoadChunk.callback(); Events.OnTick.callback() end
    resetCounts()
end
function fixtureLoop(label, count)
    for i=1,count do
        if label=='cold' then px=px+31 end
        if label=='moving' then px=px+1 end
        Events.LoadChunk.callback()
        Events.OnTick.callback()
    end
    return calls .. ':' .. objects .. ':' .. auto
end
