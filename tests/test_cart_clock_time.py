import copy
from pathlib import Path
import runpy
import shutil
import subprocess
import unittest

API=runpy.run_path(str(Path(__file__).resolve().parent/'native_queue/contributions/wooden_cart_multiplayer/clock_time.py'))


class ClockFixtureLuaTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT required for actual timing call')
    def test_observer_uses_exact_remote_hand_id_without_owner_setup_id(self):
        source=(Path(__file__).resolve().parent/'native_queue/contributions/wooden_cart_multiplayer/client.lua').read_text()
        begin=source.index('  if config.options and config.options.cart_time_alignment==true')
        end=source.index('  if wallSide and not wallPositioned',begin)
        block=source[begin:end]
        script="""
local config={options={cart_time_alignment=true}}
local elapsed,duration=2000,26000
local setup={x=1,y=2} -- Observer setup intentionally has no cartId.
local cart={getID=function() return 2040301443 end}
local owner={getPrimaryHandItem=function() return cart end}
local called=0
cartMPTimingSample=function(actualOwner,id,time)
 assert(actualOwner==owner and id==2040301443 and time==2000)
 called=called+1
end
"""+block+"\nassert(called==1)\n"
        subprocess.run([shutil.which('luajit'),'-'],input=script,text=True,check=True,capture_output=True)


