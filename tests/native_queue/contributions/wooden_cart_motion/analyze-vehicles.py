"""Independent rendered wooden mesh/continuous wheel clearance against owned native vehicle hulls."""
import argparse
import importlib.util
import json
import math
from pathlib import Path
import re
import numpy as np

_spec=importlib.util.spec_from_file_location('vehicle_footprint',Path(__file__).with_name('analyze-footprint.py'))
footprint=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(footprint)
collision=footprint.collision
fields,wrap=collision.fields,collision.wrap
native_clip=collision.native_clip
SPECS=('front','slide-left','slide-right')
EXPECTED={f'male-{cargo}-vehicle-yaw{yaw}-{spec}' for cargo in ('empty','full') for yaw in (0,45) for spec in SPECS}
CONTROLS={f'yaw{yaw}-slide-{side}' for yaw in (0,45) for side in ('left','right')}
DURATION=12000


def duration(name):
    return DURATION+(3000 if '-full-' in name and not name.endswith('front') else 0)


def finite(raw,keys):
    result={key:float(raw[key]) for key in keys}
    assert all(math.isfinite(v) for v in result.values()),'Nonfinite vehicle measurement'
    return result


def boolean(raw,key):
    assert raw[key] in ('true','false'),'Invalid vehicle boolean: '+key
    return raw[key]=='true'


def receipt(raw):
    row=finite(raw,('id','z'))
    assert row['id']>=0 and row['id']%1==0 and row['z']>0 and row['z']%1==0,'Invalid native vehicle identity/level'
    assert boolean(raw,'static') and not boolean(raw,'active'),'Vehicle fixture is not static'
    assert boolean(raw,'bodyBlocked') and boolean(raw,'crossBlocked'),'Native queries do not collide with fixture body'
    hull=np.asarray([float(v) for v in raw['hull'].split(',')]).reshape(4,2)
    assert np.isfinite(hull).all(),'Nonfinite native hull'
    edges=np.roll(hull,-1,axis=0)-hull
    lengths=np.linalg.norm(edges,axis=1)
    assert min(lengths)>.5 and max(lengths)<8,'Degenerate native hull'
    next_edges=np.roll(edges,-1,axis=0)
    cross=edges[:,0]*next_edges[:,1]-edges[:,1]*next_edges[:,0]
    assert np.all(cross>0) or np.all(cross<0),'Nonconvex native hull'
    row.update(hull=hull.tolist());return row


def same_receipt(row,layout):
    assert row['id']==layout['id'] and row['z']==layout['z'],'Vehicle identity/level changed during capture'
    assert np.max(np.abs(np.array(row['hull'])-layout['hull']))<=.002,'Vehicle hull moved during capture'


def hull(points):
    points=sorted(set(map(tuple,points)))
    assert len(points)>=3,'Degenerate rendered cart polygon'
    def cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    lower=[]
    for point in points:
        while len(lower)>=2 and cross(lower[-2],lower[-1],point)<=0:lower.pop()
        lower.append(point)
    upper=[]
    for point in reversed(points):
        while len(upper)>=2 and cross(upper[-2],upper[-1],point)<=0:upper.pop()
        upper.append(point)
    result=np.asarray(lower[:-1]+upper[:-1]);assert len(result)>=3,'Degenerate rendered cart polygon'
    return result


