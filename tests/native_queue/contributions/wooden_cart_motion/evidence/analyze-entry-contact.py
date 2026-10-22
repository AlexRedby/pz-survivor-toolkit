#!/usr/bin/env python3
"""Diagnostic sampled whole-trouser/lower-body contact, including world-cart entry.

No full-rendered-frame PASS is produced. Held transforms are same-slot captures;
world transforms are nearest exact-item visible Ready draws within 40 ms.

Inputs are explicit native profile/log/game/FBX paths. Geometry helpers live beside
this script. --self-check needs NumPy but no game files or investigation outputs.
Exit codes: 0 = clear captured samples with evidence, 1 = ordinary contact,
2 = missing evidence. None establishes every rendered frame.
"""
import argparse
import bisect
from collections import Counter, defaultdict
import importlib.util
import json
from pathlib import Path
import re
import sys

import numpy as np


PAIR_LIMIT = 40
COVERAGE_GAP = 50


def load_geometry():
    evidence = Path(__file__).resolve().parent
    sys.path.insert(0, str(evidence))
    import actual_mesh
    import clearance_geometry
    from shaft_components import build_components
    spec = importlib.util.spec_from_file_location('entry_world_basis', evidence/'check-impact-clearance.py')
    basis = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(basis)
    return actual_mesh, clearance_geometry, build_components, basis


def read_rows(path):
    if not path.is_file():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def nearest(rows, times, stamp):
    if not rows:
        return None
    index = bisect.bisect_left(times, stamp)
    return min(rows[max(0,index-1):index+1], key=lambda row: abs(row['wallTimeMillis']-stamp))


def lower_faces(mesh):
    selected = np.zeros(mesh[0], bool)
    names = {'Bip01_Pelvis', 'Bip01_Spine', 'Bip01_L_Thigh', 'Bip01_R_Thigh', 'Bip01_L_Calf', 'Bip01_R_Calf'}
    for name, ids, weights, _ in mesh[1]:
        if name in names:
            selected[ids[weights>0]] = True
    return np.flatnonzero(selected[mesh[3]].any(1))


def required_bones(mesh):
    return {name for name, ids, weights, _ in mesh[1] if len(ids) and (weights>0).any()}


