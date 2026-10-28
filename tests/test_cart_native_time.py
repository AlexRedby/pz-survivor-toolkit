"""Offline wire/capture regressions; no game, network or synchronized clocks required."""
import hashlib
import runpy
from types import SimpleNamespace
from pathlib import Path
import struct
import unittest

PATH = Path(__file__).resolve().parent / 'native_queue/contributions/wooden_cart_multiplayer/native_packet_time.py'
NATIVE = SimpleNamespace(**runpy.run_path(str(PATH)))
EPOCHS = dict(client1='00000000-0000-4000-8000-000000000001',
              server='00000000-0000-4000-8000-000000000002',
              client2='00000000-0000-4000-8000-000000000003')
ACTORS = dict(client1=11, server=21, client2=31)
CONNECTIONS = dict(client1=12, server=22, client2=32)
MS = 1_000_000


def wire(*, owner=7, index=0, kind=1, x=100.25, order='>', variables=((0, .7),)):
    # B42 PlayerPacket: owner/index, prediction including optional path,
    # boolean bitfield, variable byte count and enum/float pairs, disconnect/vehicle.
    raw = struct.pack(order+'hBBffBfffB', owner, index, kind, x, 200.5, 0, .4, .5, 1.2, 0)
    if kind == 2:
        raw += struct.pack(order+'ff', 101.5, 202.75)
    raw += struct.pack(order+'hB', 5, len(variables))
    for enum, value in variables:
        raw += struct.pack(order+'Bf', enum, value)
    return raw + struct.pack(order+'Bh', 0, -1)


def packet(role, event, when, raw=None, **changes):
    raw = wire() if raw is None else raw
    row = dict(event=event, nativePacketVersion=1, nativeProcessEpoch=EPOCHS[role],
        actorEpoch=ACTORS[role], connectionEpoch=CONNECTIONS[role], peerRole='server' if role != 'server' else 'client1',
        ownerID=7, packetType=218, packetTypeName='PlayerUpdateUnreliable', packetBodyHex=raw.hex(),
        packetSha256=hashlib.sha256(raw).hexdigest(), packetBytes=len(raw), packetByteOrder='BIG_ENDIAN',
        sourceSetGeneration=0, sourceSampleBeginNs=0, sourceSampleEndNs=0,
        sendGeneration=0, serverReceiveGeneration=0, receiveGeneration=0, ingressGeneration=0, ingressMonoNs=0,
        monoNs=when*MS, serverNs=(1000+when)*MS, clockReady=True)
    row.update(changes)
    return row


def source(generation=1, when=10, actor=11):
    return packet('client1', 'player-source-set', when, actorEpoch=actor,
        connectionEpoch=0, peerRole='unavailable', packetType=-1, packetTypeName='unavailable',
        packetBodyHex='', packetSha256='', packetBytes=0, packetByteOrder='unavailable',
        sourceSetGeneration=generation, sourceSampleBeginNs=(when-2)*MS, sourceSampleEndNs=(when-1)*MS)


def transmit(role, when, generation, *, raw=None, terminal='player-submit', **changes):
    row = packet(role, 'player-write', when, raw, sendGeneration=generation, **changes)
    rows = [row]
    if terminal is not None:
        rows.append(dict(row, event=terminal, monoNs=(when+1)*MS, serverNs=(1001+when)*MS, submissionFailed=False))
    return rows


def receive(role, when, generation, *, raw=None, accepted=False, ingress=True, **changes):
    common = dict(receiveGeneration=generation, ingressGeneration=generation-1, ingressMonoNs=(when-1)*MS)
    common.update(changes)
    row = packet(role, 'player-parse', when, raw, **common)
    rows = []
    if ingress:
        rows.append(dict(row, event='player-ingress', receiveGeneration=0, monoNs=(when-1)*MS,
                         serverNs=(999+when)*MS))
    rows.append(row)
    if accepted:
        rows.append(dict(row, event='player-accepted', monoNs=(when+1)*MS, serverNs=(1001+when)*MS))
    return rows


