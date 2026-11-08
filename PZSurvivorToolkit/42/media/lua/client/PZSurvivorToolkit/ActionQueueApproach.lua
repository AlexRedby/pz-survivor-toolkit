-- Native approach is preparation, not a request to replace the player's queue.
-- Resolve the complete routing entrypoint at its turn, including native fallbacks.
local Proof = require "PZSurvivorToolkit/SourceProof"
local Toolkit = PZSurvivorToolkit
local Operations = Toolkit.ActionQueueOperations
local commandClass,baseClass=ISQueueActionsAction,ISBaseTimedAction
local commandNew,baseNew=commandClass.new,baseClass.new
local commandFactory=Operations.command
local Approach = {}
Toolkit.ActionQueueApproach = Approach
local bindings, installed, attestations = {}, {}, {}
local spatialPrimitives={kind=type,meta=getmetatable,raw=rawget,equal=rawequal,each=ipairs,pairs=pairs,
    globals=_G,actualMeta=toolkitLuaMetatableMatches,capture=Proof.captureBindings,origin=Proof.closure,matches=Proof.matches,own=Proof.own,
    isCommand=Operations.isCommand,construction=Operations.commandConstructionTrusted}
local spatialPrimitiveWatch=Proof.captureBindings({
    {owner=_G,keys={'type','getmetatable','rawget','rawequal','pairs','ipairs','pcall','unpack','select',
        'math','table','string','getFilenameOfClosure','getGameFilesInput','toolkitLuaMetatableMatches'}},
    {owner=math,keys={'floor'}},{owner=string,keys={'byte','sub','gsub','match'}},
})
local spatialFactory,spatialSources
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
    local callback=Proof.own(owner,name)
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
local function recoveryRequest(character,handle)
    if not constructionUnchanged()or not Operations.commandConstructionTrusted()
        or type(handle)~='table'or getmetatable(handle)then return end
    local seal=rawget(handle,recoveryMarker)
    if type(seal)~='function'then return end
    local request,owner=seal(handle)
    if owner~=character or not live(request)or not available(request)then return end
    return request
end
function Approach.validate(character,handle)
    return recoveryRequest(character,handle)~=nil
end
function Approach.rebuild(character,handle)
    local request=recoveryRequest(character,handle)
    if not request then return end
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
-- A query-local lease for the captured entrypoint, not a route or a native
-- child forecast. Every resource becomes unresolved when this boundary runs.
local function spatialPlain(value)
    return spatialPrimitives.kind(value)=='table'and spatialPrimitives.meta(value)==nil
        and spatialPrimitives.kind(spatialPrimitives.actualMeta)=='function'
        and spatialPrimitives.actualMeta(value,nil)==true
end
local function spatialArray(value,limit)
    if not spatialPlain(value)then return end
    local count,maximum=0,0
    for key in spatialPrimitives.pairs(value)do
        count=count+1
        if count>limit or spatialPrimitives.kind(key)~='number'or key~=key
            or key%1~=0 or key<1 or key>limit then return end
        if key>maximum then maximum=key end
    end
    if count==maximum then return count end