def scene_windows(text, lifecycle, missing):
    events = defaultdict(dict)
    samples = defaultdict(list)
    receipts = defaultdict(list)
    for line in text.splitlines():
        match = re.search(r'\[(CART_APPROACH_EVENT|CART_APPROACH_SAMPLE|CART_ENTRY_CONTACT)\] (\{.*\})', line)
        if not match:
            continue
        row = json.loads(match[2]); key = (row['case'], row['start'])
        if match[1] == 'CART_APPROACH_EVENT':
            if row['event'] in events[key]:
                missing.append(dict(scene=key[0], reason='duplicate event', event=row['event']))
            events[key][row['event']] = row
        elif match[1] == 'CART_APPROACH_SAMPLE':
            samples[key].append(row)
        else:
            receipts[key].append(row)
    scenes = []
    for key, event in sorted(events.items(), key=lambda pair: pair[0][1]):
        absent = {'prepared','queued','terminal','settled'}-event.keys()
        if absent:
            missing.append(dict(scene=key[0], reason='missing phase events', events=sorted(absent)))
            continue
        first=event['prepared']; end=event['settled']['wall']; queued=event['queued']['wall']
        records=samples[key]; expected='ISCartEquipAction' if key[0]=='container-equip' else 'ToolkitWoodCartPickup'
        actions=[row for row in lifecycle if queued<=row['wallTimeMillis']<=end and row.get('metaType')==expected
                 and row.get('phase')=='exit' and row.get('threw') is None]
        boundaries={}
        identities=set()
        for name in ('start','perform','complete'):
            selected=[row for row in actions if row.get('event')==name]
            if len(selected)!=1:
                missing.append(dict(scene=key[0], reason='missing/ambiguous native lifecycle', action=expected, event=name, count=len(selected)))
            else:
                boundaries[name]=selected[0]['wallTimeMillis']; identities.add(selected[0].get('nativeActionId'))
        if len(identities)>1:
            missing.append(dict(scene=key[0], reason='native lifecycle identity changed'))
        if not first['wall']<=queued<=event['terminal']['wall']<=end:
            missing.append(dict(scene=key[0], reason='unordered phase bounds'))
        proofs=[first]+records+receipts[key]
        outfit=bool(proofs) and all(row.get('entryContactRepro') is True and row.get('female') is False
            and row.get('pantsType')=='Base.Trousers_JeanBaggy'
            and str(row.get('pantsModel','')).lower().replace('\\','/').removesuffix('.x')=='skinned/clothes/bob_trousers'
            and row.get('pantsID')==first.get('pantsID') for row in proofs)
        if not outfit:
            missing.append(dict(scene=key[0], reason='missing actual male baggy-jeans model/outfit receipts'))
        full=bool(proofs) and all(abs(row.get('cargoWeight',-100)-row.get('cargoCapacity',100))<.01 for row in proofs)
        if not full:
            missing.append(dict(scene=key[0], reason='missing full-cargo receipt'))
        if end-event['terminal']['wall']<1000:
            missing.append(dict(scene=key[0], reason='held tail shorter than 1000 ms'))
        scenes.append(dict(name=key[0], start=first['wall'], queued=queued, terminal=event['terminal']['wall'],
            settled=end, item=first['id'], events=event, lifecycle=boundaries, samples=records,
            sampleTimes=[row['wall'] for row in records], outfitVerified=outfit, fullCargoVerified=full))
    if not scenes:
        missing.append(dict(reason='no complete approach windows; contacts are bootstrap/setup diagnostics only'))
    return scenes


def phase_at(scenes, stamp):
    for scene in scenes:
        if not scene['start']<=stamp<=scene['settled']:
            continue
        if stamp<scene['queued']: phase='pre_menu'
        elif stamp<scene['lifecycle'].get('start',scene['terminal']): phase='native_approach_or_queue'
        elif stamp<scene['lifecycle'].get('complete',scene['terminal']):
            phase='inventory_equip' if scene['name']=='container-equip' else 'ground_pickup'
        elif stamp<scene['terminal']: phase='post_complete_handoff'
        else: phase='held_tail'
        return scene,phase
    return None,'bootstrap_setup'


def phase_bounds(scene):
    action=scene['lifecycle']; start=action.get('start',scene['terminal']); complete=action.get('complete',scene['terminal'])
    return [('pre_menu',scene['start'],scene['queued']),
            ('native_approach_or_queue',scene['queued'],start),
            ('inventory_equip' if scene['name']=='container-equip' else 'ground_pickup',start,complete),
            ('post_complete_handoff',complete,scene['terminal']),('held_tail',scene['terminal'],scene['settled'])]


