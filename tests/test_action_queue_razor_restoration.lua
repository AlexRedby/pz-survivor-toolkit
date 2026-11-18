-- Native source-backed queue/receipt composition; Java delivery is modeled by
-- the shared fixture. This does not establish live Host transport or rendering.
if not NativeActionRoot then return end
local create=assert(loadfile(ProjectRoot..'/tests/support/borrowing_composition.lua'))()
local function prepared()
 local f=create(false,{p4=false,carried=true,razor=true})
 local e,q,t=f.env,f.queue,f.env.PZSurvivorToolkit
 local previous=f.tool(810,'Base.Pen',f.inventory)
 local razor=f.tool(811,'Base.Razor')
 f.player.primary=previous
 e.ISCharacterScreen.onTrimBeard(f.player,'Moustache')
 assert(#q.queue==5,'native razor chain must enqueue approach/pickup/equip/trim/owned restoration')
 local approach,pickup,equip,body,cleanup=unpack(q.queue)
 assert(t.ActionQueueApproach.isContainer(approach,f.source,f.player))
 assert(pickup.Type=='ISInventoryTransferAction'and equip.Type=='ISEquipWeaponAction'and body.Type=='ISTrimBeard')
 assert(pickup.toolkitQueueOperation==equip.toolkitQueueOperation and equip.toolkitQueueOperation==body.toolkitQueueOperation
  and body.toolkitQueueOperation==cleanup.toolkitQueueOperation,'native operation lost its single ownership token')
 local state=assert(t.ActionQueueSettlement.operationState(pickup))
 assert(#state.borrowings==1 and state.borrowings[1].state=='prepare','menu production earned a physical loan')
 f.start(approach);f.dispatch(approach,'perform')
 f.start(pickup);f.dispatch(pickup,'perform')
 f.start(equip);f.dispatch(equip,'perform')
 assert(f.player.primary==razor and razor.container==f.inventory,'native preparation did not put the razor in the primary hand')
 state=assert(t.ActionQueueSettlement.operationState(body))
 assert(state.borrowings[1].state=='active','only actual native pickup may earn the carried tool loan')
 f.start(body)
 return f,previous,razor,body,cleanup
end
local f,previous,razor,body,cleanup=prepared()
local q,t=f.queue,f.env.PZSurvivorToolkit
f.dispatch(body,'perform')
assert(f.player:getHumanVisual().beard=='Moustache'and q.current==cleanup,'native beard effect or owned cleanup order changed')
f.start(cleanup);f.dispatch(cleanup,'perform')
local restored=q.current
assert(#q.queue==2 and restored.Type=='ISEquipWeaponAction'and restored.item==previous,'owned cleanup must issue one native prior-primary restore')
f.start(restored);f.dispatch(restored,'perform')
assert(f.player.primary==previous and razor.container==f.inventory,'native hand restoration changed the borrowed item location')
local returnCommand=q.current
f.start(returnCommand);f.dispatch(returnCommand,'perform')
local returned=q.current
assert(#q.queue==1 and returned.Type=='ISInventoryTransferAction'and returned.item==razor
 and returned.srcContainer==f.inventory and returned.destContainer==f.source,'earned native restore must precede the exact borrowed return')
f.start(returned);f.dispatch(returned,'perform')
local state=assert(t.ActionQueueSettlement.operationState(body))
assert(#q.queue==0 and razor.container==f.source and f.player.primary==previous and #f.effects==2
 and state.borrowings[1].state=='completed','native return failed to settle exactly one earned tool loan')

local g,old,borrowed,trim,parent=prepared()
local selected=g.tool(812,'Base.Pencil',g.inventory)
local intent=g.env.PZSurvivorToolkit.ActionQueueTidyIntent
local revision=intent.primaryRequestRevision(g.player)
g.env.ISInventoryPaneContextMenu.OnPrimaryWeapon({selected},0)
assert(intent.primaryRequestRevision(g.player)~=revision,'actual explicit primary producer did not retain the later user choice')
local chosen=g.queue.queue[#g.queue.queue]
assert(chosen.Type=='ISEquipWeaponAction'and chosen.item==selected,'explicit native primary callback did not queue its chosen item')
g.dispatch(trim,'perform');g.start(parent);g.dispatch(parent,'perform')
assert(g.queue.current==chosen and #g.queue.queue==1,'automatic restoration overrode the later explicit primary choice')
g.start(chosen);g.dispatch(chosen,'perform')
local remaining=assert(g.env.PZSurvivorToolkit.ActionQueueSettlement.operationState(trim))
assert(g.player.primary==selected and borrowed.container==g.inventory and #g.effects==1 and #g.queue.queue==0
 and remaining.borrowings[1].state=='active','later explicit choice replayed restoration or silently paid the unreturned loan')
print('PASS actual native razor pickup/equip/trim, owned hand restoration and return, and later explicit primary choice')

-- Cancel after the real pickup/equip, while the native trim is active.
-- The retained command gets a fresh operation and owns the single return.
local canceled,oldPrimary,borrowedRazor,active,retained=prepared()
local toolkit=canceled.env.PZSurvivorToolkit
local token=active.toolkitQueueOperation
canceled.env.ISInventoryPaneContextMenu.readItem(canceled.book(812,canceled.inventory),0)
local reader=canceled.queue.queue[#canceled.queue.queue]
assert(reader.Type=='ISReadABook' and reader.toolkitQueueOperation~=token)
local ok,why=toolkit.ActionQueue.cancelOperation(canceled.queue,active)
assert(ok,'active native trim cancellation refused: '..tostring(why))
canceled.stop(active,true)
assert(canceled.queue.current==retained and retained.toolkitQueueOperation~=token
 and canceled.player:getHumanVisual().beard~='Moustache')
canceled.start(retained);canceled.dispatch(retained,'perform')
local reEquip=canceled.queue.current
assert(reEquip and reEquip.Type=='ISEquipWeaponAction' and reEquip.item==oldPrimary)
canceled.start(reEquip);canceled.dispatch(reEquip,'perform')
local command=canceled.queue.current
canceled.start(command);canceled.dispatch(command,'perform')
local transfer=canceled.queue.current
assert(transfer and transfer.Type=='ISInventoryTransferAction' and transfer.item==borrowedRazor)
canceled.start(transfer);canceled.dispatch(transfer,'perform')
assert(canceled.queue.current==reader)
canceled.dispatch(reader,'perform')
assert(#canceled.queue.queue==0 and #canceled.effects==2 and borrowedRazor.container==canceled.source
 and canceled.player.primary==oldPrimary and #toolkit.ActionQueueSettlement.blockedReturns(canceled.player)==0)

-- The container can change after the razor was borrowed. Only the location
-- obligation is waived by Keep; native hand restoration has already finished.
for _, obstacle in ipairs({'unavailable', 'full'}) do
    local run, hammer, tool, grooming, restore = prepared()
    local queue, execution = run.queue, run.env.PZSurvivorToolkit.ActionQueueExecution
    if obstacle == 'unavailable' then run.bag.container = nil else run.source.room = false end
    run.env.ISInventoryPaneContextMenu.readItem(run.book(812, run.inventory), 0)
    local tail = queue.queue[#queue.queue]
    assert(tail.Type == 'ISReadABook')
    run.dispatch(grooming, 'perform')
    run.start(restore); run.dispatch(restore, 'perform')
    local hand = queue.current
    assert(hand.Type == 'ISEquipWeaponAction' and hand.item == hammer)
    run.start(hand); run.dispatch(hand, 'perform')
    local continuation = queue.current
    run.start(continuation); run.dispatch(continuation, 'perform')
    if obstacle == 'full' then
        local transfer = queue.current
        assert(transfer.Type == 'ISInventoryTransferAction' and transfer.item == tool and not transfer:isValid())
        run.remove(transfer)
        queue:tick()
    end
    assert(queue.current == tail and tool.container == run.inventory and run.player.primary == hammer,
        obstacle .. ': blocked return interrupted independent work')
    local debts = execution.blockedReturns(run.player)
    assert(#debts == 1 and debts[1].itemId == tool:getID() and debts[1].state == 'blocked',
        obstacle .. ': missing unpaid return')
    assert(execution.keepReturn(run.player, debts[1].id) and #execution.blockedReturns(run.player) == 0,
        obstacle .. ': cannot keep borrowed razor')
    run.dispatch(tail, 'perform')
    assert(#queue.queue == 0 and #run.effects == 1 and tool.container == run.inventory)
end
