"""Exercise the isolated genuine-packet hand fault; this is not a live Host PASS."""
from pathlib import Path
import copy
import unittest

from tests.test_queue_razor_restoration import selection
from tools.queue_checks.adapters import razor_restoration as adapter

ROOT = Path(__file__).resolve().parents[1]


class RazorHandAuthorityTests(unittest.TestCase):
    def test_selection_is_explicit_isolated_host_only(self):
        valid = selection(); valid.update(cases=['restore-success'])
        valid['options']['razor_hand_ack_delay_ms'] = 1000
        adapter.validate(valid)
        for change in ({'kind': 'sp'}, {'cases': ['empty-primary']}, {'cases': ['restore-success', 'cancel-active']},
                       {'options': {'mp_host': True, 'razor_hand_ack_delay_ms': True}},
                       {'options': {'mp_host': True, 'razor_hand_ack_delay_ms': 999}},
                       {'options': {'mp_host': True, 'razor_hand_ack_delay_ms': 1000, 'queue_editor_enabled': False}}):
            invalid = copy.deepcopy(valid); invalid.update(change)
            with self.assertRaises(ValueError): adapter.validate(invalid)

    def runtime(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime()
        lua.execute('''
          package.preload['PZSurvivorToolkit/Settings']=function()return {}end
          package.preload['TimedActions/ISTimedActionQueue']=function()return {}end
          package.preload['PZSurvivorToolkit/ActionQueueOperations']=function()return {}end
          handlers={};Events={OnServerCommand={Add=function(fn)handlers[#handlers+1]=fn end}}
          now=0;nativePresent=true;debts={};logs={};dispatched={};stops=0;keeps=0
          getTimestampMs=function()return now end;isClient=function()return true end
          player={getPlayerNum=function()return 0 end,getOnlineID=function()return 7 end,isDead=function()return false end,
            getCharacterActions=function()return {contains=function(_,a)return nativePresent and a==native end}end}
          getSpecificPlayer=function(i)return i==0 and player end
          native={};action={Type='ISEquipWeaponAction',character=player,action=native,toolkitNativeTransaction=3,toolkitNativeKind='ISEquipWeaponAction'}
          queue={character=player,current=action,queue={action},toolkitOperationGeneration=0}
          ISTimedActionQueue={queues={[player]=queue}}
          L={};PZSurvivorToolkit={ActionQueueLifecycle=L,Settings={actionQueue=function()return true end},
            ActionQueueSettlement={waitingForHandAuthority=function(q,a)return record and record.state=='started' end},
            ActionQueueExecution={blockedReturns=function()return debts end}}
          tail={};tailRow={started=false,progress=false};row={actionRef='owned-restore',progress=true}
          state={player=player,ids={items={razor={id=13},tail={initial=8}}}};evidence={}
          action.forceStop=function()stops=stops+1 end
          panel={getIsVisible=function()return true end,returnEntries={{id=9}},returnIndex=1,
            keepReturnButton={getIsVisible=function()return true end,onMouseDown=function(self)self.returnId=9 end},
            keepFailedReturn=function()keeps=keeps+1;debts={}end,removeFromUIManager=function()end}
          context={current=function()return action,row,tail,tailRow,state end,queue=function()return queue end,
            snapshot=function()return {tail={characterPages=8}}end,panel=function()return panel end,
            evidence=function()return evidence end,emit=function(marker,value)logs[#logs+1]=value end}
        ''')
        lua.execute((ROOT/'PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueAcknowledgements.lua').read_text())
        lua.globals().D = lua.execute((ROOT/'tests/native_queue/razor-restoration/client/QueueRazorHandAuthority.lua').read_text())
        lua.execute('''
          fault=D.install({kind='mp',cases={'restore-success'},options={razor_hand_ack_delay_ms=1000}},context)
          function packet(terminal)return {protocol=1,player=7,transaction=3,kind='ISEquipWeaponAction',
            token='11111111-1111-1111-1111-111111111111',state=terminal}end
          function triggerEvent(event,module,command,args)
            assert(event=='OnServerCommand'and not L.delayNativeReceipt(module,command,args),'replay retained again')
            dispatched[#dispatched+1]=args
            for _,fn in ipairs(handlers)do fn(module,command,args)end
          end
          function start()
            triggerEvent('OnServerCommand','PZSurvivorToolkitActions','State',packet('started'))
            record=assert(PZSurvivorToolkit.ActionQueueAcknowledgements.capture(action));row.receipt=record
            dispatched={};fault.poll();assert(stops==1)
          end
          function hold()
            terminal=packet('canceled');assert(L.delayNativeReceipt('PZSurvivorToolkitActions','State',terminal))
            nativePresent=false;debts={{id=9,itemId=13,state='blocked'}};fault.poll()
          end
        ''')
        return lua

    def test_keep_holds_tail_until_same_late_packet_then_duplicate(self):
        lua = self.runtime()
        lua.execute('''
          start();hold();assert(keeps==1 and stops==1 and #logs==2 and record.state=='started')
          assert(logs[1].phase=='pending'and logs[2].phase=='kept'and #logs[2].debts==0)
          now=999;fault.poll();assert(#dispatched==0)
          now=1000;fault.poll();assert(#dispatched==1 and dispatched[1]==terminal and record.state=='canceled')
          queue.current={};queue.queue={queue.current};now=1001;fault.poll()
          assert(#dispatched==2 and dispatched[2]==terminal and record.state=='canceled')
          fault.complete();fault.complete();assert(#logs==6 and stops==1 and keeps==1)
          for _,value in ipairs(logs)do assert(value.packetRef==tostring(terminal)and value.nativeRef==tostring(native))end
        ''')

    def test_unrelated_receipts_and_unstarted_replacement_never_intercepted(self):
        lua = self.runtime()
        lua.execute('''
          assert(not L.delayNativeReceipt('PZSurvivorToolkitActions','State',packet('canceled')))
          start()
          for _,change in ipairs({{protocol=2},{player=8},{transaction=4},{kind='ISReadABook'},{state='completed'},
            {token='22222222-2222-2222-2222-222222222222'}})do
            local other=packet('canceled');for key,value in pairs(change)do other[key]=value end
            assert(not L.delayNativeReceipt('PZSurvivorToolkitActions','State',other),'foreign packet held')
          end
          assert(not L.delayNativeReceipt('Other','State',packet('canceled')))
          assert(not L.delayNativeReceipt('PZSurvivorToolkitActions','Other',packet('canceled')))
          action.action={};assert(not L.delayNativeReceipt('PZSurvivorToolkitActions','State',packet('canceled')))
        ''')
