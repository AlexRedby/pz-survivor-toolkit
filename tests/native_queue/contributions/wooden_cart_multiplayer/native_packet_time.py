"""Exact observed native packet associations; never a production playback clock."""
from collections import Counter, defaultdict
import hashlib
import math
import re
import struct
import uuid

PACKET_EVENTS = {'player-source-set', 'player-write', 'player-submit', 'player-cancel',
                 'player-ingress', 'player-parse', 'player-accepted'}
SNAPSHOT_FIELDS = ('nativeInputVersion', 'nativeProcessEpoch', 'nativeActorEpoch',
                   'nativeReceiveGeneration', 'nativeConnectionEpoch',
                   'nativeIngressGeneration', 'nativePacketSha256')
IDS = ('actorEpoch', 'connectionEpoch', 'sourceSetGeneration', 'sendGeneration',
       'serverReceiveGeneration', 'receiveGeneration', 'ingressGeneration')
LIMITS = [
    'Associations are exact within the observed complete traces, not proof of unobserved startup traffic or a shipped source-time bridge.',
    'Identical bodies in different source generations remain ambiguous; no nearest timestamp, greedy pairing or undocumented clock bound filters candidates.',
    'Submission means normal native endPacket completion, not a delivery acknowledgement; prepared/cancelled writes are not submitted samples.',
    'A captured accepted prediction generation is a current native input revision. Stateful locomotion, root integration and skeleton phase can retain earlier inputs; it is not the exclusive source of the whole image.',
    'Cross-process ages are synchronized-clock point estimates. Startup readiness and latest TimeSync exchange do not bound clock error or inter-exchange drift.',
    'Same-body equality includes all exact native bytes, packet type, route and local epochs. SHA256 is only an index; raw body equality is checked.',
]


def integer(row, key, minimum=0):
    value = row.get(key)
    if type(value) is not int or value < minimum:
        raise ValueError('Invalid native integer ' + key)
    return value


def body(row):
    """Validate captured B42.21 layout without reserializing/normalizing float bits."""
    size = integer(row, 'packetBytes')
    text = row.get('packetBodyHex')
    digest = row.get('packetSha256')
    if not isinstance(text, str) or not re.fullmatch(r'[0-9a-f]*', text) or len(text) != size*2:
        raise ValueError('Invalid exact native body hex')
    if size == 0:
        if row['event'] != 'player-source-set' or text or digest != '':
            raise ValueError('Missing native body')
        return None
    if not 32 <= size <= 256:
        raise ValueError('Unbounded/short native body')
    raw = bytes.fromhex(text)
    if digest != hashlib.sha256(raw).hexdigest():
        raise ValueError('Native body SHA256 mismatch')
    order = row.get('packetByteOrder')
    if order not in ('BIG_ENDIAN', 'LITTLE_ENDIAN'):
        raise ValueError('Missing native byte order')
    endian = '>' if order == 'BIG_ENDIAN' else '<'
    owner = struct.unpack_from(endian+'h', raw)[0]
    if owner != integer(row, 'ownerID', -32768) or owner > 32767:
        raise ValueError('Native body actor differs from resolved owner')
    path = raw[3] == 2
    count_at = 28 + (8 if path else 0)
    if count_at >= size:
        raise ValueError('Truncated native prediction')
    count = raw[count_at]
    if count > 2 or size != 32 + 5*count + (8 if path else 0):
        raise ValueError('Native variable count/body span mismatch')
    floats = [4, 8, 13, 17, 21]
    if path:
        floats += [26, 30]
    floats += [count_at+2+5*i for i in range(count)]
    if any(not math.isfinite(struct.unpack_from(endian+'f', raw, offset)[0]) for offset in floats):
        raise ValueError('Nonfinite native prediction/variable')
    if raw[-3] not in (0, 1):
        raise ValueError('Unexpected native boolean encoding')
    return row['packetType'], row['packetTypeName'], order, raw


def process(row):
    value = row.get('nativeProcessEpoch')
    if not isinstance(value, str):
        raise ValueError('Missing native process epoch')
    try:
        uuid.UUID(value)
    except (ValueError, AttributeError):
        raise ValueError('Invalid native process epoch') from None
    return value


