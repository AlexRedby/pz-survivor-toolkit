"""Native makeup UI avatar isolation, exact output identities and Host waiting deletion."""
import copy
import json
import os
import subprocess
import zipfile
from pathlib import Path
import re
import shutil
from .tv_controls import MODS

SP_CASES=['preview-close','preview-location','apply-empty','apply-replace']
MP_CASES=SP_CASES+['cancel-waiting','apply-while-preview']
SUPPLY_SP_CASES=['apply-worn-bag','apply-nested-bag','apply-world-container','apply-world-bag']
SUPPLY_MP_CASES=SUPPLY_SP_CASES+['cancel-nested-bag','cancel-world-container']


def cancelling(case):return case.startswith('cancel-')


def cases(selection):
    supply=selection.get('options',{}).get('makeup_supplies') is True
    return (SUPPLY_SP_CASES if selection.get('kind')=='sp' else SUPPLY_MP_CASES) if supply else (SP_CASES if selection.get('kind')=='sp' else MP_CASES)
PREFIX='[MAKEUP_TEST] '
TARGET='Base.MakeUp_Crow'
OLD='Base.MakeUp_RedStripes1'
ALTERNATE='Base.MakeUp_RedStripes2'
DIFFERENT='Base.MakeUp_EyesShadowWhite'
SLOT='base:makeup_eyes'
OTHER_SLOT='base:makeup_eyesshadow'


def labels(case):
    middle=['same-preview','location-cleared','different-preview','closed'] if case=='preview-location' else ['closed'] if case=='preview-close' else ['cancelled','after-body'] if cancelling(case) else ['overlap-preview','after-body','closed'] if case=='apply-while-preview' else ['after-body']
    return ['baseline','preview',*middle,'final']


def definitions():
    checks={name:{case:dict(avatarVerified=True,identityVerified=True,authoritative=True,tailCompleted=True) for case in MP_CASES}
            for name in ('success-queued','server-authority')}
    checks['server-authority'].update({case:dict(avatarVerified=True,identityVerified=True,authoritative=True,tailCompleted=True) for case in SUPPLY_MP_CASES})
    checks['success-empty']={case:dict(avatarVerified=True,identityVerified=True,authoritative=True,tailCompleted=True,emptyQueueVerified=True) for case in SUPPLY_SP_CASES}
    checks['cancel-waiting']={case:dict(cancelled=True,unallocated=True,tailCompleted=True) for case in ['cancel-waiting',*SUPPLY_MP_CASES[4:]]}
    return {'makeup':dict(status='ready',clients=1,default_mods=list(MODS),
        scenario_actions={'native-makeup-ui':dict(checks=checks,toolkit_only=['cancel-waiting'],
            scope='Current full selected pack, fresh macOS SP/menu Host, one EN actor. Real native makeup window/combo/apply/close and avatar model; detached preview rendering and exact root/worn/supply identity checkpoints independently read on Host. SP immediate application; Host native duration-one body behind ordinary front reader in the preview bank; optional makeup_supplies bank covers worn/nested bags and adjacent native crate/world bag with empty application queues and front-reader pending group deletion and a second preview spanning paid completion. Queue-disabled controls explicitly allow the source-bounded initial ready-gated preview send, exact unattached preview reference retention during location/close, displaced old root items and stale close restoration. Paid Host output must exist physically in root on both roles; the native sendAddItemToContainer(kit) defect is not waived. Programmatic native UI calls and bridge return witness; no physical input or screenshot pixel assertion implied.')},
        cases=[dict(id=case,producer='native-makeup-ui',capability='effect',kinds=['sp','mp'] if case in SP_CASES+SUPPLY_SP_CASES else ['mp'],
                    modes=['native','toolkit'],languages=['EN']) for case in MP_CASES+SUPPLY_MP_CASES])}


def validate(selection):
    if (selection.get('kind') not in ('sp','mp') or selection.get('cases')!=cases(selection)
            or ('makeup_supplies' in selection.get('options',{}) and type(selection['options']['makeup_supplies']) is not bool)
            or selection.get('mode') not in ('native','toolkit') or selection.get('mods')!=MODS
            or selection.get('languages')!=['EN'] or type(selection.get('clients')) is not int or selection['clients']!=1
            or selection.get('options',{}).get('world_template')
            or selection['kind']=='mp' and selection.get('options',{}).get('mp_host') is not True):
        raise ValueError('Makeup requires the canonical ordered preview or optional supply SP4/Host6 cases, full selected EN pack, fresh one-client SP/menu Host and native/toolkit mode')


