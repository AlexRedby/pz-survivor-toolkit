require 'PZSurvivorToolkit/ActionQueuePanel'
require 'ISUI/ISInventoryPaneContextMenu'
require 'RadioCom/ISRadioWindow'
local Fixture=require 'QueueShelfBookTV'
local config=require 'QueueTestSelection'
local Toolkit=PZSurvivorToolkit
local MARK='[SHELF_TV] '
local started,done,phase=false,false,'prepare'
local ids,state,window,panel,reader,power,insert,play,receipt,progressReceipt
local initialPages,committedPages,seenTVStart=nil,nil,false
local resumedLogged,powerStarted,powerSeen,insertStarted,insertSeen,playStarted,playSeen=false,false,false,false,false,false,false
local readerOperation,resumedReader
local since,idleSince=0,nil
local mediaProbeInstalled,firstNilMediaLogged=false,false
local lastMediaProbe,lastReadingProbe,lastFlushProbe

local function pack(...) return {n=select('#',...),...} end
local function filename(callback)
    if type(getFilenameOfClosure)~='function' or type(callback)~='function' then return 'unknown' end
    local ok,value=pcall(getFilenameOfClosure,callback)
    return ok and tostring(value) or 'unknown'
end
local function installMediaProbe()
    if mediaProbeInstalled then return end
    mediaProbeInstalled=true
    local media=Toolkit.ActionQueueMedia
    if media and type(media.completionState)=='function' then
        local original=media.completionState
        media.completionState=function(action,record,...)
            local values=pack(original(action,record,...))
            local result=values[1]
            local saved=record
            local character=action and action.character
            local root=character and character:getInventory()
            local data=action and action.deviceData
            local tv=saved and saved.television
            local square=action and action.parameter
            local readingRecord=action and action.toolkitReadingMove
            local ownerTV=data and data:getParent()
            local squareData=square and square:getDeviceData()
            local signature=table.concat({tostring(result),
                tostring(saved and saved.action==action),tostring(saved and saved.character==character),
                tostring(saved and saved.tape==action.secondaryItem),tostring(saved and saved.data==data),
                tostring(saved and saved.parameter==action.parameter),tostring(saved and saved.root==root),
                tostring(readingRecord and readingRecord.operation==action.toolkitQueueOperation),
                tostring(ownerTV==tv),tostring(tv and tv:getDeviceData()==data),tostring(squareData==data),
                tostring(action and action.action),tostring(action and action.maxTime),
                tostring(action and action.isRemove),tostring(action and action.stopOnWalk),
                tostring(action and action.stopOnRun),tostring(action and action.ignoreHandsWounds),
                tostring(action and action.onStartFunc),tostring(action and action.onCompleteFunc),
                tostring(action and action.onCancelFunc),tostring(action and action.onFailFunc),
                tostring(action and action.additionalTest),tostring(action and action.retriggerLastAction),
                tostring(action and getmetatable(action)==ISDeviceMediaAction),
                tostring(action and action:isStarted()),
                tostring(saved and saved.mediaIndex),tostring(saved and saved.mediaType),
                tostring(data and data:getIsTurnedOn()),tostring(data and data:hasMedia()),
                tostring(data and data:getMediaIndex()),tostring(data and data:getMediaType()),
                tostring(data and data:isPlayingMedia()),tostring(tv and tv:getObjectIndex()),
                tostring(tv and tv:getSquare()==(saved and saved.parameter))},'|')
            if signature~=lastMediaProbe then
                lastMediaProbe=signature
                print(MARK..'MEDIA_COMPLETION result='..tostring(result)
                    ..' receiptAction='..tostring(saved and saved.action==action)
                    ..' character='..tostring(saved and saved.character==character)
                    ..' tape='..tostring(saved and saved.tape==action.secondaryItem)
                    ..' data='..tostring(saved and saved.data==data)
                    ..' parameter='..tostring(saved and saved.parameter==action.parameter)
                    ..' root='..tostring(saved and saved.root==root)
                    ..' operation='..tostring(readingRecord and readingRecord.operation==action.toolkitQueueOperation)
                    ..' television='..tostring(ownerTV==tv)
                    ..' tvData='..tostring(tv and tv:getDeviceData()==data)
                    ..' squareData='..tostring(squareData==data)
                    ..' tapeId='..tostring(saved and saved.tape and saved.tape:getID())
                    ..' mediaIndexExpected='..tostring(saved and saved.mediaIndex)
                    ..' mediaTypeExpected='..tostring(saved and saved.mediaType)
                    ..' started='..tostring(action and action.action~=nil)
                    ..' maxTime='..tostring(action and action.maxTime)
                    ..' isRemove='..tostring(action and action.isRemove)
                    ..' stopOnWalk='..tostring(action and action.stopOnWalk)
                    ..' stopOnRun='..tostring(action and action.stopOnRun)
                    ..' ignoreHandsWounds='..tostring(action and action.ignoreHandsWounds)
                    ..' onStart='..tostring(action and action.onStartFunc)
                    ..' onComplete='..tostring(action and action.onCompleteFunc)
                    ..' onCancel='..tostring(action and action.onCancelFunc)
                    ..' onFail='..tostring(action and action.onFailFunc)
                    ..' additionalTest='..tostring(action and action.additionalTest)
                    ..' retrigger='..tostring(action and action.retriggerLastAction)
                    ..' nativeMetatable='..tostring(action and getmetatable(action)==ISDeviceMediaAction)
                    ..' nativeStarted='..tostring(action and action:isStarted())
                    ..' mediaInstalled='..tostring(media.isInstalled and media.isInstalled())
                    ..' turnedOn='..tostring(data and data:getIsTurnedOn())
                    ..' hasMedia='..tostring(data and data:hasMedia())
                    ..' mediaIndex='..tostring(data and data:getMediaIndex())
                    ..' mediaType='..tostring(data and data:getMediaType())
                    ..' playing='..tostring(data and data:isPlayingMedia()))
            end
            if result==nil and not firstNilMediaLogged then
                firstNilMediaLogged=true
                local methods={}
                for name,callback in pairs(ISDeviceMediaAction or {}) do
                    if type(callback)=='function' then methods[#methods+1]=tostring(name)..'@'..filename(callback) end
                end
                for name,callback in pairs(action or {}) do
                    if type(callback)=='function' then methods[#methods+1]='instance.'..tostring(name)..'@'..filename(callback) end
                end
                table.sort(methods)
                print(MARK..'MEDIA_NIL_METHODS '..table.concat(methods,','))
            end
            return unpack(values,1,values.n)
        end
    end
    local reading=Toolkit.ActionQueueReading
    if reading and type(reading.mediaCompletionState)=='function' then
        local original=reading.mediaCompletionState
        reading.mediaCompletionState=function(q,action,...)
            local values=pack(original(q,action,...))
            local result=values[1]
            local record=action and action.toolkitReadingMove
            local wait=record and record.completion
            local ack=Toolkit.ActionQueueAcknowledgements
            local ackState=ack and wait and ack.state(action,wait.receipt)
            local freshReceipt=ack and result==nil and record and record.kind=='media' and ack.capture(action)
            local freshAckState=freshReceipt and ack.state(action,freshReceipt)
            local signature=table.concat({tostring(result),tostring(record and record.kind),
                tostring(wait~=nil),tostring(ackState),tostring(wait and wait.native==action.action),
                tostring(wait and wait.generation),tostring(q and q.toolkitOperationGeneration),
                tostring(freshReceipt~=nil),tostring(freshAckState)},'|')
            if (result=='failed' or result=='waiting' or wait or result==nil and record and record.kind=='media')
                and signature~=lastReadingProbe then
                lastReadingProbe=signature
                print(MARK..'READING_COMPLETION result='..tostring(result)
                    ..' kind='..tostring(record and record.kind)
                    ..' waitInitialized='..tostring(wait~=nil)
                    ..' ack='..tostring(ackState)
                    ..' nativeSame='..tostring(wait and wait.native==action.action)
                    ..' generation='..tostring(wait and wait.generation)
                    ..' queueGeneration='..tostring(q and q.toolkitOperationGeneration)
                    ..' freshAckCaptured='..tostring(freshReceipt~=nil)
                    ..' freshAck='..tostring(freshAckState))
            end
            return unpack(values,1,values.n)
        end
    end
    local lifecycle=Toolkit.ActionQueueLifecycle
    if lifecycle and type(lifecycle.flush)=='function' then
        local original=lifecycle.flush
        lifecycle.flush=function(q,...)
            local values=pack(original(q,...))
            local result,action=values[1],values[2]
            local signature=tostring(result)..'|'..tostring(action and action.Type)..'|'
                ..tostring(q and q.toolkitCancel==action)
            if (result=='failed' or result=='waiting') and signature~=lastFlushProbe then
                lastFlushProbe=signature
                print(MARK..'LIFECYCLE_FLUSH result='..tostring(result)
                    ..' type='..tostring(action and action.Type)
                    ..' isReader='..tostring(action and action.Type=='ISReadABook')
                    ..' cancelOwned='..tostring(q and q.toolkitCancel==action))
            end
            return unpack(values,1,values.n)
        end
    end
end

local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()) end
local function exactBook()
    return getPlayer():getInventory():getItemById(ids.book) or state.source:getItemById(ids.book)
end
local function findPanel(tv)
    local win=ISRadioWindow.activate(getPlayer(),tv)
    for _,module in ipairs(win.modules) do
        local sub=module.element and module.element.subpanel
        if sub and getmetatable(sub)==RWMMergedTV then return win,sub end
    end
    error('selected pack did not expose actual RWMMergedTV panel')
end
local function queuedActions()
    local q=queue();local out={}
    if q.current then out[#out+1]=q.current end
    for _,action in ipairs(q.queue) do out[#out+1]=action end
    return out
end
local function observeTVEffects()
    if power:isStarted() then powerStarted=true end
    if powerStarted and state.data:getIsTurnedOn() and not powerSeen then
        powerSeen=true;print(MARK..'POWER_EFFECT command=ToggleOnOff turnedOn=true')
    end
    if insert:isStarted() and insert.secondaryItem and insert.secondaryItem:getID()==state.ids.tape then insertStarted=true end
    if insertStarted and state.data:hasMedia() and state.data:getMediaIndex()==state.mediaIndex
        and state.data:getMediaType()==state.mediaType and not insertSeen then
        insertSeen=true;print(MARK..'INSERT_EFFECT command=ISDeviceMediaAction exactTape=true mediaIndex='..state.mediaIndex..' mediaType='..state.mediaType)
    end
    if play:isStarted() then playStarted=true end
    if playStarted and state.data:isPlayingMedia() and state.data:getMediaIndex()==state.mediaIndex
        and state.data:getMediaType()==state.mediaType and not playSeen then
        playSeen=true;print(MARK..'PLAY_EFFECT command=TogglePlayMedia mediaPlaying=true')
    end
end
local function observationDiagnostic(q)
    local current=q.current and q.current.Type or 'none'
    local queued={}
    for _,action in ipairs(q.queue) do queued[#queued+1]=tostring(action.Type) end
    local data=state.data
    local owner=state.tape:getContainer()
    local inventoryTape=getPlayer():getInventory():getItemById(ids.tape)
    print(MARK..'OBSERVATION_TIMEOUT current='..current..' queued='..table.concat(queued,',')
        ..' actionStarted='..tostring(powerStarted)..','..tostring(insertStarted)..','..tostring(playStarted)
        ..' nativeStarted='..tostring(power:isStarted())..','..tostring(insert:isStarted())..','..tostring(play:isStarted())
        ..' effects='..tostring(powerSeen)..','..tostring(insertSeen)..','..tostring(playSeen)
        ..' turnedOn='..tostring(data:getIsTurnedOn())..' hasMedia='..tostring(data:hasMedia())
        ..' mediaIndex='..tostring(data:getMediaIndex())..' mediaType='..tostring(data:getMediaType())
        ..' playing='..tostring(data:isPlayingMedia())
        ..' exactTapeInInventory='..tostring(inventoryTape~=nil and inventoryTape:getID()==ids.tape)
        ..' exactCommandTape='..tostring(insert.secondaryItem and insert.secondaryItem:getID()==ids.tape)
        ..' tapeOwner='..tostring(owner and owner:getType() or 'none'))
end
local function traceNativeInsertion(action)
    if config.mode~='native' then return end
    local valid,stop,perform=action.isValid,action.stop,action.perform
    local rejected=false
    action.isValid=function(self,...)
        local result=valid(self,...)
        if not result and not rejected then
            rejected=true
            print(MARK..'NATIVE_INSERT_INVALID started='..tostring(self:isStarted())
                ..' current='..tostring(queue().current==self)
                ..' hasMedia='..tostring(self.deviceData:hasMedia())
                ..' mediaIndex='..tostring(self.deviceData:getMediaIndex())
                ..' expectedMediaIndex='..tostring(state.mediaIndex)
                ..' exactTapeInInventory='..tostring(getPlayer():getInventory():getItemById(ids.tape)~=nil))
        end
        return result
    end
    action.stop=function(self,...)
        print(MARK..'NATIVE_INSERT_STOP validityRejected='..tostring(rejected)..' queued='..#queue().queue)
        return stop(self,...)
    end
    action.perform=function(self,...)
        print(MARK..'NATIVE_INSERT_PERFORM validityRejected='..tostring(rejected)..' queued='..#queue().queue)
        return perform(self,...)
    end
end
local function createTVCommands()
    window,panel=findPanel(state.tv)
    panel:toggleOnOff()
    power=assert(queue().queue[#queue().queue],'RWMMergedTV power command was not queued')
    panel:addMediaAux(state.tape)
    insert=assert(queue().queue[#queue().queue],'RWMMergedTV media insertion was not queued')
    panel:togglePlayMedia()
    play=assert(queue().queue[#queue().queue],'RWMMergedTV play command was not queued')
    assert(power.Type=='ISRadioAction' and power.mode=='ToggleOnOff'
        and insert.Type=='ISDeviceMediaAction' and insert.secondaryItem==state.tape
        and play.Type=='ISRadioAction' and play.mode=='TogglePlayMedia','native TV command identities/order differ')
    traceNativeInsertion(insert)
    print(MARK..'COMMANDS power=ISRadioAction insert=ISDeviceMediaAction play=ISRadioAction')
end
local function queueTV()
    assert(committedPages>initialPages and reader==queue().current,'committed reading progress/current action changed before TV queueing')
    print(MARK..'PROGRESS authority='..(config.kind=='mp' and 'server' or 'local')
        ..' pagesBefore='..initialPages..' pagesCommitted='..committedPages)
    print(MARK..'READ started=true pagesBefore='..initialPages..' pagesCommitted='..committedPages)
    createTVCommands()
    local actions=queuedActions();local pIndex,iIndex,playIndex
    for index,action in ipairs(actions) do
        if action==power then pIndex=index elseif action==insert then iIndex=index elseif action==play then playIndex=index end
    end
    assert(pIndex and iIndex and playIndex and pIndex<iIndex and iIndex<playIndex,'TV commands were not queued separately in power/insert/play order')
    if config.mode=='toolkit' then
        local accepted,reason=Toolkit.ActionQueue.move(queue(),reader,play,true)
        assert(accepted,'book demotion failed: '..tostring(reason))
        print(MARK..'PROMOTED current=ISReadABook target=ISRadioAction after=true accepted=true')
    else
        print(MARK..'CONTROL queueOff=true naturalReadBeforeTV=true')
    end
    phase='running'
end
local function finish()
    local value=Fixture.verify(state)
    if config.kind=='mp' then
        sendClientCommand('ShelfBookTVTest','Verify',{case='demote-and-control',ids=ids})
        phase='authority';return
    end
    assert(value.pages==ids.pages and value.exactCount==1 and value.tapeDebited
        and value.mediaTitle=='Carzone' and value.playing,'SP exact final receipt differs')
    print(MARK..'RETURN sameBook=true exactCount=1')
    print(MARK..'MEDIA tapeDebited=true exactTape=true mediaIndex='..value.mediaIndex..' mediaType='..value.mediaType..' title=Carzone playing=true')
    print(MARK..'COMPLETE case=demote-and-control');done=true
end

Events.OnServerCommand.Add(function(module,command,args)
    if module~='ShelfBookTVTest' then return end
    assert(args.ok~=false,args.error)
    if command=='Prepared' then ids=args.ids;phase='wait-fixture';since=getTimestampMs()
    elseif command=='Progressed' then progressReceipt=args
    elseif command=='Verified' then receipt=args end
end)
Events.OnGameStart.Add(function()
    started=true;since=getTimestampMs()
    getCore():setOptionPauseOnFocusloss(false)
    if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
end)
Events.OnTick.Add(function()
    if not started or done or not isIngameState() then return end
    installMediaProbe()
    local ok,err=pcall(function()
        assert(getTimestampMs()-since<300000,'fixture phase deadline '..phase)
        local player=getPlayer();if not player or not player:getSquare() then return end
        assert(Toolkit.Settings.actionQueue()==(config.mode=='toolkit'),'wrong queue mode')
        if phase=='prepare' then
            if config.kind=='mp' then
                assert(isClient(),'Host client connection not ready')
                sendClientCommand('ShelfBookTVTest','Prepare',{case='demote-and-control'})
                phase='prepare-wait';return
            end
            assert(not isClient() and not isServer(),'SP fixture expected')
            state=Fixture.prepare(player);ids=state.ids;phase='start-read';return
        end
        if phase=='prepare-wait' then return end
        if phase=='wait-fixture' then
            state=Fixture.resolve(player,ids);if not state then return end
            phase='start-read';return
        end
        if phase=='start-read' then
            assert(#queue().queue==0 and not player:hasTimedActions(),'fixture queue not empty')
            if not state.data:canBePoweredHere() or player:tooDarkToRead() then return end
            assert(state.data:canBePoweredHere() and not player:tooDarkToRead(),'fixture electricity/daylight precondition differs')
            initialPages=state.book:getAlreadyReadPages()
            assert(initialPages==state.ids.pages-4,'fixture book starting pages differ')
            print(MARK..'PREPARED shelfId='..ids.shelf..' bookId='..ids.book..' tv='..ids.x..','..ids.y..','..ids.z
                ..' tapeId='..ids.tape..' mediaIndex='..ids.mediaIndex..' mediaType='..ids.mediaType..' power=electric daylight=true')
            ISInventoryPaneContextMenu.readItem(state.book,player:getPlayerNum())
            phase='wait-reading';since=getTimestampMs();return
        end
        local q=queue()
        if phase=='wait-reading' then
            if not reader and q.current and q.current.Type=='ISReadABook' then reader=q.current end
            if not reader or reader.Type~='ISReadABook' or not reader:isStarted() or reader:getJobDelta()<0.15 then return end
            readerOperation=reader.toolkitQueueOperation
            if config.mode=='toolkit' then assert(type(readerOperation)=='table','reading operation token was not captured') end
            if config.kind=='mp' then
                sendClientCommand('ShelfBookTVTest','Progress',{book=ids.book,pagesBefore=initialPages})
                phase='wait-progress';since=getTimestampMs();return
            end
            committedPages=state.book:getAlreadyReadPages()
            if committedPages<=initialPages then return end
            queueTV();return
        end
        if phase=='wait-progress' then
            if not progressReceipt then return end
            assert(progressReceipt.ok and progressReceipt.pages>initialPages,'server did not commit book pages before the TV interruption')
            committedPages=progressReceipt.pages
            queueTV();return
        end
        if phase=='running' then
            if q.current==power and not seenTVStart then
                seenTVStart=true
                if config.mode=='native' then
                    local book=exactBook()
                    assert(book and book:getAlreadyReadPages()==book:getNumberOfPages(),'queue-off TV started before natural book completion')
                    print(MARK..'NATURAL_ORDER readerFinishedBeforeTV=true')
                end
            end
            observeTVEffects()
            if config.mode=='toolkit' and q.current and q.current~=reader and q.current.Type=='ISReadABook'
                and q.current.item and q.current.item:getID()==reader.item:getID()
                and q.current.toolkitQueueOperation==readerOperation and playSeen then resumedReader=q.current end
            local book=exactBook()
            if config.mode=='toolkit' and resumedReader and q.current==resumedReader and resumedReader:isStarted()
                and resumedReader:getJobDelta()>0.1 and book and book:getAlreadyReadPages()>committedPages then
                print(MARK..'RESUMED sameAction=false sameBook=true sameOperation=true pagesBefore='..committedPages..' pagesAfter='..book:getAlreadyReadPages())
                resumedLogged=true
                phase='draining';return
            end
            if #q.queue==0 and not player:hasTimedActions() then phase='draining';idleSince=nil end
            return
        end
        if phase=='draining' then
            observeTVEffects()
            if #q.queue>0 or player:hasTimedActions() then idleSince=nil;return end
            if not idleSince then idleSince=getTimestampMs() end
            if not (powerSeen and insertSeen and playSeen) then
                if getTimestampMs()-idleSince<3000 then return end
                observationDiagnostic(q)
                error('TV action effects did not settle within 3000ms after queue became idle')
            end
            assert(seenTVStart,'queued TV power action never started')
            assert(powerSeen and insertSeen and playSeen,'TV power/insert/play actions did not each start with their matching effect')
            print(MARK..'ACTIONS powerStarted=true powered=true insertStarted=true exactTape=true playStarted=true mediaMatched=true')
            local book=exactBook()
            assert(book and book:getAlreadyReadPages()==book:getNumberOfPages(),'book did not complete after TV sequence')
            if config.mode=='toolkit' then
                assert(resumedLogged and resumedReader and resumedReader~=reader and resumedReader.item:getID()==reader.item:getID()
                    and resumedReader.toolkitQueueOperation==readerOperation,'fresh reader did not resume the same exact book operation')
            end
            assert(state.data:hasMedia() and state.data:getMediaData()
                and state.data:getMediaData():getTitleEN()=='Carzone' and state.data:isPlayingMedia(),'exact Carzone media is not playing')
            if config.mode=='toolkit' then
                assert(reader:isStarted() or reader:getJobDelta()==0,'resumed action did not settle')
            end
            if config.kind=='mp' then finish();return end
            finish();return
        end
        if phase=='authority' then
            if not receipt then return end
            assert(receipt.ok and receipt.bookReturned and receipt.tapeRemoved and receipt.mediaIndex==state.mediaIndex
                and receipt.mediaType==state.mediaType and receipt.tvMedia=='Carzone' and receipt.playing,'server-owned final state differs')
            print(MARK..'RETURN sameBook=true exactCount=1')
            print(MARK..'MEDIA tapeDebited=true exactTape=true mediaIndex='..receipt.mediaIndex..' mediaType='..receipt.mediaType..' title=Carzone playing=true')
            print(MARK..'COMPLETE case=demote-and-control');done=true
        end
    end)
    if not ok then done=true;print('[QUEUE_TEST] FAIL shelf-book-tv '..tostring(err)) end
end)
