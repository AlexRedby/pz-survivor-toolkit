"""Read-only native cart timing baseline; never certifies playback/image equivalence."""
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path

ROLES = ('server', 'client1', 'client2')
KEYS = ('ToolkitCartPose', 'ToolkitCartActionPose')
EVENTS = {'publish', 'variable-write', 'variable-parse', 'variable-process-client',
          'variable-process-server-enter', 'variable-process-server-exit', 'player-write',
          'player-parse', 'prediction-update', 'animation-update', 'capture-prepared',
          'draw-consumed', 'transport-stats', 'clock-sync', 'clock-request', 'clock-experiment-request', 'player-source-set', 'player-submit',
          'player-cancel', 'player-ingress', 'player-accepted', 'trace-end'}


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate JSON key: ' + key)
        result[key] = value
    return result


def integer(row, key, minimum=None):
    value = row.get(key)
    if type(value) is not int or minimum is not None and value < minimum:
        raise ValueError('Invalid integer ' + key)
    return value


def finite(value):
    if isinstance(value, dict):
        for item in value.values(): finite(item)
    elif isinstance(value, list):
        for item in value: finite(item)
    elif type(value) is float and not math.isfinite(value):
        raise ValueError('Nonfinite trace value')


def identity(row):
    key = row.get('key')
    if key is None: return None
    if key not in KEYS: raise ValueError('Unknown pose key')
    if row.get('shapeError'): raise ValueError('Native pose shape guard failed')
    raw = row.get('raw')
    if raw is None or raw == '':
        if row.get('clear') is not True: raise ValueError('Unmarked clear')
        return None
    if not isinstance(raw, str) or len(raw) > 300: raise ValueError('Unbounded pose value')
    parts = raw.split(','); motion = key == KEYS[0]
    if len(parts) != (13 if motion else 14) or parts[0] != '1': raise ValueError('Pose shape changed')
    cart, serial = int(parts[1 if motion else 2]), int(parts[2 if motion else 1])
    generation = None if motion else int(parts[3])
    if serial <= 0 or integer(row,'cartID') != cart or integer(row,'serial',1) != serial:
        raise ValueError('Pose identity mismatch')
    if not motion and row.get('actionGeneration') != generation: raise ValueError('Action generation mismatch')
    if any(not math.isfinite(float(part)) for part in parts): raise ValueError('Nonfinite pose')
    return row['ownerID'], key, cart, generation, serial, raw


def distribution(values):
    if not values: return {'count': 0}
    values = sorted(values)
    def quantile(q):
        at = (len(values)-1)*q; a = int(at); b = min(a+1, len(values)-1)
        return values[a]+(values[b]-values[a])*(at-a)
    return dict(count=len(values), p50=quantile(.5), p95=quantile(.95), p99=quantile(.99), maximum=values[-1])


def read_trace(path, role):
    rows = []
    for line in path.read_text().splitlines():
        row = json.loads(line, object_pairs_hook=unique); finite(row)
        if row.get('schema') != 1 or row.get('actor') != role or row.get('event') not in EVENTS:
            raise ValueError('Trace schema/actor/event mismatch: ' + role)
        if integer(row, 'seq', 1) != len(rows)+1: raise ValueError('Missing/reordered local event sequence')
        integer(row, 'monoNs'); integer(row, 'serverNs'); integer(row, 'wallMs'); integer(row, 'ownerID', 0)
        if rows and row['monoNs'] < rows[-1]['monoNs']: raise ValueError('Monotonic clock regressed')
        if type(row.get('clockReady')) is not bool: raise ValueError('Missing clock readiness')
        if row['clockReady'] and row['serverNs'] == 0: raise ValueError('Ready clock is zero')
        if row.get('failed') is True: raise ValueError('Trace writer failed')
        identity(row)
        rows.append(row)
    if not rows: raise ValueError('Empty trace: ' + role)
    if sum(row['event'] == 'trace-end' for row in rows) != 1 or rows[-1]['event'] != 'trace-end':
        raise ValueError('Trace did not close cleanly: ' + role)
    return rows