def sources(project,selection):
    root=Path(project)/'tests/native_queue'
    return [*sorted((root/'makeup').rglob('*.lua')),root/'makeup/Main.java',*sorted((root/'startup').rglob('*.lua')),
            root/'health/shared/QueueHealthEvents.lua',root/'support/QueueEnergyPlacement.lua',Path(__file__).with_name('tv_controls.py')]


def stage(project,output,game,jdk,selection,locations,runtime):
    validate(selection);root=Path(project)/'tests/native_queue'
    classes=Path(output)/'makeup-capture-classes';classes.mkdir()
    subprocess.run([str(Path(jdk)/'bin/javac'),'--release','25','-cp',
        os.pathsep.join(str(Path(game)/name) for name in ('projectzomboid.jar','ZombieBuddy.jar')),
        '-d',str(classes),str(root/'makeup/Main.java')],check=True,capture_output=True,text=True,timeout=60,
        env={key:value for key,value in os.environ.items() if key not in ('JAVA_TOOL_OPTIONS','JDK_JAVA_OPTIONS','_JAVA_OPTIONS')})
    if not (classes/'net/alexredby/makeupcapturefixture/Main.class').is_file():
        raise ValueError('Makeup javac did not produce its test-only capture probe')
    for role in runtime['roles'].values():
        lua=Path(role['cache'])/'mods/ActionQueueTest/42/media/lua'
        for side,name in [('client','ZZStartup.lua'),('server','ZZStartupServer.lua')]:shutil.copy2(root/'startup'/side/name,lua/side/name)
        shutil.copy2(root/'health/shared/QueueHealthEvents.lua',lua/'shared')
        helper=Path(role['cache'])/'mods/MakeupAvatarCaptureProbe';jar=helper/'42/media/java/MakeupAvatarCaptureProbe.jar'
        jar.parent.mkdir(parents=True)
        with zipfile.ZipFile(jar,'x',zipfile.ZIP_DEFLATED) as archive:
            for source in sorted(classes.rglob('*.class')):archive.write(source,source.relative_to(classes).as_posix())
        (helper/'42/mod.info').write_text('name=Test-only makeup avatar capture probe\nid=MakeupAvatarCaptureProbe\n'
            'versionMin=42.21\nrequire=\\ZombieBuddy\njavaPkgName=net.alexredby.makeupcapturefixture\n'
            'javaJarFile=media/java/MakeupAvatarCaptureProbe.jar\n')
    runtime.setdefault('fixture',{}).update(mods=['MakeupAvatarCaptureProbe'],server_ready='[MAKEUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL makeup'],sandbox={'Zombies':6,'MinutesPerPage':2.0})


def raw(text,marker):
    return [json.loads(match[1]) for match in re.finditer(re.escape(PREFIX+marker+' ')+r'([^\n]+)',text)]


def complete(selection,role,text):
    try:return role=='client1' and raw(text,'COMPLETE')==[dict(cases=selection['cases'])]
    except (ValueError,TypeError):return False


