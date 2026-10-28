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
MOVE_CASES=['move-earlier','move-later','move-promote','move-deny-writer']
CARRIED_MOVE_CASES=['move-worn-earlier','move-nested-later','move-nested-promote','move-nested-deny-writer']
WORLD_MOVE_CASES=['move-world-container-earlier','move-world-bag-later','move-world-container-promote','move-world-bag-deny-walk']
DEPLETION_MOVE_CASES=['deplete-root-earlier','deplete-nested-later','deplete-world-container-promote','deplete-world-bag-later','deplete-root-deny-writer']
HELD_MOVE_CASES=['held-primary-earlier','held-secondary-later','held-both-promote','held-primary-other-secondary','held-primary-deny-equip']
HELD_SPECS={
    'held-primary-earlier':dict(uses=1,initial=dict(primary='kit',secondary=False),post=dict(primary=False,secondary=False)),
    'held-secondary-later':dict(uses=5,initial=dict(primary=False,secondary='kit'),post=dict(primary=False,secondary='kit')),
    'held-both-promote':dict(uses=1,initial=dict(primary='kit',secondary='kit'),post=dict(primary=False,secondary=False)),
    'held-primary-other-secondary':dict(uses=1,initial=dict(primary='kit',secondary='hammer'),post=dict(primary=False,secondary='hammer')),
    'held-primary-deny-equip':dict(uses=1,initial=dict(primary='kit',secondary=False),post=dict(primary='hammer',secondary=False))}
FINAL_USE_CASES=set(DEPLETION_MOVE_CASES)|{case for case,spec in HELD_SPECS.items() if spec['uses']==1}
MOVE_KINDS=dict(zip(MOVE_CASES,['earlier','later','promote','deny-writer']))
MOVE_KINDS.update(zip(CARRIED_MOVE_CASES,['earlier','later','promote','deny-writer']))
MOVE_KINDS.update(zip(WORLD_MOVE_CASES,['earlier','later','promote','deny-walk']))
MOVE_KINDS.update(zip(DEPLETION_MOVE_CASES,['earlier','later','promote','later','deny-writer']))
MOVE_KINDS.update(zip(HELD_MOVE_CASES,['earlier','later','promote','earlier','deny-equip']))
MOVE_SUPPLIES=dict(zip(CARRIED_MOVE_CASES,['worn-bag','nested-bag','nested-bag','nested-bag']))
MOVE_SUPPLIES.update(zip(WORLD_MOVE_CASES,['world-container','world-bag','world-container','world-bag']))
MOVE_SUPPLIES.update({'deplete-nested-later':'nested-bag','deplete-world-container-promote':'world-container','deplete-world-bag-later':'world-bag'})


def moving(selection):
    return any(selection.get('options',{}).get(option) is True for option in ('makeup_moves','makeup_carried_moves','makeup_world_moves','makeup_depletion_moves','makeup_held_moves'))


def cancelling(case):return case.startswith('cancel-')


def cases(selection):
    if selection.get('options',{}).get('makeup_held_moves') is True:return HELD_MOVE_CASES
    if selection.get('options',{}).get('makeup_depletion_moves') is True:return DEPLETION_MOVE_CASES
    if selection.get('options',{}).get('makeup_world_moves') is True:return WORLD_MOVE_CASES
    if selection.get('options',{}).get('makeup_carried_moves') is True:return CARRIED_MOVE_CASES
    if selection.get('options',{}).get('makeup_moves') is True:return MOVE_CASES
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
    checks['move-independent']={case:dict(moveVerified=True,identityVerified=True,authoritative=True,tailCompleted=True) for case in MOVE_KINDS if MOVE_KINDS[case] in ('earlier','later')}
    checks['priority-preempt']={case:dict(moveVerified=True,readerResumed=True,identityVerified=True,authoritative=True,tailCompleted=True) for case in MOVE_KINDS if MOVE_KINDS[case]=='promote'}
    checks['move-dependent']={case:dict(moveProtected=True,identityVerified=True,authoritative=True,tailCompleted=True) for case in MOVE_KINDS if MOVE_KINDS[case] in ('deny-writer','deny-walk','deny-equip')}
    for scenario in ('move-independent','priority-preempt','move-dependent'):
        for case,fields in checks[scenario].items():
            if case in FINAL_USE_CASES:fields['depletionVerified']=True
            if case in HELD_MOVE_CASES:fields['handsVerified']=True
    return {'makeup':dict(status='ready',clients=1,default_mods=list(MODS),
        scenario_actions={'native-makeup-ui':dict(checks=checks,toolkit_only=['cancel-waiting'],
            scope='Current full selected pack, fresh macOS SP/menu Host, one EN actor. Real native makeup window/combo/apply/close and avatar model; detached preview rendering and exact root/worn/supply identity checkpoints independently read on Host. SP immediate application; Host native duration-one body behind ordinary front reader in the preview bank; optional makeup_supplies bank covers worn/nested bags and adjacent native crate/world bag with empty application queues and front-reader pending group deletion and a second preview spanning paid completion. Optional Host-only makeup_moves exercises earlier/later pending-reader moves, promotion before a real active reader with page-preserving resume, actor-equipment writer denial. Optional mutually exclusive makeup_carried_moves repeats these edits for exact worn/nested bag kit ancestry and rejects the actor writer; optional makeup_world_moves uses adjacent exact crate/ground-bag sources and naturally walks out of source reach and back to prove unsafe reordering is denied; makeup_depletion_moves covers one-use root/nested/direct-world kits with exact physical deletion and one paid cosmetic; makeup_held_moves covers exact primary/secondary/both root kit references, preserved secondary Hammer and native primary Hammer equip conflict; controls retain original execution order. Queue-disabled controls explicitly allow the source-bounded initial ready-gated preview send, exact unattached preview reference retention during location/close, displaced old root items and stale close restoration. Paid Host output must exist physically in root on both roles; the native sendAddItemToContainer(kit) defect is not waived. Programmatic native UI calls and bridge return witness; no physical input or screenshot pixel assertion implied.')},
        cases=[dict(id=case,producer='native-makeup-ui',capability='effect',kinds=['sp','mp'] if case in SP_CASES+SUPPLY_SP_CASES else ['mp'],
                    modes=['native','toolkit'],languages=['EN']) for case in MP_CASES+SUPPLY_MP_CASES+MOVE_CASES+CARRIED_MOVE_CASES+WORLD_MOVE_CASES+DEPLETION_MOVE_CASES+HELD_MOVE_CASES])}


