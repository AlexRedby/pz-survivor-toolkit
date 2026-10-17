require 'PZSurvivorToolkit/ActionQueuePanel'
require 'TimedActions/ISFixGenerator'
require 'TimedActions/ISReadABook'
require 'TimedActions/ISQueueActionsAction'
local config=require 'QueueTestSelection'
local Authority=require 'QueueEngineAuthority'
local Toolkit=PZSurvivorToolkit
local peers=config.suite=='engine-peers'
local go,released,announced=false,false,false
local ids,receipt,current,tail,emptyCommand,done,started,step,since,phase=nil,nil,nil,nil,nil,false,false,1,0,'prepare'
local repairs,completes,progress,tailProgress,records,seen,boundaries=0,0,false,false,{},{},{}
local begin=Toolkit.ActionQueueLifecycle.begin
Toolkit.ActionQueueLifecycle.begin=function(action, nativePhase)
    local active=begin(action,nativePhase)
    if active and (action.Type=='ISFixGenerator' or action.Type=='ISReadABook' or action==emptyCommand) then
        assert(Toolkit.ActionQueueLifecycle.current(action.character)==action,'native completion ownership missing')
        boundaries[action]=true
        if action.Type=='ISFixGenerator' then
            if nativePhase=='perform' then repairs=repairs+1 else completes=completes+1 end
        end
    end
    return active
end
local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()) end
local function send(command, case)
    if config.kind=='mp' then sendClientCommand('EngineQueueTest',command,{case=case})
    elseif command=='Prepare' then ids=Authority.prepare(getPlayer(),case)
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
        if tail and queue().current==tail and tail:isStarted() and tail:getJobDelta()>0 then tailProgress=true end
        if phase=='prepare' then
            assert(Toolkit.Settings.actionQueue(),'engine suite requires enabled queue')
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
            emptyCommand=ISQueueActionsAction:new(player,function() end)
            ISTimedActionQueue.add(emptyCommand)
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
            if active and active.Type=='ISFixGenerator' and config.kind=='mp' then
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
                if cancels and (not peers or released) and (config.kind=='sp' or #records==1 and records[1].state=='started') then
                    local allowed,reason=Toolkit.ActionQueue.cancel(q,current)
                    assert(allowed,'native repair cancellation denied '..tostring(reason))
                    print('[ENGINE_TEST] CANCEL_REQUEST case='..case..' progress=true')
                    phase='draining';return
                end
            end
            if not cancels and #q.queue==0 and not player:hasTimedActions() then phase='draining' end
        end
        if phase=='draining' then
            if #queue().queue>0 or player:hasTimedActions() then return end
            assert(progress,'native repair never made progress')
            assert(boundaries[emptyCommand],'empty native command failed to complete through shared lifecycle')
            assert(tailProgress and boundaries[tail] and tail.item:getAlreadyReadPages()==tail.item:getNumberOfPages(),'native reading tail did not progress and complete through lifecycle')
            local expected=cancels and 0 or 2
            -- MP effects can make the last client action invalid before its local perform; receipts own the result.
            assert(repairs==expected or config.kind=='mp' and not cancels and repairs==1,
                'native repair perform count '..repairs)
            assert(completes==(config.kind=='sp' and expected or 0),'native complete phase count '..completes)
            if config.kind=='mp' then
                assert(#records==(cancels and 1 or 2),'missing captured native acknowledgements')
                for _,record in ipairs(records) do assert(record.state==(cancels and 'canceled' or 'completed'),'wrong authoritative action outcome '..record.state) end
            end
            print('[ENGINE_TEST] PHASES case='..case..' perform='..repairs..' complete='..completes)
            send('Verify',case);phase='receipt';return
        end
        if phase=='receipt' then
            if not receipt then return end
            assert(receipt.ok and receipt.case==case and receipt.tailRead,'invalid authority receipt')
            print('[ENGINE_TEST] PASS case='..case..' condition='..receipt.condition..' scraps='..receipt.scraps
                ..' tailRead=true boundary=true progress=true receipts='..#records)
            step=step+1
            if step>#config.cases then done=true;print('[ENGINE_TEST] COMPLETE cases='..#config.cases);return end
            ids,receipt,current,tail=nil,nil,nil,nil
            repairs,completes,progress,tailProgress,records,seen,boundaries=0,0,false,false,{},{},{}
            phase='prepare';since=getTimestampMs()
        end
    end)
    if not ok then done=true;print('[QUEUE_TEST] FAIL engine '..tostring(errorMessage)) end
end)
