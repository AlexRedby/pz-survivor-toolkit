#!/usr/bin/env python3
"""Verify sampled inventory-equip Host body/shaft geometry against consumed native draws.

Reads an isolated --profile and explicit local --game/--mesh assets; writes JSON to stdout.
A complete protocol and sampled source geometry do not prove GPU garment/all-frame fit.
"""
import sys
sys.dont_write_bytecode = True
import argparse, hashlib, json, math, runpy
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[4]
EV = ROOT/'tests/native_queue/contributions/wooden_cart_motion/evidence'
MP = ROOT/'tests/native_queue/contributions/wooden_cart_multiplayer'
SP = runpy.run_path(str(EV/'analyze-entry-contact.py'))
C = runpy.run_path(str(MP/'analyze.py'))
P = runpy.run_path(str(MP/'analyze-inventory-equip.py'))
require, parse = C['require'], C['parse']
VBO_SHA = '0f99448cda120bad9f324f38bdbf994f8788ab6731473533475fb6eaf3f4c948'
REGIONS = ('trousersL','trousersR','lowerBodyL','lowerBodyR')
def rows(path):
    return [parse(line) for line in path.read_text().splitlines() if line.strip()]
def one(records,event,role):
    result=[r for r in records if r.get('event')==event]
    require(len(result)==1,role+': missing/ambiguous '+event)
    return result[0]
def lower(name): return any(part in name for part in ('Thigh','Calf','Foot','Toe'))
def lower_delta(pair):
    b,a=pair['before']['bones'],pair['after']['bones']
    return max(abs(x-y) for key in b if lower(key) for x,y in zip(b[key],a[key]))
def matrix(value):
    require(isinstance(value,list) and len(value)==16 and all(C['number'](v) for v in value),'Invalid matrix')
    result=np.asarray(value,dtype=float).reshape(4,4).T
    require(abs(np.linalg.det(result))>1e-10,'Singular matrix')
    return result