def snapshot(value,ids):
    assert type(value) is dict and set(value)=={'case','actor','root','worn','kit','frontPages','tailPages'}|({'supply','placement'} if 'supply'in ids else set()),'snapshot shape differs'
    assert value['case']==ids['case'] and value['actor']==ids['actor'],'snapshot actor/case differs'
    root=value['root'];assert type(root) is list and root,'physical root identities absent'
    assert all(type(row) is dict and set(row)=={'id','kind'} and type(row['id']) is int and type(row['kind']) is str and row['kind'] for row in root)
    found={row['id']:row['kind'] for row in root}
    assert len(found)==len(root) and list(found)==sorted(found),'duplicate/reordered root identity'
    worn=value['worn'];assert type(worn) is list
    assert all(type(row) is dict and set(row)=={'id','kind','slot','root','sameReference','container'}
               and type(row['id']) is int and type(row['kind']) is str and type(row['slot']) is str
               and type(row['root']) is bool and type(row['sameReference']) is bool and (row['container'] is False or row['container']=='root')
               and row['root']==(row['id'] in found) and (not row['root'] or found[row['id']]==row['kind'])
               and (not row['sameReference'] or row['root'] and row['container']=='root') for row in worn),'worn/root identity differs'
    assert [row['slot'] for row in worn]==sorted({row['slot'] for row in worn}) and len({row['id'] for row in worn})==len(worn),'duplicate worn identity/slot'
    kit=value['kit'];assert type(kit) is dict and set(kit)=={'id','kind','uses','maxUses','root'}
    assert kit['id']==ids['items']['kit'] and kit['kind']==ids['types']['kit']
    if 'supply'in ids:
        assert kit['id'] not in found and kit['root'] is False,'supply kit moved to root'
        tile=ids['placement']
        assert type(tile) is dict and set(tile)=={'x','y','z'} and all(type(number) is int for number in tile.values()),'supply placement target absent/invalid'
        assert value['placement']==dict(tile=tile,square=tile),'supply actor coordinates/current square did not settle on exact placement'
        supply_snapshot(value,ids,found)
    else:assert found.get(kit['id'])==kit['kind'] and kit['root'] is True
    assert type(kit['uses']) is int and 0<=kit['uses']<=kit['maxUses']==5
    for name in ('front','tail'):
        assert found.get(ids['items'][name])==ids['types'][name]
        assert type(value[name+'Pages']) is int and ids[name+'Initial']<=value[name+'Pages']<=ids[name+'Total']
    return found


def supply_snapshot(value,ids,root):
    spec=ids['supply'];source=value['supply']
    assert type(spec) is dict and set(spec)=={'kind','world','ancestors'}
    kind=ids['case'].split('-',1)[1]
    assert spec['kind']==kind and kind in ('worn-bag','nested-bag','world-container','world-bag')
    assert type(source) is dict and set(source)=={'kind','world','ancestors','items','access'} and source['kind']==kind
    assert type(spec['ancestors']) is list and type(source['ancestors']) is list
    expected_count=2 if kind=='nested-bag' else 1 if kind=='worn-bag' else 0
    assert len(spec['ancestors'])==len(source['ancestors'])==expected_count
    known=set(ids['items'].values());parent='root'
    for expected,actual in zip(spec['ancestors'],source['ancestors']):
        assert set(expected)=={'id','kind','parent'} and type(expected['id']) is int and expected['id'] not in known
        assert expected['kind']=='Base.Bag_Schoolbag' and expected['parent']==parent
        if parent!='root':assert expected['id'] not in root,'nested source ancestor duplicated in root'
        assert type(actual) is dict and set(actual)=={'id','kind','parent','items'}
        assert {key:actual[key] for key in expected}==expected,'supply ancestor identity differs'
        known.add(expected['id']);parent=expected['id']
    if expected_count:
        outer=spec['ancestors'][0]
        assert root.get(outer['id'])==outer['kind'],'outer bag left actor root'
        assert any(row['id']==outer['id'] and row['kind']==outer['kind'] and row['slot']=='base:back' and row['root'] and row['sameReference'] for row in value['worn']),'outer source backpack no longer worn'
        assert spec['world'] is False and source['world'] is False and source['access'] is False
    else:
        world=spec['world'];assert type(world) is dict and source['world']==world,'world source identity differs'
        fields={'kind','x','y','z','index','owner','type'}|({'id'} if kind=='world-bag' else {'sprite','containerIndex'})
        assert set(world)==fields and world['kind']==kind
        assert all(type(world[key]) is int for key in ('x','y','z','index')) and world['index']>=0
        assert type(world['owner']) is str and world['owner']
        tile=ids['placement']
        assert world['z']==tile['z'] and abs(world['x']-tile['x'])+abs(world['y']-tile['y'])==1,'world makeup source is not adjacent to settled actor'
        assert source['access']==dict(blocked=False),'world makeup source is blocked by a wall'
        if kind=='world-bag':assert type(world['id']) is int and world['id'] not in known and world['id'] not in root and world['type']=='Base.Bag_Schoolbag'
        else:assert world['type']=='crate' and world['sprite']=='carpentry_01_16' and type(world['containerIndex']) is int and world['containerIndex']>=0
    def members(rows):
        assert type(rows) is list and all(type(row) is dict and set(row)=={'id','kind'} and type(row['id']) is int and type(row['kind']) is str and row['kind'] for row in rows)
        assert [row['id'] for row in rows]==sorted({row['id'] for row in rows}),'duplicate/reordered source member'
        return {row['id']:row['kind'] for row in rows}
    direct=members(source['items'])
    assert direct.get(ids['items']['kit'])==ids['types']['kit'],'exact supply member absent'
    assert not any(item in root for item in direct),'source member duplicated in root'
    seen=set(root)
    containers=source['ancestors'] if source['ancestors'] else [dict(items=source['items'])]
    for container in containers:
        contents=members(container['items'])
        assert not seen.intersection(contents),'supply source/ancestor member duplicated across containers'
        seen.update(contents)
    for i,actual in enumerate(source['ancestors']):
        contents=members(actual['items'])
        if i+1<len(spec['ancestors']):
            child=spec['ancestors'][i+1]
            assert contents.get(child['id'])==child['kind'] and ids['items']['kit'] not in contents,'nested parent/member differs'
        else:assert contents==direct
    assert source==ids['baseline']['supply'],'source/ancestor contents conservation differs'