def clock_report(traces):
    reports = {}
    for role in ('client1','client2'):
        epochs = defaultdict(list); pending_dropped = 0
        for row in traces[role]:
            if row['event'] != 'clock-sync': continue
            t0=integer(row,'clientSendNs');server=integer(row,'serverPreparedNs');t1=integer(row,'clientProcessNs')
            before=integer(row,'offsetBeforeNs');after=integer(row,'offsetAfterNs');observed=integer(row,'observedMonoNs')
            if t1<t0 or observed<t1 or observed>row['monoNs']: raise ValueError('Invalid TimeSync observation ordering')
            if any(type(row.get(field)) is not bool for field in ('readyBefore','readyAfter','pendingBeforeOwner')):
                raise ValueError('Invalid TimeSync readiness/binding flags')
            guid=row.get('connectionGUID');token=integer(row,'connectionToken')
            if not isinstance(guid,str) or not guid: raise ValueError('Missing TimeSync connection identity')
            dropped=integer(row,'pendingDroppedCount',0);pending_dropped=max(pending_dropped,dropped)
            lower,upper=server-t1,server-t0
            midpoint=lower+(t1-t0)//2
            epochs[guid,token].append(dict(clientSendNs=t0,serverPreparedNs=server,clientProcessNs=t1,observedMonoNs=observed,
                rttMs=(t1-t0)/1e6,offsetLowerNs=lower,offsetUpperNs=upper,midpointOffsetNs=midpoint,
                midpointRadiusMs=(t1-t0)/2e6,appliedBeforeNs=before,appliedAfterNs=after,
                appliedCorrectionMs=(after-before)/1e6,filteredMinusMidpointMs=(after-midpoint)/1e6,
                filteredDistanceOutsideExchangeIntervalMs=max(lower-after,after-upper,0)/1e6,
                readyBefore=row['readyBefore'],readyAfter=row['readyAfter'],pendingBeforeOwner=row['pendingBeforeOwner']))
        reports[role]=dict(samples=sum(map(len,epochs.values())),pendingDroppedCount=pending_dropped,
            preOwnerHandshakeCaptured=any(row['pendingBeforeOwner'] for rows in epochs.values() for row in rows),
            startupCoverage='Unknown; bounded pending retention does not prove the first native exchange was captured',
            connectionEpochs=[dict(connectionGUID=guid,connectionToken=token,exchanges=rows,
                rttMs=distribution([row['rttMs'] for row in rows]),
                absoluteFilteredMinusMidpointMs=distribution([abs(row['filteredMinusMidpointMs']) for row in rows]))
                for (guid,token),rows in epochs.items()])
    return dict(roles=reports,conditionalOffsetModel='theta=S-C lies in [s-t1,s-t0] for this matched exchange only',
        assumptions=['Echoed request and server reply belong to the same native connection/process epoch.',
                     'Server response-preparation timestamp is causally between client request preparation and response processing.',
                     'Relative clock offset/rate is constant during this exchange; no cross-machine drift bound has been established.'],
        qualification='RTT includes preparation, queues and client processing. Native readiness/10ms correction threshold is not a clock accuracy bound. Filter lag is reported separately.',
        eventTimeOffsetBounds='Unknown between exchanges without a justified clock drift/stability allowance; publication ages remain point estimates.')



