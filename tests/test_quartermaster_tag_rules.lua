local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local loaded = {}
local oldRequire = require
require = function(name)
    if loaded[name] then return loaded[name] end
    local file = root .. 'shared/' .. name .. '.lua'
    local fn = loadfile(file)
    if not fn then return oldRequire(name) end
    loaded[name] = fn()
    return loaded[name]
end
local mode, enabled, disk, clock = 'sp', true, {}, 100
isClient = function() return mode == 'client' end
isServer = function() return mode == 'server' end
getTimestampMs = function() return clock end
PZSurvivorToolkit = {Settings = {itemTags = function() return enabled end}}
local function event() return {handlers = {}, Add = function() end} end
Events = {}
for _, name in ipairs({'OnGameStart','OnCreatePlayer','OnObjectAdded','OnInitGlobalModData','OnClientCommand','OnServerCommand','OnTick','OnReceiveGlobalModData'}) do
    local e = event(); Events[name] = e
    e.Add = function(fn) e.handlers[#e.handlers + 1] = fn end
end
local moddata = {}
ModData = {getOrCreate = function(key) moddata[key] = moddata[key] or {}; return moddata[key] end,
    transmit = function() end, request = function() end}
getFileReader = function(path)
    local text = disk[path]
    if not text then return nil end
    local done = false
    return {readLine = function() if not done then done = true; return text end end, close = function() end}
end
getFileWriter = function(path) return {write = function(_, text) disk[path] = text end, close = function() end} end
local function list(values)
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end}
end
local square = {getX = function() return 10 end, getY = function() return 20 end, getZ = function() return 0 end}
local current = {getX = function() return 10 end, getY = function() return 19 end, getZ = function() return 0 end,
    isBlockedTo = function(self) return self.blocked end}
local player = {getCurrentSquare = function() return current end, getUsername = function() return 'survivor' end}
getSpecificPlayer = function() return player end
local container = {isLockedToCharacter = function(self) return self.locked end}
local object = {md = {}, getSquare = function() return square end, getObjectIndex = function() return 0 end,
    getContainerCount = function() return 1 end, getContainerByIndex = function() return container end,
    transmitModData = function(self) self.transmits = (self.transmits or 0) + 1 end}
object.getModData = function(self) return self.md end
object.hasModData = function() return true end
square.getObjects = function() return list({object}) end
getCell = function() return {getGridSquare = function(_, x,y,z) if x == 10 and y == 20 and z == 0 then return square end end} end
local safe = true
SafeHouse = {isSafehouseAllowLoot = function(sq, authenticated) assert(authenticated == player and sq == square); return safe end}
local Tags = require 'PZSurvivorToolkit/ItemTags'
assert(Tags.normalizeRule, 'ItemTags rule API missing')
local categories = {'Food','foodPerishable','Electronics'}
-- The resolver boundary used by Core's private gather closure and the public manifest path.
local function union(target, source) for k,v in pairs(source or {}) do if v then target[k] = v end end end
LootSorter = {serverFns = {}, getCategories = function() return categories end,
    parseCoordKey = function(key) local x,y,z=key:match('^(%d+),(%d+),(%d+)$'); return tonumber(x),tonumber(y),tonumber(z) end,
    linkResolves = function(preset, link) return preset and (link == true or preset.gen == link) end,
    getRegistry = function() return ModData.getOrCreate('LootSorter_Registry').boxes or {} end}
LootSorter.modDataHasDesignation = function(md)
    for _, field in ipairs({'LSBox','LSBoxItems','LSBoxPresets'}) do
        for _, set in pairs(md[field] or {}) do for _, on in pairs(set) do if on then return true end end end
    end
    return false
end
LootSorter.squareHasDesignation = function() return LootSorter.modDataHasDesignation(object.md) end
local presets = {}
LootSorter.getPresetStore = function() return presets end
LootSorter.resolveEffective = function(cats, items, links, store)
    local a,b = {}, {}; union(a,cats); union(b,items)
    for name,link in pairs(links or {}) do
        local p=store and store[name]
        if LootSorter.linkResolves(p,link) then union(a,p.cats); union(b,p.items) end
    end
    return a,b