def worn_identity(value):return [{key:row[key] for key in ('id','kind','slot','root')} for row in value['worn']]


def desired_worn(base,ids,item=None,kind=None,slot=None,root=False,clear=False):
    rows=worn_identity(base)
    if slot is not None:rows=[row for row in rows if row['slot']!=slot]
    if not clear and item is not None:rows.append(dict(id=item,kind=kind,slot=slot,root=root))
    return sorted(rows,key=lambda row:row['slot'])


def native_control_worn(base,ids,case,label,role,points):
    """Additional native Host states, never Toolkit or paid-output waivers.

    Native IsoGameCharacter.setWornItem sends only when connection.isReady();
    the first preview-close authority checkpoint in the clean Host control kept
    its exact baseline old item. ISMakeUpUI onSelectLocation/close remove the
    saved object, while WornItems.indexOf(InventoryItem) uses reference identity.
    SyncClothingPacket.process can create an unattached same-ID Clothing. The
    captured native Host control retained its exact last preview after those
    removals. Limit this baseline to the already witnessed ID/type/slot, with
    unchanged physical root and kit checks still enforced by check_case.
    """
    if case=='preview-close' and label=='preview' and role=='authority':
        return [(worn_identity(base),'initial-preview-send-ready-gated')]
    if case=='preview-location' and label=='location-cleared':
        preview=points['same-preview']['client']['preview']
        return [(desired_worn(base,ids,preview['id'],ALTERNATE,SLOT),'native-selected-reference-not-worn')]
    if case=='preview-location' and label in ('closed','final'):
        preview=points['different-preview']['client']['preview']
        return [(desired_worn(base,ids,preview['id'],DIFFERENT,OTHER_SLOT),'native-selected-reference-not-worn')]
    return []


