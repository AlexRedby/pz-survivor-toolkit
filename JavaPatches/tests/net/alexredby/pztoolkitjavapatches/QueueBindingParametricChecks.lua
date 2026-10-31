-- Test-only native Kahlua causal checks; constructors/counters are supplied by the Java test host.
local nativePairs=pairs
local checks=0
local function test(label,body)
 local old,new=body(false),body(true)
 assert(old==new,label..': baseline/candidate differ '..tostring(old)..'/'..tostring(new))
 checks=checks+1;Emit('PARAMETRIC_CASE '..label..' '..tostring(old))
end
local function classGuard(own,lifecycle)return(own and ParamClassFactory or OriginalClassFactory)(lifecycle or {})end
local function policy(own,radioMethods,lifecycle,transfer)
 local state={resources=0,priorCalls=0,toolkit={}}
 state.class={Type='Fixture',start=function()end,stop=function()end}
 state.action=setmetatable({Type='Fixture',mode='Toggle'},state.class)
 state.snapshot={class=state.class,methods={start=state.class.start,stop=state.class.stop},helpers={}}
 state.floor={previous=function()end,replacement=function()end}
 state.destination={getType=function()return 'bag'end}
 local resources=function()state.resources=state.resources+1;return{targets={}}end
 local helpers=function()state.priorCalls=state.priorCalls+1;return true end
 state.radio,state.matches=(own and ParamPolicyFactory or OriginalPolicyFactory)({Toggle=true},radioMethods or {},lifecycle or {},resources,nil,state.toolkit,transfer and state.class or {},state.floor,function(value,kind)return value==state.destination and kind=='ItemContainer'end,helpers,function()return true end)
 return state
end
local function supported(own,before,wanted)if own then assert(Hits()-before==wanted,'unexpected native hit count '..(Hits()-before)..' wanted '..wanted)end end

test('plain-class-fresh-owner-and-map',function(own)
 local guard=classGuard(own);local a,b=function()end,function()end;local first=Hits()
 assert(guard({helper=a},{helper=a}));assert(guard({helper=b},{helper=b}));supported(own,first,2)
 assert(not guard({helper=b},{helper=a}));supported(own,first,2)
 return true
end)
test('class-raw-metatable-inheritance',function(own)
 local f=function()end;local owner=setmetatable({},{helper=f});local guard=classGuard(own);local before=Hits()
 assert(guard(owner,{helper=f}));supported(own,before,1);return true
end)
test('class-index-table-chain',function(own)
 local f=function()end;local index=setmetatable({},{__index={helper=f}})
 local owner=setmetatable({},{__index=index});local guard=classGuard(own);local before=Hits()
 assert(guard(owner,{helper=f}));supported(own,before,1);return true
end)
test('raw-field-precedes-function-index',function(own)
 local f=function()end;local calls=0;local owner=setmetatable({},{helper=f,__index=function()calls=calls+1;error('index called')end})
 local before=Hits();assert(classGuard(own)(owner,{helper=f}));supported(own,before,1);assert(calls==0);return calls
end)
test('function-index-fallback',function(own)
 local f=function()end;local calls=0;local owner=setmetatable({},{__index=function(_,key)calls=calls+1;assert(key=='helper');return f end})
 local before=Hits();assert(classGuard(own)(owner,{helper=f}));supported(own,before,0);assert(calls==1);return calls
end)
test('following-lifecycle-remains-fresh',function(own)
 local f,g=function()end,function()end;local reads=0
 local owner=setmetatable({},{__index=function(_,key)assert(key=='start');reads=reads+1;return reads==1 and f or g end})
 local before=Hits();assert(not classGuard(own,{'start'})(owner,{start=f}));supported(own,before,0);assert(reads==2);return reads
end)
test('class-false-is-not-normalized',function(own)
 local before=Hits();assert(not classGuard(own)({},{helper=false}));supported(own,before,0);return true
end)
test('radio-nil-false-normalization',function(own)
 local p=policy(own,{missing=false,ownFalse=false});p.action.ownFalse=false;local before=Hits()
 assert(p.radio(p.action,true));supported(own,before,1);assert(p.resources==1);return p.resources
end)
test('native-helper-nil-false-normalization',function(own)
 local p=policy(own);p.snapshot.helpers={missing=false,ownFalse=false};p.action.ownFalse=false;local before=Hits()
 assert(p.matches(p.action,p.snapshot));supported(own,before,1);return true
end)
test('native-boolEval-reference-semantics',function(own)
 local p=policy(own,{helper=NonCanonicalFalse,float=FloatNaN});p.action.helper=NonCanonicalFalse;p.action.float=FloatNaN;local before=Hits()
 assert(p.radio(p.action,true));supported(own,before,1);return true
end)
test('map-mutation-is-fresh',function(own)
 local guard=classGuard(own);local f,g=function()end,function()end;local expected={helper=f};local owner={helper=f};local before=Hits()
 assert(guard(owner,expected));owner.helper=g;expected.helper=g;assert(guard(owner,expected));expected.extra=false;owner.extra=false;assert(guard(owner,expected));supported(own,before,3);return true
end)
test('initial-unsupported-does-not-cache-arguments',function(own)
 local guard=classGuard(own);local f=function()end;ForeignTable.helper=f;local before=Hits()
 assert(guard(ForeignTable,{helper=f}));assert(guard({helper=f},{helper=f}));supported(own,before,1);ForeignTable.helper=nil;return true
end)
test('rewritten-owner-fallback',function(own)
 local guard=classGuard(own);local f=function()end;Rewritten.helper=f;local before=Hits();assert(guard(Rewritten,{helper=f}));supported(own,before,0);Rewritten.helper=nil;return true
end)
for _,verdict in ipairs({false,true})do
 test('function-equality-'..tostring(verdict),function(own)
  local f,g=function()end,function()end;local eq=0;FunctionMeta.__eq=function()eq=eq+1;return verdict end
  local before=Hits();assert(classGuard(own)({helper=f},{helper=g})==verdict);supported(own,before,0);FunctionMeta.__eq=nil;assert(eq==1);return eq
 end)
