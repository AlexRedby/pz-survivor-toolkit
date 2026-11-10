"""Native same-square radio battery insertion/removal authority receipts."""
import json
from pathlib import Path
import re
import shutil
from .. import report
from ..placement import validate as validate_placement
from . import tv_controls as tv

MODS = tv.MODS
CASES = ('root', 'worn-bag', 'world')
PREFIX = '[DEVICE_BATTERY_BINDING] '


def definitions():
    checks = {case: {'effectsVerified': True, 'serverAuthorityVerified': True, 'tailCompleted': True} for case in CASES}
    return {'device-battery-binding': {'status': 'ready', 'clients': 1, 'default_mods': list(MODS),
        'scenario_actions': {'same-square-radio-battery': {'mods': list(MODS),
            'checks': {'success-queued': checks, 'server-authority': checks},
            'scope': 'Native RWMPower insertion and removal on the second of two same-square world radios, with root, worn-bag and adjacent world-container inputs, exact item and authority receipts and independent book tail.'}},
        'cases': [dict(id=case, producer='fixture', capability='effect', kinds=['sp','mp'], modes=['native','toolkit'], languages=['EN']) for case in CASES]}}


def validate(selection):
    if (selection.get('cases') != list(CASES) or selection.get('kind') not in ('sp','mp')
        or selection.get('mode') not in ('native','toolkit') or selection.get('languages') != ['EN']
        or type(selection.get('clients')) is not int or selection.get('clients') != 1 or selection.get('mods') != MODS
        or selection.get('options',{}).get('world_template')
        or selection['kind']=='mp' and selection.get('options',{}).get('mp_host') is not True):
        raise ValueError('Battery binding requires fresh selected-pack SP/menu Host and one EN client')