def geometry(frame,vertices,vehicle):
    # Reuse the independently validated same-frame transform; the production envelope is not an oracle.
    footprint.world_bounds(frame,vertices)
    matrix=np.asarray(frame['cart']).reshape(4,4).T
    angle=float(frame['slotAngle']);c,s=math.cos(angle),math.sin(angle)
    transform=np.array([[-1.5*c,0,-1.5*s],[-1.5*s,0,1.5*c]])
    linear=transform@matrix[:3,:3];offset=transform@matrix[:3,3]+[frame['slotX'],frame['slotY']]
    polygon=hull(vertices[:,:3]@linear.T+offset)
    center=linear@footprint.CENTER+offset
    vehicle=np.asarray(vehicle)
    axes=[]
    for points in (vehicle,polygon):
        for edge in np.roll(points,-1,axis=0)-points:
            length=np.linalg.norm(edge)
            if length>1e-10:axes.append(np.array([-edge[1],edge[0]])/length)
    # Exact support over every wheel spin angle, including axle width. Each separating axis is a proof.
    body_gap,wheel_gap=-math.inf,-math.inf
    for axis in axes:
        other=vehicle@axis;body=polygon@axis
        support=footprint.HALF_AXLE*abs(axis@linear[:,0])+footprint.RADIUS*math.hypot(axis@linear[:,1],axis@linear[:,2])
        wheel=float(center@axis)
        body_gap=max(body_gap,float(min(body)-max(other)),float(min(other)-max(body)))
        wheel_gap=max(wheel_gap,wheel-support-float(max(other)),float(min(other))-wheel-support)
    return dict(polygon=polygon.tolist(),wheelCenter=center.tolist(),wheelLinear=linear.tolist(),
                bodyGap=body_gap,wheelGap=wheel_gap,slotX=float(frame['slotX']),slotY=float(frame['slotY']),slotAngle=angle)


def support(measured,axis):
    axis=np.asarray(axis);polygon=np.asarray(measured['polygon']);linear=np.asarray(measured['wheelLinear'])
    center=np.asarray(measured['wheelCenter'])
    radius=footprint.HALF_AXLE*abs(axis@linear[:,0])+footprint.RADIUS*math.hypot(axis@linear[:,1],axis@linear[:,2])
    return min(float(min(polygon@axis)),float(center@axis)-radius),max(float(max(polygon@axis)),float(center@axis)+radius)


def layout_fields(text):
    prefix, native = text.split(' id=', 1)
    declared, measured = fields(prefix), fields('id='+native)
    assert set(declared) & set(measured) == {'z'}, 'Unexpected overlapping vehicle layout fields'
    declared_z, measured_z = float(declared['z']), float(measured['z'])
    assert math.isfinite(declared_z) and math.isfinite(measured_z) and declared_z == measured_z, 'Declared and measured vehicle levels disagree'
    return dict(declared, **measured)


def aligned_contact(rows, tangent):
    groups=[]
    for row in rows:
        if abs(wrap(row['heading']-tangent))>math.radians(5):
            if groups and groups[-1]:groups.append([])
            continue
        if not groups or groups[-1] and row['wall']-groups[-1][-1]['wall']>500:groups.append([])
        groups[-1].append(row)
    return max(groups,key=lambda group:group[-1]['wall']-group[0]['wall'] if group else -1,default=[])


def measured_start(rows):
    before=[row for row in rows if row['elapsed']<1000]
    assert len(before)>=10 and before[-1]['elapsed']-before[0]['elapsed']>=800, 'Missing stable pre-input vehicle window'
    assert before[0]['elapsed']<=200 and before[-1]['elapsed']>=800 and all(row['drive']==0 for row in before), 'Invalid pre-input vehicle window'
    assert collision.spread(before)<=.025 and collision.angle_drift(before,'heading')<=math.radians(1.5), 'Vehicle actor moves during measured pre-input window'
    return before[0]['x'],before[0]['y']


