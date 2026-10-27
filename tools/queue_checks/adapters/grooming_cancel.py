"""Native waiting/active grooming cancellation, tool debt and unchanged styling costs."""
import copy
import json
import math
from pathlib import Path
import re
import shutil
import struct
from .tv_controls import MODS

CASES=['borrowed-scissors','style-no-tool','styled-scissors','beard-trim','dye-hair','dye-beard']
ACTIVE_CASES=['active-'+case for case in CASES]
ALL_CASES=CASES+ACTIVE_CASES
def base_case(case):return case.removeprefix('active-')
HAIRCUT=set(CASES[:3])
BODY={case:('ISCutHair' if case in HAIRCUT else 'ISTrimBeard' if case=='beard-trim' else 'ISDyeHair') for case in CASES}
PRODUCER={'ISCutHair':'ISCharacterScreen.onCutHair','ISTrimBeard':'ISCharacterScreen.onTrimBeard','ISDyeHair':'ISInventoryPaneContextMenu.onDyeHair'}
BORROWED={case:('scissors' if case in ('borrowed-scissors','styled-scissors') else 'razor' if case=='beard-trim' else 'dye' if case.startswith('dye-') else False) for case in CASES}
def duration(case):return 100 if case=='style-no-tool' else 120 if case.startswith('dye-') else 300
PREFIX='[GROOMING_TEST] '


def definitions():
    return {'grooming-cancel':dict(status='ready',clients=1,default_mods=list(MODS),
        scenario_actions={'native-haircut':dict(scope='Actual character-screen haircut/beard and inventory dye producers; waiting deletion after native scissors pickup or behind a reader; active cancellation after native body progress and sealed Host started receipt. Source-bound callbacks, exact borrowed tool return, native P4 idle hands/headwear restoration, appearance and gel conservation. Host completion uses sealed native transaction plus authority outputs; direct remote callback counts unavailable.',
            checks={'cancel-waiting':{case:dict(cancelled=True,cleanupVerified=True) for case in CASES},
                    'cancel-active':{case:dict(cancelled=True,cleanupVerified=True,activeCancelVerified=True) for case in ACTIVE_CASES},
                    'server-authority':{case:dict(authoritative=True) for case in ALL_CASES}},toolkit_only=['cancel-waiting','cancel-active'])},
        cases=[dict(id=case,producer='native-haircut',capability='effect',kinds=['sp','mp'],modes=['native','toolkit'],languages=['EN']) for case in ALL_CASES])}


def validate(selection):
    cases=selection.get('cases')
    if (type(cases) is not list or not cases or cases!=[case for case in ALL_CASES if case in cases]
            or selection.get('kind') not in ('sp','mp') or selection.get('mode') not in ('native','toolkit')
            or selection.get('mods')!=MODS or selection.get('languages')!=['EN']
            or type(selection.get('clients')) is not int or selection['clients']!=1
            or selection.get('options',{}).get('world_template')
            or selection['kind']=='mp' and selection.get('options',{}).get('mp_host') is not True):
        raise ValueError('Grooming cancellation requires ordered cases, one EN actor, fresh full-pack SP/menu Host and native/toolkit mode')


def sources(project, selection):
    root=Path(project)/'tests/native_queue'
    return [*sorted((root/'grooming-cancel').rglob('*.lua')), *sorted((root/'startup').rglob('*.lua')),
            root/'health/shared/QueueHealthEvents.lua',root/'support/QueueEnergyPlacement.lua',Path(__file__).with_name('tv_controls.py')]


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection);root=Path(project)/'tests/native_queue'
    for role in runtime['roles'].values():
        lua=Path(role['cache'])/'mods/ActionQueueTest/42/media/lua'
        for side,name in [('client','ZZStartup.lua'),('server','ZZStartupServer.lua')]:shutil.copy2(root/'startup'/side/name,lua/side/name)
        shutil.copy2(root/'health/shared/QueueHealthEvents.lua',lua/'shared')
    runtime.setdefault('fixture',{}).update(server_ready='[GROOMING_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL grooming-cancel'],sandbox={'Zombies':6,'MinutesPerPage':2.0})


