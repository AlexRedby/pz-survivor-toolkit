-- Pure hand-assignment component of native Equip, evaluated from projected
-- state. No actor/item getters, action registration or complete edit claim.
-- A native owner must separately prove binding, side effects, capacity and
-- fresh outcomes (including Host replication and selected-mod hand hooks).
local Hands={}
PZSurvivorToolkit.ActionQueueHands=Hands
local kind,meta,each,equal=type,getmetatable,pairs,rawequal
local rowFields={item=true,requiresBoth=true,handWeapon=true,handgun=true}
local stateFields={primary=true,secondary=true}
local function plain(value,allowed)
    if kind(value)~="table"or meta(value)~=nil then return false end
    for key in each(value)do if not allowed[key]then return false end end
    return true
end
local function opaque(value)return kind(value)=="table"or kind(value)=="userdata"end
local function row(value)
    return plain(value,rowFields)and opaque(value.item)
        and kind(value.requiresBoth)=="boolean"and kind(value.handWeapon)=="boolean"
        and kind(value.handgun)=="boolean"and(not value.handgun or value.handWeapon)
end
local function consistent(left,right)
    return left==false or right==false or not equal(left.item,right.item)
        or left.requiresBoth==right.requiresBoth and left.handWeapon==right.handWeapon and left.handgun==right.handgun
end
local suffixes={RequiresBoth="requiresBoth",HandWeapon="handWeapon",Handgun="handgun"}
local function factsFor(facts,side,value)
    facts[side]=value~=false and value.item or false
    for suffix,field in each(suffixes)do facts[side..suffix]=value~=false and value[field]or false end
end
local function assign(effects,side,value)
    effects[#effects+1]={field=side,set=value~=false and value.item or false}
    for suffix,field in each(suffixes)do
        effects[#effects+1]={field=side..suffix,set=value~=false and value[field]or false}
    end
    return effects
end
local function resource(actor,state,incoming,mode)
    if not opaque(actor)or not plain(state,stateFields)or not row(incoming)
        or not(state.primary==false or row(state.primary))or not(state.secondary==false or row(state.secondary))
        or not consistent(state.primary,state.secondary)or not consistent(state.primary,incoming)
        or not consistent(state.secondary,incoming)
        or(mode~="primary"and mode~="secondary"and mode~="both")then return end
    local facts={};factsFor(facts,"primary",state.primary);factsFor(facts,"secondary",state.secondary)
    local cases={}
    local result={domain="hands",key=actor,facts=facts,cases=cases}
    if mode=="both"then
        cases[1]={when={{field="primary",equal=incoming.item},{field="secondary",equal=incoming.item}},effects={}}
        cases[2]={when={},effects=assign(assign({},"primary",incoming),"secondary",incoming)}
        return result
    end
    local opposite=mode=="primary"and"secondary"or"primary"
    -- Native complete returns before all writes when isAlreadyEquipped is
    -- true. Its single-hand predicate does not inspect the other item's traits.
    cases[1]={when={{field=mode,equal=incoming.item},{field=opposite,notEqual=incoming.item}},effects={}}
    local cleared=assign(assign({},opposite,false),mode,incoming)
    for _,predicate in ipairs({{field=opposite.."RequiresBoth",equal=true},
        {field=opposite,equal=incoming.item},{field=opposite,sameAs=mode}})do
        cases[#cases+1]={when={predicate},effects=cleared}
    end
    if mode=="primary"and incoming.handgun then
        cases[#cases+1]={when={{field=opposite.."HandWeapon",equal=true}},effects=cleared}
    elseif mode=="secondary"and incoming.handWeapon then
        cases[#cases+1]={when={{field=opposite.."Handgun",equal=true}},effects=cleared}
    end
    cases[#cases+1]={when={},effects=assign({},mode,incoming)}
    return result
end
function Hands.equipResource(...)
    -- Kahlua need not clear omitted fixed parameters. Check the real call
    -- arity before extracting this required, data-only input tuple.
    if select('#',...)~=4 then return end
    local actor,state,incoming,mode=...
    -- Invalid metadata (including a failed native metatable query) describes
    -- no resource. Refusal must not assert/log or promote partial information.
    local ok,value=pcall(resource,actor,state,incoming,mode)
    if ok then return value end
end
return Hands