end
-- Validate inherited reads without ever indexing through a foreign __index.
-- The native classes and Lua 5.1 test classes use slightly different table
-- chains; both must remain bounded tables with no lookup callback.
local function spatialInheritance(action)
    local p=spatialPrimitives
    local pending,seen,specifications={action},{},{}
    local index=1
    while index<=#pending do
        local owner=pending[index];index=index+1
        if not seen[owner]then
            if #specifications>=8 or p.kind(owner)~='table'then return end
            seen[owner]=true;specifications[#specifications+1]={owner=owner,exact=true}
            local parent=p.meta(owner)
            if parent~=nil then
                if p.kind(parent)~='table'then return end
                pending[#pending+1]=parent
                local lookup=p.own(parent,'__index')
                if lookup~=nil then
                    if p.kind(lookup)~='table'then return end
                    pending[#pending+1]=lookup
                end
            end
        end
    end
    return p.capture(specifications)
end
local function prepareSpatialRequest(action)
    local p=spatialPrimitives
    if not spatialPrimitiveWatch or not spatialPrimitiveWatch()
        or p.meta(p.globals)~=nil or not spatialPlain(Toolkit)or not spatialPlain(Approach)
        or not spatialPlain(Proof)or not spatialPlain(Operations)or not spatialPlain(luautils)
        or not spatialPlain(first)or not spatialPlain(installed)or not spatialPlain(knownWrappers)
        or not spatialPlain(attestations)
        or not p.equal(p.raw(p.globals,'PZSurvivorToolkit'),Toolkit)
        or not p.equal(p.raw(Toolkit,'ActionQueueApproach'),Approach)
        or not p.equal(p.raw(Toolkit,'ActionQueueOperations'),Operations)
        or not p.equal(p.raw(p.globals,'ISQueueActionsAction'),commandClass)
        or not p.equal(p.raw(p.globals,'ISBaseTimedAction'),baseClass)
        or not p.equal(p.raw(Approach,'prepareSpatialLease'),spatialFactory)
        or not p.equal(p.raw(Proof,'captureBindings'),p.capture)
        or not p.equal(p.raw(Proof,'closure'),p.origin)or not p.equal(p.raw(Proof,'matches'),p.matches)
        or not p.equal(p.raw(Proof,'own'),p.own)
        or not p.equal(p.raw(Operations,'isCommand'),p.isCommand)
        or not p.equal(p.raw(Operations,'commandConstructionTrusted'),p.construction)
        or p.kind(action)~='table'or not p.equal(p.meta(action),commandClass) then return end
    -- Capture before metadata readers: they may reenter and change bindings.
    local rootWatch=p.capture({
        {owner=p.globals,keys={'PZSurvivorToolkit','ISQueueActionsAction','ISBaseTimedAction','luautils',
            'getFilenameOfClosure','getGameFilesInput','type','getmetatable','rawget','rawequal','pairs','ipairs',
            'pcall','unpack','select','math','table','string','toolkitLuaMetatableMatches'}},
        {owner=Toolkit,keys={'ActionQueueApproach','ActionQueueOperations'}},
        {owner=Approach,keys={'prepareSpatialLease'}},{owner=Proof,keys={'captureBindings','closure','matches','own'}},
        {owner=Operations,keys={'command','isCommand','commandConstructionTrusted','expandCommand','runWith'}},
        {owner=commandClass,exact=true},{owner=baseClass,exact=true},{owner=action,exact=true},
        {owner=math,exact=true},{owner=string,exact=true},{owner=table,exact=true},
    })
    if not rootWatch then return end
    local inheritanceWatch=spatialInheritance(action)
    if not inheritanceWatch then return end
    local record=p.own(action,'toolkitQueueCommand')
    if not spatialPlain(record)or not spatialPlain(record.marker)then return end
    local request=record.snapshot
    if not spatialPlain(request)or not spatialPlain(request.binding)or not spatialPlain(request.args)
        or not spatialPlain(request.guards)then return end
    local binding,args,guards=request.binding,request.args,request.guards
    local spec=binding.spec
    if spatialArray(guards,2)~=2 or not spatialPlain(spec)or not p.equal(binding.owner,luautils) or binding.name~='walkAdj'
        or not p.equal(spec.actor,first.actor) or spec.receiver~=nil or spec.cursor~=nil
        or spatialArray(spec.arrays,1)~=1 or spec.arrays[1]~=4
        or request.cursorKind~=nil or request.selected~=nil
        or p.kind(args.n)~='number'or args.n%1~=0 or args.n<2 or args.n>4
        or not p.equal(args[1],p.own(action,'character'))or args[1]==nil or args[2]==nil
        or args[3]~=nil and p.kind(args[3])~='boolean'
        or args[4]~=nil and not spatialArray(args[4],32)then return end
    local argumentFields=0
    for key in p.pairs(args)do
        argumentFields=argumentFields+1
        if argumentFields>5 or key~='n'and(key~=1 and key~=2 and key~=3 and key~=4 or key>args.n)then return end
    end
    if p.kind(args[2])~='table'and p.kind(args[2])~='userdata'then return end
    if p.own(action,'action')or p.own(action,'started')or p.own(action,'_isAddingActions')
        or p.own(action,'isAddingActions')or record.ready~=nil
        or p.own(action,'onFailFunc')or p.own(action,'additionalTest')or p.own(action,'retriggerLastAction')
        or not p.equal(record.callback,resolve) or not p.equal(record.owner,action) or not spatialPlain(record.args)
        or spatialArray(record.args,1)~=1 or not p.equal(record.args[1],request)
        or not p.equal(p.own(action,'args'),record.args)
        or not p.equal(p.own(action,'addActionsFunction'),record.callback)then return end
    for index=1,2 do
        if not spatialPlain(guards[index])or not p.equal(guards[index].owner,luautils) then return end
    end
    if guards[1].name~='walkAdj'or not p.equal(guards[1].callback,binding.wrapper)
        or guards[2].name~='getCorrectSquareForWall'or not p.equal(guards[2].callback,luautils.getCorrectSquareForWall)
        or not spatialPlain(installed[luautils])or not p.equal(installed[luautils].walkAdj,binding)
        or not p.equal(knownWrappers[binding.wrapper],binding) or not p.equal(luautils.walkAdj,binding.wrapper) then return end
    local token=p.own(action,'toolkitQueueOperation')
    if token~=nil and(not spatialPlain(token)or token.toolkitStarted or token.toolkitCancelled)then return end
    local specifications={
        {owner=record,exact=true},{owner=record.marker,exact=true},{owner=request,exact=true},{owner=binding,exact=true},
        {owner=args,exact=true},{owner=record.args,exact=true},{owner=spec,exact=true},
        {owner=spec.arrays,exact=true},{owner=guards,exact=true},
        {owner=guards[1],exact=true},{owner=guards[2],exact=true},
        {owner=luautils,keys={'walkAdj','getCorrectSquareForWall'}},
        {owner=installed,keys={luautils}},{owner=installed[luautils],keys={'walkAdj'}},
        {owner=knownWrappers,keys={binding.wrapper}},{owner=attestations,keys={binding}},
        {owner=first,exact=true},
    }
    if args[4]then specifications[#specifications+1]={owner=args[4],exact=true}end
    if token then specifications[#specifications+1]={owner=token,keys={'toolkitStarted','toolkitCancelled'}}end
    local requestWatch=p.capture(specifications)
    if not requestWatch or not rootWatch()then return end
    if not p.origin(p.isCommand,'ActionQueueOperations.lua')
        or not p.origin(p.construction,'ActionQueueOperations.lua')
        or not p.origin(commandFactory,'ActionQueueOperations.lua')
        or not p.origin(commandNew,'ISQueueActionsAction.lua')or not p.origin(baseNew,'ISBaseTimedAction.lua')
        or not p.origin(resolve,'ActionQueueApproach.lua')
        or not p.origin(binding.callback,'luautils.lua')
        or not p.origin(guards[2].callback,'luautils.lua')then return end
    if spatialSources==nil then
        local trusted=p.matches('media/lua/shared/luautils.lua',937393183,nil,true)
            and p.matches('media/lua/client/TimedActions/ISQueueActionsAction.lua',687313299,nil,true)
            and p.matches('media/lua/shared/TimedActions/ISBaseTimedAction.lua',3104185167,nil,true)
        if not rootWatch()or not requestWatch()or not inheritanceWatch()then return end
        spatialSources=trusted
    end
    if not spatialSources or not rootWatch()or not requestWatch()or not inheritanceWatch()
        or not p.construction()or not p.isCommand(action)or not rootWatch()or not requestWatch()or not inheritanceWatch()then return end
    local description={version=1,kind='deferred-spatial',actor=args[1],targetSquare=args[2],
        invalidates='all-resources',routing='native',expansion='native',outcome='native'}
    local descriptorWatch=p.capture({{owner=description,exact=true}})
    if not descriptorWatch then return end
    return function()
        return rootWatch()and requestWatch()and inheritanceWatch()and descriptorWatch()
    end,description
end
function Approach.prepareSpatialLease(action)
    local watch,description=prepareSpatialRequest(action)
    if not watch then return end
    local used=false
    return function()
        if used then return false end
        used=true
        return watch()
    end,description
end
spatialFactory=Approach.prepareSpatialLease

-- The canonical checker is a trusted native bootstrap root, like the existing
-- actual-metatable helper. Its Java implementation certifies its own exact
-- entry and the geometry helper's reflected Method, not merely invoker classes.
-- Replacing every bootstrap root before Toolkit loads is outside this model.
local spatialEditFactory
local spatialEditApis={read=toolkitQueueSpatialNoMovement,check=toolkitQueueSpatialApiMatches,
    className=getClassSimpleName,call=pcall}
local function prepareSpatialEdit(action,targetObject)
    local p,api=spatialPrimitives,spatialEditApis
    if not spatialPrimitiveWatch or not spatialPrimitiveWatch()or not spatialPlain(Approach)
        or not p.equal(p.raw(Approach,'prepareSpatialEditLease'),spatialEditFactory)
        or not p.equal(p.raw(Approach,'prepareSpatialLease'),spatialFactory)
        or not spatialPlain(p.globals)or p.kind(api.read)~='function'or p.kind(api.check)~='function'
        or p.kind(api.className)~='function'or p.kind(api.call)~='function'then return end
    local bindings=p.capture({
        {owner=p.globals,keys={'toolkitQueueSpatialNoMovement','toolkitQueueSpatialApiMatches','getClassSimpleName','pcall'}},
        {owner=Approach,keys={'prepareSpatialEditLease','prepareSpatialLease'}},
    })
    local function unchanged()
        return bindings()and p.equal(p.raw(p.globals,'toolkitQueueSpatialNoMovement'),api.read)
            and p.equal(p.raw(p.globals,'toolkitQueueSpatialApiMatches'),api.check)
            and p.equal(p.raw(p.globals,'getClassSimpleName'),api.className)and p.equal(p.raw(p.globals,'pcall'),api.call)
    end
    if not bindings or not unchanged()or p.kind(action)~='table'then return end
    local record=p.own(action,'toolkitQueueCommand')
    local request=spatialPlain(record)and p.own(record,'snapshot')
    local args=spatialPlain(request)and p.own(request,'args')
    if not spatialPlain(args)or args[3]~=true then return end
    -- Class is only a bootstrap gate for the dedicated trusted checker. That
    -- checker's exact self/env/frame certificate then proves the geometry API.
    local class=api.className(api.check)
    if class~='LuaJavaInvoker'and class~='MultiLuaJavaInvoker'or not unchanged()or api.check(api.read)~=true then return end
    local sourceCheck=prepareSpatialRequest(action)
    if not sourceCheck or not unchanged()then return end
    local actor,target,exclusions=args[1],args[2],args[4]
    -- Provision only an initially eligible no-op. Unsupported/far requests
    -- retain the ordinary legacy edit policy rather than acquiring a proof
    -- that would subsequently turn its existing allowance into a denial.
    if not sourceCheck()then return end
    local certified,canonical=api.call(api.check,api.read)
    if not certified or canonical~=true or not unchanged()or not sourceCheck()then return end
    local observed,near=api.call(api.read,actor,target,exclusions,targetObject)
    if not observed or near~=true or not unchanged()or not sourceCheck()then return end
    local edit={version=1,complete=true,capacity='unchanged',resources={}}
    local editWatch=p.capture({{owner=edit,exact=true},{owner=edit.resources,exact=true}})
    if not editWatch then return end
    local used=false
    return function()
        if used then return false end
        used=true
        -- Check the immutable source/request both sides of the certified,
        -- callback-free Java reader. No Lua engine getter or route runs.
        local valid=sourceCheck()
        if not valid or not unchanged()or not editWatch()then return false end
        local ok,canonical=api.call(api.check,api.read)
        if not ok or canonical~=true or not unchanged()then return false end
        local observed,near=api.call(api.read,actor,target,exclusions,targetObject)
        return observed and near==true and unchanged()and sourceCheck()and editWatch()
    end,edit
end
function Approach.prepareSpatialEditLease(action,targetObject)
    local ok,check,edit=spatialEditApis.call(prepareSpatialEdit,action,targetObject)
    if ok then return check,edit end
end
spatialEditFactory=Approach.prepareSpatialEditLease
return Approach
