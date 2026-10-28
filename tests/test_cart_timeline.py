"""Cart timing join/clock/transport failure regressions; synthetic evidence only."""
import copy
import json
from pathlib import Path
import runpy
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ANALYZER = ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer/analyze-timeline.py'
api = runpy.run_path(str(ANALYZER))


class CartTimelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root/'selection.json').write_text(json.dumps(dict(suite='wooden_cart_multiplayer', kind='mp', mode='toolkit', options=dict(cart_timeline=True))))
        self.rows = {role: [] for role in api['ROLES']}
        self.pose = dict(key='ToolkitCartPose', raw='1,42,3,0,0,0,1,0,0,0,0,0,0', cartID=42, serial=3)
        def pose(role, event, at, **fields): return self.add(role,event,at,**self.pose,**fields)
        pose('client1','publish',100)
        pose('client1','variable-write',101,serializedBytes=77)
        self.add('client1','player-write',102,serializedBytes=44)
        pose('server','variable-process-server-enter',110)
        pose('server','variable-write',111,serializedBytes=77)
        pose('server','variable-process-server-exit',112)
        pose('client2','variable-parse',120)
        pose('client2','variable-process-client',121)
        self.add('client2','player-parse',122,serializedBytes=-1)
        pose('client2','prediction-update',123)
        pose('client2','animation-update',124)
        for role in ('client1','client2'):
            at = 130 if role == 'client2' else 105
            fields = dict(captureId=1,slotToken=7,preparedPrimary=42,preparedSecondary=42,
                          nativeMonoNs=at*1_000_000-1_000_000,nativeServerNs=at*1_000_000-1_000_000,nativeClockReady=True)
            pose(role,'capture-prepared',at,part='both',**fields)
            pose(role,'draw-consumed',at+1,part='body',**fields)
            pose(role,'draw-consumed',at+2,part='cart',**fields)
        for role in self.rows:
            for i,at in enumerate((150,1150)):
                self.add(role,'transport-stats',at,connectionGUID='99',endpoint='server' if role!='server' else 'client2',
                         scope='owned-connection-all-native-traffic',headerCoverage='unverified',available=True,
                         nativeActualBytesSent=100+1000*i,nativeActualBytesReceived=50+500*i,
                         userBytesResent=10+20*i,resendBufferBytes=25-i,resendBufferMessages=1)
            self.add(role,'trace-end',1200,failed=False)
        for role in ('client1','client2'):
            clock=dict(schema=1,event='clock-sync',actor=role,seq=1,monoNs=99_000_000,serverNs=99_000_000,
                       wallMs=99,clockReady=True,ownerID=7,clientSendNs=90_000_000,serverPreparedNs=594_000_000,
                       clientProcessNs=98_000_000,observedMonoNs=98_000_000,offsetBeforeNs=0,offsetAfterNs=5_000_000,
                       readyBefore=True,readyAfter=True,connectionGUID='99',connectionToken=10,
                       pendingBeforeOwner=True,pendingDroppedCount=0)
            self.rows[role].insert(0,clock)
            for i,row in enumerate(self.rows[role],1): row['seq']=i
        self.write()

    def add(self,role,event,at,**fields):
        row = dict(schema=1,event=event,actor=role,seq=len(self.rows[role])+1,monoNs=at*1_000_000,
                   serverNs=at*1_000_000,wallMs=at,clockReady=True,ownerID=7,**fields)
        self.rows[role].append(row); return row

    def write(self):
        for role,rows in self.rows.items():
            path = self.root/role; path.mkdir(exist_ok=True)
            (path/('cart-timeline-server.jsonl' if role=='server' else 'cart-timeline.jsonl')).write_text('\n'.join(json.dumps(row) for row in rows)+'\n')

    def analyze(self): self.write(); return api['analyze'](self.root)

    def test_join_measures_native_clock_age_and_consumed_slot_without_claiming_image_equivalence(self):
        report = self.analyze()
        self.assertTrue(report['baselineStagesObserved'])
        self.assertNotIn('functionalPass',report)
        self.assertNotIn('animationEquivalencePass',report)
        age=report['durationsMs']['client2/draw-consumed/ToolkitCartPose/cart/allObservationPublicationAgeMs']
        self.assertEqual(age['count'],1); self.assertEqual(age['p50'],32)
        self.assertEqual(report['durationsMs']['client2/receiptToDrawMs']['maximum'],11)
        self.assertEqual(report['durationsMs']['client2/nativeCaptureToDrawMs']['maximum'],3)
        self.assertEqual(report['preparedWithoutBothDraws'],0)
        self.assertEqual(report['transport'][0]['nativeActualBytesSentDelta'],1000)
        self.assertEqual(report['transport'][0]['userBytesResentPerSecond'],20)
        self.assertIn('IP/UDP/header coverage is unverified',' '.join(report['limitations']))

    def test_zero_unsynchronized_clock_is_retained_but_not_used_for_cross_process_age(self):
        next(row for row in self.rows['client1'] if row['event']=='publish').update(clockReady=False,serverNs=0)
        report = self.analyze()
        self.assertEqual(report['clocks']['unsynchronizedEvents'],1)
        self.assertNotIn('client2/draw-consumed/ToolkitCartPose/cart/allObservationPublicationAgeMs',report['durationsMs'])
        self.assertEqual(report['durationsMs']['client2/receiptToDrawMs']['maximum'],11)

    def test_same_serial_after_sender_reset_is_ambiguous_even_if_raw_value_repeats(self):
        rows=self.rows['client1']; duplicate=copy.deepcopy(next(row for row in rows if row['event']=='publish'));duplicate.update(monoNs=100_000_001)
        rows.insert(2,duplicate)
        for i,row in enumerate(rows,1): row['seq']=i
        report=self.analyze()
        self.assertEqual(report['ambiguousPublicationIdentities'],1)
        self.assertGreater(report['unmatchedJoins']['ambiguous-publication'],0)
        self.assertNotIn('client2/draw-consumed/ToolkitCartPose/cart/allObservationPublicationAgeMs',report['durationsMs'])

    def test_draw_must_keep_frozen_payload_hands_and_exact_slot(self):
        for field,value in (('slotToken',8),('raw','1,42,4,0,0,0,1,0,0,0,0,0,0'),('preparedPrimary',-1),('nativeMonoNs',1)):
            row=next(row for row in self.rows['client2'] if row['event']=='draw-consumed')
            original=copy.deepcopy(row);row[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError): self.analyze()
            row.clear();row.update(original)

    def test_duplicate_receipt_after_preparation_does_not_rejuvenate_frozen_frame(self):
        rows=self.rows['client2']; before=next(i for i,row in enumerate(rows) if row['event']=='draw-consumed')
        receipt=copy.deepcopy(next(row for row in rows if row['event']=='variable-process-client'))
        receipt.update(monoNs=130_500_000,serverNs=130_500_000)
        rows.insert(before,receipt)
        for i,row in enumerate(rows,1): row['seq']=i
        report=self.analyze()
        self.assertEqual(report['durationsMs']['client2/receiptToDrawMs']['maximum'],11)

    def test_trace_loss_failure_incomplete_close_and_counter_reset_are_rejected(self):
        mutations = [lambda rows: rows[2].update(seq=20),lambda rows: rows[-1].update(failed=True),
                     lambda rows: rows.pop(),lambda rows: rows[-2].update(nativeActualBytesSent=0),
                     lambda rows: next(row for row in rows if row['event']=='variable-parse').update(shapeError=True),lambda rows: rows[0].update(serverNs=0),
                     lambda rows: rows[0].update(predictionX=float('nan'))]
        original=copy.deepcopy(self.rows)
        for mutate in mutations:
            self.rows=copy.deepcopy(original);mutate(self.rows['client2'])
            with self.subTest(mutate=mutate),self.assertRaises(ValueError): self.analyze()

    def test_missing_native_stage_and_unavailable_wire_stats_are_explicit(self):
        self.rows['client2']=[row for row in self.rows['client2'] if row['event']!='player-parse']
        for i,row in enumerate(self.rows['client2'],1): row['seq']=i
        for rows in self.rows.values():
            for row in rows:
                if row['event']=='transport-stats': row['available']=False
        report=self.analyze()
        self.assertFalse(report['baselineStagesObserved'])
        self.assertEqual(report['missingStages']['client2'],['player-parse'])
        self.assertTrue(all(row['availableSamples']==0 for row in report['transport']))

    def test_clock_interval_is_conditional_and_filter_lag_is_separate_from_ready_flag(self):
        sync=self.analyze()['clocks']['synchronization']
        owner=sync['roles']['client1'];exchange=owner['connectionEpochs'][0]['exchanges'][0]
        self.assertEqual(exchange['rttMs'],8)
        self.assertEqual((exchange['offsetLowerNs'],exchange['offsetUpperNs']),(496_000_000,504_000_000))
        self.assertEqual(exchange['filteredMinusMidpointMs'],-495)
        self.assertEqual(exchange['filteredDistanceOutsideExchangeIntervalMs'],491)
        self.assertTrue(exchange['readyAfter'])
        self.assertIn('not a clock accuracy bound',sync['qualification'])
        self.assertIn('Unknown between exchanges',sync['eventTimeOffsetBounds'])

    def test_clock_pending_loss_and_connection_epoch_are_explicit(self):
        row=next(row for row in self.rows['client2'] if row['event']=='clock-sync');row['pendingDroppedCount']=4
        other=copy.deepcopy(row);other.update(monoNs=1190_000_000,serverNs=1190_000_000,
            clientSendNs=1180_000_000,clientProcessNs=1188_000_000,serverPreparedNs=1191_000_000,
            observedMonoNs=1188_000_000,connectionGUID='100',connectionToken=11,pendingBeforeOwner=False)
        self.rows['client2'].insert(-1,other)
        for i,row in enumerate(self.rows['client2'],1): row['seq']=i
        report=self.analyze()['clocks']['synchronization']['roles']['client2']
        self.assertEqual(report['pendingDroppedCount'],4)
        self.assertEqual(len(report['connectionEpochs']),2)

    def test_clock_invalid_exchange_or_observation_order_is_rejected(self):
        row=next(row for row in self.rows['client2'] if row['event']=='clock-sync')
        original=copy.deepcopy(row)
        for field,value in (('clientProcessNs',89_000_000),('observedMonoNs',97_000_000),('readyBefore','true'),('connectionGUID','')):
            row.clear();row.update(original);row[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError): self.analyze()

    def test_native_menu_host_child_trace_is_distinct_in_shared_owner_cache(self):
        selection=json.loads((self.root/'selection.json').read_text());selection['options']['mp_host']=True
        (self.root/'selection.json').write_text(json.dumps(selection))
        source=self.root/'server/cart-timeline-server.jsonl';source.rename(self.root/'client1/cart-timeline-server.jsonl')
        report=api['analyze'](self.root)
        self.assertEqual(report['sourceFiles']['server'],'client1/cart-timeline-server.jsonl')
        self.assertEqual(report['sourceFiles']['client1'],'client1/cart-timeline.jsonl')

    def test_first_delivery_excludes_late_cached_repeats_of_the_same_serial(self):
        rows=self.rows['server'];original=next(row for row in rows if row['event']=='variable-write')
        for at in (211,1011):
            repeat=copy.deepcopy(original);repeat.update(monoNs=at*1_000_000,serverNs=at*1_000_000,wallMs=at);rows.append(repeat)
        rows.sort(key=lambda row:row['monoNs'])
        for i,row in enumerate(rows,1): row['seq']=i
        report=self.analyze();stage='server/variable-write/ToolkitCartPose'
        self.assertEqual(report['durationsMs'][stage+'/allObservationPublicationAgeMs']['maximum'],911)
        self.assertEqual(report['durationsMs'][stage+'/allObservationPublicationAgeMs']['count'],3)
        self.assertEqual(report['durationsMs'][stage+'/firstDeliveryPublicationAgeMs']['maximum'],11)
        self.assertEqual(report['durationsMs'][stage+'/firstDeliveryPublicationAgeMs']['count'],1)
        self.assertEqual(report['repeatedStageObservations'][stage],2)

    def test_unsynchronized_first_receipt_is_not_replaced_by_a_later_ready_repeat(self):
        rows=self.rows['client2'];first=next(row for row in rows if row['event']=='variable-parse')
        later=copy.deepcopy(first);later.update(monoNs=220_000_000,serverNs=220_000_000,wallMs=220)
        first.update(clockReady=False,serverNs=0);rows.append(later);rows.sort(key=lambda row:row['monoNs'])
        for i,row in enumerate(rows,1): row['seq']=i
        report=self.analyze();stage='client2/variable-parse/ToolkitCartPose'
        self.assertNotIn(stage+'/firstDeliveryPublicationAgeMs',report['durationsMs'])
        self.assertEqual(report['firstDeliverySkipped'][stage+'/clock-not-ready'],1)
        self.assertEqual(report['durationsMs'][stage+'/allObservationPublicationAgeMs']['maximum'],120)

    def active_fixture(self):
        path=self.root/'analysis/canonical';path.mkdir(parents=True)
        (path/'mp-comparison.json').write_text(json.dumps(dict(epoch=200,ownerOnlineID=7,cartID=42,evidenceComplete=True)))
        for role,rows in self.rows.items():
            template=next(row for row in rows if row['event']=='transport-stats')
            for at,total in ((14900,2100),(17000,999999)):
                row=copy.deepcopy(template);row.update(monoNs=at*1_000_000,serverNs=at*1_000_000,wallMs=at,
                    nativeActualBytesSent=total,nativeActualBytesReceived=total,userBytesResent=total)
                rows.append(row)
            end=next(row for row in rows if row['event']=='trace-end');end.update(monoNs=18000_000_000,serverNs=18000_000_000,wallMs=18000)
            if role=='server':
                template=next(row for row in rows if row['event']=='variable-write')
                for at in (500,1000):
                    row=copy.deepcopy(template);row.update(monoNs=at*1_000_000,serverNs=at*1_000_000,wallMs=at);rows.append(row)
            rows.sort(key=lambda row:row['monoNs'])
            for i,row in enumerate(rows,1): row['seq']=i

    def test_active_motion_counts_serializations_and_only_actual_counter_samples_inside_window(self):
        self.active_fixture();active=self.analyze()['activeMotion']
        self.assertEqual((active['startWallMs'],active['endWallMs'],active['durationMs']),(200,15200,15000))
        self.assertEqual(active['epochSource'],'analysis/canonical/mp-comparison.json')
        write=next(row for row in active['serializedCartWrites'] if row['actor']=='server')
        self.assertEqual((write['writes'],write['serializedBytes'],write['uniquePayloadIdentities'],write['repeatedIdentityWrites']),(2,154,1,1))
        for row in active['nativeConnectionTraffic']:
            self.assertEqual((row['firstSampleWallMs'],row['lastSampleWallMs']),(1150,14900))
            self.assertEqual((row['uncoveredStartMs'],row['uncoveredEndMs']),(950,300))
            self.assertEqual(row['nativeActualBytesSentDelta'],1000)
            self.assertFalse(row['interpolated']);self.assertFalse(row['extrapolated'])
            self.assertEqual(row['headerCoverage'],'unverified')

    def test_active_motion_duration_uses_frozen_fast_flag_and_inventory_has_separate_scope(self):
        self.active_fixture();path=self.root/'selection.json';selected=json.loads(path.read_text());selected['options']['cart_fast_motion']=True
        path.write_text(json.dumps(selected));self.assertEqual(self.analyze()['activeMotion']['durationMs'],26000)
        selected['options']['cart_inventory_equip']=True;path.write_text(json.dumps(selected))
        report=self.analyze();self.assertFalse(report['activeMotion']['available'])
        self.assertIn('Inventory-equip',report['activeMotion']['reason'])
        self.assertEqual(len(report['transport']),3)

    def test_active_window_missing_or_single_counter_samples_never_extrapolate(self):
        self.active_fixture()
        for rows in self.rows.values():
            for row in rows:
                if row['event']=='transport-stats' and (row['wallMs']==14900 or row['actor']=='client2' and row['wallMs']==1150): row['available']=False
        active=self.analyze()['activeMotion']
        for row in active['nativeConnectionTraffic']:
            self.assertEqual(row['availableSamplesInsideWindow'],0 if row['actor']=='client2' else 1)
            if row['actor']=='client2': self.assertEqual(row['uncoveredTotalMs'],15000)
            self.assertNotIn('nativeActualBytesSentDelta',row)
            self.assertEqual(row['coverageFraction'],0)
            self.assertIn('Fewer than two',row['deltaUnavailableReason'])

    def test_conflicting_motion_epochs_or_wrong_owner_are_rejected(self):
        self.active_fixture();path=self.root/'analysis/other';path.mkdir()
        report=dict(epoch=201,ownerOnlineID=7,cartID=42,evidenceComplete=True)
        (path/'mp-comparison.json').write_text(json.dumps(report))
        with self.assertRaisesRegex(ValueError,'Conflicting'): self.analyze()
        report.update(epoch=200,ownerOnlineID=8);(path/'mp-comparison.json').write_text(json.dumps(report))
        with self.assertRaises(ValueError): self.analyze()

    def test_explicit_selection_and_async_writer_errors_are_required(self):
        path=self.root/'selection.json';selection=json.loads(path.read_text());selection['options']['cart_timeline']='true'
        path.write_text(json.dumps(selection))
        with self.assertRaisesRegex(ValueError,'Explicit'): self.analyze()
        selection['options']['cart_timeline']=True;path.write_text(json.dumps(selection))
        (self.root/'server-launch.log').write_text('[CART_TIMELINE] ERROR writer overflow')
        with self.assertRaisesRegex(ValueError,'diagnostic error'): self.analyze()


if __name__ == '__main__': unittest.main()
