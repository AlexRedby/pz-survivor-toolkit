"""Conservation and native interruption gates for unavailable Fitness storage."""
import copy
import math
from .fitness import _matches, _same, _number, _inventory, _clinical

CASES = ('storage-walk-away', 'storage-peer-pickup')


def _object(value):return value if isinstance(value,dict) else {}


def _position(value):
    return isinstance(value,dict) and all(_number(value.get(k)) for k in ('x','y','z'))


def _near(a,b):
    return _position(a) and _position(b) and a['z']==b['z'] and max(abs(a['x']-b['x']),abs(a['y']-b['y']))<=.25


def _pickup_range(value,origin):
    return (_position(value) and value['z']==origin['z']
            and abs(math.floor(value['x'])-origin['x'])<=1 and abs(math.floor(value['y'])-origin['y'])<=1)


def _topology(value, spec, bag_endpoint, partial=False, prepared=False):
    if not isinstance(value,dict) or not _position(value.get('position')) or not isinstance(value.get('resources'),list):
        return False
    owner={'world':'world','client1-root':'client1','client2-root':'client2'}[bag_endpoint]
    expected=[]
    for name,container,who in [('bag',bag_endpoint,owner),('content',spec['bag']['id'],owner),('prop','client1-root','client1')]:
        ref=spec[name]
        if prepared and name=='prop':container=spec['bag']['id']
        if partial and name!='prop':continue
        row=dict(id=ref['id'],kind=ref['kind'],container=container,owner=who,favorite=ref['favorite'])
        if name=='bag' and bag_endpoint=='world':row['world']=dict(**spec['origin'],linked=True)
        expected.append(row)
    expected.sort(key=lambda row:(row['id'],row['owner']))
    return _same(value['resources'],expected)