def active_motion(root, selection, traces, owners):
    options=selection.get('options', {})
    if options.get('cart_inventory_equip') is True:
        return dict(available=False,reason='Inventory-equip retains the whole-capture scope; its action window is separate')
    if 'cart_wall_exit' in options:
        return dict(available=False,reason='Wall bank is outside the ordinary 15/26-second motion contract')
    if type(options.get('cart_fast_motion',False)) is not bool:
        raise ValueError('cart_fast_motion must be a frozen boolean')
    reports=sorted((root/'analysis').glob('*/mp-comparison.json'))
    if (root/'analysis/mp-comparison.json').is_file(): reports.insert(0,root/'analysis/mp-comparison.json')
    canonical=[]
    for path in reports:
        report=json.loads(path.read_text(),object_pairs_hook=unique);finite(report)
        if report.get('evidenceComplete') is not True: raise ValueError('Incomplete canonical motion comparison')
        canonical.append((path,report))
    if canonical:
        descriptors={(integer(report,'epoch',0),integer(report,'ownerOnlineID',0),integer(report,'cartID')) for _,report in canonical}
        if len(descriptors)!=1: raise ValueError('Conflicting canonical motion comparisons')
        epoch,owner,cart=next(iter(descriptors));epoch_source=str(canonical[0][0].relative_to(root))
    else:
        # The adapter invokes this before writing mp-comparison.json on a fresh
        # capture. Reuse the existing strict analyzer rather than guessing an epoch.
        import runpy
        try: report=runpy.run_path(str(Path(__file__).with_name('analyze.py')))['analyze'](root)
        except (OSError,ValueError,KeyError) as error:
            return dict(available=False,reason='Canonical motion evidence unavailable: '+str(error))
        epoch=integer(report,'epoch',0);owner=integer(report,'ownerOnlineID',0);cart=integer(report,'cartID')
        epoch_source='analyze.py:analyze(profile)'
    if owners!={owner}: raise ValueError('Canonical motion owner differs from timeline')
    duration=26000 if options.get('cart_fast_motion',False) else 15000
    end=epoch+duration
    writes={};counter_groups=defaultdict(list)
    for role,rows in traces.items():
        for row in rows:
            if not epoch<=row['wallMs']<=end: continue
            if row['event']=='variable-write' and row.get('key') in KEYS:
                group=writes.setdefault((role,row['key']),dict(actor=role,key=row['key'],writes=0,serializedBytes=0,
                    clearWrites=0,foreignCartWritesExcluded=0,identities=set(),repeatedIdentityWrites=0))
                key=identity(row)
                if key and row['cartID']!=cart: group['foreignCartWritesExcluded']+=1;continue
                group['writes']+=1;group['serializedBytes']+=integer(row,'serializedBytes',0)
                if not key: group['clearWrites']+=1
                elif key in group['identities']: group['repeatedIdentityWrites']+=1
                else: group['identities'].add(key)
            if row['event']=='transport-stats': counter_groups[role,row['connectionGUID'],row['endpoint']].append(row)
    serialized=[]
    for group in writes.values():
        group['uniquePayloadIdentities']=len(group.pop('identities'));group['serializedBytesPerSelectedSecond']=group['serializedBytes']/(duration/1000)
        serialized.append(group)
    transport=[]
    all_connections={(role,row['connectionGUID'],row['endpoint']) for role,rows in traces.items() for row in rows if row['event']=='transport-stats'}
    for role,guid,endpoint in sorted(all_connections):
        rows=counter_groups[role,guid,endpoint];available=[row for row in rows if row['available']]
        item=dict(actor=role,connectionGUID=guid,endpoint=endpoint,samplesInsideWindow=len(rows),availableSamplesInsideWindow=len(available),
            scope='owned-connection-all-native-traffic',headerCoverage='unverified',interpolated=False,extrapolated=False,
            sampledWallSpanMs=0,coverageFraction=0)
        if available:
            first,last=available[0],available[-1]
            item.update(firstSampleWallMs=first['wallMs'],lastSampleWallMs=last['wallMs'],
                uncoveredStartMs=first['wallMs']-epoch,uncoveredEndMs=end-last['wallMs'],
                sampledWallSpanMs=last['wallMs']-first['wallMs'],coverageFraction=(last['wallMs']-first['wallMs'])/duration)
        else: item.update(uncoveredStartMs=None,uncoveredEndMs=None,uncoveredTotalMs=duration)
        if len(available)>=2:
            first,last=available[0],available[-1];seconds=(last['monoNs']-first['monoNs'])/1e9
            if seconds<=0: raise ValueError('Active transport interval is not positive')
            item['sampledMonotonicSeconds']=seconds
            for field in ('nativeActualBytesSent','nativeActualBytesReceived','userBytesResent'):
                delta=last[field]-first[field]
                if delta<0: raise ValueError('Active connection counters reset')
                item[field+'Delta']=delta;item[field+'PerSampledSecond']=delta/seconds
            item['maximumObservedResendBufferBytes']=max(row['resendBufferBytes'] for row in available)
        else: item['deltaUnavailableReason']='Fewer than two available actual counter samples inside the selected window'
        transport.append(item)
    return dict(available=True,startWallMs=epoch,endWallMs=end,durationMs=duration,epochSource=epoch_source,
        windowClock='Canonical fixture wall epoch and recorded wallMs; boundaries are inclusive',
        cartID=cart,serializedCartWrites=serialized,nativeConnectionTraffic=transport,
        qualifications=['Serialization counts include cached repeated writes and server relay/fanout serialization; they are not new source publications or wire transmissions.',
                        'Write hooks do not record recipients, so server fanout and cached repeats cannot be assigned to individual destinations.',
                        'Counter deltas cover only first-to-last actual available samples inside the window; uncovered edges are excluded, never interpolated or extrapolated.',
                        'Native counters include all connection traffic; IP/UDP header coverage is unverified and no cart-only wire budget is inferred.',
                        'Post-motion action banks are excluded from the selected 15/26-second window.'])