def raw(text,marker):
    return [json.loads(match[1]) for match in re.finditer(re.escape(PREFIX+marker+' ')+r'([^\n]+)',text)]


def complete(selection,role,text):
    try:return role=='client1' and raw(text,'COMPLETE')==[{'cases':selection['cases']}]
    except (ValueError,TypeError):return False


def number(value):return type(value) in (int,float) and math.isfinite(value)


def snapshot(value,case):
    if (type(value) is not dict or value.get('case')!=case or type(value.get('items')) is not list
            or value.get('male') is not True or type(value.get('worn')) is not list or type(value.get('torchActive')) is not bool
            or any(type(value.get(key)) is not int for key in ('frontPages','tailPages'))):return False
    ids=[]
    for item in value['items']:
        if (type(item) is not dict or set(item)!={'id','kind','container','favorite'} or type(item['id']) is not int
                or not isinstance(item['kind'],str) or not item['kind'] or type(item['favorite']) is not bool
                or not (item['container']=='root' or type(item['container']) is int)):return False
        ids.append(item['id'])
    if len(ids)!=len(set(ids)) or ids!=sorted(ids):return False
    parents={item['id']:item['container'] for item in value['items']}
    for item in ids:
        visited=set();current=item
        while parents[current]!='root':
            if current in visited or parents[current] not in parents:return False
            visited.add(current);current=parents[current]
    if any(type(row) is not dict or set(row)!={'id','location'} or type(row['id']) is not int or row['id'] not in ids
           or not isinstance(row['location'],str) for row in value['worn']):return False
    if len({row['location'] for row in value['worn']})!=len(value['worn']):return False
    if any(value.get(key) is not False and (type(value.get(key)) is not int or value[key] not in ids) for key in ('primary','secondary')):return False
    appearance=value.get('appearance',{});color=appearance.get('color',{})
    return (set(appearance)=={'model','nonAttached','color','beardModel','beardColor'} and isinstance(appearance['model'],str) and bool(appearance['model'])
            and (appearance['nonAttached'] is False or isinstance(appearance['nonAttached'],str))
            and set(color)=={'r','g','b'} and all(number(v) and 0<=v<=1 for v in color.values())
            and isinstance(appearance['beardModel'],str) and valid_color(appearance['beardColor'])
            and (value.get('dye') is False or type(value.get('dye')) is dict and set(value['dye'])=={'id','amount','color'}
                 and type(value['dye']['id']) is int and value['dye']['id'] in ids and number(value['dye']['amount'])
                 and 0<=value['dye']['amount']<=1 and valid_color(value['dye']['color'])))


def restored(value,base):
    return all(value.get(key)==base.get(key) for key in ('items','worn','primary','secondary')) and value.get('torchActive') is True


def valid_color(value):
    return type(value) is dict and set(value)=={'r','g','b'} and all(number(v) and 0<=v<=1 for v in value.values())


def wire_color(color):
    # Current B42.21 HumanVisual.save/get*Byte uses float32*255 truncated to int;
    # load constructs ImmutableColor(int,int,int), dividing each byte by255f.
    f32=lambda value:struct.unpack('f',struct.pack('f',value))[0]
    return {key:f32(int(f32(f32(value)*255))/255) for key,value in color.items()}


def fluid_wire_color(color):
    f32=lambda value:struct.unpack('f',struct.pack('f',value))[0]
    return {key:f32((int(f32(f32(f32(value)*255)-128))+128)/255) for key,value in color.items()}


