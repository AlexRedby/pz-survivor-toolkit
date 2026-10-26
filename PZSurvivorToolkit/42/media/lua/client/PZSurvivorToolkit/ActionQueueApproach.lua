-- Native approach is preparation, not a request to replace the player's queue.
-- Resolve the complete routing entrypoint at its turn, including native fallbacks.
local Toolkit = PZSurvivorToolkit
local Operations = Toolkit.ActionQueueOperations
local commandClass,baseClass=ISQueueActionsAction,ISBaseTimedAction
local commandNew,baseNew=commandClass.new,baseClass.new
local commandFactory=Operations.command
local Approach = {}
Toolkit.ActionQueueApproach = Approach
local bindings, installed, attestations = {}, {}, {}
local walking = setmetatable({}, {__mode='k'})
local resolving, preparing = 0, 0
local nativeBatch
local nativeRoot
local cursorContract
local function source(callback)
    if type(callback)~='function' or type(getFilenameOfClosure)~='function' then return end
    local ok,path=pcall(getFilenameOfClosure,callback)
    if ok and type(path)=='string' then return path:gsub('\\','/') end
end
local function native(callback)
    local path=source(callback)
    return path and nativeRoot and path:sub(1,#nativeRoot)==nativeRoot
end
local function constructionUnchanged()
    return ISQueueActionsAction==commandClass and ISBaseTimedAction==baseClass
        and commandClass.new==commandNew and baseClass.new==baseNew
        and Operations.command==commandFactory and native(commandNew)and native(baseNew)
end
local function copy(value)
    local result={}
    for key,member in pairs(value)do result[key]=member end
    return setmetatable(result,getmetatable(value))
end
local function actor(cursor)
    return cursor and (cursor.character or getSpecificPlayer(cursor.player))
end
local function ownedQueue(character)
    local queue=ISTimedActionQueue.queues[character]
    return queue and queue.character==character and queue
end
local knownWrappers={}
local function addGuard(guards,owner,name)
    local callback=owner and owner[name]
    if not native(callback)and not knownWrappers[callback]then return false end
    guards[#guards+1]={owner=owner,name=name,callback=callback}
    return true
end
local function guardList(binding,args,kind,bridge)
    local guards={{owner=binding.owner,name=binding.name,callback=binding.wrapper}}
    local function helper(name)return addGuard(guards,luautils,name)end
    local receiver=binding.spec.receiver and args[binding.spec.receiver]
    if binding.spec.cursor then
        if bridge then
            guards[#guards+1]={owner=receiver,name='create',callback=receiver.create}
            guards[#guards+1]={owner=bridge,name='nativeMoveableCreate',callback=bridge.nativeMoveableCreate}
        elseif not addGuard(guards,receiver,'create')then return end
        if kind=='FishingNet'then
            if not addGuard(guards,receiver,'isValid')then return end
        elseif kind=='ISDestroyCursor'then
            for _,name in ipairs({'getObjectList','canDestroy','_isWall','_isDoorFrame','_isDoorWallN','_isDoorWallW',
                '_isDoorN','_isDoorW','isFloorAtTopOfStairs','couldSeeOpposite','isBasementWallAdjacentToTheVoid'})do
                if not addGuard(guards,receiver,name)then return end
            end
            for _,name in ipairs({'walkAdj','walkAdjWindowOrDoor','walkAdjWall','stringStarts'})do
                if not helper(name)then return end
            end
        end
        local filename=source(binding.callback):match('([^/]+)$')
        if filename=='ISPaintCursor.lua'or filename=='ISPaperCursor.lua'then
            if not addGuard(guards,ISBuildingObject,'walkTo')or not helper('walkAdjWall')then return end
        elseif filename=='ISBuildingObject.lua'then
            if not receiver.skipWalk2 then
                if receiver.isWallLike then
                    if not helper('walkAdjWall')then return end
                elseif receiver.currentMoveProps then
                    for _,name in ipairs({'walkAdj','walkAdjMultiTile','getSpriteGridTopLeft','getMultiTileSquares'})do
                        if not addGuard(guards,receiver.currentMoveProps,name)then return end
                    end
                    for _,name in ipairs({'walkAdj','walkAdjSquares','walkAdjSquaresExcluded'})do
                        if not helper(name)then return end
                    end
                else
                    if not helper('walkAdj')then return end
                    if receiver.Type=='ISWoodenFloor'and not helper('walkAdjWall')then return end
                end
            end
        end
        for _,name in ipairs({'getSquares','getClosestSquare','getTopLeftOfSquares'})do
            if receiver[name]and not addGuard(guards,receiver,name)then return end
        end
    elseif receiver then
        for _,name in ipairs({'walkAdjMultiTile','getSpriteGridTopLeft','getMultiTileSquares'})do
            if not addGuard(guards,receiver,name)then return end
        end
        for _,name in ipairs({'walkAdj','walkAdjSquares','walkAdjSquaresExcluded'})do
            if not helper(name)then return end
        end
    end
    if luautils and luautils.getCorrectSquareForWall
        and not addGuard(guards,luautils,'getCorrectSquareForWall')then return end
    return guards
end
local function live(request)
    local attest=type(request)=='table'and attestations[request.binding]
    if not attest or not attest()then return false end
    for _,guard in ipairs(request.guards)do
        if guard.owner[guard.name]~=guard.callback then return false end
    end
    if request.cursorKind and cursorContract(request.args[1])~=request.cursorKind then return false end
    return true
end
local function squareExists(square)
    return square and getCell():getGridSquare(square:getX(),square:getY(),square:getZ())==square
end
local function available(request)
    local args,binding=request.args,request.binding
    local name=binding.name
    if binding.spec.cursor then return getCell():getGridSquare(args[2],args[3],args[4])~=nil end
    if binding.spec.receiver then
        if name=='walkAdjMultiTile'then return getCell():getGridSquare(args[3],args[4],args[5])~=nil end
        return squareExists(args[3])
    end
    if name=='walkAdjObject'or name=='walkToObject'then
        local object=args[2]
        return object and object:getSquare()and squareExists(object:getSquare())
            and(not object.getObjectIndex or object:getObjectIndex()>=0)
    elseif name=='walkAdjSquares'or name=='walkAdjSquaresExcluded'then
        if not args[2]or #args[2]==0 then return false end
        for _,square in ipairs(args[2])do if not squareExists(square)then return false end end
        for _,square in ipairs(name=='walkAdjSquaresExcluded'and args[3]or{})do
            if not squareExists(square)then return false end
        end
        return true
    elseif name=='walkToContainer'then return args[1]and args[1]:isExistYet()end
    return squareExists(args[2])
end
-- A loaded target may border an unloaded tile. Native correction dereferences
-- that tile without a nil check. Treat only this missing-grid precondition as
-- no route; nested helpers can then try their original ancestor's fallback.
local function routeAvailable(binding,args)
    if binding.owner~=luautils then return true end
    local name=binding.name
    local squares
    if name=='walkAdj'or name=='walkAdjAltTest'then
        local target=args[2]
        if not squareExists(target)then return false end
        if name=='walkAdj'then
            for _,excluded in ipairs(args[4]or{})do
                if excluded==args[1]:getCurrentSquare()then return true end
            end
        elseif args[3]then
            local alternate=args[3]
            if math.abs(target:getX()+.5-alternate:getX())<=1.6
                and math.abs(target:getY()+.5-alternate:getY())<=1.6 then return true end
        end
        squares={target}
    elseif name=='walkAdjObject'then
        squares={args[2]and args[2]:getSquare()}
        if #squares==0 then return false end
    elseif name=='walkAdjSquares'or name=='walkAdjSquaresExcluded'then squares=args[2]or{}
    else return true end
    for _,square in ipairs(squares)do
        if not squareExists(square)or not squareExists(luautils.getCorrectSquareForWall(args[1],square))then return false end
    end
    return true
end
local function reject(action)
    local queue=ownedQueue(action.character)
    if not queue or queue.current~=action or queue.queue[1]~=action then return end
    Operations.invalidate(action.toolkitQueueOperation)
    queue.toolkitGroupCancel={action=action,token=action.toolkitQueueOperation,reason='approach_unavailable'}
end
local function pathFailed(action)
    local record=walking[action]
    if record then record.failed=true end
end
local function selectedAvailable(request)
    if not request.selected then return true end
    local receiver=request.args[1]
    for index,object in ipairs(receiver:getObjectList())do
        if object==request.selected then receiver.objectIndex=index;return true end
    end
    return false
end
local function routeAccepted(request,result)
    if result==true then return true end
    -- Native tryBuild permits a fishing net in valid nearby water even when no
    -- adjacent walking tile exists. Preserve that caller-level continuation.
    if request.cursorKind=='FishingNet'then
        local args=request.args
        local square=getCell():getGridSquare(args[2],args[3],args[4])
        return square~=nil and args[1]:isValid(square,true)==true
    end
    return false
end
local function resolve(character,request)
    local queue=ownedQueue(character)
    local current=queue and queue.current
    if not current or not Operations.isCommand(current)or not live(request)or not available(request)
        or not selectedAvailable(request)then
        if current then reject(current)end
        return
    end
    if not routeAvailable(request.binding,request.args)then
        if not routeAccepted(request,false)then reject(current)end
        return
    end
    -- Native helpers may clear/replace their own inserted walking alternatives.
    -- The executor's beginAddingActions boundary protects existing tasks.
    resolving,preparing=resolving+1,preparing+1
    local result={pcall(request.binding.callback,unpack(request.args,1,request.args.n))}
    resolving,preparing=resolving-1,preparing-1
    if not result[1]then error(result[2],0)end
    if not routeAccepted(request,result[2])then reject(current);return end
    for index=2,1+current._numAddedActions do
        local action=queue.queue[index]
        if action and (action.Type=='ISWalkToTimedAction' or action.Type=='ISPathFindAction'
            or action.Type=='ISWalkToTimedActionF') then
            if native(action.stop)and native(action.update)and native(action.perform)then
                local record={class=getmetatable(action),token=current.toolkitQueueOperation,
                    stop=action.stop,update=action.update,perform=action.perform,valid=action.isValid}
                walking[action]=record
                if action.Type=='ISPathFindAction'and not action.onFailFunc
                    and not action.runActionsAfterFailing and native(action.setOnFail)then
                    action:setOnFail(pathFailed,action)
                    record.onFail=pathFailed
                end
            end
        end
    end
end
local function synchronous(callback,args)
    resolving=resolving+1
    local result={pcall(callback,unpack(args,1,args.n))}
    resolving=resolving-1
    if not result[1]then error(result[2],0)end
    return unpack(result,2)
end
-- A reviewed compound native command replaces prior work once when the queue
-- is disabled. Each later approach resolves at its own boundary, so a native
-- clear cannot erase an earlier sibling such as body washing.
function Approach.runNativeBatch(character, callback, ...)
    local token=Operations.preparationScope(character)
    if Toolkit.Settings.actionQueue() or not token or not instanceof(character,'IsoPlayer')
        or not character:isLocalPlayer() or character:isDead() or isServer() then return callback(...) end
    if nativeBatch and nativeBatch.character==character and nativeBatch.token==token then return callback(...) end
    local previous=nativeBatch
    ISTimedActionQueue.clear(character)
    nativeBatch={character=character,token=token}
    local result={n=select('#',...),...}
    local function pack(...)return{n=select('#',...),...}end
    result=pack(pcall(callback,unpack(result,1,result.n)))
    nativeBatch=previous
    if not result[1]then error(result[2],0)end
    return unpack(result,2,result.n)
end
local function canCapture(character)
    if resolving>0 or not instanceof(character,'IsoPlayer') or character:isDead() or isServer() then return end
    local queue=ownedQueue(character)
    if queue and queue:isCurrentActionAddingOtherActions() then return end
    local token=Operations.preparationScope(character)
    if Toolkit.Settings.actionQueue() or nativeBatch and nativeBatch.character==character and nativeBatch.token==token then return token end
end
-- skipBuildAction is also used by UI pickers and debug editors. Only their
-- declared timed-action-producing native create contracts have async semantics.
local actionCursors={ISRemovePlantCursor=true,ISScytheGrassCursor=true,ISChopTreeCursor=true,
    ISCleanBloodCursor=true,ISCleanGraffitiCursor=true,ISShovelGroundCursor=true,
    ISPickDungCursor=true,farmingPlot=true,ISPaintCursor=true,ISPaperCursor=true,
    FishingNet=true,ISDestroyCursor=true,ISMoveableCursor=true,ISExtinguishCursor=true}
cursorContract=function(cursor)
    if type(cursor.onSquareSelected)=='function'then return end
    local callback,bridge=cursor.create
    if not native(callback)then
        local world=Toolkit.ActionQueueWorld
        local original=world and world.nativeMoveableCreate and world.nativeMoveableCreate(callback)
        if not native(original)then return end
        callback,bridge=original,world
    end
    if not cursor.skipBuildAction then return 'build',bridge end
    local filename=source(callback)
    local kind=filename and filename:match('([^/]+)%.lua$')
    -- Native joypad extinguishing chooses its area relative to the actor at
    -- selection. Its walkTo is a no-op, just like the 3D-item cursor's walkTo.
    -- Keep those synchronous; direct helpers used by create still share dispatch.
    if kind=='ISExtinguishCursor'and actor(cursor):getJoypadBind()~=-1 then return end
    if actionCursors[kind]then return kind,bridge end
end
local function bind(owner,name,spec)
    if not owner or installed[owner]and installed[owner][name] then return end
    local callback=rawget(owner,name)
    if not native(callback)then return end
    local binding={owner=owner,name=name,callback=callback,spec=spec}
    local wrapper
    wrapper=function(...)
        local args={n=select('#',...),...}
        if preparing>0 and owner[name]==wrapper and not routeAvailable(binding,args)then return false end
        -- A UI selector consumes a boolean immediately to call its selection
        -- callback; that contract is not a queued gameplay dependency.
        local kind,bridge
        if spec.cursor then
            kind,bridge=cursorContract(args[1])
            if not kind then return synchronous(callback,args)end
        end
        local character=spec.actor(args)
        local token=canCapture(character)
        if owner[name]~=wrapper or not token then return callback(...)end
        -- A receiver can be a reusable placement cursor. Freeze its routing
        -- fields, not the live actor, squares, items or world objects.
        if spec.receiver then
            local receiver=args[spec.receiver]
            if type(receiver)~='table'then return callback(...)end
            receiver=copy(receiver)
            if type(receiver.currentMoveProps)=='table'then receiver.currentMoveProps=copy(receiver.currentMoveProps)end
            args[spec.receiver]=receiver
        end
        for _,index in ipairs(spec.arrays or{})do
            if type(args[index])=='table'then
                local list={};for i,member in ipairs(args[index])do list[i]=member end;args[index]=list
            end
        end
        local guards=guardList(binding,args,kind,bridge)
        if not guards then return synchronous(callback,args)end
        local request={binding=binding,args=args,guards=guards,cursorKind=kind}
        if kind=='ISDestroyCursor'then
            request.selected=args[1]:getObjectList()[args[1].objectIndex]
            if not request.selected then return synchronous(callback,args)end
        end
        local command=Operations.command(character,resolve,request)
        command.toolkitQueueApproach=true
        command.toolkitQueueOperation=token
        ISTimedActionQueue.add(command)
        -- Native callers already interpret true as accepted/enqueued, not arrived.
        return true
    end
    binding.wrapper=wrapper;knownWrappers[wrapper]=binding
    local receiver,cursor,actorFunction=spec.receiver,spec.cursor,spec.actor
    local arrays={};for index,value in ipairs(spec.arrays or{})do arrays[index]=value end
    attestations[binding]=function()
        if binding.owner~=owner or binding.name~=name or binding.callback~=callback
            or binding.wrapper~=wrapper or binding.spec~=spec or spec.receiver~=receiver
            or spec.cursor~=cursor or spec.actor~=actorFunction then return false end
        local current=spec.arrays or{}
        if #current~=#arrays then return false end
        for index,value in ipairs(arrays)do if current[index]~=value then return false end end
        return true
    end
    installed[owner]=installed[owner]or{};installed[owner][name]=binding
    bindings[#bindings+1]=binding
    owner[name]=wrapper
end
local first={actor=function(args)return args[1]end}
local function listSpec(...)
    return {actor=first.actor,arrays={...}}
end
local cursorSpec={receiver=1,cursor=true,actor=function(args)return actor(args[1])end}
local propsSpec={receiver=1,actor=function(args)return args[2]end}
local function derives(class,parent)
    for _=1,20 do
        if class==parent then return true end
        local meta=type(class)=='table'and getmetatable(class)
        class=meta and (meta.__index or meta)
        if not class then return false end
    end
    return false
end
function Approach.install()
    local path=source(ISBaseTimedAction and ISBaseTimedAction.new)
    nativeRoot=nativeRoot or path and path:match('^(.*media/lua/)')
    if not nativeRoot then return false end
    for _,name in ipairs({'walk','walkAdjAltTest','walkAdjWall','walkAdjWindowOrDoor','walkAdjFence','walkAdjObject','walkToObject'})do
        bind(luautils,name,first)
    end
    bind(luautils,'walkAdj',listSpec(4))
    bind(luautils,'walkAdjSquares',listSpec(2))
    bind(luautils,'walkAdjSquaresExcluded',listSpec(2,3))
    bind(luautils,'walkToContainer',{actor=function(args)return getSpecificPlayer(args[2])end})
    bind(ISMoveableSpriteProps,'walkAdj',propsSpec)
    bind(ISMoveableSpriteProps,'walkAdjMultiTile',propsSpec)
    -- Capture the ancestor before its helpers: floor/wall/multi-tile alternative
    -- routes must be resolved together, rather than optimistic nested booleans.
    if ISBuildingObject then
        bind(ISBuildingObject,'walkTo',cursorSpec)
        for _,class in pairs(_G)do
            if type(class)=='table'and class~=ISBuildingObject and derives(class,ISBuildingObject)then
                bind(class,'walkTo',cursorSpec)
            end
        end
    end
    return true
end
-- Consumers may verify the captured native body without mistaking this owned
-- dispatcher for a foreign helper. They still retain the live wrapper identity.
function Approach.nativeHelper(owner,name,callback)
    if owner~=luautils or type(callback)~='function'or owner[name]~=callback then return end
    local binding=installed[owner]and installed[owner][name]
    if not binding or binding.wrapper~=callback or knownWrappers[callback]~=binding
        or not attestations[binding]()or not native(binding.callback)then return end
    return binding.callback
end
-- Only native preparation paths created by this dispatcher get selective failure
-- handling. Manual movement/cancel retains normal whole-queue cancellation.
function Approach.onStop(action)
    local record=walking[action]
    if not record or not Toolkit.Settings.actionQueue() or record.class~=getmetatable(action)
        or action.toolkitQueueOperation~=record.token or record.stop~=action.stop or record.update~=action.update
        or record.perform~=action.perform or record.valid~=action.isValid
        or action.onCompleteFunc or action.onFailFunc~=record.onFail or action.runActionsAfterFailing
        or not(record.failed or action.Type=='ISWalkToTimedAction'and action.result==BehaviorResult.Failed)
        or action.character:isDead() or action.character:isPlayerMoving() or action.character:pressedMovement(false)
        or action.character:pressedCancelAction() then return false end
    local queue=ownedQueue(action.character)
    if not queue or queue.current~=action or queue.queue[1]~=action then return false end
    walking[action]=nil
    reject(action)
    queue.toolkitCancel=action
    return true
end
-- Recovery receives only an opaque seal for native argument intent. It never
-- reuses a command/action/token. Complex mutable cursor receivers remain outside
-- the recovery contract until their complete state has a reconstruction model.
local recoveryMarker={}
local function requestCopy(request)
    local args={n=request.args.n}
    for index=1,args.n do args[index]=request.args[index]end
    for _,index in ipairs(request.binding.spec.arrays or{})do
        if args[index]then
            local values={};for i,value in ipairs(args[index])do values[i]=value end;args[index]=values
        end
    end
    return {binding=request.binding,args=args,guards=request.guards}
end
function Approach.capture(action)
    if not constructionUnchanged()or not Approach.isAction(action)or action.action then return end
    local request=action.toolkitQueueCommand.snapshot
    if request.binding.spec.receiver or not live(request)then return end
    local frozen,owner=requestCopy(request),action.character
    local handle={}
    handle[recoveryMarker]=function(candidate)if candidate==handle then return frozen,owner end end
    return handle
end
function Approach.rebuild(character,handle)
    if not constructionUnchanged()or type(handle)~='table'or getmetatable(handle)then return end
    local seal=rawget(handle,recoveryMarker)
    if type(seal)~='function'then return end
    local request,owner=seal(handle)
    if owner~=character or not live(request)or not available(request)then return end
    local action=commandFactory(character,resolve,requestCopy(request))
    if not Operations.isCommand(action)then return end
    action.toolkitQueueApproach=true
    return action
end
local function pruneWalking()
    for action in pairs(walking)do
        local queue=ownedQueue(action.character)
        local found=false
        for _,member in ipairs(queue and queue.queue or{})do
            if member==action then found=true;break end
        end
        if not found then walking[action]=nil end
    end
end
function Approach.completed(action)
    walking[action]=nil
    -- Kahlua does not implement weak-key collection. Remove canceled siblings
    -- as well, without retaining old actions until another queue reset.
    pruneWalking()
end
function Approach.reset(queue)
    for _,action in ipairs(queue.queue or{})do walking[action]=nil end
end
-- Consumers with a verified transfer contract can include its exact shared
-- preparation without accepting arbitrary extra commands into that contract.
function Approach.isContainer(action,container,character)
    if not Approach.isAction(action)or action.character~=character then return false end
    local request=action.toolkitQueueCommand.snapshot
    return request.binding.owner==luautils and request.binding.name=='walkToContainer'
        and request.args[1]==container and getSpecificPlayer(request.args[2])==character
end
function Approach.isAction(action)
    local record=action and action.toolkitQueueCommand
    return record and record.callback==resolve and Operations.isCommand(action)and live(record.snapshot)
end
return Approach
