package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/?.lua;'..package.path
isClient=function() return false end
local world={}
ModData={getOrCreate=function() return world end}
local Tags=require 'PZSurvivorToolkit/ItemTags'
local Custom=require 'PZSurvivorToolkit/TagCustomization'
local Schema=require 'PZSurvivorToolkit/ItemTagSchema'
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for key,child in pairs(value) do result[key]=copy(child) end;return result
end
local active='custom:11111111-1234-1234-1234-123456789abc'
local unassigned='custom:22222222-1234-1234-1234-123456789abc'
local deleted='custom:33333333-1234-1234-1234-123456789abc'
local name='Mod.ChoiceSubject'
local script={getFullName=function() return name end}
local base={'condiment','food','junk','category:Mod.Unknown',active,deleted,'condiment',
    legacyCategory='Mod.Unknown',legacyTags={food=true},itemCategory='Mod.Unknown',itemSignature='fixture',
    foodStates={'fresh','stale','rotten'},cookingStates={'raw','cooked','burnt'},
    usageBase={managed={fuel=true}},usageStates={{fuel=true,bandage=true,fishBait=true},
        {beverage=true,alcoholic=true,disinfectant=true,trapBait=true,repair=true,spentBattery=true}},
    mediaStates={{experience=true},{recipe=true}}}
local automatic,lastAutomatic,lastContext=Tags.automaticForScriptItem
Tags.automaticForScriptItem=function(_,context)
    lastAutomatic,lastContext=copy(base),context
    return lastAutomatic
end
local function parity(changes)
    world=Custom.empty()
    world.definitions[active]={name='Assigned'}
    world.definitions[unassigned]={name='Unassigned'}
    world.definitions[deleted]={deleted=true}
    world.types[name:lower()]=changes
    local owned=Tags.forScriptItem(script,Tags.newScriptProjectionContext())
    local expected=Tags.choices(owned)
    -- Ordinary producers still own all nested metadata.
    assert(owned.usageStates~=lastAutomatic.usageStates and owned.usageStates[1]~=lastAutomatic.usageStates[1])
    owned.usageStates[1].fuel=false
    assert(lastAutomatic.usageStates[1].fuel==true,'owned projection shared state metadata')
    local context=Tags.newScriptProjectionContext()
    local actual=Tags.choicesForScriptItem(script,context)
    assert(lastContext==context,'choice producer discarded its operation context')
    assert(#actual==#expected and actual.legacyCategory==owned.legacyCategory,'choice producer changed count/category')
    for index,id in ipairs(expected) do assert(actual[index]==id,'choice producer changed ordered ID '..index) end
    for key in pairs(actual) do
        assert(type(key)=='number' or key=='legacyCategory','choice producer retained unused metadata '..key)
    end
    local numeric=Custom.projectIds(base,name)
    for key in pairs(numeric) do assert(type(key)=='number','numeric projection retained metadata') end
end
parity({})
parity({condiment='remove',junk='remove',[unassigned]='add',[deleted]='add',food='add'})
parity({seasoning='add',fresh='remove',raw='remove',fuel='remove',[active]='remove',[unassigned]='add'})
world.definitions[active].deleted=true
local expected=Tags.choices(Tags.forScriptItem(script))
local actual=Tags.choicesForScriptItem(script)
assert(#actual==#expected)
for index,id in ipairs(expected) do assert(actual[index]==id,'choice producer ignored live deletion') end
assert(#Tags.choicesForScriptItem(nil)==0)

-- Metadata that choice callers never consume must not even be traversed.
local cycle={};cycle.self=cycle
assert(Custom.projectIds({'junk',usageStates=cycle},name)[1]=='junk')
Tags.automaticForScriptItem=automatic

-- The indexed automatic builder preserves the old first-occurrence removal
-- behavior for duplicate imported IDs, including the retained array order.
Schema.items['mod.duplicatechoices']={'edible','edible','snack','fuel','fuel'}
ItemType={FOOD='food',CONTAINER='container',DRAINABLE='drainable',LITERATURE='literature',MAP='map'}
local duplicate={getFullName=function() return 'Mod.DuplicateChoices' end,
    getDisplayCategory=function() return 'Mod.Unknown' end,isItemType=function() return false end}
local tags=Tags.automaticForScriptItem(duplicate)
assert(#tags==4 and tags[1]=='edible' and tags[2]=='snack' and tags[3]=='fuel' and tags[4]=='fuel',
    'indexed membership changed duplicate removal or order')
Schema.items['mod.duplicatechoices']=nil
local duplicateChoices={'fuel','fuel',usageStates={{fuel=true,repair=true},{repair=true}}}
local choices=Tags.choices(duplicateChoices)
assert(#choices==4 and choices[1]=='fuel' and choices[2]=='fuel' and choices[3]=='repair' and choices[4]=='maintenance',
    'indexed choices removed source duplicates or changed addition order')
print('Script choices: ordered public-producer parity, state metadata, custom/retired/deleted IDs and owned live outputs passed')
