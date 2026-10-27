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
local milkScript = {getFullName=function()return 'Base.MilkBottle'end}
local Cooking = {read=function(script, value)
    if script == milkScript then
        assert(value.getFluidContainer, 'manifest did not supply the sampled physical item')
        return value:getFluidContainer() == 'milk'
    end
    return nil
end}
local Fluids = {read=function(script, value)
    if script == milkScript then
        local fluid = value:getFluidContainer()
        if fluid == 'unknown' then return nil, {'beverage','alcoholic'}, true end
        if fluid == 'alcohol' then return 'alcoholic', {'beverage','alcoholic'}, true end
        if fluid == 'milk' or fluid == 'water' then return 'beverage', {'beverage','alcoholic'}, true end
        return 'none', {'beverage','alcoholic'}, true
    end
end}
local cached = {}
require = function(name)
    if cached[name] then return cached[name] end
    local module
    if name=='PZSurvivorToolkit/ItemTags' then module=Tags
    elseif name=='PZSurvivorToolkit/ItemCookingTags' then module=Cooking
    elseif name=='PZSurvivorToolkit/ItemFluidTags' then module=Fluids
    elseif name=='PZSurvivorToolkit/ItemUsageTags' then
        module=dofile(shared..name..'.lua')
        module.read=function(script,value)
            assert(script == (value.getScriptItem and value:getScriptItem()), 'usage capture omitted the physical script')
            return value.usage or {}, {{disinfectant=true,fuel=true}}, true
        end
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
local function bottle(fluid)
    local value=item('Base.MilkBottle','Bottle')
    value.fluid=fluid
    value.getScriptItem=function()return milkScript end
    value.getFluidContainer=function(self)return self.fluid end
    return value
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
assert(legacy.entries[Model.identity('Base.A','Old translated label','Food')].ingredient==nil,
    'legacy row invented a current cooking classification')
assert(legacy.entries[Model.identity('Base.A','Old translated label','Food')].cookingState==nil,
    'legacy row invented a current cooking state')
assert(legacy.entries[Model.identity('Base.A','Old translated label','Food')].fluidState==nil,
    'legacy row invented current fluid contents')
assert(legacy.entries[Model.identity('Base.A','Old translated label','Food')].usageState==nil,
    'legacy row invented current medical/fuel capability')
-- Stable identity separates types with identical labels, preserves custom names, ignores locale.
assert(Model.item(item('Base.A','Translated A')).key==Model.item(item('Base.A','Other locale')).key)
assert(Model.item(item('Base.A','Same')).key~=Model.item(item('Base.B','Same')).key)
assert(Model.item(item('Base.A','Renamed',true)).name=='Renamed')
assert(Model.item(item('Base.A','Renamed',true)).key~=Model.item(item('Base.A','Same')).key)
local milk,empty,petrol=bottle('milk'),bottle(nil),bottle('petrol')
local milkRow,emptyRow,petrolRow=Model.item(milk),Model.item(empty),Model.item(petrol)
assert(milkRow.ingredient==true and emptyRow.ingredient==false and petrolRow.ingredient==false,
    'snapshot did not capture live contents independently of the milk bottle type')
assert(milkRow.key~=petrolRow.key and emptyRow.key==petrolRow.key,
    'snapshot grouping ignored captured cooking capability')
assert(Model.item(item('Base.Unknown','Unknown')).ingredient==nil,
    'unavailable native cooking metadata must remain unknown')
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

local exactA,exactB=item('Base.Identical','Same'),item('Base.Identical','Same')
local modA,modB={PZSTItemTags={food='remove'}},{PZSTItemTags={tool='add'}}
for _,entry in ipairs({{exactA,modA},{exactB,modB}})do
 entry[1].hasModData=function()return true end
 entry[1].getModData=function()return entry[2]end
end
local projectedA,projectedB=Model.item(exactA),Model.item(exactB)
assert(projectedA.key~=projectedB.key and projectedA.tagDelta.food=='remove'
 and projectedB.tagDelta.tool=='add','warehouse merged different physical tag assignments')

