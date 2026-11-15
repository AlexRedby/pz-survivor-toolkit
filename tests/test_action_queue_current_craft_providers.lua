-- Current selected sources intentionally remain unsupported as queue-edit
-- providers. This proves the refusal boundary, not positive integration.
if not NativeActionRoot or not ((NativeCookCraftPanelSourcePath and NativeNeatCraftPanelSourcePath)or NativeWishlistWorkshopRoot) then
    if TestCoverage then TestCoverage('refusal-boundary','skipped','Current crafting-provider refusal requires native and Workshop sources.')end
    return
end
TestProjectCookBalanceFixtureOnly=true
local setup=assert(loadfile(ProjectRoot..'/tests/test_project_cook_balance.lua'))()
TestProjectCookBalanceFixtureOnly=nil
NC_CraftActionPanel,PJCK_EvoPanel=nil,nil
local compat=setup(nil,true)
assert(not compat.verifySources('Neat_Crafting')and not compat.verifySources('Project_Cook'),
    'current producer sources unexpectedly match the legacy audited contracts')
assert(not compat.isInstalled('Neat_Crafting')and not compat.isInstalled('Project_Cook')
    and not compat.isInstalled('Project_Cook_FirstAddition'),
    'unreviewed current crafting source acquired queue-edit authority')
assert(NC_CraftActionPanel==nil and PJCK_EvoPanel==nil,
    'refused provider was preloaded or rewritten by its queue adapter')
assert(compat.isInstalled('Project_Cook_Balance')and PJCK_CraftActionPanel,
    'refusing evolved-recipe edits disabled the independently proven completion repair')
assert(not compat.isCraftOwner('NC_CraftActionPanel',{}, {})
    and not compat.isCraftOwner('PJCK_CraftActionPanel',{}, {}),
    'balance-only or unknown provider acquired a craft edit contract')
print('UNSUPPORTED current Neat Crafting queue integration: new transfer/return/cancel/progressive/ALL protocol needs qualification')
print('UNSUPPORTED current Project Cook queue edits: new evolved-recipe strict-instance/input selection needs qualification; completion balance remains supported')
print('PASS current-provider refusal boundary only; positive selected-pack queue integration remains incomplete')
if TestCoverage then TestCoverage('refusal-boundary','passed','Refusal boundary only; current Neat Crafting and Project Cook queue-edit integration remains unsupported.')end