def validate(selection):
    if (selection.get('kind') not in ('sp','mp') or selection.get('cases')!=cases(selection)
            or any(option in selection.get('options',{}) and type(selection['options'][option]) is not bool for option in ('makeup_moves','makeup_carried_moves','makeup_world_moves','makeup_depletion_moves','makeup_held_moves','makeup_supplies'))
            or sum(selection.get('options',{}).get(option) is True for option in ('makeup_moves','makeup_carried_moves','makeup_world_moves','makeup_depletion_moves','makeup_held_moves','makeup_supplies'))>1
            or moving(selection) and selection.get('kind')!='mp'
            or selection.get('mode') not in ('native','toolkit') or selection.get('mods')!=MODS
            or selection.get('languages')!=['EN'] or type(selection.get('clients')) is not int or selection['clients']!=1
            or selection.get('options',{}).get('world_template')
            or selection['kind']=='mp' and selection.get('options',{}).get('mp_host') is not True):
        raise ValueError('Makeup requires the canonical ordered preview/supply SP4/Host6 or optional Host-only move cases, full selected EN pack, fresh one-client SP/menu Host and native/toolkit mode')


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


def snapshot(value,ids,transition=False):
    assert type(value) is dict and set(value)=={'case','actor','root','worn','kit','frontPages','tailPages'}|({'supply','placement'} if 'supply'in ids else set())|({'middlePages','placement'} if ids.get('move') is True else set())|({'hands'} if ids.get('held') is True else set()),'snapshot shape differs'
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
    if ids.get('held') is True:
        hands=value['hands'];assert type(hands) is dict and set(hands)=={'primary','secondary'}
        for hand in hands.values():
            if hand is False:continue
            assert type(hand) is dict and set(hand)=={'id','kind','root','sameReference','container','equipParent'}
            assert type(hand['id']) is int and type(hand['kind']) is str and type(hand['root']) is bool and type(hand['sameReference']) is bool and type(hand['equipParent']) is bool
            assert hand['container'] is False or hand['container']=='root'
            assert hand['root']==(hand['id'] in found) and(not hand['root'] or found[hand['id']]==hand['kind'])
            assert not hand['sameReference'] or hand['root'] and hand['container']=='root','held reference has no exact physical root member'
    kit=value['kit'];removed=kit is False;kit_id=ids['items']['kit']
    if removed:
        assert ids.get('depletion') is True,'non-depletion kit disappeared'
        assert kit_id not in found and not any(row['id']==kit_id for row in worn),'consumed kit remains in actor inventory/equipment'
        if not transition:
            initial={row['id'] for row in ids['baseline']['root']}
            paid=[row for row in root if row['id'] not in initial]
            assert len(paid)==1 and paid[0]['kind']==ids['target'],'consumed kit has no unique physical paid output'
            assert any(row['id']==paid[0]['id'] and row['kind']==ids['target'] and row['slot']==ids['slot']
                       and row['root'] and row['sameReference'] and row['container']=='root' for row in worn),'consumed kit has no exact paid root/worn output'
    else:
        assert type(kit) is dict and set(kit)=={'id','kind','uses','maxUses','root'}
        assert kit['id']==kit_id and kit['kind']==ids['types']['kit']
        assert type(kit['uses']) is int and 0<=kit['uses']<=kit['maxUses']==5
    if 'supply'in ids:
        assert kit_id not in found and (removed or kit['root'] is False),'supply kit moved to root'
        tile=ids['placement']
        assert type(tile) is dict and set(tile)=={'x','y','z'} and all(type(number) is int for number in tile.values()),'supply placement target absent/invalid'
        assert value['placement']==dict(tile=tile,square=tile),'supply actor coordinates/current square did not settle on exact placement'
        supply_snapshot(value,ids,found)
    elif not removed:assert found.get(kit_id)==kit['kind'] and kit['root'] is True
    if ids.get('move') is True:
        assert value['placement']==dict(tile=ids['placement'],square=ids['placement']),'move actor left settled authority tile'
    for name in (('front','middle','tail') if ids.get('move') is True else ('front','tail')):
        assert found.get(ids['items'][name])==ids['types'][name]
        assert type(value[name+'Pages']) is int and ids[name+'Initial']<=value[name+'Pages']<=ids[name+'Total']
    return found


