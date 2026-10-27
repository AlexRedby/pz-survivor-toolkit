local callback
Events={OnGameBoot={Add=function(fn) assert(not callback);callback=fn end}}
ItemTag={CANT_COMPOST='cantcompost',NO_COOKING_XP='nocookingxp',IS_COMPOSTABLE='iscompostable'}
local load=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/000ToolkitWormCompost.lua'))
local apply=load()
assert(apply==callback,'startup did not register the owned fix')
callback() -- Scripts are resolved when startup fires, not when this file loads.
local tags={[ItemTag.CANT_COMPOST]=true,[ItemTag.NO_COOKING_XP]=true,['mod:wormrole']=true}
local otherTags={[ItemTag.CANT_COMPOST]=true}
local calls,removed=0,0
local worm={getTags=function() return {remove=function(_,tag)
    assert(tag==ItemTag.CANT_COMPOST,'removed an unrelated native tag')
    tags[tag]=nil;removed=removed+1
end} end}
ScriptManager={instance={FindItem=function(_,name)
    assert(name=='Base.Worm','fix inspected unrelated item definitions')
    calls=calls+1;return worm
end}}
for _,mode in ipairs({'single-player','Host-client','Host-server'}) do
    tags[ItemTag.CANT_COMPOST]=true
    callback()
    assert(not tags[ItemTag.CANT_COMPOST],mode..' kept the native worm restriction')
    assert(tags[ItemTag.NO_COOKING_XP] and tags['mod:wormrole'],'fix replaced other worm tags')
    assert(not tags[ItemTag.IS_COMPOSTABLE],'fresh worms became directly compostable')
    assert(otherTags[ItemTag.CANT_COMPOST],'fix removed another item restriction')
end
callback()
assert(calls==4 and removed==4,'startup fix was not safe to repeat')
ScriptManager.instance.FindItem=function() return nil end
callback() -- Missing native definition is a no-op, never a global restriction bypass.
print('worm compost startup: OK')