def parse(text):
    assert '[WOOD_BANK] RUN_STARTED' in text,'Missing vehicle run boundary'
    log=text.rsplit('[WOOD_BANK] RUN_STARTED',1)[1]
    assert '[WOOD_BANK] FAIL' not in log,'Vehicle fixture reported a failure'
    starts,ends,layouts,rows,motion,states,events={},{},{},{},{},{},{}
    control_starts,control_ends,control_rows={},{},{}
    active=None
    for line in log.splitlines():
        match=re.search(r'\[WOOD_BANK\] CASE (\S+)(?: attempt=\d+)? wall=(\d+)',line)
        if match:
            name,at=match[1],int(match[2]);assert name in EXPECTED and name not in starts and active is None,'Unexpected/duplicate vehicle scene'
            starts[name]=at;rows[name]=[];motion[name]=[];states[name]=[];events[name]=[];active=name
        match=re.search(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)',line)
        if match:
            name=match[1];assert active==name and int(match[2])==starts[name],'Vehicle completion disagrees with start'
            ends[name]=int(match[2]);active=None
        match=re.search(r'\[CART_VEHICLE_CONTROL\] (START|COMPLETE) (\S+) wall=(\d+)',line)
        if match:
            kind,name,at=match[1],match[2],int(match[3]);assert name in CONTROLS,'Unknown vehicle control'
            if kind=='START':
                assert name not in control_starts and active is None and not starts,'Vehicle controls must precede scenes'
                control_starts[name]=at;control_rows[name]=[];active=name
            else:
                assert active==name and name not in control_ends,'Vehicle control completion without start'
                control_ends[name]=at;active=None
        if '[CART_VEHICLE_LAYOUT] ' in line:
            raw=layout_fields(line.split('[CART_VEHICLE_LAYOUT] ',1)[1]);name=raw['case']
            assert name==active and name not in layouts,'Duplicate/misplaced vehicle layout'
            layout=finite(raw,('yaw','x','y','nx','ny','tx','ty','width','length','startX','startY'))
            layout.update(receipt(raw));assert layout['yaw'] in (0,45),'Wrong vehicle yaw'
            expected=np.array([math.cos(math.radians(layout['yaw'])),-math.sin(math.radians(layout['yaw']))])
            assert np.linalg.norm(expected-[layout['nx'],layout['ny']])<1e-6,'Vehicle normal disagrees with yaw'
            assert np.linalg.norm([layout['tx']+layout['ny'],layout['ty']-layout['nx']])<1e-6,'Invalid vehicle tangent'
            assert ('yaw'+str(int(layout['yaw']))) in name,'Scene yaw disagrees with layout'
            shape=np.asarray(layout['hull'])-[layout['x'],layout['y']]
            assert abs(max(abs(shape@expected))-layout['width'])<.003,'Vehicle width disagrees with native hull'
            assert abs(max(abs(shape@np.array([layout['tx'],layout['ty']])))-layout['length'])<.003,'Vehicle length disagrees with native hull'
            layouts[name]=layout
        for prefix,collection,bare in (('[CART_VEHICLE_SAMPLE] ',rows,False),('[CART_VEHICLE_CONTROL_SAMPLE] ',control_rows,True)):
            if prefix not in line:continue
            raw=fields(line.split(prefix,1)[1]);name=raw['case'];assert name==active and name in layouts,'Vehicle sample outside its layout'
            row=finite(raw,('wall','elapsed','x','y','heading','drive'));row.update(receipt(raw));same_receipt(row,layouts[name])
            assert boolean(raw,'bare')==bare and not boolean(raw,'run') and not boolean(raw,'sprint'),'Vehicle bank requires native Walk'
            tracks=raw['tracks'];parsed=re.findall(r'([^=;]+)=([^@;]+)@([^;]+);',tracks)
            assert parsed and all(math.isfinite(float(a)+float(b)) for _,a,b in parsed),'Missing/nonfinite native vehicle tracks'
            row['walking']=any(native_clip(n)=='Bob_Walk' and float(a)>0 and float(b)>.1 for n,a,b in parsed)
            collection[name].append(row)
        if '[WOOD_BANK_SAMPLE] ' in line:
            row=collision.sample(line);assert row['case']==active and active in motion,'Vehicle motion outside its scene';motion[active].append(row)
        if '[CART_FOOTPRINT_STATE] ' in line:
            raw=fields(line.split('[CART_FOOTPRINT_STATE] ',1)[1]);assert raw['case']==active and active in states,'Vehicle diagnostics outside scene'
            row=finite(raw,('wall','elapsed','front'));assert row['front'] in (1.26,1.62),'Invalid vehicle cart envelope'
            row.update(blocked=boolean(raw,'blocked'),clear=boolean(raw,'clear'),recovering=boolean(raw,'recovering'));states[active].append(row)
        if '[WOOD_RAMP_EVENT] ' in line:
            raw=fields(line.split('[WOOD_RAMP_EVENT] ',1)[1]);assert raw['case']==active and active in events,'Vehicle input outside scene'
            events[active].append(finite(raw,('elapsed','gait','drive')))
    complete=re.findall(r'\[WOOD_BANK\] ALL_COMPLETE cases=(\d+)',log)
    assert len(complete)==1 and int(complete[0])==len(starts) and starts.keys()==ends.keys() and active is None,'Incomplete vehicle run'
    assert control_starts.keys()==control_ends.keys()==CONTROLS,'Missing bare vehicle controls'
    assert starts and set(layouts)==set(starts)|CONTROLS and '[CART_VEHICLE] CLEANUP_COMPLETE' in log,'Missing vehicle layout/cleanup'
    return dict(starts=starts,layouts=layouts,rows=rows,motion=motion,states=states,events=events,
                control_starts=control_starts,control_ends=control_ends,control_rows=control_rows)