def expected_appearance(base,ids,native,remote=False,authority=None):
    result=copy.deepcopy(base['appearance'])
    if not native:return result
    if ids['actionKind']=='ISCutHair':result.update(model=ids['targetStyle'],nonAttached=ids['initialStyle'] if ids['targetAttached'] else False)
    elif ids['actionKind']=='ISTrimBeard':result['beardModel']=ids['targetBeard']
    else:result['color' if base_case(ids['case'])=='dye-hair' else 'beardColor']=wire_color((authority or base)['dye']['color']) if remote else copy.deepcopy(base['dye']['color'])
    return result


def appearance_matches(actual,expected,ids,native,remote=False):
    if not (native and remote and ids['actionKind']=='ISDyeHair'):return actual==expected
    key='color' if base_case(ids['case'])=='dye-hair' else 'beardColor'
    # Permit only float32/JSON presentation error around the one exact native
    # byte transform, not arbitrary cross-role color drift.
    return (set(actual)==set(expected) and all(actual[k]==v for k,v in expected.items() if k!=key)
            and valid_color(actual[key]) and all(abs(actual[key][k]-v)<=1e-6 for k,v in expected[key].items()))


def check_case(row,selection,prepared,authority):
    selected=row['id'];case=base_case(selected);active=selected in ACTIVE_CASES;native=selection['mode']=='native';mp=selection['kind']=='mp';expected=1 if native else 0
    ids,base,command,receipt=row['ids'],row['baseline'],row['command'],row['receipt']
    assert ids==prepared and receipt==authority,'authority marker/row differs'
    assert ids['duration']==duration(case) and ids['actionKind']==BODY[case] and ids['producer']==PRODUCER[BODY[case]] and ids['borrowed']==BORROWED[case] and ids['male'] is True
    assert ids['case']==selected and type(ids['items']) is dict and len(set(ids['items'].values()))==len(ids['items'])
    required={'bag','content','front','tail','torch','secondary'}|({BORROWED[case]} if BORROWED[case] else set())|({'hat'} if case in ('borrowed-scissors','dye-hair') else set())|({'mask'} if case=='dye-beard' else set())|({'gel'} if case=='styled-scissors' else set())
    assert set(ids['items'])==required and set(ids['types'])==required,'exact seeded identities missing'
    types=dict(bag='Base.Bag_Schoolbag',content='Base.Paperclip',front='Base.BookCarpentry1',tail='Base.BookFirstAid1',torch='Base.Torch',secondary='Base.Screwdriver',scissors='Base.Scissors',hat='Base.Hat_BaseballCap',gel='Base.Hairgel',razor='Base.Razor',dye='Base.HairDyeCommon',mask='Base.Hat_DustMask')
    assert ids['types']=={name:types[name] for name in required},'fixture item types changed'
    assert all(type(item) is int for item in ids['items'].values())
    assert (ids['initialStyle']!=ids['targetStyle'] if case in HAIRCUT else ids['initialStyle']==ids['targetStyle']) and number(ids['initialLevel']) and number(ids['targetLevel']) and ids['initialLevel']>=ids['targetLevel']
    assert type(ids['targetAttached']) is bool and ids['targetAttached']==(case=='style-no-tool')
    assert case!='styled-scissors' or ids['targetStyle']=='MohawkFan'
    assert case!='borrowed-scissors' or ids['targetStyle'] in ('CrewCut','Bob')
    assert all(word not in ids['initialStyle'] for word in ('Bald','Mohawk','Spike','Greased','Buffont'))
    assert all(type(ids[key]) is int for key in ('frontTotal','frontInitial','tailTotal','tailInitial'))
    assert ids['frontTotal']>3 and ids['frontInitial']==ids['frontTotal']-3 and ids['tailTotal']>1 and ids['tailInitial']==ids['tailTotal']-1
    assert row['nativeMethodsUnchanged'] is True and command['producer']==PRODUCER[BODY[case]] and command['duration']==duration(case)
    assert ids['initialBeard']==('LongScruffy' if case not in HAIRCUT else False)
    assert ids['targetBeard']==('Moustache' if case=='beard-trim' else False)
    if case=='beard-trim':assert ids['beardInitialLevel']==3 and ids['beardTargetLevel']==1
    else:assert ids['beardTargetLevel'] is False
    assert command['cancelled'] is (not native) and command['frontQueued'] is (case=='style-no-tool')
    all_snapshots=[ids['baseline'],base,receipt['baseline'],receipt['checkpoint'],receipt['final'],row['clientFinal'],command['boundary']['snapshot'],command['beforeTail']['snapshot'],command['idle']['snapshot']]
    assert all(snapshot(value,selected) for value in all_snapshots),'malformed/duplicate item snapshot'
    assert restored(base,ids['baseline']) and restored(receipt['baseline'],ids['baseline'])
    for baseline_role,initial in enumerate((base,receipt['baseline'])):
        assert initial['appearance']['model']==ids['initialStyle'] and initial['appearance']['nonAttached'] is False
        assert initial['primary']==ids['items']['torch'] and initial['secondary']==ids['items']['secondary']
        lookup={item['id']:item for item in initial['items']}
        assert all(lookup[item]['kind']==ids['types'][name] for name,item in ids['items'].items())
        assert all(lookup[item]['container']==(ids['items']['bag'] if name in ('content','scissors','razor','dye') else 'root') for name,item in ids['items'].items()),'seeded item topology changed'
        assert lookup[ids['items']['bag']]['favorite'] is True
        borrowed=BORROWED[case]
        if borrowed:assert lookup[ids['items'][borrowed]]['container']==ids['items']['bag'] and lookup[ids['items'][borrowed]]['favorite'] is True
        if case not in HAIRCUT:assert initial['appearance']['beardModel']==ids['initialBeard']
        if case.startswith('dye-'):
            assert initial['dye']['id']==ids['items']['dye'] and initial['dye']['amount']==1
            expected_color=fluid_wire_color(ids['baseline']['dye']['color']) if mp and baseline_role==0 else ids['baseline']['dye']['color']
            assert all(abs(initial['dye']['color'][k]-v)<=1e-6 for k,v in expected_color.items()),'native item fluid color serialization differs'
        else:assert initial['dye'] is False
        assert initial['frontPages']==ids['frontInitial'] and initial['tailPages']==ids['tailInitial']
        if case=='styled-scissors':assert initial['gel']==dict(id=ids['items']['gel'],uses=20)
        else:assert initial['gel'] is False
    boundary=command['boundary'];before=command['beforeTail'];idle=command['idle']
    assert boundary['case']==selected and boundary['mode']==selection['mode'] and boundary['accepted'] is (not native)
    assert boundary['reason'] is False and boundary['started'] is True and boundary['bodyUnallocated'] is (not active) and boundary['tailRetained'] is True
    assert number(boundary['progress']) and 0<boundary['progress']<=1
    assert boundary['kind']==(BODY[case] if active else 'ISReadABook' if case=='style-no-tool' else 'ISInventoryTransferAction')
    assert boundary['item']==(ids['items'].get(BORROWED[case],False) if active else ids['items']['front' if case=='style-no-tool' else BORROWED[case]])
    assert boundary['snapshot']['appearance']==base['appearance'] and boundary['snapshot']['gel']==base['gel'] and boundary['snapshot']['dye']==base['dye']
    assert all(number(value.get('at')) for value in (boundary,before,idle)) and boundary['at']<before['at']<=idle['since']<=idle['at']
    assert idle['at']-idle['since']>=2000 and idle['empty'] is True and before['callback']=='ISBaseTimedAction.begin'
    assert before['case']==idle['case']==selected
    assert before['snapshot']['tailPages']==ids['tailInitial'],'tail effect preceded its begin witness'
    assert type(command['bodyStarts']) is int and command['bodyStarts']==(1 if active else expected)
    assert type(command['bodyCompletes']) is int and command['bodyCompletes']==expected
    assert command['completeCountProof']==('sealed-native-transaction' if mp else 'shared-native-complete')
    records=command['records'];assert type(records) is list and [record['sequence'] for record in records]==list(range(1,len(records)+1))
    bodies=[record for record in records if record['role']=='body'];assert len(bodies)==1
    body=bodies[0];assert body['kind']==BODY[case] and body['item']==ids['items'].get(BORROWED[case],False) and body['constructorDuration']==ids['duration']
    assert type(body['starts']) is int and body['starts']==(1 if active else expected) and body['started'] is (native or active)
    observed=[record for record in records if record['role']==('body' if active else 'front' if case=='style-no-tool' else 'prepare') and record['kind']==boundary['kind'] and record['item']==boundary['item']]
    assert len(observed)==1 and observed[0]['started'] is True and type(observed[0]['starts']) is int and observed[0]['starts']==1,'boundary action was not actually observed started'
    if mp:
        assert receipt['bodyCompletes'] is False and receipt['bodyRecords']==[]
        assert receipt['completeCountProof']=='unavailable-remote-callback' and receipt['completeCountLimit']
    else:
        assert type(receipt['bodyCompletes']) is int and receipt['bodyCompletes']==expected and receipt['bodyRecords']==records and receipt['completeCountProof']=='shared-native-complete'
    if native:
        assert isinstance(body['nativeRef'],str) and body['nativeRef']
        assert number(body.get('startedAt')) and (body['startedAt']<=boundary['at'] if active else body['startedAt']>=boundary['at']),'haircut start/checkpoint order differs'
        assert sum(end['phase']=='perform' and end['succeeded'] is True for end in body['finishes'])==1
        if mp:
            assert type(body['transaction']) is int and -128<=body['transaction']<=127 and body['transaction']!=0
            assert isinstance(body['token'],str) and re.fullmatch(r'[\da-fA-F]{8}(?:-[\da-fA-F]{4}){3}-[\da-fA-F]{12}',body['token'])
            assert body['terminal']=='completed' and receipt['bodyCompletes'] is False and receipt['bodyRecords']==[]
            assert receipt['completeCountProof']=='unavailable-remote-callback' and receipt['completeCountLimit']
        else:assert sum(end['phase']=='complete' and end['succeeded'] is True for end in body['finishes'])==1
    elif active:
        assert isinstance(body['nativeRef'],str) and body['nativeRef']
        assert number(body.get('startedAt')) and body['startedAt']<=boundary['at']
        assert body['finishes']==[],'active grooming perform/complete/replay differs'
        removal=body['stoppedRemoval']
        assert set(removal)=={'at','nativeRef','queueAbsent','nativeAbsent','finished','forceComplete'}
        assert removal['nativeRef']==body['nativeRef']and removal['queueAbsent'] is True and removal['nativeAbsent'] is True
        assert removal['finished'] is False and removal['forceComplete'] is False
        assert number(removal['at'])and boundary['at']<=removal['at']<=idle['at']
        if mp:assert body['terminal']=='canceled'
        else:assert body['terminal'] is False and body['transaction'] is False and body['token'] is False
    else:
        assert body['nativeRef'] is False and body['finishes']==[] and body['terminal'] is False and body['transaction'] is False and body['token'] is False
        if not mp:assert receipt['bodyCompletes']==0
    if active:
        assert boundary['stage']=='active'
        if mp:
            started=boundary['startedReceipt'];trace=command['outcomes']
            assert type(started) is dict and set(started)=={'transaction','kind','token','state'}
            assert started==dict(transaction=body['transaction'],kind=BODY[case],token=body['token'],state='started')
            assert type(body['transaction']) is int and -128<=body['transaction']<=127 and body['transaction']!=0
            assert isinstance(body['token'],str) and re.fullmatch(r'[\da-fA-F]{8}(?:-[\da-fA-F]{4}){3}-[\da-fA-F]{12}',body['token'])
            assert type(trace) is list and len(trace)==2
            assert trace==[dict(protocol=1,player=ids['actor'],**started),dict(protocol=1,player=ids['actor'],**dict(started,state='completed' if native else 'canceled'))],'authority body receipt identity/order/replay differs'
        else:assert boundary['startedReceipt'] is False and command['outcomes']==[]
    elif boundary.get('stage','waiting')!='waiting':raise AssertionError('waiting stage differs')
    assert all(end['succeeded'] is True and number(end['at']) for record in records for end in record['finishes'])
    for role in ('tail',):
        matching=[record for record in records if record['role']==role]
        assert len(matching)==1 and matching[0]['item']==ids['items'][role]
    if BORROWED[case]:
        borrowed_id=ids['items'][BORROWED[case]]
        returns=[record for record in records if record['role']=='return' and record['item']==borrowed_id]
        assert len(returns)==1 and sum(end['phase']=='perform' and end['succeeded'] is True for end in returns[0]['finishes'])==1
        if not native:
            assert all(end['at']<=before['at'] for end in returns[0]['finishes']),'required return did not finish before independent tail'
        else:
            assert all(end['at']>=before['at'] for end in returns[0]['finishes']),'native P4 return preceded the independent tail'
        assert any(item['id']==borrowed_id and item['container']==('root' if native else ids['items']['bag']) for item in before['snapshot']['items'])
    for role,(final,initial) in enumerate(((row['clientFinal'],base),(receipt['final'],receipt['baseline']))):
        assert restored(final,initial),'required inventory/equipment/favorite conservation failed'
        assert appearance_matches(final['appearance'],expected_appearance(initial,ids,native,mp and role==0,receipt['baseline']),ids,native,mp and role==0),'cosmetic state or native color changed'
        if case.startswith('dye-'):
            expected_dye=copy.deepcopy(initial['dye']);expected_dye['amount']-=.5 if native else 0
            assert final['dye']==expected_dye,'exact dye amount/color changed'
        else:assert final['dye'] is False
        assert final['tailPages']==ids['tailTotal'] and final['frontPages']==(ids['frontTotal'] if case=='style-no-tool' else ids['frontInitial'])
        if case=='styled-scissors':assert final['gel']==dict(id=ids['items']['gel'],uses=19 if native else 20)
        else:assert final['gel'] is False
    assert idle['snapshot']==row['clientFinal'],'post-idle state drifted'
    if not native or not mp:
        assert before['snapshot']['appearance']==base['appearance'] and before['snapshot']['gel']==base['gel'] and before['snapshot']['dye']==base['dye'],'pre-tail state conflicts with source-pinned canceled/native SP ordering'
    else:
        assert any(appearance_matches(before['snapshot']['appearance'],expected,ids,True,True) for expected in (base['appearance'],expected_appearance(base,ids,True,True,receipt['baseline']))),'invalid remote appearance before tail'
        if case=='styled-scissors':assert before['snapshot']['gel'] in (base['gel'],dict(id=ids['items']['gel'],uses=19))
        if case.startswith('dye-'):
            paid=copy.deepcopy(base['dye']);paid['amount']-=.5
            assert before['snapshot']['dye'] in (base['dye'],paid)
    if not native:
        assert receipt['checkpoint']['appearance']==receipt['baseline']['appearance'] and receipt['checkpoint']['gel']==receipt['baseline']['gel'] and receipt['checkpoint']['dye']==receipt['baseline']['dye']
    return dict(cancelled=not native,cleanupVerified=True,authoritative=True,nativeEffectsVerified=True,tailCompleted=True,activeCancelVerified=active and not native)


