if not NativeActionRoot then print('Book controls SKIP (pass --native-action-root).');return end

-- Policy-only matrix: Java ownership/start state and container facts are explicit.
-- This does not simulate a producer, native stop acknowledgement or a UI gesture.
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
f.native('shared/RadioCom/ISRadioAction.lua')
f.native('shared/TimedActions/ISEquipWeaponAction.lua')
isClient=function()return false end
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
local policy=f.project('ActionQueuePolicy')
local player=f.player
player.class='IsoPlayer'
local function container(parent,bag)
    return {class='ItemContainer',getType=function()return 'container' end,
        getParent=function()return parent end,getContainingItem=function()return bag end,
        getAcceptItemFunction=function(self)return self.acceptItem end}
end
local root=container(player)
player.inventory=root
local function runningBook(kind)
    return f.action(ISReadABook,{item=f.item(kind),action={
        isStarted=function()return true end,finished=function()return false end,
        isForceComplete=function()return false end}})
end
local function volume()
    return f.action(ISRadioAction,{mode='SetVolume',device={class='IsoTelevision'}})
end
local sources={root=root,shelf=container({class='IsoObject'})}
local bag={class='InventoryContainer',getID=function()return 100000 end,
    getFullType=function()return 'Base.Bag_Schoolbag' end,getContainer=function()return root end}
sources.bag=container(nil,bag)
for _,kind in ipairs({'Base.BookFirstAid1','Base.Book','Base.Magazine'})do
    for _,sourceName in ipairs({'root','shelf','bag'})do
        local reader,later=runningBook(kind),volume()
        local returning
        if sourceName~='root' then
            returning=f.action(ISInventoryTransferAction,{item=reader.item,
                srcContainer=root,destContainer=sources[sourceName],allowMissingItems=true})
            returning.toolkitQueueOperation=reader.toolkitQueueOperation
        end
        local q=returning and f.queue(reader,returning,later)or f.queue(reader,later)
        assert(not policy.cancelReason(q,reader),'active native book body blocked: '..kind..'/'..sourceName)
        assert(not policy.cancelOperationReason(q,reader),'native book operation blocked: '..kind..'/'..sourceName)
        assert(not policy.moveReason(q,later,reader),'native volume cannot preempt book: '..kind..'/'..sourceName)

        -- A foreign neighbor has no declared footprint. The body stop remains
        -- known, while removing or crossing an entire compound retains its guard.
        local unknown=f.action(ISBaseTimedAction:derive('BookControlsUnknown'))
        table.insert(q.queue,returning and 3 or 2,unknown)
        assert(not policy.cancelReason(q,reader),'foreign tail disabled the isolated reader stop')
        local decision=policy.evaluateCancel(q,reader,true)
        assert(not decision.allowed and decision.blocker==unknown and decision.reason=='edit_unknown',
            'whole-operation rejection must identify its unknown neighbor')
        assert(policy.moveReason(q,later,reader)=='move_dependent',
            'foreign crossed action must not acquire edit permission')
    end
end

for _,endpoint in ipairs({'source','destination'})do
    local reader,later=runningBook('Base.BookFirstAid1'),volume()
    local destination=container({class='IsoObject'})
    local returning=f.action(ISInventoryTransferAction,{item=reader.item,
        srcContainer=root,destContainer=destination,allowMissingItems=true})
    returning.toolkitQueueOperation=reader.toolkitQueueOperation
    local q=f.queue(reader,returning,later)
    local filtered=endpoint=='source'and root or destination
    local calls=0
    filtered.acceptItem=function()calls=calls+1;return true end
    assert(not policy.cancelReason(q,reader),'container filter disabled the isolated reader stop')
    local contract=policy.inspect(returning)
    assert(contract and contract.knownInputs==false and contract.cancelOperation==false,
        'callback-filter endpoint must retain its explicit unsupported-transfer contract')
    assert(policy.cancelOperationReason(q,reader)=='operation_dependent')
    assert(policy.moveReason(q,later,reader)=='move_dependent')
    assert(calls==0,'permission inspection must never execute container acceptance callbacks')
    filtered.acceptItem=nil
    assert(not policy.cancelOperationReason(q,reader)and not policy.moveReason(q,later,reader),
        'removing the unsupported callback must restore the ordinary book controls')