class ClockRequestTests(unittest.TestCase):
    def setUp(self):
        self.rows={'client1':[],'client2':[]}
        self.process='10000000-0000-0000-0000-000000000001'
        self.plan=dict(event='clock-experiment-request',nativeProcessEpoch=self.process,connectionEpoch=1,
            monoNs=90_000_000,fixtureRequestOrdinal=1,fixtureRequestCap=14,fixtureRequestMonoNs=90_000_000,fixtureElapsedMs=0)
        self.request=dict(event='clock-request',nativeProcessEpoch=self.process,connectionEpoch=1,
            clientSendNs=100_000_000,observedMonoNs=101_000_000,monoNs=105_000_000,
            clockRequestOrdinal=1,fixtureRequestOrdinal=1,clockRequestOrigin='fixture',connectionGUID='99',connectionToken=12,clockRequestDropped=0)
        self.reply=dict(event='clock-sync',nativeProcessEpoch=self.process,clockRequestConnectionEpoch=1,
            clientSendNs=100_000_000,clientProcessNs=109_000_000,serverPreparedNs=605_000_000,
            clockRequestObserved=True,clockRequestOrdinal=1,clockRequestOrigin='fixture',clockRequestDropped=0,
            connectionGUID='99',connectionToken=12)
        self.rows['client1']=[self.plan,self.request,self.reply]

    def report(self,selected=True): return API['request_report'](self.rows,selected)

    def test_exact_echoed_request_association_and_sampled_offset_model(self):
        result=self.report();role=result['roles']['client1']
        self.assertEqual(role['replies'],{'matched-fixture':1})
        self.assertTrue(role['observedRequestAssociationComplete'])
        self.assertEqual(role['sampledEpochCompatibility'][0]['sampledConstantOffsetIntersectionNs'],[496_000_000,505_000_000])
        self.assertIn('not an upper drift bound',result['qualification'])
        self.assertFalse(result['roles']['client2']['observedRequestAssociationComplete'])

    def test_startup_only_request_matching_does_not_qualify_active_experiment(self):
        self.rows['client1']=[self.request,self.reply]
        self.request.update(clockRequestOrigin='native',fixtureRequestOrdinal=0)
        self.reply['clockRequestOrigin']='native'
        result=self.report();role=result['roles']['client1']
        self.assertTrue(role['observedRequestAssociationComplete'])
        self.assertFalse(role['experimentCoverageComplete'])
        self.assertFalse(result['experimentCoverageComplete'])
        self.assertIsNone(role['fixtureElapsedSpanMs'])

    def test_repeated_fixture_coverage_requires_both_clients_and_every_attempt(self):
        plan=copy.deepcopy(self.plan);plan.update(fixtureRequestOrdinal=2,fixtureRequestMonoNs=2_100_000_000,fixtureElapsedMs=2010)
        request=copy.deepcopy(self.request);request.update(clockRequestOrdinal=2,fixtureRequestOrdinal=2,
            clientSendNs=2_110_000_000,observedMonoNs=2_111_000_000,monoNs=2_115_000_000)
        reply=copy.deepcopy(self.reply);reply.update(clockRequestOrdinal=2,clientSendNs=2_110_000_000,
            clientProcessNs=2_119_000_000,serverPreparedNs=2_615_000_000)
        self.rows['client1'] += [plan,request,reply]
        result=self.report()
        self.assertTrue(result['roles']['client1']['experimentCoverageComplete'])
        self.assertEqual(result['roles']['client1']['fixtureElapsedSpanMs'],[0,2010])
        self.assertFalse(result['experimentCoverageComplete'])
        self.rows['client2']=copy.deepcopy(self.rows['client1'])
        self.assertTrue(self.report()['experimentCoverageComplete'])
        self.rows['client2'].remove(self.rows['client2'][-2])
        self.assertFalse(self.report()['experimentCoverageComplete'])
        self.rows['client2']=copy.deepcopy(self.rows['client1'])
        self.rows['client2'].pop()
        self.assertFalse(self.report()['experimentCoverageComplete'])

    def test_native_retry_before_original_reply_does_not_rebind_cached_clock(self):
        request=copy.deepcopy(self.request);request.update(clientSendNs=110_000_000,observedMonoNs=111_000_000,
            monoNs=112_000_000,clockRequestOrdinal=2,clockRequestOrigin='native')
        self.rows['client1'].insert(2,request)
        reply=copy.deepcopy(self.reply);reply.update(clientSendNs=110_000_000,clientProcessNs=119_000_000,
            serverPreparedNs=615_000_000,clockRequestOrdinal=2,clockRequestOrigin='native')
        self.rows['client1'].append(reply)
        role=self.report()['roles']['client1']
        self.assertEqual(role['requestOrigins'],{'fixture':1,'native':1})
        self.assertEqual(role['replies'],{'matched-fixture':1,'matched-native':1})

    def test_wrong_connection_or_echo_remains_missing_instead_of_nearest(self):
        for key,value in [('clockRequestConnectionEpoch',2),('clientSendNs',100_000_001)]:
            with self.subTest(key=key):
                saved=copy.deepcopy(self.reply);self.reply[key]=value
                role=self.report()['roles']['client1']
                self.assertEqual(role['replies'],{'request-record-missing':1})
                self.assertFalse(role['observedRequestAssociationComplete'])
                self.reply.clear();self.reply.update(saved)

    def test_claimed_identity_must_match_exact_request_metadata(self):
        for key,value in [('clockRequestOrdinal',2),('clockRequestOrigin','native'),('connectionGUID','100'),('connectionToken',13)]:
            with self.subTest(key=key):
                saved=copy.deepcopy(self.reply);self.reply[key]=value
                with self.assertRaisesRegex(ValueError,'binding changed'): self.report()
                self.reply.clear();self.reply.update(saved)

    def test_legacy_and_dropped_startup_are_explicit_not_complete(self):
        self.rows['client1'].append(dict(event='clock-sync'))
        self.request['clockRequestDropped']=1
        role=self.report()['roles']['client1']
        self.assertEqual(role['droppedRequests'],1)
        self.assertEqual(role['replies']['legacy-unassociated'],1)
        self.assertFalse(role['observedRequestAssociationComplete'])

    def test_duplicate_request_and_ordinal_are_rejected(self):
        self.rows['client1'].insert(2,copy.deepcopy(self.request))
        with self.assertRaisesRegex(ValueError,'Duplicate'): self.report()

    def test_experiment_is_independently_opted_in_and_cannot_create_more_than_cap(self):
        with self.assertRaisesRegex(ValueError,'Unselected'): self.report(False)
        self.plan['fixtureRequestOrdinal']=15
        with self.assertRaisesRegex(ValueError,'ordinal/cap'): self.report()

    def test_minimum_spacing_deadline_and_epoch_fence(self):
        original=copy.deepcopy(self.plan)
        for change in [dict(fixtureRequestMonoNs=100_000_000),dict(connectionEpoch=2),dict(fixtureRequestMonoNs=33_090_000_000)]:
            with self.subTest(change=change):
                second=copy.deepcopy(original);second.update(fixtureRequestOrdinal=2,fixtureElapsedMs=2000,fixtureRequestMonoNs=2_090_000_000);second.update(change)
                self.rows['client1']=[self.plan,self.request,self.reply,second]
                with self.assertRaises(ValueError):self.report()

    def test_incompatible_sampled_exchanges_do_not_invent_drift_upper_bound(self):
        request=copy.deepcopy(self.request);request.update(clientSendNs=110_000_000,observedMonoNs=111_000_000,
            monoNs=112_000_000,clockRequestOrdinal=2,clockRequestOrigin='native')
        reply=copy.deepcopy(self.reply);reply.update(clientSendNs=110_000_000,clientProcessNs=119_000_000,
            serverPreparedNs=715_000_000,clockRequestOrdinal=2,clockRequestOrigin='native')
        self.rows['client1'] += [request,reply]
        result=self.report();epoch=result['roles']['client1']['sampledEpochCompatibility'][0]
        self.assertFalse(epoch['observedConstantOffsetCompatible'])
        self.assertIsNone(epoch['sampledConstantOffsetIntersectionNs'])
        self.assertNotIn('clockErrorBound',result)

    def test_pending_reply_loss_or_no_reply_never_claims_complete_exchange_coverage(self):
        self.reply['pendingDroppedCount']=5
        self.assertFalse(self.report()['roles']['client1']['observedRequestAssociationComplete'])
        self.rows['client1'].remove(self.reply)
        role=self.report()['roles']['client1']
        self.assertFalse(role['observedRequestAssociationComplete'])
        self.assertEqual(role['requestsWithoutObservedReply'],1)

    def test_exact_fixture_attempt_epoch_and_timestamp_are_required(self):
        self.request['connectionEpoch']=2;self.reply['clockRequestConnectionEpoch']=2
        with self.assertRaisesRegex(ValueError,'experiment connection/process'):self.report()
        self.request['connectionEpoch']=1;self.reply['clockRequestConnectionEpoch']=1
        self.plan['fixtureRequestMonoNs']=self.request['clientSendNs']+1
        with self.assertRaisesRegex(ValueError,'predates'):self.report()

    def test_unobserved_reply_never_claims_request_identity(self):
        self.reply.update(clockRequestObserved=False,clockRequestOrdinal=0,clockRequestOrigin='unobserved')
        self.assertEqual(self.report()['roles']['client1']['replies'],{'unobserved-request':1})
        self.reply['clockRequestOrdinal']=1
        with self.assertRaisesRegex(ValueError,'claims an identity'):self.report()


if __name__=='__main__':unittest.main()