def contact_metrics(rows,layout,direction):
    if len(rows)<2:return dict(durationMs=0,tangent=0,normal=0,backtracking=0,samples=len(rows))
    tangent=np.array([layout['tx'],layout['ty']])*direction;normal=np.array([layout['nx'],layout['ny']])
    points=np.array([[r['x'],r['y']] for r in rows]);deltas=np.diff(points,axis=0)@tangent
    return dict(durationMs=rows[-1]['wall']-rows[0]['wall'],tangent=float((points[-1]-points[0])@tangent),
                normal=float(np.ptp(points@normal)),backtracking=float(sum(np.maximum(0,-deltas))),samples=len(rows))


def analyze(text,profile):
    data=parse(text);starts=data['starts'];layouts=data['layouts'];failures=[];geometry_failures=[];summaries=[];controls={}
    vertices,sha=footprint.mesh(profile)
    durations={name:duration(name) for name in starts}
    updates,budget_failures=footprint.native_updates(profile,starts,durations);failures.extend(budget_failures)
    def fail(name,reason,geometry=False):
        target=geometry_failures if geometry else failures
        if (name,reason) not in target:target.append((name,reason))
    for name,rows in data['control_rows'].items():
        layout=layouts[name];start=data['control_starts'][name]
        collision.coverage(rows,start,7000,'vehicle bare control '+name,60)
        assert 7000<=data['control_ends'][name]-start<=7500,'Invalid vehicle bare control duration'
        measured_start(rows)
        direction=-1 if name.endswith('right') else 1;center=np.array([layout['x'],layout['y']]);normal=np.array([layout['nx'],layout['ny']]);tangent=np.array([layout['tx'],layout['ty']])
        contact=[]
        for row in rows:
            position=np.array([row['x'],row['y']])-center;n=float(position@normal);t=float(position@tangent)
            if abs(n)<layout['width']-.005 and abs(t)<layout['length']-.005:fail(name,'bare actor enters native hull')
            if 1200<=row['elapsed']<6800 and -.005<=n-layout['width']<=.35 and abs(t)<layout['length']-.15:contact.append(row)
        metrics=contact_metrics(contact,layout,direction);controls[name]=metrics
        if metrics['durationMs']<600 or metrics['tangent']<.15 or metrics['normal']>.25 or metrics['backtracking']>.03 or any(b['wall']-a['wall']>500 for a,b in zip(contact,contact[1:])):
            fail(name,'bare Walk lacks sustained vehicle contact slide')
        if not contact or not all(r['walking'] for r in contact):fail(name,'native bare Walk gait missing at contact')
    assert max(data['control_ends'].values())<min(starts.values()),'Controls overlap vehicle scenes'
    windows=sorted((start,name) for name,start in starts.items())
    assert all(b-a>=durations[name] for (a,name),(b,_) in zip(windows,windows[1:])),'Overlapping vehicle scenes'
    frames={name:[] for name in starts}
    for line in (profile/'body-clearance.jsonl').read_text().splitlines():
        frame=json.loads(line);at=frame['wallTimeMillis'];assert type(at) in (int,float) and math.isfinite(at),'Invalid vehicle frame time'
        for start,name in windows:
            if start<=at<start+durations[name]:
                assert frame['female'] is False,'Vehicle bank requires male native mesh'
                measured=geometry(frame,vertices,layouts[name]['hull']);measured.update(wall=at,elapsed=at-start)
                frames[name].append(measured);break
    for name,start in starts.items():
        rows,motion,states,events=(data[k][name] for k in ('rows','motion','states','events'));layout=layouts[name];measured=frames[name]
        total=durations[name];extra=total-DURATION
        for stream,label in ((rows,'vehicle'),(motion,'motion'),(states,'diagnostics'),(measured,'mesh')):collision.coverage(stream,start,total,label+' '+name,80)
        assert [(r['wall'],r['elapsed']) for r in rows]==[(r['wall'],r['elapsed']) for r in motion]==[(r['wall'],r['elapsed']) for r in states],'Misaligned vehicle motion/diagnostics'
        measured_start(motion)
        assert len(events)==4 and all(abs(e['elapsed']-t)<=500 and e['gait']==0 for e,t in zip(events,(1000,8500+extra,9300+extra,11000+extra))),'Missing/wrong vehicle input stages'
        assert events[0]['drive'] in footprint.ANGLES and events[1]['drive']==0 and events[2]['drive'] in footprint.ANGLES and events[3]['drive']==0,'Invalid vehicle drives'
        for a,b in zip([dict(elapsed=0,drive=0,gait=0),*events],[*events,dict(elapsed=total,drive=0,gait=0)]):
            stage=[r for r in motion if a['elapsed']+150<=r['elapsed']<b['elapsed']-150]
            assert stage and all(r['drive']==a['drive'] and r['requestedGait']==0 for r in stage),'Vehicle input/sample disagreement'
        assert all(math.dist((r['x'],r['y']),(m['x'],m['y']))<=.002 and abs(wrap(r['heading']-m['heading']))<=.1 for r,m in zip(rows,motion)),'Vehicle and cart motion streams disagree'
        direction=-1 if name.endswith('right') else 1
        desired=math.atan2(-layout['ny']+(0 if name.endswith('front') else direction*layout['ty']),-layout['nx']+(0 if name.endswith('front') else direction*layout['tx']))
        drive=min(footprint.ANGLES,key=lambda key:abs(wrap(footprint.ANGLES[key]-desired)))
        assert events[0]['drive']==drive and abs(wrap(motion[0]['heading']-desired))<=.1,'Wrong vehicle approach direction'
        times=[r['wall'] for r in motion]
        for frame in measured:
            assert footprint.slot_matches(frame,motion,times),'Same-frame vehicle cart slot disagrees with actor'
            if frame['bodyGap']<-.005:fail(name,'rendered wooden mesh enters native vehicle hull',True)
            if frame['wheelGap']<-.005:fail(name,'continuous wheel cylinder enters native vehicle hull',True)
        normal=np.array([layout['nx'],layout['ny']]);tangent=np.array([layout['tx'],layout['ty']]);center=np.array([layout['x'],layout['y']])
        direction=-1 if name.endswith('right') else 1
        for frame in measured:
            frame['sideGap']=support(frame,normal)[0]-float(center@normal)-layout['width']
            frame['tail']=support(frame,tangent*direction)[0]-float(center@(tangent*direction))-layout['length']
        frame_times=[f['wall'] for f in measured]
        contact=[r for r in motion if 1500<=r['elapsed']<8000 and any(-.005<=f['sideGap']<=.20 and f['tail']<-.1 for f in footprint.brackets(measured,frame_times,r['wall']))]
        geometry_contact=contact
        if not name.endswith('front'):
            contact=aligned_contact(contact,math.atan2(direction*tangent[1],direction*tangent[0]))
        metrics=contact_metrics(contact,layout,direction)
        if not contact or metrics['durationMs']<600:fail(name,'rendered cart never sustains vehicle contact')
        if not any(s['blocked'] for s in states if contact and contact[0]['wall']<=s['wall']<=contact[-1]['wall']):fail(name,'vehicle contact never rejects normal movement')
        if name.endswith('front'):
            quiet=[r for r in motion if 5000<=r['elapsed']<8000]
            if collision.spread(quiet)>.025 or collision.angle_drift(quiet,'heading')>math.radians(1.5) or collision.wheel_roll_error(quiet)>.025:fail(name,'frontal vehicle contact chatters')
        else:
            late=[r for r in contact if r['wall']>=contact[-1]['wall']-600] if contact else []
            late_metrics=contact_metrics(late,layout,direction)
            if metrics['tangent']<.15 or metrics['normal']>.20 or metrics['backtracking']>.04 or late_metrics['tangent']<.04 or any(b['wall']-a['wall']>500 for a,b in zip(contact,contact[1:])):fail(name,'cart lacks sustained tangent progress at vehicle contact')
            # Keep yaw chatter visible when flutter leaves the geometry or alignment window.
            late_geometry=[r for r in motion if geometry_contact[-1]['wall']-600<=r['wall']<=geometry_contact[-1]['wall']] if geometry_contact else []
            turns=[wrap(b['heading']-a['heading']) for a,b in zip(late_geometry,late_geometry[1:])]
            if sum(map(abs,turns))-abs(sum(turns))>.06:fail(name,'vehicle contact heading chatters')
            contact_motion=[r for r in contact if r['actualDistance']>1e-6]
            if not footprint.progressing(contact_motion,{'Bob_Walk'}):fail(name,'native cart Walk does not progress at vehicle contact')
            ends=[f for f in measured if 1500<=f['elapsed']<8500+extra and f['tail']>.01]
            if not ends:fail(name,'cart does not clear finite vehicle end')
            elif not any(f['sideGap']<-.1 for f in ends):fail(name,'normal motion does not resume beyond vehicle end')
        before=min(motion,key=lambda r:abs(r['elapsed']-events[2]['elapsed']))
        if abs(wrap(footprint.ANGLES[events[2]['drive']]-before['heading']-math.pi))>math.pi/8+.05:fail(name,'reverse input disagrees with accepted heading')
        reverse=[r for r in motion if 9600+extra<=r['elapsed']<11000+extra]
        travel=sum((b['x']-a['x'])*math.cos(before['heading']+math.pi)+(b['y']-a['y'])*math.sin(before['heading']+math.pi) for a,b in zip(reverse,reverse[1:]))
        if travel<.15 or not any(r['direction']<0 and r['actualDistance']>1e-6 for r in reverse) or not footprint.progressing(reverse,{'Bob_WalkBwdNoAim1Hand'}):fail(name,'native reverse does not escape vehicle')
        quiet=[r for r in motion if 11600+extra<=r['elapsed']<total]
        if collision.spread(quiet)>.025 or collision.angle_drift(quiet,'heading')>math.radians(1.5) or collision.wheel_roll_error(quiet)>.025:fail(name,'final vehicle release does not settle')
        summaries.append(dict(case=name,durationMs=total,samples=len(rows),frames=len(measured),nativeUpdates=len(updates[name]),vehicle=layout,
            contact=metrics,bareWalk=controls[f'yaw{int(layout["yaw"])}-slide-'+('right' if direction<0 else 'left')],geometrySamples=measured))
    return dict(complete=True,caseCount=len(starts),controlCount=len(controls),meshSha256=sha,motionPass=not failures,footprintPass=not geometry_failures,
                motionFailures=failures,footprintFailures=geometry_failures,controls=controls,cases=summaries,
                limit='Sampled rendered wooden mesh convex projection and analytical wheel-cylinder support against real static native hulls. Native update budgets and bare Walk controls are required. Between-frame geometry, body/grip/clothing, runtime errors, video quality and multiplayer remain separate gates.')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--profile',type=Path,required=True);parser.add_argument('--log',type=Path);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();assert args.profile.is_dir(),'Capture profile missing';assert not args.output.exists(),'Refuse to overwrite an existing report'
    result=analyze((args.log or args.profile/'native-launch.log').read_text(errors='replace'),args.profile)
    with args.output.open('x') as output:json.dump(result,output,indent=2,allow_nan=False);output.write('\n')
    print(json.dumps({k:v for k,v in result.items() if k!='cases'},indent=2,allow_nan=False))
    return 0 if result['motionPass'] and result['footprintPass'] else 1


if __name__=='__main__':raise SystemExit(main())