end
test('double-nan-fallback',function(own)
 local nan=0/0;local before=Hits();assert(not classGuard(own)({helper=nan},{helper=nan}));supported(own,before,0);return true
end)
test('selected-pairs-before-getter-replaces',function(own)
 local p=policy(own);local reads,foreign=0,0;local helpers={missing=false};p.snapshot.helpers=nil
 setmetatable(p.snapshot,{__index=function(_,key)if key=='helpers'then reads=reads+1;pairs=function(t)foreign=foreign+1;return nativePairs(t)end;return helpers end end})
 local before=Hits();assert(p.matches(p.action,p.snapshot));supported(own,before,0);pairs=nativePairs;assert(reads==1 and foreign==0);return reads..':'..foreign
end)
test('selected-pairs-before-getter-restores',function(own)
 local p=policy(own);local reads,foreign=0,0;local helpers={missing=false};p.snapshot.helpers=nil
 setmetatable(p.snapshot,{__index=function(_,key)if key=='helpers'then reads=reads+1;pairs=nativePairs;return helpers end end})
 pairs=function(t)foreign=foreign+1;return nativePairs(t)end
 local before=Hits();assert(p.matches(p.action,p.snapshot));supported(own,before,0);pairs=nativePairs;assert(reads==1 and foreign==1);return reads..':'..foreign
end)
test('helpers-getter-exactly-once-and-fresh-map',function(own)
 local p=policy(own);local reads=0;p.snapshot.helpers=nil
 setmetatable(p.snapshot,{__index=function(_,key)if key=='helpers'then reads=reads+1;return reads==1 and{first=false}or{second=false}end end})
 local before=Hits();assert(p.matches(p.action,p.snapshot));assert(p.matches(p.action,p.snapshot));supported(own,before,2);assert(reads==2);return reads
end)
test('helpers-getter-reentrant-distinct-map',function(own)
 local p=policy(own);local reads=0;local trace={};p.snapshot.helpers=nil
 local inner={class=p.class,methods=p.snapshot.methods,helpers={inner=false}}
 setmetatable(p.snapshot,{__index=function(_,key)if key=='helpers'then reads=reads+1;trace[#trace+1]='helpers';local result=p.matches(p.action,inner);trace[#trace+1]='nested:'..tostring(result);return{outer=false}end end})
 local before=Hits();assert(p.matches(p.action,p.snapshot));supported(own,before,2);assert(reads==1);return table.concat(trace,',')
end)
test('native-audited-floor-mismatch-falls-back',function(own)
 local p=policy(own,nil,nil,true);p.action.getNotFullFloorSquare=p.floor.replacement;p.action.destContainer=p.destination;p.snapshot.helpers={getNotFullFloorSquare=p.floor.previous};local before=Hits()
 assert(p.matches(p.action,p.snapshot));supported(own,before,0);assert(p.priorCalls==1);return p.priorCalls
end)
test('native-ordinary-lifecycle-guard-kept',function(own)
 local p=policy(own,nil,{'start'});p.action.start=function()end;local before=Hits();assert(not p.matches(p.action,p.snapshot));supported(own,before,0);return true
end)
test('replaced-pairs-callback',function(own)
 local f=function()end;local guard=classGuard(own);assert(guard({helper=f},{helper=f}));local calls=0
 pairs=function(t)calls=calls+1;return nativePairs(t)end;local before=Hits();assert(guard({helper=f},{helper=f}));supported(own,before,0);pairs=nativePairs;assert(calls==1);return calls
end)
test('foreign-pairs-yields-on-original-path',function(own)
 local f=function()end;local guard=classGuard(own);assert(guard({helper=f},{helper=f}));local before=Hits()
 pairs=function(t)coroutine.yield('pairs-pause');return nativePairs(t)end
 local co=coroutine.create(function()return guard({helper=f},{helper=f})end);local ok,value=coroutine.resume(co);assert(ok and value=='pairs-pause');ok,value=coroutine.resume(co);assert(ok and value==true and coroutine.status(co)=='dead');pairs=nativePairs;supported(own,before,0);return true
end)
test('selected-foreign-pairs-yields-after-getter',function(own)
 local p=policy(own);local reads=0;p.snapshot.helpers=nil
 setmetatable(p.snapshot,{__index=function(_,key)if key=='helpers'then reads=reads+1;pairs=nativePairs;return{missing=false}end end})
 pairs=function(t)coroutine.yield('saved-pairs-pause');return nativePairs(t)end;local before=Hits()
 local co=coroutine.create(function()return p.matches(p.action,p.snapshot)end);local ok,value=coroutine.resume(co);assert(ok and value=='saved-pairs-pause'and reads==1);ok,value=coroutine.resume(co);assert(ok and value==true and reads==1);pairs=nativePairs;supported(own,before,0);return true
end)
test('same-prototype-different-caller',function(own)
 local guard=classGuard(own);local f=function()end;assert(guard({helper=f},{helper=f}));local before=Hits();local clone=CloneSamePrototype(guard)
 assert(clone({helper=f},{helper=f}));supported(own,before,0);return true
end)
test('actual-caller-fenv',function(own)
 local guard=classGuard(own);local f=function()end;assert(guard({helper=f},{helper=f}));local calls=0;local before=Hits()
 local alternate=setmetatable({pairs=function(t)calls=calls+1;return nativePairs(t)end},{__index=_G});setfenv(guard,alternate);assert(guard({helper=f},{helper=f}));supported(own,before,0);setfenv(guard,_G);assert(calls==1);return calls
end)
test('debug-fallback',function(own)
 local guard=classGuard(own);local f=function()end;local before=Hits();SetDebug(true);assert(guard({helper=f},{helper=f}));SetDebug(false);supported(own,before,0);return true
end)
test('table-index-cycle-fallback-error',function(own)
 local a,b={},{};setmetatable(a,{__index=b});setmetatable(b,{__index=a});local before=Hits();local ok,message=pcall(classGuard(own),a,{missing=false});assert(not ok);supported(own,before,0);return tostring(message):find('loop in gettable',1,true)~=nil
end)
-- Direct test-only native resolver probe avoids invoking the baseline's unbounded
-- raw-metatable recursion for a missing key in a raw metatable cycle.
local a,b={},{};setmetatable(a,b);setmetatable(b,a);local ok=ProbePureLookup(a,'missing');assert(ok==false)
local deep={};for i=1,18 do deep=setmetatable({},{__index=deep})end;assert(ProbePureLookup(deep,'missing')==false)
assert(ProbePureLookup(UnknownOwner,'missing')==false)
Emit('PARAMETRIC_PROOF cases='..checks..' boundedUnsupported=3 aliasGetterOnce=true selectedIteratorPreserved=true qualification=false')

local nativeIpairs=ipairs
local lifeChecks=0
local function lifeTest(label,body)
 local a,b=body(false),body(true);assert(a==b,label..': outcomes differ');lifeChecks=lifeChecks+1;Emit('LIFECYCLE_CASE '..label..' '..tostring(a))
end
local function lifeHit(own,before,count)if own then assert(LifeHits()-before==count,'lifecycle hits '..(LifeHits()-before)..' expected '..count)end end
lifeTest('known-nil-and-inheritance',function(own)
 local f=function()end;local before=LifeHits();assert(classGuard(own,{'absent','start'})(setmetatable({},{start=f}),{start=f}));lifeHit(own,before,1);return true
end)
lifeTest('raw-ipairs-list-inheritance',function(own)
 local f=function()end;local list=setmetatable({},{[1]='start'});local before=LifeHits();assert(classGuard(own,list)({start=f},{start=f}));lifeHit(own,before,1);return true
end)
lifeTest('list-index-function-not-called',function(own)
 local calls=0;local list=setmetatable({},{__index=function()calls=calls+1;error('ipairs must use rawget')end});local before=LifeHits();assert(classGuard(own,list)({},{}));lifeHit(own,before,1);return calls
end)
lifeTest('list-hole-terminates',function(own)
 local f=function()end;local before=LifeHits();assert(classGuard(own,{[1]='start',[3]='bad'})({start=f,bad=f},{start=f}));lifeHit(own,before,1);return true
end)
lifeTest('fresh-lifecycle-and-maps',function(own)
 local list={'start'};local f=function()end;local guard=classGuard(own,list);local before=LifeHits();assert(guard({start=f},{start=f}));list[1]='absent';assert(guard({},{}));lifeHit(own,before,2);return true
end)
lifeTest('whole-loop-fallback-keeps-getter-prefix',function(own)
 local trace={};local methods=setmetatable({},{__index=function(_,key)trace[#trace+1]=key;return nil end});local before=LifeHits();assert(classGuard(own,{'first','second'})({},methods));lifeHit(own,before,0);return table.concat(trace,',')
end)
lifeTest('snapshot-methods-getter-per-field',function(own)
 local p=policy(own,nil,{'start','stop'});p.snapshot.methods=nil;local calls=0
 setmetatable(p.snapshot,{__index=function(_,key)if key=='methods'then calls=calls+1;return{start=p.class.start,stop=p.class.stop}end end})
 local before=LifeHits();assert(p.matches(p.action,p.snapshot));lifeHit(own,before,0);assert(calls==2);return calls
end)
lifeTest('native-expected-map-pure-inheritance',function(own)
 local p=policy(own,nil,{'start','stop'});p.snapshot.methods=setmetatable({},{start=p.class.start,stop=p.class.stop});local before=LifeHits();assert(p.matches(p.action,p.snapshot));lifeHit(own,before,1);return true
end)
lifeTest('bulk-stop-audit-once-and-next-fresh-denial',function(own)
 local p=policy(own,nil,{'start','stop'},true);p.class.Type='ISInventoryTransferAction';p.action.Type=p.class.Type;p.action.stop=function()end;local calls=0
 p.toolkit.BulkActions={isGuardedTransfer=function(action,expected)calls=calls+1;assert(expected==p.class.stop);action.start=function()end;return true end}
 local before=LifeHits();assert(p.matches(p.action,p.snapshot));assert(not p.matches(p.action,p.snapshot));lifeHit(own,before,0);assert(calls==1);return calls
end)
lifeTest('bulk-stop-yield-original-frame',function(own)
 local p=policy(own,nil,{'start','stop'},true);p.class.Type='ISInventoryTransferAction';p.action.Type=p.class.Type;p.action.stop=function()end;local calls=0
 p.toolkit.BulkActions={isGuardedTransfer=function()calls=calls+1;coroutine.yield('bulk-stop');return true end}
 local before=LifeHits();local co=coroutine.create(function()return p.matches(p.action,p.snapshot)end);local ok,value=coroutine.resume(co);assert(ok and value=='bulk-stop');ok,value=coroutine.resume(co);assert(ok and value==true);lifeHit(own,before,0);return calls
end)
lifeTest('foreign-ipairs-yield',function(own)
 local guard=classGuard(own,{'absent'});local before=LifeHits();local calls=0
 ipairs=function(t)calls=calls+1;coroutine.yield('foreign-ipairs');return nativeIpairs(t)end
 local co=coroutine.create(function()return guard({},{})end);local ok,value=coroutine.resume(co);assert(ok and value=='foreign-ipairs');ok,value=coroutine.resume(co);assert(ok and value==true);ipairs=nativeIpairs;lifeHit(own,before,0);return calls
end)
lifeTest('same-prototype-clone-lifecycle',function(own)
 local guard=classGuard(own,{'absent'});assert(guard({},{}));local before=LifeHits();assert(CloneSamePrototype(guard)({},{}));lifeHit(own,before,0);return true
end)
lifeTest('actual-fenv-lifecycle',function(own)
 local guard=classGuard(own,{'absent'});assert(guard({},{}));local calls=0;local before=LifeHits();local alternate=setmetatable({ipairs=function(t)calls=calls+1;return nativeIpairs(t)end},{__index=_G});setfenv(guard,alternate);assert(guard({},{}));setfenv(guard,_G);lifeHit(own,before,0);return calls
end)
Emit('LIFECYCLE_PROOF cases='..lifeChecks..' wholeLoopFallback=true bulkStopOriginal=true freshArguments=true')
QueueBindingParametricChecksPassed=true