def analyze(profile, log, game, mesh_path, *, _geometry=None):
    actual, geometry, components, basis=load_geometry() if _geometry is None else _geometry
    missing=[]
    vertices,actual.components=components(mesh_path)
    native,_=geometry.shafts(profile/'WheelbarrowWood.bin')
    source={tuple(value) for value in np.round(vertices,7)}
    if not all(tuple(value) in source for value in np.round(native,7)):
        raise ValueError('native VBO does not match original FBX with the measured import Z reflection')
    if not all(solid['closed'] or len(solid['vertices'])==16 for solid in actual.components):
        raise ValueError('shaft topology differs from the calibrated closed/open components')
    models={(female,pants):geometry.model(game,female,pants) for female in (False,True) for pants in (False,True)}
    faces={(female,pants):(np.arange(len(mesh[3])) if pants else lower_faces(mesh)) for (female,pants),mesh in models.items()}
    for mesh in models.values():
        total=np.zeros(mesh[0])
        for _,ids,weights,_ in mesh[1]: total[ids]+=weights
        if np.max(abs(total[mesh[3]]-1))>1e-4:
            raise ValueError('unweighted native geometry in selected body/trouser faces')
    held=read_rows(profile/'body-clearance.jsonl');tails=read_rows(profile/'action-tail-poses.jsonl')
    worlds=read_rows(profile/'world-cart-poses.jsonl');lifecycle=read_rows(profile/'action-lifecycle.jsonl')
    scenes=scene_windows(log.read_text(),lifecycle,missing)
    for name,rows in [('body-clearance',held),('full-tail',tails),('world-cart',worlds)]:
        if not rows: missing.append(dict(reason='missing capture stream', stream=name))
    frames=[];valid_held=[];failed=Counter();world_pair_gaps=[]

    def evaluate(row,convert,presentation,world=None):
        stamp=row['wallTimeMillis'];scene,phase=phase_at(scenes,stamp)
        female=row.get('female')
        if type(female) is not bool:
            failed['invalid sex']+=1;return False
        if scene and female:
            failed['scene actor is female']+=1;return False
        frame=dict(time=stamp,scene=scene['name'] if scene else None,phase=phase,presentation=presentation,
            female=female,outfitVerified=bool(scene and scene['outfitVerified']),
            itemId=scene['item'] if scene else None)
        if world is not None:
            frame.update(itemId=world['itemId'],pairingGapMs=world['wallTimeMillis']-stamp,worldTime=world['wallTimeMillis'],worldSource=world.get('source'))
        for pants in (False,True):
            mesh=models[female,pants]
            absent=required_bones(mesh)-row.get('bones',{}).keys()
            if absent:
                failed['missing native influencing bones']+=1
                return False
            body=geometry.skin(row,mesh)
            local=(np.c_[body,np.ones(len(body))]@convert.T)[:,:3]
            if not np.isfinite(local).all():
                failed['nonfinite geometry']+=1;return False
            indices=faces[female,pants]
            for shaft in 'LR':
                hits=indices[np.flatnonzero(actual.intersects(local[mesh[3][indices]],shaft))]
                frame[('pants' if pants else 'lowerBody')+shaft]=len(hits)
                if len(hits):frame[('pants' if pants else 'lowerBody')+shaft+'FaceIndices']=hits.tolist()
        frames.append(frame)
        return True

    for row in held:
        if row.get('model')!='WheelbarrowWood':continue
        try:
            matrix=np.asarray(row['cart'],dtype=float).reshape(4,4).T
            if evaluate(row,np.linalg.inv(matrix),'held_same_slot'): valid_held.append(row)
        except (ValueError,KeyError,np.linalg.LinAlgError) as error:
            failed['invalid held matrix: '+str(error)]+=1
    valid_held.sort(key=lambda row:row['wallTimeMillis']);held_times=[row['wallTimeMillis'] for row in valid_held]
    coverage=defaultdict(list);not_applicable=Counter();pair_failures=[]
    for scene in scenes:
        item_worlds=[row for row in worlds if row.get('itemId')==scene['item']]
        item_worlds.sort(key=lambda row:row['wallTimeMillis']);item_world_times=[row['wallTimeMillis'] for row in item_worlds]
        visible=[row for row in worlds if row.get('itemId')==scene['item'] and row.get('renderStatus')=='Ready'
                 and row.get('alpha',0)>0 and scene['start']-PAIR_LIMIT<=row['wallTimeMillis']<=scene['settled']+PAIR_LIMIT]
        visible.sort(key=lambda row:row['wallTimeMillis']);visible_times=[row['wallTimeMillis'] for row in visible]
        for row in tails:
            stamp=row['wallTimeMillis'];current,phase=phase_at(scenes,stamp)
            if current is not scene:continue
            key=(scene['name'],phase)
            sample_index=bisect.bisect_right(scene['sampleTimes'],stamp)-1
            sample=scene['samples'][sample_index] if sample_index>=0 else scene['events']['prepared']
            sample_age=stamp-sample['wall']
            if not 0<=sample_age<=100:
                pair_failures.append(dict(scene=scene['name'],time=stamp,phase=phase,reason='ownership sample gap',gapMs=sample_age));continue
            if row.get('female') is not False or any(required_bones(models[False,pants])-row.get('bones',{}).keys() for pants in (False,True)):
                pair_failures.append(dict(scene=scene['name'],time=stamp,phase=phase,reason='missing full native male tail palette'));continue
            held_row=nearest(valid_held,held_times,stamp)
            held_ok=held_row is not None and abs(held_row['wallTimeMillis']-stamp)<=PAIR_LIMIT and phase_at(scenes,held_row['wallTimeMillis'])[0] is scene
            world=nearest(visible,visible_times,stamp)
            world_ok=False
            state_index=bisect.bisect_right(item_world_times,stamp)-1
            state=item_worlds[state_index] if state_index>=0 else None
            # Never carry a previously visible world cart through its explicit
            # suppression or native removal into the held phase.
            visible_now=state is not None and state.get('renderStatus')=='Ready' and state.get('alpha',0)>0
            complete=scene['lifecycle'].get('complete')
            after_removal=complete is not None and stamp>complete and (world is None or world['wallTimeMillis']<complete)
            if visible_now and not after_removal and world is not None and abs(world['wallTimeMillis']-stamp)<=PAIR_LIMIT:
                try:
                    convert=np.linalg.inv(basis.world_matrix(world))@basis.actor_matrix(row)
                    world_ok=evaluate(row,convert,'world_nearest_draw',world)
                    if world_ok:world_pair_gaps.append(world['wallTimeMillis']-stamp)
                except (ValueError,KeyError,np.linalg.LinAlgError) as error:
                    failed['invalid world/actor matrix: '+str(error)]+=1
            if held_ok or world_ok:
                coverage[key].append(stamp)
            elif sample.get('containerCount')==1 and sample.get('primaryID')==-1 and not row.get('cartModel'):
                # A cart inside a bag has no displayed shafts to intersect.
                not_applicable[key]+=1;coverage[key].append(stamp)
            else:
                pair_failures.append(dict(scene=scene['name'],time=stamp,phase=phase,
                    reason='no synchronized visible world or held geometry',cartModel=row.get('cartModel'),
                    nearestWorldGapMs=None if world is None else world['wallTimeMillis']-stamp,
                    nearestHeldGapMs=None if held_row is None else held_row['wallTimeMillis']-stamp))
    summaries=[]
    for scene in scenes:
        phases=[]
        for phase,start,end in phase_bounds(scene):
            if end<start:
                missing.append(dict(scene=scene['name'],phase=phase,reason='negative native phase duration'));continue
            stamps=sorted(set(t for t in coverage[scene['name'],phase] if start<=t<=end))
            gaps=[b-a for a,b in zip(stamps,stamps[1:])]
            complete=(end==start or bool(stamps) and stamps[0]-start<=COVERAGE_GAP and end-stamps[-1]<=COVERAGE_GAP and max(gaps,default=0)<=COVERAGE_GAP)
            if not complete:missing.append(dict(scene=scene['name'],phase=phase,reason='phase coverage gap',start=start,end=end,first=stamps[0] if stamps else None,last=stamps[-1] if stamps else None,maxGapMs=max(gaps,default=None)))
            rows=[frame for frame in frames if frame['scene']==scene['name'] and frame['phase']==phase]
            contacts=[frame for frame in rows if any(frame[k] for k in ('pantsL','pantsR','lowerBodyL','lowerBodyR'))]
            phases.append(dict(phase=phase,start=start,end=end,durationMs=end-start,geometryObservations=len(rows),coverageAnchors=len(stamps),
                hiddenContainerAnchors=not_applicable[scene['name'],phase],sampleCoverageComplete=complete,
                maxCoverageGapMs=max(gaps,default=None),contactObservations=len(contacts),contactTimes=sorted({frame['time'] for frame in contacts}),
                pantsContactObservations={side:sum(frame['pants'+side]>0 for frame in rows) for side in 'LR'},
                lowerBodyContactObservations={side:sum(frame['lowerBody'+side]>0 for frame in rows) for side in 'LR'}))
        summaries.append(dict(scene=scene['name'],itemId=scene['item'],outfitVerified=scene['outfitVerified'],fullCargoVerified=scene['fullCargoVerified'],nativeLifecycle=scene['lifecycle'],phases=phases))
    if failed:missing.append(dict(reason='unusable geometry rows',counts=dict(failed)))
    if pair_failures:missing.append(dict(reason='unpaired/missing full-tail observations',count=len(pair_failures)))
    bootstrap_worlds=[row for row in worlds if row.get('renderStatus')=='Ready' and row.get('alpha',0)>0
                      and phase_at(scenes,row['wallTimeMillis'])[0] is None]
    if bootstrap_worlds:
        missing.append(dict(reason='visible bootstrap/setup world draws lack an exact-item phase receipt; not paired',count=len(bootstrap_worlds),
                            first=bootstrap_worlds[0]['wallTimeMillis'],last=bootstrap_worlds[-1]['wallTimeMillis']))
    contacts=[row for row in frames if any(row[k] for k in ('pantsL','pantsR','lowerBodyL','lowerBodyR'))]
    ordinary=[row for row in contacts if row['phase']!='bootstrap_setup']
    setup=[row for row in contacts if row['phase']=='bootstrap_setup']
    if not tails and scenes:missing.append(dict(reason='no tail anchors; cannot establish world/held handoff coverage'))
    return dict(schema='cart-entry-geometry-diagnostic-v1',
        status='contacts_observed' if ordinary else 'insufficient_evidence' if missing else 'no_contacts_in_captured_samples',
        fullRenderedFramePass=None,scope='Whole native Bob/Kate_Trousers faces and body faces influenced by Pelvis/Spine/Thigh/Calf versus both actual wooden shafts; sampled SP diagnostic.',
        limits=dict(worldPairMaximumMs=PAIR_LIMIT,phaseCoverageMaximumGapMs=COVERAGE_GAP,held='same-slot body/cart matrices; cart item inferred from exact scene receipts',
                    world='nearest exact-item Ready alpha>0 draw; asynchronous sampling, no pose interpolation',
                    pants='actual male baggy-jeans receipt required for ordinary scene claims; setup pants remain reference geometry',
                    allRenderedFrames=False,prePreparedWorldGeometry='not paired without an exact-item scene receipt'),
        mesh=dict(nativeVboVerified=True,shaftComponents=len(actual.components),malePantsFaces=len(models[False,True][3]),maleLowerBodyFaces=len(faces[False,False])),
        streams=dict(held=len(held),tails=len(tails),worlds=len(worlds),worldPairs=len(world_pair_gaps),maxAbsoluteWorldPairGapMs=max(map(abs,world_pair_gaps),default=None)),
        ordinaryContactObservations=len(ordinary),ordinaryContactTimes=sorted({row['time'] for row in ordinary}),
        bootstrapSetupContactObservations=len(setup),bootstrapSetupContactTimes=sorted({row['time'] for row in setup}),
        missingEvidence=missing,pairingFailures=pair_failures,scenes=summaries,frames=frames)