def draw(generation=41, *, capture=1, when=70, frozen=65, ingress=None, **changes):
    raw = wire()
    row = dict(event='draw-consumed', part='body', key='ToolkitCartPose', captureId=capture, slotToken=90+capture,
        nativeInputVersion=1, nativeProcessEpoch=EPOCHS['client2'], nativeActorEpoch=ACTORS['client2'],
        nativeReceiveGeneration=generation, nativeConnectionEpoch=CONNECTIONS['client2'] if generation else 0,
        nativeIngressGeneration=(generation-1 if ingress is None else ingress) if generation else 0,
        nativePacketSha256=hashlib.sha256(raw).hexdigest() if generation else '',
        monoNs=when*MS, nativeMonoNs=frozen*MS, serverNs=(1000+when)*MS, clockReady=True)
    row.update(changes)
    return row


def fixture(raw=None):
    raw = wire() if raw is None else raw
    start = source()
    traces = dict(client1=[start]+transmit('client1', 20, 3, raw=raw,
        sourceSetGeneration=1, sourceSampleBeginNs=start['sourceSampleBeginNs'], sourceSampleEndNs=start['sourceSampleEndNs']),
        server=receive('server', 30, 23, raw=raw)+transmit('server', 40, 25, raw=raw,
            peerRole='client2', connectionEpoch=24, serverReceiveGeneration=23),
        client2=receive('client2', 50, 41, raw=raw, accepted=True))
    traces['client2'].append(draw(nativePacketSha256=hashlib.sha256(raw).hexdigest()))
    return traces


def events(traces, role, event):
    return [row for row in traces[role] if row['event'] == event]


class ExactNativeBodyChecks(unittest.TestCase):
    def test_real_native_optional_path_and_variable_spans(self):
        for kind in (0, 1, 2):
            for count in (0, 1, 2):
                for order, name in (('>', 'BIG_ENDIAN'), ('<', 'LITTLE_ENDIAN')):
                    with self.subTest(kind=kind, count=count, order=order):
                        raw = wire(kind=kind, order=order, variables=((0, .6), (1, .8))[:count])
                        self.assertEqual(len(raw), 32+5*count+(8 if kind == 2 else 0))
                        row = packet('client1', 'player-write', 1, raw, packetByteOrder=name)
                        self.assertEqual(NATIVE.body(row)[-1], raw)

    def test_signed_short_actor_and_exact_negative_zero_are_preserved(self):
        raw = wire(owner=-7, x=-0.0)
        row = packet('client1', 'player-write', 1, raw, ownerID=-7)
        positive = packet('client1', 'player-write', 1, wire(owner=-7, x=0.0), ownerID=-7)
        self.assertNotEqual(NATIVE.body(row), NATIVE.body(positive))
        self.assertEqual(bytes.fromhex(row['packetBodyHex'])[4:8], b'\x80\x00\x00\x00')

    def test_rejects_malformed_truncated_nonfinite_and_bad_hash(self):
        base = packet('client1', 'player-write', 1)
        cases = [dict(packetBodyHex=base['packetBodyHex'].upper()), dict(packetBytes=36),
                 dict(packetSha256='0'*64), dict(packetByteOrder='native'), dict(ownerID=8),
                 dict(packetBytes=True), dict(packetBodyHex=base['packetBodyHex']+'00', packetBytes=38)]
        for mutation in cases:
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                NATIVE.body(dict(base, **mutation))
        invalid = [wire()[:-1], wire()+b'\x00', wire(x=float('nan')),
                   wire(kind=2, variables=((0, float('inf')),))]
        for raw in invalid:
            with self.subTest(raw=raw.hex()), self.assertRaises(ValueError):
                NATIVE.body(packet('client1', 'player-write', 1, raw))
        raw = bytearray(wire()); raw[28] = 3
        with self.assertRaisesRegex(ValueError, 'span'):
            NATIVE.body(packet('client1', 'player-write', 1, raw))
        raw = bytearray(wire()); raw[-3] = 2
        with self.assertRaisesRegex(ValueError, 'boolean'):
            NATIVE.body(packet('client1', 'player-write', 1, raw))

    def test_byte_order_remains_part_of_exact_identity(self):
        # Symmetric bytes remain byte-for-byte equal and finite in both orders.
        raw = bytes(32)
        big = packet('client1', 'player-write', 1, raw, ownerID=0)
        little = dict(big, packetByteOrder='LITTLE_ENDIAN')
        self.assertNotEqual(NATIVE.body(big), NATIVE.body(little))


