-- Focused producer observation checks. Native transfer outcomes/Keep commits
-- have separate Settlement coverage; these doubles grant no gameplay proof.
local function list(items)
    return {size=function() return #items end, get=function(_,i) return items[i+1] end,
        contains=function(_,item) for _,value in ipairs(items) do if value==item then return true end end return false end}
end
local sources, lines = {}, {}
local function callback(file,line,body)
    local fn=body or function() return true end
    sources[fn],lines[fn]=file,line
    return fn
end
local bindingCalls=0
local Proof={closure=function(fn,file) return sources[fn]==file end,matches=function() return true end}
Proof.captureBindings=function(bindings)
    bindingCalls=bindingCalls+1
    local refs={}
    for _,entry in ipairs(bindings) do
        for _,key in ipairs(entry.keys) do refs[#refs+1]={entry.owner,key,entry.owner[key]} end
    end
    return function() for _,ref in ipairs(refs) do if ref[1][ref[2]]~=ref[3] then return false end end return true end
end
getFirstLineOfClosure=function(fn) return lines[fn] end
CharacterTrait={DISORGANIZED='disorganized'}
ItemType={DRAINABLE='drainable',FOOD='food',CONTAINER='container'}
local root={}
local player={getPlayerNum=function() return 0 end,getInventory=function() return root end,
    isDead=function() return false end,isAsleep=function() return false end,
    hasTrait=function(self) return self.disorganized==true end,isEquipped=function() return false end}
instanceof=function(value,kind) return value==player and kind=='IsoPlayer' end
getSpecificPlayer=function() return player end
local p4,enabled=false,true
getActivatedMods=function() return {contains=function(_,id) return id=='P4TidyUpMeister' and p4 end} end
local recipe={isCanBeDoneFromFloor=function(self) return self.floor==true end}
local body={character=player,craftRecipe=recipe}
local handles,remembered={},0
local settlement={observePreparation=callback('ActionQueueSettlement.lua',nil,function(action,spec)
    local handle={action=action,spec=spec};handles[#handles+1]=handle;return handle
end),rememberPreparation=callback('ActionQueueSettlement.lua',nil,function(value)
    assert(value==body);remembered=remembered+1;return true
end)}
local policy={matchesNative=callback('ActionQueuePolicy.lua'),isOrdinaryTransfer=callback('ActionQueuePolicy.lua'),
    isCarriedContainer=callback('ActionQueuePolicy.lua',nil,function(container) return container.carried==true end)}
local craft={supports=callback('ActionQueueCraft.lua')}
local definitions={inspect=callback('ActionQueueDefinitions.lua')}
local bulk={transfer=callback('BulkActions.lua',233)}
ISCraftingUI={ReturnItemsToOriginalContainer=callback('ISCraftingUI.lua',4),ReturnItemToContainer=callback('ISCraftingUI.lua',15)}
ISInventoryTransferUtil={newInventoryTransferAction=callback('ISInventoryTransferUtil.lua',15)}
PZSurvivorToolkit={ActionQueueSettlement=settlement,ActionQueuePolicy=policy,ActionQueueCraft=craft,
    ActionQueueDefinitions=definitions,BulkActions=bulk,Settings={actionQueue=function() return enabled end}}
require=function(name) assert(name=='PZSurvivorToolkit/SourceProof');return Proof end
local path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCraftLoans.lua'
local source
if NativeReadText then source=NativeReadText(path)
else local file=assert(io.open(path));source=file:read('*a');file:close() end
local Loans=assert(loadstring(source,'@'..path))()
local function tool(id,opts)
    opts=opts or {}
    local source={carried=not opts.world,getContainingItem=function() return {} end}
    local script={isItemType=function(_,kind) return opts.kind==kind end,
        getReplaceOnUse=function() return opts.replace end,getReplaceOnDeplete=function() end,
        getOnBreak=function() return opts.onBreak end}
    local item={getID=function() return id end,getFullType=function() return 'Base.Tool'..id end,
        getScriptItem=function() return script end,getContainer=function() return opts.root and root or source end}
    local input={isKeep=function() return not opts.consume end,hasConsumeFromItem=function() return false end,
        hasCreateToItem=function() return false end,isReplace=function() return false end,isApplyOnTick=function() return false end}
    return item,{input={native=input},items=list({item})},source
end
local first,firstSelection,firstSource=tool(1)
local second,secondSelection,secondSource=tool(2)
local consumed,consumeSelection=tool(3,{consume=true})
local selected={firstSelection,secondSelection,consumeSelection}
local kept=list({first,second})
local observation=assert(Loans.capture(player,body,selected,kept))
local firstPickup={character=player,item=first,srcContainer=firstSource,destContainer=root}
local secondPickup={character=player,item=second,srcContainer=secondSource,destContainer=root}
observation.pickup(firstPickup);observation.pickup(secondPickup);observation.body(body)
assert(#handles==2 and handles[1]~=handles[2] and handles[1].action==firstPickup and handles[2].action==secondPickup)
assert(remembered==1 and handles[1].spec.guard(firstPickup) and handles[2].spec.guard(secondPickup))
assert(not handles[1].spec.guard(secondPickup),'one tool acquired the other tool pickup')
assert(handles[1].spec.capture().source==firstSource and handles[2].spec.capture().source==secondSource)
assert(handles[1].spec.observed()==false,'producer guessed native transfer success')
local before=bindingCalls
local rootItem,rootSelection=tool(4,{root=true})
assert(Loans.capture(player,body,{rootSelection},list({rootItem}))==nil and bindingCalls==before)
assert(Loans.capture(player,body,selected,list({}))==nil and bindingCalls==before)
recipe.floor=true
assert(Loans.capture(player,body,selected,kept)==nil and bindingCalls==before)
recipe.floor=false
for _,opts in ipairs({{consume=true},{kind='food'},{kind='drainable'},{kind='container'},{replace=true},{onBreak=true}}) do
    local item,selection=tool(5,opts)
    before=bindingCalls
    assert(Loans.capture(player,body,{selection},list({item}))==nil and bindingCalls==before)
end
local worldItem,worldSelection=tool(6,{world=true})
assert(Loans.capture(player,body,{worldSelection},list({worldItem}))==nil)
p4=true;assert(Loans.capture(player,body,selected,kept)==nil);p4=false
enabled=false;assert(Loans.capture(player,body,selected,kept)==nil);enabled=true
player.disorganized=true;assert(Loans.capture(player,body,selected,kept)==nil);player.disorganized=false
local old=policy.matchesNative
policy.matchesNative=function() return true end
assert(not handles[1].spec.guard(firstPickup),'changed transfer policy retained its loan lease')
assert(Loans.capture(player,body,selected,kept)==nil)
policy.matchesNative=old
local saved=settlement.observePreparation
settlement.observePreparation=nil
assert(Loans.capture(player,body,selected,kept)==nil,'missing optional support escaped into gameplay')
settlement.observePreparation=saved
assert(Loans.capture(player,body,{},nil)==nil,'malformed optional capture escaped into gameplay')
print('Craft loan producer checks passed: exact kept-tool pickups, independent handles, unsupported native paths and live source revocation.')
