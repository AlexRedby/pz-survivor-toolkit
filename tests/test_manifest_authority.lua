local shared = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/'
local server = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/server/'
local clock, reads = 1000, 0
local data, squares = {}, {}
PZSurvivorToolkit, LootSorter = {}, {RPC_TIMEOUT_MS=15000,RPC_SWEEP_MS=5000,DBG=function()end}
isClient, isServer = function()return false end, function()return true end
getTimestampMs = function()return clock end
getSpecificPlayer = function()return {} end
Events = {}
for _, name in ipairs({'OnClientCommand','OnServerCommand','OnGameStart','OnTick'}) do
    Events[name] = {Add=function()end,Remove=function()end}
end
ModData = {getOrCreate=function(key) data[key]=data[key] or {}; return data[key] end}
getCell = function()return {getGridSquare=function(_,x,y,z)return squares[x..','..y..','..z]end}end
local presets = {}
local Tags = {enabled=function()return true end,normalizeRule=function(rule)return rule end,
    ruleActive=function(rule)return rule and #rule.include>0 end}
local cached = {}
require = function(name)
    if cached[name] then return cached[name] end
    local module
    if name=='PZSurvivorToolkit/ItemTags' then module=Tags
    elseif name=='PZSurvivorToolkit/QuartermasterPresets' then
        module={native=function()return presets end,rules=function()return {}end}
    elseif name=='PZSurvivorToolkit/ContainerAppearance' then
        module={read=function(obj,ci)return obj.appearance or {}end}
    else
        local path = name=='PZSurvivorToolkit/ManifestAuthority' and server or shared
        module=dofile(path..name..'.lua')
    end
    cached[name]=module or true
    return module
end
local Authority=require 'PZSurvivorToolkit/ManifestAuthority'
local Model=require 'PZSurvivorToolkit/ManifestModel'
local function list(values, counted)
    return {values=values,size=function(self)return #self.values end,get=function(self,index)
        if counted then reads=reads+1 end
        return self.values[index+1]
    end}
end
local function item(ft, label, custom)
    return {getFullType=function()return ft end,getDisplayName=function()return label end,
        getName=function()return label end,isCustomName=function()return custom end,
        getDisplayCategory=function()return 'Food' end}
end
local function container(values)
    local items=list(values,true)
    return {getItems=function()return items end,getType=function()return 'crate' end},items
end
local function object(containers,md)
    return {hasModData=function()return true end,getModData=function()return md end,
        getContainerCount=function()return #containers end,
        getContainerByIndex=function(_,ci)return containers[ci+1]end}
end
local function square(x,objects)
    local sq={getX=function()return x end,getY=function()return 0 end,getZ=function()return 0 end,
        getObjects=function()return list(objects)end}
    squares[x..',0,0']=sq
    data.LootSorter_Registry=data.LootSorter_Registry or {}
    data.LootSorter_Registry.boxes=data.LootSorter_Registry.boxes or {}
    data.LootSorter_Registry.boxes[x..',0,0']=true
    return sq
end
local function step(items,nodes)
    local before=reads
    local used,count=Authority.step(items or 7,nodes or 30)
    assert(reads-before <= (items or 7),'single tick read beyond item budget')
    assert(count <= (nodes or 30),'single tick exceeded world node budget')
    return used
end
local function settle(n)
    for i=1,n or 100 do clock=clock+50; step() end
end
-- Legacy coordinate data stays available while unloaded, even if registry entries disappeared.
data.LootSorter_Manifest={boxes={['99,0,0']={['Old translated label']={ft='Base.A',n=8,cat='Food'}},
    ['1,0,0']={['Legacy crate contents']={ft='Base.A',n=2}}}}
settle(10)
local store=Authority.getStore()
assert(store.schema==2 and not store.boxes and store.containers['legacy:99,0,0'])
local legacy=store.containers['legacy:99,0,0']
assert(legacy.entries[Model.identity('Base.A','Old translated label','Food')].n==8)
assert(legacy.legacy and not legacy.loaded and legacy.sampledAt==0)
-- Stable identity separates types with identical labels, preserves custom names, ignores locale.
assert(Model.item(item('Base.A','Translated A')).key==Model.item(item('Base.A','Other locale')).key)
assert(Model.item(item('Base.A','Same')).key~=Model.item(item('Base.B','Same')).key)
assert(Model.item(item('Base.A','Renamed',true)).name=='Renamed')
assert(Model.item(item('Base.A','Renamed',true)).key~=Model.item(item('Base.A','Same')).key)
-- Multicontainer, presets (including generation), and tag-only designations share real resolver.
local many={}
for i=1,220 do many[i]=item('Base.T'..i,'Same label') end
local c1,items=container(many)
local mediaTape=item('Base.VHS_Home','Local tape title')
mediaTape.getRecordedMediaIndex=function()return 22 end
mediaTape.getMediaData=function()return {getId=function()return 'home:22'end}end
local c2=container({item('Base.A','Named tool',true),item('Base.B','Same label'),mediaTape})
local c3=container({item('Base.Hidden','Hidden')})
presets.Pantry={gen=2,cats={Food=true},items={}}
local obj=object({c1,c2,c3},{LSBoxPresets={['0']={Pantry=2},['2']={Pantry=1}},
    PZSTQuartermasterTagRules={['1']={include={'tool'},exclude={}}}})
obj.appearance={name='Pantry',icon={kind='item',value='Base.A'},color={r=1,g=0,b=0,a=1}}
square(1,{obj})
Authority.resetRuntime()
for i=1,15 do step(7,30) end
assert(store.containers['legacy:1,0,0'],'partial huge-container scan erased legacy data')
assert(not store.containers['1,0,0/0/0'],'huge container published partial counts')
for i=1,500 do
    if store.containers['1,0,0/0/0'] then break end
    step(1,1)
end
assert(store.containers['1,0,0/0/0'] and store.containers['legacy:1,0,0'])
local oldRows=Model.PAGE_ROWS
Model.PAGE_ROWS=1
local transitionPlayer={}
local _,transition=Authority.requestPage(transitionPlayer,{})
local legacySent,modernSent=false,false
local function observeTransition(part)
    for _,record in ipairs(part.containers)do
        if record.key=='1,0,0' then
            if record.legacy then legacySent=true else modernSent=true end
        end
    end
end
observeTransition(transition)
settle(150)
while transition.cursor do
    local status
    status,transition=Authority.requestPage(transitionPlayer,{cursor=transition.cursor})
    assert(status=='ok')
    observeTransition(transition)
end
assert(not (legacySent and modernSent),'revisit mixed legacy and replacement samples in one stream')
Model.PAGE_ROWS=oldRows
local first=store.containers['1,0,0/0/0']
assert(first and #first.itemOrder==220 and first.name=='Pantry' and first.icon.value=='Base.A')
assert(first.loaded and first.sampledAt>0 and not store.containers['legacy:1,0,0'])
assert(store.containers['1,0,0/0/1'] and not store.containers['1,0,0/0/2'])
-- RPC never reads inventory, validates authenticated player/cursor, bounds even one huge container.
local player,other={},{}
assert(Authority.requestPage(nil,{})=='invalid')
assert(Authority.requestPage(player,{cursor=999999})=='stale')
local before=reads
local verdict,page=Authority.requestPage(player,{})
assert(verdict=='ok' and page.cursor and reads==before)
assert(Authority.requestPage(other,{cursor=page.cursor})=='stale','cursor was usable by another player')
local seen,total,mediaPassed={},0,false
while page do
    local n=0
    for _,record in ipairs(page.containers) do
        for key,entry in pairs(record.entries) do
            n=n+1
            if entry.mediaId=='home:22' then
                assert(entry.mediaIndex==22 and not entry.name)
                mediaPassed=true
            end
            local id=record.id..':'..key
            assert(not seen[id],'duplicate entry across pages')
            seen[id]=true; total=total+entry.n
        end
    end
    assert(n<=Model.PAGE_ROWS and #page.containers<=Model.PAGE_CONTAINERS)
    if page.cursor then verdict,page=Authority.requestPage(player,{cursor=page.cursor});assert(verdict=='ok')
    else page=nil end
end
assert(total==231 and mediaPassed,'paged ledger lost container/legacy/media records')
assert(Authority.requestPage(player,{revision=store.revision})=='ok')
local _,unchanged=Authority.requestPage(player,{revision=store.revision})
assert(unchanged.unchanged and not unchanged.containers)
-- Rechecking unchanged contents advances real sample time without changing the data revision.
local revision = store.revision
local sampled = store.containers[first.id]
settle(150)
assert(store.revision == revision, 'unchanged sampling invalidated the data revision')
local resampled = store.containers[first.id]
assert(resampled ~= sampled and resampled.sampledAt > sampled.sampledAt, 'authority must replace immutable samples')
assert(resampled.entries == sampled.entries and resampled.itemOrder == sampled.itemOrder,
    'equal samples should reuse the immutable contents and original ordering')
-- Iterator order is not a change in inventory data.
items.values[1],items.values[2] = items.values[2],items.values[1]
settle(150)
assert(store.revision == revision, 'inventory iteration order changed the data revision')
items.values[1],items.values[2] = items.values[2],items.values[1]
settle(150)
assert(store.revision == revision)
-- A group can temporarily equal the old count and then exceed it within the same sample.
local secondItems = c2:getItems().values
local secondKey = Model.identity('Base.A','Named tool','Food')
secondItems[#secondItems+1] = secondItems[1]
settle(150)
assert(store.revision > revision and store.containers['1,0,0/0/1'].entries[secondKey].n == 2,
    'temporary count match hid a later duplicate item')
assert(store.containers['1,0,0/0/0'].entries == resampled.entries, 'unrelated contents were rebuilt')
secondItems[#secondItems] = nil
settle(150)
assert(store.containers['1,0,0/0/1'].entries[secondKey].n == 1, 'decreased count was not published')
revision = store.revision
-- Freshness traverses bounded container pages, carries no items and uses authenticated cursors.
local oldContainers = Model.PAGE_CONTAINERS
Model.PAGE_CONTAINERS = 1
local freshPlayer, freshness = {}, {}
local _, fresh = Authority.requestPage(freshPlayer, {revision=revision})
local pages = 0
while fresh do
    assert(fresh.unchanged and fresh.revision == revision and not fresh.containers, 'idle poll resent items')
    local count = 0
    for id, timestamp in pairs(fresh.samples) do
        count = count + 1
        assert(not freshness[id] and timestamp == store.containers[id].sampledAt)
        freshness[id] = timestamp
    end
    assert(count <= Model.PAGE_CONTAINERS, 'freshness exceeded its container budget')
    pages = pages + 1
    if fresh.cursor then
        assert(Authority.requestPage(other,{cursor=fresh.cursor}) == 'stale')
        _,fresh = Authority.requestPage(freshPlayer,{cursor=fresh.cursor})
    else fresh=nil end
end
assert(pages == 3 and freshness[first.id] and freshness['legacy:99,0,0'] == 0)
-- A metadata mutation invalidates an in-flight freshness stream, never dates stale counts.
local _, interrupted = Authority.requestPage(freshPlayer, {revision=revision})
assert(interrupted.cursor)
obj.appearance.name = 'Renamed pantry'
settle(150)
assert(store.revision > revision and store.containers[first.id].name == 'Renamed pantry')
assert(Authority.requestPage(freshPlayer,{cursor=interrupted.cursor}) == 'stale')
assert(sampled.name == 'Pantry', 'published sample was changed in place')
obj.appearance.name = 'Pantry'
settle(150)
Model.PAGE_CONTAINERS = oldContainers
-- Full item pages keep one immutable sample through subsequent unchanged resampling.
Model.PAGE_ROWS = 1
local pinnedPlayer, pinned = {}, nil
local _, part = Authority.requestPage(pinnedPlayer,{})
while part do
    for _, record in ipairs(part.containers) do if record.id == first.id then pinned = record end end
    if pinned then break end
    _,part = Authority.requestPage(pinnedPlayer,{cursor=assert(part.cursor)})
end
assert(pinned and part.cursor)
settle(150)
local _, continuation = Authority.requestPage(pinnedPlayer,{cursor=part.cursor})
assert(continuation.containers[1].id == first.id and continuation.containers[1].sampledAt == pinned.sampledAt,
    'full pagination changed its pinned sample after a freshness update')
Model.PAGE_ROWS = oldRows
-- Any loaded mutation (consumption/replacement, not just transfer hooks) eventually reconciles.
items.values[1]=item('Base.Replacement','Other')
settle(150)
assert(store.containers[first.id].entries[Model.identity('Base.Replacement',nil,'Food')])
assert(not store.containers[first.id].entries[Model.identity('Base.T1',nil,'Food')])
-- Disappearing chunk retains the full sample and records its stale loaded state.
squares['1,0,0']=nil
settle(10)
assert(store.containers[first.id] and not store.containers[first.id].loaded)
assert(store.containers[first.id].entries[Model.identity('Base.Replacement',nil,'Food')])
-- Removing a designation is proved only after the tile loads again; unrelated legacy survives.
square(1,{object({c1},{})})
settle(30)
assert(not store.containers[first.id] and not store.containers['1,0,0/0/1'])
assert(store.containers['legacy:99,0,0'])
-- Raw custom names are independent of getName's translated condition/fluid decorations.
local custom=item('Base.A','My named axe',true)
custom.getName=function()return 'Worn My named axe'end
assert(Model.item(custom).name=='My named axe')
-- Recorded titles have locale-independent identities even though native names are translated.
local tape=item('Base.VHS_Home','Localized tape title')
tape.getRecordedMediaIndex=function()return 22 end
tape.getMediaData=function()return {getId=function()return 'home:22'end}end
local recording=Model.item(tape)
assert(recording.mediaIndex==22 and recording.mediaId=='home:22' and not recording.name)
local otherTape=item('Base.VHS_Home','Another translated title')
otherTape.getRecordedMediaIndex=function()return 23 end
otherTape.getMediaData=function()return {getId=function()return 'home:23'end}end
assert(recording.key~=Model.item(otherTape).key)
tape.getDisplayName=function()return 'Different locale same recording'end
assert(recording.key==Model.item(tape).key)
assert(Model.text('a'..string.rep('Ж',256),512)=='a'..string.rep('Ж',255))
assert(Model.text('abc'..string.rep('🧟',200),512)=='abc'..string.rep('🧟',127))
-- Category preparation uses the owned boundary per sampled instance.
local prepared=0
local Categories=require 'PZSurvivorToolkit/ItemCategories'
local originalPrepare=Categories.prepareItem
Categories.prepareItem=function(value)
    prepared=prepared+1
    value.category='RecordedMedia'
end
local media=item('Base.HomeVHS','Tape')
media.getDisplayCategory=function()return media.category or 'Food'end
local result=Model.item(media)
assert(prepared==1 and result.cat=='RecordedMedia')
Categories.prepareItem=originalPrepare
assert(result.key~=Model.item(item('Base.HomeVHS','Tape')).key)
assert(Authority.requestPage(player,{revision='1'})=='invalid')
assert(Authority.requestPage(player,{cursor=0/0})=='invalid')
-- Compaction spends node budget and cannot invalidate an already open page's order reference.
local order=store.order
for i=1,600 do
    local id='dead:'..i
    store.order[#store.order+1]=id
    store.positions[id]=#store.order
end
Authority.resetRuntime()
local _,compactingPage=Authority.requestPage(player,{})
for i=1,100 do step(7,30)end
assert(store.order~=order and #store.order<10,'dead historical origins were never compacted')
local continuations=0
while compactingPage.cursor do
    local status
    status,compactingPage=Authority.requestPage(player,{cursor=compactingPage.cursor})
    assert(status=='ok','compaction broke an already issued cursor')
    continuations=continuations+1
    assert(continuations<20)
end
print('Manifest authority: bounded migration/scans/RPC, identities, origins, presets, mutations and stale retention passed.')
