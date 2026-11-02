if not NativeActionRoot then
    if TestCoverage then TestCoverage('source-contract','skipped','Native action sources unavailable; pass --game or --native-action-root.')end
    return
end
-- Production uses only game metadata accessors. Native Kahlua has no debug library.
local filename=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
local firstLine=NativeFirstLineOfClosure or getFirstLineOfClosure
    or debug and function(callback)return debug.getinfo(callback,'S').linedefined end
assert(type(firstLine)=='function','Bulk binding fixture requires the native first-line accessor')
local function setup(options)
    options=options or {}
    local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    local effects,metadataReads=0,0
    local forbidden,hook=false,nil
    local function effect()effects=effects+1;error('binding invoked native/gameplay effect')end
    local function metadata(kind,callback,reader)
        assert(not forbidden,'metadata read after Bulk binding lease')
        metadataReads=metadataReads+1
        if hook then local visit=hook;hook=nil;visit(kind,callback)end
        return reader(callback)
    end
    getFilenameOfClosure=function(callback)return metadata('filename',callback,filename)end
    getFirstLineOfClosure=not options.noLine and function(callback)return metadata('line',callback,firstLine)end or nil
    isClient=function()return false end
    createItemTransaction,removeItemTransaction,isItemTransactionDone,isItemTransactionRejected=effect,effect,effect,effect
    InventoryItemFactory={CreateItem=effect};instanceItem=effect;getTimestampMs=effect
    getGameFilesInput,getModFileReader=effect,effect
    luautils={haveToBeTransfered=effect}
    ISInventoryTransferUtil={newInventoryTransferAction=effect}
    PZSurvivorToolkit.ActionQueueExecution={beforeStop=effect}
    PZSurvivorToolkit.ActionQueuePickupFailure={beforeStop=effect}
    PZSurvivorToolkit.Settings.actionQueue=effect
    local loadedProof
    local proofCalls={}
    local beforeRequire=require
    require=function(name)
        if name=='PZSurvivorToolkit/SourceProof' then
            if options.noProof then return nil end
            if not loadedProof then
                loadedProof=beforeRequire(name)
                if options.trackProof then
                    local sourceClosure=loadedProof.closure
                    loadedProof.closure=function(callback,path)
                        proofCalls[#proofCalls+1]=callback
                        return sourceClosure(callback,path)
                    end
                end
            end
            return loadedProof
        end
        return beforeRequire(name)
    end
    local actions=f.project('BulkActions')
    local function action()
        return f.action(ISInventoryTransferAction,{transactionId=0,
            item={getID=effect,getFullType=effect,getContainer=effect},
            srcContainer={getType=effect,getItems=effect},destContainer={getType=effect,getItems=effect}})
    end
    local function guarded(custom,merge)
        local value=action()
        if custom then value.onCompleteFunc=custom end
        local original=value.stop
        actions.guardTransfer(value,merge)
        return value,original
    end
    local function receiptKey(guard)
        local key
        for candidate,value in pairs(guard)do
            if type(candidate)=='table'and type(value)=='function'then assert(not key);key=candidate end
        end
        return assert(key,'missing per-guard receipt')
    end
    return {actions=actions,guarded=guarded,action=action,proof=function()return loadedProof end,
        receiptKey=receiptKey,effect=effect,proofCalls=proofCalls,hook=function(value)hook=value end,
        forbid=function()forbidden=true end,
        counts=function()return effects,metadataReads end}
end
local function lease(s,action,original,effective)
    local value,description=s.actions.transferBinding(action,original,effective)
    assert(type(value)=='function','expected source-owned Bulk binding lease')
    assert(type(description)=='table'and getmetatable(description)==nil,'expected plain Bulk layer description')
    return value,description
end
local function copy(value)local result={};for key,field in pairs(value)do result[key]=field end;return result end

-- The same per-action no-op and guarded stop survive repeated normal adoption.
do
    local s=setup();local action,original=s.guarded()
    local complete,stop,guard=action.onCompleteFunc,action.stop,action.toolkitTransferGuard
    assert(s.actions.isGuardedTransfer(action,original))
    assert(s.actions.guardTransfer(action)==action and action.onCompleteFunc==complete
        and action.stop==stop and action.toolkitTransferGuard==guard)
    local validate=lease(s,action,original)
    local beforeEffects,beforeMetadata=s.counts()
    s.forbid()
    assert(validate()and not validate(),'Bulk lease must be pure and single-use')
    local afterEffects,afterMetadata=s.counts()
    assert(afterEffects==beforeEffects and afterEffects==0 and afterMetadata==beforeMetadata,
        'post-facts Bulk validation performed effects or metadata reads')
end

-- Normal stop ordering/delegation remains unchanged; this explicitly invokes
-- only harmless fixture callbacks, separate from the read-only lease checks.
do
    local s=setup();local action=s.action();local calls={}
    local original=function(self)assert(self==action);calls[#calls+1]='native';return 'stopped'end
    action.stop=original
    PZSurvivorToolkit.ActionQueueExecution={beforeStop=function(self)assert(self==action);calls[#calls+1]='execution'end}
    PZSurvivorToolkit.ActionQueuePickupFailure={beforeStop=function(self)assert(self==action);calls[#calls+1]='pickup'end}
    s.actions.guardTransfer(action)
    assert(action:stop()=='stopped'and table.concat(calls,',')=='execution,pickup,native')
    assert(s.counts()==0)
end

-- Independent receipt/lease owners do not share their no-op identity or retain a
-- global action registry. Reading one action does not consume another lease.
do
    local s=setup();local first,original=s.guarded();local second,otherOriginal=s.guarded()
    assert(first.onCompleteFunc~=second.onCompleteFunc,'per-action native no-op identity changed')
    local one,two=lease(s,first,original),lease(s,second,otherOriginal)
    s.forbid();assert(one()and two())
end

-- Per-action receipts never enter SourceProof's shared callback cache.
do
    local s=setup({trackProof=true});local action,original=s.guarded()
    local validate,description=lease(s,action,original)
    local receipt=action.toolkitTransferGuard[s.receiptKey(action.toolkitTransferGuard)]
    assert(#s.proofCalls>0)
    for _,callback in ipairs(s.proofCalls)do assert(callback~=receipt,'SourceProof retained an action-bound receipt')end
    assert(description.wrappedStop==action.stop and description.stop==original
        and description.onComplete==action.onCompleteFunc)
    s.forbid();assert(validate())
end

-- An explicit effective pointer proves exactly the sealed Bulk layer. It never
-- makes a default unknown outer wrapper pass; the composer owns that proof.
for _,mode in ipairs({'valid','outer-mutated','layer-mutated','description-mutated'})do
    local s=setup();local action,original=s.guarded();local sealed=action.stop
    local outer=function()error('outer wrapper invoked by provenance read')end
    action.stop=outer
    assert(s.actions.transferBinding(action,original)==nil,'unknown outer wrapper accepted by default')
    assert(s.actions.transferBinding(action,original,s.effect)==nil,'unsealed effective pointer accepted')
    local validate,description=lease(s,action,original,sealed)
    assert(description.wrappedStop==sealed and description.stop==original
        and description.onComplete==action.onCompleteFunc)
    if mode=='outer-mutated'then action.stop=s.effect
    elseif mode=='layer-mutated'then action.toolkitTransferGuard.stop=s.effect
    elseif mode=='description-mutated'then description.stop=s.effect end
    s.forbid();assert(validate()==(mode=='valid')and s.counts()==0)
end
-- The opposite order describes the exact delegate captured inside Bulk; the
-- caller must still prove that delegate, rather than assuming it is native.
do
    local s=setup();local action=s.action();local native=action.stop
    local inner=function()error('inner wrapper invoked by provenance read')end
    action.stop=inner;s.actions.guardTransfer(action)
    assert(s.actions.transferBinding(action,native)==nil,'wrapped delegate confused with native stop')
    local validate,description=lease(s,action,inner)
    assert(description.stop==inner and description.wrappedStop==action.stop)
    s.forbid();assert(validate()and s.counts()==0)
end

-- Existing custom callbacks, optional native merging and unavailable provenance
-- retain normal guard behavior while granting no lease.
for _,mode in ipairs({'custom','merge','no-proof','no-line'})do
    local s=setup({noProof=mode=='no-proof',noLine=mode=='no-line'})
    local custom=mode=='custom'and s.effect or nil
    local action,original=s.guarded(custom,mode=='merge')
    assert(s.actions.isGuardedTransfer(action,original))
    if custom then assert(action.onCompleteFunc==custom)end
    if mode=='merge'then assert(action.onCompleteFunc==nil)end
    assert(s.actions.transferBinding(action,original)==nil,mode..' unexpectedly received a lease')
    assert(s.counts()==0)
end

-- Copying the public marker/record or transplanting its genuine receipt never
-- proves another guard/action; neither an owner callback nor a native stop runs.
for _,mode in ipairs({'copy-guard','copy-action','transplant-receipt','transplant-noop','fake-receipt',
    'same-file-stop','same-file-transfer','same-file-binding','same-file-noop'})do
    local s=setup();local action,original=s.guarded();local guard=action.toolkitTransferGuard
    local other,otherOriginal=s.guarded();local key=s.receiptKey(guard)
    local fakeCalls=0
    if mode=='copy-guard'then action.toolkitTransferGuard=copy(guard)
    elseif mode=='copy-action'then local duplicate=copy(action);setmetatable(duplicate,getmetatable(action));action=duplicate
    elseif mode=='transplant-receipt'then guard[key]=other.toolkitTransferGuard[key]
    elseif mode=='transplant-noop'then action.onCompleteFunc=other.onCompleteFunc;action.toolkitQueueSafeOnComplete=other.onCompleteFunc
    elseif mode=='fake-receipt'then guard[key]=function()fakeCalls=fakeCalls+1;error('foreign receipt invoked')end
    elseif mode=='same-file-stop'then guard[key]=action.stop
    elseif mode=='same-file-transfer'then guard[key]=s.actions.transfer
    elseif mode=='same-file-binding'then guard[key]=s.actions.transferBinding
    elseif mode=='same-file-noop'then guard[key]=action.onCompleteFunc end
    assert(s.actions.transferBinding(action,original)==nil,'forged Bulk owner accepted: '..mode)
    assert(fakeCalls==0 and s.counts()==0,'forged Bulk callback executed: '..mode)
end

-- A successful receipt is still a narrowly watched capability: any selected
-- field/owner replacement invalidates it, using raw identity rather than __eq.
for _,mode in ipairs({'stop','guard','marker','original','receipt','complete','safe','action-meta','guard-meta',
    'guard-extra','toolkit','module','factory','guard-api','guarded-api','source-proof','filename','first-line'})do
    local s=setup();local action,original=s.guarded();local validate=lease(s,action,original)
    local guard=action.toolkitTransferGuard
    local metaCalls=0
    local function metaEffect()metaCalls=metaCalls+1;error('metatable callback invoked')end
    if mode=='stop'then action.stop=s.effect
    elseif mode=='guard'then action.toolkitTransferGuard=copy(guard)
    elseif mode=='marker'then guard.marker={}
    elseif mode=='original'then guard.original=s.effect
    elseif mode=='receipt'then guard[s.receiptKey(guard)]=s.effect
    elseif mode=='complete'then action.onCompleteFunc=s.effect
    elseif mode=='safe'then action.toolkitQueueSafeOnComplete=s.effect
    elseif mode=='action-meta'then setmetatable(action,{__index=metaEffect,__eq=metaEffect})
    elseif mode=='guard-meta'then setmetatable(guard,{__index=metaEffect,__eq=metaEffect})
    elseif mode=='guard-extra'then guard.extra=true
    elseif mode=='toolkit'then PZSurvivorToolkit={}
    elseif mode=='module'then PZSurvivorToolkit.BulkActions={}
    elseif mode=='factory'then s.actions.transferBinding=s.effect
    elseif mode=='guard-api'then s.actions.guardTransfer=s.effect
    elseif mode=='guarded-api'then s.actions.isGuardedTransfer=s.effect
    elseif mode=='source-proof'then s.proof().closure=s.effect
    elseif mode=='filename'then getFilenameOfClosure=s.effect
    elseif mode=='first-line'then getFirstLineOfClosure=s.effect end
    s.forbid()
    assert(not validate()and not validate(),'mutated Bulk lease remained available: '..mode)
    assert(metaCalls==0 and s.counts()==0,'mutation validation invoked callback: '..mode)
end

-- Missing own fields cannot be supplied by native Kahlua's inherited rawget.
do
    local s=setup();local action,original=s.guarded();local validate=lease(s,action,original)
    local meta=getmetatable(action)
    meta.toolkitQueueSafeOnComplete=action.toolkitQueueSafeOnComplete
    action.toolkitQueueSafeOnComplete=nil
    s.forbid();assert(not validate()and s.counts()==0)
end

-- Metadata is allowed only during preparation. Mutations and reentry there
-- must invalidate the outer read before its private receipt can be adopted.
for _,mode in ipairs({'mutate','reenter','replace-line','replace-proof','error'})do
    local s=setup();local action,original=s.guarded();local nested
    s.hook(function()
        if mode=='mutate'then action.toolkitTransferGuard.original=s.effect
        elseif mode=='reenter'then nested=s.actions.transferBinding(action,original)
        elseif mode=='replace-line'then getFirstLineOfClosure=function()return 1 end
        elseif mode=='replace-proof'then s.proof().closure=s.effect
        elseif mode=='error'then error('metadata unavailable')end
    end)
    assert(s.actions.transferBinding(action,original)==nil,'metadata mutation/reentry accepted: '..mode)
    assert(nested==nil and s.counts()==0)
end

-- A setter which substitutes another callback is preserved by the guard, but
-- cannot turn that callback into the private owned no-op.
do
    local s=setup();local action=s.action();local original=action.stop
    action.setOnComplete=function(self)self.onCompleteFunc=s.effect end
    s.actions.guardTransfer(action)
    assert(action.onCompleteFunc==s.effect and action.toolkitQueueSafeOnComplete==s.effect)
    assert(s.actions.transferBinding(action,original)==nil and s.counts()==0)
end
-- Oversized extension tables stay unknown without an unbounded lease scan.
do
    local s=setup();local action,original=s.guarded()
    for index=1,129 do action['extension'..index]=index end
    assert(s.actions.transferBinding(action,original)==nil and s.counts()==0)
end
print('Bulk transfer binding PASS (native source, private ownership, pure one-use lease, aliases, mutation/reentry).')
if TestCoverage then TestCoverage('source-contract','passed')end