def analyze(root):
    root = Path(root)
    selection = json.loads((root/'selection.json').read_text(), object_pairs_hook=unique)
    if (selection.get('suite') not in ('wooden_cart_multiplayer', 'cart_motion_mp')
            or selection.get('kind') != 'mp' or selection.get('mode') != 'toolkit'
            or selection.get('options', {}).get('cart_timeline') is not True):
        raise ValueError('Explicit MP cart_timeline selection required')
    paths = {role: root/role/'cart-timeline.jsonl' for role in ROLES}
    paths['server'] = root/('client1' if selection.get('options', {}).get('mp_host') is True else 'server')/'cart-timeline-server.jsonl'
    traces = {role: read_trace(paths[role], role) for role in ROLES}
    for role in ROLES:
        for path in (root/(role+'-launch.log'), root/role/'console.txt'):
            if path.is_file() and '[CART_TIMELINE] ERROR' in path.read_text(errors='replace'):
                raise ValueError('Timeline diagnostic error: ' + role)
    owners = {row['ownerID'] for rows in traces.values() for row in rows}
    if len(owners) != 1: raise ValueError('Multiple owner identities')
    counts = {role: dict(Counter(row['event'] for row in rows)) for role, rows in traces.items()}
    required = {'server': ('variable-process-server-enter', 'variable-write', 'variable-process-server-exit', 'transport-stats'),
                'client1': ('publish', 'variable-write', 'player-write', 'capture-prepared', 'draw-consumed', 'transport-stats', 'clock-sync'),
                'client2': ('variable-parse', 'variable-process-client', 'player-parse', 'prediction-update',
                            'animation-update', 'capture-prepared', 'draw-consumed', 'transport-stats', 'clock-sync')}
    missing = {role: [event for event in events if not counts[role].get(event)] for role, events in required.items()}
    source = defaultdict(list)
    for row in traces['client1']:
        if row['event'] == 'publish' and (key := identity(row)): source[key].append(row)
    ambiguous = {key for key, rows in source.items() if len(rows) != 1}
    durations = defaultdict(list); unaligned = Counter(); unmatched = Counter(); prepared = {}
    receipts = {}; stats = defaultdict(list)
    first_observed=set();repeat_observations=Counter();first_skipped=Counter()
    for role, rows in traces.items():
        for row in rows:
            event = row['event']; key = identity(row)
            if event == 'transport-stats':
                if row.get('scope') != 'owned-connection-all-native-traffic' or row.get('headerCoverage') != 'unverified':
                    raise ValueError('Mislabelled transport scope')
                if type(row.get('available')) is not bool: raise ValueError('Missing counter availability')
                if row['available']:
                    for field in ('nativeActualBytesSent','nativeActualBytesReceived','userBytesResent',
                                  'resendBufferBytes','resendBufferMessages'): integer(row, field, 0)
                stats[role, row['connectionGUID'], row['endpoint']].append(row)
            if key and event == 'variable-process-client': receipts[role, key] = row
            if key and event in ('variable-write','variable-parse','variable-process-client','variable-process-server-enter',
                                 'variable-process-server-exit','draw-consumed'):
                stage=role+'/'+event+'/'+row['key']+('/'+row['part'] if event=='draw-consumed' else '')
                observed=(stage,key);first=observed not in first_observed
                first_observed.add(observed)
                if not first: repeat_observations[stage]+=1
                metric=stage+'/allObservationPublicationAgeMs'
                reason=None
                if key in ambiguous: unmatched['ambiguous-publication']+=1;reason='ambiguous-publication'
                elif key not in source: unmatched['missing-publication']+=1;reason='missing-publication'
                else:
                    origin=source[key][0]
                    if not origin['clockReady'] or not row['clockReady']: unaligned[metric]+=1;reason='clock-not-ready'
                    elif row['serverNs']<origin['serverNs']: unaligned['negative-clock-difference']+=1;reason='negative-clock-difference'
                    else:
                        age=(row['serverNs']-origin['serverNs'])/1e6
                        durations[metric].append(age)
                        if first: durations[stage+'/firstDeliveryPublicationAgeMs'].append(age)
                if first and reason: first_skipped[stage+'/'+reason]+=1
            if event in ('capture-prepared','draw-consumed'):
                token = role, integer(row, 'captureId', 1), integer(row, 'slotToken'), row.get('key')
                integer(row, 'nativeMonoNs'); integer(row, 'nativeServerNs')
                integer(row, 'preparedPrimary'); integer(row, 'preparedSecondary')
                if row['nativeMonoNs'] > row['monoNs']: raise ValueError('Original native capture is in the future')
                if type(row.get('nativeClockReady')) is not bool: raise ValueError('Missing original capture readiness')
                if event == 'capture-prepared':
                    if token in prepared: raise ValueError('Duplicate prepared capture')
                    prepared[token] = row, set(), receipts.get((role, key)) if key else None
                else:
                    if token not in prepared: raise ValueError('Draw has no exact prepared capture')
                    capture, parts, receipt = prepared[token]; part = row.get('part')
                    if part not in ('body','cart') or part in parts: raise ValueError('Duplicate/invalid consumed part')
                    for field in ('raw','preparedPrimary','preparedSecondary','nativeMonoNs','nativeServerNs','nativeClockReady',
                                  'nativeInputVersion','nativeProcessEpoch','nativeActorEpoch','nativeReceiveGeneration',
                                  'nativeConnectionEpoch','nativeIngressGeneration','nativePacketSha256'):
                        if row.get(field) != capture.get(field): raise ValueError('Draw identity advanced after preparation')
                    if row['monoNs'] < capture['monoNs']: raise ValueError('Draw predates preparation')
                    parts.add(part)
                    durations[role+'/prepareToDrawMs'].append((row['monoNs']-capture['monoNs'])/1e6)
                    durations[role+'/nativeCaptureToDrawMs'].append((row['monoNs']-row['nativeMonoNs'])/1e6)
                    if receipt: durations[role+'/receiptToDrawMs'].append((row['monoNs']-receipt['monoNs'])/1e6)
    transport = []
    for (role, guid, endpoint), rows in stats.items():
        available = [row for row in rows if row['available']]
        item = dict(actor=role, connectionGUID=guid, endpoint=endpoint, connectionType=rows[-1].get('connectionType','unknown'),
                    samples=len(rows), availableSamples=len(available))
        if len(available) >= 2:
            first, last = available[0], available[-1]; seconds = (last['monoNs']-first['monoNs'])/1e9
            if seconds <= 0: raise ValueError('Transport sample interval is not positive')
            item['windowSeconds'] = seconds
            for field in ('nativeActualBytesSent','nativeActualBytesReceived','userBytesResent'):
                delta = last[field]-first[field]
                if delta < 0: raise ValueError('Connection counters reset within trace')
                item[field+'Delta'] = delta; item[field+'PerSecond'] = delta/seconds
            item['maximumResendBufferBytes'] = max(row['resendBufferBytes'] for row in available)
        transport.append(item)
    cadence = {}
    for role, rows in traces.items():
        for event in ('publish','variable-process-client','player-write','player-parse'):
            groups = defaultdict(list)
            for row in rows:
                if row['event'] == event: groups[row.get('key','native-player')].append(row['monoNs'])
            for key, times in groups.items(): cadence[role+'/'+event+'/'+key+'/intervalMs'] = distribution([(b-a)/1e6 for a,b in zip(times,times[1:])])
    import runpy
    clock_requests=runpy.run_path(str(Path(__file__).with_name('clock_time.py')))['request_report'](traces,selection.get('options',{}).get('cart_time_alignment') is True)
    native_report=runpy.run_path(str(Path(__file__).with_name('native_packet_time.py')))['native_packet_report'](traces)
    return dict(schema=1, diagnosticOnly=True, traceComplete=True, ownerID=next(iter(owners)), events=counts,
        sourceFiles={role:str(path.relative_to(root)) for role,path in paths.items()},
        missingStages=missing, baselineStagesObserved=not any(missing.values()), nativePackets=native_report,
        clocks=dict(unsynchronizedEvents=sum(not row['clockReady'] for rows in traces.values() for row in rows),
                    skippedDifferences=dict(unaligned), qualification='GameTime synchronized clock point estimates; exchange-specific uncertainty and filter lag are reported separately',
                    synchronization=clock_report(traces),requests=clock_requests),
        durationsMs={key:distribution(values) for key,values in sorted(durations.items())}, intervalsMs=cadence,
        ambiguousPublicationIdentities=len(ambiguous), unmatchedJoins=dict(unmatched),
        repeatedStageObservations=dict(repeat_observations),firstDeliverySkipped=dict(first_skipped),
        ageSemantics='First delivery is the first observed callback per exact unique publication identity and stage; all-observation ages include cached repeats and frozen rendered residency, not fresh network latency.',
        activeMotion=active_motion(root,selection,traces,owners),
        preparedWithoutBothDraws=sum(parts != {'body','cart'} for _,parts,_ in prepared.values()), transport=transport,
        limitations=['All-observation publication ages include repeated cached serialization/receipt; repeated callbacks are not fresh publications or measured network latency.',
                     'Publication age at draw is age of the frozen animation variable observed at preparation, not full image/prediction sample age.',
                     'PlayerPacket has no sample timestamp or unique sequence; native send/parse/update intervals do not establish a one-to-one packet or playback-time bridge.',
                     'Variable processServer boundaries plus writes observe the relay call, not network delivery or per-recipient acknowledgement.',
                     'Native RakNet actualBytes counters include all traffic on each owned connection; IP/UDP/header coverage is unverified; they are not cart-only wire bytes.',
                     'Repeated publication identity is ambiguous without a protocol epoch and is excluded from cross-process joins.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args(); report = analyze(args.profile)
    with args.output.open('x') as output: json.dump(report, output, indent=2, allow_nan=False)


if __name__ == '__main__': main()
