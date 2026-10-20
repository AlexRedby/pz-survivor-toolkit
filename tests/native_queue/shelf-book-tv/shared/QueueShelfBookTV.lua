local Fixture = {}

local function countId(container,id)
    local count=0
    local items=container:getItems()
    for i=0,items:size()-1 do
        local item=items:get(i)
        if item:getID()==id then count=count+1 end
        if instanceof(item,'InventoryContainer') then count=count+countId(item:getItemContainer(),id) end
    end
    return count
end

local function free(square)
    return square and square:isFree(false) and not square:getRoom()
        and square:getObjects():size() <= 1 and square:getSpecialObjects():size() == 0
end

function Fixture.prepare(player, case)
    assert(case=='demote-and-control' or case=='worn-bag', 'unknown shelf/TV case')
    local origin = require('QueueEnergyPlacement')(player)
    local y, z = origin:getY(), origin:getZ()
    local shelfSquare, tvSquare = getCell():getGridSquare(origin:getX() - 1, y, z), getCell():getGridSquare(origin:getX() + 1, y, z)
    local generatorSquare = getCell():getGridSquare(origin:getX(), y + 1, z)
    assert(free(shelfSquare) and free(tvSquare) and free(generatorSquare), 'deterministic shelf/TV/power footprint became occupied')

    local generatorItem = assert(instanceItem('Base.Generator'))
    local generator = IsoGenerator.new(generatorItem, getCell(), generatorSquare)
    generator:setCondition(100)
    generator:setFuel(10.0)
    generator:setActivated(true)
    assert(generator:isActivated() and generator:getFuel() > 0, 'fixture generator did not start')

    local shelf = IsoThumpable.new(getCell(), shelfSquare, 'furniture_storage_01_8', false, {})
    shelf:setCanPassThrough(true)
    shelf:setIsContainer(true)
    shelf:setName('Shelf book fixture')
    local source = assert(shelf:getContainer())
    source:setType('shelf')
    source:setCapacity(100)
    source:setExplored(true)
    shelfSquare:AddSpecialObject(shelf)

    local book = assert(source:AddItem('Base.BookCarpentry1'))
    local pages = book:getNumberOfPages()
    assert(pages > 5, 'fixture book has too few pages')
    book:setAlreadyReadPages(pages - 4)
    player:setAlreadyReadPages(book:getFullType(), pages - 4)

    local tv = IsoTelevision.new(getCell(), tvSquare, getSprite('appliances_television_01_4'))
    tvSquare:AddSpecialObject(tv)
    local data = assert(tv:getDeviceData())
    data:setMediaType(1)
    data:setIsTurnedOn(false)
    getGameTime():setTimeOfDay(12.0)
    assert(tvSquare:haveElectricity() and data:canBePoweredHere(), 'fixture mains generator did not power the TV square')
    print('[SHELF_TV] POWER_SOURCE generatorIndex='..generator:getObjectIndex()..' active=true fuel='..generator:getFuel()
        ..' tvSquareElectricity=true tvCanBePowered=true replica=false')

    local mediaData=assert(getZomboidRadio():getRecordedMedia():getMediaData('07b0cd73-7563-4699-9fb4-99316a0fc0bd'),
        'Carzone E1 recorded media missing')
    local bag,bagLocation
    local tapeSource=player:getInventory()
    if case=='worn-bag' then
        bag=assert(player:getInventory():AddItem('Base.Bag_Schoolbag'))
        bagLocation=bag:canBeEquipped()
        assert(bagLocation and not player:getWornItem(bagLocation), 'fixture bag slot already occupied')
        player:setWornItem(bagLocation,bag)
        tapeSource=bag:getItemContainer()
        tapeSource:setExplored(true)
    end
    local tape = assert(tapeSource:AddItem('Base.VHS_Retail'))
    tape:setRecordedMediaData(mediaData)
    local tapeIndex,tapeType=tape:getRecordedMediaIndex(),tape:getMediaType()
    assert(tape:isRecordedMedia() and tapeType == data:getMediaType(), 'VHS media type differs from TV')
    if isServer() then
        shelf:transmitCompleteItemToClients()
        tv:transmitCompleteItemToClients()
        if bag then
            sendAddItemToContainer(player:getInventory(), bag)
            sendClothing(player,bagLocation,bag)
        else sendAddItemToContainer(player:getInventory(), tape) end
    end
    player:teleportTo(origin:getX() + 0.5, y + 0.5, z)
    -- Lighting catches up after teleport; the client waits for native readability before starting.
    return {player=player, shelf=shelf, source=source, book=book, tv=tv, data=data, tape=tape,
        mediaIndex=tapeIndex,mediaType=tapeType,generator=generator,bag=bag,bagSource=bag and tapeSource,
        ids={shelf=shelf:getObjectIndex(), book=book:getID(), tape=tape:getID(), mediaIndex=tapeIndex,mediaType=tapeType,
            case=case,bag=bag and bag:getID(),bagLocation=bag and tostring(bagLocation),
            initialPages=pages-4,shelfX=shelfSquare:getX(),shelfY=shelfSquare:getY(),shelfZ=shelfSquare:getZ(),
            generatorIndex=generator:getObjectIndex(),generatorX=generatorSquare:getX(),generatorY=generatorSquare:getY(),generatorZ=generatorSquare:getZ(),
            x=tvSquare:getX(),y=tvSquare:getY(),z=tvSquare:getZ(),pages=pages}}
