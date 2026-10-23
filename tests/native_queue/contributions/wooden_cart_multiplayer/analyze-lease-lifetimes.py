"""Bounded native setter fixture evidence; does not certify normal release or reconnect."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import runpy

HELD = runpy.run_path(str(Path(__file__).with_name('analyze-lease.py')))
require, parse, integer, text = (HELD[name] for name in ('require', 'parse', 'integer', 'text'))
ROLES = ('server', 'client1', 'client2')
CLIENTS = ROLES[1:]
MARKER = '[CART_LEASE_LIFETIME] '
NATIVE = '[CART_EQUIPMENT] '
MAX = 9007199254740991
IDENTITY = ('session', 'grant', 'lease', 'cart')
PHASES = ('baseline', 'release-reacquire', 'same-id-replacement')


def token(value):
    require(isinstance(value, str) and len(value) <= 160, 'Missing native lifetime token')
    match = re.fullmatch(r'1\|([^|\s]{1,120})\|([1-9][0-9]*)\|([1-9][0-9]*)\|([1-9][0-9]*)', value)
    require(match is not None, 'Invalid/default native lifetime token')
    process, actor, connection, revision = match.groups()
    numbers = tuple(map(int, (actor, connection, revision)))
    require(all(n <= MAX for n in numbers), 'Native lifetime token overflow')
    return (process, *numbers)


def records(log, marker, limit):
    result = []
    for line, value in enumerate(log.splitlines()):
        if marker in value:
            row = parse(value.split(marker, 1)[1])
            require(isinstance(row, dict), 'Expected evidence JSON object')
            result.append((line, row))
            require(len(result) <= limit, 'Evidence record limit exceeded')
    return result


def identity(row):
    text(row, 'session', 80)
    integer(row, 'grant', 1, 2147483647)
    integer(row, 'lease', 1, 2147483647)
    integer(row, 'cart', -2147483648, 2147483647)
    return tuple(row[field] for field in IDENTITY)


def native_trace(log, selected, owner, cutoff):
    """Replay one native actor ledger; nested serials are paired as a stack."""
    process, actor, connection, _ = selected
    traces = records(log, NATIVE, 8192)
    target, clocks, serials = [], {}, set()
    for line, row in traces:
        if line > cutoff:
            continue  # Runtime shutdown is outside this completed fixture.
        require(row.get('event') != 'error', 'Native equipment trace error')
        proc = text(row, 'process', 120)
        mono = integer(row, 'monoNs', -9223372036854775808, 9223372036854775807)
        require(proc not in clocks or mono >= clocks[proc], 'Native monotonic clock regressed')
        clocks[proc] = mono
        if proc == process and row.get('ownerID') == owner:
            require(row.get('actorEpoch') == actor, 'Native owner actor incarnation changed')
        if proc == process and row.get('actorEpoch') == actor:
            target.append((line, row))
    require(target, 'Missing exact native lifetime trace')
    stack, snapshots, revision, current, prior_serial = [], {}, None, None, 0
    for line, row in target:
        require(integer(row, 'ownerID', 0, 32767) == owner, 'Native owner changed')
        require(integer(row, 'connectionEpoch', 1, MAX) == connection, 'Native connection changed')
        rev = integer(row, 'revision', 1, MAX)
        depth = integer(row, 'depth', 0, 2147483647)
        serial = integer(row, 'mutationSerial', 0, MAX)
        for key in ('oldPrimaryEpoch', 'oldSecondaryEpoch', 'primaryEpoch', 'secondaryEpoch'):
            integer(row, key, 0, MAX)
        state = tuple(row[key] for key in ('primaryEpoch', 'secondaryEpoch', 'primaryID', 'secondaryID'))
        for epoch, id_ in ((state[0], state[2]), (state[1], state[3])):
            require((epoch == 0 and id_ is None) or (epoch > 0 and type(id_) is int and -2147483648 <= id_ <= 2147483647),
                    'Native hand epoch/ID mismatch')
        require(row.get('success') is True and row.get('poisoned') is False and row.get('retired') is False,
                'Failed/poisoned/retired native lifetime cannot heal')
        event, reason = row.get('event'), text(row, 'reason', 80)
        if event == 'baseline':
            require(revision is None and not stack and serial == 0 and depth == 0 and reason == 'admitted-current',
                    'Repeated or invalid native baseline')
            require(rev == 1 and state[0] == state[1] and state[0] > 0 and state[2] == state[3], 'Invalid native held baseline')
            revision, current = rev, state
        elif event == 'mutation-enter':
            require(revision is not None and rev == revision+1 and depth == len(stack)+1, 'Native mutation entry revision/depth differs')
            require(serial > prior_serial and (process, actor, serial) not in serials, 'Native mutation serial reused/reordered')
            serials.add((process, actor, serial)); prior_serial = serial
            if not stack:
                require(state == current, 'Unobserved native equipment mutation')
            require((row['oldPrimaryEpoch'], row['oldSecondaryEpoch']) == state[:2], 'Native mutation entry old references differ')
            stack.append(row); revision = rev
        elif event == 'mutation-exit':
            require(stack and rev == revision and depth == len(stack)-1, 'Unpaired native mutation exit')
            entry = stack.pop()
            require(serial == entry['mutationSerial'] and reason == entry['reason']
                    and all(row[k] == entry[k] for k in ('oldPrimaryEpoch', 'oldSecondaryEpoch')), 'Native mutation scope mismatch')
            if not stack:
                current = state
        else:
            raise ValueError('Unknown/retired native event: '+str(event))
        if not stack:
            snapshots[revision] = (line, current)
    require(not stack, 'Unfinished native mutation scope')
    return target, snapshots


def analyze(root):
    root = Path(root)
    selection = parse((root/'selection.json').read_text())
    require(isinstance(selection, dict) and isinstance(selection.get('options'), dict)
            and selection['options'].get('cart_lease_lifetimes') is True
            and selection['options'].get('cart_lease_control') is True, 'Explicit lifetime and held lease control selection required')
    control = HELD['analyze'](root)
    require(control.get('evidenceComplete') is True and control.get('roundsPerClient') == 3, 'Held lease control prerequisite failed')
    owner, cart = control['ownerID'], control['cartID']
    logs = {role: (root/(role+'-launch.log')).read_text() for role in ROLES}
    require(all(len(log) <= 32*1024*1024 for log in logs.values()), 'Capture log size limit exceeded')
    rows, index, positions = {}, {}, {}
    expected = dict(server=Counter(ready=2, begin=1, cycle=2, bind=6, echo=6, prepare=4, stale=4, done=2, complete=1),
                    client1=Counter(ready=1, begin=1, cycle=2, request=3, bound=3, receipt=3, prepare=2, done=1, complete=1),
                    client2=Counter(ready=1, begin=1, cycle=2, request=3, bound=3, receipt=3, prepare=2, done=1, complete=1))
    for role in ROLES:
        rows[role] = records(logs[role], MARKER, 64)
        require(Counter(row.get('event') for _, row in rows[role]) == expected[role], role+': lifetime event counts differ')
        wall, phases = -1, []
        for line, row in rows[role]:
            require(row.get('actor') == role and integer(row, 'owner', 0, 32767) == owner, role+': foreign lifetime owner/actor')
            now = integer(row, 'wall', 0, MAX)
            require(now >= wall, role+': lifetime wall clock regressed'); wall = now
            phase = integer(row, 'phase', 0, 3); phases.append(phase)
            event = row['event']
            require(phase == 0 if event == 'ready' else phase == 3 if event in ('done','complete') else phase >= 1,
                    role+': invalid event phase')
            requester = row.get('requester') if role == 'server' and event in ('ready','bind','echo','prepare','stale','done') else role
            require(requester in CLIENTS or requester == 'server', 'Unknown native requester')
            key = role, phase, requester, event
            require(key not in index, 'Duplicate lifetime event'); index[key] = row; positions[key] = line
            if event in ('bind','bound','echo','receipt','stale') or role == 'server' and event in ('ready','prepare','done'):
                require(row.get('guarded') is True, 'Actual native lifetime guard missing')
            if event in ('bind','bound','echo','receipt','stale') or event == 'prepare' and role == 'server':
                require(identity(row)[3] == cart, 'Native lifetime cart differs')
            if event in ('request','bound','bind','echo','receipt','prepare'):
                text(row, 'nonce', 120)
            if event in ('request','bound','bind','prepare'):
                token(row.get('lifetime'))
            if event in ('echo','receipt'):
                require(row.get('accepted') is (requester == 'client1') and type(row.get('accepted')) is bool,
                        'Exact native source authority differs')
                require(integer(row,'seq',1,1) == 1, 'Fresh lifetime sequence differs')
            if event == 'stale':
                require(phase in (2,3) and row.get('accepted') is False, 'Retired payload was not refused')
        require(phases == sorted(phases), role+': lifetime phase order regressed')
        require(rows[role][-1][1]['event'] == 'complete', role+': lifetime completion must be final')
        require(rows[role][-1][1]['wall']-rows[role][0][1]['wall'] <= 20000, 'Lifetime fixture deadline exceeded')

    def get(role, phase, event, requester=None):
        key = role, phase, requester or role, event
        require(key in index, 'Missing exact lifetime event: '+str(key))
        return index[key], positions[key]

    tokens, chains, pending_nonces = {role: {} for role in ROLES}, [], set()
    session, phase_identities = None, {}
    for phase in (1,2,3):
        authoritative = set()
        for role in CLIENTS:
            request, rp = get(role,phase,'request')
            bound, bp = get(role,phase,'bound'); receipt, ep = get(role,phase,'receipt')
            bind, sb = get('server',phase,'bind',role); echo, se = get('server',phase,'echo',role)
            require(rp < bp < ep and sb < se, 'Lifetime callback chain reordered')
            require(len({row['nonce'] for row in (request,bind,bound,echo,receipt)}) == 1, 'Fresh challenge nonce differs')
            require(request['nonce'] not in pending_nonces, 'Fresh/pending lifetime nonce reused'); pending_nonces.add(request['nonce'])
            ident = identity(bind)
            require(all(identity(row) == ident for row in (bound,echo,receipt)), 'Exact lifetime session/binding chain differs')
            require(request['lifetime'] == bound['lifetime'], 'Client native lifetime changed during bind')
            tokens[role][phase] = request['lifetime']; authoritative.add(bind['lifetime'])
            phase_identities.setdefault(phase,set()).add(ident)
            if session is None: session = ident[0]
            require(session == ident[0], 'Server session changed during setter fixture')
            require(ident[1] == 1 and ident[2] == phase, 'Server grant/lease did not follow exact fixture lifetime')
            if phase == 1:
                _, begin = get(role,1,'begin'); _, server_begin = get('server',1,'begin')
                require(begin < rp and server_begin < sb, 'Lifetime bind preceded fixture begin')
            else:
                _, server_cycle = get('server',phase,'cycle')
                require(server_cycle < sb, 'Server lifetime bind preceded native setter cycle')
            if phase == 3:
                _, done = get(role,3,'done'); _, server_done = get('server',3,'done',role)
                _, complete = get(role,3,'complete'); _, server_complete = get('server',3,'complete')
                require(ep < done < complete and se < server_done < server_complete, 'Lifetime done/completion preceded receipt')
            if phase < 3:
                prepared, pp = get(role,phase,'prepare'); server_prepared, sp = get('server',phase,'prepare',role)
                require(ep < pp and se < sp and prepared['nonce'] == server_prepared['nonce'], 'Pending challenge preparation reordered/mismatched')
                require(prepared['nonce'] not in pending_nonces, 'Pending lifetime nonce reused'); pending_nonces.add(prepared['nonce'])
                require(prepared['lifetime'] == request['lifetime'] and server_prepared['lifetime'] == bind['lifetime']
                        and identity(server_prepared) == ident, 'Pending challenge native binding differs')
            if phase > 1:
                cycle, cp = get(role,phase,'cycle'); stale, ss = get('server',phase,'stale',role)
                previous, _ = get(role,phase-1,'prepare'); old_bind, _ = get('server',phase-1,'bind',role)
                require(cp < rp and ss < sb, 'Fresh binding preceded stale rejection')
                require(cycle.get('staleReplyAccepted') is False and cycle.get('stalePayloadAccepted') is False,
                        'Retired pending reply/payload was not refused')
                require(cycle.get('staleNonce') == previous['nonce'], 'Stale prepared reply nonce differs')
                require(identity(stale) == identity(old_bind), 'Stale server payload identity differs')
            chains.append(dict(requester=role,phase=phase,nonce=request['nonce'],session=ident[0],grant=ident[1],lease=ident[2],accepted=receipt['accepted']))
        require(len(authoritative) == 1 and len(phase_identities[phase]) == 1, 'Authoritative phase binding differs by requester')
        tokens['server'][phase] = authoritative.pop()
        if phase > 1:
            require(phase_identities[phase] != phase_identities[phase-1], 'Retired server binding silently reused')
    require(len({token(tokens[role][1])[0] for role in ROLES}) == 3, 'Native process identity reused across roles')
    cycles = []
    cargo_identity = None
    for role in ROLES:
        complete, cutoff = get(role,3,'complete')
        selected = token(tokens[role][1])
        trace, snapshots = native_trace(logs[role], selected, owner, cutoff)
        require(all(row['revision'] <= token(tokens[role][3])[3] for _,row in trace),
                'Unlinked native mutation after final lifetime bind')
        for phase in (1,2,3):
            tok = token(tokens[role][phase])
            require(tok[:3] == selected[:3] and tok[3] in snapshots, 'Unknown/stale native token revision')
            snapshot_line, state = snapshots[tok[3]]
            require(state[0] > 0 and state[0] == state[1] and state[2] == state[3] == cart, 'Native token does not resolve exact held cart')
            evidence_events = ('bind', 'prepare') if role == 'server' and phase < 3 else ('bind',) if role == 'server' else ('request','bound','prepare') if phase < 3 else ('request','bound')
            next_enter = min((line for line,row in trace if row['event']=='mutation-enter' and row['revision']>tok[3]), default=cutoff+1)
            for event in evidence_events:
                targets = CLIENTS if role == 'server' else (role,)
                for requester in targets:
                    _, line = get(role,phase,event,requester)
                    require(snapshot_line < line < next_enter, 'Lifetime token used outside completed native revision window')
        for phase in (2,3):
            row, line = get(role,phase,'cycle')
            before, after = token(row.get('before')), token(row.get('after'))
            require(row.get('name') == PHASES[phase-1] and row.get('sameItem') is True, 'Setter fixture original cart restoration missing')
            require(integer(row,'cart',-2147483648,2147483647) == cart, 'Setter fixture cart changed')
            cid=integer(row,'cargoID',-2147483648,2147483647); weight=row.get('cargoWeight')
            require(type(weight) in (int,float) and 0 < weight <= 100000, 'Invalid fixture cargo weight')
            require(cargo_identity is None or cargo_identity == (cid,weight), 'Fixture cargo identity/weight changed'); cargo_identity=(cid,weight)
            require(row['before'] == tokens[role][phase-1] and row['after'] == tokens[role][phase]
                    and before[:3] == after[:3] == selected[:3] and after[3] > before[3], 'Cycle token boundary differs')
            require(before[3] in snapshots and after[3] in snapshots, 'Cycle native revision missing')
            before_line, original = snapshots[before[3]]; after_line, restored = snapshots[after[3]]
            require(before_line < after_line < line and restored == original, 'Native setter original references not restored before cycle')
            window = [(n,r) for n,r in trace if before[3] < r['revision'] <= after[3]]
            require(window and all(r['event'] in ('mutation-enter','mutation-exit') and r['reason'] in ('primary','secondary') for _,r in window), 'Unknown/interleaving mutation in setter cycle')
            completed=[r for _,r in window if r['event']=='mutation-exit']
            exits=[r for r in completed if r['depth']==0]
            require(len(completed)>=4 and {r['reason'] for r in completed} == {'primary','secondary'}, 'Completed native setter writes missing')
            if phase == 2:
                intermediate=[r for r in exits if r['primaryEpoch']==r['secondaryEpoch']==0 and r['primaryID'] is None and r['secondaryID'] is None]
                require(intermediate, 'No completed native both-hands release')
            else:
                intermediate=[r for r in exits if r['primaryEpoch']==r['secondaryEpoch'] and r['primaryEpoch']>0
                              and r['primaryEpoch']!=original[0] and r['primaryID']==r['secondaryID']==cart]
                require(intermediate, 'No completed same-ID different-reference replacement')
            require(exits.index(intermediate[0]) < len(exits)-1, 'Intermediate setter state was not later restored')
            cycles.append(dict(actor=role,phase=phase,name=row['name'],before=row['before'],after=row['after'],completedSetterWrites=len(completed),nativeLineStart=window[0][0]+1,nativeLineEnd=after_line+1))
    return dict(schema=1,diagnosticOnly=True,evidenceComplete=True,ownerID=owner,cartID=cart,
                phases=list(PHASES),completeChains=6,completedNativeCycles=6,stalePreparedRepliesRefused=4,
                staleClientPayloadsRefused=4,staleServerPayloadsRefused=4,
                heldLeaseControl=dict(evidenceComplete=True,roundsPerClient=3,completeChains=control['completeChains']),
                logicalCommandMessages=dict(fixture=40,clientToServer=20,serverToClient=20,includingHeldControl=64),
                chains=chains,cycles=cycles,sourceFiles={role:role+'-launch.log' for role in ROLES},
                qualification='Native setter fixture only: completed reference release/reacquisition and same-ID replacement with restored original cart/cargo, guarded fresh binds and stale refusals. No normal menu release, complete reconnect lifecycle, production migration or runtime PASS is established. Logical command counts are not wire bytes or delivery acknowledgements.')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile',required=True,type=Path)
    args=parser.parse_args()
    print(json.dumps(analyze(args.profile),indent=2))


if __name__ == '__main__':
    main()