def verify(root,selection,catalog):
    from ..report import events
    root=Path(root);text=(root/'client1-launch.log').read_text(errors='replace')
    authority=(root/'server-launch.log').read_text(errors='replace') if selection['kind']=='mp' else text
    rows=events(text);results=[row for row in rows if row.get('event')=='case'];issues=[];outcomes=[]
    if [row.get('event') for row in rows]!=['setup']+['case']*len(selection['cases'])+['complete'] or [row.get('id') for row in results]!=selection['cases']:
        issues.append('Missing/duplicate/reordered grooming events')
    if not rows or any(row.get(key)!=value for row in rows for key,value in dict(suite='grooming-cancel',kind=selection['kind'],mode=selection['mode'],actor='client1').items()):issues.append('Grooming event context differs')
    if not rows or rows[0].get('nativeDurations') is not True or rows[0].get('queueEnabled') is not (selection['mode']=='toolkit'):issues.append('Grooming timing/queue control missing')
    if not rows or any(rows[-1].get(key)!=value for key,value in dict(cases=selection['cases'],performed=len(selection['cases']),failed=0,skipped=0).items()):issues.append('Grooming completion counts differ')
    prepared=raw(authority,'PREPARED');verified=raw(authority,'VERIFIED')
    stream=[]
    for line in text.splitlines():
        match=re.search(r'\[GROOMING_TEST\] (CANCEL|BEFORE_TAIL|IDLE)\s+([^\n]*)',line)
        if match:stream.append((match[1],json.loads(match[2])))
        elif '[QUEUE_CHECK] ' in line:
            event=json.loads(line.split('[QUEUE_CHECK] ',1)[1])
            if event.get('event')=='case':stream.append(('CASE',event.get('id')))
    expected_stream=[]
    for row in results:
        command=row.get('command',{})
        expected_stream.extend([(marker,command.get(key)) for marker,key in [('CANCEL','boundary'),('BEFORE_TAIL','beforeTail'),('IDLE','idle')]])
        expected_stream.append(('CASE',row.get('id')))
    if stream!=expected_stream:issues.append('Grooming raw publication order differs')
    if raw(authority,'BASELINED')!=[row.get('receipt',{}).get('baseline') for row in results]:issues.append('Authority grooming baseline marker differs')
    for marker in ('CANCEL','BEFORE_TAIL','IDLE'):
        key={'CANCEL':'boundary','BEFORE_TAIL':'beforeTail','IDLE':'idle'}[marker]
        if raw(text,marker)!=[row.get('command',{}).get(key) for row in results]:issues.append('Raw grooming '+marker+' evidence differs')
    expected_outcomes=[dict(case=row['id'],receipt=receipt) for row in results for receipt in row.get('command',{}).get('outcomes',[])]
    if raw(text,'OUTCOME')!=expected_outcomes:issues.append('Authority grooming outcome publication differs')
    publications=[]
    for match in re.finditer(re.escape(PREFIX)+r'(OUTCOME|CANCEL|IDLE) ([^\n]+)',text):
        publications.append((match[1],json.loads(match[2])))
    for row in results:
        if row.get('id') not in ACTIVE_CASES or selection['kind']!='mp':continue
        own=[(marker,value) for marker,value in publications if value.get('case')==row['id']]
        if [marker for marker,_ in own]!=['OUTCOME','CANCEL','OUTCOME','IDLE']:
            issues.append(row['id']+': active authority receipt/checkpoint order differs')
    if len(prepared)!=len(results) or len(verified)!=len(results):issues.append('Authority grooming markers missing/duplicate')
    for index,row in enumerate(results):
        problems=[];outcome={}
        try:
            assert row.get('status')=='passed',row.get('reason','fixture failed')
            outcome=check_case(row,selection,prepared[index],verified[index])
        except (AssertionError,KeyError,TypeError,ValueError,IndexError) as error:problems.append(str(error)or 'grooming evidence differs')
        issues.extend(row.get('id','?')+': '+problem for problem in problems)
        outcomes.append(dict(actor='client1',case=row.get('id'),status='failed' if problems else 'passed',outcome=outcome))
    return dict(issues=issues,outcomes=outcomes)