class NativePacketAssociationChecks(unittest.TestCase):
    def test_full_route_freezes_exact_accepted_generation(self):
        result = NATIVE.native_packet_report(fixture())
        self.assertTrue(result['available'])
        self.assertTrue(result['diagnosticOnly'])
        self.assertEqual(result['observerReceipts'], {'unique-observed-source': 1})
        self.assertEqual(result['sourceSetEventToDrawPointEstimateMs']['minimum'], 60)
        self.assertEqual(result['receiptToDrawMs']['minimum'], 20)
        self.assertEqual(result['snapshotAssociations'][0]['receiveGeneration'], 41)
        self.assertEqual(result['receiptAssociations'][0]['serverReceiveGenerations'], [23])
        self.assertTrue(any('not the exclusive source' in text for text in result['limitations']))
        self.assertTrue(any('unobserved startup' in text for text in result['limitations']))

    def test_submitted_retransmissions_keep_one_source_generation(self):
        traces = fixture(); start = traces['client1'][0]
        traces['client1'] += transmit('client1', 25, 4, sourceSetGeneration=1,
            sourceSampleBeginNs=start['sourceSampleBeginNs'], sourceSampleEndNs=start['sourceSampleEndNs'])
        result = NATIVE.native_packet_report(traces)
        association = result['receiptAssociations'][0]
        self.assertEqual(association['status'], 'unique-observed-source')
        self.assertEqual(len(association['sourceGenerations']), 1)
        self.assertEqual(association['sourceTransmissionOccurrences'], 2)

    def test_identical_bodies_distinct_source_samples_are_not_greedily_paired(self):
        traces = fixture(); newer = source(2, 26)
        traces['client1'] += [newer]+transmit('client1', 28, 5, sourceSetGeneration=2,
            sourceSampleBeginNs=newer['sourceSampleBeginNs'], sourceSampleEndNs=newer['sourceSampleEndNs'])
        traces['client2'] += receive('client2', 54, 43, accepted=True)+[draw(43, capture=2)]
        result = NATIVE.native_packet_report(traces)
        self.assertEqual(result['observerReceipts'], {'ambiguous-source': 2})
        for association in result['receiptAssociations']:
            self.assertEqual([item['generation'] for item in association['sourceGenerations']], [1, 2])
        self.assertEqual(result['sourceSetEventToDrawPointEstimateMs']['count'], 0)
        self.assertEqual(result['snapshotAssociations'][0]['sourceSetEventToDrawPointEstimateRangeMs'], [44, 60])

    def test_cancelled_and_unfinished_preparations_never_become_sources(self):
        for terminal in ('player-cancel', None):
            traces = fixture()
            traces['client1'] = traces['client1'][:1]+transmit('client1', 20, 3,
                terminal=terminal, sourceSetGeneration=1, sourceSampleBeginNs=8*MS, sourceSampleEndNs=9*MS)
            result = NATIVE.native_packet_report(traces)
            self.assertEqual(result['observerReceipts'], {'unmatched': 1})
            self.assertEqual(result['sourceSetEventToDrawPointEstimateMs']['count'], 0)
            self.assertEqual(result['cancelledWrites'], int(terminal == 'player-cancel'))
            self.assertEqual(result['unmatched']['write-without-terminal'], int(terminal is None))

    def test_server_fanout_uses_exact_parent_and_directed_recipient(self):
        traces = fixture()
        traces['server'] += transmit('server', 41, 26, peerRole='client1', connectionEpoch=22, serverReceiveGeneration=23)
        result = NATIVE.native_packet_report(traces)
        self.assertEqual(result['receiptAssociations'][0]['serverTransmissionOccurrences'], 1)
        for row in events(traces, 'server', 'player-write')+events(traces, 'server', 'player-submit'):
            if row['peerRole'] == 'client2':
                row['serverReceiveGeneration'] = 999
        result = NATIVE.native_packet_report(traces)
        self.assertEqual(result['observerReceipts'], {'unmatched': 1})
        self.assertEqual(result['unmatched']['fanout-without-source-receipt'], 1)

    def test_cancelled_fanout_cannot_supply_observer_route(self):
        traces = fixture()
        events(traces, 'server', 'player-submit')[0]['event'] = 'player-cancel'
        self.assertEqual(NATIVE.native_packet_report(traces)['observerReceipts'], {'unmatched': 1})

    def test_exact_wire_not_float_value_or_hash_alone_controls_matching(self):
        for raw in (wire(x=-0.0), wire(order='<')):
            traces = fixture(wire(x=0.0) if raw == wire(x=-0.0) else None)
            for row in traces['client2']:
                if row['event'] != 'draw-consumed':
                    row.update(packetBodyHex=raw.hex(), packetSha256=hashlib.sha256(raw).hexdigest(),
                               packetBytes=len(raw), packetByteOrder='LITTLE_ENDIAN' if raw == wire(order='<') else 'BIG_ENDIAN')
            traces['client2'][-1]['nativePacketSha256'] = hashlib.sha256(raw).hexdigest()
            self.assertEqual(NATIVE.native_packet_report(traces)['observerReceipts'], {'unmatched': 1})

    def test_unavailable_or_wrong_packet_route_never_yields_unique_source(self):
        mutations = [dict(packetType=-1, packetTypeName='unavailable'), dict(packetType=213),
                     dict(packetTypeName='Other'), dict(peerRole='client1'), dict(peerRole='unavailable')]
        for mutation in mutations:
            traces = fixture()
            for row in traces['client2']:
                if row['event'] != 'draw-consumed':
                    row.update(mutation)
            with self.subTest(mutation=mutation):
                self.assertEqual(NATIVE.native_packet_report(traces)['observerReceipts'], {'unmatched': 1})

    def test_missing_source_metadata_and_ingress_are_explicit(self):
        traces = fixture(); traces['client1'].pop(0)
        traces['client2'] = [row for row in traces['client2'] if row['event'] != 'player-ingress']
        result = NATIVE.native_packet_report(traces)
        self.assertEqual(result['observerReceipts'], {'incomplete-source-evidence': 1})
        self.assertEqual(result['unmatched']['submitted-without-source-set'], 1)
        self.assertEqual(result['unmatched']['parse-without-observed-ingress'], 1)
        self.assertEqual(result['receiptAssociations'][0]['missingSourceOccurrences'], 1)

    def test_multiple_connection_or_actor_epochs_stay_ambiguous(self):
        for changes in (dict(connectionEpoch=124), dict(actorEpoch=121)):
            traces = fixture()
            if 'actorEpoch' in changes:
                traces['server'] += receive('server', 60, 123, actorEpoch=121)
                traces['server'] += transmit('server', 62, 125, peerRole='client2',
                    connectionEpoch=24, serverReceiveGeneration=123, **changes)
            else:
                traces['server'] += transmit('server', 42, 125, peerRole='client2', serverReceiveGeneration=23, **changes)
            with self.subTest(changes=changes):
                self.assertEqual(NATIVE.native_packet_report(traces)['observerReceipts'], {'ambiguous-route': 1})

    def test_source_and_observer_epoch_reuse_cannot_be_disambiguated_by_time(self):
        traces = fixture(); start = source(2, 26, actor=111)
        traces['client1'] += [start]+transmit('client1', 28, 5, actorEpoch=111,
            sourceSetGeneration=2, sourceSampleBeginNs=24*MS, sourceSampleEndNs=25*MS)
        self.assertEqual(NATIVE.native_packet_report(traces)['observerReceipts'], {'ambiguous-route': 1})
        traces = fixture()
        traces['client2'] += receive('client2', 55, 141, actorEpoch=131, connectionEpoch=132)
        self.assertEqual(NATIVE.native_packet_report(traces)['observerReceipts'], {'ambiguous-route': 2})

    def test_missing_one_of_several_source_samples_never_claims_uniqueness(self):
        traces = fixture()
        traces['client1'] += transmit('client1', 28, 5, sourceSetGeneration=999)
        result = NATIVE.native_packet_report(traces)
        self.assertEqual(result['receiptAssociations'][0]['status'], 'incomplete-source-evidence')
        self.assertEqual(len(result['receiptAssociations'][0]['sourceGenerations']), 1)
        self.assertEqual(result['sourceSetEventToDrawPointEstimateMs']['count'], 0)

    def test_wrong_source_actor_and_changed_source_interval_are_rejected(self):
        traces = fixture()
        traces['client1'][0]['actorEpoch'] += 1
        result = NATIVE.native_packet_report(traces)
        self.assertEqual(result['observerReceipts'], {'incomplete-source-evidence': 1})
        traces = fixture(); traces['client1'][0]['sourceSampleEndNs'] -= 1
        with self.assertRaisesRegex(ValueError, 'source/write identity'):
            NATIVE.native_packet_report(traces)
        traces = fixture(); traces['client1'][0]['sourceSampleBeginNs'] = 11*MS
        with self.assertRaisesRegex(ValueError, 'sample interval'):
            NATIVE.native_packet_report(traces)

    def test_changed_terminal_ingress_acceptance_and_parent_identity_are_rejected(self):
        mutations = [('client1', 'player-submit', 'sourceSetGeneration', 99),
                     ('client1', 'player-submit', 'packetTypeName', 'Other'),
                     ('server', 'player-ingress', 'actorEpoch', 99),
                     ('client2', 'player-accepted', 'packetByteOrder', 'LITTLE_ENDIAN'),
                     ('client2', 'player-accepted', 'ingressGeneration', 99)]
        for role, event, field, value in mutations:
            traces = fixture()
            events(traces, role, event)[0][field] = value
            with self.subTest(event=event, field=field), self.assertRaises(ValueError):
                NATIVE.native_packet_report(traces)
        traces = fixture()
        for row in events(traces, 'server', 'player-write')+events(traces, 'server', 'player-submit'):
            row['actorEpoch'] += 1
        with self.assertRaisesRegex(ValueError, 'fanout actor'):
            NATIVE.native_packet_report(traces)

    def test_repeated_acceptance_preserves_earliest_consistent_copy(self):
        traces = fixture()
        first = events(traces, 'client2', 'player-accepted')[0]
        traces['client2'].append(dict(first, monoNs=90*MS, serverNs=1090*MS))
        result = NATIVE.native_packet_report(traces)
        self.assertEqual(result['acceptanceOccurrences'], 2)
        self.assertEqual(result['acceptedGenerations'], 1)
        self.assertEqual(result['observerBodySnapshots']['unique-observed-source'], 1)
        traces['client2'][-1]['ingressGeneration'] = 999
        with self.assertRaisesRegex(ValueError, 'repeated acceptance'):
            NATIVE.native_packet_report(traces)

    def test_snapshot_without_observed_client_packet_reports_missing_receipt(self):
        traces = fixture(); traces['client2'] = [draw()]
        result = NATIVE.native_packet_report(traces)
        self.assertEqual(result['observerBodySnapshots']['missing-accepted-receipt'], 1)

    def test_cached_receipt_reparse_and_skipped_acceptance_preserve_old_frozen_input(self):
        traces = fixture()
        traces['client2'] += receive('client2', 60, 43, accepted=False)
        # A draw consumed later can still own a slot prepared before a newer acceptance.
        traces['client2'] += receive('client2', 80, 45, accepted=True)
        traces['client2'].append(draw(41, capture=2, when=100, frozen=65))
        result = NATIVE.native_packet_report(traces)
        self.assertEqual([row['receiveGeneration'] for row in result['snapshotAssociations']], [41, 41])
        traces['client2'].append(draw(43, capture=3, when=100, frozen=65))
        result = NATIVE.native_packet_report(traces)
        self.assertEqual(result['observerBodySnapshots']['missing-accepted-receipt'], 1)

    def test_frozen_actor_hash_ingress_epoch_and_capture_time_are_checked(self):
        mutations = [dict(nativeActorEpoch=99), dict(nativePacketSha256='0'*64),
                     dict(nativeIngressGeneration=99), dict(nativeMonoNs=49*MS),
                     dict(nativeProcessEpoch=EPOCHS['server']), dict(nativeInputVersion=2)]
        for mutation in mutations:
            traces = fixture(); traces['client2'][-1].update(mutation)
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                NATIVE.native_packet_report(traces)
        traces = fixture(); traces['client2'][-1]['nativeConnectionEpoch'] += 1
        self.assertEqual(NATIVE.native_packet_report(traces)['observerBodySnapshots']['missing-accepted-receipt'], 1)

    def test_empty_input_and_missing_snapshot_metadata_are_reported(self):
        traces = fixture(); traces['client2'][-1] = draw(0)
        traces['client2'].append(dict(draw(capture=2), nativeInputVersion=None))
        result = NATIVE.native_packet_report(traces)
        self.assertEqual(result['observerBodySnapshots'], {'no-accepted-native-input': 1, 'missing-input-metadata': 1})
        traces['client2'][-2]['nativeProcessEpoch'] = EPOCHS['server']
        with self.assertRaisesRegex(ValueError, 'snapshot process'):
            NATIVE.native_packet_report(traces)

    def test_clock_unready_and_negative_point_estimates_are_explicit(self):
        traces = fixture(); traces['client2'][-1]['clockReady'] = False
        result = NATIVE.native_packet_report(traces)
        self.assertEqual(result['sourceSetEventToDrawPointEstimateMs']['count'], 0)
        self.assertEqual(result['snapshotAssociations'][0]['sourceClockStatus'], 'unavailable')
        self.assertEqual(result['observerBodySnapshots']['source-clock-unavailable'], 1)
        traces = fixture(); traces['client2'][-1]['serverNs'] = 1000*MS
        result = NATIVE.native_packet_report(traces)
        self.assertEqual(result['sourceSetEventToDrawPointEstimateMs']['minimum'], -10)
        self.assertEqual(result['observerBodySnapshots']['negative-source-point-estimate'], 1)
        self.assertTrue(any('do not bound clock error' in text for text in result['limitations']))
        self.assertEqual(result['receiptToDrawMs']['minimum'], 20)

    def test_old_traces_are_unavailable_instead_of_fabricated_associations(self):
        traces = dict(client1=[dict(event='player-write', serializedBytes=37)], client2=[draw()])
        result = NATIVE.native_packet_report(traces)
        self.assertFalse(result['available'])
        self.assertIn('not captured', result['reason'])

    def test_schema_versions_and_generation_types_are_strict(self):
        for field, value in (('nativePacketVersion', True), ('nativePacketVersion', 2),
                             ('sendGeneration', True), ('actorEpoch', 0), ('nativeProcessEpoch', 'legacy')):
            traces = fixture(); traces['client1'][-1][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                NATIVE.native_packet_report(traces)
        traces = fixture(); traces['client2'][-1]['nativeInputVersion'] = True
        with self.assertRaisesRegex(ValueError, 'input version'):
            NATIVE.native_packet_report(traces)

    def test_process_restart_or_epoch_reuse_cannot_merge(self):
        traces = fixture(); traces['client1'][-1]['nativeProcessEpoch'] = '00000000-0000-4000-8000-000000000009'
        with self.assertRaisesRegex(ValueError, 'Multiple native process epochs'):
            NATIVE.native_packet_report(traces)
        traces = fixture()
        for row in traces['server']:
            row['nativeProcessEpoch'] = EPOCHS['client1']
        with self.assertRaisesRegex(ValueError, 'reused across roles'):
            NATIVE.native_packet_report(traces)


if __name__ == '__main__':
    unittest.main()
