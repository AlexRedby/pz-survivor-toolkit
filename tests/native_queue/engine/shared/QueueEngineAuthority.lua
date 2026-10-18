local Authority, sessions = {}, {}
local selection = require 'QueueTestSelection'
function Authority.cancels(case, player)
    return case=='cancel' or case=='late-continuation' or case=='peer-cancel' and player:getUsername()=='client1'
end
local function count(player)
    local total, values = 0, player:getInventory():getItems()
    for i=0,values:size()-1 do if values:get(i):getFullType()=='Base.ElectronicsScrap' then total=total+1 end end
    return total
end
local function free(square)
    return square and square:isFree(false) and not square:getRoom()
        and square:getSpecialObjects():size()==0 and square:getObjects():size()<=1
end
local function placement(player)
    local point=require('QueueEnergyPlacement')(player)
    for offset=0,4 do
        local x,y,z=point:getX()+1+offset*3,point:getY(),point:getZ()
        local square=getCell():getGridSquare(x,y,z)
        if free(square) and free(getCell():getGridSquare(x-1,y,z)) then
            return square,{x=x-0.5,y=y+0.5,z=z}
        end
    end
    error('No distinct loaded native generator and adjacent standing square')
end
function Authority.prepare(player, case)
    local key=player:getUsername()
    local session=sessions[key]
    if session and session.pending then assert(session.pending.case==case,'out-of-order engine prepare');return session.pending.ids end
    if not session or session.generator:getObjectIndex()==-1 then
        local square,spawn
        if session then square,spawn=session.square,session.spawn else square,spawn=placement(player) end
        for owner,existing in pairs(sessions) do if owner~=key then assert(existing.generator:getSquare()~=square,'peer targets overlap') end end
        local item=assert(instanceItem('Base.Generator'))
        item:setCondition(94)
        session={generator=IsoGenerator.new(item,getCell(),square),verified=session and session.verified or 0,spawn=spawn,square=square}
        sessions[key]=session
    end
    assert(selection.cases[session.verified+1]==case,'unexpected engine case')
    assert(player:getPerkLevel(Perks.Electricity)==0,'fixture requires native Electricity zero')
    assert(count(player)==0,'unexpected ElectronicsScrap before fixture')
    session.generator:setCondition(94)
    local ids={case=case,scraps={},spawn=session.spawn,x=session.generator:getX(),y=session.generator:getY(),z=session.generator:getZ(),
        objectIndex=session.generator:getObjectIndex()}
    local function seed(kind)
        local item=assert(player:getInventory():AddItem(kind),kind)
        if isServer() then sendAddItemToContainer(player:getInventory(),item) end
        return item
    end
    for i=1,2 do ids.scraps[i]=seed('Base.ElectronicsScrap'):getID() end
    local book=seed(case=='repair' and 'Base.BookCarpentry1' or 'Base.BookFirstAid1')
    book:setAlreadyReadPages(book:getNumberOfPages()-1)
    player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
    ids.tail=book:getID()
    local blocker
    if case=='missing-target' then
        blocker=seed('Base.BookFarming1');ids.blocker=blocker:getID()
        blocker:setAlreadyReadPages(blocker:getNumberOfPages()-1)
        player:setAlreadyReadPages(blocker:getFullType(),blocker:getNumberOfPages()-1)
    end
    session.pending={case=case,ids=ids,book=book,blocker=blocker}
    assert(session.generator:getObjectIndex()>=0 and session.generator:getCondition()==94 and count(player)==2,'native generator fixture not ready')
    print('[ENGINE_TEST] PREPARED case='..case..' condition=94 scraps=2 electricity=0 nativeGenerator=true actor='..key)
    print('[ENGINE_TEST] TARGET case='..case..' x='..ids.x..' y='..ids.y..' z='..ids.z..' index='..ids.objectIndex..' actor='..key)
    return ids
end
function Authority.invalidate(player, case)
    local session=assert(sessions[player:getUsername()])
    assert(case=='missing-target' and session.pending and session.pending.case==case,'unexpected target removal')
    assert(not session.pending.removed and session.generator:getCondition()==94 and count(player)==2,'target removal raced repair')
    session.square:transmitRemoveItemFromSquare(session.generator)
    assert(session.generator:getObjectIndex()==-1,'fixture target survived removal')
    session.pending.removed=true
    print('[ENGINE_TEST] TARGET_REMOVED case='..case..' beforeRepair=true actor='..player:getUsername())
    return {case=case,ok=true}
end
function Authority.verify(player, case)
    local session=assert(sessions[player:getUsername()])
    local pending=assert(session.pending)
    assert(pending.case==case,'out-of-order engine verification')
    local enabled=selection.mode=='toolkit'
    local expected=Authority.cancels(case,player) or case=='missing-target'
    expected=expected and 2 or not enabled and selection.kind=='sp' and 1 or 0
    local condition=expected==2 and 94 or expected==1 and 98 or 100
    assert(session.generator:getCondition()==condition,'authoritative generator condition differs')
    assert((session.generator:getObjectIndex()==-1)==(case=='missing-target')
        and (case~='missing-target' or pending.removed),'target availability differs')
    assert(count(player)==expected,'authoritative scrap count differs')
    for i,id in ipairs(pending.ids.scraps) do
        assert((player:getInventory():getItemById(id)~=nil)==(expected==2 or expected==1 and i==2),'exact scrap identity differs')
    end
    assert(player:getInventory():getItemById(pending.ids.tail)==pending.book,'tail identity changed')
    local read=pending.book:getAlreadyReadPages()==pending.book:getNumberOfPages()
    if enabled or case=='repair' and selection.kind=='sp' then assert(read,'authoritative native tail did not finish reading')
    elseif case~='repair' then assert(not read,'native rejected/stopped action unexpectedly preserved tail') end
    local result={case=case,ok=true,condition=condition,scraps=expected,tailRead=read}
    print('[ENGINE_TEST] AUTHORITY case='..case..' condition='..condition..' scraps='..expected..' tailRead='..tostring(read)..' actor='..player:getUsername())
    for _,id in ipairs(pending.ids.scraps) do
        local item=player:getInventory():getItemById(id)
        if item then
            player:getInventory():Remove(item)
            if isServer() then sendRemoveItemFromContainer(player:getInventory(),item) end
        end
    end
    session.pending=nil;session.verified=session.verified+1
    return result
end
return Authority