end

function Fixture.resolve(player, ids)
    local square = getCell():getGridSquare(ids.shelfX, ids.shelfY, ids.shelfZ)
    local shelf
    if square then
        for i=0,square:getSpecialObjects():size()-1 do
            local object=square:getSpecialObjects():get(i)
            if object:getObjectIndex()==ids.shelf and object:getContainer() then shelf=object;break end
        end
    end
    local tvSquare=getCell():getGridSquare(ids.x,ids.y,ids.z)
    local tv
    if tvSquare then
        for i=0,tvSquare:getSpecialObjects():size()-1 do
            local object=tvSquare:getSpecialObjects():get(i)
            if instanceof(object,'IsoTelevision') then tv=object;break end
        end
    end
    local generatorSquare=getCell():getGridSquare(ids.generatorX,ids.generatorY,ids.generatorZ)
    local generator
    if generatorSquare then
        for i=0,generatorSquare:getSpecialObjects():size()-1 do
            local object=generatorSquare:getSpecialObjects():get(i)
            if instanceof(object,'IsoGenerator') and object:getObjectIndex()==ids.generatorIndex then generator=object;break end
        end
    end
    local book=shelf and shelf:getContainer():getItemById(ids.book)
    local bag=ids.bag and player:getInventory():getItemById(ids.bag)
    local tapeSource=bag and bag:getItemContainer() or player:getInventory()
    local tape=tapeSource:getItemById(ids.tape)
    if not shelf or not book or not tv or not tape or not generator then return nil end
    if ids.bag and (not bag or player:getWornItem(bag:canBeEquipped())~=bag) then return nil end
    if bag and bag:getContainer()~=player:getInventory() or tape:getContainer()~=tapeSource then return nil end
    local data=tv:getDeviceData()
    if not generator:isActivated() or generator:getFuel()<=0 or not tvSquare:haveElectricity()
        or not data:canBePoweredHere() then return nil end
    print('[SHELF_TV] POWER_SOURCE generatorIndex='..generator:getObjectIndex()..' active=true fuel='..generator:getFuel()
        ..' tvSquareElectricity=true tvCanBePowered=true replica=true')
    assert(book:getNumberOfPages()==ids.pages and ids.initialPages==ids.pages-4,'replicated exact book page metadata differs')
    book:setAlreadyReadPages(ids.initialPages)
    player:setAlreadyReadPages(book:getFullType(),ids.initialPages)
    return {player=player,shelf=shelf,source=shelf:getContainer(),book=book,tv=tv,data=data,
        tape=tape,mediaIndex=tape:getRecordedMediaIndex(),mediaType=tape:getMediaType(),generator=generator,
        bag=bag,bagSource=bag and tapeSource,ids=ids}
end