def self_check():
    """Exercise geometry, full-face coverage and missing-evidence policy without PZ."""
    import copy
    import tempfile
    from types import SimpleNamespace

    actual, geometry, _, basis=load_geometry()
    actual.self_check()
    saved_components=actual.components
    identity=np.eye(4).T.reshape(-1).tolist()
    far=np.array([[3.,-.2,-.2],[3.,.2,-.2],[3.,0.,.2]])
    points=np.concatenate([far,far])
    native_mesh=(6,[
        ('Bip01_Pelvis',np.arange(3),np.ones(3),np.c_[points[:3],np.ones(3)]),
        ('Bip01_L_Calf',np.arange(3,6),np.ones(3),np.c_[points[3:],np.ones(3)])],
        {},np.array([[0,1,2],[3,4,5]]))
    np.testing.assert_array_equal(lower_faces(native_mesh),[0,1])
    assert required_bones(native_mesh)=={'Bip01_Pelvis','Bip01_L_Calf'}
    cube=np.array([[-1,-1,-1],[1,-1,-1],[1,1,-1],[-1,1,-1],
                   [-1,-1,1],[1,-1,1],[1,1,1],[-1,1,1]],dtype=float)*.1
    cube_faces=np.array([[0,2,1],[0,3,2],[4,5,6],[4,6,7],[0,1,5],[0,5,4],
                         [1,2,6],[1,6,5],[2,3,7],[2,7,6],[3,0,4],[3,4,7]])
    solids=[dict(vertices=cube,triangles=cube[cube_faces],closed=True,side='L'),
            dict(vertices=cube+[1,0,0],triangles=(cube+[1,0,0])[cube_faces],closed=True,side='R')]
    native_vertices=np.concatenate([solid['vertices'] for solid in solids])
    fixture_geometry=SimpleNamespace(model=lambda *args:native_mesh,skin=geometry.skin,
                                     shafts=lambda path:(native_vertices,{}))
    loaded=(actual,fixture_geometry,lambda path:(native_vertices,solids),basis)
    base=dict(female=False,slotX=100.,slotY=200.,slotZ=7.,slotAngle=.7,
              bones={'Bip01_Pelvis':identity.copy(),'Bip01_L_Calf':identity.copy()})
    world=dict(itemId=42,renderStatus='Ready',alpha=1.,angle=[13,-27,81],
               x=100.,y=200.,z=7.,transform=identity)
    raw=np.linalg.inv(basis.world_matrix(world))@basis.actor_matrix(base)
    world['transform']=raw.T.reshape(-1).tolist()
    np.testing.assert_allclose(basis.world_matrix(world),basis.actor_matrix(base),atol=1e-10)
    proof=dict(case='wrong-side',start=1000,id=42,entryContactRepro=True,female=False,
               pantsType='Base.Trousers_JeanBaggy',pantsID=123,
               pantsModel='skinned/clothes/bob_trousers',cargoWeight=30,cargoCapacity=30)
    def sample(stamp):
        return dict(proof,wall=stamp,elapsed=stamp-1000,containerCount=0,
                    worldCount=int(stamp<2600),primaryID=42 if stamp>=2600 else -1)
    text='\n'.join('[CART_APPROACH_EVENT] '+json.dumps(dict(sample(stamp),event=event))
                   for event,stamp in [('prepared',1000),('queued',1700),('terminal',2650),('settled',3650)])
    text+='\n'+'\n'.join('[CART_APPROACH_SAMPLE] '+json.dumps(sample(stamp)) for stamp in range(1000,3651,25))
    tails=[dict(base,wallTimeMillis=stamp,cartModel=stamp>=2500) for stamp in range(1000,3651,17)]
    held=[dict(base,wallTimeMillis=stamp,model='WheelbarrowWood',cart=identity) for stamp in range(2500,3651,33)]
    worlds=[dict(world,wallTimeMillis=stamp) for stamp in range(1000,2600,17)]
    lifecycle=[dict(wallTimeMillis=stamp,event=event,phase='exit',threw=None,
                    metaType='ToolkitWoodCartPickup',nativeActionId=1)
               for event,stamp in [('start',2000),('perform',2595),('complete',2600)]]
    checks=[]
    try:
        with tempfile.TemporaryDirectory(prefix='cart-entry-contact-self-check-') as directory:
            root=Path(directory);(root/'capture.log').write_text(text)
            def run(test_tails=tails,test_worlds=worlds,test_lifecycle=lifecycle):
                for name,rows in [('body-clearance.jsonl',held),('action-tail-poses.jsonl',test_tails),
                                  ('world-cart-poses.jsonl',test_worlds),('action-lifecycle.jsonl',test_lifecycle)]:
                    (root/name).write_text(''.join(json.dumps(row)+'\n' for row in rows))
                return analyze(root,root/'capture.log',root,root/'synthetic.fbx',_geometry=loaded)
            result=run()
            assert not result['missingEvidence'],result['missingEvidence']
            assert result['ordinaryContactObservations']==0 and result['fullRenderedFramePass'] is None
            assert all(row.get('worldTime',0)<=2600 for row in result['frames'] if row['presentation']=='world_nearest_draw')
            checks.append('complete sampled clear geometry and actor/world basis')
            # A calf-only triangle lies outside the historical hip-face subset.
            contact=copy.deepcopy(tails)
            row=next(row for row in contact if row['wallTimeMillis']>=2200)
            row['bones']=copy.deepcopy(row['bones'])
            row['bones']['Bip01_L_Calf'][12]=-3.
            hit=run(test_tails=contact)
            selected=[frame for frame in hit['frames'] if frame['time']==row['wallTimeMillis']]
            assert any(frame.get('pantsLFaceIndices')==[1] and frame.get('lowerBodyLFaceIndices')==[1] for frame in selected)
            checks.append('whole trousers include calf-only contact')
            for mode in ('wrong_item','alpha_zero','suppressed_world','missing_palette','sparse_coverage','missing_lifecycle'):
                test_worlds=copy.deepcopy(worlds);test_tails=copy.deepcopy(tails);test_lifecycle=copy.deepcopy(lifecycle)
                if mode=='wrong_item':
                    for row in test_worlds:row['itemId']=99
                elif mode=='alpha_zero':
                    for row in test_worlds:row['alpha']=0
                elif mode=='suppressed_world':
                    test_worlds=[row for row in test_worlds if not 1900<=row['wallTimeMillis']<2100]
                    test_worlds.append(dict(wallTimeMillis=1900,itemId=42,renderStatus='Suppressed',transitionHidden=True))
                    test_worlds.sort(key=lambda row:row['wallTimeMillis'])
                elif mode=='missing_palette':
                    for row in test_tails:row['bones'].pop('Bip01_Pelvis',None)
                elif mode=='sparse_coverage':test_tails=test_tails[::10]
                elif mode=='missing_lifecycle':test_lifecycle=test_lifecycle[:-1]
                rejected=run(test_tails,test_worlds,test_lifecycle)
                assert rejected['missingEvidence'],mode
                assert rejected['status']=='insufficient_evidence',mode
                assert rejected['fullRenderedFramePass'] is None
                checks.append('reject incomplete evidence: '+mode)
    finally:
        actual.components=saved_components
    return dict(selfCheck='PASS',checks=checks,requiresGameAssets=False)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-check',action='store_true',help='Run synthetic geometry/evidence regressions without game files')
    for name in ('profile','log','game','mesh','output'):parser.add_argument('--'+name,type=Path)
    args=parser.parse_args()
    if args.self_check:
        if any(getattr(args,name) is not None for name in ('profile','log','game','mesh','output')):
            parser.error('--self-check runs alone')
        print(json.dumps(self_check(),indent=2));return 0
    for name in ('profile','log','game','mesh','output'):
        if getattr(args,name) is None:parser.error('--'+name+' is required')
    if args.output.exists():parser.error('preserve existing output; choose a fresh report path')
    result=analyze(args.profile,args.log,args.game,args.mesh)
    with args.output.open('x') as target:json.dump(result,target,indent=2,allow_nan=False)
    print(json.dumps({key:value for key,value in result.items() if key not in ('frames','pairingFailures')},indent=2))
    return 1 if result['ordinaryContactObservations'] else 2 if result['missingEvidence'] else 0


if __name__=='__main__':raise SystemExit(main())
