require 'PZSurvivorToolkit/ActionQueuePanel'
require 'TimedActions/ISFixGenerator'
require 'TimedActions/ISReadABook'
require 'TimedActions/ISQueueActionsAction'
local config=require 'QueueTestSelection'
local Authority=require 'QueueEngineAuthority'
local Toolkit=PZSurvivorToolkit
local peers=config.suite=='engine-peers'
local enabled=config.mode=='toolkit'
local go,released,announced=false,false,false
local ids,receipt,current,tail,emptyCommand,done,started,step,since,phase=nil,nil,nil,nil,nil,false,false,1,0,'prepare'
local repairs,completes,progress,tailProgress,records,seen,boundaries=0,0,false,false,{},{},{}
local flushes,completionActions=0,{}
local blocker,invalidated,removalRequested,lateChecked
local lifecycle=Toolkit.ActionQueueLifecycle
local begin,finish,flush=lifecycle.begin,lifecycle.finish,lifecycle.flush
lifecycle.begin=function(action, nativePhase)
    local active=begin(action,nativePhase)
    if action.Type=='ISFixGenerator' then assert(active==enabled,'wrong native repair boundary mode') end
    if active and (action.Type=='ISFixGenerator' or action.Type=='ISReadABook' or action==emptyCommand) then
        assert(lifecycle.current(action.character)==action,'native completion ownership missing')
        boundaries[action]=true
        if action.Type=='ISFixGenerator' then
            local queue=ISTimedActionQueue.queues[action.character]
            assert(action.character==getPlayer() and queue and queue.current==action and queue.queue[1]==action
                and action.action,'native repair completion owner differs')
            local record=completionActions[action]
            if nativePhase=='perform' then
                assert(not record,'duplicate native repair perform boundary')
                record={native=action.action};completionActions[action]=record
            else
                assert(nativePhase=='complete' and config.kind=='sp' and record and record.perform=='finished',
                    'native repair complete preceded perform or ran on the client')
            end
            assert(record.native==action.action and not record[nativePhase],'duplicate or replaced native repair phase')
            record[nativePhase]='begun'
        end
    end
    return active
end
lifecycle.finish=function(action,nativePhase,succeeded)
    finish(action,nativePhase,succeeded)
    if not enabled or action.Type~='ISFixGenerator' then return end
    local record=completionActions[action]
    assert(record and record[nativePhase]=='begun' and succeeded,'native repair phase did not finish once')
    record[nativePhase]='finished'
    if nativePhase=='perform' then repairs=repairs+1 else completes=completes+1 end
end
lifecycle.flush=function(queue)
    local action=queue.current
    local record=completionActions[action]
    local absent=record and not queue.character:getCharacterActions():contains(record.native)
    local tailStarted=record and tail and tail:isStarted()
    local outcome,finished=flush(queue)
    if record and outcome=='completed' then
        assert(finished==action and not record.flushed and absent and record.perform=='finished'
            and (config.kind=='mp' or record.complete=='finished'),'native repair flushed before completion/removal or twice')
        assert(not tailStarted,'independent reader started before native repair completion')
        record.flushed=true;flushes=flushes+1
    end
    return outcome,finished
end
local function completionSettled()
    assert(flushes==repairs and completes==(config.kind=='sp' and repairs or 0),'native repair completion phases differ')
    for _,record in pairs(completionActions) do assert(record.flushed,'native repair did not settle before reader') end
end
local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()) end
local function send(command, case)
    if config.kind=='mp' then sendClientCommand('EngineQueueTest',command,{case=case})
    elseif command=='Prepare' then ids=Authority.prepare(getPlayer(),case)
    elseif command=='Invalidate' then invalidated=Authority.invalidate(getPlayer(),case)
    else receipt=Authority.verify(getPlayer(),case) end
end
local function generator()
    local square=getCell():getGridSquare(ids.x,ids.y,ids.z)
    if not square then return end
    for i=0,square:getSpecialObjects():size()-1 do
        local object=square:getSpecialObjects():get(i)
        if instanceof(object,'IsoGenerator') and object:getObjectIndex()==ids.objectIndex then return object end
    end