def native_packet_report(traces):
    events = [(role, row) for role, rows in traces.items() for row in rows
              if row.get('event') in PACKET_EVENTS and row.get('nativePacketVersion') is not None]
    if not events:
        return dict(available=False, reason='Exact native packet tracing was not captured', limitations=LIMITS)
    processes = defaultdict(set)
    for role, row in events:
        if type(row.get('nativePacketVersion')) is not int or row['nativePacketVersion'] != 1:
            raise ValueError('Unknown native packet trace version')
        processes[role].add(process(row))
        for field in IDS:
            integer(row, field)
        integer(row, 'actorEpoch', 1)
        if integer(row, 'ownerID', -32768) > 32767:
            raise ValueError('Invalid native owner ID')
        integer(row, 'packetType', -1)
        integer(row, 'monoNs', -(1 << 63))
        integer(row, 'serverNs', -(1 << 63))
        if type(row.get('clockReady')) is not bool:
            raise ValueError('Missing native clock readiness')
        if not isinstance(row.get('peerRole'), str) or not isinstance(row.get('packetTypeName'), str):
            raise ValueError('Missing native packet route/type')
        body(row)
    for row in traces.get('client2', []):
        if (row.get('event') == 'draw-consumed' and row.get('part') == 'body'
                and row.get('key') == 'ToolkitCartPose' and row.get('nativeInputVersion') is not None):
            nonce = process(row)
            if processes['client2'] and nonce not in processes['client2']:
                raise ValueError('Native snapshot process changed')
            processes['client2'].add(nonce)
    if any(len(values) != 1 for values in processes.values()):
        raise ValueError('Multiple native process epochs in one role trace')
    if len({value for values in processes.values() for value in values}) != len(processes):
        raise ValueError('Native process epoch reused across roles')

    sets, writes, terminals, ingresses, parses, accepted = {}, {}, {}, {}, {}, {}
    unmatched = Counter()
    acceptance_occurrences = 0

    def send_key(role, row):
        return role, process(row), row['connectionEpoch'], row['sendGeneration']

    def receive_key(role, row):
        return role, process(row), row['connectionEpoch'], row['receiveGeneration']

    def sample_key(row):
        return process(row), row['actorEpoch'], row['sourceSetGeneration']

    def scope(row):
        return process(row), row['actorEpoch'], row['connectionEpoch']

    def index(table, key, row, label):
        if key in table:
            raise ValueError('Duplicate native ' + label)
        table[key] = row

    def same(left, right, fields, label):
        if any(left.get(field) != right.get(field) for field in fields):
            raise ValueError(label)

    identity = ('peerRole', 'packetType', 'packetTypeName', 'packetBodyHex', 'packetSha256',
                'packetBytes', 'packetByteOrder', 'actorEpoch', 'ownerID')
    for role, row in events:
        event = row['event']
        if event == 'player-source-set':
            if role != 'client1' or not row['sourceSetGeneration']:
                raise ValueError('Invalid native source role/generation')
            begin = integer(row, 'sourceSampleBeginNs', -(1 << 63))
            end = integer(row, 'sourceSampleEndNs', -(1 << 63))
            if end < begin or end > row['monoNs']:
                raise ValueError('Native source sample interval regressed')
            index(sets, sample_key(row), row, 'source generation')
        elif event == 'player-write':
            if row['sendGeneration'] and row['connectionEpoch']:
                index(writes, send_key(role, row), row, 'write generation')
            else:
                unmatched['write-without-send-scope'] += 1
        elif event in ('player-submit', 'player-cancel'):
            if not row['sendGeneration'] or not row['connectionEpoch']:
                raise ValueError('Native terminal has no send scope')
            index(terminals, send_key(role, row), row, 'send terminal')
        elif event == 'player-ingress':
            if not row['ingressGeneration'] or not row['connectionEpoch']:
                raise ValueError('Native ingress has no connection scope')
            index(ingresses, (role, process(row), row['connectionEpoch'], row['ingressGeneration']), row, 'ingress generation')
        elif event == 'player-parse':
            if not row['receiveGeneration'] or not row['connectionEpoch']:
                unmatched['parse-without-receive-scope'] += 1
            else:
                index(parses, receive_key(role, row), row, 'receive generation')
        elif event == 'player-accepted':
            if not row['receiveGeneration'] or not row['connectionEpoch']:
                raise ValueError('Native accepted input has no receive scope')
            acceptance_occurrences += 1
            key = receive_key(role, row)
            previous = accepted.get(key)
            if previous is not None:
                same(row, previous, identity + ('ingressGeneration', 'ingressMonoNs'),
                     'Native repeated acceptance changed receipt identity')
            if previous is None or row['monoNs'] < previous['monoNs']:
                accepted[key] = row
    submitted, cancelled = {}, 0
    for key, terminal in terminals.items():
        write = writes.get(key)
        if write is None:
            raise ValueError('Native terminal without exact write')
        same(terminal, write, identity + ('sourceSetGeneration', 'serverReceiveGeneration',
             'sourceSampleBeginNs', 'sourceSampleEndNs'), 'Native send scope changed after serialization')
        if terminal['monoNs'] < write['monoNs']:
            raise ValueError('Native terminal predates write')
        if terminal['event'] == 'player-submit':
            if terminal.get('submissionFailed'):
                raise ValueError('Failed native send marked submitted')
            submitted[key] = write
        else:
            cancelled += 1
    unmatched['write-without-terminal'] = len(set(writes)-set(terminals))
    for key, row in parses.items():
        ingress = ingresses.get((*key[:3], row['ingressGeneration']))
        if ingress is None:
            unmatched['parse-without-observed-ingress'] += 1
        else:
            same(row, ingress, identity + ('ingressMonoNs',), 'Native parse differs from exact ingress')
            if row['monoNs'] < ingress['monoNs']:
                raise ValueError('Native parse predates ingress')
    for key, row in accepted.items():
        parsed = parses.get(key)
        if parsed is None:
            unmatched['accepted-without-observed-parse'] += 1
            continue
        same(row, parsed, identity + ('ingressGeneration', 'ingressMonoNs'),
             'Native accepted input differs from parsed receipt')
        if row['monoNs'] < parsed['monoNs']:
            raise ValueError('Native acceptance predates parse')

    # Across processes there is no shared connection or actor ordinal. Candidates must
    # follow the exact directed fixture role route; conflicting local epochs stay
    # ambiguous rather than being selected by clocks, sequence or event proximity.
    source_by_body = defaultdict(dict)
    source_transmissions = defaultdict(list)
    unknown_sources = Counter()
    observer_by_body = defaultdict(list)
    server_receives = {}
    observer_scopes = defaultdict(set)

    def matchable(row):
        return row['packetType'] >= 0 and row['packetTypeName'] not in ('', 'unavailable')

    for (role, nonce, connection, generation), row in parses.items():
        if role == 'server' and row['peerRole'] == 'client1' and matchable(row):
            index(server_receives, (nonce, generation), row, 'server receive ID')
        elif role == 'client2' and row['peerRole'] == 'server' and matchable(row):
            observer_scopes[body(row)].add(scope(row))
    for (role, nonce, connection, generation), row in submitted.items():
        if role != 'client1' or row['peerRole'] != 'server' or not matchable(row):
            continue
        exact = body(row)
        source_transmissions[exact].append(row)
        key = sample_key(row)
        source = sets.get(key)
        if source is None:
            unmatched['submitted-without-source-set'] += 1
            unknown_sources[exact] += 1
            continue
        same(source, row, ('ownerID', 'sourceSampleBeginNs', 'sourceSampleEndNs'),
             'Native source/write identity changed')
        if source['monoNs'] > row['monoNs']:
            raise ValueError('Native source/write association regressed')
        source_by_body[exact][key] = source
    for (role, nonce, connection, generation), row in submitted.items():
        if role != 'server' or row['peerRole'] != 'client2' or not matchable(row):
            continue
        parent = server_receives.get((nonce, row['serverReceiveGeneration']))
        if parent is None:
            unmatched['fanout-without-source-receipt'] += 1
            continue
        if row['actorEpoch'] != parent['actorEpoch'] or row['ownerID'] != parent['ownerID']:
            raise ValueError('Native fanout actor differs from parent receipt')
        if body(row) != body(parent) or row['packetTypeName'] != parent['packetTypeName']:
            unmatched['server-forward-body-changed'] += 1
            continue
        if row['monoNs'] < parent['monoNs']:
            raise ValueError('Native fanout predates receipt')
        observer_by_body[body(row)].append((row, parent))

    receipts, matches, counts = {}, [], Counter()
    for key, row in parses.items():
        if key[0] != 'client2':
            continue
        exact = body(row)
        routes = observer_by_body.get(exact, []) if row['peerRole'] == 'server' and matchable(row) else []
        # A type name is checked as well as its wire ID; -1/unavailable never joins.
        routes = [(send, parent) for send, parent in routes if send['packetTypeName'] == row['packetTypeName']]
        sources = source_by_body.get(exact, {}) if routes else {}
        transmissions = source_transmissions.get(exact, []) if routes else []
        scopes = [set(scope(send) for send in transmissions),
                  set(scope(parent) for _, parent in routes),
                  set(scope(send) for send, _ in routes), observer_scopes.get(exact, set())]
        ambiguous_route = bool(routes) and any(len(values) > 1 for values in scopes)
        if ambiguous_route:
            status = 'ambiguous-route'
        elif routes and unknown_sources[exact]:
            status = 'incomplete-source-evidence'
        else:
            status = 'unique-observed-source' if len(sources) == 1 else 'ambiguous-source' if sources else 'unmatched'
        counts[status] += 1
        receipts[key] = (row, sources, routes, status)
        matches.append(dict(receiveGeneration=row['receiveGeneration'], connectionEpoch=row['connectionEpoch'],
            status=status, sourceGenerations=[dict(processEpoch=k[0], actorEpoch=k[1], generation=k[2]) for k in sorted(sources)],
            sourceTransmissionOccurrences=len(transmissions),
            missingSourceOccurrences=unknown_sources[exact] if routes else 0,
            serverTransmissionOccurrences=len(routes), serverReceiveGenerations=sorted({parent['receiveGeneration'] for _, parent in routes})))

    point_ages, local_ages = [], []
    captures, snapshot_counts = set(), Counter()
    snapshots = []
    for row in traces.get('client2', []):
        if row.get('event') != 'draw-consumed' or row.get('part') != 'body' or row.get('key') != 'ToolkitCartPose':
            continue
        if row.get('nativeInputVersion') is None:
            snapshot_counts['missing-input-metadata'] += 1
            continue
        if type(row.get('nativeInputVersion')) is not int or row['nativeInputVersion'] != 1:
            raise ValueError('Unknown native input version')
        capture = (integer(row, 'captureId', 1), integer(row, 'slotToken', -(1 << 63)))
        if capture in captures:
            raise ValueError('Duplicate native body capture')
        captures.add(capture)
        generation = integer(row, 'nativeReceiveGeneration')
        connection = integer(row, 'nativeConnectionEpoch')
        actor = integer(row, 'nativeActorEpoch', 1)
        ingress = integer(row, 'nativeIngressGeneration')
        nonce = process(row)
        if nonce not in processes['client2']:
            raise ValueError('Native snapshot process changed')
        if not generation:
            if connection or ingress or row.get('nativePacketSha256') != '':
                raise ValueError('Empty frozen native snapshot has receipt metadata')
            snapshot_counts['no-accepted-native-input'] += 1
            continue
        key = 'client2', nonce, connection, generation
        item = receipts.get(key)
        acceptance = accepted.get(key)
        if item is None or acceptance is None:
            snapshot_counts['missing-accepted-receipt'] += 1
            continue
        parsed, sources, routes, status = item
        if actor != parsed['actorEpoch'] or row.get('nativePacketSha256') != parsed['packetSha256']:
            raise ValueError('Frozen native snapshot identity changed')
        if ingress != parsed['ingressGeneration']:
            raise ValueError('Frozen native ingress generation changed')
        if acceptance['monoNs'] > integer(row, 'nativeMonoNs', -(1 << 63)):
            raise ValueError('Native input accepted after original slot capture')
        snapshot_counts[status] += 1
        local_age = (integer(row, 'monoNs', -(1 << 63))-parsed['monoNs'])/1e6
        if local_age < 0:
            raise ValueError('Native draw predates receipt')
        local_ages.append(local_age)
        if type(row.get('clockReady')) is not bool:
            raise ValueError('Missing native snapshot clock readiness')
        integer(row, 'serverNs', -(1 << 63))
        age_points = [(row['serverNs']-source['serverNs'])/1e6 for source in sources.values()
                      if row['clockReady'] and source['clockReady']]
        snapshot = dict(captureId=capture[0], status=status, receiveGeneration=generation,
                        sourceGenerationCount=len(sources), receiptToDrawMs=local_age,
                        sourceClockStatus='point-estimate-only' if age_points else 'unavailable')
        if age_points:
            snapshot['sourceSetEventToDrawPointEstimateRangeMs'] = [min(age_points), max(age_points)]
        else:
            snapshot_counts['source-clock-unavailable'] += 1
        if status == 'unique-observed-source' and len(age_points) == 1:
            # Negative estimates diagnose inadequate clocks; never clip or call them latency.
            point_ages.append(age_points[0])
            if age_points[0] < 0:
                snapshot_counts['negative-source-point-estimate'] += 1
        snapshots.append(snapshot)

    def stats(values):
        if not values:
            return dict(count=0)
        values = sorted(values)
        def q(p):
            at = (len(values)-1)*p
            lo = int(at)
            hi = min(lo+1, len(values)-1)
            return values[lo]+(values[hi]-values[lo])*(at-lo)
        return dict(count=len(values), minimum=values[0], p50=q(.5), p95=q(.95), p99=q(.99), maximum=values[-1])
    return dict(available=True, schema=1, diagnosticOnly=True,
        processEpochs={role: next(iter(values)) for role, values in processes.items()},
        sourceSetGenerations=len(sets), preparedWrites=len(writes), submittedWrites=len(submitted), cancelledWrites=cancelled,
        receivedGenerations=len(parses), acceptedGenerations=len(accepted), acceptanceOccurrences=acceptance_occurrences, unmatched=dict(unmatched),
        observerReceipts=dict(counts), observerBodySnapshots=dict(snapshot_counts),
        sourceSetEventToDrawPointEstimateMs=stats(point_ages), receiptToDrawMs=stats(local_ages),
        receiptAssociations=matches, snapshotAssociations=snapshots, limitations=LIMITS)