end

do
    local reader,later=runningBook('Base.BookFirstAid1'),volume()
    local q=f.queue(reader,later)
    reader.onCompleteFunc=function()error('permission checks must not invoke foreign callbacks')end
    assert(policy.evaluateCancel(q,reader).reason=='edit_unknown')
    assert(policy.moveReason(q,later,reader)=='move_active')
end

do
    -- Exact plain-root equipment witness: the stock completion equips
    -- a non-activatable plain item from root into empty hands. No worn/back
    -- clothing, force-dropped item or inventory mutation participates.
    local pen=f.item('Base.Pen')
    pen.canBeActivated=function()return false end
    pen.getCurrentUsesFloat=function()return 1 end
    player.getPrimaryHandItem=function(self)return self.primaryHand end
    player.getSecondaryHandItem=function(self)return self.secondaryHand end
    player.setPrimaryHandItem=function(self,item)self.primaryHand=item end
    player.setSecondaryHandItem=function(self,item)self.secondaryHand=item end
    player.getClothingItem_Back=function()end
    player.isEquippedClothing=function()return false end
    player.getCurrentSquare=function()return {} end
    getPlayerInventory=function()return {refreshBackpacks=function()end}end
    isServer=function()return false end
    root.Remove=function()error('plain root equip cannot remove inventory items')end
    root.AddItem=function()error('plain root equip cannot add inventory items')end
    local reader=runningBook('Base.BookFirstAid1')
    local equip=f.action(ISEquipWeaponAction,{item=pen,primary=true,twoHands=false})
    local q=f.queue(reader,equip)
    assert(not policy.moveReason(q,equip,reader),'root reader must allow independent root equipment')
    assert(not policy.cancelOperationReason(q,reader),'root reader cancellation must allow independent root equipment')
    local returning=f.action(ISInventoryTransferAction,{item=reader.item,
        srcContainer=root,destContainer=sources.bag,allowMissingItems=true})
    returning.toolkitQueueOperation=reader.toolkitQueueOperation
    q=f.queue(reader,returning,equip)
    local decision=policy.evaluateMove(q,equip,reader)
    assert(not decision.allowed and decision.reason=='container_capacity' and decision.resource==root,
        'record the existing blanket equipment/return capacity restriction')
    local cancellation=policy.evaluateCancel(q,reader,true)
    assert(not cancellation.allowed and cancellation.reason=='container_capacity' and cancellation.resource==root,
        'the same equipment/return gate also disables the borrowed-reader header cancel')
    assert(not policy.cancelReason(q,reader),'the isolated reader child stop retains its native permission')
    local beforePen,beforeBook=pen:getContainer(),reader.item:getContainer()
    assert(ISEquipWeaponAction.complete(equip))
    assert(player.primaryHand==pen and player.secondaryHand==nil)
    assert(pen:getContainer()==beforePen and reader.item:getContainer()==beforeBook,
        'native plain equip witness must preserve both root inventory endpoints')
    player.primaryHand=nil
end
do
    local reader,later=runningBook('Base.BookFirstAid1'),volume()
    local returning=f.action(ISInventoryTransferAction,{item=reader.item,srcContainer=root,
        destContainer=sources.bag,allowMissingItems=true})
    returning.toolkitQueueOperation=reader.toolkitQueueOperation
    local q=f.queue(reader,returning,later)
    assert(policy.returnFailureIndependent(q,returning),'disjoint device tail must qualify without execution recursion')
    q.queue[3]=runningBook('Base.BookFirstAid1');q.queue[3].item=reader.item
    assert(not policy.returnFailureIndependent(q,returning),'exact book consumer cannot run after a failed return')
    q.queue[3]=f.action(ISBaseTimedAction:derive('UnknownReturnTail'))
    assert(not policy.returnFailureIndependent(q,returning),'unknown suffix cannot gain isolated-failure authority')
    q.queue[3]=f.action(ISInventoryTransferAction,{item=f.item('Base.Pen'),srcContainer=root,destContainer=sources.bag})
    assert(not policy.returnFailureIndependent(q,returning),'future capacity-sharing transfers need their own contracts')
end
print('Book controls: root/shelf/carried-bag, skill/generic literature, body/group and unknown/filter guards passed.')
