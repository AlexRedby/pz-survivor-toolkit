"""Native echoed-clock requests and explicitly bounded experiment qualification."""
from collections import Counter, defaultdict
import uuid


def number(row, key, minimum=0):
    value = row.get(key)
    if type(value) is not int or value < minimum: raise ValueError('Invalid clock request '+key)
    return value


def nonce(row):
    value = row.get('nativeProcessEpoch')
    try: uuid.UUID(value)
    except (ValueError, TypeError, AttributeError): raise ValueError('Invalid clock process epoch') from None
    return value


def request_report(traces, selected):
    roles = {}
    for role in ('client1', 'client2'):
        rows = traces[role]
        requests, ordinals, epochs = {}, set(), defaultdict(list)
        origins, replies, experiments = Counter(), Counter(), []
        maximum_dropped = 0
        maximum_reply_dropped = 0
        matched_keys = set()
        for row in rows:
            event = row['event']
            if event == 'clock-request':
                process = nonce(row)
                connection = number(row, 'connectionEpoch', 1)
                sent = number(row, 'clientSendNs', -(1 << 63))
                observed = number(row, 'observedMonoNs', -(1 << 63))
                ordinal = number(row, 'clockRequestOrdinal', 1)
                if not sent <= observed <= row['monoNs']: raise ValueError('Clock request observation ordering')
                origin = row.get('clockRequestOrigin')
                if origin not in ('native', 'fixture'): raise ValueError('Unknown clock request origin')
                if origin == 'fixture' and not selected: raise ValueError('Unselected fixture clock request')
                key = process, connection, sent
                if key in requests or (process, ordinal) in ordinals: raise ValueError('Duplicate clock request identity')
                if not isinstance(row.get('connectionGUID'), str) or not row['connectionGUID']:
                    raise ValueError('Missing native clock connection GUID')
                number(row, 'connectionToken', -(1 << 63))
                maximum_dropped = max(maximum_dropped, number(row, 'clockRequestDropped'))
                requests[key] = row;ordinals.add((process, ordinal));origins[origin] += 1
            elif event == 'clock-experiment-request':
                if not selected: raise ValueError('Unselected clock experiment')
                nonce(row);number(row, 'connectionEpoch', 1)
                if number(row, 'fixtureRequestCap') != 14: raise ValueError('Clock experiment cap changed')
                number(row, 'fixtureRequestOrdinal', 1)
                number(row, 'fixtureRequestMonoNs', -(1 << 63))
                elapsed = row.get('fixtureElapsedMs')
                if type(elapsed) not in (int, float) or not 0 <= elapsed <= 26000:
                    raise ValueError('Clock experiment escaped active bank')
                experiments.append(row)
        if experiments:
            if [row['fixtureRequestOrdinal'] for row in experiments] != list(range(1, len(experiments)+1)) or len(experiments) > 14:
                raise ValueError('Clock experiment ordinal/cap guard failed')
            if len({(row['nativeProcessEpoch'], row['connectionEpoch']) for row in experiments}) != 1:
                raise ValueError('Clock experiment continued after connection epoch change')
            times = [row['fixtureRequestMonoNs'] for row in experiments]
            if any(b-a < 2_000_000_000 for a, b in zip(times, times[1:])) or times[-1]-times[0] > 32_000_000_000:
                raise ValueError('Clock experiment spacing/deadline guard failed')
        fixture_requests = [row for row in requests.values() if row['clockRequestOrigin'] == 'fixture']
        if len(fixture_requests) > len(experiments): raise ValueError('Fixture clock request has no bounded experiment attempt')
        attempt_requests = set()
        for row in fixture_requests:
            ordinal = number(row, 'fixtureRequestOrdinal', 1)
            if ordinal > len(experiments) or ordinal in attempt_requests:
                raise ValueError('Clock request has no exact experiment attempt')
            attempt_requests.add(ordinal);attempt = experiments[ordinal-1]
            if (row['nativeProcessEpoch'], row['connectionEpoch']) != (attempt['nativeProcessEpoch'], attempt['connectionEpoch']):
                raise ValueError('Clock request changed experiment connection/process epoch')
            if row['clientSendNs'] < attempt['fixtureRequestMonoNs']:
                raise ValueError('Clock request predates its experiment attempt')
            if ordinal < len(experiments) and row['observedMonoNs'] > experiments[ordinal]['fixtureRequestMonoNs']:
                raise ValueError('Clock request escaped synchronous experiment attempt')
        prepared = sorted(row['clientSendNs'] for row in fixture_requests)
        if any(b-a < 2_000_000_000 for a,b in zip(prepared,prepared[1:])):
            raise ValueError('Fixture native request preparation spacing failed')
        for row in rows:
            if row['event'] != 'clock-sync': continue
            if 'pendingDroppedCount' in row: maximum_reply_dropped=max(maximum_reply_dropped,number(row,'pendingDroppedCount'))
            if 'clockRequestObserved' not in row:
                replies['legacy-unassociated'] += 1;continue
            process = nonce(row)
            if type(row['clockRequestObserved']) is not bool: raise ValueError('Invalid clock request binding flag')
            connection = number(row, 'clockRequestConnectionEpoch', 1)
            maximum_dropped = max(maximum_dropped, number(row, 'clockRequestDropped'))
            key = process, connection, number(row, 'clientSendNs', -(1 << 63))
            if row['clockRequestObserved']:
                request = requests.get(key)
                if request is None:
                    replies['request-record-missing'] += 1;continue
                for field in ('clockRequestOrdinal', 'clockRequestOrigin', 'connectionGUID', 'connectionToken'):
                    if row.get(field) != request.get(field): raise ValueError('Echoed clock request binding changed '+field)
                replies['matched-'+request['clockRequestOrigin']] += 1
                matched_keys.add(key)
                t0 = row['clientSendNs'];t1 = number(row, 'clientProcessNs', -(1 << 63))
                server = number(row, 'serverPreparedNs', -(1 << 63))
                if t1 < t0: raise ValueError('Clock reply predates request')
                epochs[process, connection].append(dict(processed=t1, lower=server-t1, upper=server-t0))
            else:
                if number(row, 'clockRequestOrdinal') != 0 or row.get('clockRequestOrigin') != 'unobserved':
                    raise ValueError('Unobserved clock request claims an identity')
                replies['unobserved-request'] += 1
        intervals = []
        for (process, connection), samples in epochs.items():
            samples.sort(key=lambda item: item['processed'])
            lower = max(item['lower'] for item in samples);upper = min(item['upper'] for item in samples)
            intervals.append(dict(processEpoch=process, connectionEpoch=connection, exchanges=len(samples),
                observedConstantOffsetCompatible=lower <= upper,
                sampledConstantOffsetIntersectionNs=[lower, upper] if lower <= upper else None,
                maximumObservedExchangeGapMs=max(((b['processed']-a['processed'])/1e6 for a,b in zip(samples,samples[1:])),default=None)))
        roles[role] = dict(requests=len(requests), requestOrigins=dict(origins), replies=dict(replies),
            fixtureAttempts=len(experiments), fixtureCap=14, droppedRequests=maximum_dropped,
            droppedReplies=maximum_reply_dropped, requestsWithoutObservedReply=len(set(requests)-matched_keys),
            observedRequestAssociationComplete=bool(requests) and bool(matched_keys) and set(requests)==matched_keys and not maximum_dropped and not maximum_reply_dropped
                and not any(replies[key] for key in ('legacy-unassociated','request-record-missing','unobserved-request')),
            sampledEpochCompatibility=intervals)
    return dict(experimentSelected=selected, roles=roles,
        trafficScope='Experiment adds only native TimeSync requests on owned clients, at most14 attempts per client, minimum2s spacing,32s deadline. Normal native retries remain separate and unsuppressed. No production cart payload/rate changes.',
        qualification='Exact echoed t0 plus process/connection epoch associates the exchange. Constant-offset compatibility at sampled exchanges is not an upper drift bound between them, a one-way latency measurement, or a source-image playback clock.')