end
local function privateFind()
    local md=object.md
    if not (md.LSBox or md.LSBoxItems or md.LSBoxPresets) then return {} end
    return LootSorter.resolveEffective(md.LSBox and md.LSBox['0'], md.LSBoxItems and md.LSBoxItems['0'],md.LSBoxPresets and md.LSBoxPresets['0'],presets)
end
LootSorter.findDesignatedOnSquare = privateFind
LootSorter.serverFns.putPreset = function(_, args)
    local existing=presets[args.name]
    if existing and args.baseRev ~= existing.rev then return 'stale' end
    presets[args.name] = {cats=args.cats,items=args.items,gen=existing and existing.gen or clock,rev=(existing and existing.rev or 0)+1}
    return 'ok'
end
LootSorter.serverFns.removePreset = function(_, args) presets[args.name] = nil; return 'ok' end
local function serialize(value)
    if type(value) ~= 'table' then return type(value)=='string' and string.format('%q', value) or tostring(value) end
    local out={'{'}; for key,v in pairs(value) do out[#out+1]='['..serialize(key)..']='..serialize(v)..',' end
    out[#out+1]='}'; return table.concat(out)
end
LootSorter.presetSerialize = function(value) return 'return '..serialize(value) end
LootSorter.presetDeserialize = function(text) return assert(loadstring(text))() end
if NativeQuartermasterLuaRoot then
    dofile(NativeQuartermasterLuaRoot .. '/shared/LootSorter_Presets.lua')
    dofile(NativeQuartermasterLuaRoot .. '/shared/LootSorter_Util.lua')
    loaded['TimedActions/ISTimedActionQueue'], loaded['TimedActions/ISInventoryTransferAction'] = {}, {}
    LootSorter.DBG = function() end
    LootSorter.arePresetsSynced = function() return true end
    LootSorter.removeCoords = function() end
    dofile(NativeQuartermasterLuaRoot .. '/client/LootSorter_Core.lua')
end
local Rules = require 'PZSurvivorToolkit/QuartermasterTagRules'
dofile(root .. 'server/PZSurvivorToolkit/QuartermasterTagRuleAuthority.lua')
dofile(root .. 'client/PZSurvivorToolkit/QuartermasterTagRuleClient.lua')
Rules.installAuthority(); Rules.installClient()
local rule={mode='all',include={'food'},exclude={'perishable'}}
local function args(value) return {x=10,y=20,z=0,object=0,ci=0,rule=value or rule,baseRevision=Rules.getBoxRevision(object,0)} end
local nativeLootSorter = LootSorter
LootSorter = nil
assert(Rules.applyBox(player,args())=='invalid' and not object.md[Rules.FIELD] and not object.md[Rules.REVISIONS],
    'command mutated ModData without Quartermaster installed')
LootSorter = nativeLootSorter
local oldRevisionArgs = args()
local verdict, revision = Rules.applyBox(player,args())
assert(verdict=='ok' and revision==1 and Rules.getBoxRevision(object,0)==1)
assert(Rules.applyBox(player,oldRevisionArgs)=='stale' and Rules.getBoxRevision(object,0)==1,
    'concurrent stale editor replaced newer rule')
assert(object.md[Rules.FIELD]['0'].include[1]=='food' and not object.md.LSBox['0'].food)
assert(LootSorter.modDataHasDesignation(object.md), 'rule-only box lost designation')
LootSorter.getRegistry()
local cats=privateFind()
assert(cats.Food and not cats.foodPerishable and not cats.Electronics, 'private sorter did not resolve rule')
if NativeQuartermasterLuaRoot then
    local boxes = LootSorter.gatherBoxes(player)
    assert(#boxes == 1 and boxes[1].cats.Food and boxes[1].container == container, 'installed native private gather missed rule-only box')
    boxes = LootSorter.gatherBoxesOrWarn(player)
    assert(#boxes == 1 and boxes[1].cats.Food, 'installed native sorter gather missed rule-only box')
    mode='client'; LootSorter._receivedRegistry=moddata.LootSorter_Registry
    object.md.LSBox['0']=nil; safe=false
    boxes=LootSorter.gatherBoxes(player)
    assert(#boxes==0 and object.md.LSBox['0']==nil, 'rule lookup touched forbidden safehouse before native permission gate')
    safe=true; boxes=LootSorter.gatherBoxes(player)
    assert(#boxes==1 and boxes[1].cats.Food, 'allowed MP gather lost rule-only box')
    -- Manifest/public lookup does not run inside gather, and getRegistry resets the lookup index.
    LootSorter._manifestWin={playerNum=0}
    LootSorter.getRegistry()
    boxes=LootSorter.findDesignatedOnSquare(square)
    assert(#boxes==1 and boxes[1].cats.Food, 'MP manifest/public lookup lost rule-only box outside gather')
    safe=false; object.md.LSBox['0']=nil; LootSorter.getRegistry()
    boxes=LootSorter.findDesignatedOnSquare(square)
    assert(#boxes==0 and object.md.LSBox['0']==nil, 'MP manifest bypassed safehouse permission')
    safe=true; mode='sp'
end
object.md.LSBox['0']={foodPerishable=true, PreciseModCategory=true}
LootSorter.getRegistry(); cats=privateFind()
assert(cats.foodPerishable and cats.PreciseModCategory, 'rule exclusions stripped manual picks')
local schema=require 'PZSurvivorToolkit/ItemTagSchema'
schema.categories.FutureFood={'food'}; categories[#categories+1]='FutureFood'
LootSorter.getRegistry(); cats=privateFind(); assert(cats.FutureFood, 'saved rule froze current categories')
enabled=false; LootSorter.getRegistry(); cats=privateFind(); assert(not cats.FutureFood and cats.PreciseModCategory)
enabled=true
-- A native empty category save removes the temporary anchor. Re-indexing restores only the empty anchor.
object.md.LSBox['0']=nil; LootSorter.getRegistry(); cats=privateFind(); assert(cats.FutureFood)
assert(Rules.applyBox(player,args({mode='all',include={},exclude={}}))=='ok')
LootSorter.findDesignatedOnSquare(square); cats=privateFind(); assert(not cats.FutureFood, 'cleared rule stayed in table lookup')
mode='server'
assert(Rules.applyBox(nil,args())=='invalid', 'unauthenticated write allowed')
local bad=args(); bad.object=1; assert(Rules.applyBox(player,bad)=='missing')
bad=args(); bad.ci=1; assert(Rules.applyBox(player,bad)=='missing')
bad=args(); bad.x=10.5; assert(Rules.applyBox(player,bad)=='invalid')
bad=args({mode='all',include={'__unknown__'},exclude={}}); assert(Rules.applyBox(player,bad)=='invalid')
safe=false; assert(Rules.applyBox(player,args())=='denied'); safe=true
current.blocked=true; assert(Rules.applyBox(player,args())=='unreachable'); current.blocked=false
container.locked=true; assert(Rules.applyBox(player,args())=='denied'); container.locked=false
local oldCurrent=current; current={getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end}
assert(Rules.applyBox(player,args())=='unreachable'); current=oldCurrent
mode='client'; assert(Rules.applyBox(player,args())=='invalid'); mode='sp'
-- Preserve native preset conflict checks; store only normalized rule data after success.
local put=LootSorter.serverFns.putPreset
assert(put(player,{name='Pantry',cats={Precise=true},items={Beans=true},pzstTagRule=rule})=='ok')
assert(Rules.getPreset('Pantry',presets.Pantry))
local saved=disk['PZSTQuartermasterTagRules.txt']; assert(saved)
Rules.localPresets=nil
assert(Rules.getPreset('Pantry',presets.Pantry).exclude[1]=='perishable','SP rules did not survive file roundtrip')
local anyRule={mode='any',include={'food','electrical'},exclude={'perishable'}}
assert(put(player,{name='Either',cats={},items={},pzstTagRule=anyRule})=='ok')
Rules.localPresets=nil
assert(Rules.getPreset('Either',presets.Either).mode=='any', 'SP any-rule mode was lost in sidecar')
local either=LootSorter.resolveEffective({}, {}, {Either=presets.Either.gen}, presets)
assert(either.Food and either.Electronics and not either.foodPerishable, 'saved any+excluded rule changed semantics')
local rev=presets.Pantry.rev
assert(put(player,{name='Pantry',baseRev=0,cats={},items={},pzstTagRule={mode='any',include={'electrical'},exclude={}}})=='stale')
assert(presets.Pantry.rev==rev and Rules.getPreset('Pantry',presets.Pantry).include[1]=='food')
local effective,items=LootSorter.resolveEffective({Manual=true},{ManualItem=true},{Pantry=presets.Pantry.gen},presets)
assert(effective.FutureFood and effective.Manual and effective.Precise and items.Beans and items.ManualItem)
presets.Pantry.gen=presets.Pantry.gen+1
assert(not Rules.getPreset('Pantry',presets.Pantry), 'deleted/remade preset inherited prior rule')
assert(LootSorter.serverFns.removePreset(player,{name='Pantry'})=='ok' and not Rules.presetStore().Pantry)
if NativeQuartermasterLuaRoot then
    -- Paste must keep clipboard A's native picks when another copy replaces the global clipboard with B.
    local originalSave, pasteReply = Rules.saveBox
    Rules.saveBox = function(_,_,_,_,callback) pasteReply=callback end
    LootSorter.addCoord = function() end
    LootSorter.clipboard={cats={ClipboardA=true},items={ItemA=true},presets={},priority=3,pzstTagRule=rule}
    LootSorter.pasteDesignation(object,0)
    local newerClipboard={cats={ClipboardB=true},items={ItemB=true},presets={},priority=9}
    LootSorter.clipboard=newerClipboard
    pasteReply('ok',10)
    assert(object.md.LSBox['0'].ClipboardA and not object.md.LSBox['0'].ClipboardB
        and object.md.LSBoxItems['0'].ItemA and LootSorter.clipboard==newerClipboard,
        'pending paste mixed new clipboard selections with old accepted rule')
    Rules.saveBox=originalSave
end
-- Client commands carry the selected authenticated player; failures and timeouts leave caller in control.
mode='client'; local sent, callback
sendClientCommand=function(authenticated,module,command,packet) assert(authenticated==player); sent=packet end
Rules.saveBox(object,0,rule,player,function(verdict) callback=verdict end)
assert(sent and callback==nil)
for _, fn in ipairs(Events.OnServerCommand.handlers) do fn('PZSTQuartermasterTags','saved',{token=sent.token,verdict='denied'}) end
assert(callback=='denied')
object.md[Rules.FIELD] = nil
callback=nil
Rules.saveBox(object,0,rule,player,function(verdict)
    callback=verdict
    assert(Rules.getBox(object,0), 'native save could transmit before accepted server rule reached object ModData')
end)
for _, fn in ipairs(Events.OnServerCommand.handlers) do fn('PZSTQuartermasterTags','saved',{token=sent.token,verdict='ok',revision=sent.baseRevision+1}) end
assert(callback=='ok' and Rules.getBox(object,0).include[1]=='food')
callback=nil
object.md[Rules.REVISIONS]['0']=7
Rules.saveBox(object,0,rule,player,function(verdict) callback=verdict end)
object.md[Rules.REVISIONS]['0']=9
object.md[Rules.FIELD]['0']={mode='all',include={'electrical'},exclude={}}
for _, fn in ipairs(Events.OnServerCommand.handlers) do fn('PZSTQuartermasterTags','saved',{token=sent.token,verdict='ok',revision=8}) end
assert(callback=='stale' and Rules.getBoxRevision(object,0)==9 and Rules.getBox(object,0).include[1]=='electrical',
    'older successful reply overwrote newer observed object rule/revision')
for _, malformed in ipairs({'10', 10.5, math.huge, 0/0, false}) do
    callback=nil
    Rules.saveBox(object,0,rule,player,function(verdict) callback=verdict end)
    for _, fn in ipairs(Events.OnServerCommand.handlers) do
        fn('PZSTQuartermasterTags','saved',{token=sent.token,verdict='ok',revision=malformed})
    end
    assert(callback=='invalid' and Rules.getBoxRevision(object,0)==9, 'malformed reply revision was accepted')
end
callback=nil; Rules.saveBox(object,0,rule,player,function(verdict) callback=verdict end)
clock=clock+16000; for _,fn in ipairs(Events.OnTick.handlers) do fn() end
assert(callback=='timeout')
print('Quartermaster rules passed: dynamic resolver, exact picks, opt-out, clearing, authority, SP persistence, preset conflicts, client refusal/timeout.')
