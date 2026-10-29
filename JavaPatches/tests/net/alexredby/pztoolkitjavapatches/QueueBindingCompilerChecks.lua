-- Test-only native Kahlua cases; constructors/counters come from the Java test host.
local originalPairs=pairs
local checks=0
local function makeCompat(own)
 local helper={isStaleVehicleContainer=function()end}
 local proximity={invName='inv',invName_corpses='corpses',isLockedForPlayer=function()end,setTransferRunning=function()end,hasQueuedTransferAction=function()end,isProximityType=function()end}
 local methods={};for k,v in pairs(proximity)do methods[k]=v end
 local owner={MODULE='TurnOffFridges',AUTO_KEY='TOF_auto',one=function()end,two=function()end,ON={fridgeoff='fridge',freezeroff='freezer'},OFF={fridge='fridgeoff',freezer='freezeroff'}}
 local functions={one=owner.one,two=owner.two}
 local constants={ON={map=owner.ON,values={fridgeoff='fridge',freezeroff='freezer'}},OFF={map=owner.OFF,values={fridge='fridgeoff',freezer='freezeroff'}}}
 EURY_CONTAINERS=helper;TurnOffFridges=owner
 local state={helper=helper,proximity=proximity,methods=methods,owner=owner,functions=functions,priorCalls=0}
 local factory=own and OwnedCompat or BaseCompat
 state.bc,state.fridge=factory(helper,helper.isStaleVehicleContainer,proximity,methods,owner,functions,constants,owner.MODULE,owner.AUTO_KEY,function()state.priorCalls=state.priorCalls+1;if state.prior then return state.prior()end;return true end)
 return state
end
local function makeCarts(own)
 local class={Type='ISCartTransferAction',method=function()end}
 local core={Network={sendToServer=function()end},isCart=function()end,safeIsCart=function()end}
 local methods={};for k,v in pairs(class)do methods[k]=v end
 local coreMethods={isCart=core.isCart,safeIsCart=core.safeIsCart}
 local cart={involvesCart=function()end,isTransfer=function()end,capacitySafe=function()end}
 local toolkit={ActionQueueCarts=cart};local compat={};toolkit.ActionQueueCompat=compat
 local state={class=class,methods=methods,core=core,coreMethods=coreMethods,cart=cart,toolkit=toolkit,compat=compat,priorCalls=0}
 local approved=function()end
 compat.isTransferPerform=function(value)state.priorCalls=state.priorCalls+1;assert(value==approved);if state.prior then return state.prior()end;return true end
 ISCartTransferAction=class;SaucedCarts=core
 state.guard=(own and OwnedCarts or BaseCarts)(true,nil,toolkit,cart,cart.involvesCart,cart.isTransfer,cart.capacitySafe,class,core,core.Network,approved,compat,compat.isTransferPerform,methods,coreMethods,core.Network.sendToServer)
 return state
