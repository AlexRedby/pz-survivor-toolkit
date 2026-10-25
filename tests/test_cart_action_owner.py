"""Exercise the probe with the real sealed acknowledgement API, without a game."""
import json
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[1]
LUA=shutil.which('luajit')


@unittest.skipUnless(LUA,'LuaJIT required')
class ActionOwnerProbeTests(unittest.TestCase):
    def run_lua(self,body,observer=False):
        script=r'''
local root=ROOT
local callbacks={}
Events={OnServerCommand={Add=function(fn) callbacks[#callbacks+1]=fn end}}
local now,logs,commands=100,{},{}
print=function(s) logs[#logs+1]=s end
getTimestampMs=function() now=now+1;return now end
PZSurvivorToolkit={};ISTimedActionQueue={queues={}}
local player={getPlayerNum=function() return 0 end,getOnlineID=function() return 7 end,isDead=function() return false end}
getPlayer=function() return player end;getSpecificPlayer=function(slot) if slot==0 then return player end end
isServer=function() return false end;isClient=function() return true end
getFileReader=function() return {readLine=function() return 'client1' end,close=function() end} end
local connection,foreign={},{};local ingress=connection
cartLeaseCurrent=function() return connection end;cartLeaseIngress=function() return ingress end
cartLeaseSeed=function() return '00000000-0000-0000-0000-000000000001' end
cartLeaseChallengeSeed=function() return '00000000-0000-0000-0000-000000000004' end
require=function() end
local Ack=dofile(root..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueAcknowledgements.lua')
local J=dofile(root..'/tests/native_queue/contributions/wooden_cart_multiplayer/json.lua')
local config={disposable=true,options={cart_action_admission=true,cart_observer_association=OBSERVER}}
require=function(name)
 if name=='QueueTestSelection' then return config end
 if name=='CartMPJSON' then return J end
 if name=='PZSurvivorToolkit/ActionQueueAcknowledgements' then return Ack end
 error(name)
end
sendClientCommand=function(p,module,command,args)
 assert(p==player and module=='CartActionAdmissionProbe' and command=='Query')
 commands[#commands+1]=args
end
local probe=dofile(root..'/tests/native_queue/contributions/wooden_cart_multiplayer/action-admission.lua')
local action={character=player,action={},Type='ToolkitWoodCartPickup',itemId=42,toolkitNativeTransaction=11,toolkitNativeKind='ToolkitWoodCartPickup'}
local queue={current=action,queue={action},toolkitOperationGeneration=1};ISTimedActionQueue.queues[player]=queue
local token='00000000-0000-0000-0000-000000000002'
local function event(module,command,args) for _,fn in ipairs(callbacks) do fn(module,command,args) end end
local function start()
 probe.track(action,{index=1,phase='pickup-complete',id=42})
 event('PZSurvivorToolkitActions','State',{protocol=1,player=7,transaction=11,kind='ToolkitWoodCartPickup',token=token,state='started'})
 probe.sample();assert(#commands==1)
end
local function reply()
 return {nonce=commands[1].nonce,index=1,phase='pickup-complete',owner=7,cart=42,token=token,
  transaction=11,kind='ToolkitWoodCartPickup',tokenObserved=true,sourceValidated=true,admittedBindingValid=true,
  stage='accepted',startGeneration=3,process='00000000-0000-0000-0000-000000000003'}
end
local function has(needle) for _,line in ipairs(logs) do if line:find(needle,1,true) then return true end end end
BODY
'''.replace('ROOT',json.dumps(str(ROOT))).replace('BODY',body).replace('OBSERVER','true' if observer else 'false')
        result=subprocess.run([LUA,'-'],input=script,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr)

    def test_no_query_without_sealed_receipt_and_exact_token_response_works(self):
        self.run_lua('''
probe.track(action,{index=1,phase='pickup-complete',id=42});probe.sample();assert(#commands==0)
event('PZSurvivorToolkitActions','State',{protocol=1,player=7,transaction=11,kind='ToolkitWoodCartPickup',token=token,state='started'})
probe.sample();assert(#commands==1)
event('CartActionAdmissionProbe','Reply',reply())
event('PZSurvivorToolkitActions','State',{protocol=1,player=7,transaction=11,kind='ToolkitWoodCartPickup',token=token,state='completed'})
probe.sample();assert(has('"event":"reply"') and has('"event":"terminal"'))
assert(not has('[CART_ADMISSION] ERROR'));assert(#commands==1)
''')

    def test_observer_source_is_frozen_at_exact_sealed_capture_and_echoed(self):
        self.run_lua('''
local source='1|00000000-0000-0000-0000-000000000001|1|2|3|4|5'
cartObserverSource=function(native) assert(native==action.action);return source end
start();assert(commands[1].observerSource==source)
local r=reply();r.observerSource=source;event('CartActionAdmissionProbe','Reply',r)
assert(has('"observerSource":"'..source..'"') and has('"event":"reply"'))
assert(not has('[CART_ADMISSION] ERROR'))
''',observer=True)

    def test_observer_source_missing_or_changed_is_refused(self):
        for missing in (True,False):
            self.run_lua('''
local source='1|00000000-0000-0000-0000-000000000001|1|2|3|4|5'
cartObserverSource=function(native) assert(native==action.action);return SOURCE end
'''.replace('SOURCE','nil' if missing else 'source')+('''
assert(not pcall(start));assert(#commands==0)
''' if missing else '''
start();local r=reply();r.observerSource=source..'9';event('CartActionAdmissionProbe','Reply',r)
assert(has('[CART_ADMISSION] ERROR') and not has('"event":"reply"'))
'''),observer=True)

    def test_native_counter_logs_preserve_exact_safe_integer_digits(self):
        self.run_lua('''
start();local r=reply();r.monoNs=253716934852789;r.startGeneration=9007199254740991
event('CartActionAdmissionProbe','Reply',r)
assert(has('"monoNs":253716934852789') and has('"startGeneration":9007199254740991'))
assert(not has('[CART_ADMISSION] ERROR'))
''')

    def test_native_cancel_receipt_does_not_restore_revoked_seal(self):
        self.run_lua('''
start();event('CartActionAdmissionProbe','Reply',reply())
local sealed=assert(Ack.capture(action));Ack.reset(queue);queue.toolkitOperationGeneration=2
assert(Ack.observe(action,sealed)==nil)
event('PZSurvivorToolkitActions','State',{protocol=1,player=7,transaction=11,kind='ToolkitWoodCartPickup',token=token,state='canceled'})
probe.sample()
assert(has('"event":"native-terminal-receipt"') and has('"state":"canceled"'))
assert(has('"event":"seal-revoked"') and has('"reason":"operation-generation-changed"'))
assert(has('"captureGeneration":1') and has('"observedGeneration":2'))
assert(not has('"event":"terminal"') and not has('[CART_ADMISSION] ERROR'))
assert(Ack.observe(action,sealed)==nil)
''')

    def test_hotkey_drop_reset_and_late_receipts_cannot_claim_repeated_drop(self):
        for outcome,before_reset in (('canceled',False),('completed',False),('completed',True)):
            with self.subTest(outcome=outcome,before_reset=before_reset):
                self.run_lua('''
config.options.cart_hotkey_setdown=true
local nativeOutcome=OUTCOME;local terminalBeforeReset=BEFORE_RESET
local item={getID=function() return 42 end}
local operation={};action.Type='ToolkitWoodCartDrop';action.item=item
action.toolkitNativeKind='ToolkitWoodCartDrop';action.toolkitQueueOperation=operation
local function state(selectedToken,outcome)
 event('PZSurvivorToolkitActions','State',{protocol=1,player=7,transaction=11,
  kind='ToolkitWoodCartDrop',token=selectedToken,state=outcome})
end
-- Isolate reset and repeat: both retain the same byte transaction/cart,
-- while the native/Lua action, operation, generation and token must be fresh.
probe.trackQueued(queue.queue,{index=1,phase=OLD_PHASE,id=42})
state(token,'started');probe.sample();assert(#commands==1)
local oldReceipt=assert(Ack.capture(action));local r=reply()
r.phase=OLD_PHASE;r.kind='ToolkitWoodCartDrop'
event('CartActionAdmissionProbe','Reply',r)
if terminalBeforeReset then state(token,nativeOutcome) end
Ack.reset(queue);queue.toolkitOperationGeneration=2
local repeatedOperation={}
local repeated={character=player,action={},Type='ToolkitWoodCartDrop',item=item,
 toolkitNativeTransaction=11,toolkitNativeKind='ToolkitWoodCartDrop',toolkitQueueOperation=repeatedOperation}
local repeatedToken='00000000-0000-0000-0000-000000000005'
queue.current=repeated;queue.queue={repeated}
probe.trackQueued(queue.queue,{index=2,phase='drop-repeat',id=42})
state(token,'started');probe.sample()
assert(Ack.capture(action)==nil and Ack.observe(action,oldReceipt)==nil)
assert(Ack.capture(repeated)==nil and #commands==1,'Old start acquired repeated action rights')
state(repeatedToken,'started');probe.sample();assert(#commands==2)
local repeatedReceipt=assert(Ack.capture(repeated))
local repeatedReply=reply()
repeatedReply.nonce=commands[2].nonce;repeatedReply.index=2;repeatedReply.phase='drop-repeat'
repeatedReply.kind='ToolkitWoodCartDrop';repeatedReply.token=repeatedToken;repeatedReply.startGeneration=4
event('CartActionAdmissionProbe','Reply',repeatedReply)
-- A terminal delivered before reset or after the repeated action's own receipt
-- remains historical; neither schedule can settle or recapture the new action.
if not terminalBeforeReset then state(token,nativeOutcome) end
state(token,'started');probe.sample()
assert(Ack.capture(action)==nil and Ack.observe(action,oldReceipt)==nil)
assert(Ack.capture(repeated)==repeatedReceipt and Ack.observe(repeated,repeatedReceipt)=='started')
assert(repeatedReceipt.token==repeatedToken and repeatedReceipt.native==repeated.action
 and repeatedReceipt.generation==2 and repeatedReceipt.state=='started')
assert(queue.current==repeated and #queue.queue==1 and queue.queue[1]==repeated
 and queue.toolkitOperationGeneration==2 and repeated.toolkitQueueOperation==repeatedOperation
 and action.toolkitQueueOperation==operation)
assert(#commands==2 and commands[1].token==token and commands[2].token==repeatedToken)
assert(has('"event":"seal-revoked"') and has('"reason":"operation-generation-changed"'))
assert(has('"event":"native-terminal-receipt"') and has('"state":"'..nativeOutcome..'"'))
assert(not has('"event":"terminal"'),'Reset action regained sealed terminal authority')
state(repeatedToken,'completed');probe.sample()
assert(Ack.observe(repeated,repeatedReceipt)=='completed' and #commands==2)
assert(not has('[CART_ADMISSION] ERROR'))
'''.replace('OUTCOME',json.dumps(outcome)).replace('BEFORE_RESET','true' if before_reset else 'false')
                   .replace('OLD_PHASE',json.dumps('drop-cancel' if outcome=='canceled' else 'drop-complete')))

    def test_completed_hotkey_drop_without_reset_retains_sealed_outcome(self):
        self.run_lua('''
config.options.cart_hotkey_setdown=true
action.Type='ToolkitWoodCartDrop';action.item={getID=function() return 42 end}
action.toolkitNativeKind='ToolkitWoodCartDrop'
probe.trackQueued(queue.queue,{index=1,phase='drop-complete',id=42})
local function state(outcome)
 event('PZSurvivorToolkitActions','State',{protocol=1,player=7,transaction=11,
  kind='ToolkitWoodCartDrop',token=token,state=outcome})
end
state('started');probe.sample();local sealed=assert(Ack.capture(action))
local r=reply();r.phase='drop-complete';r.kind='ToolkitWoodCartDrop'
event('CartActionAdmissionProbe','Reply',r)
state('completed');probe.sample()
assert(Ack.observe(action,sealed)=='completed' and #commands==1)
assert(has('"event":"terminal"') and has('"event":"native-terminal-receipt"'))
assert(not has('"event":"seal-revoked"') and not has('[CART_ADMISSION] ERROR'))
''')

    def test_original_terminal_delivery_requires_exact_ingress_and_frozen_transaction(self):
        for mutation in ('ingress=foreign','r.transaction=12'):
            with self.subTest(mutation=mutation):
                self.run_lua("start();local r={protocol=1,player=7,transaction=11,kind='ToolkitWoodCartPickup',token=token,state='completed'};"+mutation+";event('PZSurvivorToolkitActions','State',r);assert(has('[CART_ADMISSION] ERROR'));assert(not has('\"event\":\"native-terminal-receipt\"'))")

    def test_pickup_tracks_exact_queued_cart_after_approach(self):
        self.run_lua('''
local walk={character=player,Type='ISWalkToTimedAction'}
probe.trackQueued({walk,action},{index=1,phase='pickup-complete',id=42})
queue.current=walk;probe.sample();assert(#commands==0)
queue.current=action
event('PZSurvivorToolkitActions','State',{protocol=1,player=7,transaction=11,kind='ToolkitWoodCartPickup',token=token,state='started'})
probe.sample();assert(#commands==1 and has('"event":"capture"'))
''')

    def test_native_deferred_pickup_follows_exact_approach_operation(self):
        self.run_lua('''
local operation={};local walk={character=player,Type='ISWalkToTimedActionF',
 toolkitWoodCartItem={getID=function() return 42 end},toolkitQueueOperation=operation}
queue.current=walk;queue.queue={walk}
probe.trackQueued(queue.queue,{index=1,phase='pickup-complete',id=42});probe.sample()
assert(not has('"event":"track"') and #commands==0)
action.toolkitQueueOperation=operation;queue.queue={action};queue.current=action
-- Native State may arrive before the next OnTick samples the newly inserted action.
event('PZSurvivorToolkitActions','State',{protocol=1,player=7,transaction=11,kind='ToolkitWoodCartPickup',token=token,state='started'})
probe.sample();assert(#commands==1 and has('"event":"capture"'))
''')

    def test_deferred_pickup_rejects_foreign_operation_or_queue_reset(self):
        for mutation in ('action.toolkitQueueOperation={}','queue.toolkitOperationGeneration=2'):
            with self.subTest(mutation=mutation):
                self.run_lua('''
local operation={};local walk={character=player,Type='ISWalkToTimedActionF',
 toolkitWoodCartItem={getID=function() return 42 end},toolkitQueueOperation=operation}
queue.current=walk;queue.queue={walk}
probe.trackQueued(queue.queue,{index=1,phase='pickup-complete',id=42})
action.toolkitQueueOperation=operation;queue.queue={action};queue.current=action
'''+mutation+''';assert(not pcall(probe.sample));assert(#commands==0 and not has('"event":"track"'))''')

    def test_missing_or_ambiguous_queued_cart_is_refused(self):
        self.run_lua('''
local spec={index=1,phase='pickup-complete',id=42}
assert(not pcall(probe.trackQueued,{{Type='ISWalkToTimedAction'}},spec))
assert(not pcall(probe.trackQueued,{action,action},spec))
assert(#commands==0 and not has('"event":"track"'))
''')

    def test_role_alias_reload_registers_callbacks_once(self):
        self.run_lua('''
local again=dofile(root..'/tests/native_queue/contributions/wooden_cart_multiplayer/action-admission.lua')
assert(again==probe and #callbacks==2)
start();event('CartActionAdmissionProbe','Reply',reply())
assert(not has('[CART_ADMISSION] ERROR'))
''')

    def test_changed_ingress_or_native_action_is_rejected(self):
        for mutation in ('ingress=foreign','action.action={}'):
            with self.subTest(mutation=mutation):
                self.run_lua("start();"+mutation+";event('CartActionAdmissionProbe','Reply',reply());assert(has('[CART_ADMISSION] ERROR'));assert(not has('\"event\":\"reply\"'))")

    def test_wrong_nonce_or_transaction_token_is_rejected(self):
        for mutation in ("r.nonce='old:1'","r.token='00000000-0000-0000-0000-000000000099'"):
            with self.subTest(mutation=mutation):
                self.run_lua("start();local r=reply();"+mutation+";event('CartActionAdmissionProbe','Reply',r);assert(has('[CART_ADMISSION] ERROR'));assert(not has('\"event\":\"reply\"'))")


if __name__=='__main__':unittest.main()