def supply_snapshot(value,ids,root):
    spec=ids['supply'];source=value['supply']
    assert type(spec) is dict and set(spec)=={'kind','world','ancestors'}
    kind=spec['kind'] if ids.get('move') is True else ids['case'].split('-',1)[1]
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
    direct=members(source['items']);removed=ids.get('depletion') is True and value['kit'] is False
    if removed:assert ids['items']['kit'] not in direct,'consumed kit remains in exact supply'
    else:assert direct.get(ids['items']['kit'])==ids['types']['kit'],'exact supply member absent'
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
    expected=copy.deepcopy(ids['baseline']['supply'])
    if removed:
        expected['items']=[row for row in expected['items'] if row['id']!=ids['items']['kit']]
        for ancestor in expected['ancestors']:ancestor['items']=[row for row in ancestor['items'] if row['id']!=ids['items']['kit']]
    assert source==expected,'source/ancestor contents conservation differs'


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


def check_avatar(selected,render,kind,slot,previous,reserved,native):
    assert type(selected) is dict and set(selected)=={'id','kind','slot','root','previous'}
    assert type(selected['id']) is int and selected['id'] not in reserved and selected['root'] is False
    assert selected['kind']==kind and selected['slot']==slot and selected['previous']==previous
    assert type(render) is dict and set(render)=={'ok','actorUnchanged','selected','uiType','source','nativeRendered','stableFrames','stableMs'}
    assert {key:render[key] for key in ('ok','actorUnchanged','selected','uiType','source')}==dict(
        ok=True,actorUnchanged=True,selected=selected['id'],uiType='UI3DModel',source='native-worn' if native else 'toolkitMakeupAvatarPreview'),'real avatar rendering witness differs'
    assert render['nativeRendered'] is True and type(render['stableFrames']) is int and render['stableFrames']>=3
    assert type(render['stableMs']) is int and render['stableMs']>=500,'native avatar frame was not stable'


def check_native_paid(body,outcomes,ids):
    assert type(body) is dict and set(body)=={'duration','starts','finishes','nativeRef'} and body['duration']==1
    assert type(body['starts']) is int and body['starts']==1
    assert type(body['nativeRef']) is str and body['nativeRef'] not in ('','nil','false')
    assert len(body['finishes'])==1 and body['finishes'][0]['phase']=='perform' and body['finishes'][0]['succeeded'] is True and type(body['finishes'][0]['at']) is int
    assert len(outcomes)==2
    identity={key:outcomes[0][key] for key in ('protocol','player','transaction','kind','token')}
    assert identity['protocol']==1 and identity['player']==ids['actor'] and type(identity['transaction']) is int and identity['transaction']!=0
    assert identity['kind']=='ISApplyMakeUp' and isinstance(identity['token'],str) and re.fullmatch(r'[0-9a-f-]{36}',identity['token'])
    assert outcomes==[dict(identity,state=state) for state in ('started','completed')],'native Host receipt identity/order differs'


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
            expected_kind=ALTERNATE if label in ('same-preview','overlap-preview') else DIFFERENT if label=='different-preview' else TARGET
            expected_slot=OTHER_SLOT if label=='different-preview' else SLOT
            previous=False if label=='different-preview' else submitted['id'] if label=='overlap-preview'and native else ids['items'].get('old',False)
            check_avatar(selected,render,expected_kind,expected_slot,previous,reserved,native)
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
        if paid:check_native_paid(body,outcomes,ids)
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


