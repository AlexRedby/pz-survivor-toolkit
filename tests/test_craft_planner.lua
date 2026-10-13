local testNext = next
next = nil -- Native Kahlua does not expose this Lua standard-library global.
PZSurvivorToolkit = {}
local Planner = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/CraftPlanner.lua'))()
local function input(kind, amount, keep, index)
    return {index=index or 1, keep=keep or false, choices={{fullType=kind, amount=amount}}}
end
local function recipe(id, inputs, outputs) return {id=id, name=id, inputs=inputs, outputs=outputs} end
local function model(recipes, stock)
    local result = {recipes=recipes, resources={}, accepts=function(_,resource) return resource.item.valid ~= false end}
    for kind, amount in pairs(stock) do
        for i=1,amount do
            local id = #result.resources + 1
            table.insert(result.resources,{fullType=kind,item={getID=function() return id end}})
        end
    end
    return result
end
local recipes = {
    saw=recipe('saw',{input('Log',1),input('Saw',1,true,2)},{Plank=3}),
    handles=recipe('handles',{input('Plank',1),input('Knife',1,true,2)},{Handle=12}),
    spoon=recipe('spoon',{input('Handle',1),input('Knife',1,true,2)},{Spoon=1}),
}
local original=model(recipes,{Log=1,Saw=1,Knife=1})
local plan=assert(Planner.plan(original,'spoon',2))
assert(#plan.steps==4 and plan.steps[1].recipe.id=='saw' and plan.steps[2].recipe.id=='handles')
assert(plan.steps[3].recipe.id=='spoon' and plan.steps[4].recipe.id=='spoon')
assert(plan.consumed.Log==1 and not plan.consumed.Saw and not plan.consumed.Knife)
assert(#original.resources==3, 'planning must not mutate the inventory snapshot')
local totals={}
for _,item in ipairs(plan.resources) do totals[item.fullType]=(totals[item.fullType] or 0)+1 end
assert(totals.Plank==2 and totals.Handle==10 and totals.Spoon==2 and totals.Knife==1)
assert(#assert(Planner.plan(model(recipes,{Handle=2,Knife=1}),'spoon',2)).steps==2)
assert(not Planner.plan(model(recipes,{Log=1,Saw=1}),'spoon',1), 'missing tools must not be invented')
local invalid=model(recipes,{Handle=1,Knife=1});invalid.resources[1].item.valid=false;invalid.resources[2].item.valid=false
assert(not Planner.plan(invalid,'spoon',1), 'unusable real objects must not satisfy inputs')
local cycle={a=recipe('a',{input('B',1)},{A=1}),b=recipe('b',{input('A',1)},{B=1})}
assert(not Planner.plan(model(cycle,{}),'a',1), 'cyclic recipes must terminate')
local shared={out=recipe('out',{input('A',1),input('B',1,false,2)},{C=1}),
    a=recipe('a',{input('Raw',1)},{A=1}),b=recipe('b',{input('Raw',1)},{B=1})}
assert(not Planner.plan(model(shared,{Raw=1}),'out',1), 'branches may not double-spend raw materials')
assert(#assert(Planner.plan(model(shared,{Raw=2}),'out',1)).steps==3)
-- Backtrack producer choice when the first path spends a material required by another slot.
shared.aa=recipe('aa',{input('Other',1)},{A=1})
assert(#assert(Planner.plan(model(shared,{Raw=1,Other=1}),'out',1)).steps==3)
local alternative=input('Rare',1);alternative.choices[2]={fullType='Common',amount=2}
local alternatives={out=recipe('out',{alternative},{Result=1})}
local alternativePlan=assert(Planner.plan(model(alternatives,{Common=2}),'out',1))
assert(alternativePlan.steps[1].inputs[1].fullType=='Common' and alternativePlan.consumed.Common==2)
local duplicateTools={out=recipe('out',{input('Tool',1,true),input('Tool',1,true,2)},{Result=1})}
assert(not Planner.plan(model(duplicateTools,{Tool=1}),'out',1), 'one tool cannot occupy two native input slots')
assert(Planner.plan(model(duplicateTools,{Tool=2}),'out',1))
local catalyst={out=recipe('out',{input('Tool',1),input('Tool',1,true,2)},{Result=1})}
assert(not Planner.plan(model(catalyst,{Tool=1}),'out',1), 'a consumed tool cannot simultaneously be kept')
assert(Planner.plan(model(catalyst,{Tool=2}),'out',1))
local constrained = model(catalyst,{Tool=2})
constrained.accepts = function(slot, resource) return not slot.keep or resource.item:getID() == 1 end
local allocated = assert(Planner.plan(constrained, 'out', 1))
assert(allocated.steps[1].inputs[1].resourceIds[1] == 2 and allocated.steps[1].inputs[2].resourceIds[1] == 1,
    'backtrack same-type objects when only one satisfies a later tool slot')
assert(allocated.initialIds[1] and allocated.initialIds[2], 'execution must reserve initial object identities')
local reusable = {
    out=recipe('out',{input('A',1,true),input('B',1,true,2)},{Result=1}),
    b=recipe('b',{input('Raw',1),input('A',1,true,2)},{B=1}),
}
for _, reverse in ipairs({false,true}) do
    reusable.out.inputs = reverse and {input('B',1,true),input('A',1,true,2)}
        or {input('A',1,true),input('B',1,true,2)}
    local reuse = assert(Planner.plan(model(reusable,{A=1,Raw=1}),'out',1))
    local targetSlot = reverse and 2 or 1
    assert(#reuse.steps==2 and reuse.steps[1].recipe.id=='b' and reuse.steps[2].recipe.id=='out')
    assert(reuse.steps[1].inputs[2].resourceIds[1]==reuse.steps[2].inputs[targetSlot].resourceIds[1],
        'a prerequisite may reuse the exact tool reserved by either target slot order')
    assert(reuse.consumed.Raw==1 and not reuse.consumed.A)
end
reusable.out.inputs = {input('A',1),input('B',1,true,2)}
local consumeAfterUse = assert(Planner.plan(model(reusable,{A=1,Raw=1}),'out',1))
assert(consumeAfterUse.consumed.A==1 and consumeAfterUse.steps[1].inputs[2].resourceIds[1]
    ==consumeAfterUse.steps[2].inputs[1].resourceIds[1],
    'a parent consumed input may be used as a prerequisite tool before it is consumed')
reusable.b.inputs = {input('Raw',1),input('A',1,false,2)}
assert(not Planner.plan(model(reusable,{A=1,Raw=1}),'out',1),
    'prerequisites must not consume inputs reserved by their parent')
local separateConsumed = assert(Planner.plan(model(reusable,{A=2,Raw=1}),'out',1))
assert(separateConsumed.consumed.A==2 and separateConsumed.steps[1].inputs[2].resourceIds[1]
    ~=separateConsumed.steps[2].inputs[1].resourceIds[1],
    'a prerequisite and parent must consume distinct original objects')
reusable.b.inputs = {input('Raw',1),input('A',1,true,2),input('A',1,true,3)}
assert(not Planner.plan(model(reusable,{A=1,Raw=1}),'out',1),
    'a borrowed ancestor tool cannot occupy two prerequisite slots')
assert(Planner.plan(model(reusable,{A=2,Raw=1}),'out',1))
local nested = {
    out=recipe('out',{input('A',1,true),input('B',1,true,2)},{Result=1}),
    b=recipe('b',{input('A',1,true),input('C',1,true,2)},{B=1}),
    c=recipe('c',{input('Raw',1),input('A',1,true,2)},{C=1}),
}
local nestedPlan = assert(Planner.plan(model(nested,{A=1,Raw=1}),'out',1))
assert(#nestedPlan.steps==3 and nestedPlan.steps[1].recipe.id=='c' and nestedPlan.steps[2].recipe.id=='b')
local nestedId = nestedPlan.steps[3].inputs[1].resourceIds[1]
assert(nestedPlan.steps[1].inputs[2].resourceIds[1]==nestedId
    and nestedPlan.steps[2].inputs[1].resourceIds[1]==nestedId,
    'nested reservations release only their own claim on a shared tool')
nested.a=recipe('a',{input('Other',1)},{A=1})
local generatedTool = assert(Planner.plan(model(nested,{Other=1,Raw=1}),'out',1))
assert(#generatedTool.steps==4 and generatedTool.steps[1].recipe.id=='a')
for _, slot in ipairs({generatedTool.steps[2].inputs[2],generatedTool.steps[3].inputs[1],generatedTool.steps[4].inputs[1]}) do
    assert(slot.generated==1 and #slot.resourceIds==0, 'generated retained tools preserve their identity across prerequisites')
end
nested.c.inputs={input('Raw',1),input('A',1,true,2),input('A',1,true,3)}
assert(not Planner.plan(model(nested,{Other=1,Raw=1}),'out',1),
    'one generated retained tool cannot satisfy two simultaneous slots')
local preferred = model(catalyst,{Tool=2})
preferred.recipes = {out=recipe('out',{input('Tool',1)},{Result=1})}
preferred.recipes.out.inputs[1].preferredIds = {[2]=true}
local preferredPlan = assert(Planner.plan(preferred,'out',2))
assert(preferredPlan.steps[1].inputs[1].resourceIds[1]==2 and preferredPlan.steps[2].inputs[1].resourceIds[1]==1,
    'preferred object IDs win inventory order but do not prevent later same-type crafts')
preferred.recipes.out.inputs[1].keep=true
local preferredTool = assert(Planner.plan(preferred,'out',2))
assert(preferredTool.steps[1].inputs[1].resourceIds[1]==2 and preferredTool.steps[2].inputs[1].resourceIds[1]==2,
    'retained preferred objects are reused across target repetitions')
local retainedPreference = input('Tool',1,true,2)
retainedPreference.preferredIds = {[1]=true}
local preserveTool = model({
    out=recipe('out',{input('Mid',1),retainedPreference},{Result=1}),
    mid=recipe('mid',{input('Tool',1)},{Mid=1}),
},{Tool=3})
local preserved = assert(Planner.plan(preserveTool,'out',2))
assert(#preserved.steps==4 and preserved.steps[1].inputs[1].resourceIds[1]==2
    and preserved.steps[3].inputs[1].resourceIds[1]==3,
    'prerequisites consume alternative copies before a preferred retained tool')
assert(preserved.steps[2].inputs[2].resourceIds[1]==1 and preserved.steps[4].inputs[2].resourceIds[1]==1,
    'the preferred retained tool survives every target repetition')
nested.c.inputs = {input('Raw',1),input('A',1,true,2)}
nested.out.inputs = {input('B',1),input('A',1,true,2)}
local preferredNested = model(nested,{A=1,Raw=1})
local preferredNestedId
for _, resource in ipairs(preferredNested.resources) do
    if resource.fullType=='A' then preferredNestedId=resource.item:getID() end
end
nested.out.inputs[2].preferredIds = {[preferredNestedId]=true}
local preferredNestedPlan = assert(Planner.plan(preferredNested,'out',1))
assert(preferredNestedPlan.steps[1].inputs[2].resourceIds[1]==preferredNestedId
    and preferredNestedPlan.steps[2].inputs[1].resourceIds[1]==preferredNestedId
    and preferredNestedPlan.steps[3].inputs[2].resourceIds[1]==preferredNestedId,
    'nested prerequisites may borrow a preferred retained tool protected before other slots')
preferred.recipes.out.inputs[1].keep=false
preferred.recipes.out.inputs[1].selectedIds={[2]=true}
preferred.accepts=function(slot,resource) return not slot.selectedIds or slot.selectedIds[resource.item:getID()] end
assert(not Planner.plan(preferred,'out',2), 'legacy selected IDs remain a hard constraint despite preferences')
assert(not plan.reserved, 'reservation bookkeeping must not leak into the returned plan')
assert(plan.steps[2].inputs[1].generated == 1 and #plan.steps[2].inputs[1].resourceIds == 0,
    'generated intermediates are distinguished from original inventory objects')
local deep = {}
for i = 1, 40 do deep['r'..i] = recipe('r'..i, {input('i'..(i+1),1)}, {['i'..i]=1}) end
local tooDeep, why = Planner.plan(model(deep, {i41=1}), 'r1', 1)
assert(not tooDeep and why == 'complex', 'deep dependency chains are bounded')
local large=model({out=recipe('out',{input('Bulk',1000),input('MissingTool',1,true,2)},{Result=1})},{Bulk=10000})
local began=os.clock()
local bounded, limit=Planner.plan(large,'out',1)
assert(not bounded and limit=='complex' and os.clock()-began<2,
    'large same-type allocations must exhaust the work budget without freezing the UI')
for _,n in ipairs({0,-1,0.5,101,math.huge}) do assert(not Planner.plan(original,'spoon',n)) end
print('Craft planner: chains, quantities/surplus, retained prerequisites, shared inputs, preferences, backtracking and bounds passed.')
