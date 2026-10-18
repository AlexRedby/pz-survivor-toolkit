"""Correlate diagnostic packet bytes and identities; never infer health-test success."""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path

PREFIX = '[SYNC_VISUALS_TRACE] '
ACTORS = ('server', 'client1', 'client2')


def visual_ids(event):
    worn = (event.get('player') or {}).get('worn', [])
    objects = {row['visual']['object']: row['item']['id'] for row in worn if row.get('visual')}
    result = []
    for visual in event.get('packetVisuals') or []:
        item = (visual or {}).get('item') or {}
        result.append(item.get('id') if item.get('id') is not None else objects.get((visual or {}).get('object')))
    return result


def audit(events):
    writes = defaultdict(list)
    for event in events:
        if event['kind'] == 'visual.write':
            writes[event.get('wire', {}).get('sha256')].append(event)
    issues, packets, returns, removals = [], [], [], []
    for actor in ACTORS:
        pending, removed = None, {}
        for event in (e for e in events if e['actor'] == actor):
            kind, player = event['kind'], event.get('player') or {}
            if kind == 'lineCap':
                issues.append(actor + ': diagnostic line cap reached')
            if event.get('error'):
                issues.append(actor + ': trace/native error at line ' + str(event['line']))
            if kind == 'visual.parse.enter':
                if pending is not None:
                    issues.append(actor + ': unclosed visual parse')
                pending = event
            elif kind == 'visual.parse.exit':
                if pending is None:
                    issues.append(actor + ': visual parse exit without enter'); continue
                enter, pending = pending, None
                matches = [e for e in writes.get(enter.get('wire', {}).get('sha256'), [])
                           if e['actor'] != actor and 0 <= enter['timeMs'] - e['timeMs'] < 30000]
                identities = {tuple(visual_ids(e)) for e in matches}
                sender_ids = list(next(iter(identities))) if len(identities) == 1 else None
                receiver_ids = visual_ids(event)
                identity_known = sender_ids is not None and None not in sender_ids + receiver_ids
                packets.append({'actor': actor, 'line': event['line'], 'username': player.get('username'),
                                'incomingCount': enter.get('count'), 'actualCount': len(receiver_ids),
                                'wireMatched': bool(matches), 'identityAmbiguous': len(identities) > 1,
                                'senderIDs': sender_ids, 'receiverIDs': receiver_ids,
                                'countMismatch': enter.get('count') != len(receiver_ids),
                                'identityMismatch': identity_known and sender_ids != receiver_ids,
                                'remaining': event.get('remaining'),
                                'senderLines': [{'actor': e['actor'], 'line': e['line']} for e in matches]})
            if kind == 'bandage.remove' and player.get('local'):
                before = {row['item']['id'] for row in (event.get('before') or {}).get('worn', [])}
                after = {row['item']['id'] for row in player.get('worn', [])}
                for identifier in before - after:
                    removed[(player['username'], identifier)] = event['line']
                    removals.append({'actor': actor, 'line': event['line'], 'timeMs': event['timeMs'], 'id': identifier,
                                     'username': player['username']})
            elif kind == 'clothing.process.exit' and player.get('local'):
                for row in player.get('worn', []):
                    key = (player['username'], row['item']['id'])
                    if key in removed:
                        returns.append({'actor': actor, 'line': event['line'], 'removedLine': removed[key],
                                        'username': player['username'], 'id': row['item']['id'], 'type': row['item']['type']})
                        del removed[key]
        if pending is not None:
            issues.append(actor + ': unclosed visual parse')
    if not packets:
        issues.append('No visual packets captured; absence of mismatches is not evidence')
    identities_verified = bool(packets) and all(p['wireMatched'] and not p['identityAmbiguous']
        and p['senderIDs'] is not None and None not in p['senderIDs'] + p['receiverIDs'] for p in packets)
    convergence = []
    for (username, identifier), removal in {(r['username'], r['id']): r for r in removals}.items():
        states = {}
        for event in events:
            player = event.get('player') or {}
            if player.get('username') == username and (event['actor'] == 'server' or
                    event['actor'] == removal['actor'] and player.get('local')):
                states[event['actor']] = event
        def clear(actor):
            event = states.get(actor)
            return event is not None and event['timeMs'] >= removal['timeMs'] and all(
                row['item']['id'] != identifier for row in event['player'].get('worn', []))
        convergence.append({'username': username, 'id': identifier, 'lastRemovalLine': removal['line'],
                            'serverClear': clear('server'), 'localClear': clear(removal['actor']),
                            'lastStateLines': {actor: e['line'] for actor, e in states.items()}})
    return {'issues': issues, 'identitiesVerified': identities_verified,
            'counts': dict(Counter(e['actor'] + ':' + e['kind'] for e in events)),
            'packets': packets, 'mismatches': [p for p in packets if p['countMismatch']],
            'identityMismatches': [p for p in packets if p['identityMismatch']],
            'localRemovals': removals, 'reintroducedRemovedIDs': returns,
            'finalConvergence': convergence,
            'allRemovedConverged': bool(convergence) and all(r['serverClear'] and r['localClear'] for r in convergence)}


def capture(root):
    events, logs, issues = [], {}, []
    for actor in ACTORS:
        path = root / (actor + '-launch.log')
        if not path.is_file():
            issues.append('Missing log: ' + str(path)); continue
        data = path.read_bytes(); logs[actor] = hashlib.sha256(data).hexdigest()
        for number, line in enumerate(data.decode(errors='replace').splitlines(), 1):
            if PREFIX not in line:
                continue
            try:
                event = json.loads(line.split(PREFIX, 1)[1]); event.update(actor=actor, line=number); events.append(event)
            except (ValueError, AttributeError) as error:
                issues.append(actor + ':' + str(number) + ': malformed trace: ' + str(error))
    result = audit(events); result['issues'] = issues + result['issues']
    return dict(result, root=str(root), logSHA256=logs,
                analyzerSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = capture(args.run.resolve())
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.write_text(text)
    else:
        print(text, end='')
    raise SystemExit(bool(result['issues'] or result['mismatches'] or result['identityMismatches']
                          or result['reintroducedRemovedIDs'] or not result['identitiesVerified']))