-- Same-type bottles retain live cooking capability through grouping, scans and RPC pages.
milk.hasModData=function()return true end
milk.getModData=function()return {PZSTItemTags={ingredient='remove',tool='add'}}end
local bottles=container({milk,empty,petrol})
square(2,{object({bottles},{PZSTQuartermasterTagRules={['0']={include={'tool'},exclude={}}}})})
settle(100)
local bottleRecord=assert(store.containers['2,0,0/0/0'])
assert(#bottleRecord.itemOrder==2 and bottleRecord.entries[emptyRow.key].n==2)
local capturedMilk=assert(bottleRecord.entries[Model.item(milk).key])
assert(capturedMilk.ingredient==true and capturedMilk.tagDelta.ingredient=='remove'
    and capturedMilk.tagDelta.tool=='add', 'cooking capture lost manual tag assignments')
local capturedRevision=store.revision
settle(100)
assert(store.revision==capturedRevision and store.containers[bottleRecord.id].entries==bottleRecord.entries,
    'unchanged cooking capture rebuilt the sample')
Model.PAGE_ROWS=1
local bottlePlayer,seenMilk,seenOther={},false,false
local _,bottlePage=Authority.requestPage(bottlePlayer,{})
while bottlePage do
    for _,record in ipairs(bottlePage.containers)do
        if record.id==bottleRecord.id then
            for _,row in pairs(record.entries)do
                if row.ingredient==true then
                    seenMilk=true
                    assert(row.tagDelta.ingredient=='remove' and row.tagDelta.tool=='add')
                elseif row.ingredient==false then seenOther=true;assert(row.n==2)
                else error('pagination dropped a captured false cooking capability') end
            end
        elseif record.legacy then
            for _,row in pairs(record.entries)do assert(row.ingredient==nil)end
        end
    end
    if bottlePage.cursor then _,bottlePage=Authority.requestPage(bottlePlayer,{cursor=bottlePage.cursor})
    else bottlePage=nil end
end
assert(seenMilk and seenOther,'paginated sample omitted cooking groups')
Model.PAGE_ROWS=oldRows
milk.fluid='petrol'
settle(100)
local changedBottles=store.containers[bottleRecord.id]
assert(store.revision>capturedRevision and not changedBottles.entries[capturedMilk.key],
    'live fluid mutation retained an old ingredient classification')
for _,row in pairs(changedBottles.entries)do assert(row.ingredient==false)end
squares['2,0,0']=nil
settle(10)
assert(not store.containers[bottleRecord.id].loaded)
for _,row in pairs(store.containers[bottleRecord.id].entries)do assert(row.ingredient==false)end

-- Native flags on identical full types partition immutable groups and survive pages/unloading.
local function food(state)
    local value=item('Base.Steak','Steak')
    value.state=state
    value.IsFood=function()return true end
    value.isCookable=function(self)return self.state~=false end
    value.isCooked=function(self)return self.state=='cooked' end
    value.isBurnt=function(self)return self.state=='burnt' end
    return value
end
local raw,cooked,burnt,inapplicable=food('raw'),food('cooked'),food('burnt'),food(false)
local unknown=item('Base.Steak','Steak')
local foodItems={raw,food('raw'),cooked,burnt,inapplicable,unknown}
local foods=container(foodItems)
square(3,{object({foods},{PZSTQuartermasterTagRules={['0']={include={'food'},exclude={}}}})})
settle(100)
local foodRecord=assert(store.containers['3,0,0/0/0'])
assert(#foodRecord.itemOrder==5,'same-type food merged different cooking states')
assert(foodRecord.entries[Model.item(raw).key].n==2,'identical cooking states did not aggregate')
local foodRevision=store.revision
settle(100)
assert(store.revision==foodRevision and store.containers[foodRecord.id].entries==foodRecord.entries,
    'unchanged cooking states rebuilt the immutable sample')
-- Comparison must notice captured fields even in an older or malformed stored identity.
foodRecord.entries[Model.item(cooked).key].cookingState=nil
settle(100)
assert(store.revision>foodRevision and store.containers[foodRecord.id].entries[Model.item(cooked).key].cookingState=='cooked',
    'entry comparison ignored the captured cooking state')
foodRecord=store.containers[foodRecord.id]
foodRevision=store.revision
Model.PAGE_ROWS=1
local foodPlayer,states={},{}
local _,foodPage=Authority.requestPage(foodPlayer,{})
while foodPage do
    for _,record in ipairs(foodPage.containers)do
        if record.id==foodRecord.id then
            for _,row in pairs(record.entries)do
                local state=row.cookingState
                states[state==nil and 'unknown' or tostring(state)]=row.n
            end
        elseif record.legacy then
            for _,row in pairs(record.entries)do assert(row.cookingState==nil)end
        end
    end
    if foodPage.cursor then _,foodPage=Authority.requestPage(foodPlayer,{cursor=foodPage.cursor})
    else foodPage=nil end
end
assert(states.raw==2 and states.cooked==1 and states.burnt==1 and states['false']==1 and states.unknown==1,
    'paginated food sample lost a cooking state or inferred unknown state')
Model.PAGE_ROWS=oldRows
raw.state='cooked'
settle(100)
local changedFoods=store.containers[foodRecord.id]
assert(store.revision>foodRevision and changedFoods.entries[Model.item(raw).key].n==2
    and changedFoods.entries[Model.item(food('raw')).key].n==1,
    'in-place cooking mutation did not repartition the sample')
squares['3,0,0']=nil
settle(10)
assert(not store.containers[foodRecord.id].loaded and store.containers[foodRecord.id].entries==changedFoods.entries,
    'unloading lost the last known cooking states')

-- Current contents partition identical bottles even when their cooking capability is identical.
local water,waterAgain,alcohol,unavailable=bottle('water'),bottle('water'),bottle('alcohol'),bottle('unknown')
local fluidItems={water,waterAgain,alcohol,bottle(nil),unavailable}
square(4,{object({container(fluidItems)},{PZSTQuartermasterTagRules={['0']={include={'tool'},exclude={}}}})})
settle(100)
local fluidRecord=assert(store.containers['4,0,0/0/0'])
assert(#fluidRecord.itemOrder==4, 'same-type bottles merged distinct current contents or unknown state')
assert(fluidRecord.entries[Model.item(water).key].n==2, 'identical fluid states did not aggregate')
local fluidRevision=store.revision
settle(100)
assert(store.revision==fluidRevision and store.containers[fluidRecord.id].entries==fluidRecord.entries,
    'unchanged fluid contents rebuilt the immutable sample')
-- Even an old row whose identity already matches must have its captured field reconciled.
fluidRecord.entries[Model.item(alcohol).key].fluidState=nil
settle(100)
assert(store.revision>fluidRevision and store.containers[fluidRecord.id].entries[Model.item(alcohol).key].fluidState=='alcoholic',
    'entry comparison ignored the captured fluid state')
fluidRecord=store.containers[fluidRecord.id]
fluidRevision=store.revision
Model.PAGE_ROWS=1
local fluidPlayer,contents={},{}
local _,fluidPage=Authority.requestPage(fluidPlayer,{})
while fluidPage do
    for _,record in ipairs(fluidPage.containers)do
        if record.id==fluidRecord.id then
            for _,row in pairs(record.entries)do contents[row.fluidState or 'unknown']=row.n end
        elseif record.legacy then
            for _,row in pairs(record.entries)do assert(row.fluidState==nil)end
        end
    end
    if fluidPage.cursor then _,fluidPage=Authority.requestPage(fluidPlayer,{cursor=fluidPage.cursor})
    else fluidPage=nil end
end
assert(contents.beverage==2 and contents.alcoholic==1 and contents.none==1 and contents.unknown==1,
    'pagination lost captured contents or inferred old/unknown fluid state')
Model.PAGE_ROWS=oldRows
-- The per-row payload estimate reserves space for captured contents and usage fields.
local allOrder,allBytes=store.order,Model.PAGE_BYTES
store.order={fluidRecord.id}
local firstFluid=fluidRecord.entries[fluidRecord.itemOrder[1]]
Model.PAGE_BYTES=1800+#firstFluid.key+#firstFluid.ft+#firstFluid.cat+208
local budgetPlayer={}
local _,budgetPage=Authority.requestPage(budgetPlayer,{})
local budgetRows=0
for _ in pairs(budgetPage.containers[1].entries)do budgetRows=budgetRows+1 end
assert(budgetRows==1 and budgetPage.cursor, 'page estimate omitted captured contents/usage field allowances')
store.order,Model.PAGE_BYTES=allOrder,allBytes
water.fluid='alcohol'
settle(100)
local changedFluids=store.containers[fluidRecord.id]
assert(store.revision>fluidRevision and changedFluids.entries[Model.item(water).key].n==2
    and changedFluids.entries[Model.item(waterAgain).key].n==1,
    'in-place fluid mutation did not repartition the sample')
squares['4,0,0']=nil
settle(10)
assert(not store.containers[fluidRecord.id].loaded and store.containers[fluidRecord.id].entries==changedFluids.entries,
    'unloading lost last-known fluid contents')
-- Existing schema-2 samples remain valid and unknown while their source chunk is unavailable.
local oldKey=Model.identity('Base.MilkBottle',nil,'Food')
local oldId='55,0,0/0/0'
local oldSample={id=oldId,key='55,0,0',x=55,y=0,z=0,object=0,ci=0,loaded=false,
    sampledAt=123,entries={[oldKey]={key=oldKey,ft='Base.MilkBottle',cat='Food',n=1}},itemOrder={oldKey}}
store.containers[oldId]=oldSample
store.order[#store.order+1]=oldId
store.positions[oldId]=#store.order
store.byCoord[oldSample.key]={[oldId]=true}
store.liveCount=store.liveCount+1
Authority.resetRuntime()
settle(100)
assert(Authority.getStore()==store and store.schema==2 and store.containers[oldId]==oldSample
    and oldSample.entries[oldKey].fluidState==nil and oldSample.entries[oldKey].usageState==nil,
    'additive capture invalidated schema-2 samples or inferred unloaded bottle contents/usage')

-- An equally alcoholic diluted mixture can lose treatment/fuel capability without changing type or beverage role.
do
    local function usageBottle(roles)
        local value=bottle('alcohol')
        value.usage=roles
        return value
    end
    local good=usageBottle({bandage=false,disinfectant=true,dirty=false,fuel=true})
    local diluted=usageBottle({bandage=false,disinfectant=false,dirty=false,fuel=false})
    local unknown=usageBottle({})
    local usageItems={good,usageBottle(good.usage),diluted,unknown}
    square(5,{object({container(usageItems)},{PZSTQuartermasterTagRules={['0']={include={'tool'},exclude={}}}})})
    settle(100)
    local record=assert(store.containers['5,0,0/0/0'])
    assert(#record.itemOrder==3 and record.entries[Model.item(good).key].n==2,
        'same-type medical/fuel contents were merged or identical roles failed to aggregate')
    local revision=store.revision
    settle(100)
    assert(store.revision==revision and store.containers[record.id].entries==record.entries,
        'unchanged medical/fuel roles rebuilt the immutable sample')
    record.entries[Model.item(good).key].usageState=nil
    settle(100)
    assert(store.revision>revision and store.containers[record.id].entries[Model.item(good).key].usageState=='0101',
        'entry comparison ignored the captured usage roles')
    record=store.containers[record.id]
    revision=store.revision
    local strongKey=Model.item(good).key
    Model.PAGE_ROWS=1
    local player,states={},{}
    local _,page=Authority.requestPage(player,{})
    while page do
        for _,sample in ipairs(page.containers)do
            if sample.id==record.id then
                for _,row in pairs(sample.entries)do
                    assert(row.fluidState=='alcoholic', 'usage capture changed the independent beverage state')
                    states[row.usageState or 'unknown']=row.n
                end
            elseif sample.id==oldId or sample.legacy then
                for _,row in pairs(sample.entries)do assert(row.usageState==nil)end
            end
        end
        if page.cursor then _,page=Authority.requestPage(player,{cursor=page.cursor})
        else page=nil end
    end
    assert(states['0101']==2 and states['0000']==1 and states.unknown==1,
        'pagination lost known-false usage roles or inferred unknown contents')
    Model.PAGE_ROWS=oldRows
    good.usage=diluted.usage
    settle(100)
    local changedUsage=store.containers[record.id]
    assert(store.revision>revision and changedUsage.entries[Model.item(good).key].n==2
        and changedUsage.entries[strongKey].n==1,
        'in-place dilution did not repartition medical/fuel roles')
    squares['5,0,0']=nil
    settle(10)
    assert(not store.containers[record.id].loaded and store.containers[record.id].entries==changedUsage.entries,
        'unloading lost last-known medical/fuel roles')
end