def sources(project, selection):
    root=Path(project)/'tests/native_queue'
    return [*sorted((root/'device-battery-binding').rglob('*.lua')), *sorted((root/'startup').rglob('*.lua')),
            root/'health/shared/QueueHealthEvents.lua',root/'support/QueueEnergyPlacement.lua',
            Path(__file__).resolve().parents[1]/'placement.py']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection);root=Path(project)/'tests/native_queue'
    for role in runtime['roles'].values():
        lua=Path(role['cache'])/'mods/ActionQueueTest/42/media/lua'
        for side,name in [('client','ZZStartup.lua'),('server','ZZStartupServer.lua')]:
            shutil.copy2(root/'startup'/side/name,lua/side/name)
        shutil.copy2(root/'health/shared/QueueHealthEvents.lua',lua/'shared')
    runtime.setdefault('fixture',{}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL device-battery-binding'],sandbox={'Zombies':6,'MinutesPerPage':2.0})


def _raw(text, marker):
    return [json.loads(m.group(1)) for m in re.finditer(re.escape(PREFIX+marker+' ')+r'([^\n]+)',text)]


def complete(selection, role, text):
    return role=='client1' and _raw(text,'COMPLETE')==[{'cases':list(CASES)}]


def check_case(row, selection, prepared, baseline, verified, acks):
    issues=[]
    try:
        ids=row['ids'];wrong,target=ids['wrong'],ids['target'];bat=ids['battery'];case=ids['case']
        if (ids!=prepared or case not in CASES or ids['mode']!=selection['mode']
            or set(wrong)!={'x','y','z','index'} or set(target)!=set(wrong)
            or any(type(v) is not int for d in (wrong,target) for v in d.values())
            or any(wrong[k]!=target[k] for k in ('x','y','z')) or not 0<=wrong['index']<target['index']
            or any(type(bat[k]) is not int for k in ('id','uses','maxUses')) or not 0<bat['uses']<=bat['maxUses']):
            raise ValueError('same-square device/input identity')
        source=ids['source']
        if source['kind']!=case: raise ValueError('source kind')
        if case=='root' and (source['bag'] is not False or source['world'] is not False): raise ValueError('root source')
        if case=='worn-bag':
            if (source['world'] is not False or set(source['bag'])!={'id','type','location'} or type(source['bag']['id']) is not int
                    or source['bag']['type']!='Base.Bag_Military' or not isinstance(source['bag']['location'],str) or not source['bag']['location']): raise ValueError('worn bag identity')
        if case=='world':
            w=source['world'];origin=ids['origin']
            if (source['bag'] is not False or set(w)!={'x','y','z','index'} or any(type(v) is not int for v in w.values())
                    or w['index']<0 or w['x']!=origin['x'] or w['y']!=origin['y']-1 or w['z']!=origin['z']): raise ValueError('world container identity')
        validate_placement(row['clientPlacement'],ids['origin'],'local')
        validate_placement(ids['placementProof'],ids['origin'],'replica' if selection['kind']=='mp' else 'local')
        if row['authorityBaseline']!=baseline or row['server']!=verified: raise ValueError('authority receipts')
        snapshots=[row[k] for k in ('input','baseline','authorityBaseline','client','server')]
        for snapshot in snapshots:
            if (snapshot['wrong']['power']!=row['input']['wrong']['power']
                or snapshot['case']!=case or snapshot['source']!=source or snapshot['wrong']['identity']!=wrong
                or snapshot['target']['identity']!=target or snapshot['wrong']['battery'] is not False):
                raise ValueError('wrong device mutation')
        if (not row['input']['inputPresent'] or row['input']['target']['battery'] is not False
            or row['input']['sourceCount']!=1 or row['input']['rootCount']!=(1 if case=='root' else 0)
            or row['input']['actorCount']!=(0 if case=='world' else 1)): raise ValueError('input state')
        for snap in (row['baseline'],row['authorityBaseline']):
            if snap['inputPresent'] or snap['sourceCount']!=0 or snap['rootCount']!=0 or snap['actorCount']!=0 or snap['target']['battery'] is not True: raise ValueError('insertion did not debit/install battery')
            if abs(snap['target']['power']-bat['uses']/bat['maxUses'])>.011: raise ValueError('inserted charge differs')
        for snap in (row['client'],row['server']):
            if snap['inputPresent'] or snap['sourceCount']!=0 or snap['rootCount']!=0 or snap['actorCount']!=0 or snap['target']['battery'] is not False: raise ValueError('removal did not clear battery')
            initial={v['id']:v for v in row['input']['batteries']};final={v['id']:v for v in snap['batteries']}
            if len(initial)!=len(row['input']['batteries']) or len(final)!=len(snap['batteries']): raise ValueError('duplicate battery ID')
            if (bat['id'] in initial)!=(case!='world') or bat['id'] in final: raise ValueError('original battery identity')
            initial.pop(bat['id'],None);added=set(final)-set(initial)
            if len(added)!=1 or any(final.get(k)!=v for k,v in initial.items()): raise ValueError('battery conservation')
            result=final[added.pop()]
            if (type(result['id']) is not int or type(result['uses']) is not int or type(result['maxUses']) is not int
                or result['maxUses']!=bat['maxUses'] or abs(result['uses']-bat['uses'])>1): raise ValueError('removed battery charge')
            for name in ('front','tail'):
                if (snap['books'][name]['id']!=ids[name]['id'] or snap['books'][name]['root'] is not True
                    or snap['books'][name]['pages']!=ids[name]['pages'] or snap['books'][name]['characterPages']!=ids[name]['pages']):
                    raise ValueError('book completion '+name)
        if (row['status']!='passed' or row['queueIdle'] is not True or not tv._number(row['settleMilliseconds']) or row['settleMilliseconds']<1000): raise ValueError('queue settle')
        if row.get('edit')!={'cancelled':selection['mode']=='toolkit' and case=='root','reordered':selection['mode']=='toolkit' and case=='root','untouched':True}:
            raise ValueError('pending edit effects')
        all_commands=row['commands']
        cancelled=[c for c in all_commands if c.get('cancelled')]
        if selection['mode']=='toolkit' and case=='root':
            if (len(cancelled)!=1 or cancelled[0]['name']!='cancelled-eject'
                or cancelled[0]['type']!='ISDeviceBatteryAction' or cancelled[0]['duration']!=30
                or cancelled[0]['producer']!='native RWMPower callback'
                or cancelled[0]['started'] is not False or cancelled[0]['progress'] is not False or cancelled[0].get('ack')):
                raise ValueError('cancelled battery effect')
        elif cancelled: raise ValueError('unexpected native cancellation')
        commands=[c for c in all_commands if not c.get('cancelled')]
        expected_names=['insert','front']+(['cancelled-eject']if selection['mode']=='toolkit' and case=='root' else[])+['eject','tail']
        if [c['name']for c in all_commands]!=expected_names: raise ValueError('complete producer sequence')
        if [c['name'] for c in commands]!=['insert','front','eject','tail']: raise ValueError('native action sequence')
        for c in commands:
            battery=c['name'] in ('insert','eject')
            if (c['type']!=('ISDeviceBatteryAction' if battery else 'ISReadABook') or c['started'] is not True or c['progress'] is not True
                or c['producer']!=('native RWMPower callback' if battery else 'native ISReadABook constructor')
                or not tv._number(c['duration']) or c['duration']<=0 or battery and c['duration']!=30): raise ValueError('native action evidence')
        if any(not tv._number(c.get('startedAt')) for c in commands) or [c['startedAt'] for c in commands]!=sorted(c['startedAt'] for c in commands): raise ValueError('native start order')
        expected=[]
        if selection['kind']=='mp':
            for c in (commands[0],commands[2]):
                ack=c['ack']
                if ack['kind']!='ISDeviceBatteryAction' or ack['state']!='completed' or type(ack['transaction']) is not int or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}',str(ack['token'])): raise ValueError('native ACK')
                expected.extend(dict(case=case,name=c['name'],kind=ack['kind'],transaction=ack['transaction'],token=ack['token'],state=state) for state in ('started','completed'))
            if commands[0]['ack']['token']==commands[2]['ack']['token']: raise ValueError('reused ACK')
        if acks!=expected: raise ValueError('wire receipts')
    except (KeyError,TypeError,ValueError,IndexError,ZeroDivisionError) as error:
        issues.append('Battery binding evidence differs: '+str(error))
    return issues