def main(profile,game,mesh):
    selection=parse((profile/'selection.json').read_text());variant=selection['options']['cart_inventory_equip_variant']
    female,load=P['VARIANTS'][variant];logs={};receipts={}
    for role in ('server','client1','client2'):
        path=profile/role/'console.txt'
        if not path.is_file(): path=profile/(role+'-launch.log')
        logs[role]=path.read_text(errors='replace')
        receipts[role]=[parse(line.split(P['MARKER'],1)[1].rstrip('.')) for line in logs[role].splitlines() if P['MARKER'] in line]
        require(all(r.get('producer')==P['PRODUCER'] and r.get('actor')==role for r in receipts[role]),role+': foreign receipt')
    spec=one(receipts['server'],'spec','server');epoch=one(receipts['server'],'start','server')['epoch']
    require(spec.get('female') is female and spec.get('variant')==variant and spec.get('load')==load
            and spec.get('cartType')=='SaucedWheelbarrow.WheelbarrowWood' and type(spec.get('id')) is int and spec['id']>0
            and type(spec.get('ownerID')) is int and spec['ownerID']>=0,'Invalid authoritative spec')
    for role in ('client1','client2'):
        start=one(receipts[role],'start',role)
        require(start.get('epoch')==epoch and start.get('id')==spec['id'] and start.get('ownerID')==spec['ownerID'],role+': foreign start')
    checks=[r for r in receipts['server'] if r.get('event')=='owner-check']
    require(len(checks)<=1,'Ambiguous authoritative tail')
    analysis_end=checks[0]['wall']+2000 if checks else None
    native={r:rows(profile/r/'inventory-equip-native.jsonl') for r in ('client1','client2')}
    poses={r:rows(profile/r/'body-clearance.jsonl') for r in native};cameras={r:rows(profile/r/'render-camera.jsonl') for r in native}
    try:
        P['analyze_data'](logs,native,poses,cameras,variant);protocol={'status':'evidence_complete','failures':[]}
    except (ValueError,KeyError,AssertionError) as e: protocol={'status':'diagnostic_failure','failures':[str(e)]}
    actual,geometry,components,_=SP['load_geometry']();source,actual.components=components(mesh)
    require(all(p['closed'] or len(p['vertices'])==16 for p in actual.components),'Unexpected shaft topology')
    source={tuple(v) for v in np.round(source,7)}
    models={pants:geometry.model(game,female,pants) for pants in (False,True)}
    faces={pants:np.arange(len(v[3])) if pants else SP['lower_faces'](v) for pants,v in models.items()}
    needed=set().union(*(SP['required_bones'](v) for v in models.values()))
    for pants,value in models.items():
        total=np.zeros(value[0])
        for _,ids,weights,_ in value[1]: total[ids]+=weights
        require(np.max(abs(total[value[3][faces[pants]]]-1))<1e-4,'Unweighted selected native source geometry')
    source_paths={key:game/'media/models_X/Skinned'/name for key,name in
                  [('body','FemaleBody.x' if female else 'MaleBody.x'),
                   ('trousers','Clothes/Kate_Trousers.x' if female else 'Clothes/Bob_Trousers.x')]}
    result=dict(schema='host-equip-geometry-diagnostic-v1',profile=str(profile.resolve()),status=protocol['status'],protocolAudit=protocol,
        functionalPass=None,allRenderedFramesPass=None,spec=spec,epoch=epoch,
        limits=['Sampled same-slot geometry only; no functional or all-rendered-frame claim.',
                'Native X trousers/body source skinned using captured body bones; no GPU garment-palette/simulation claim.',
                'First attachment pairs are prepared snapshots; ordinary body poses require consumed body/cart DrawSolid receipts.'],
        sourceGeometry=dict(fbx=str(mesh),sha256=hashlib.sha256(mesh.read_bytes()).hexdigest(),shaftComponents=len(actual.components),
                            trousersFaces=len(models[True][3]),lowerBodyFaces=len(faces[False]),
                            nativeSourceFiles={key:dict(path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest())
                                               for key,path in source_paths.items()}),roles={})
    for role in native:
        values=[r for r in native[role] if r.get('wall',-1)>=epoch]
        bodies=P['native_rows'](values,role,spec)
        pairs=sorted((r for r in values if r['event']=='grounding-pair'),key=lambda r:r['wall']);require(pairs,role+': missing pairs')
        first=pairs[0]['wall'];pants='skinned/clothes/'+('kate' if female else 'bob')+'_trousers'
        outfit=[r for r in receipts[role] if r.get('wall',-1)>=epoch and r.get('id')==spec['id'] and r.get('pantsType')=='Base.Trousers_JeanBaggy']
        require(outfit and all(r.get('female') is female and r.get('pantsModel')==pants and r.get('ownerID')==spec['ownerID'] and r.get('wornCount')==3 for r in outfit),role+': missing selected native outfit receipt')
        vbo=profile/role/'WheelbarrowWood.bin';proof=parse((profile/role/'wood-wheel-mesh-proof.json').read_text())
        digest=hashlib.sha256(vbo.read_bytes()).hexdigest()
        require(proof.get('sha256')==digest==VBO_SHA and proof.get('matchesOriginal') is True and proof.get('id')==spec['ownerID']
                and proof.get('local') is (role=='client1') and proof.get('bytes')==vbo.stat().st_size
                and proof.get('wallTimeMillis',-1)>=epoch,role+': wrong source VBO proof')
        vertices,_=geometry.shafts(vbo)
        require(all(tuple(v) in source for v in np.round(vertices,7)),role+': native VBO differs from FBX')
        draws={}
        for draw in cameras[role]:
            key=(draw.get('captureId'),draw.get('part'));require(key not in draws,role+': duplicate draw');draws[key]=draw
        selected=[];excluded=[]
        for row in poses[role]:
            if row.get('wallTimeMillis',-1)<first or analysis_end is not None and row['wallTimeMillis']>analysis_end:
                missing=[part for part in ('body','cart') if (row.get('captureId'),part) not in draws]
                excluded.append(dict(wall=row['wallTimeMillis'],captureId=row.get('captureId'),slotToken=row.get('slotToken'),
                                     reason='after requested window' if row['wallTimeMillis']>=first else 'before first held slot',
                                     unconsumedParts=missing))
                continue
            C['pose'](row)
            require(row.get('id')==spec['ownerID'] and row.get('female') is female and row.get('local') is (role=='client1')
                    and row.get('cartItemId')==row.get('primary')==row.get('secondary')==spec['id']
                    and row.get('model')=='WheelbarrowWood' and row.get('cartModelCount')==1 and row.get('cartItemSource')=='hands',role+': foreign pose')
            for part in ('body','cart'):
                draw=draws.get((row.get('captureId'),part))
                require(draw and draw.get('slotToken')==row.get('slotToken') and draw.get('captureWallTimeMillis')==row['wallTimeMillis']
                        and draw.get('model')==('WheelbarrowWood' if part=='cart' else 'FemaleBody' if female else 'MaleBody')
                        and draw.get('id')==spec['ownerID'] and draw.get('preparedPrimary')==draw.get('preparedSecondary')==spec['id']
                        and row['wallTimeMillis']<=draw.get('wallTimeMillis',-1)<=row['wallTimeMillis']+1000,role+': missing consumed same-slot draw')
            selected.append(row)
        require(selected,role+': no drawn geometry')
        observations=[]
        def evaluate(row,kind):
            inv=np.linalg.inv(matrix(row['cart']));require(needed<=row['bones'].keys(),role+': missing influencing bones')
            for name in needed: matrix(row['bones'][name])
            obs=dict(wall=row['wallTimeMillis'],source=kind)
            for pants,value in models.items():
                skin=geometry.skin(row,value);local=(np.c_[skin,np.ones(len(skin))]@inv.T)[:,:3]
                for side in 'LR':
                    hits=faces[pants][np.flatnonzero(actual.intersects(local[value[3][faces[pants]]],side))]
                    key=('trousers' if pants else 'lowerBody')+side;obs[key]=len(hits)
                    if len(hits): obs[key+'Faces']=hits.tolist()
            obs['cartAdvanceRelativeLastPose']=selected[-1]['cart'][14]-row['cart'][14]
            if any(obs.get(k,0) for k in REGIONS):
                nearest=min(bodies,key=lambda body:abs(body['wall']-row['wallTimeMillis']))
                gap=nearest['wall']-row['wallTimeMillis']
                require(abs(gap)<=50,role+': no nearby native body tracks for contact diagnostic')
                obs['nativeTrackContext']=dict(wall=nearest['wall'],gapMs=gap,exactWall=gap==0,moving=nearest['moving'],
                    tracks=[track for track in nearest['tracks'] if track['weight']>1e-4],
                    readiness=nearest['readiness'])
            observations.append(obs)
        for pair in pairs:
            b,a=pair['before'],pair['after']
            require(pair['wall']<=first+800 and all(type(b.get(k)) is int and b[k]==a.get(k) for k in ('slotToken','cartDataToken'))
                    and all(s.get('id')==s.get('primaryID')==s.get('secondaryID')==spec['id'] for s in (b,a)),role+': foreign first-pair source')
            evaluate(dict(wallTimeMillis=a['wall'],cart=a['cart'],bones=a['bones']),'first_attachment_same_slot')
        for row in selected: evaluate(row,'draw_bound_same_slot')
        summary={}
        for kind in ('first_attachment_same_slot','draw_bound_same_slot'):
            group=[r for r in observations if r['source']==kind];times=sorted(set(r['wall'] for r in group))
            summary[kind]=dict(samples=len(group),firstWall=times[0],lastWall=times[-1],maxSampleGapMs=max((b-a for a,b in zip(times,times[1:])),default=0),
                maximumCartAdvanceRelativeLastPose=max(r['cartAdvanceRelativeLastPose'] for r in group),
                contactSamples=sum(any(r[k] for k in REGIONS) for r in group),contactsByRegion={k:sum(r[k]>0 for r in group) for k in REGIONS})
        contacts=[r for r in observations if any(r[k] for k in REGIONS)]
        result['roles'][role]=dict(vboSha256=digest,nativeOutfitReceipts=len(outfit),samples=summary,
            analysisWindow=dict(start=first,end=analysis_end,endSource='authoritative-owner-check+2000ms' if analysis_end is not None else 'observed-diagnostic-capture',
                                excludedPostWindowPoses=sum(r['reason']=='after requested window' for r in excluded),excludedPoses=excluded),
            cartAdvanceReference=dict(wall=selected[-1]['wallTimeMillis'],cartTranslation=selected[-1]['cart'][12:15]),
            firstPair=dict(wall=first,slotToken=pairs[0]['after']['slotToken'],cartDataToken=pairs[0]['after']['cartDataToken'],
                           beforeReadiness=pairs[0]['before']['readiness'],afterReadiness=pairs[0]['after']['readiness'],lowerBodyMaximumMatrixDelta=lower_delta(pairs[0])),
            allPairsLowerBodyMaximumMatrixDelta=max(lower_delta(pair) for pair in pairs),
            wheelMaximumFloorError=max(abs(C['wheel'](row)-.008) for row in selected),
            palmMaximumDistance={side:max(C['palm'](row,side) for row in selected) for side in 'LR'},contactSamples=len(contacts),distinctContactTimes=sorted(set(r['wall'] for r in contacts)),contactDetails=contacts)
    result['geometryStatus']='contacts_observed' if any(r['contactSamples'] for r in result['roles'].values()) else 'no_contacts_in_captured_samples'
    print(json.dumps(result,indent=2,allow_nan=False))
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ('profile','game','mesh'):parser.add_argument('--'+key,type=Path,required=True)
    args=parser.parse_args();main(args.profile,args.game,args.mesh)
