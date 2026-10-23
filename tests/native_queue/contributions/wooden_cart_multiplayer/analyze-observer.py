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
PARAMS_MARKER = '[CART_OBSERVER_PARAMS] '
ASSOCIATION_FIELDS = ('associationKind', 'actionEpoch', 'consumeGeneration', 'paramsMapEpoch', 'paramsRevision')
SNAP_PARAMS = ('observerAssociationKind', 'observerConsumeGeneration', 'observerParamsMapEpoch', 'observerParamsRevision')
PARAM_LINKS = dict(observerAssociationKind='associationKind', observerConsumeGeneration='consumeGeneration',
                   observerParamsMapEpoch='paramsMapEpoch', observerParamsRevision='paramsRevision')
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
    if any(key in row for key in ASSOCIATION_FIELDS):
        require(all(key in row for key in ASSOCIATION_FIELDS), 'Incomplete native association metadata')
        require(row['associationKind'] in ('unavailable', 'packet-apply', 'retained-params'), 'Unknown native association kind')
        for key in ASSOCIATION_FIELDS[1:]: integer(row, key, 0, MAX)
        if row['proxyEpoch'] > 0:
            require(row['actionEpoch'] > 0 and row['associationKind'] != 'unavailable', 'Proxy lacks concrete native action identity')
            require((row['associationKind'] == 'retained-params') == all(row[key] > 0 for key in ASSOCIATION_FIELDS[2:]),
                    'Association kind differs from retained parameter ordinals')
        if row['associationKind'] != 'retained-params':
            require(all(row[key] == 0 for key in ASSOCIATION_FIELDS[2:]), 'Non-retained association claims parameter provenance')
    return row


def packet_key(row):
    return row['process'], row['packetEpoch'], row['receiveGeneration']


def successful(row):
    require(row['success'] is True, 'Failed native diagnostic operation')


PARAM_EVENTS = {'params-birth', 'params-load', 'params-invalidate', 'params-escape',
                'params-consume-begin', 'params-consume', 'params-error'}
PARAM_MASK_FIELDS = ('loadedParamMask', 'nativeDefaultMask', 'defaultConsumerGeneration')
PARAM_IDENTITY = ('actorEpoch', 'mapEpoch', 'revision', 'variablesEpoch', 'variablesMapEpoch',
                  'variablesRevision', 'packetEpoch', 'applyGeneration', 'stateTag', 'sourceLife')