end
Events.OnServerCommand.Add(function(module,command,args)
    if module~='EngineQueueTest' then return end
    assert(args.ok~=false,args.error)
    if command=='Prepared' then ids=args elseif command=='Verified' then receipt=args
    elseif command=='Invalidated' then invalidated=args
    elseif command=='Begin' then go=true elseif command=='Release' then released=true end
end)
Events.OnGameStart.Add(function()
    started=true;since=getTimestampMs()
    getCore():setOptionPauseOnFocusloss(false)
    if not isClient() then getPlayer():setGhostMode(true) end
    if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
end)
Events.OnTick.Add(function()
    if not started or done or not isIngameState() then return end
    local ok,errorMessage=pcall(function()
        assert(getTimestampMs()-since<180000,'engine native stage deadline '..phase)
        local case=config.cases[step]
        local player=getPlayer()
        if not player or player:isDead() or not player:getSquare() then return end
        if config.kind=='mp' and (not isClient() or player:getOnlineID()<0) then return end
        local cancels=Authority.cancels(case,player)
        if tail and queue().current==tail and tail:isStarted() and tail:getJobDelta()>0 then
            completionSettled();tailProgress=true
        end
        if phase=='prepare' then
            assert(Toolkit.Settings.actionQueue()==enabled,'wrong engine queue mode')
            send('Prepare',case);phase='ready';return
        end
        if phase=='ready' then
            if not ids then return end
            assert(ids.case==case,'wrong prepared case')
            local gen=generator()
            local book=player:getInventory():getItemById(ids.tail)
            if not gen or not book then return end
            if gen:getCondition()~=94 then return end
            for _,id in ipairs(ids.scraps) do if not player:getInventory():getItemById(id) then return end end
            local scraps=0
            local items=player:getInventory():getItems()
            for i=0,items:size()-1 do if items:get(i):getFullType()=='Base.ElectronicsScrap' then scraps=scraps+1 end end
            if scraps~=2 then return end
            local blockingBook=ids.blocker and player:getInventory():getItemById(ids.blocker)
            if ids.blocker and not blockingBook then return end
            if peers and not go then
                if not announced then send('Ready',case);announced=true end
                return
            end
            player:teleportTo(ids.spawn.x,ids.spawn.y,ids.spawn.z)
            assert(gen:getCondition()==94 and not gen:isActivated(),'client generator baseline differs')
            book:setAlreadyReadPages(book:getNumberOfPages()-1)
            player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
            current=ISFixGenerator:new(player,gen)
            assert(current:getDuration()==150 and not player:isTimedActionInstant(),'native repair duration changed')
            if enabled then
                emptyCommand=ISQueueActionsAction:new(player,function() end)
                ISTimedActionQueue.add(emptyCommand)
            end
            if blockingBook then
                blockingBook:setAlreadyReadPages(blockingBook:getNumberOfPages()-1)
                player:setAlreadyReadPages(blockingBook:getFullType(),blockingBook:getNumberOfPages()-1)
                blocker=ISReadABook:new(player,blockingBook)
                ISTimedActionQueue.add(blocker)
            end
            ISTimedActionQueue.add(current)
            tail=ISReadABook:new(player,book)
            assert(tail.minutesPerPage==2.0 and tail.maxTime>1,'native read duration changed')
            ISTimedActionQueue.add(tail)
            assert(current.toolkitQueueOperation~=tail.toolkitQueueOperation,'tail must be independent native work')
            print('[ENGINE_TEST] ENQUEUED case='..case..' repairDuration=150 tailPages=1 nativeDurations=true')
            phase='running';since=getTimestampMs();return
        end
        if phase=='running' then
            local q=queue()
            local active=q.current
            if case=='missing-target' then
                if active==blocker and blocker:isStarted() and blocker:getJobDelta()>0 then
                    progress=true
                    if not removalRequested then removalRequested=true;send('Invalidate',case) end
                end
                if invalidated and not lateChecked then
                    local gen=generator()
                    if gen and gen:getObjectIndex()>=0 then return end
                    assert(active==blocker and not current:isStarted(),'target removal did not precede native repair')
                    lateChecked=true
                    print('[ENGINE_TEST] MISSING_TARGET case='..case..' beforeStart=true blockerProgress=true')
                end
            end
            if enabled and active and active.Type=='ISFixGenerator' and config.kind=='mp' then
                local record=Toolkit.ActionQueueAcknowledgements.capture(active)
                if record and not seen[record.token] then
                    seen[record.token]=true;records[#records+1]=record
                    print('[ENGINE_TEST] CAPTURE case='..case..' kind=ISFixGenerator token='..record.token
                        ..' transaction='..record.transaction..' player='..player:getOnlineID())
                    if peers and active==current then
                        sendClientCommand('EngineQueueTest','Started',{case=case,transaction=record.transaction,token=record.token})
                    end
                end
            end
            if active==current and current:isStarted() and current:getJobDelta()>0 then
                progress=true
                if cancels and (not peers or released) and (not enabled or config.kind=='sp' or #records==1 and records[1].state=='started') then
                    if enabled then
                        local allowed,reason=Toolkit.ActionQueue.cancel(q,current)
                        assert(allowed,'native repair cancellation denied '..tostring(reason))
                    else current:forceStop() end
                    print('[ENGINE_TEST] CANCEL_REQUEST case='..case..' progress=true')
                    phase='draining';return
                end
            end
            if not cancels and #q.queue==0 and not player:hasTimedActions() then phase='draining' end
        end
        if phase=='draining' then
            if #queue().queue>0 or player:hasTimedActions() then return end
            assert(progress,'native repair/blocker never made progress')
            if case=='missing-target' then assert(lateChecked and invalidated,'missing target was not observed before repair') end
            if case=='late-continuation' and not lateChecked then
                local q=queue()
                assert(q:indexOf(current)==-1,'late callback parent is still queued')
                local gen=current.generator
                local condition=gen:getCondition()
                for i=1,2 do current:continueFixing() end
                assert(#q.queue==0 and not player:hasTimedActions() and gen:getCondition()==condition,'late callbacks resurrected repair')
                lateChecked=true
                print('[ENGINE_TEST] LATE_CALLBACK case='..case..' parentRetired=true repeats=2 unchanged=true')
            end
            if enabled then
                assert(boundaries[emptyCommand],'empty native command failed to complete through shared lifecycle')
                assert(tailProgress and boundaries[tail] and tail.item:getAlreadyReadPages()==tail.item:getNumberOfPages(),'native reading tail did not progress and complete through lifecycle')
            end
            local expected=(cancels or case=='missing-target' or not enabled) and 0 or 2
            -- MP effects can make the last client action invalid before its local perform; receipts own the result.
            assert(repairs==expected or enabled and config.kind=='mp' and not cancels and case~='missing-target' and repairs==1,
                'native repair perform count '..repairs)
            assert(completes==(config.kind=='sp' and expected or 0),'native complete phase count '..completes)
            completionSettled()
            if enabled and config.kind=='mp' then
                assert(#records==(case=='missing-target' and 0 or cancels and 1 or 2),'missing captured native acknowledgements')
                for _,record in ipairs(records) do assert(record.state==(cancels and 'canceled' or 'completed'),'wrong authoritative action outcome '..record.state) end
            end
            print('[ENGINE_TEST] PHASES case='..case..' perform='..repairs..' complete='..completes..' flush='..flushes)
            send('Verify',case);phase='receipt';return
        end
        if phase=='receipt' then
            if not receipt then return end
            assert(receipt.ok and receipt.case==case and type(receipt.tailRead)=='boolean','invalid authority receipt')
            print('[ENGINE_TEST] PASS case='..case..' condition='..receipt.condition..' scraps='..receipt.scraps
                ..' tailRead='..tostring(receipt.tailRead)..' boundary='..tostring(enabled)..' progress=true receipts='..#records)
            step=step+1
            if step>#config.cases then done=true;print('[ENGINE_TEST] COMPLETE cases='..#config.cases);return end
            ids,receipt,current,tail=nil,nil,nil,nil
            repairs,completes,progress,tailProgress,records,seen,boundaries=0,0,false,false,{},{},{}
            flushes,completionActions=0,{}
            blocker,invalidated,removalRequested,lateChecked,emptyCommand=nil,nil,nil,nil,nil
            phase='prepare';since=getTimestampMs()
        end
    end)
    if not ok then done=true;print('[QUEUE_TEST] FAIL engine '..tostring(errorMessage)) end
end)