end
local function test(label,callback)callback();checks=checks+1;Emit('QUEUE_BINDING_CASE '..label..' passed')end
local forged=0
Capture=function()forged=forged+1;return {}end;Fast=function()forged=forged+1;return true end;TestOwnRefsCapture=Capture
test('fresh-visits-three-owned-sites',function()
 local c=makeCompat(true);local k=makeCarts(true);local before=NativeHits();local captures=NativeCaptures()
 for i=1,10 do assert(c.bc()and c.fridge()and k.guard())end
 assert(NativeHits()==before+30 and NativeCaptures()==captures+3 and c.priorCalls==10 and k.priorCalls==10 and forged==0)
end)
test('original-lua-identity-and-lines',function()
 for _,label in ipairs({'bc','fridge'})do local a=makeCompat(false)[label];local b=makeCompat(true)[label];assert(type(a)=='function'and type(b)=='function'and NativeFilename(a)==NativeFilename(b)and NativeFirstLine(a)==NativeFirstLine(b)and getfenv(a)==getfenv(b))end
 local a,b=makeCarts(false).guard,makeCarts(true).guard;assert(NativeFilename(a)==NativeFilename(b)and NativeFirstLine(a)==NativeFirstLine(b))
end)
test('mismatch-falls-back-not-rejection',function()
 local c=makeCompat(true);assert(c.bc()and c.fridge());local before=NativeHits();c.proximity.invName=('x'..c.methods.invName):sub(2);assert(c.bc()and NativeHits()==before)
 c.owner.one=function()end;assert(not c.fridge()and NativeHits()==before)
end)
test('snapshot-mutation-additions-meta',function()
 local c=makeCompat(true);assert(c.bc());local before=NativeHits()
 c.methods.invName='new';c.proximity.invName='new';assert(c.bc()and NativeHits()==before)
 c.methods.extra=true;c.proximity.extra=true;assert(c.bc()and NativeHits()==before)
 c.methods.extra=nil;c.proximity.extra=nil;setmetatable(c.methods,{});assert(c.bc()and NativeHits()==before)
end)
test('owner-metatable-own-versus-inherited',function()
 local c=makeCompat(true);local calls=0;setmetatable(c.proximity,{__index=function(_,key)calls=calls+1;return c.methods[key]end})
 local before=NativeHits();assert(c.bc()and NativeHits()==before+1 and calls==0)
 c.proximity.invName=nil;before=NativeHits();assert(c.bc()and NativeHits()==before and calls==1)
end)
test('function-class-equality-original-path',function()
 for _,verdict in ipairs({true,false})do
  local c=makeCompat(true);assert(c.fridge());local eq=0;local before=NativeHits();c.owner.one=function()end
  FunctionMeta.__eq=function()eq=eq+1;return verdict end
  assert(c.fridge()==verdict and eq==1 and NativeHits()==before);FunctionMeta.__eq=nil
 end
end)
test('cart-normalized-false-missing-falls-back',function()
 local c=makeCarts(true);assert(c.guard());local before=NativeHits();c.coreMethods.isCart=false;c.core.isCart=nil
 assert(c.guard()and NativeHits()==before)
end)
test('prior-callback-still-precedes-live-loop',function()
 local c=makeCompat(true);assert(c.fridge());local before=NativeHits();local reads=0
 c.prior=function()c.owner.one=nil;setmetatable(c.owner,{__index=function(_,key)reads=reads+1;return c.functions[key]end});return true end
 assert(c.fridge()and reads==1 and NativeHits()==before)
end)
test('later-native-pairs-replacement',function()
 local c=makeCompat(true);local k=makeCarts(true);assert(c.bc()and c.fridge()and k.guard());local before=NativeHits();local loops=0
 pairs=function(t)loops=loops+1;return originalPairs(t)end
 assert(c.bc()and c.fridge()and k.guard()and loops==9 and NativeHits()==before)
 pairs=originalPairs
end)
test('preinstalled-pairs-cold-unsupported',function()
 local c=makeCompat(true);local loops=0;pairs=function(t)loops=loops+1;return originalPairs(t)end
 local before=NativeHits();assert(c.bc()and NativeHits()==before and loops==1);pairs=originalPairs
 assert(c.bc()and NativeHits()==before)
end)
test('actual-caller-environment',function()
 local c=makeCompat(true);assert(c.bc());local before=NativeHits();local loops=0
 local env=setmetatable({EURY_CONTAINERS=c.helper,pairs=function(t)loops=loops+1;return originalPairs(t)end},{__index=_G})
 setfenv(c.bc,env);assert(c.bc()and loops==1 and NativeHits()==before)
 env.EURY_CONTAINERS={};assert(c.bc()==false and loops==1 and NativeHits()==before)
 setfenv(c.bc,_G);assert(c.bc()and NativeHits()==before+1)
end)
test('same-prototype-distinct-closure-fallback',function()
 local c=makeCompat(true);assert(c.bc());local clone=CloneSamePrototype(c.bc);local before=NativeHits()
 assert(clone()and NativeHits()==before and c.bc()and NativeHits()==before+1)
end)
test('environment-global-and-meta',function()
 local c=makeCompat(true);assert(c.bc());local before=NativeHits();local realEnv=_G;local saved=realEnv._G
 realEnv._G={};assert(c.bc()and NativeHits()==before);realEnv._G=saved
 setmetatable(realEnv,{});assert(c.bc()and NativeHits()==before);setmetatable(realEnv,nil)
 assert(c.bc()and NativeHits()==before+1)
end)
test('debug-fallback',function()
 local c=makeCompat(true);assert(c.bc());local before=NativeHits();SetDebug(true);assert(c.bc()and NativeHits()==before);SetDebug(false);assert(c.bc()and NativeHits()==before+1)
end)
test('foreign-delegate-owner-fallback',function()
 local c=makeCompat(true);for k,v in pairs(c.proximity)do ForeignDelegate[k]=v end
 local fresh=OwnedCompat(c.helper,c.helper.isStaleVehicleContainer,ForeignDelegate,c.methods,c.owner,c.functions,{},c.owner.MODULE,c.owner.AUTO_KEY,nil)
 local before=NativeHits();assert(fresh()and NativeHits()==before)
end)
test('cold-false-snapshot-fallback',function()
 local c=makeCarts(true);c.coreMethods.isCart=false;c.core.isCart=false;local before=NativeHits()
 assert(c.guard()and NativeHits()==before)
end)
test('identical-boxed-nan-falls-back',function()
 local c=makeCarts(true);local nan=0/0;c.class.nan=nan;c.methods.nan=nan;local before=NativeHits()
 local ok,reason=c.guard();assert(ok==false and reason=='cart_method_changed:nan'and NativeHits()==before)
end)
test('foreign-iterator-yield-stays-in-lua',function()
 local c=makeCompat(true);assert(c.bc());local before=NativeHits()
 pairs=function(t)coroutine.yield('iterator-pause');return originalPairs(t)end
 local co=coroutine.create(function()return c.bc()end)
 local ok,value=coroutine.resume(co);assert(ok and value=='iterator-pause')
 ok,value=coroutine.resume(co);assert(ok and value==true and coroutine.status(co)=='dead'and NativeHits()==before)
 pairs=originalPairs
end)
assert(forged==0)
Emit('QUEUE_BINDING_TRUST_PASS cases='..checks..' forgedCalls=0 actualCallerClosure=true actualCallerEnvironment=true')
QueueBindingCompilerTrustPassed=true
