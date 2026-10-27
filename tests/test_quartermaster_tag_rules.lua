local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local loaded = {}
local oldRequire = require
require = function(name)
    if loaded[name] then return loaded[name] end
    local file = root .. 'shared/' .. name .. '.lua'
    local fn = loadfile(file)
    if not fn then return oldRequire(name) end
    loaded[name] = fn() or true
    return loaded[name]
end
local mode, enabled, disk, clock = 'sp', true, {}, 100
isClient = function() return mode == 'client' end
isServer = function() return mode == 'server' end
getTimestampMs = function() return clock end
getText = function(key) return key end
PZSurvivorToolkit = {Settings = {itemTags = function() return enabled end}}
local function event() return {handlers = {}, Add = function() end} end
Events = {}
for _, name in ipairs({'OnGameStart','OnCreatePlayer','OnObjectAdded','OnInitGlobalModData','OnClientCommand','OnServerCommand','OnTick','OnReceiveGlobalModData'}) do
    local e = event(); Events[name] = e
    e.Add = function(fn) e.handlers[#e.handlers + 1] = fn end
    e.Remove = function(fn)
        for i = #e.handlers, 1, -1 do if e.handlers[i] == fn then table.remove(e.handlers, i) end end
    end
end
local moddata = {}
ModData = {getOrCreate = function(key) moddata[key] = moddata[key] or {}; return moddata[key] end,
    transmit = function() end, request = function() end}
getFileReader = function(path, create)
    if create and disk[path] == nil then disk[path] = '' end
    local text = disk[path]
    if not text then return nil end
    local lines, index = {}, 0
    if text ~= '' then
        for line in (text:gsub('\n$', '') .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = line end
    end
    return {readLine = function() index = index + 1; return lines[index] end, close = function() end}
end
getFileWriter = function(path, create, append)
    assert(create == true and append == false)
    disk[path] = ''
    return {write = function(_, text) disk[path] = disk[path] .. text end, close = function() end}
end
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
instanceof = function(value, kind) return value == object and kind == 'IsoObject' end
square.getObjects = function() return list({object}) end
getCell = function() return {getGridSquare = function(_, x,y,z) if x == 10 and y == 20 and z == 0 then return square end end} end
local safe = true
SafeHouse = {isSafehouseAllowLoot = function(sq, authenticated) assert(authenticated == player and sq == square); return safe end}
local Tags = require 'PZSurvivorToolkit/ItemTags'
assert(Tags.normalizeRule, 'ItemTags rule API missing')
local categories = {'Food','foodPerishable','Electronics'}
LootSorter = {serverFns = {}, getCategories = function() return categories end,
    getItemNames = function() return {} end,
    getDisplayNameForFullType = function(value) return value end,
    getItemFullType = function(value) return value end}
local function presets() return LootSorter.getPresetStore() end
LootSorter.isAuthority = function() return not isClient() end
LootSorter.RPC_TIMEOUT_MS, LootSorter.RPC_SWEEP_MS = 15000, 5000
require 'LootSorter_Rpc'
dofile(root .. 'shared/LootSorter_Presets.lua')
dofile(root .. 'shared/LootSorter_Util.lua')
dofile(root .. 'shared/LootSorter_Plan.lua')
loaded['TimedActions/ISTimedActionQueue'], loaded['TimedActions/ISInventoryTransferAction'] = {}, {}
LootSorter.DBG = function() end
LootSorter.removeCoords = function() end
dofile(root .. 'client/LootSorter_PresetSync.lua')
dofile(root .. 'client/LootSorter_Core.lua')
local originalRegistry, originalResolver, originalPlanner = LootSorter.getRegistry, LootSorter.resolveEffective, LootSorter.planTrips
local Rules = require 'PZSurvivorToolkit/QuartermasterTagRules'
dofile(root .. 'server/LootSorter_Presets.lua')
dofile(root .. 'server/PZSurvivorToolkit/QuartermasterTagRuleAuthority.lua')
dofile(root .. 'client/PZSurvivorToolkit/QuartermasterTagRuleClient.lua')
assert(LootSorter.getRegistry == originalRegistry and LootSorter.resolveEffective == originalResolver
    and LootSorter.planTrips == originalPlanner, 'tag rules replaced discovery or planner APIs')
local function record(category, fullType)
    return {cat = category, ref = {getDisplayCategory = function() return category end,
        getFullType = function() return fullType end}}
end
local function target()
    return LootSorter.findDesignatedOnSquare(square, player)[1] or {cats = {}, items = {}, rules = {}}
end
do
 local toyBox={cats={},rules={{mode='all',include={'toy'},exclude={}}}}
 local weaponBox={cats={},rules={{mode='all',include={'weapon'},exclude={}}}}
 local toy=record('weaponRanged','Base.Revolver_CapGun')
 local weapon=record('weaponRanged','Base.Crossbow')
 assert(Rules.matches(toyBox,toy) and not Rules.matches(toyBox,weapon), 'toy box inherited ranged category')
 assert(not Rules.matches(weaponBox,toy) and Rules.matches(weaponBox,weapon), 'weapon box accepted a cap gun')
 assert(Rules.matches(toyBox,record('ammunitionRanged','Base.CapGunCap')), 'toy box rejected caps')
 local matcher=Rules.matcher()
 assert(matcher(toyBox,toy) and not matcher(weaponBox,toy), 'planned routing disagreed with direct toy routing')
end
do
    local ordinary={cats={},rules={{mode='all',include={'container'},exclude={'wearable'}}}}
    local bag=record('Container','Mod.Backpack')
    local case=record('Container','Mod.Case')
    for _,value in ipairs({bag,case}) do
        value.ref.IsInventoryContainer=function() return true end
        value.ref.getBodyLocation=function() return nil end
    end
    bag.ref.canBeEquipped=function() return 'Back' end
    case.ref.canBeEquipped=function() return nil end
    assert(not Rules.matches(ordinary,bag) and Rules.matches(ordinary,case),
        'Container excluding Wearable did not distinguish bags from hand-carried cases')
    local matcher=Rules.matcher()
    assert(not matcher(ordinary,bag) and matcher(ordinary,case),'planned container exclusion differed')
end
do
    local readingBox={cats={},rules={{mode='all',include={'readable'},exclude={}}}}
    local note=record('literatureWriteable','Base.Notebook')
    note.ref.IsLiterature=function() return true end
    note.ref.canBeWrite=function() return true end
    note.ref.isEmptyPages=function(self) return not self.written end
    assert(not Rules.matches(readingBox,note),'sorter accepted blank paper as readable')
    note.ref.written=true
    assert(Rules.matches(readingBox,note),'sorter rejected a written note')
    local matcher=Rules.matcher()
    assert(matcher(readingBox,note),'planner rejected a written note')
    note.ref.written=false
    assert(not Rules.matcher()(readingBox,note),'a new plan retained previously written content')
end
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
assert(object.md[Rules.FIELD]['0'].include[1]=='food' and not object.md.LSBox,
    'rule-only save created category anchors')
assert(LootSorter.modDataHasDesignation(object.md), 'rule-only box lost designation')
local box = target()
assert(Rules.matches(box,record('Food')) and not Rules.matches(box,record('foodPerishable'))
    and not Rules.matches(box,record('Electronics')), 'direct sorter did not resolve rule')
assert(next(box.cats)==nil, 'tag rule expanded into legacy categories')
local boxes = LootSorter.gatherBoxes(player)
assert(#boxes == 1 and Rules.matches(boxes[1],record('Food')) and boxes[1].container == container,
    'private gather missed rule-only box')
boxes = LootSorter.gatherBoxesOrWarn(player)
assert(#boxes == 1 and Rules.matches(boxes[1],record('Food')), 'sorter gather missed rule-only box')
local Presets = require 'PZSurvivorToolkit/QuartermasterPresets'
mode='client'; LootSorter._receivedRegistry=moddata.LootSorter_Registry
assert(Presets.receive({schema=1,revision=0,presets=presets(),rules={}}))
safe=false
boxes=LootSorter.gatherBoxes(player)
assert(#boxes==0 and not object.md.LSBox, 'rule lookup touched forbidden safehouse before permission gate')
safe=true; boxes=LootSorter.gatherBoxes(player)
assert(#boxes==1 and Rules.matches(boxes[1],record('Food')), 'allowed Host gather lost rule-only box')
LootSorter._manifestWin={playerNum=0}
LootSorter.getRegistry()
boxes=LootSorter.findDesignatedOnSquare(square)
assert(#boxes==1 and Rules.matches(boxes[1],record('Food')), 'public lookup lost rule-only box outside gather')
safe=false
boxes=LootSorter.findDesignatedOnSquare(square)
assert(#boxes==0 and not object.md.LSBox, 'public lookup bypassed safehouse permission')
safe=true; mode='sp'
local originalProps=farming_vegetableconf
farming_vegetableconf={props={Sunflower={seedName='Base.SunflowerSeeds'}}}
local seedOnly={mode='all',include={'food','seed'},exclude={}}
assert(Rules.applyBox(player,args(seedOnly))=='ok')
boxes=LootSorter.gatherBoxes(player)
assert(#boxes==1 and boxes[1].container==container,
    'private gather dropped an item-only food+seed rule with no manual designation')
local itemRecord=record('Food','Base.SunflowerSeeds')
itemRecord.name,itemRecord.weight='Sunflower seeds',1
local plannedBox={cats=boxes[1].cats,items=boxes[1].items,rules=boxes[1].rules,capacity=10,used=0}
local plan=LootSorter.planTrips({itemRecord},{plannedBox},{{ref={},space=10,factor=1}},10,nil,Rules.matches)
assert(#plan.trips==1 and plan.trips[1].perBox[plannedBox][1].item==itemRecord and #plan.leftover==0,
    'planner did not receive/match item-only food+seed target')
assert(not object.md.LSBox,'rule-only gather persisted category anchors')
enabled=false;boxes=LootSorter.gatherBoxes(player)
assert(#boxes==0,'disabled tags retained item-only rule target without manual designation')
enabled=true;farming_vegetableconf=originalProps
assert(Rules.applyBox(player,args(rule))=='ok')
object.md.LSBox={['0']={foodPerishable=true, PreciseModCategory=true}}
box=target()
assert(Rules.matches(box,record('foodPerishable')) and Rules.matches(box,record('PreciseModCategory')),
    'rule exclusions stripped manual picks')
local schema=require 'PZSurvivorToolkit/ItemTagSchema'
schema.categories.FutureFood={'food'}; categories[#categories+1]='FutureFood'
box=target(); assert(Rules.matches(box,record('FutureFood')), 'saved rule froze current categories')
enabled=false; box=target()
assert(not Rules.matches(box,record('FutureFood')) and Rules.matches(box,record('PreciseModCategory')))
enabled=true
object.md.LSBox['0']=nil
box=target(); assert(Rules.matches(box,record('FutureFood')), 'rule required a manual category anchor')
assert(Rules.applyBox(player,args({mode='all',include={},exclude={}}))=='ok')
box=target(); assert(not Rules.matches(box,record('FutureFood')), 'cleared rule stayed in routing')
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
assert(Rules.getPreset('Pantry',presets().Pantry))
local Storage = require 'PZSurvivorToolkit/QuartermasterPresetStorage'
local saved = Storage.load()
assert(saved.generation > 0 and saved.native.Pantry.cats.Precise
    and saved.rules.Pantry.gen == saved.native.Pantry.gen and saved.rules.Pantry.cats.food,
    'native selection and linked tag rule did not commit in one snapshot')
local legacyNative, legacyRules = disk['QuartermasterPresets.txt'], disk['PZSTQuartermasterTagRules.txt']
require('PZSurvivorToolkit/QuartermasterPresets').load()
assert(Rules.getPreset('Pantry',presets().Pantry).exclude[1]=='perishable','SP rules did not survive snapshot roundtrip')
local anyRule={mode='any',include={'food','electrical'},exclude={'perishable'}}
assert(put(player,{name='Either',cats={},items={},pzstTagRule=anyRule})=='ok')
require('PZSurvivorToolkit/QuartermasterPresets').load()
assert(Rules.getPreset('Either',presets().Either).mode=='any', 'SP any-rule mode was lost in snapshot')
local either={cats={},rules=Rules.forBox(nil,0,{Either=presets().Either.gen},presets())}
assert(Rules.matches(either,record('Food')) and Rules.matches(either,record('Electronics'))
    and not Rules.matches(either,record('foodPerishable')), 'saved any+excluded rule changed semantics')
local rev=presets().Pantry.rev
assert(put(player,{name='Pantry',expectExisting=true,baseRev=0,cats={},items={},pzstTagRule={mode='any',include={'electrical'},exclude={}}})=='stale')
assert(presets().Pantry.rev==rev and Rules.getPreset('Pantry',presets().Pantry).include[1]=='food')
local effective,items=LootSorter.resolveEffective({Manual=true},{ManualItem=true},{Pantry=presets().Pantry.gen},presets())
local effectiveBox={cats=effective,rules=Rules.forBox(nil,0,{Pantry=presets().Pantry.gen},presets())}
assert(Rules.matches(effectiveBox,record('FutureFood')) and effective.Manual and effective.Precise
    and items.Beans and items.ManualItem and not effective.FutureFood)
presets().Pantry.gen=presets().Pantry.gen+1
assert(not Rules.getPreset('Pantry',presets().Pantry), 'deleted/remade preset inherited prior rule')
assert(LootSorter.serverFns.removePreset(player,{name='Pantry'})=='ok' and not Rules.presetStore().Pantry)
saved = Storage.load()
assert(not saved.native.Pantry and not saved.rules.Pantry and saved.native.Either and saved.rules.Either,
    'native removal and tag-rule cleanup were not committed together')
assert(disk['QuartermasterPresets.txt'] == legacyNative and disk['PZSTQuartermasterTagRules.txt'] == legacyRules,
    'snapshot writes changed legacy files')
do
    local value = {cats = {Precise = 'truthy', Ignored = false}, items = {Beans = true},
        presets = {Bound = 41}, priority = '7', pzstTagRule = rule}
    local snapshot = LootSorter.snapshotDesignation(value)
    assert(snapshot.cats.Precise == 'truthy' and not snapshot.cats.Ignored and snapshot.presets.Bound == 41
        and snapshot.priority == 7 and LootSorter.snapshotDesignation({priority = 'invalid'}).priority == 0,
        'designation snapshot lost truthy values, generations or numeric priority')
    snapshot.cats.Precise, snapshot.items.Beans, snapshot.presets.Bound = nil, nil, 42
    snapshot.pzstTagRule.include[1], snapshot.pzstTagRule.exclude[1] = 'electrical', 'meat'
    assert(value.cats.Precise == 'truthy' and value.items.Beans and value.presets.Bound == 41
        and rule.include[1] == 'food' and rule.exclude[1] == 'perishable', 'snapshot aliased source sets or nested rule')
    local originalData, originalTransmit = object.md, object.transmitModData
    local originalAdd, originalRemove = LootSorter.addCoord, LootSorter.removeCoords
    local publications, coordUpdates = 0, 0
    object.md = {LSBox = {['0'] = {Old = true}, ['1'] = {OtherContainer = true}},
        LSBoxItems = {['0'] = {OldItem = true}}, LSBoxPresets = {['0'] = {OldPreset = true}},
        LSBoxPriority = {['0'] = 99}, [Rules.FIELD] = {['0'] = rule}, [Rules.REVISIONS] = {['0'] = 17}}
    LootSorter.addCoord = function() coordUpdates = coordUpdates + 1 end
    LootSorter.removeCoords = LootSorter.addCoord
    object.transmitModData = function(self)
        publications = publications + 1
        assert(self.md[Rules.FIELD]['0'] == rule and self.md[Rules.REVISIONS]['0'] == 17,
            'native publication rewrote rule data or revision outside authority')
        if publications == 1 then
            assert(self.md.LSBox['0'].Precise == 'truthy' and not self.md.LSBox['0'].Old
                and self.md.LSBoxItems['0'].Beans and not self.md.LSBoxItems['0'].OldItem
                and self.md.LSBoxPresets['0'].Bound == 41 and not self.md.LSBoxPresets['0'].OldPreset
                and self.md.LSBoxPriority['0'] == 7, 'publication exposed a partial native designation')
        else
            assert(not self.md.LSBox['0'] and not self.md.LSBoxItems['0'] and not self.md.LSBoxPresets['0']
                and not self.md.LSBoxPriority['0'], 'empty complete designation did not clear every native field')
        end
    end
    LootSorter.setBoxDesignation(object, 0, value)
    assert(publications == 1 and coordUpdates == 1 and object.md.LSBox['1'].OtherContainer,
        'complete designation published more than once or changed another container')
    object.md.LSBox['0'].Precise, object.md.LSBoxPresets['0'].Bound = nil, 42
    assert(value.cats.Precise == 'truthy' and value.presets.Bound == 41, 'complete designation retained input tables')
    LootSorter.setBoxDesignation(object, 0, {})
    assert(publications == 2 and coordUpdates == 2, 'empty designation did not publish once')
    object.md, object.transmitModData = originalData, originalTransmit
    LootSorter.addCoord, LootSorter.removeCoords = originalAdd, originalRemove
end
do
    local originalData, originalClipboard, originalAdd = object.md, LootSorter.clipboard, LootSorter.addCoord
    LootSorter.addCoord = function() end
    object.md = {LSBoxPresets = {['0'] = {GenerationBound = 41}}}
    local copied = LootSorter.copyDesignation(object, 0)
    assert(copied.presets.GenerationBound == 41, 'copy discarded the numeric preset generation')
    object.md = {}
    assert(LootSorter.pasteDesignation(object, 0))
    assert(object.md.LSBoxPresets['0'].GenerationBound == 41, 'paste discarded the numeric preset generation')
    assert(not LootSorter.linkResolves({gen = 42}, object.md.LSBoxPresets['0'].GenerationBound),
        'pasted designation resolved a deleted and recreated preset')
    object.md, LootSorter.clipboard, LootSorter.addCoord = originalData, originalClipboard, originalAdd
end
-- Client commands carry the selected authenticated player; failures and timeouts leave caller in control.
mode='client'; local sent, callback
-- A fresh client process installs the shared transport's client sweep.
dofile(root .. 'shared/LootSorter_Rpc.lua')
sendClientCommand=function(authenticated,module,command,packet)
    assert(authenticated==player and module=='Quartermaster' and command=='saveBox'); sent=packet
end
local function reply(verdict, revision)
    for _, fn in ipairs(Events.OnServerCommand.handlers) do
        fn('Quartermaster','rpcResult',{rpcToken=sent.rpcToken,verdict=verdict,detail={revision=revision}})
    end
end
Rules.saveBox(object,0,rule,player,function(verdict) callback=verdict end)
assert(sent and callback==nil)
reply('denied')
assert(callback=='denied')
object.md[Rules.FIELD] = nil
callback=nil
Rules.saveBox(object,0,rule,player,function(verdict)
    callback=verdict
    assert(Rules.getBox(object,0), 'native save could transmit before accepted server rule reached object ModData')
end)
reply('ok',sent.baseRevision+1)
assert(callback=='ok' and Rules.getBox(object,0).include[1]=='food')
callback=nil
object.md[Rules.REVISIONS]['0']=7
Rules.saveBox(object,0,rule,player,function(verdict) callback=verdict end)
object.md[Rules.REVISIONS]['0']=9
object.md[Rules.FIELD]['0']={mode='all',include={'electrical'},exclude={}}
reply('ok',8)
assert(callback=='stale' and Rules.getBoxRevision(object,0)==9 and Rules.getBox(object,0).include[1]=='electrical',
    'older successful reply overwrote newer observed object rule/revision')
for _, malformed in ipairs({'10', 10.5, math.huge, 0/0, false}) do
    callback=nil
    Rules.saveBox(object,0,rule,player,function(verdict) callback=verdict end)
    reply('ok',malformed)
    assert(callback=='invalid' and Rules.getBoxRevision(object,0)==9, 'malformed reply revision was accepted')
end
callback=nil; Rules.saveBox(object,0,rule,player,function(verdict) callback=verdict end)
clock=clock+16000; for _,fn in ipairs(Events.OnTick.handlers) do fn() end
assert(callback=='timeout')
do
    -- Exercise actual client acknowledgement ordering, not a replacement saveBox callback.
    local originalData, originalClipboard, originalTransmit = object.md, LootSorter.clipboard, object.transmitModData
    local originalAdd, originalRemove, originalNotify = LootSorter.addCoord, LootSorter.removeCoords, LootSorter.notify
    local publications, added, removed, notified = 0, 0, 0, 0
    local appearance = {name = 'Existing', icon = {kind = 'item', value = 'Base.Axe'}, color = {r = 1, g = 0, b = 0}}
    LootSorter.addCoord = function() added = added + 1 end
    LootSorter.removeCoords = function() removed = removed + 1 end
    LootSorter.notify = function() notified = notified + 1 end
    local function baseline()
        object.md = {LSBox = {['0'] = {Original = true}, ['1'] = {OtherContainer = true}}, LSBoxItems = {['0'] = {OriginalItem = true}},
            LSBoxPresets = {['0'] = {OriginalPreset = 12}}, LSBoxPriority = {['0'] = 8},
            [Rules.FIELD] = {['0'] = {mode = 'all', include = {'electrical'}, exclude = {}}},
            [Rules.REVISIONS] = {['0'] = 1}, BetterContainers = {customize = {_global = appearance}},
            crate_customContainerName = 'Existing', unrelated = 'untouched'}
    end
    local function respond(verdict)
        reply(verdict, sent.baseRevision+1)
    end
    object.transmitModData = function(self)
        publications = publications + 1
    end
    baseline()
    LootSorter.clipboard = {cats = {ClipboardA = true}, items = {ItemA = true}, presets = {Pantry = 41},
        priority = 3, pzstTagRule = {mode = 'all', include = {'food'}, exclude = {'perishable'}}}
    local clipboardA = LootSorter.clipboard
    assert(LootSorter.pasteDesignation(object, 0) and publications == 0 and object.md.LSBox['0'].Original,
        'paste wrote native selections before authority accepted its configuration')
    assert(sent.baseRevision == 1 and sent.configuration and sent.configuration.cats.ClipboardA and sent.configuration.items.ItemA
        and sent.configuration.presets.Pantry == 41 and sent.configuration.priority == 3
        and sent.rule.include[1] == 'food' and sent.configuration.appearance == nil,
        'paste did not submit the complete sorting-only configuration with its captured revision')
    clipboardA.cats.ClipboardA, clipboardA.items.ItemA, clipboardA.presets.Pantry = nil, nil, 42
    clipboardA.pzstTagRule.include[1], clipboardA.pzstTagRule.exclude[1] = 'electrical', 'meat'
    local expectedClipboard = {cats = {ClipboardB = true}, items = {ItemB = true}, presets = {}, priority = 9}
    LootSorter.clipboard = expectedClipboard
    object.md.unrelated = 'changed while pending'
    respond('ok')
    assert(Rules.getBoxRevision(object, 0) == 2 and Rules.getBox(object, 0).include[1] == 'food'
        and object.md.LSBox['0'].ClipboardA and not object.md.LSBox['0'].Original and object.md.LSBoxItems['0'].ItemA
        and object.md.LSBoxPresets['0'].Pantry == 41 and object.md.LSBoxPriority['0'] == 3,
        'accepted paste did not mirror every sorting layer from its detached snapshot')
    assert(publications == 0 and added == 0 and removed == 0 and LootSorter.clipboard == expectedClipboard,
        'accepted paste republished client data or changed the current clipboard')
    assert(object.md.LSBox['1'].OtherContainer and object.md.unrelated == 'changed while pending'
        and object.md.crate_customContainerName == 'Existing' and object.md.BetterContainers.customize._global == appearance
        and appearance.name == 'Existing' and appearance.icon.value == 'Base.Axe' and appearance.color.r == 1,
        'sorting-only paste changed another compartment, live data or existing name/icon/color')

    local copied = LootSorter.copyDesignation(object, 0)
    object.md.LSBox['0'].ClipboardA, object.md.LSBoxItems['0'].ItemA, object.md.LSBoxPresets['0'].Pantry = nil, nil, 42
    object.md[Rules.FIELD]['0'].include[1], object.md[Rules.FIELD]['0'].exclude[1] = 'electrical', 'meat'
    assert(copied.cats.ClipboardA and copied.items.ItemA and copied.presets.Pantry == 41
        and copied.pzstTagRule.include[1] == 'food' and copied.pzstTagRule.exclude[1] == 'perishable',
        'copy aliased source native sets or nested rule')
    copied.cats.ClipboardA, copied.pzstTagRule.include[1] = 'changed', 'seed'
    assert(not object.md.LSBox['0'].ClipboardA and object.md[Rules.FIELD]['0'].include[1] == 'electrical',
        'clipboard edits mutated source designation')

    for _, verdict in ipairs({'denied', 'stale', 'timeout'}) do
        baseline()
        LootSorter.clipboard = {cats = {Refused = true}, items = {}, presets = {}, priority = 99, pzstTagRule = rule}
        LootSorter.pasteDesignation(object, 0)
        if verdict == 'timeout' then
            clock = clock + 16000
            for _, fn in ipairs(Events.OnTick.handlers) do fn() end
        else respond(verdict) end
        assert(publications == 0 and added == 0 and removed == 0 and object.md.LSBox['0'].Original
            and not object.md.LSBox['0'].Refused and object.md.LSBoxItems['0'].OriginalItem
            and object.md.LSBoxPresets['0'].OriginalPreset == 12 and object.md.LSBoxPriority['0'] == 8
            and Rules.getBoxRevision(object, 0) == 1 and Rules.getBox(object, 0).include[1] == 'electrical',
            'paste ' .. verdict .. ' changed native or rule state')
    end
    assert(notified == 3, 'refused or timed out paste did not report failure')
    object.md = {[Rules.FIELD] = {['0'] = rule}}
    LootSorter.copyDesignation(object, 0)
    assert(LootSorter.hasClipboardContent() and LootSorter.describeClipboard() == 'UI_PZST_QMTagRule',
        'rule-only clipboard was hidden or described as empty')
    baseline()
    expectedClipboard = {}
    LootSorter.clipboard = expectedClipboard
    assert(not LootSorter.hasClipboardContent() and LootSorter.describeClipboard() == 'empty')
    assert(LootSorter.pasteDesignation(object, 0) and publications == 0 and sent.configuration,
        'empty paste skipped authoritative configuration clear')
    respond('ok')
    assert(not Rules.getBox(object, 0) and not object.md.LSBox['0'] and not object.md.LSBoxItems['0']
        and not object.md.LSBoxPresets['0'] and not object.md.LSBoxPriority['0'] and Rules.getBoxRevision(object, 0) == 2,
        'empty paste did not clear every sorting layer through authority')
    baseline()
    object.md[Rules.FIELD] = nil
    LootSorter.clipboard = {cats = {NativeOnly = true}, presets = {GenerationBound = 41}}
    assert(LootSorter.pasteDesignation(object, 0) and sent.baseRevision == 1 and sent.configuration.cats.NativeOnly
        and object.md.LSBox['0'].Original and not Tags.ruleActive(sent.rule),
        'native-only paste bypassed authority or failed to send an empty rule')
    respond('ok')
    assert(object.md.LSBox['0'].NativeOnly and object.md.LSBoxPresets['0'].GenerationBound == 41
        and not Rules.getBox(object, 0) and Rules.getBoxRevision(object, 0) == 2,
        'native-only paste did not mirror the authoritative replacement')
    assert(publications == 0 and added == 0 and removed == 0, 'paste performed a second client publication or index update')
    LootSorter.clipboard = nil
    assert(not LootSorter.pasteDesignation(object, 0) and LootSorter.describeClipboard() == nil)
    object.md, LootSorter.clipboard, object.transmitModData = originalData, originalClipboard, originalTransmit
    LootSorter.addCoord, LootSorter.removeCoords, LootSorter.notify = originalAdd, originalRemove, originalNotify
end
do
    local previousProvider = OrganizedCategories
    local previousGather, previousNotify = LootSorter.gatherBoxesOrWarn, LootSorter.notify
    local item = {category = 'Material', getDisplayCategory = function(self) return self.category end}
    local source = {getItems = function() return list({item}) end, isInCharacterInventory = function() return true end}
    local gathered = false
    OrganizedCategories = {applyItemDisplayOverride = function(current)
        assert(current == item, 'sort replaced the original inventory item')
        current.category = 'craftingTailoring_material'
    end}
    LootSorter.gatherBoxesOrWarn = function()
        gathered = true
        assert(item.category == 'craftingTailoring_material', 'owned sort did not prepare its raw source before planning')
        return {}
    end
    LootSorter.notify = function() end
    LootSorter.sort(source, 0)
    assert(gathered and item.category == 'craftingTailoring_material', 'owned sort required an external preparation wrapper')
    OrganizedCategories = previousProvider
    LootSorter.gatherBoxesOrWarn, LootSorter.notify = previousGather, previousNotify
end
do
    local previousGather, previousNotify, previousPlanner = LootSorter.gatherBoxesOrWarn, LootSorter.notify, LootSorter.planTrips
    local previousDebug, previousLog, previousFill = LootSorter.isDebug, LootSorter.DBG, LootSorter.BOX_FILL_FRACTION
    local previousFinder = AdjacentFreeTileFinder
    local debug, capacityReads, weightReads, plans, boxLogs = false, 0, 0, 0, {}
    local destination = {
        getEffectiveCapacity = function(_, character)
            assert(character == player)
            capacityReads = capacityReads + 1
            return 10
        end,
        getCapacityWeight = function() weightReads = weightReads + 1; return 2 end,
    }
    local source = {getItems = function() return list({}) end, isInCharacterInventory = function() return true end}
    LootSorter.gatherBoxesOrWarn = function()
        return {{square = square, container = destination, cats = {Food = true}, items = {Apple = true}, dist = 1}}
    end
    LootSorter.notify = function() end
    LootSorter.isDebug = function() return debug end
    LootSorter.DBG = function(message)
        assert(not message:find('SORT ERROR:', 1, true), message)
        if debug and message:find('box[', 1, true) == 1 then boxLogs[#boxLogs + 1] = message end
    end
    LootSorter.BOX_FILL_FRACTION = 0.9
    AdjacentFreeTileFinder = {Find = function(sq, character)
        assert(sq == square and character == player)
        return current
    end}
    LootSorter.planTrips = function(items, gathered, ...)
        plans = plans + 1
        assert(#gathered == 1 and gathered[1].capacity == 9 and gathered[1].used == 2,
            'lazy diagnostics changed the actual capacity snapshot passed to the planner')
        return previousPlanner(items, gathered, ...)
    end
    LootSorter.sort(source, 0)
    assert(plans == 1 and capacityReads == 1 and weightReads == 1 and #boxLogs == 0,
        'release sort performed capacity reads for silent box diagnostics')
    debug = true
    capacityReads, weightReads = 0, 0
    LootSorter.sort(source, 0)
    assert(plans == 2 and capacityReads == 2 and weightReads == 2 and #boxLogs == 1,
        'debug sort lost its box diagnostics or the required planner snapshot')
    assert(boxLogs[1] == 'box[1] cap=10 used=2.0 dist=1 cats=[Food ] items=[Apple ]',
        'lazy diagnostics changed the debug box output')
    LootSorter.gatherBoxesOrWarn, LootSorter.notify, LootSorter.planTrips = previousGather, previousNotify, previousPlanner
    LootSorter.isDebug, LootSorter.DBG, LootSorter.BOX_FILL_FRACTION = previousDebug, previousLog, previousFill
    AdjacentFreeTileFinder = previousFinder
end
print('Quartermaster rules passed: direct item matching/discovery, exact picks, opt-out, clearing, authority, SP persistence, preset conflicts, client refusal/timeout and owned sort preparation.')
