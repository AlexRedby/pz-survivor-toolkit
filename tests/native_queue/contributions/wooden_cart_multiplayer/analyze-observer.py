"""Exact diagnostic State revision/proxy/frozen-slot associations, never playback authority."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import runpy

ADMISSION = runpy.run_path(str(Path(__file__).with_name('analyze-action-admission.py')))
TIMELINE = runpy.run_path(str(Path(__file__).with_name('analyze-timeline.py')))
parse, require, integer, text, marked = (ADMISSION[key] for key in ('parse', 'require', 'integer', 'text', 'marked'))
uuid_text, equal, MAX = ADMISSION['uuid_text'], ADMISSION['identity_equal'], ADMISSION['MAX']
ROLES = ('server', 'client1', 'client2')
MARKER = '[CART_OBSERVER] '
EVENTS = {'source-begin', 'source-capture', 'source-end', 'state-set', 'state-write', 'state-submit', 'state-cancel',
          'state-parse', 'state-process-server', 'state-process-client', 'state-apply',
          'proxy-associate', 'proxy-stop', 'proxy-replaced', 'state-discard'}
SOURCE_FIELDS = ('sourceProcess', 'sourceActorEpoch', 'sourceConnectionEpoch', 'sourceNativeEpoch',
                 'sourceTableEpoch', 'sourceBeginGeneration')
LOCAL_FIELDS = ('process', 'owner', 'actorEpoch', 'sourceLife', 'stateTag', 'stateGeneration', 'packetEpoch',
                'ingressGeneration', 'receiveGeneration', 'stage')
BOOLS = ('diagnosticWire', 'proxyCurrent', 'associationValid', 'transportValidated', 'sourceValidated', 'success')
ORDINALS = ('actorEpoch', 'connectionEpoch', 'stateGeneration', 'packetEpoch', 'ingressGeneration',
            'receiveGeneration', 'sendGeneration', 'parentReceiveGeneration', 'proxyEpoch', 'applyGeneration')
SNAPSHOT = ('observerVersion', 'observerDiagnosticWire', 'observerProcess', 'observerSourceLife',
            'observerStateTag', 'observerStateGeneration', 'observerPacketEpoch', 'observerIngressGeneration',
            'observerReceiveGeneration', 'observerApplyGeneration', 'observerProxyEpoch', 'observerProxyState',
            'observerProxyCurrent', 'observerAssociationValid', 'observerReason')
SNAP_LINKS = dict(observerSourceLife='sourceLife', observerStateTag='stateTag',
                  observerStateGeneration='stateGeneration', observerPacketEpoch='packetEpoch',
                  observerIngressGeneration='ingressGeneration', observerReceiveGeneration='receiveGeneration',
                  observerApplyGeneration='applyGeneration', observerProxyEpoch='proxyEpoch')
FROZEN = SNAPSHOT + ('raw', 'preparedPrimary', 'preparedSecondary', 'nativeMonoNs', 'nativeServerNs',
                     'nativeClockReady', 'nativeInputVersion', 'nativeProcessEpoch', 'nativeActorEpoch',
                     'nativeReceiveGeneration', 'nativeConnectionEpoch', 'nativeIngressGeneration', 'nativePacketSha256')


def life(value, state=False):
    require(isinstance(value, str) and len(value) <= 240, 'Missing/bounded diagnostic source identity')
    fields = value.split('|')
    require(len(fields) == (8 if state else 7) and fields[0] == '1', 'Malformed diagnostic source identity')
    uuid_text({'process': fields[1]}, 'process')
    require(all(part.isascii() and part.isdigit() and not part.startswith('0') and 1 <= int(part) <= MAX
                for part in fields[2:]), 'Invalid diagnostic source ordinal')
    return (fields[1], *(int(part) for part in fields[2:]))


def row_check(row, role):
    require(isinstance(row, dict) and row.get('event') in EVENTS, 'Unknown/malformed observer event')
    require(type(row.get('protocol')) is int and row['protocol'] == 1 and row.get('role') == role,
            'Observer protocol/endpoint differs')
    uuid_text(row, 'process')
    require(all(type(row.get(key)) is bool for key in BOOLS) and row['diagnosticWire'],
            'Observer guards must be actual diagnostic booleans')
    integer(row, 'owner', -1, 32767)
    for key in ORDINALS:
        integer(row, key, 0, MAX)
    for key in ('bodyBegin', 'bodyEnd', 'packetBytes'):
        integer(row, key, 0, 2048+3)
    integer(row, 'monoNs', -(1 << 63), (1 << 63)-1)
    integer(row, 'wallMs', 0, MAX)
    require(row.get('stage') in ('Enter', 'Exit', 'Execute', 'unavailable')
            and row.get('proxyState') in ('active', 'stopped', 'replaced', 'unavailable')
            and row.get('peerRole') in (*ROLES, 'unavailable'), 'Unknown observer enum')
    text(row, 'reason', 160)
    values = life(row.get('sourceLife'))
    equal(dict(zip(SOURCE_FIELDS, values)), row, SOURCE_FIELDS, 'Source identity components differ')
    if row['event'].startswith('source-'):
        require(row['stateTag'] == '' and row['stateGeneration'] == 0 and row['packetEpoch'] == 0
                and row['stage'] == 'unavailable', 'Source lifecycle claims a packet revision')
    else:
        tag = life(row.get('stateTag'), True)
        require(row['stateTag'] == row['sourceLife']+'|'+str(row['stateGeneration'])
                and tag[:-1] == values and row['packetEpoch'] > 0, 'State marker differs from exact source revision')
    return row


def packet_key(row):
    return row['process'], row['packetEpoch'], row['receiveGeneration']


def successful(row):
    require(row['success'] is True, 'Failed native diagnostic operation')


def analyze(root):
    root = Path(root)
    selection = parse((root/'selection.json').read_text())
    options = selection.get('options', {})
    require(options.get('cart_observer_association') is True and options.get('cart_timeline') is True,
            'Explicit diagnostic observer association/timeline selection required')
    admission = ADMISSION['analyze'](root)
    require(admission.get('evidenceComplete') is True, 'Native admission prerequisite incomplete')
    logs = {role: (root/(role+'-launch.log')).read_text() for role in ROLES}
    rows = {role: marked(logs[role], MARKER) for role in ROLES}
    require(all(rows.values()), 'Missing diagnostic observer endpoint evidence')
    processes = {}
    by_event = {role: defaultdict(list) for role in ROLES}
    for role in ROLES:
        observed = set()
        for row in rows[role]:
            row_check(row, role); observed.add(row['process'])
            by_event[role][row['event']].append(row)
        require(len(observed) == 1, 'Observer process changed during selected bank')
        processes[role] = next(iter(observed))
    require(len(set(processes.values())) == 3, 'Observer endpoints reused process epoch')
    require(all(phase['process'] == processes['server'] for phase in admission['phases']),
            'Diagnostic relay belongs to another native admission process')
    accepted_rows = marked(logs['server'], ADMISSION['NATIVE_MARKER'])
    server_incarnations = {(row['actorEpoch'], row['connectionEpoch']) for row in accepted_rows if row['event'] == 'accepted'}
    owner_rows = marked(logs['client1'], ADMISSION['OWNER_MARKER'])
    queries = marked(logs['server'], ADMISSION['QUERY_MARKER'])
    owners = defaultdict(dict)
    for row in owner_rows:
        owners[row['index']][row['event']] = row
    phases, selected = [], {}
    for admitted in admission['phases']:
        index = admitted['index']; group = owners[index]
        capture = group['capture']; source = text(capture, 'observerSource', 240)
        parsed = life(source)
        require(parsed[0] == capture['ownerProcess'] == processes['client1'], 'Source marker belongs to foreign owner process')
        for event in ('query', 'reply'):
            equal(capture, group[event], ('observerSource',), 'Fresh owner query changed frozen observer source')
        server_queries = [row for row in queries if row['index'] == index]
        require(len(server_queries) == 1, 'Missing exact diagnostic server query')
        equal(capture, server_queries[0], ('observerSource',), 'Server query echoed a different observer source')
        require(source not in selected, 'Source lifetime reused across sealed action phases')
        selected[source] = index
        begins = [row for row in by_event['client1']['source-begin'] if row['sourceLife'] == source]
        require(len(begins) == 1, 'Missing/duplicate exact native source begin')
        begin = begins[0]; successful(begin)
        require(begin['owner'] == admitted['ownerID'] and begin['sourceValidated']
                and begin['process'] == begin['sourceProcess'] and begin['actorEpoch'] == parsed[1]
                and begin['connectionEpoch'] == parsed[2] and begin['reason'] == 'native-start-enter',
                'Native source begin lacks exact owner/incarnation proof')
        require(begin['wallMs'] <= capture['wallMs'], 'Source begin follows sealed owner capture')
        proofs = [row for row in by_event['client1']['source-capture'] if row['sourceLife'] == source]
        require(len(proofs) == 1, 'Missing/duplicate exact native source capture')
        proof = proofs[0]; successful(proof)
        equal(begin, proof, ('process', 'owner', 'actorEpoch', 'connectionEpoch', 'sourceLife')+SOURCE_FIELDS,
              'Source capture changed exact current native incarnation')
        require(proof['sourceValidated'] and proof['reason'] == 'exact-current-native'
                and begin['monoNs'] <= proof['monoNs'] and proof['wallMs'] <= capture['wallMs'],
                'Source capture lacks direct current native pointer proof')
        ends = [row for row in by_event['client1']['source-end'] if row['sourceLife'] == source]
        require(len(ends) <= 1, 'Duplicate source retirement')
        if ends:
            require(ends[0]['monoNs'] >= proof['monoNs'] and ends[0]['reason'] in
                    ('native-stop', 'native-perform', 'start-threw', 'source-restarted'), 'Source retirement predates capture or has unknown reason')
        phases.append(dict(index=index, phase=admitted['phase'], token=admitted['token'],
                           sourceLife=source, sourceBeginGeneration=parsed[-1], sourceEndReason=ends[0]['reason'] if ends else None,
                           ownerSealedOutcome=admitted['ownerSealedOutcome'],
                           ownerSealRevocationReason=admitted['ownerSealRevocationReason'],
                           stateRevisions=0, proxyAssociations=0, activeFrozenBodyCartPairs=0,
                           frozenCarryoverBodyCartPairs=0, sourceStateSetsBeforeSealedCapture=0))

    # Tags identify source State revisions. Repeated writes are a candidate set,
    # never a guessed transmission selected by nearest clocks or packet names.
    sets, parsed_packets, submissions = {}, {}, defaultdict(list)
    writes, terminals = {}, {}
    for role in ROLES:
        for row in by_event[role]['state-set']:
            if row['sourceLife'] not in selected: continue
            successful(row)
            require(role == 'client1' and row['process'] == row['sourceProcess'] and row['sourceValidated']
                    and row['receiveGeneration'] == row['ingressGeneration'] == 0
                    and row['actorEpoch'] == row['sourceActorEpoch']
                    and row['owner'] == admission['phases'][0]['ownerID'], 'Foreign/unvalidated source State set')
            require(row['stateTag'] not in sets, 'Duplicate source State revision')
            sets[row['stateTag']] = row
        for row in by_event[role]['state-parse']:
            if row['sourceLife'] not in selected: continue
            successful(row)
            require(role in ('server', 'client2') and row['receiveGeneration'] > 0
                    and row['ingressGeneration'] > 0 and row['connectionEpoch'] > 0
                    and row['transportValidated'], 'State parse lacks original ingress provenance')
            key = packet_key(row)
            require(key not in parsed_packets, 'Duplicate exact State parse revision')
            parsed_packets[key] = row
        for event in ('state-write', 'state-submit', 'state-cancel'):
            for row in by_event[role][event]:
                if row['sourceLife'] not in selected: continue
                require(row['sendGeneration'] > 0 and row['connectionEpoch'] > 0
                        and row['bodyBegin'] >= 3 and row['bodyEnd'] > row['bodyBegin']
                        and row['packetBytes'] == row['bodyEnd']-row['bodyBegin'] <= 2048,
                        'State send lacks bounded native body/submission identity')
                key = row['process'], row['sendGeneration']
                target = writes if event == 'state-write' else terminals
                require(key not in target, 'Duplicate State write/submission terminal')
                target[key] = row
    for key, write in writes.items():
        successful(write)
        require(key in terminals, 'State write has no submit/cancel terminal')
        terminal = terminals[key]
        equal(write, terminal, LOCAL_FIELDS+('connectionEpoch', 'peerRole', 'sendGeneration',
              'parentReceiveGeneration', 'bodyBegin', 'bodyEnd', 'packetBytes'), 'Submission changed exact native State write')
        require(terminal['monoNs'] >= write['monoNs'], 'Submission precedes State write')
        role = write['role']
        if role == 'client1':
            origin = sets.get(write['stateTag'])
            require(origin is not None, 'Native State write has no exact source set')
            equal(origin, write, LOCAL_FIELDS, 'Source State write changed exact revision')
            require(write['peerRole'] == 'server' and write['connectionEpoch'] == write['sourceConnectionEpoch']
                    and write['sourceValidated'] and write['transportValidated'] and terminal['transportValidated']
                    and write['parentReceiveGeneration'] == 0, 'Wrong owner State submission route')
        elif role == 'server':
            origin = parsed_packets.get(packet_key(write))
            require(origin is not None, 'Server relay lacks exact receive revision')
            equal(origin, write, LOCAL_FIELDS, 'Server relay changed parsed native State')
            require(write['parentReceiveGeneration'] == origin['receiveGeneration'] and write['sourceValidated']
                    and write['transportValidated'] and write['peerRole'] in ('client1', 'client2'),
                    'Server State relay lacks native source/parent/recipient proof')
        else:
            raise ValueError('Observer became a diagnostic source writer')
        if terminal['event'] == 'state-submit':
            successful(terminal)
            submissions[(role, write['peerRole'], write['stateTag'])].append(terminal)
    require(set(terminals) == set(writes), 'Submission terminal has no exact State write')

    for role in ('server', 'client2'):
        incarnations = {(row['actorEpoch'], row['connectionEpoch']) for row in parsed_packets.values() if row['role'] == role}
        require(len(incarnations) == 1, 'Ambiguous local native actor/connection incarnations')
        if role == 'server':
            require(incarnations == server_incarnations, 'Diagnostic State actor/source differs from admitted native incarnation')
    processes_by_packet = defaultdict(list)
    applies, proxies, boundaries, discards = {}, {}, defaultdict(list), set()
    for role in ('server', 'client2'):
        expected = 'state-process-server' if role == 'server' else 'state-process-client'
        require(not by_event[role]['state-process-client' if role == 'server' else 'state-process-server'],
                'Native State process event on wrong endpoint')
        for event in (expected, 'state-apply', 'proxy-associate', 'proxy-stop', 'proxy-replaced', 'state-discard'):
            for row in by_event[role][event]:
                if row['sourceLife'] not in selected: continue
                origin = parsed_packets.get(packet_key(row))
                require(origin is not None, 'Native process/apply/proxy lacks exact parse')
                equal(origin, row, LOCAL_FIELDS+('connectionEpoch',), 'Native State receipt identity changed before process/apply')
                require(row['monoNs'] >= origin['monoNs'], 'Native State operation predates original parse')
                if event == expected:
                    successful(row)
                    require(row['transportValidated'] and (role != 'server' or row['sourceValidated']),
                            'State processing lacks native transport/source guard')
                    processes_by_packet[packet_key(row)].append(row)
                elif event == 'state-apply':
                    successful(row)
                    require(role == 'client2' and row['applyGeneration'] > 0 and row['transportValidated'],
                            'State application lacks original transport/generation')
                    key = row['process'], row['applyGeneration']
                    require(key not in applies, 'Duplicate exact State apply generation')
                    applies[key] = row
                elif event == 'proxy-associate':
                    successful(row)
                    require(role == 'client2' and row['stage'] == 'Enter' and row['proxyState'] == 'active'
                            and row['proxyCurrent'] and row['transportValidated']
                            and row['proxyEpoch'] > 0 and row['applyGeneration'] > 0,
                            'Proxy association lacks scoped Enter/setAction proof')
                    key = row['process'], row['proxyEpoch']
                    require(key not in proxies, 'Proxy epoch reused by a later association')
                    proxies[key] = row
                elif event == 'state-discard':
                    discards.add(packet_key(row))
                elif event in ('proxy-stop', 'proxy-replaced'):
                    require(row['proxyEpoch'] > 0 and row['applyGeneration'] > 0
                            and row['proxyState'] == ('stopped' if event == 'proxy-stop' else 'replaced')
                            and row['associationValid'] is False, 'Retired proxy claims an active association')
                    boundaries[(row['process'], row['proxyEpoch'])].append(row)
    for key, origin in parsed_packets.items():
        require(origin['stateTag'] in sets, 'Parsed marker has no exact owner source State revision')
        require(origin['owner'] == sets[origin['stateTag']]['owner']
                and origin['stage'] == sets[origin['stateTag']]['stage'], 'Parsed marker moved to another native actor/stage')
        route = ('client1', 'server') if origin['role'] == 'server' else ('server', 'client2')
        require(origin['peerRole'] == route[0] and submissions[(*route, origin['stateTag'])],
                'Parsed State lacks successful directed diagnostic submission')
        require(processes_by_packet[key], 'Parsed State lacks successful native source/process validation')
    for key, proxy in proxies.items():
        apply = applies.get((proxy['process'], proxy['applyGeneration']))
        require(apply is not None, 'Proxy setAction has no completed exact State apply')
        require(packet_key(proxy) not in discards, 'Discarded State revision claims an applied proxy')
        require(apply['proxyEpoch'] == proxy['proxyEpoch'] and apply['proxyCurrent']
                and apply['associationValid'] and apply['proxyState'] == 'active',
                'Completed State apply does not validate exact current proxy')
        equal(proxy, apply, LOCAL_FIELDS+('connectionEpoch',), 'Proxy linked to a different native apply receipt')
        require(proxy['monoNs'] <= apply['monoNs'], 'Scoped proxy creation follows State apply exit')
        for boundary in boundaries[key]:
            equal(proxy, boundary, LOCAL_FIELDS+('connectionEpoch', 'proxyEpoch', 'applyGeneration'), 'Retired proxy changed original association')
            require(boundary['monoNs'] >= proxy['monoNs'], 'Proxy retirement precedes association')
    require(set(boundaries) <= set(proxies), 'Proxy retirement has no exact association')

    trace_path = root/'client2/cart-timeline.jsonl'
    trace = TIMELINE['read_trace'](trace_path, 'client2')
    captures, diagnostics = {}, Counter()
    for row in trace:
        if row['event'] not in ('capture-prepared', 'draw-consumed'): continue
        require(row.get('ownerID') == admission['phases'][0]['ownerID'], 'Frozen observer slot belongs to wrong native actor')
        require(type(row.get('observerVersion')) is int and row['observerVersion'] == 1
                and row.get('observerDiagnosticWire') is True, 'Missing diagnostic frozen observer schema')
        require(row.get('observerProcess') == processes['client2'], 'Frozen proxy belongs to another observer process')
        require(all(type(row.get(field)) is bool for field in ('observerProxyCurrent', 'observerAssociationValid')),
                'Frozen observer guards must be actual booleans')
        for field in tuple(SNAP_LINKS)[2:]: integer(row, field, 0, MAX)
        state = row.get('observerProxyState')
        require(state in ('active', 'stopped', 'replaced', 'unavailable'), 'Unknown frozen proxy state')
        text(row, 'observerReason', 160)
        if state == 'unavailable':
            require(row.get('observerSourceLife') == row.get('observerStateTag') == ''
                    and all(row[field] == 0 for field in tuple(SNAP_LINKS)[2:])
                    and not row['observerProxyCurrent'] and not row['observerAssociationValid'],
                    'Unavailable frozen proxy claims source/authority')
        else:
            life(row.get('observerSourceLife')); life(row.get('observerStateTag'), True)
            require(row['observerStateTag'] == row['observerSourceLife']+'|'+str(row['observerStateGeneration']),
                    'Frozen marker differs from source revision')
            require(state == 'active' or not row['observerAssociationValid'], 'Stopped/replaced proxy claims active frozen association')
            require(not row['observerAssociationValid'] or row['observerProxyCurrent'], 'Non-current proxy claims valid association')
        key = integer(row, 'captureId', 1, MAX), integer(row, 'slotToken', -(1 << 31), (1 << 31)-1), row.get('key')
        integer(row, 'nativeMonoNs', -(1 << 63), (1 << 63)-1)
        integer(row, 'nativeServerNs', -(1 << 63), (1 << 63)-1)
        integer(row, 'preparedPrimary', -2147483648, 2147483647)
        integer(row, 'preparedSecondary', -2147483648, 2147483647)
        require(type(row.get('nativeClockReady')) is bool, 'Frozen native clock flag is not boolean')
        require(row['nativeMonoNs'] <= row['monoNs'], 'Frozen native capture is in the future')
        if row['event'] == 'capture-prepared':
            require(key not in captures and row.get('part') == 'both', 'Duplicate/invalid frozen slot preparation')
            captures[key] = (row, {})
        else:
            require(key in captures and row.get('part') in ('body', 'cart'), 'Consumed draw lacks exact prepared body/cart slot')
            captured, parts = captures[key]
            require(row['part'] not in parts, 'Duplicate consumed body/cart part')
            equal(captured, row, FROZEN, 'Body/cart draw advanced frozen native association metadata')
            require(row['monoNs'] >= captured['monoNs'], 'Consumed draw predates preparation')
            parts[row['part']] = row
    # Both variable keys duplicate the same native slot. Validate both above;
    # count one canonical ActionPose view, never double-count body/cart draws.
    views = {}
    for (capture_id, slot, key), (captured, parts) in captures.items():
        if (capture_id, slot) in views:
            equal(views[capture_id, slot], captured, SNAPSHOT+('nativeMonoNs', 'nativeServerNs', 'nativeClockReady',
                  'preparedPrimary', 'preparedSecondary'), 'Pose-key views changed the same frozen slot association')
        else: views[capture_id, slot] = captured
    for (capture_id, slot, key), (captured, parts) in captures.items():
        if key != 'ToolkitCartActionPose': continue
        state = captured['observerProxyState']; diagnostics['prepared/'+state] += 1
        if set(parts) != {'body', 'cart'}:
            diagnostics['prepared-without-both-draws'] += 1; continue
        source = captured['observerSourceLife']
        if source not in selected:
            diagnostics['unselected-or-unavailable-source-pairs'] += 1; continue
        phase = phases[selected[source]-1]
        proxy = proxies.get((captured['observerProcess'], captured['observerProxyEpoch']))
        require(proxy is not None, 'Frozen selected source has no exact native proxy association')
        equal(dict((field, proxy[native]) for field, native in SNAP_LINKS.items()), captured,
              tuple(SNAP_LINKS), 'Frozen body/cart slot changed exact proxy input revision')
        apply = applies[(proxy['process'], proxy['applyGeneration'])]
        require(apply['monoNs'] <= captured['nativeMonoNs'], 'Frozen proxy predates successful State apply')
        past = [row for row in boundaries[(proxy['process'], proxy['proxyEpoch'])] if row['monoNs'] <= captured['nativeMonoNs']]
        if past:
            latest = max(past, key=lambda row: row['monoNs'])
            require(state == latest['proxyState'] and captured['observerAssociationValid'] is False,
                    'Frozen slot revived an already stopped/replaced proxy')
        elif state in ('stopped', 'replaced'):
            raise ValueError('Frozen retirement has no native stop/replacement evidence')
        if state != 'active' or not captured['observerAssociationValid'] or not captured['observerProxyCurrent']:
            diagnostics['inactive-selected-source-pairs'] += 1
            if state == 'stopped' and captured['observerProxyCurrent']:
                diagnostics['stopped-retained-current-pairs'] += 1
            continue
        end = max(row['monoNs'] for row in parts.values())
        carry = any(captured['nativeMonoNs'] < row['monoNs'] <= end
                    for row in boundaries[(proxy['process'], proxy['proxyEpoch'])])
        if carry:
            phase['frozenCarryoverBodyCartPairs'] += 1; diagnostics['frozen-carryover-pairs'] += 1
        else:
            phase['activeFrozenBodyCartPairs'] += 1
    for phase in phases:
        source = phase['sourceLife']; index = phase['index']
        phase['stateRevisions'] = sum(row['sourceLife'] == source for row in sets.values())
        phase['proxyAssociations'] = sum(row['sourceLife'] == source for row in proxies.values())
        phase['sourceStateSetsBeforeSealedCapture'] = sum(row['sourceLife'] == source and row['wallMs'] <= owners[index]['capture']['wallMs']
                                                        for row in sets.values())
        require(phase['stateRevisions'] > 0 and phase['proxyAssociations'] > 0
                and phase['activeFrozenBodyCartPairs'] > 0, 'Selected phase lacks transported active frozen body/cart association: '+phase['phase'])
    return dict(schema=1, diagnosticOnly=True, alteredDiagnosticWire=True, evidenceComplete=True,
                exactSealedSourceAssociations=6, nativeAdmissionEvidenceComplete=True,
                logicalQueryMessages=admission['logicalQueryMessages'], phases=phases,
                diagnostics=dict(diagnostics), sourceBeginsWithoutSelectedSeal=sum(row['sourceLife'] not in selected for row in by_event['client1']['source-begin']),
                proxyAssociations=len(proxies), successfulDirectedSubmissions=sum(map(len, submissions.values())),
                parsedStateRevisions=len(parsed_packets),
                discardedStateRevisions=len(discards),
                sourceRevisionCoverageComplete=True, proxyCoverageComplete=True, sampledDrawCoverageComplete=True,
                repeatedSubmissionCandidateSets=sum(len(value) > 1 for value in submissions.values()),
                sourceFiles=[str(root/(role+'-launch.log')) for role in ROLES]+[str(trace_path)],
                qualification='Opt-in altered diagnostic State wire pilot: exact source revision, native proxy and frozen body/cart input associations for this six-phase bank only. The marker is provenance, not a lease grant or production authority. Repeated writes do not identify a unique physical transmission. Stopped/replaced and frozen carryover inputs do not count as active draws. Stateful skeleton blending/tracks and other inputs prevent whole-image/source-age or playback equivalence claims. No action/release/reconnect protocol proof, production migration or runtime PASS is inferred; runtime and source verification remain separate.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(analyze(args.profile), indent=2))


if __name__ == '__main__': main()