def check_case(row,selection,prepared,receipt):
    ids=row['ids'];case=row['id'];supply=selection.get('options',{}).get('makeup_supplies') is True;native=selection['mode']=='native';mp=selection['kind']=='mp'
    assert ('supply'in ids)==supply,'supply bank topology absent/unexpected'
    assert ids==prepared and row['receipt']==receipt and row['status']=='passed','authority publication or fixture status differs'
    assert ids['case']==case and ids['target']==TARGET and ids['oldType']==OLD and ids['alternate']==ALTERNATE and ids['different']==DIFFERENT
    assert ids['slot']==SLOT and ids['otherSlot']==OTHER_SLOT and ids['producer']=='ISMakeUpUI.onApplyMakeUp' and ids['duration']==1
    assert type(ids['actor']) is int and ids['kitUses']==5 and ids['kitType']=='Eyes'
    names={'kit','front','tail'}|({'old'} if case!='apply-empty' else set())
    assert set(ids['items'])==set(ids['types'])==names
    assert len(set(ids['items'].values()))==len(names) and all(type(value) is int for value in ids['items'].values())
    assert ids['types']==dict(kit='Base.MakeupEyeshadow',front='Base.BookCarpentry1',tail='Base.BookFirstAid1',**({'old':OLD} if 'old'in names else {}))
    for name,pages in [('front',3),('tail',1)]:
        assert type(ids[name+'Total']) is int and ids[name+'Total']>pages and ids[name+'Initial']==ids[name+'Total']-pages
    checkpoints=row['checkpoints'];assert type(checkpoints) is list and [point['client']['label'] for point in checkpoints]==labels(case)
    assert [point['authority']['label'] for point in checkpoints]==labels(case)
    base=ids['baseline'];base_root=snapshot(base,ids)
    assert base['kit']['uses']==5 and base['frontPages']==ids['frontInitial'] and base['tailPages']==ids['tailInitial']
    assert all(base_root.get(value)==ids['types'][name] for name,value in ids['items'].items() if name!='kit'or not supply)
    assert not any(value['slot'] in (SLOT,OTHER_SLOT) for value in base['worn'] if value['id']!=ids['items'].get('old'))
    if 'old'in names:assert [v for v in worn_identity(base) if v['slot']==SLOT]==[dict(id=ids['items']['old'],kind=OLD,slot=SLOT,root=True)]
    reserved=set(base_root)|set(ids['items'].values())
    if supply:
        source=base['supply'];reserved.update(value['id'] for value in source['items'])
        for ancestor in source['ancestors']:
            reserved.add(ancestor['id']);reserved.update(value['id'] for value in ancestor['items'])
        if source['world'] and source['world']['kind']=='world-bag':reserved.add(source['world']['id'])
    submitted=row['submitted'];assert type(submitted) is dict and set(submitted)=={'id','kind','slot','root','previous'}
    assert type(submitted['id']) is int and submitted['id'] not in reserved and submitted['kind']==TARGET and submitted['slot']==SLOT and submitted['root'] is False
    assert submitted['previous']==ids['items'].get('old',False)
    output=row['output'];paid=case.startswith('apply-') or cancelling(case) and native
    assert (type(output) is int and output not in reserved) if paid else output is False
    if paid and not mp:assert output==submitted['id'],'SP immediate result changed native preview identity'
    if paid and mp:assert output!=submitted['id'],'Host result reused client preview identity'
    second=row['second'];assert (type(second) is dict and second['kind']==ALTERNATE and second['slot']==SLOT
        and second['root'] is False and type(second['id']) is int and second['id'] not in {*base_root,submitted['id'],output}) if case=='apply-while-preview' else second is False
    if second:assert set(second)==set(submitted) and second['previous']==(submitted['id'] if native else ids['items']['old'])
    expected_root=dict(base_root)
    if paid:
        expected_root[output]=TARGET
        # Native MP preview displaces the old worn item before complete() reads it.
        if 'old'in names and not(native and mp):expected_root.pop(ids['items']['old'])
    assert row['nativeMethodsUnchanged'] is True
    by_label={point['client']['label']:point for point in checkpoints};control_baseline=[]
    for sequence,point in enumerate(checkpoints,1):
        client,authority=point['client'],point['authority'];label=client['label']
        assert set(point)=={'client','authority'} and client['case']==authority['case']==case
        assert client['sequence']==authority['sequence']==sequence and type(client['at']) is int and type(authority['at']) is int
        assert set(client)=={'case','label','sequence','at','snapshot','preview','render','bodyUnallocated','edit'}
        assert set(authority)=={'case','label','sequence','at','snapshot'} and type(client['bodyUnallocated']) is bool
        late=label in ('after-body','final') or label=='closed' and case=='apply-while-preview'
        expected_items=expected_root if late else base_root
        selected=client['preview'];render=client['render']
        active=label in ('preview','same-preview','different-preview','overlap-preview')
        if active:
            assert type(selected) is dict and set(selected)==set(submitted) and selected['root'] is False and type(selected['id']) is int and selected['id'] not in reserved
            expected_kind=ALTERNATE if label in ('same-preview','overlap-preview') else DIFFERENT if label=='different-preview' else TARGET
            expected_slot=OTHER_SLOT if label=='different-preview' else SLOT
            assert selected['kind']==expected_kind and selected['slot']==expected_slot
            assert selected['previous']==(False if label=='different-preview' else submitted['id'] if label=='overlap-preview'and native else ids['items'].get('old',False))
            assert type(render) is dict and set(render)=={'ok','actorUnchanged','selected','uiType','source','nativeRendered','stableFrames','stableMs'}
            assert {key:render[key] for key in ('ok','actorUnchanged','selected','uiType','source')}==dict(
                ok=True,actorUnchanged=True,selected=selected['id'],uiType='UI3DModel',source='native-worn' if native else 'toolkitMakeupAvatarPreview'),'real avatar rendering witness differs'
            assert render['nativeRendered'] is True and type(render['stableFrames']) is int and render['stableFrames']>=3
            assert type(render['stableMs']) is int and render['stableMs']>=500,'native avatar frame was not stable'
        else:assert render is False
        for role,value in [('client',client['snapshot']),('authority',authority['snapshot'])]:
            actual_root=snapshot(value,ids)
            assert actual_root==expected_items,'physical root inventory conservation differs at '+label+'/'+role
            assert value['kit']['uses']==5-int(paid and late),'supply cost differs at '+label+'/'+role
            if label=='baseline':assert worn_identity(value)==worn_identity(base) and value['frontPages']==ids['frontInitial'] and value['tailPages']==ids['tailInitial']
            expected_worn=worn_identity(base)
            if late and paid:
                expected_worn=desired_worn(base,ids,output,TARGET,SLOT,True)
                if not(native and case=='apply-while-preview'and label in ('closed','final')):
                    assert any(row['id']==output and row['kind']==TARGET and row['slot']==SLOT and row['root']
                               and row['sameReference'] and row['container']=='root' for row in value['worn']),'paid output is not exact physical worn reference'
            if native and active:
                expected_worn=desired_worn(base,ids,selected['id'],selected['kind'],selected['slot'])
                if label=='different-preview':expected_worn=desired_worn(base,ids,selected['id'],selected['kind'],OTHER_SLOT)
            if native and label=='location-cleared':expected_worn=desired_worn(base,ids,slot=SLOT,clear=True)
            if native and label=='cancelled':expected_worn=desired_worn(base,ids,submitted['id'],TARGET,SLOT)
            if native and case=='apply-while-preview'and label in ('closed','final'):
                expected_worn=desired_worn(base,ids,submitted['id'],TARGET,SLOT)
            actual_worn=worn_identity(value)
            if actual_worn!=expected_worn:
                alternatives=native_control_worn(base,ids,case,label,role,by_label) if native and mp else []
                matched=[reason for allowed,reason in alternatives if actual_worn==allowed]
                assert len(matched)==1,'worn preview/paid result identity differs at '+label+'/'+role
                control_baseline.append(dict(label=label,role=role,reason=matched[0]))
            if label=='final':
                assert value['frontPages']==(ids['frontTotal'] if mp and (cancelling(case) or paid and not supply) else ids['frontInitial'])
                assert value['tailPages']==ids['tailTotal'],'independent tail pages differ'
            elif not(mp and (cancelling(case) or not supply and case in ('apply-empty','apply-replace','apply-while-preview')) and label not in ('baseline','preview')):
                assert value['frontPages']==ids['frontInitial']
            if not late:assert value['tailPages']==ids['tailInitial'],'independent tail advanced before body/checkpoint'
        if label=='preview':assert selected==submitted and client['bodyUnallocated'] is True
        if label=='overlap-preview':assert selected==second and client['bodyUnallocated'] is True
        if label in ('cancelled','baseline','preview','same-preview','location-cleared','different-preview'):assert client['bodyUnallocated'] is True
    assert row['clientFinal']==by_label['final']['client']['snapshot'] and receipt['snapshot']==by_label['final']['authority']['snapshot']
    assert receipt['case']==case and receipt['sequence']==len(checkpoints)
    if supply:
        evidence=row['applyQueues']
        assert type(evidence) is dict and set(evidence)=={'before','after'}
        assert evidence['before']==dict(types=[],hasTimedActions=False,nativeActions=0),'supply application did not start with empty queue'
        after=evidence['after']
        assert type(after) is dict and set(after)=={'types','hasTimedActions','nativeActions'}
        expected_types=(['ISReadABook'] if cancelling(case) else [])+['ISApplyMakeUp'] if mp else []
        assert after['types']==expected_types,'native supply producer inserted/reordered actions'
        assert after['hasTimedActions'] is mp and type(after['nativeActions']) is int and after['nativeActions']==int(mp)
        assert row['supplyTransferStarts']==0 and type(row['supplyTransferStarts']) is int,'supply fixture performed a transfer'
    body=row['body'];outcomes=row['outcomes']
    if mp and (case.startswith('apply-') or cancelling(case)):
        assert type(body) is dict and set(body)=={'duration','starts','finishes','nativeRef'} and body['duration']==1
        assert body['starts']==int(paid) and type(body['starts']) is int
        if paid:
            assert type(body['nativeRef']) is str and body['nativeRef'] not in ('','nil','false')
            assert len(body['finishes'])==1 and body['finishes'][0]['phase']=='perform' and body['finishes'][0]['succeeded'] is True and type(body['finishes'][0]['at']) is int
            assert len(outcomes)==2
            identity={key:outcomes[0][key] for key in ('protocol','player','transaction','kind','token')}
            assert identity['protocol']==1 and identity['player']==ids['actor'] and type(identity['transaction']) is int and identity['transaction']!=0
            assert identity['kind']=='ISApplyMakeUp' and isinstance(identity['token'],str) and re.fullmatch(r'[0-9a-f-]{36}',identity['token'])
            assert outcomes==[dict(identity,state=state) for state in ('started','completed')],'native Host receipt identity/order differs'
        else:assert body['nativeRef'] is False and body['finishes']==[] and outcomes==[]
    else:assert body is False and outcomes==[],'SP immediate/preview-only scenario manufactured native body'
    edit=row['edit']
    if cancelling(case):
        assert type(edit) is dict and edit['accepted'] is (not native) and edit['bodyAbsent'] is (not native)
        assert edit['bodyUnallocated'] is True and edit['frontSame'] is True and edit['tailRetained'] is True and isinstance(edit['frontNative'],str)
        assert by_label['cancelled']['client']['edit']==edit
    else:assert edit is False
    assert type(row['beforeTail']) is dict and type(row['beforeTail']['at']) is int
    snapshot(row['beforeTail']['snapshot'],ids)
    assert row['beforeTail']['snapshot']['tailPages']==ids['tailInitial'],'tail was already consumed before its native begin'
    return dict(avatarVerified=True,identityVerified=True,authoritative=True,tailCompleted=True,
                cancelled=cancelling(case)and not native,unallocated=cancelling(case),
                nativePreviewControl=native,paid=paid,nativeStaleRestore=native and case=='apply-while-preview',
                nativeControlBaseline=control_baseline,emptyQueueVerified=supply and not cancelling(case))