function Fixture.pickupArrived(state,insert)
    local root=state.player:getInventory()
    -- getItemById searches nested bags too; the direct owner proves transfer.
    local tape=root:getItemById(state.ids.tape)
    if not tape or tape:getID()~=state.ids.tape or tape:getContainer()~=root then return false end
    -- B42 MP removes the old client object and deserializes a replacement with
    -- the same ID, then natively rebinds direct queued-action item fields.
    if not isClient() and tape~=state.tape or not insert or insert.secondaryItem~=tape
        or tape:getFullType()~=state.tape:getFullType() or not tape:isRecordedMedia()
        or tape:getRecordedMediaIndex()~=state.ids.mediaIndex or tape:getMediaType()~=state.ids.mediaType then return false end
    assert(countId(root,state.ids.tape)==1 and countId(state.bagSource,state.ids.tape)==0,
        'native pickup exact endpoints differ')
    state.pickedTape=tape
    return true
end

function Fixture.bagReceipt(state)
    local bag=assert(state.bag,'worn-bag receipt requires exact fixture bag')
    local root=state.player:getInventory()
    local location=bag:canBeEquipped()
    assert(root:getItemById(state.ids.bag)==bag and bag:getContainer()==root
        and countId(root,state.ids.bag)==1
        and state.player:getWornItem(location)==bag and tostring(location)==state.ids.bagLocation,
        'exact bag identity or worn location changed')
    assert(bag:getItemContainer()==state.bagSource and state.bagSource:getItems():size()==0,
        'fixture worn bag source changed or retained unexpected contents')
    assert(countId(root,state.ids.tape)==0,
        'exact VHS remains in worn bag or inventory')
    return 'bagId='..state.ids.bag..' location='..state.ids.bagLocation
        ..' worn=true root=true sameContainer=true empty=true tapeRemoved=true'
end

function Fixture.captureDurations(pickup,insert,power,play,client)
    -- The native MP transfer constructor waits at -1 until ItemTransaction
    -- supplies its duration. Native create/start may subsequently adjust timers.
    assert(not pickup.action and (client and pickup.maxTime==-1 or not client and pickup.maxTime>0),
        'native pickup constructor duration differs')
    local result={pickup=pickup.maxTime}
    for name,action in pairs({insert=insert,power=power,play=play}) do
        local duration=action:getDuration()
        assert(not action.action and type(duration)=='number' and duration>0 and action.maxTime==duration,
            'native '..name..' constructor duration differs')
        result[name]=duration
    end
    return result
end

function Fixture.verify(state)
    local data=state.tv:getDeviceData()
    assert(state.generator:isActivated() and state.generator:getFuel()>0
        and state.tv:getSquare():haveElectricity() and data:canBePoweredHere(), 'mains generator stopped powering fixture TV')
    local bookId=state.ids.book
    local returnedItem=state.source:getItemById(bookId)
    local returned = returnedItem and returnedItem:getID()==bookId
    local exactCount = 0
    local items=state.source:getItems()
    for i=0,items:size()-1 do if items:get(i):getID()==bookId then exactCount=exactCount+1 end end
    assert(returnedItem and returnedItem:getAlreadyReadPages()==returnedItem:getNumberOfPages(), 'book did not finish after resumption')
    assert(returned and exactCount==1, 'same exact book was not returned exactly once')
    assert(countId(state.player:getInventory(),state.ids.tape)==0 and data:getMediaData(),
        'tape was not debited or TV has no media')
    assert(data:hasMedia() and data:getMediaIndex()==state.mediaIndex and data:getMediaType()==state.mediaType
        and data:getMediaData():getTitleEN()=='Carzone' and data:isPlayingMedia(),
        'inserted Carzone tape is not the playing TV media')
    if state.ids.bag then Fixture.bagReceipt(state) end
    return {pages=returnedItem:getAlreadyReadPages(),returned=returned,exactCount=exactCount,
        tapeDebited=countId(state.player:getInventory(),state.ids.tape)==0,
        mediaIndex=data:getMediaIndex(),mediaType=data:getMediaType(),
        mediaTitle=data:getMediaData():getTitleEN(),playing=data:isPlayingMedia()}
end

return Fixture