def verify(root, selection, catalog):
    issues=[];outcomes=[];root=Path(root)
    try:
        text=(root/'client1-launch.log').read_text(errors='replace')
        authority=(root/'server-launch.log').read_text(errors='replace') if selection['kind']=='mp' else text
        events=[e for e in report.events(text) if e.get('suite')=='device-battery-binding']
        rows=[e for e in events if e.get('event')=='case'];setups=[e for e in events if e.get('event')=='setup'];ends=[e for e in events if e.get('event')=='complete']
        prepared,baseline,verified=(_raw(authority,m) for m in ('PREPARED','BASELINE','VERIFIED'))
        placements=_raw(text,'CLIENT_PLACEMENT');acks=_raw(text,'ACK')
        cases=list(CASES)
        if (len(setups)!=1 or len(ends)!=1 or [r.get('id') for r in rows]!=cases
            or any([r.get('case') for r in values]!=cases for values in (prepared,baseline,verified,placements))):
            raise ValueError('missing, duplicate or out-of-order case/authority evidence')
        if (setups[0].get('cases')!=cases or setups[0].get('queueEnabled') is not (selection['mode']=='toolkit') or setups[0].get('nativeDurations') is not True
            or ends[0].get('cases')!=cases or ends[0].get('performed')!=len(cases) or ends[0].get('failed')!=0 or ends[0].get('skipped')!=0):
            raise ValueError('setup or completion evidence')
        for i,case in enumerate(cases):
            row=rows[i]
            if (row.get('actor')!='client1' or row.get('kind')!=selection['kind'] or row.get('mode')!=selection['mode']
                or placements[i]!={'case':case,'proof':row.get('clientPlacement')}): raise ValueError('actor or placement evidence')
            errors=check_case(row,selection,prepared[i],baseline[i],verified[i],[ack for ack in acks if ack.get('case')==case]);issues+=errors
            outcomes.append(dict(actor='client1',case=case,status='failed' if errors else 'passed',reason='; '.join(errors),
                outcome=dict(effectsVerified=not errors,serverAuthorityVerified=not errors,tailCompleted=not errors)))
        if any(ack.get('case') not in cases for ack in acks): raise ValueError('unknown-case ACK')
        if not complete(selection,'client1',text): issues.append('Missing completion marker')
    except (OSError,ValueError,KeyError,TypeError) as error: issues.append(str(error))
    return {'issues':issues,'outcomes':outcomes,'evidence':{'limits':['Programmatic native RWMPower callbacks; physical input is not covered.']}}
