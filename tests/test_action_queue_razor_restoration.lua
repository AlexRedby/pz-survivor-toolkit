-- Native source-backed queue/receipt composition; Java delivery is modeled by
-- the shared fixture. This does not establish live Host transport or rendering.
if not NativeActionRoot then return end
local create=assert(loadfile(ProjectRoot..'/tests/support/borrowing_composition.lua'))()
local originalContains=string.contains
string.contains=originalContains or function(value,part)return value:find(part,1,true)~=nil end
local function prepared(editorEnabled,kind)
 kind=kind or {tool='Base.Razor',body='ISTrimBeard',style='Moustache'}
 local f=create(false,{p4=false,carried=true,razor=true,queue=editorEnabled})
 local e,q,t=f.env,f.queue,f.env.PZSurvivorToolkit
 local previous,secondary
 if kind.empty then secondary=f.tool(810,'Base.Pen',f.inventory)
 elseif kind.required then
  previous=f.tool(810,'Base.StoneWheelSmall',f.inventory)
  previous.isRequiresEquippedBothHands=function()return true end
  secondary=previous
 elseif kind.axeGrip then
  previous=f.tool(810,'Base.Axe',f.inventory)
  previous.class='HandWeapon'
  previous.getSwingAnim=function()return 'Heavy'end
  previous.isTwoHandWeapon=function()return true end
  secondary=kind.axeGrip=='both' and previous or f.tool(814,'Base.Pen',f.inventory)
 else previous=f.tool(810,'Base.Pen',f.inventory) end
 f.player.secondary=secondary
 local razor=f.tool(811,kind.tool)
 f.player.primary=previous
 if kind.body=='ISCutHair'then e.ISCharacterScreen.onCutHair(f.player,kind.style,300)
 else e.ISCharacterScreen.onTrimBeard(f.player,kind.style)end
 local approach,pickup,equip,body,cleanup
 if editorEnabled == false then
  assert(#q.queue==4,kind.tool..' '..kind.body..': editor-off pickup/equip/groom/restore expected; got '..#q.queue)
  pickup,equip,body,cleanup=unpack(q.queue)
 else
  assert(#q.queue==5,kind.tool..' '..kind.body..': expected approach/pickup/equip/groom/owned restoration; got '..#q.queue)
  approach,pickup,equip,body,cleanup=unpack(q.queue)
  assert(t.ActionQueueApproach.isContainer(approach,f.source,f.player))
 end
 assert(pickup.Type=='ISInventoryTransferAction'and equip.Type=='ISEquipWeaponAction'and body.Type==kind.body and body.item==razor and body.maxTime==300)
 assert(pickup.toolkitQueueOperation==equip.toolkitQueueOperation and equip.toolkitQueueOperation==body.toolkitQueueOperation
  and body.toolkitQueueOperation==cleanup.toolkitQueueOperation,'native operation lost its single ownership token')
 local state=assert(t.ActionQueueSettlement.operationState(pickup))
 assert(#state.borrowings==1 and state.borrowings[1].state=='prepare','menu production earned a physical loan')
 if approach then f.start(approach);f.dispatch(approach,'perform') end
 f.start(pickup);f.dispatch(pickup,'perform')
 f.start(equip);f.dispatch(equip,'perform')
 assert(f.player.primary==razor and razor.container==f.inventory,'native preparation did not put the exact borrowed tool in the primary hand')
 state=assert(t.ActionQueueSettlement.operationState(body))
 assert(state.borrowings[1].state=='active','only actual native pickup may earn the carried tool loan')
 f.start(body)
 return f,previous,razor,body,cleanup,secondary
end
for _,kind in ipairs({
 {tool='Base.Razor',body='ISTrimBeard',style='Moustache',axeGrip='both'},
 {tool='Base.Razor',body='ISTrimBeard',style='Moustache',required=true},
 {tool='Base.Scissors',body='ISCutHair',style='Fabian',axeGrip='primary'},
 {tool='Base.Razor',body='ISTrimBeard',style='Moustache'},
 {tool='Base.Scissors',body='ISTrimBeard',style='Moustache'},
 {tool='Base.Scissors',body='ISCutHair',style='Bald',empty=true},
 {tool='Base.Razor',body='ISTrimBeard',style='Moustache',empty=true},
 {tool='Base.Scissors',body='ISCutHair',style='Fabian'},
})do
for _, editorEnabled in ipairs({true, false}) do
 local f,previous,razor,body,cleanup,secondary=prepared(editorEnabled,kind)
 local q,t=f.queue,f.env.PZSurvivorToolkit
 f.dispatch(body,'perform')
 local visual=f.player:getHumanVisual()
 assert((kind.body=='ISTrimBeard'and visual.beard==kind.style or kind.body=='ISCutHair'and visual.hair==kind.style)
  and q.current==cleanup,'native grooming effect or owned cleanup order changed')
 if kind.body=='ISCutHair'then
  assert(f.player.hairGrowthResets==1 and visual.nonAttached==nil,'native haircut growth/model cleanup changed')
  if kind.style=='Bald'then assert(visual.hairColor==visual.naturalHairColor,'native Bald natural hair color was not restored')end
 end
 f.start(cleanup);f.dispatch(cleanup,'perform')
 local restored=q.current
 assert(#q.queue==2 and restored.Type==(kind.empty and 'ISUnequipAction' or 'ISEquipWeaponAction')
  and restored.item==(previous or razor),'owned cleanup must issue one matching hand action')
 f.start(restored);f.dispatch(restored,'perform')
 assert(f.player.primary==previous and f.player.secondary==secondary and razor.container==f.inventory,'hand state or borrowed item location differs before return')
 local returnCommand=q.current
 f.start(returnCommand);f.dispatch(returnCommand,'perform')
 local returned=q.current
 assert(#q.queue==1 and returned.Type=='ISInventoryTransferAction'and returned.item==razor
  and returned.srcContainer==f.inventory and returned.destContainer==f.source,'earned native restore must precede the exact borrowed return')
 f.start(returned);f.dispatch(returned,'perform')
 local state=assert(t.ActionQueueSettlement.operationState(body))
 assert(#q.queue==0 and razor.container==f.source and f.player.primary==previous and #f.effects==2
  and #state.borrowings==1 and state.borrowings[1].state=='completed'
  and f.effects[1].item==razor and f.effects[1].destination==f.inventory
  and f.effects[2].item==razor and f.effects[2].destination==f.source,'native return failed to settle exactly one earned tool loan')
end
end

-- Native equip drops a heavy held item into the world. Neither its old grip
-- nor a one-slot replica of a mandatory grip can authorize an inventory restore.
do
 local f=create(false,{p4=false,carried=true,razor=true})
 local item=f.tool(810,'Base.StoneAnvil',f.inventory)
 item.isRequiresEquippedBothHands=function()return true end
 item.isForceDropHeavyItem=function()return true end
 f.player.primary,f.player.secondary=item,item
 local hands=f.env.PZSurvivorToolkit.ActionQueueEquip.restorationHands
 assert(hands(f.player)==nil)
 f.player.primary,f.player.secondary=nil,nil
 assert(hands(f.player,item,true)==nil)
 item.isForceDropHeavyItem=function()return false end
 f.player.primary=item
 assert(hands(f.player)==nil)
end

-- The native Bald callback also permits a tool-less body. It must run without
-- earning a hand intent, a physical loan, or an owned restoration command.
for _,editorEnabled in ipairs({true,false})do
 local f=create(false,{p4=false,carried=true,razor=true,queue=editorEnabled})
 local previous=f.tool(810,'Base.Pen',f.inventory)
 f.player.primary=previous
 f.env.ISCharacterScreen.onCutHair(f.player,'Bald',300)
 local body=f.queue.current
 assert(#f.queue.queue==1 and body.Type=='ISCutHair'and body.item==nil and body.maxTime==300,
  'tool-less native haircut acquired preparation or restoration work')
 f.start(body);f.dispatch(body,'perform')
 local state=f.env.PZSurvivorToolkit.ActionQueueSettlement.operationState(body)
 assert(#f.queue.queue==0 and #f.effects==0 and f.player.primary==previous
  and f.player:getHumanVisual().hair=='Bald'and(not state or #state.borrowings==0),
  'tool-less native haircut earned a loan or modified the prior hand')
end

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
print('PASS native razor/scissors beard and scissors haircut borrowing, exact hand restoration and return, tool-less isolation, and later primary choice')

-- A secondary-only request is still pending when the older cleanup runs.
-- Restoring a shared grip would overwrite that later choice.
local h,axe,razor,body,cleanup=prepared(true,{tool='Base.Razor',body='ISTrimBeard',style='Moustache',axeGrip='both'})
local pen=h.tool(813,'Base.Pen',h.inventory)
local requests=h.env.PZSurvivorToolkit.ActionQueueTidyIntent
local primaryRevision=requests.primaryRequestRevision(h.player)
local bothRevision=requests.handRequestRevision(h.player,true)
h.env.ISInventoryPaneContextMenu.OnSecondWeapon({pen},0)
local choice=h.queue.queue[#h.queue.queue]
assert(choice.item==pen and not choice.primary and requests.primaryRequestRevision(h.player)==primaryRevision
 and requests.handRequestRevision(h.player,true)~=bothRevision)
h.dispatch(body,'perform');h.start(cleanup);h.dispatch(cleanup,'perform')
assert(h.queue.current==choice and #h.queue.queue==1)
h.start(choice);h.dispatch(choice,'perform')
assert(h.player.secondary==pen and h.player.primary==razor and razor.container==h.inventory and axe.container==h.inventory)

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
for _, obstacle in ipairs({'unavailable', 'full', 'full-empty-hand'}) do
    local empty = obstacle == 'full-empty-hand'
    local kind = empty and {tool='Base.Razor', body='ISTrimBeard', style='Moustache', empty=true} or nil
    local run, hammer, tool, grooming, restore, secondary = prepared(not empty, kind)
    local queue, execution = run.queue, run.env.PZSurvivorToolkit.ActionQueueExecution
    if obstacle == 'unavailable' then run.bag.container = nil else run.source.room = false end
    run.env.ISInventoryPaneContextMenu.readItem(run.book(812, run.inventory), 0)
    local tail = queue.queue[#queue.queue]
    assert(tail.Type == 'ISReadABook')
    run.dispatch(grooming, 'perform')
    run.start(restore); run.dispatch(restore, 'perform')
    local hand = queue.current
    assert(hand.Type == (empty and 'ISUnequipAction' or 'ISEquipWeaponAction') and hand.item == (hammer or tool))
    run.start(hand); run.dispatch(hand, 'perform')
    local continuation = queue.current
    run.start(continuation); run.dispatch(continuation, 'perform')
    if obstacle ~= 'unavailable' then
        local transfer = queue.current
        assert(transfer.Type == 'ISInventoryTransferAction' and transfer.item == tool and not transfer:isValid())
        run.remove(transfer)
        queue:tick()
    end
    assert(queue.current == tail and tool.container == run.inventory and run.player.primary == hammer and run.player.secondary == secondary,
        obstacle .. ': blocked return interrupted independent work')
    local debts = execution.blockedReturns(run.player)
    assert(#debts == 1 and debts[1].itemId == tool:getID() and debts[1].state == 'blocked',
        obstacle .. ': missing unpaid return')
    assert(execution.keepReturn(run.player, debts[1].id) and #execution.blockedReturns(run.player) == 0,
        obstacle .. ': cannot keep borrowed razor')
    run.dispatch(tail, 'perform')
    assert(#queue.queue == 0 and #run.effects == 1 and tool.container == run.inventory)
end

string.contains=originalContains