def retained_consumers(logs, processes, applies, parsed_packets, selected):
    """Replay native map revisions and permanent alias escapes, never map values."""
    maps, begins, consumers, defaulted_loads = {}, {}, {}, []
    count = 0
    for role in ROLES:
        previous = None
        for row in marked(logs[role], PARAMS_MARKER):
            count += 1
            require(isinstance(row, dict) and row.get('event') in PARAM_EVENTS, 'Unknown retained parameter event')
            require(type(row.get('protocol')) is int and row['protocol'] == 1, 'Unknown retained parameter protocol')
            require(row.get('process') == processes[role], 'Retained parameter belongs to another process')
            require(type(row.get('success')) is bool and type(row.get('bound')) is bool,
                    'Retained parameter guards must be booleans')
            require(row.get('mapKind') in ('params', 'variables', 'none'), 'Unknown retained parameter map kind')
            for field in PARAM_IDENTITY[:8]+('consumeGeneration', 'actionEpoch'):
                integer(row, field, 0, MAX)
            integer(row, 'monoNs', -(1 << 63), (1 << 63)-1)
            require(previous is None or row['monoNs'] >= previous, 'Retained parameter log order moved backwards')
            previous = row['monoNs']
            text(row, 'reason', 160)
            require(isinstance(row.get('stateTag'), str) and isinstance(row.get('sourceLife'), str), 'Missing retained parameter source fields')
            require(row['event'] != 'params-error', 'Native retained parameter diagnostic error')
            key = row['process'], row['mapEpoch']
            event = row['event']
            if event == 'params-birth':
                require(row['success'] and not row['bound'] and row['mapEpoch'] > 0 and row['revision'] == 0
                        and key not in maps and row['mapKind'] != 'none', 'Invalid/duplicate retained map birth')
                require((row['mapKind'] == 'params' and row['actorEpoch'] > 0)
                        or (row['mapKind'] == 'variables' and row['actorEpoch'] == 0
                            and row['variablesEpoch'] > 0 and row['variablesMapEpoch'] == row['mapEpoch']
                            and row['variablesRevision'] == 0), 'Retained map birth lacks exact owner/wrapper identity')
                maps[key] = dict(birth=row, revision=0, escaped=False, load=None)
                continue
            if event in ('params-invalidate', 'params-escape'):
                require(not row['bound'] and row['mapEpoch'] > 0, 'Map mutation claims retained authority')
                state = maps.get(key)
                if state is None:
                    require(event == 'params-escape', 'Map write has no observed birth')
                    maps[key] = dict(birth=None, revision=row['revision'], escaped=True, load=None)
                else:
                    require(row['revision'] > state['revision'], 'Map mutation did not advance native revision')
                    if state['birth'] is not None:
                        equal(state['birth'], row, ('mapKind', 'actorEpoch'), 'Map mutation changed native map owner')
                    state.update(revision=row['revision'], escaped=state['escaped'] or event == 'params-escape', load=None)
                continue
            if event == 'params-load':
                state = maps.get(key)
                if not row['bound']:
                    if state is not None: state['load'] = None
                    continue
                require(role == 'client2' and row['success'] and row['mapKind'] == 'params', 'Invalid retained State load')
                loaded_mask = integer(row, 'loadedParamMask', 0, 127)
                default_mask = integer(row, 'nativeDefaultMask', 0, 127)
                default_generation = integer(row, 'defaultConsumerGeneration', 0, MAX)
                require(loaded_mask & default_mask == 0 and loaded_mask | default_mask == 127,
                        'Retained load lacks complete disjoint native parameter origin masks')
                require(default_mask & ~12 == 0 and bool(default_generation) == bool(default_mask),
                        'Retained load claims unsupported or unproven native parameter default')
                require(state is not None and state['birth'] is not None and not state['escaped']
                        and state['revision'] == row['revision'] and row['revision'] > 0,
                        'Retained State load lacks unescaped exact map birth/revision')
                equal(state['birth'], row, ('actorEpoch',), 'Retained State load changed map actor')
                nested = maps.get((row['process'], row['variablesMapEpoch']))
                require(nested is not None and nested['birth'] is not None and not nested['escaped']
                        and nested['birth']['mapKind'] == 'variables' and row['variablesEpoch'] > 0
                        and nested['birth']['variablesEpoch'] == row['variablesEpoch']
                        and nested['revision'] == row['variablesRevision'], 'Retained State load lacks unescaped exact variables birth/revision')
                if row['sourceLife'] not in selected:
                    state['load'] = row
                    continue
                apply = applies.get((row['process'], row['applyGeneration']))
                require(apply is not None and row['packetEpoch'] == apply['packetEpoch']
                        and row['stateTag'] == apply['stateTag'] and row['sourceLife'] == apply['sourceLife']
                        and row['actorEpoch'] == apply['actorEpoch'] and apply['stage'] == 'Enter'
                        and parsed_packets[packet_key(apply)]['monoNs'] <= row['monoNs'] <= apply['monoNs'],
                        'Retained load lacks exact original successful State apply')
                state['load'] = row
                if default_mask: defaulted_loads.append(row)
                continue
            consume_key = row['process'], row['consumeGeneration']
            require(row['consumeGeneration'] > 0, 'Missing native parameter consume generation')
            if event == 'params-consume-begin':
                require(consume_key not in begins and row['actionEpoch'] == 0 and row['success'] and not row['bound'],
                        'Duplicate/invalid parameter consume begin')
                begins[consume_key] = row
                continue
            require(event == 'params-consume' and consume_key in begins and consume_key not in consumers,
                    'Parameter consume lacks unique native begin/exit')
            begin = begins[consume_key]
            require(begin['monoNs'] <= row['monoNs'], 'Parameter consume exit precedes entry')
            consumers[consume_key] = row
            if not row['bound'] or row['sourceLife'] not in selected: continue
            equal(begin, row, PARAM_IDENTITY+PARAM_MASK_FIELDS+('consumeGeneration', 'mapKind'), 'Parameter consume changed native input revision')
            require(role == 'client2' and begin['success'] and row['success'] and not begin['bound']
                    and row['actionEpoch'] > 0 and row['mapKind'] == 'params', 'Retained consume lacks successful exact native action')
            state = maps.get(key)
            load = None if state is None else state['load']
            require(load is not None and not state['escaped'] and state['revision'] == row['revision'],
                    'Retained consume follows overwrite/unmarked load/unknown alias')
            equal(load, row, PARAM_IDENTITY+PARAM_MASK_FIELDS, 'Retained consume differs from exact loaded State revision')
            nested = maps.get((row['process'], row['variablesMapEpoch']))
            require(nested is not None and not nested['escaped'] and nested['revision'] == row['variablesRevision'],
                    'Retained variables changed or escaped before consume')
            apply = applies[row['process'], row['applyGeneration']]
            require(apply['monoNs'] <= begin['monoNs'], 'Retained consumer began before original State apply completed')
    require(set(begins) == set(consumers), 'Parameter consumer has no completed native exit')
    used_defaults = set()
    for load in defaulted_loads:
        key = load['process'], load['defaultConsumerGeneration']
        consume, begin = consumers.get(key), begins.get(key)
        require(consume is not None and begin is not None and key not in used_defaults,
                'Native default lacks unique completed original consumer')
        apply = applies[load['process'], load['applyGeneration']]
        require(not consume['bound'] and consume['success'] and consume['reason'] == 'non-retained-apply'
                and consume['actionEpoch'] > 0 and consume['actionEpoch'] == apply['actionEpoch']
                and apply.get('associationKind') == 'packet-apply' and apply['proxyEpoch'] > 0,
                'Native default lacks successful original packet-apply proxy consumer')
        equal(load, consume, PARAM_IDENTITY+PARAM_MASK_FIELDS, 'Native default commit changed original consumer input revision')
        equal(load, begin, ('actorEpoch', 'mapEpoch'), 'Native default began on a different actor/map')
        require(parsed_packets[packet_key(apply)]['monoNs'] <= begin['monoNs'] <= consume['monoNs']
                <= load['monoNs'] <= apply['monoNs'], 'Native default escaped original State apply consumer')
        used_defaults.add(key)
    return {key: row for key, row in consumers.items() if row['bound'] and row['sourceLife'] in selected}, count, len(used_defaults)


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
    native_params_schema = any('associationKind' in row for values in rows.values() for row in values)
    require(all(('associationKind' in row) == native_params_schema for values in rows.values() for row in values),
            'Native association metadata schema changed during bank')
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
    consumers, params_event_count, native_default_commits = retained_consumers(logs, processes, applies, parsed_packets, selected)
    require(not params_event_count or native_params_schema, 'Retained parameter events require explicit native association schema')
    used_consumers, associated_actions = set(), set()
    for key, proxy in proxies.items():
        if native_params_schema:
            action_key = proxy['process'], proxy['actionEpoch']
            require(action_key not in associated_actions, 'Native action reused by distinct proxy associations')
            associated_actions.add(action_key)
        apply = applies.get((proxy['process'], proxy['applyGeneration']))
        require(apply is not None, 'Proxy setAction has no completed exact State apply')
        require(packet_key(proxy) not in discards, 'Discarded State revision claims an applied proxy')
        equal(proxy, apply, LOCAL_FIELDS+('connectionEpoch',), 'Proxy linked to a different native apply receipt')
        if proxy.get('associationKind') == 'retained-params':
            consumer_key = proxy['process'], proxy['consumeGeneration']
            consume = consumers.get(consumer_key)
            require(consume is not None and consumer_key not in used_consumers, 'Retained proxy lacks unique successful native parameter consumer')
            require(proxy['reason'] == 'exact-retained-params-consumer' and proxy['associationValid']
                    and proxy['actionEpoch'] == consume['actionEpoch'] and proxy['actorEpoch'] == consume['actorEpoch']
                    and proxy['paramsMapEpoch'] == consume['mapEpoch'] and proxy['paramsRevision'] == consume['revision']
                    and proxy['packetEpoch'] == consume['packetEpoch'] and proxy['applyGeneration'] == consume['applyGeneration']
                    and proxy['stateTag'] == consume['stateTag'] and proxy['sourceLife'] == consume['sourceLife']
                    and consume['monoNs'] <= proxy['monoNs'], 'Retained proxy changed exact successful native consumer')
            used_consumers.add(consumer_key)
        else:
            require(apply['proxyEpoch'] == proxy['proxyEpoch'] and apply['proxyCurrent']
                    and apply['associationValid'] and apply['proxyState'] == 'active',
                    'Completed State apply does not validate exact current proxy')
            if native_params_schema:
                equal(proxy, apply, ASSOCIATION_FIELDS, 'Completed apply changed exact native proxy action identity')
            require(proxy['monoNs'] <= apply['monoNs'], 'Scoped proxy creation follows State apply exit')
        for boundary in boundaries[key]:
            equal(proxy, boundary, LOCAL_FIELDS+('connectionEpoch', 'proxyEpoch', 'applyGeneration')+(ASSOCIATION_FIELDS if native_params_schema else ()), 'Retired proxy changed original association')
            require(boundary['monoNs'] >= proxy['monoNs'], 'Proxy retirement precedes association')
    require(set(boundaries) <= set(proxies), 'Proxy retirement has no exact association')

    trace_path = root/'client2/cart-timeline.jsonl'
    trace = TIMELINE['read_trace'](trace_path, 'client2')
    captures, diagnostics = {}, Counter()
    for row in trace:
        if row['event'] not in ('capture-prepared', 'draw-consumed'): continue
        require(row.get('ownerID') == admission['phases'][0]['ownerID'], 'Frozen observer slot belongs to wrong native actor')
        require(type(row.get('observerVersion')) is int and row['observerVersion'] == (2 if native_params_schema else 1)
                and row.get('observerDiagnosticWire') is True, 'Missing diagnostic frozen observer schema')
        require(row.get('observerProcess') == processes['client2'], 'Frozen proxy belongs to another observer process')
        require(all(type(row.get(field)) is bool for field in ('observerProxyCurrent', 'observerAssociationValid')),
                'Frozen observer guards must be actual booleans')
        for field in tuple(SNAP_LINKS)[2:]: integer(row, field, 0, MAX)
        if native_params_schema:
            require(all(key in row for key in SNAP_PARAMS), 'Incomplete frozen retained parameter metadata')
            require(row['observerAssociationKind'] in ('unavailable', 'packet-apply', 'retained-params'), 'Unknown frozen association kind')
            for field in SNAP_PARAMS[1:]: integer(row, field, 0, MAX)
            if row['observerAssociationKind'] == 'retained-params':
                require(all(row[field] > 0 for field in SNAP_PARAMS[1:]), 'Retained frozen association lacks parameter identity')
            else:
                require(all(row[field] == 0 for field in SNAP_PARAMS[1:]), 'Frozen non-retained association claims parameter identity')
        else:
            require(not any(key in row for key in SNAP_PARAMS), 'Old frozen schema claims retained parameter metadata')
        state = row.get('observerProxyState')
        require(state in ('active', 'stopped', 'replaced', 'unavailable'), 'Unknown frozen proxy state')
        text(row, 'observerReason', 160)
        if native_params_schema:
            require((state == 'unavailable') == (row['observerAssociationKind'] == 'unavailable'),
                    'Frozen proxy state differs from association availability')
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
            equal(captured, row, FROZEN+(SNAP_PARAMS if native_params_schema else ()), 'Body/cart draw advanced frozen native association metadata')
            require(row['monoNs'] >= captured['monoNs'], 'Consumed draw predates preparation')
            parts[row['part']] = row
    # Both variable keys duplicate the same native slot. Validate both above;
    # count one canonical ActionPose view, never double-count body/cart draws.
    views = {}
    for (capture_id, slot, key), (captured, parts) in captures.items():
        if (capture_id, slot) in views:
            equal(views[capture_id, slot], captured, SNAPSHOT+(SNAP_PARAMS if native_params_schema else ())+('nativeMonoNs', 'nativeServerNs', 'nativeClockReady',
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
        if native_params_schema:
            equal(dict((field, proxy[native]) for field, native in PARAM_LINKS.items()), captured, SNAP_PARAMS,
                  'Frozen body/cart slot changed retained parameter consumer identity')
        apply = applies[(proxy['process'], proxy['applyGeneration'])]
        require(apply['monoNs'] <= captured['nativeMonoNs'], 'Frozen proxy predates successful State apply')
        require(proxy['monoNs'] <= captured['nativeMonoNs'], 'Frozen proxy predates native association')
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
    failures = []
    for phase in phases:
        source = phase['sourceLife']; index = phase['index']
        phase['stateRevisions'] = sum(row['sourceLife'] == source for row in sets.values())
        phase['proxyAssociations'] = sum(row['sourceLife'] == source for row in proxies.values())
        phase['sourceStateSetsBeforeSealedCapture'] = sum(row['sourceLife'] == source and row['wallMs'] <= owners[index]['capture']['wallMs']
                                                        for row in sets.values())
        require(phase['stateRevisions'] > 0 and phase['proxyAssociations'] > 0,
                'Selected phase lacks transported native proxy association: '+phase['phase'])
        if phase['activeFrozenBodyCartPairs'] == 0:
            failures.append('Selected phase lacks transported active frozen body/cart association: '+phase['phase'])
    return dict(schema=1, diagnosticOnly=True, alteredDiagnosticWire=True, evidenceComplete=not failures,
                failures=failures, activeFrozenPhaseCount=sum(phase['activeFrozenBodyCartPairs'] > 0 for phase in phases),
                proxyReplacementBoundaries=sum(row['event']=='proxy-replaced' for values in boundaries.values() for row in values),
                exactSealedSourceAssociations=6, nativeAdmissionEvidenceComplete=True,
                logicalQueryMessages=admission['logicalQueryMessages'], phases=phases,
                diagnostics=dict(diagnostics), sourceBeginsWithoutSelectedSeal=sum(row['sourceLife'] not in selected for row in by_event['client1']['source-begin']),
                proxyAssociations=len(proxies), retainedParamsEvidenceAvailable=bool(params_event_count),
                retainedParamsEvents=params_event_count, retainedParamsConsumerAssociations=len(used_consumers),
                originalNativeDefaultCommits=native_default_commits, successfulDirectedSubmissions=sum(map(len, submissions.values())),
                parsedStateRevisions=len(parsed_packets),
                discardedStateRevisions=len(discards),
                sourceRevisionCoverageComplete=True, proxyCoverageComplete=True, sampledDrawCoverageComplete=not failures,
                repeatedSubmissionCandidateSets=sum(len(value) > 1 for value in submissions.values()),
                sourceFiles=[str(root/(role+'-launch.log')) for role in ROLES]+[str(trace_path)],
                qualification='Opt-in altered diagnostic State wire pilot: exact source revision and native packet-apply/retained-parameter proxy associations for this six-phase bank only. Frozen body/cart coverage is complete only when sampledDrawCoverageComplete is true; failures preserve missing phases explicitly. Native hand-slot defaults count only with a completed exact original apply consumer. The marker is provenance, not a lease grant or production authority. Repeated writes do not identify a unique physical transmission. Stopped/replaced and frozen carryover inputs do not count as active draws. Stateful skeleton blending/tracks and other inputs prevent whole-image/source-age or playback equivalence claims. No action/release/reconnect protocol proof, production migration or runtime PASS is inferred; runtime and source verification remain separate.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(analyze(args.profile), indent=2))


if __name__ == '__main__': main()
