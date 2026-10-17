local Authority, sessions = {}, {}
local selection = require 'QueueTestSelection'
local function count(player)
    local total, values = 0, player:getInventory():getItems()
    for i=0,values:size()-1 do if values:get(i):getFullType()=='Base.ElectronicsScrap' then total=total+1 end end
    return total
end
function Authority.prepare(player, case)
    local key=player:getUsername()
    local session=sessions[key]
    if not session then
        local point=require('QueueEnergyPlacement')(player)
        local square=assert(getCell():getGridSquare(point:getX()+1,point:getY(),point:getZ()))
        local item=assert(instanceItem('Base.Generator'))
        item:setCondition(94)
        session={generator=IsoGenerator.new(item,getCell(),square),verified=0,
            spawn={x=point:getX()+0.5,y=point:getY()+0.5,z=point:getZ()}}
        sessions[key]=session
    end
    if session.pending then assert(session.pending.case==case,'out-of-order engine prepare');return session.pending.ids end
    assert(selection.cases[session.verified+1]==case,'unexpected engine case')
    assert(player:getPerkLevel(Perks.Electricity)==0,'fixture requires native Electricity zero')
    assert(count(player)==0,'unexpected ElectronicsScrap before fixture')
    session.generator:setCondition(94)
    local ids={case=case,scraps={},spawn=session.spawn,x=session.generator:getX(),y=session.generator:getY(),z=session.generator:getZ()}
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
    session.pending={case=case,ids=ids,book=book}
    assert(session.generator:getObjectIndex()>=0 and session.generator:getCondition()==94 and count(player)==2,'native generator fixture not ready')
    print('[ENGINE_TEST] PREPARED case='..case..' condition=94 scraps=2 electricity=0 nativeGenerator=true')
    return ids
end
function Authority.verify(player, case)
    local session=assert(sessions[player:getUsername()])
    local pending=assert(session.pending)
    assert(pending.case==case,'out-of-order engine verification')
    local expected=case=='repair' and 0 or 2
    assert(session.generator:getCondition()==(case=='repair' and 100 or 94),'authoritative generator condition differs')
    assert(count(player)==expected,'authoritative scrap count differs')
    for _,id in ipairs(pending.ids.scraps) do
        assert((player:getInventory():getItemById(id)~=nil)==(expected==2),'exact scrap identity differs')
    end
    assert(player:getInventory():getItemById(pending.ids.tail)==pending.book,'tail identity changed')
    assert(pending.book:getAlreadyReadPages()==pending.book:getNumberOfPages(),'authoritative native tail did not finish reading')
    local result={case=case,ok=true,condition=session.generator:getCondition(),scraps=expected,tailRead=true}
    print('[ENGINE_TEST] AUTHORITY case='..case..' condition='..result.condition..' scraps='..expected..' tailRead=true')
    session.pending=nil;session.verified=session.verified+1
    return result
end
return Authority
