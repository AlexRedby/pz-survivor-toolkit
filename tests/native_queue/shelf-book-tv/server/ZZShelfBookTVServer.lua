local Fixture=require 'QueueShelfBookTV'
local sessions={}
local progressWaiting={}
local MODULE='ShelfBookTVTest'

local function progress(player,request)
    local key=player:getUsername()
    local state=assert(sessions[key],'progress receipt has no prepared shelf/TV state')
    assert(request.book==state.ids.book and request.pagesBefore==state.ids.pages-4,'progress request identity/baseline differs')
    local item=player:getInventory():getItemById(state.ids.book)
    local pages=item and item:getAlreadyReadPages()
    if item and item:getID()==state.ids.book and pages>request.pagesBefore and pages<item:getNumberOfPages() then
        print('[SHELF_TV] AUTH_PROGRESS pagesBefore='..request.pagesBefore..' pagesCommitted='..pages..' actor='..key)
        sendServerCommand(player,MODULE,'Progressed',{ok=true,pages=pages})
        progressWaiting[key]=nil
        return true
    end
    progressWaiting[key]={player=player,request=request}
    return false
end

local function execute(command,player,args)
    local key=player:getUsername()
    if command=='Prepare' then
        assert((args.case=='demote-and-control' or args.case=='worn-bag') and not sessions[key],'unexpected or duplicate shelf/TV preparation')
        local state=Fixture.prepare(player,args.case)
        sessions[key]=state
        print('[SHELF_TV] PREPARED shelfId='..state.ids.shelf..' bookId='..state.ids.book
            ..' tv='..state.ids.x..','..state.ids.y..','..state.ids.z..' tapeId='..state.ids.tape
            ..' mediaIndex='..state.ids.mediaIndex..' mediaType='..state.ids.mediaType..' power=electric daylight=true')
        if state.bag then
            print('[SHELF_TV] BAG_PREPARED bagId='..state.ids.bag..' location='..state.ids.bagLocation
                ..' tapeId='..state.ids.tape..' worn=true root=true tapeInBag=true')
        end
        sendServerCommand(player,MODULE,'Prepared',{ok=true,ids=state.ids})
    elseif command=='Progress' then
        progress(player,args)
    elseif command=='Verify' then
        local state=assert(sessions[key],'missing server-owned shelf/TV state')
        assert(args.case==state.ids.case and args.ids.book==state.ids.book and args.ids.bag==state.ids.bag
            and args.ids.tape==state.ids.tape and args.ids.shelf==state.ids.shelf,'client receipt identity differs')
        local value=Fixture.verify(state)
        local result={ok=true,bookReturned=value.returned,exactCount=value.exactCount,
            tapeRemoved=value.tapeDebited,mediaIndex=value.mediaIndex,mediaType=value.mediaType,
            tvMedia=value.mediaTitle,playing=value.playing}
        print('[SHELF_TV] AUTHORITY pagesComplete=true bookReturned='..tostring(value.returned)
            ..' exactBookCount='..value.exactCount..' tapeRemoved='..tostring(value.tapeDebited)
            ..' mediaIndex='..value.mediaIndex..' mediaType='..value.mediaType
            ..' tvMedia='..value.mediaTitle..' playing='..tostring(value.playing)..' actor='..key)
        if state.bag then
            result.bagReceipt=Fixture.bagReceipt(state)
            print('[SHELF_TV] BAG_AUTHORITY '..result.bagReceipt..' actor='..key)
        end
        sessions[key]=nil
        sendServerCommand(player,MODULE,'Verified',result)
    else
        error('unknown shelf/TV command '..tostring(command))
    end
end

Events.OnClientCommand.Add(function(module,command,player,args)
    if module~=MODULE then return end
    local ok,err=pcall(execute,command,player,args)
    if not ok then
        print('[QUEUE_TEST] FAIL shelf-book-tv server '..tostring(err))
        sendServerCommand(player,MODULE,command=='Prepare' and 'Prepared' or 'Verified',{ok=false,error=tostring(err)})
    end
end)

Events.OnTick.Add(function()
    for key,pending in pairs(progressWaiting) do
        local ok,done=pcall(progress,pending.player,pending.request)
        if not ok then
            progressWaiting[key]=nil
            print('[QUEUE_TEST] FAIL shelf-book-tv server progress '..tostring(done))
            sendServerCommand(pending.player,MODULE,'Progressed',{ok=false,error=tostring(done)})
        elseif done then progressWaiting[key]=nil end
    end
end)
