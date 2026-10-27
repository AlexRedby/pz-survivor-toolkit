"""Exercise the genuine-packet diagnostic fault against the production ACK receiver."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PendingOutcomeFaultTests(unittest.TestCase):
    def runtime(self, case='placement-cancel-restore', mode='toolkit'):
        try:
            from lupa.lua51 import LuaRuntime
        except ImportError:
            self.skipTest('Lupa is required for source-backed receipt fault checks')
        lua = LuaRuntime()
        lua.globals().caseID = case
        lua.globals().mode = mode
        lua.execute("""
            now=0;nativePresent=true;logs={};dispatched={};ticks={};handlers={}
            getTimestampMs=function()return now end
            Events={OnServerCommand={Add=function(fn)handlers[#handlers+1]=fn end},
              OnTick={Add=function(fn)ticks[#ticks+1]=fn end}}
            package.preload['PZSurvivorToolkit/Settings']=function()return {}end
            package.preload['TimedActions/ISTimedActionQueue']=function()return {}end
            package.preload['QueueHealthEvents']=function()return {encode=function(row)return tostring(row)end}end
            root={};player={getInventory=function()return root end,getOnlineID=function()return 7 end,
              getPlayerNum=function()return 0 end,isDead=function()return false end,
              getCharacterActions=function()return {contains=function(_,n)return nativePresent and n==nativeAction end}end}
            getSpecificPlayer=function(slot)if slot==0 then return player end end;isClient=function()return true end
            nativeAction={};kind=caseID=='active-cancel-restore'and 'ISFitnessAction'or 'ISDropWorldItemAction'
            terminal=caseID=='active-cancel-restore'and 'canceled'or 'completed'
            action={Type=kind,character=player,action=nativeAction,toolkitNativeTransaction=3,toolkitNativeKind=kind}
            queue={character=player,current=action,queue={action},toolkitOperationGeneration=0}
            ISTimedActionQueue={queues={[player]=queue},resetQueue=function()end,cancelQueue=function()end}
            enabled=mode=='toolkit'
            L={allowNativeCompletion=function()return false end,registerObserver=function()return true end}
            PZSurvivorToolkit={ActionQueueLifecycle=L,Settings={actionQueue=function()return enabled end}}
            context={case=function()return caseID end,player=function()return player end,active=function()return true end,
              emit=function(marker,row)if marker=='RECEIPT_FAULT'then logs[#logs+1]=row end end}
        """)
        lua.execute((ROOT / 'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueAcknowledgements.lua').read_text())
        lua.globals().D = lua.execute((ROOT / 'tests/native_queue/fitness/client/QueueFitnessDiagnostics.lua').read_text())
        lua.execute("""
            options={fitness_diagnostics=true,fitness_receipt_delay_ms=1000,fitness_receipt_duplicate=true,
              fitness_editor_toggles={[caseID]='off-pending-outcome'}}
            diagnostics=D.install({kind='mp',mode=mode,options=options},context)
            function triggerEvent(event,module,command,args)
              assert(event=='OnServerCommand'and not L.delayNativeReceipt(module,command,args),'replay recaptured genuine packet')
              dispatched[#dispatched+1]=args
              for _,fn in ipairs(handlers)do fn(module,command,args)end
            end
            function packet(state)
              return {protocol=1,player=7,transaction=3,kind=kind,token='11111111-1111-1111-1111-111111111111',state=state}
            end
            function start()
              triggerEvent('OnServerCommand','PZSurvivorToolkitActions','State',packet('started'))
              record=assert(PZSurvivorToolkit.ActionQueueAcknowledgements.capture(action));dispatched={}
            end
            function hold()
              args=packet(terminal)
              assert(L.delayNativeReceipt('PZSurvivorToolkitActions','State',args),'real terminal not retained')
            end
            function observePending()
              local a,r,n=diagnostics.pendingFault()
              assert(a==action and r==record and n==nativeAction,'pending diagnostic replaced original identities')
              enabled=false
              diagnostics.markPending({mode=mode,editorEnabled=false,sealedStarted=mode=='toolkit',tailRetained=true,tailUnread=true})
            end
        """)
        return lua

    def test_real_packet_and_sealed_ack_release_then_duplicate_once(self):
        for case in ('active-cancel-restore', 'placement-cancel-restore'):
            with self.subTest(case=case):
                lua=self.runtime(case)
                lua.execute("""
                    start();hold();nativePresent=caseID=='placement-cancel-restore'
                    now=100;observePending();assert(record.state=='started'and #logs==2)
                    now=999;ticks[1]();assert(#dispatched==0 and record.state=='started')
                    now=1000;ticks[1]();assert(#dispatched==1 and dispatched[1]==args and record.state==terminal)
                    nativePresent=false;queue.current={};queue.queue={queue.current}
                    now=1001;ticks[1]();assert(#dispatched==2 and dispatched[2]==args and record.state==terminal)
                    now=2000;ticks[1]();assert(#dispatched==2 and #diagnostics.faultComplete()==4)
                    local phases={'retained','pending','released','duplicate'}
                    for i,row in ipairs(logs)do
                      assert(row.sequence==i and row.phase==phases[i] and row.packetRef==tostring(args))
                      assert(row.fingerprint==logs[1].fingerprint and row.nativeRef==tostring(nativeAction))
                    end
                    assert(logs[3].ackBefore=='started'and logs[3].ackAfter==terminal)
                    assert(logs[4].ackBefore==terminal and logs[4].ackAfter==terminal and not logs[4].currentMatches)
                    assert(not PZSurvivorToolkit.ActionQueueAcknowledgements.capture(action),'duplicate restored retired action capability')
                    assert(args.protocol==1 and args.player==7 and args.transaction==3 and args.kind==kind
                      and args.token=='11111111-1111-1111-1111-111111111111'and args.state==terminal)
                """)

    def test_retained_timestamp_and_deadline_share_one_clock_sample(self):
        lua=self.runtime()
        lua.execute("""
            start();now=100
            getTimestampMs=function()local value=now;now=now+1;return value end
            hold()
            assert(logs[1].at==100 and logs[1].deadline==1100,
              'retained timestamp/deadline sampled different clock instants')
        """)

    def test_native_terminal_is_correlated_after_real_reset_and_current_advances(self):
        lua=self.runtime('active-cancel-restore','native')
        lua.execute("""
            start();PZSurvivorToolkit.ActionQueueAcknowledgements.reset(queue)
            queue.current={};queue.queue={};nativePresent=false
            hold();now=1;observePending();now=1000;ticks[1]();now=1001;ticks[1]()
            assert(#diagnostics.faultComplete()==4 and not logs[1].currentMatches)
            for _,row in ipairs(logs)do assert(row.ackBefore==false and row.ackAfter==false)end
            assert(#dispatched==2 and dispatched[1]==args and dispatched[2]==args and record.state=='started')
        """)

    def test_unrelated_foreign_and_replaced_native_packets_are_never_held(self):
        lua=self.runtime()
        lua.execute("""
            local early=packet(terminal)
            assert(not L.delayNativeReceipt('PZSurvivorToolkitActions','State',early),'terminal without genuine Started was held')
            start()
            for _,change in ipairs({{protocol=2},{player=99},{transaction=4},{kind='ISReadABook'},
              {token='22222222-2222-2222-2222-222222222222'},{state='canceled'}})do
              local other=packet(terminal);for key,value in pairs(change)do other[key]=value end
              assert(not L.delayNativeReceipt('PZSurvivorToolkitActions','State',other),'foreign terminal held')
            end
            assert(not L.delayNativeReceipt('Other','State',packet(terminal)))
            assert(not L.delayNativeReceipt('PZSurvivorToolkitActions','Other',packet(terminal)))
            action.action={};assert(not L.delayNativeReceipt('PZSurvivorToolkitActions','State',packet(terminal)),
              'replacement native episode accepted old terminal')
            assert(not pcall(diagnostics.faultComplete),'missing interception passed')
        """)

    def test_missed_pending_window_and_mutated_packet_fail_closed(self):
        lua=self.runtime()
        lua.execute("""
            start();hold();now=1000
            assert(not pcall(ticks[1])and #dispatched==0,'unobserved held window released silently')
            assert(not pcall(diagnostics.pendingFault),'expired pending observation accepted')
            assert(not pcall(diagnostics.faultComplete),'unfinished fault passed')
        """)
        lua=self.runtime()
        lua.execute("""
            start();hold();now=1;nativePresent=false;observePending()
            args.token='22222222-2222-2222-2222-222222222222';now=1000
            assert(not pcall(ticks[1])and #dispatched==0,'mutated terminal dispatched')
        """)

    def test_actual_fixture_observes_active_native_removal_and_seal_before_disabling(self):
        lua=self.runtime('active-cancel-restore')
        source=(ROOT/'tests/native_queue/fitness/client/ZZFitnessQueue.lua').read_text()
        begin=source.index('local function observePendingOutcome()')
        body=source[begin:source.index('local function editorCleanup(',begin)]
        lua.execute("""
            start();hold();state={player=player,items={tail={getFullType=function()return 'Book'end,getNumberOfPages=function()return 200 end}}}
            tail={};pages=0;tailPresent=true;editorWrites=0;rawRows={};command={editorCancelBoundary={}}
            player.getAlreadyReadPages=function()return pages end
            queue.indexOf=function(_,a)return a==tail and tailPresent and 2 or -1 end
            config={mode=mode};native=false;T=PZSurvivorToolkit;case=function()return caseID end
            editorToggle=function()return 'off-pending-outcome'end
            queueValue=queue;queue=function()return queueValue end
            editorBoundary=function(a,b)return {boundary=b,nativeRef=tostring(a.action)}end
            raw=function(marker,row)rawRows[#rawRows+1]={marker,row}end
            setEditor=function(value,boundary)editorWrites=editorWrites+1;enabled=value end
        """)
        lua.execute(body.replace('local function observePendingOutcome()', 'function observePendingOutcome()',1))
        lua.execute("""
            observePendingOutcome();assert(editorWrites==0 and #logs==1,'disabled before native removal')
            nativePresent=false;pages=200
            assert(not pcall(observePendingOutcome)and editorWrites==0,'finished tail accepted pending boundary')
            pages=0;tailPresent=false
            assert(not pcall(observePendingOutcome)and editorWrites==0,'lost tail accepted pending boundary')
            tailPresent=true;local old=queueValue.current;queueValue.current={}
            assert(not pcall(observePendingOutcome)and editorWrites==0,'foreign head accepted pending boundary')
            queueValue.current=old
            observePendingOutcome();assert(editorWrites==1 and not enabled and #logs==2)
            assert(logs[2].sealedStarted and logs[2].nativeAbsent and logs[2].tailRetained and logs[2].tailUnread)
            assert(command.editorPendingBoundary.boundary=='pending-outcome'and rawRows[1][1]=='EDITOR_PENDING')
        """)

    def test_actual_fixture_requires_paid_placement_native_episode_still_held(self):
        lua=self.runtime()
        source=(ROOT/'tests/native_queue/fitness/client/ZZFitnessQueue.lua').read_text()
        begin=source.index('local function observePendingOutcome()')
        body=source[begin:source.index('local function editorCleanup(',begin)]
        lua.execute("""
            start();hold();state={player=player,items={tail={getFullType=function()return 'Book'end,getNumberOfPages=function()return 200 end}}}
            tail={};editorWrites=0;command={editorCancelBoundary={}}
            player.getAlreadyReadPages=function()return 0 end
            queue.indexOf=function(_,a)return a==tail and 2 or -1 end
            config={mode=mode};native=false;T=PZSurvivorToolkit;case=function()return caseID end
            editorToggle=function()return 'off-pending-outcome'end
            queueValue=queue;queue=function()return queueValue end
            editorBoundary=function(a,b)return {boundary=b,nativeRef=tostring(a.action)}end
            raw=function()end
            setEditor=function(value)editorWrites=editorWrites+1;enabled=value end
        """)
        lua.execute(body.replace('local function observePendingOutcome()', 'function observePendingOutcome()',1))
        lua.execute("""
            nativePresent=false
            local ok,problem=pcall(observePendingOutcome)
            assert(not ok and tostring(problem):find('lost its held native episode',1,true)and editorWrites==0,
              'completed placement without its held native episode accepted')
            nativePresent=true;observePendingOutcome()
            assert(editorWrites==1 and not enabled and #logs==2 and not logs[2].nativeAbsent and logs[2].sealedStarted,
              'actual Java-held paid placement could not disable while genuine ACK remained Started')
        """)


if __name__ == '__main__':
    unittest.main()