def move_orders(case,toolkit):
    kind=MOVE_KINDS[case]
    before=['front','body','middle','tail'] if kind=='later' else ['front','writer','body','middle','tail'] if kind in ('deny-writer','deny-equip') else ['front','middle','body','tail']
    if kind=='deny-walk':before=['front','body','walk-out','walk-back','middle','tail']
    accepted=toolkit and kind not in ('deny-writer','deny-walk','deny-equip')
    after=(['front','body','middle','tail'] if kind in ('earlier','promote') else ['front','middle','body','tail']) if accepted else before
    starts=['front','body','front','middle','tail'] if accepted and kind=='promote' else after
    return before,after,starts,accepted


def check_walk(row,ids,edit,points):
    if MOVE_KINDS[row['id']]!='deny-walk':
        assert 'walk' not in ids and not row.get('walk'),'unexpected native walk evidence'
        return
    spec=ids['walk'];walk=row['walk']
    assert type(spec) is dict and set(spec)=={'origin','via','out','source'} and spec['origin']==ids['placement']
    for key in ('origin','via','out'):
        tile=spec[key];assert type(tile) is dict and set(tile)=={'x','y','z'} and all(type(v) is int for v in tile.values())
    origin,out,via=spec['origin'],spec['out'],spec['via'];source=ids['supply']['world']
    assert spec['source']==source and source['kind']=='world-bag','walk source identity differs'
    dx,dy=out['x']-origin['x'],out['y']-origin['y']
    assert (abs(dx),abs(dy)) in ((2,0),(0,2)) and origin['z']==via['z']==out['z']==source['z']
    assert via==dict(x=origin['x']+dx//2,y=origin['y']+dy//2,z=origin['z']),'native walk is not the configured cardinal two-step route'
    assert max(abs(out['x']-source['x']),abs(out['y']-source['y']))>1,'native walk endpoint stayed in makeup source reach'
    assert type(walk) is dict and set(walk)=={'out','back','outEndpoint','returnedOrigin'}
    references=[]
    for name in ('out','back'):
        part=walk[name]
        assert type(part) is dict and set(part)=={'duration','starts','dequeues','nativeRef','finishes','dequeuedAt'}
        assert type(part['duration']) is int and part['duration']==-1 and type(part['starts']) is int and part['starts']==1
        assert type(part['dequeues']) is int and part['dequeues']==1,'native walk did not dequeue exactly once'
        assert isinstance(part['nativeRef'],str) and part['nativeRef'] not in ('','nil','false')
        references.append(part['nativeRef'])
        assert type(part['dequeuedAt']) is int and edit['at']<part['dequeuedAt']<=points[2]['client']['at']
        finishes=part['finishes'];assert type(finishes) is list and len(finishes)==1
        assert set(finishes[0])=={'phase','succeeded','at'} and finishes[0]['phase']=='perform' and finishes[0]['succeeded'] is True
        assert type(finishes[0]['at']) is int and edit['at']<finishes[0]['at']<=part['dequeuedAt']
    assert len(set(references+[edit['frontNativeBefore'],row['body']['nativeRef']]))==4,'native walking reused another action allocation'
    kit=dict(ids['baseline']['kit'],uses=4)
    for name,target in (('outEndpoint',out),('returnedOrigin',origin)):
        witness=walk[name]
        assert type(witness) is dict and set(witness)=={'at','placement','source','kit'}
        assert type(witness['at']) is int and edit['at']<witness['at']<=points[2]['client']['at']
        assert witness['placement']==dict(tile=target,square=target),'native walk endpoint/current square differs'
        assert witness['kit']==kit,'native world walk changed paid kit charge/ownership'
        actual=witness['source'];baseline=ids['baseline']['supply']
        assert type(actual) is dict and set(actual)==set(baseline)
        assert {k:v for k,v in actual.items() if k!='access'}=={k:v for k,v in baseline.items() if k!='access'},'native walk changed exact source members/identity'
        assert type(actual['access']) is dict and set(actual['access'])=={'blocked'} and type(actual['access']['blocked']) is bool
        if name=='returnedOrigin':assert actual==baseline,'returned source is no longer the original accessible source'
    assert walk['out']['finishes'][0]['at']<=walk['back']['finishes'][0]['at'] and walk['outEndpoint']['at']<=walk['returnedOrigin']['at'],'native out/return completion order differs'


def expected_hands(ids,phase):
    result={}
    for slot,name in HELD_SPECS[ids['case']][phase].items():
        result[slot]=False if name is False else dict(id=ids['items'][name],kind=ids['types'][name],root=True,sameReference=True,container='root',equipParent=True)
    return result


def check_pending_hands(value,ids):
    spec=HELD_SPECS[ids['case']];expected=expected_hands(ids,'post')
    for slot,hand in value['hands'].items():
        if spec['initial'][slot]=='kit' and spec['post'][slot] is False:
            if hand is False:continue
            assert hand['id']==ids['items']['kit'] and hand['kind']==ids['types']['kit'],'pending hand has an unknown item'
            if hand['root']:assert hand['sameReference'] is True and hand['container']=='root' and hand['equipParent'] is True,'pending held kit lost exact root ownership'
            else:assert hand['sameReference'] is False and hand['container'] is False,'pending detached kit has fabricated root ownership'
        else:assert hand==expected[slot],'pending hand lost an unrelated/retained native item'


def check_equip_writer(row,ids,kind):
    if kind!='deny-equip':
        assert not row.get('equipWriter'),'unexpected native equipment writer'
        return
    writer=row['equipWriter']
    assert type(writer) is dict and set(writer)=={'item','primary','twoHands','duration','starts','nativeRef','finishes'}
    assert writer['item']==ids['items']['hammer'] and writer['primary'] is True and writer['twoHands'] is False
    assert type(writer['duration']) is int and writer['duration']==50 and type(writer['starts']) is int and writer['starts']==1
    assert isinstance(writer['nativeRef'],str) and writer['nativeRef'] not in ('','nil','false',row['body']['nativeRef'],row['edit']['frontNativeBefore'])
    finishes=writer['finishes'];assert type(finishes) is list and len(finishes)==1
    assert set(finishes[0])=={'phase','succeeded','at'} and finishes[0]['phase']=='perform' and finishes[0]['succeeded'] is True
    assert type(finishes[0]['at']) is int and finishes[0]['at']<=row['body']['finishes'][0]['at']


def check_owned_effect(row,selection,receipt):
    """Inspect owned paid effects directly, including final use and exact hands."""
    ids=row['ids'];case=row['id'];native=selection['mode']=='native';kind=MOVE_KINDS[case];depleted=case in FINAL_USE_CASES
    initial_uses=1 if depleted else 5
    assert selection['kind']=='mp' and row['status']=='passed' and (ids.get('depletion') is True)==depleted
    assert ids['target']==TARGET and ids['oldType']==OLD and ids['alternate']==ALTERNATE and ids['different']==DIFFERENT
    assert ids['slot']==SLOT and ids['otherSlot']==OTHER_SLOT and ids['producer']=='ISMakeUpUI.onApplyMakeUp' and ids['duration']==1
    assert type(ids['actor']) is int and type(ids['kitUses']) is int and ids['kitUses']==initial_uses and ids['kitType']=='Eyes'
    assert row['nativeMethodsUnchanged'] is True and row['second'] is False
    base=ids['baseline'];base_root=snapshot(base,ids);kit_id=ids['items']['kit']
    assert base['kit']['uses']==initial_uses and base['frontPages']==ids['frontInitial'] and base['middlePages']==ids['middleInitial'] and base['tailPages']==ids['tailInitial']
    assert not any(w['slot'] in (SLOT,OTHER_SLOT,'base:makeup_fullface','base:makeup_lips') for w in base['worn'])
    reserved=set(base_root)|set(ids['items'].values())
    if 'supply' in ids:
        source=base['supply'];reserved.update(v['id'] for v in source['items'])
        for ancestor in source['ancestors']:
            reserved.add(ancestor['id']);reserved.update(v['id'] for v in ancestor['items'])
        if source['world'] and source['world']['kind']=='world-bag':reserved.add(source['world']['id'])
    submitted=row['submitted'];assert type(submitted) is dict and set(submitted)=={'id','kind','slot','root','previous'}
    assert type(submitted['id']) is int and submitted['id'] not in reserved and submitted['kind']==TARGET and submitted['slot']==SLOT and submitted['root'] is False and submitted['previous'] is False
    output=row['output'];assert type(output) is int and output not in reserved|{submitted['id']},'final use did not create one distinct native paid output'
    expected_root=dict(base_root)
    if depleted:expected_root.pop(kit_id,None)
    expected_root[output]=TARGET
    points=row['checkpoints'];assert [point['authority']['label'] for point in points]==['baseline','preview','after-body','final']
    for sequence,point in enumerate(points,1):
        client,authority=point['client'],point['authority'];label=client['label'];paid=label in ('after-body','final')
        assert set(point)=={'client','authority'} and client['case']==authority['case']==case
        assert client['sequence']==authority['sequence']==sequence and type(client['at']) is int and type(authority['at']) is int
        assert set(client)=={'case','label','sequence','at','snapshot','preview','render','bodyUnallocated','edit'}
        assert set(authority)=={'case','label','sequence','at','snapshot'} and type(client['bodyUnallocated']) is bool
        if label=='preview':
            assert client['preview']==submitted and client['bodyUnallocated'] is True
            check_avatar(client['preview'],client['render'],TARGET,SLOT,False,reserved,native)
        else:assert client['render'] is False
        assert client['edit']==(row['edit'] if paid else False)
        for role,value in (('client',client['snapshot']),('authority',authority['snapshot'])):
            found=snapshot(value,ids)
            assert found==(expected_root if paid else base_root),'final-use physical root conservation differs at '+label+'/'+role
            if paid and depleted:assert value['kit'] is False,'final-use kit still physically present at '+label+'/'+role
            else:assert value['kit']['uses']==initial_uses-int(paid),'owned kit cost differs at '+label+'/'+role
            worn=worn_identity(base)
            if label=='preview' and native:worn=desired_worn(base,ids,submitted['id'],TARGET,SLOT)
            if paid:
                worn=desired_worn(base,ids,output,TARGET,SLOT,True)
                if kind=='deny-writer':worn=sorted([w for w in worn if w['slot']!='base:socks']+[dict(id=ids['items']['writer'],kind=ids['types']['writer'],slot='base:socks',root=True)],key=lambda w:w['slot'])
            assert worn_identity(value)==worn,'owned effect worn identities differ at '+label+'/'+role
            if ids.get('held'):assert value['hands']==expected_hands(ids,'post' if paid else 'initial'),'owned effect exact hands differ at '+label+'/'+role
            if label in ('baseline','preview'):assert value['tailPages']==ids['tailInitial']
            if label=='baseline':assert client['bodyUnallocated'] is True
            if label=='final':assert value['tailPages']==ids['tailTotal']
    assert row['clientFinal']==points[-1]['client']['snapshot'] and receipt['snapshot']==points[-1]['authority']['snapshot']
    assert receipt['case']==case and receipt['sequence']==len(points)
    before=row['beforeTail'];assert type(before) is dict and set(before)=={'at','snapshot'} and type(before['at']) is int
    actual=before['snapshot'];found=snapshot(actual,ids,transition=True)
    assert actual['tailPages']==ids['tailInitial'],'tail was consumed before its real native start'
    expected_before=dict(base_root)
    if actual['kit'] is False:expected_before.pop(kit_id,None)
    else:assert actual['kit']['uses'] in ((1,) if depleted else (4,5)),'before-tail retained kit cost differs'
    if output in found:expected_before[output]=TARGET
    assert found==expected_before,'before-tail physical root identities changed beyond native output/removal packets'
    # Only the paid cosmetic slot can still be converging across packets. The
    # known writer socks have their separate exact transition proof above.
    changed_slots={SLOT}|({'base:socks'} if kind=='deny-writer' else set())
    assert [w for w in actual['worn'] if w['slot'] not in changed_slots]==[w for w in base['worn'] if w['slot'] not in changed_slots],'before-tail unrelated worn records changed'
    target=[w for w in actual['worn'] if w['slot']==SLOT]
    baseline_target=[w for w in base['worn'] if w['slot']==SLOT]
    if target!=baseline_target:
        assert len(target)==1,'before-tail cosmetic slot has no exact transition'
        worn=target[0]
        paid_transition=worn['id']==output and worn['kind']==TARGET
        preview_transition=native and worn==dict(id=submitted['id'],kind=TARGET,slot=SLOT,root=False,sameReference=False,container=False)
        assert paid_transition or preview_transition,'before-tail cosmetic slot has an unknown item/reference'
    if ids.get('held'):check_pending_hands(actual,ids)
    check_native_paid(row['body'],row['outcomes'],ids)
    return dict(avatarVerified=True,identityVerified=True,authoritative=True,tailCompleted=True,paid=True,depletionVerified=depleted,handsVerified=ids.get('held') is True,nativePreviewControl=native)


def check_move_case(row,selection,prepared,receipt):
    """Validate actual move evidence, then reuse the established UI/output proof.

    The projection removes only move-bank bookkeeping and checks reader progress
    separately below; it does not waive kit cost, physical output or old removal.
    """
    ids=row['ids'];case=row['id'];toolkit=selection['mode']=='toolkit';kind=MOVE_KINDS[case]
    assert case in MOVE_KINDS and ids.get('move') is True and ids==prepared and row['receipt']==receipt
    assert (ids.get('depletion') is True)==(case in FINAL_USE_CASES),'unexpected depletion contract'
    assert (ids.get('held') is True)==(case in HELD_MOVE_CASES),'unexpected held contract'
    held=HELD_SPECS.get(case)
    if held:assert ids.get('handSpec')==dict(initial=held['initial'],post=held['post']) and ids['kitUses']==held['uses']
    else:assert 'handSpec' not in ids
    assert ('supply' in ids)==(case in MOVE_SUPPLIES) and 'wearPending' not in ids
    if case in MOVE_SUPPLIES:assert ids['supply']['kind']==MOVE_SUPPLIES[case],'makeup source topology differs from case'
    has_hammer=held and any(v=='hammer' for phase in ('initial','post') for v in held[phase].values())
    names={'kit','front','middle','tail'}|({'hammer'} if has_hammer else set())|({'old'} if case=='move-earlier' else set())|({'writer'} if kind=='deny-writer' else set())
    assert set(ids['items'])==set(ids['types'])==names and len(set(ids['items'].values()))==len(names)
    assert ids['types']==dict(kit='Base.MakeupEyeshadow',front='Base.BookCarpentry1',middle='Base.BookCooking1',tail='Base.BookFirstAid1',
        **({'old':OLD} if 'old' in names else {}),**({'writer':'Base.Socks_Ankle'} if 'writer' in names else {}),**({'hammer':'Base.Hammer'} if has_hammer else {}))
    assert ids['frontInitial']==ids['frontTotal']-(3 if case in MOVE_SUPPLIES or case in DEPLETION_MOVE_CASES or case in HELD_MOVE_CASES else 8) and ids['middleInitial']==ids['middleTotal']-1
    assert type(ids['placement']) is dict and set(ids['placement'])=={'x','y','z'} and all(type(v) is int for v in ids['placement'].values())
    points=row['checkpoints'];assert [p['client']['label'] for p in points]==['baseline','preview','after-body','final']
    values=[ids['baseline'],row['clientFinal'],receipt['snapshot'],*[p[role]['snapshot'] for p in points for role in ('client','authority')]]
    for value in values:snapshot(value,ids)
    snapshot(row['beforeTail']['snapshot'],ids,transition=case in FINAL_USE_CASES)
    for point in points:
        for role in ('client','authority'):
            value=point[role]['snapshot'];label=point[role]['label']
            if label in ('baseline','preview'):
                assert value['middlePages']==ids['middleInitial'] and value['frontPages']==ids['frontInitial']
            if label=='final':assert value['middlePages']==ids['middleTotal'] and value['frontPages']==ids['frontTotal']
    assert row['clientFinal']==points[-1]['client']['snapshot'] and receipt['snapshot']==points[-1]['authority']['snapshot'],'move final publication differs'
    assert ids['baseline']['frontPages']==ids['frontInitial'] and ids['baseline']['middlePages']==ids['middleInitial']
    before_tail=row['beforeTail']['snapshot']
    assert before_tail['frontPages']==ids['frontTotal'] and before_tail['middlePages']==ids['middleTotal'],'independent readers did not finish before tail'
    before,after,starts,accepted=move_orders(case,toolkit);edit=row['edit']
    assert set(edit)=={'at','accepted','reason','before','after','bodyUnallocated','ownershipPreserved','frontPages','frontDelta','frontNativeBefore','frontNativeAfter','frontRetained','tailRetained'}|({'hands'} if held else set())
    if held:assert edit['hands']==expected_hands(ids,'initial'),'held kit was not the exact live input at move admission'
    assert type(edit['at']) is int and edit['accepted'] is accepted and edit['before']==before and edit['after']==after,'move admission/queue order differs'
    assert edit['bodyUnallocated'] is True and edit['ownershipPreserved'] is True and edit['frontRetained'] is True and edit['tailRetained'] is True,'move changed operation ownership or independent readers'
    assert type(edit['frontPages']) is int and ids['frontInitial']<edit['frontPages']<ids['frontTotal']
    assert type(edit['frontDelta']) in (int,float) and 0<edit['frontDelta']<1
    assert isinstance(edit['frontNativeBefore'],str) and edit['frontNativeBefore'] not in ('','nil','false')
    if kind!='promote' or not accepted:assert edit['frontNativeAfter']==edit['frontNativeBefore'],'pending edit replaced native active reader'
    if accepted or not toolkit:assert edit['reason'] is False
    else:assert isinstance(edit['reason'],str) and edit['reason'],'unsafe move has no denial reason'
    assert row['startOrder']==starts,'native start order differs from requested move/control'
    assert row['supplyTransferStarts']==0 and type(row['supplyTransferStarts']) is int and not row.get('applyQueues'),'move bank manufactured transfers or an empty application queue'
    resumed=accepted and kind=='promote'
    if resumed:
        resume=row['readerResume'];assert set(resume)=={'pages','resumedPages','native'} and resume['pages']==edit['frontPages']
        assert type(resume['resumedPages']) is int and edit['frontPages']<=resume['resumedPages']<ids['frontTotal'],'native reader resume lost its checkpoint'
        assert isinstance(resume['native'],str) and resume['native'] not in ('','nil','false',edit['frontNativeBefore']),'native reader did not restart after promotion'
    else:assert not row.get('readerResume')
    if case=='move-earlier':
        initial=[ids['baseline'],points[0]['client']['snapshot'],points[0]['authority']['snapshot']]
        for value in initial:
            assert any(w['id']==ids['items']['old'] and w['root'] and w['sameReference'] and w['container']=='root' for w in value['worn']),'old cosmetic was not exact root-owned worn Clothing'
    if kind=='deny-writer':
        original_socks=[w for w in ids['baseline']['worn'] if w['slot']=='base:socks']
        assert all(w['id']!=ids['items']['writer'] and w['root'] and w['sameReference']
                   and w['container']=='root' for w in original_socks),'writer baseline is not exact original root clothing'
        writer_socks=[dict(id=ids['items']['writer'],kind=ids['types']['writer'],slot='base:socks',
                           root=True,sameReference=True,container='root')]
        for point in points:
            for role in ('client','authority'):
                expected=original_socks if point[role]['label'] in ('baseline','preview') else writer_socks
                assert [w for w in point[role]['snapshot']['worn'] if w['slot']=='base:socks']==expected,'actor writer slot transition differs'
        for value in (row['beforeTail']['snapshot'],row['clientFinal'],receipt['snapshot']):
            assert [w for w in value['worn'] if w['slot']=='base:socks']==writer_socks,'actor writer did not retain exact physical worn output'
    check_walk(row,ids,edit,points)
    check_equip_writer(row,ids,kind)
    if case in DEPLETION_MOVE_CASES or case in HELD_MOVE_CASES:
        result=check_owned_effect(row,selection,receipt)
        result.update(moveVerified=accepted,moveProtected=toolkit and not accepted,readerResumed=resumed)
        return result
    # Preserve the old proof's renderer, callback, authoritative body receipt,
    # exact root/output identity, one-use charge and correct old removal checks.
    projected=copy.deepcopy(row);pid=projected['ids'];alias='apply-replace' if case=='move-earlier' else 'apply-empty'
    projected['id']=pid['case']=alias;pid.pop('move');pid.pop('supply',None);pid.pop('placement');pid['frontInitial']=pid['frontTotal']-3
    for name in ('middle','writer'):pid['items'].pop(name,None);pid['types'].pop(name,None)
    projected['edit']=False
    pvalues=[pid['baseline'],projected['clientFinal'],projected['receipt']['snapshot'],projected['beforeTail']['snapshot']]
    for point in projected['checkpoints']:
        for role in ('client','authority'):
            point[role]['case']=alias
            if role=='client':point[role]['edit']=False
            pvalues.append(point[role]['snapshot'])
    projected['receipt']['case']=alias
    for value in pvalues:
        value['case']=alias;value.pop('middlePages');value.pop('placement');value.pop('supply',None)
        if case in MOVE_SUPPLIES:
            value['kit']['root']=True;value['root'].append(dict(id=pid['items']['kit'],kind=pid['types']['kit']));value['root'].sort(key=lambda v:v['id'])
        # Both the original and replacement socks are validated above. Remove
        # this one known writer slot before checking all remaining worn slots.
        if kind=='deny-writer':value['worn']=[w for w in value['worn'] if w['slot']!='base:socks']
        value['frontPages']=pid['frontInitial'] if value['kit']['uses']==5 else pid['frontTotal']
    for point in projected['checkpoints']:
        if point['client']['label'] in ('baseline','preview'):
            point['client']['snapshot']['frontPages']=pid['frontInitial'];point['authority']['snapshot']['frontPages']=pid['frontInitial']
    result=check_case(projected,selection,pid,projected['receipt'])
    result.update(moveVerified=accepted,moveProtected=toolkit and not accepted,readerResumed=resumed)
    return result


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
    if raw(text,'WALK')!=[dict(case=row['id'],label=label,evidence=(row.get('walk') if type(row.get('walk')) is dict else {}).get(label)) for row in results if MOVE_KINDS.get(row.get('id'))=='deny-walk' for label in ('outEndpoint','returnedOrigin')]:issues.append('Raw makeup native walking witnesses differ')
    if raw(text,'OUTCOME')!=[dict(case=row['id'],receipt=receipt) for row in results for receipt in row.get('outcomes',[])]:issues.append('Raw makeup native outcomes differ')
    if raw(text,'BEFORE_TAIL')!=[dict(case=row['id'],evidence=row.get('beforeTail')) for row in results]:issues.append('Raw makeup tail boundary differs')
    if raw(text,'EDIT')!=[dict(case=row['id'],evidence=row.get('edit')) for row in results if cancelling(row.get('id','')) or row.get('id') in MOVE_KINDS]:issues.append('Raw makeup pending edit differs')
    if (selection.get('options',{}).get('makeup_supplies') is True or moving(selection)) and (not prepared or any(value.get('placement')!=prepared[0].get('placement') for value in prepared)):
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
        try:outcome=(check_move_case if moving(selection) else check_case)(row,selection,prepared[i],verified[i])
        except (AssertionError,KeyError,TypeError,ValueError,IndexError) as error:problems.append(str(error)or'makeup evidence differs')
        issues.extend(row.get('id','?')+': '+problem for problem in problems)
        outcomes.append(dict(actor='client1',case=row.get('id'),status='failed' if problems else'passed',outcome=outcome))
    return dict(issues=issues,outcomes=outcomes)