def verify_negative(case,row,prep,receipt,selection):
    issues=[]
    def fail(message):issues.append('Fitness negative storage '+message+': '+case)
    mp=selection['kind']=='mp';managed=selection['mode']=='toolkit';walk=case=='storage-walk-away'
    ids=prep.get('items',{});spec=_object(prep.get('negativeStorage'));command=_object(row.get('command'))
    if (set(ids)!=set(('front','tail','bag','hammer','screwdriver','dumbbell'))
            or any(type(v)is not int for v in ids.values()) or len(set(ids.values()))!=6
            or not _inventory(prep.get('inventory')) or not _clinical(prep.get('before'))
            or not isinstance(spec,dict) or not isinstance(spec.get('origin'),dict)
            or set(spec['origin'])!={'x','y','z'} or any(type(v)is not int for v in spec['origin'].values())
            or any(not _matches(spec.get(n),dict(id=ids[key],kind=kind,favorite=fav)) for n,key,kind,fav in (
                ('bag','bag','Base.Bag_Schoolbag',True),('prop','dumbbell','Base.DumbBell',True),('content','front','Base.BookCarpentry1',False)))):
        return ['Fitness negative storage preparation differs: '+case]
    if not walk and not mp:fail('competition requires actual Host')
    if receipt.get('violations')!=[]:fail('native observer reported violations')
    if not _topology(prep.get('negativeBefore'),spec,'client1-root',prepared=True):fail('initial exact resources differ')
    initial=prep['inventory'];expected=copy.deepcopy(initial)
    expected['items']=[dict(item,container='root') if item['id']==ids['dumbbell'] else item for item in expected['items'] if item['id'] not in (ids['bag'],ids['front'])]
    expected['worn']=[entry for entry in expected['worn'] if entry['id']!=ids['bag']]
    actual=receipt.get('inventory',{})
    if walk and isinstance(actual,dict):
        expected['primary']=actual.get('primary');expected['secondary']=actual.get('secondary')
        if actual.get('primary') not in (False,ids['hammer'],ids['dumbbell']) or actual.get('secondary') not in (False,ids['screwdriver']):fail('unproved interrupted hand item')
    if not _inventory(actual) or not _same(actual,expected) or not _same(command.get('clientInventory'),expected):fail('actor inventory or original tools differ')
    endpoint='world' if walk else 'client2-root'
    if not _topology(receipt.get('negativeStorage'),spec,endpoint):fail('authority conservation or ownership differs')
    if not _topology(command.get('negativeFinal'),spec,endpoint,partial=not walk):fail('local exact topology differs')
    if (not _matches(row,dict(status='passed',reason=None)) or not _matches(command,dict(menuDispatched=True,nativeDurations=True,
            minutes=10,frontMinutes=0,activeObserved=True,queueDrained=True,clientCurrentExerciseCleared=True,
            pendingCancelled=False,reordered=False,activeCancelled=False,closedUI=False,startedOrder=['bicepscurl']))
            or not _matches(receipt,dict(case=case,tailRead=True,frontRead=False,removed=False,currentExerciseCleared=True,serverStopSettled=True,peerConnected=True))
            or not _same(receipt.get('before'),prep['before']) or not _number(receipt.get('serverSettleMilliseconds')) or receipt['serverSettleMilliseconds']<2000
            or type(command.get('nativeStopCalls'))is not int or command.get('nativeStopCalls')!=1 or type(command.get('nativeStopReturns'))is not int or command.get('nativeStopReturns')!=1):fail('native request or settled stop/reader differs')
    records=receipt.get('records',[])
    if not isinstance(records,list) or len(records)!=1:return issues+['Fitness negative storage requires one real workout: '+case]
    record=_object(records[0]);before=record.get('before');after=record.get('after');rep=record.get('lastRep')
    if (not _matches(record,dict(exercise='bicepscurl',minutes=10,maxTime=5000000,previousStopSettled=True,currentExerciseCleared=True,serverStopReturned=True,
            stopMethod='serverStop' if mp else 'observed-native-removal'))
            or type(record.get('reps'))is not int or record['reps']<=0
            or not all(_clinical(value)for value in (before,after,rep))):fail('native paid workout evidence differs')
    else:
        if (record.get('minEndurance',1)>=before['endurance']
                or sum(rep[k] for k in ('fitnessXP','strengthXP'))<=sum(before[k]for k in ('fitnessXP','strengthXP'))
                or any(after[k]<rep[k]for k in ('fitnessXP','strengthXP'))
                or rep['regularity'].get('bicepscurl',0)<=before['regularity'].get('bicepscurl',0)
                or rep['stiffness'].get('arms',0)<=before['stiffness'].get('arms',0)):fail('missing real training effects/costs')
    final_clinical=receipt.get('clinical')
    if (not all(_clinical(value)for value in (rep,after,final_clinical))
            or any(rep[key]!=after[key] or after[key]!=final_clinical[key]for key in ('fitnessXP','strengthXP'))):
        fail('native paid XP endpoints disagree')
    if not _topology(record.get('negativeStorage'),spec,'world'):fail('workout began without paid world placement')
    body=copy.deepcopy(expected);body.update(primary=ids['dumbbell'],secondary=False)
    if not _same(record.get('startEquipment'),body):fail('body started without exact borrowed prop and ordinary items')
    placements=receipt.get('placements')
    placed=placements[0] if isinstance(placements,list) and len(placements)==1 else {}
    storage=_object(placed.get('storage')) if isinstance(placed,dict) else {}
    if (not _matches(placed,dict(callback='ISDropWorldItemAction.complete',succeeded=True))
            or not _matches(storage,dict(id=ids['bag'],kind='Base.Bag_Schoolbag',favorite=True,endpoint='world',occurrences=1,
                contents=[dict(id=ids['front'],kind='Base.BookCarpentry1',container=ids['bag'])],world=dict(**spec['origin'],linked=True)))
            or not _number(placed.get('nativeClock')) or not _number(record.get('startMS')) or placed['nativeClock']>record['startMS']):
        fail('exact paid native drop completion missing')
    if mp and (not _matches(record.get('stopCallbacks'),dict(serverStop=1)) or record.get('stopCallbacks',{}).get('complete',0)!=0):fail('server stop replayed or wrong terminal callback')
    if not all(_number(record.get(k))for k in ('durationStartMS','durationStopMS','durationStopFrameGameMS')):fail('independent active interval missing')
    else:
        elapsed=record['durationStopMS']-record['durationStartMS']
        if not 0<record['durationStopFrameGameMS']<60000 or (not 0<elapsed<600000 if walk else elapsed+record['durationStopFrameGameMS']<600000):fail('native interrupted/full duration differs')
    stop=_object(command.get('negativeStop'))
    if not _matches(stop,dict(callback='ISFitnessAction.stop')) or not _matches(stop.get('state'),dict(type='ISFitnessAction',exercise='bicepscurl',minutes=10,started=True)):fail('exact local native stop missing')
    if managed:
        samples=command.get('progressSamples',[])
        if not isinstance(samples,list)or len(samples)!=1 or not all(_number(samples[0].get(k))for k in ('total','elapsed','fraction')) or not 0<samples[0].get('fraction',0)<=1 or samples[0].get('total')!=10:fail('real visible progress missing')
        if mp and (len(command.get('activeAcks',[]))!=1 or not walk and (len(command.get('terminalAcks',[]))!=1 or command['activeAcks'][0]!=command['terminalAcks'][0].get('token'))):fail('matching native acknowledgements missing')
    if walk:
        witness=_object(command.get('walkAway'));fresh=_object(command.get('freshReader'))
        if (not _matches(witness,dict(producer='ISWalkToCursor.create',maxTime=-1,nativeStarted=True,nativeBegin=True,nativeCompleted=True,nativeResult='Succeeded',nativePerformCalls=1,oldTailCancelled=True))
                or not _number(witness.get('maxDisplacement'))or witness['maxDisplacement']<2
                or not _position(witness.get('before'))or not _position(witness.get('after'))
                or not isinstance(witness.get('destination'),dict)
                or not _matches(fresh,dict(callback='ISInventoryPaneContextMenu.onLiteratureItems'))
                or not _topology(command.get('afterWalk'),spec,'world')or not _same(fresh.get('snapshot'),command.get('afterWalk'))
                or not _topology(command.get('negativeBeforeTail'),spec,'world')):fail('real cursor interruption/arrival/fresh reader missing')
        begin=_object(fresh.get('begin'));tail_snapshot=_object(command.get('negativeBeforeTail'))
        if (command.get('oldTailStarted',False) is not False
                or not _matches(begin,dict(callback='ISBaseTimedAction.begin',id=ids['tail'],kind='Base.BookFirstAid1'))
                or not _same(begin.get('snapshot'),tail_snapshot)
                or not all(_number(value)for value in (witness.get('completedAt'),fresh.get('timestampMS'),begin.get('timestampMS'),witness.get('tailPages'),witness.get('tailTotal'),fresh.get('pages'),fresh.get('total')))
                or not 0<=witness.get('tailPages',-1)<witness.get('tailTotal',0)
                or not witness.get('tailPages')==fresh.get('pages')<fresh.get('total',0)==witness.get('tailTotal')
                or not witness.get('completedAt',float('inf'))<=fresh.get('timestampMS',-1)<=begin.get('timestampMS',-1)
                or not _near(tail_snapshot.get('position'),_object(command.get('afterWalk')).get('position'))
                or not _near(witness.get('after'),_object(command.get('afterWalk')).get('position'))
                or not _position(witness.get('before'))or not _position(witness.get('after'))
                or math.hypot(witness['after']['x']-witness['before']['x'],witness['after']['y']-witness['before']['y'])<2
                or math.hypot(witness['after']['x']-witness['before']['x'],witness['after']['y']-witness['before']['y'])>witness.get('maxDisplacement',-1)+.01):fail('new reader or measured walk chronology differs')
        positions=[receipt.get('negativeStorage',{}).get('position'),command.get('afterWalk',{}).get('position')]
        if any(not _position(p)or p['z']!=spec['origin']['z']or max(abs(p['x']-spec['origin']['x']-.5),abs(p['y']-spec['origin']['y']-.5))<2 for p in positions):fail('actor never left native pickup range')
        destination=_object(witness.get('destination'));arrival=witness.get('after')
        if (not _matches(witness,dict(tailId=ids['tail']))
                or set(destination)!={'x','y','z'} or any(type(destination.get(k))is not int for k in ('x','y','z'))
                or destination.get('z')!=spec['origin']['z'] or not _position(witness.get('before'))
                or witness['before']['z']!=spec['origin']['z'] or not _position(arrival)
                or arrival['z']!=destination.get('z') or math.floor(arrival['x'])!=destination.get('x')
                or math.floor(arrival['y'])!=destination.get('y')):fail('walk original reader or destination arrival differs')
    else:
        grant=_object(receipt.get('peerGrant'));picked=_object(receipt.get('peerPickup'));proof=_object(picked.get('proof'))
        expected_content=[dict(id=ids['front'],kind='Base.BookCarpentry1',container=ids['bag'])]
        if (type(grant.get('reps'))is not int or grant['reps']<=0 or not _topology(grant.get('snapshot'),spec,'world')
                or not _topology(picked.get('snapshot'),spec,'client2-root')
                or not _matches(proof,dict(phase='picked',id=ids['bag'],kind='Base.Bag_Schoolbag',favorite=True,contents=expected_content,callbacks=1,queueDrained=True,origin=spec['origin']))
                or not _matches(proof.get('pickupStart'),dict(callback='ISBaseTimedAction.begin',id=ids['bag'],kind='Base.Bag_Schoolbag',source='world',destination='peer-root',origin=spec['origin']))
                or not _matches(proof.get('transaction'),dict(callback='ISInventoryTransferAction.perform',completed=True,rejected=False,id=ids['bag'],kind='Base.Bag_Schoolbag',source='world',destination='peer-root'))
                or type(_object(proof.get('transaction')).get('transactionId'))is not int or proof['transaction']['transactionId']==0
                or type(proof.get('callbacks'))is not int
                or type(picked.get('onlineID'))is not int or picked['onlineID']!=prep.get('peerOnlineID')or grant.get('peerOnlineID')!=picked['onlineID']
                or proof.get('walkRequired')is True and not _matches(proof,dict(walkStarted=True,walkMoved=True,walkFinished=True))):fail('source-bound peer native pickup evidence differs')
        if not _topology(command.get('negativeBeforeTail'),spec,'client2-root',partial=True)or not _topology(_object(receipt.get('tailStart')).get('negativeStorage'),spec,'client2-root'):fail('independent reader precedes proven ownership')
        pickup_start=_object(proof.get('pickupStart'));transaction=_object(proof.get('transaction'))
        picked_position=_object(picked.get('snapshot')).get('peerPosition')
        grant_position=_object(grant.get('snapshot')).get('peerPosition')
        final_position=_object(receipt.get('negativeStorage')).get('peerPosition')
        local_position=_object(proof.get('snapshot')).get('position')
        if (not all(_pickup_range(value,spec['origin'])for value in (pickup_start.get('position'),proof.get('position'),grant_position,picked_position,final_position,local_position))
                or not all(_near(proof.get('position'),value)for value in (pickup_start.get('position'),grant_position,picked_position,final_position,local_position))
                or not _matches(grant_position,dict(onlineID=prep.get('peerOnlineID')))
                or not _matches(picked_position,dict(onlineID=prep.get('peerOnlineID')))
                or not _matches(final_position,dict(onlineID=prep.get('peerOnlineID')))
                or not _matches(local_position,dict(onlineID=prep.get('peerOnlineID')))
                or not all(_number(value)for value in (pickup_start.get('timestampMS'),transaction.get('timestampMS')))
                or pickup_start['timestampMS']>transaction['timestampMS']):fail('peer native reach or pickup chronology differs')
    return issues