def verify(root,selection,catalog):
    from ..report import events
    validate(selection);root=Path(root);text=(root/'client1-launch.log').read_text(errors='replace')
    authority=(root/'server-launch.log').read_text(errors='replace') if selection['kind']=='mp' else text
    rows=events(text);results=[row for row in rows if row.get('event')=='case'];issues=[];outcomes=[]
    if [row.get('event') for row in rows]!=['setup']+['case']*len(selection['cases'])+['complete'] or [row.get('id') for row in results]!=selection['cases']:
        issues.append('Missing/duplicate/reordered makeup events')
    if any(row.get(key)!=value for row in rows for key,value in dict(suite='makeup',kind=selection['kind'],mode=selection['mode'],actor='client1').items()):issues.append('Makeup event context differs')
    if not rows or any(rows[0].get(key) is not value for key,value in dict(queueEnabled=selection['mode']=='toolkit',nativeDurations=True,avatarSupported=True,captureSupported=True).items()):issues.append('Makeup queue/renderer/timing setup absent')
    if not rows or rows[0].get('cases')!=selection['cases']:issues.append('Makeup setup case selection differs')
    if not rows or any(rows[-1].get(key)!=value for key,value in dict(cases=selection['cases'],performed=len(selection['cases']),skipped=0,failed=0).items()):issues.append('Makeup completion counts differ')
    if not complete(selection,'client1',text):issues.append('Makeup completion marker absent/duplicated')
    shots=raw(text,'SCREENSHOT');filename='makeup-preview-'+selection['kind']+'-'+selection['mode']+'.png'
    if (len(shots)!=1 or shots[0].get('case')!=selection['cases'][0] or shots[0].get('file')!=filename
        or shots[0].get('fadeClear') is not True or shots[0].get('nativeRendered') is not True
        or type(shots[0].get('renderFrames')) is not int or shots[0]['renderFrames']<3
        or type(shots[0].get('renderMs')) is not int or shots[0]['renderMs']<500):
        issues.append('Makeup stable rendered screenshot witness missing/duplicate')
    image=root/'client1/Screenshots'/filename
    try:
        header=image.read_bytes()[:24]
        if (len(header)<24 or header[:8]!=b'\x89PNG\r\n\x1a\n' or header[12:16]!=b'IHDR'
            or int.from_bytes(header[16:20],'big')<128 or int.from_bytes(header[20:24],'big')<128):
            issues.append('Makeup screenshot is not a usable native PNG')
    except OSError:issues.append('Makeup native screenshot file missing')
    prepared,verified=raw(authority,'PREPARED'),raw(authority,'VERIFIED')
    if len(prepared)!=len(results) or len(verified)!=len(results):issues.append('Makeup authority case markers missing/duplicate')
    expected_client=[point['client'] for row in results for point in row.get('checkpoints',[])]
    expected_authority=[point['authority'] for row in results for point in row.get('checkpoints',[])]
    if raw(text,'CLIENT_SNAPSHOT')!=expected_client:issues.append('Raw makeup client checkpoints differ')
    if raw(authority,'SNAPSHOT')!=expected_authority:issues.append('Raw makeup authority checkpoints differ')
    if raw(text,'OUTCOME')!=[dict(case=row['id'],receipt=receipt) for row in results for receipt in row.get('outcomes',[])]:issues.append('Raw makeup native outcomes differ')
    if raw(text,'BEFORE_TAIL')!=[dict(case=row['id'],evidence=row.get('beforeTail')) for row in results]:issues.append('Raw makeup tail boundary differs')
    if raw(text,'EDIT')!=[dict(case=row['id'],evidence=row.get('edit')) for row in results if cancelling(row.get('id',''))]:issues.append('Raw makeup pending edit differs')
    if selection.get('options',{}).get('makeup_supplies') is True and (not prepared or any(value.get('placement')!=prepared[0].get('placement') for value in prepared)):
        issues.append('Makeup supply cases did not retain one settled placement tile')
    if raw(text,'APPLY_QUEUES')!=[dict(case=row['id'],evidence=row.get('applyQueues')) for row in results if selection.get('options',{}).get('makeup_supplies') is True]:issues.append('Raw makeup native queue submission boundary differs')
    # Matching per-marker lists alone must not admit case/checkpoint reordering.
    client_order=[];server_order=[]
    for line in text.splitlines():
        if PREFIX+'CLIENT_SNAPSHOT 'in line:
            point=json.loads(line.split(PREFIX+'CLIENT_SNAPSHOT ',1)[1]);client_order.append(('snapshot',point.get('case'),point.get('label'),point.get('sequence')))
        elif '[QUEUE_CHECK] 'in line:
            point=json.loads(line.split('[QUEUE_CHECK] ',1)[1])
            if point.get('event')=='case':client_order.append(('case',point.get('id')))
    expected_order=[entry for row in results for entry in
                    [*[('snapshot',row['id'],point['client']['label'],point['client']['sequence']) for point in row.get('checkpoints',[])],('case',row['id'])]]
    if client_order!=expected_order:issues.append('Makeup client checkpoint/case publication order differs')
    for line in authority.splitlines():
        match=re.search(re.escape(PREFIX)+r'(PREPARED|SNAPSHOT|VERIFIED) ([^\n]+)',line)
        if match:
            point=json.loads(match[2]);server_order.append((match[1],point.get('case'),point.get('label'),point.get('sequence')))
    expected_server=[entry for row in results for entry in [('PREPARED',row['id'],None,None),
        *[('SNAPSHOT',row['id'],point['authority']['label'],point['authority']['sequence']) for point in row.get('checkpoints',[])],
        ('VERIFIED',row['id'],None,len(row.get('checkpoints',[])))]]
    if server_order!=expected_server:issues.append('Makeup authority checkpoint/case publication order differs')
    if '[QUEUE_TEST] FAIL makeup' in text+authority or raw(text,'RENDER_FAILURE'):issues.append('Makeup fixture/renderer failure marker present')
    for i,row in enumerate(results):
        problems=[];outcome={}
        try:outcome=check_case(row,selection,prepared[i],verified[i])
        except (AssertionError,KeyError,TypeError,ValueError,IndexError) as error:problems.append(str(error)or'makeup evidence differs')
        issues.extend(row.get('id','?')+': '+problem for problem in problems)
        outcomes.append(dict(actor='client1',case=row.get('id'),status='failed' if problems else'passed',outcome=outcome))
    return dict(issues=issues,outcomes=outcomes)
