"""Two real menu-Host clients verify initial and subsequent vehicle item synchronization."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import zipfile

SUITE='vehicle-inventory'
MARKER='[VEHICLE_INVENTORY] '
PHASES=['initial','late-add','late-remove','nested-add','nested-remove','native-take','native-return','replacement','rejoined','post-rejoin-add','post-rejoin-remove']


def definitions():
    return {SUITE: {'status':'ready','clients':2,'default_mods':['ZombieBuddy','PZToolkitJavaPatches','PZSurvivorToolkit','NewMusic'],
        'cases':[{'id':'sync','producer':'fixture','capability':'effect','kinds':['mp'],'languages':['EN','RU'],'modes':['toolkit']}]}}


def validate(s):
    if (s.get('cases')!=['sync'] or s.get('kind')!='mp' or s.get('mode')!='toolkit' or s.get('clients')!=2
        or s.get('languages')!=['EN','RU'] or s.get('options',{}).get('mp_host') is not True
        or not {'ZombieBuddy','PZToolkitJavaPatches','PZSurvivorToolkit','NewMusic'}<=set(s.get('mods',[]))
        or any(s.get('options',{}).get(k) for k in ('world_template','seed_run','startup_connection'))):
        raise ValueError('Vehicle inventory requires two EN/RU fresh menu-Host clients, Toolkit Java Patches and NewMusic')


def sources(project,s):
    base=Path(project)/'tests/native_queue'
    return [*sorted((base/SUITE).rglob('*.lua')),base/SUITE/'Main.java',*sorted((base/'startup').rglob('*.lua')),base/'vehicle-doors/shared/VehicleDoorsFixture.lua']


def stage(project,output,game,jdk,selection,locations,runtime):
    validate(selection);base=Path(project)/'tests/native_queue';classes=Path(output)/'inventory-probe-classes';classes.mkdir()
    subprocess.run([str(Path(jdk)/'bin/javac'),'--release','25','-cp',os.pathsep.join(str(Path(game)/j) for j in ('projectzomboid.jar','ZombieBuddy.jar')),
        '-d',str(classes),str(base/SUITE/'Main.java')],check=True,capture_output=True,text=True,timeout=60)
    for role,settings in runtime['roles'].items():
        lua=Path(output)/role/'mods/ActionQueueTest/42/media/lua'
        for side,name in [('client','ZZStartup.lua'),('server','ZZStartupServer.lua')]:
            text=(base/'startup'/side/name).read_text().replace('posX=10835,posY=10144','posX=10640,posY=10144')
            if side=='client':
                text=text.replace("config.cases[1]=='lease_lifecycle'","config.suite=='vehicle-inventory'").replace('cart-lease-lifecycle-rejoin.txt','vehicle-inventory-rejoin.txt')
            (lua/side/name).write_text(text)
        shutil.copy2(base/'vehicle-doors/shared/VehicleDoorsFixture.lua',lua/'shared/VehicleDoorsFixture.lua')
        preflight=lua/'client/ZZReleasePreflight.lua'
        text=preflight.read_text()
        line="        print('[QUEUE_TEST] WINDOW_SIZE width='..width..' height='..height)"
        assert text.count(line)==1
        text=text.replace(line,"        if vehicleInventoryWindowObservation(width,height) then\n"+line+"\n        end")
        preflight.write_text(text)

        helper=Path(settings['cache'])/'mods/VehicleInventoryProbe';jar=helper/'42/media/java/VehicleInventoryProbe.jar';jar.parent.mkdir(parents=True)
        with zipfile.ZipFile(jar,'x') as z:
            for p in sorted(classes.rglob('*.class')):z.write(p,p.relative_to(classes).as_posix())
        (helper/'42/mod.info').write_text('name=Disposable vehicle inventory probe\nid=VehicleInventoryProbe\nversionMin=42.21\nrequire=\\ZombieBuddy\njavaPkgName=net.alexredby.vehicleinventoryfixture\njavaJarFile=media/java/VehicleInventoryProbe.jar\n')
    ini=Path(output)/'server/Server/queue-smoke.ini';ini.write_text(ini.read_text().replace('SpawnPoint=10835,10144,0','SpawnPoint=10640,10144,0'))
    runtime.setdefault('fixture',{}).update(mods=['VehicleInventoryProbe'],server_ready='[STARTUP_TEST] SERVER_READY',failure_markers=[MARKER+'FAIL '],client_launch_stagger_seconds=8)


def complete(s,role,text):
    return text.count(MARKER+'COMPLETE '+role)==1


def analyze(logs):
    issues=[]
    server=logs['server']
    for role in ('server','client1','client2'):
        text=logs[role]
        phases=re.findall(re.escape(MARKER)+'PASS '+role+r' (\S+)',text)
        if phases!=PHASES or MARKER+'FAIL ' in text or not complete(None,role,text):issues.append(role+': incomplete ordered item/replica checks')
    states=dict(re.findall(re.escape(MARKER)+r'STATE (\S+) vehicle=(-?\d+)',server))
    wire=[dict(phase=m[0],kind=m[1],vehicle=m[2],channel=int(m[3]),guid=m[4]) for m in re.findall(
        re.escape(MARKER)+r'WIRE phase=(\S+) kind=(\S+) vehicle=(-?\d+) channel=(-?\d+) guid=(\d+)',server)]
    peers=dict(re.findall(re.escape(MARKER)+r'PEER (\S+) connection=(\d+):\d+',server))
    rejoined_tokens=re.findall(re.escape(MARKER)+r'REJOIN connection=(\d+:\d+)',server)
    rejoined=[token.split(':')[0] for token in rejoined_tokens]
    peer_tokens=dict(re.findall(re.escape(MARKER)+r'PEER (\S+) connection=(\d+:\d+)',server))
    if set(peers)!= {'client1','client2'} or len(rejoined)!=1 or rejoined_tokens[0]==peer_tokens.get('client2'):
        issues.append('Missing real guest connection replacement')
    for phase in PHASES:
        if re.findall(re.escape(MARKER)+r'ACK (client[12]) '+phase+r'(?:\s|$)',server)!=['client1','client2']:
            # Arrival order is intentionally unconstrained.
            if sorted(re.findall(re.escape(MARKER)+r'ACK (client[12]) '+phase+r'(?:\s|$)',server))!=['client1','client2']:
                issues.append('Missing exact authoritative item checks: '+phase)
    for phase in ('initial','replacement'):
        rows=[r for r in wire if r['phase']==phase and r['vehicle']==states.get(phase)]
        if any(r['kind'] in ('add','remove') for r in rows):issues.append('Pre-snapshot vehicle deltas were not coalesced: '+phase)
        if {r['guid'] for r in rows if r['kind']=='full' and r['channel']==0}!=set(peers.values()):issues.append('Missing initial native full snapshots: '+phase)
    for phase,kind in [('late-add','add'),('late-remove','remove'),('nested-add','add'),('nested-remove','remove'),('post-rejoin-add','add'),('post-rejoin-remove','remove')]:
        expected=set(peers.values()) if phase.startswith(('late-','nested-')) else {peers.get('client1'),rejoined[0] if rejoined else None}
        rows=[r for r in wire if r['phase']==phase and r['vehicle']==states.get(phase) and r['kind']==kind]
        if {r['guid'] for r in rows if r['channel']==0}!=expected or any(r['channel']!=0 for r in rows):issues.append('Missing ordered native vehicle delta sends: '+phase)
    if MARKER+'NATIVE_EXIT client2' not in logs['client2'] or MARKER+'NATIVE_RECONNECT client2' not in logs['client2']:issues.append('Missing native menu reconnect')
    if len(re.findall(re.escape(MARKER)+r'MUSIC vehicle=',server))!=2:issues.append('Missing both early NewMusic replacement cases')
    return issues,{'phases':PHASES,'wire':wire,'peers':peers,'rejoined':rejoined,'states':states}


def verify(root,s,catalog):
    logs={r:(Path(root)/(r+'-launch.log')).read_text(errors='replace') for r in ('server','client1','client2')}
    issues,evidence=analyze(logs)
    return {'issues':issues,'outcomes':[dict(actor=r,case='sync',status='failed' if issues else 'passed',reason='; '.join(issues)) for r in ('client1','client2')],
        'evidence':dict(evidence,limits=['Programmatically queued native inventory transfers and menu reconnect; macOS stationary CarNormal. Native replacement may allocate a different numeric ID; ID reuse/failure paths require the woven JVM regression.'])}
