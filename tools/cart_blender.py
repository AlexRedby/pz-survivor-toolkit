#!/usr/bin/env python3
"""Prepare/edit/export native cart clips without touching installed game assets.

python3 tools/cart_blender.py prepare --clip wood_cart_pickup
python3 tools/cart_blender.py edit build/blender/wood_cart_pickup
python3 tools/cart_blender.py export build/blender/wood_cart_pickup
"""
import argparse
from datetime import datetime,timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import shlex
import subprocess
import sys
import uuid

ROOT=Path(__file__).resolve().parents[1]
PRESETS=Path(__file__).with_name('cart_blender_presets.json')


def jdk_binary(jdk,name):
    return Path(jdk)/'bin'/(name+('.exe' if os.name=='nt' else ''))


def game_default():
    paths={'darwin':Path.home()/'Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java',
           'win32':Path(os.environ.get('ProgramFiles(x86)',r'C:\Program Files (x86)'))/'Steam/steamapps/common/ProjectZomboid',
           'linux':Path.home()/'.steam/steam/steamapps/common/ProjectZomboid/projectzomboid'}
    return paths.get(sys.platform)


def executable(value,kind):
    if value:
        path=Path(value).expanduser().resolve()
        if kind=='blender' and path.suffix=='.app':path/='Contents/MacOS/Blender'
        if path.is_file():return path
        raise ValueError(f'{kind} executable not found: {path}')
    if kind=='blender':
        candidates=[Path.home()/'Applications/Blender.app/Contents/MacOS/Blender',Path('/Applications/Blender.app/Contents/MacOS/Blender')]
        candidates += [Path(shutil.which('blender'))] if shutil.which('blender') else []
    else:
        home=os.environ.get('JAVA_HOME')
        if home:candidates=[Path(home)/'bin'/kind]
        elif Path('/usr/libexec/java_home').is_file():
            found=subprocess.run(['/usr/libexec/java_home'],capture_output=True,text=True,check=True)
            candidates=[Path(found.stdout.strip())/'bin'/kind]
        else:candidates=[Path(shutil.which(kind))] if shutil.which(kind) else []
    for path in candidates:
        if path.is_file():return path.resolve()
    raise ValueError(f'{kind} was not found; pass its explicit path')


def run(command,log):
    try:
        result=subprocess.run([str(x) for x in command],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
    except subprocess.TimeoutExpired as error:
        partial=error.stdout or ''
        log.write_text(partial.decode(errors='replace') if isinstance(partial,bytes) else partial)
        raise ValueError(f'Command timed out after 120 seconds; see {log}') from error
    log.write_text(result.stdout)
    if result.returncode:
        raise ValueError(f'Command failed ({result.returncode}); see {log}\n{result.stdout[-1800:]}')
    return result.stdout


def config_for(workspace):
    path=Path(workspace).resolve()/'workspace.json'
    config=json.loads(path.read_text())
    if config.get('schema')!='pz-cart-blender-workspace-v1':raise ValueError('unsupported Blender workspace')
    return path,config


def prepare(args):
    presets=json.loads(PRESETS.read_text());preset=presets.get(args.clip,{})
    source=ROOT/'assets/animations'/(args.clip+'.json')
    if not re.fullmatch(r'[a-zA-Z0-9_]+',args.clip) or not source.is_file():raise ValueError('unknown animation source')
    game=args.game or game_default()
    if game is None:raise ValueError('pass --game with the game Java directory')
    game=game.expanduser().resolve()
    template=game/'media/anims_X/Bob/Bob_Idle.x'
    if not (game/'projectzomboid.jar').is_file() or not template.is_file():raise ValueError(f'game Java folder is invalid: {game}')
    blender=executable(args.blender,'blender')
    jdk=Path(args.jdk).expanduser().resolve() if args.jdk else executable(None,'javac').parent.parent
    for name in ('java','javac'):
        if not jdk_binary(jdk,name).is_file():raise ValueError(f'missing JDK executable: {name}')
    duration=args.duration if args.duration is not None else preset.get('playback_seconds')
    if duration is None or not math.isfinite(duration) or not .05<=duration<=60:
        raise ValueError('pass --duration with actual playback seconds (0.05..60) for this clip')
    body=game/'media/models_X/Skinned'/('FemaleBody.x' if args.female else 'MaleBody.x')
    if not body.is_file():raise ValueError(f'native body mesh not found: {body}')
    cart=None
    if args.cart_fbx is not None or preset.get('cart'):
        if not preset.get('cart'):raise ValueError('no calibrated cart reference for this clip; omit --cart-fbx')
        cart=dict(preset['cart'])
        if args.cart_fbx is not None:
            path=args.cart_fbx
        else:
            workshop=args.workshop
            if workshop is None:
                steamapps=next((p for p in game.parents if p.name=='steamapps'),None)
                if steamapps is None:raise ValueError('pass --workshop with Steam content/108600')
                workshop=steamapps/'workshop/content/108600'
            path=workshop/cart['workshop_id']/cart['relative_path']
        if not path.is_file():raise ValueError(f'cart reference missing: {path}; pass --cart-fbx')
        cart['path']=str(path.resolve())
    output=(args.output or ROOT/'build/blender'/args.clip).resolve()
    # A prepared workspace owns all its contents; never merge with an existing one.
    output.mkdir(parents=True,exist_ok=False)
    config={'schema':'pz-cart-blender-workspace-v1','clip':args.clip,'clip_name':preset.get('clip_name','Toolkit_'+''.join(s.title() for s in args.clip.split('_'))),
            'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'template':str(template),'body':str(body),'cart':cart,'duration':duration,
            'blender':str(blender),'jdk':str(jdk),'game':str(game),'python':sys.executable,'root':str(ROOT),
            'scene':str(output/'scene.blend'),'scope':preset.get('scope','Body clip authoring; runtime interaction is checked in PZ.')}
    path=output/'workspace.json';path.write_text(json.dumps(config,indent=2)+'\n')
    run([blender,'--background','--python-exit-code','1','--python',ROOT/'tools/cart_blender_scene.py','--',path],output/'prepare.log')
    if sys.platform=='darwin':
        for name,command in (('Edit in Blender','edit'),('Export for PZ','export')):
            shortcut=output/(name+'.command')
            shortcut.write_text('#!/bin/sh\nexec '+shlex.join([sys.executable,str(ROOT/'tools/cart_blender.py'),command,str(output)])+'\n')
            shortcut.chmod(0o755)
    print(f'Scene: {config["scene"]}\nEdit: {sys.executable} {ROOT / "tools/cart_blender.py"} edit {output}')
    return output


def export_workspace(workspace,bake_fps=None):
    path,config=config_for(workspace);directory=path.parent
    # All exports are new snapshots. Source JSON, runtime .x and installed mods are never destinations.
    output=directory/'exports'/(datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex[:8])
    output.mkdir(parents=True)
    result=output/'poses.json';expected=output/'expected.tsv';clip=output/(config['clip_name']+'.x')
    import cart_clip_bake as baker
    game=Path(config['game']);jdk=Path(config['jdk']);classes=output/'classes';classes.mkdir()
    java_source=ROOT/'tools/CartClipCheck.java'
    run([jdk_binary(jdk,'javac'),'-cp',game/'projectzomboid.jar','-d',classes,java_source],output/'javac.log')
    requested_bake_fps=bake_fps
    while True:
        suffix=f'-{bake_fps:g}' if bake_fps is not None else ''
        command=[config['blender'],'--background',config['scene'],'--python-exit-code','1','--python',ROOT/'tools/cart_clip_blender.py','--','export','--input',config['scene'],'--output',result,'--timing','keys','--verify-output',expected]
        if bake_fps is not None:command+=['--bake-fps',str(bake_fps)]
        run(command,output/f'blender{suffix}.log')
        samples=json.loads(result.read_text())
        clip.write_text(baker.bake(Path(config['template']).read_text(),samples,config['clip_name']))
        try:
            native=run([jdk_binary(jdk,'java'),'--enable-native-access=ALL-UNNAMED',f'-Djava.library.path={game}','-cp',os.pathsep.join(map(str,[classes,game/'projectzomboid.jar'])),'CartClipCheck',clip,expected],output/f'native{suffix}.log')
            break
        except ValueError as error:
            # Curves are approximated by native linear keys. Increase sampling
            # only for a measured approximation error, never for other failures.
            if bake_fps is None or bake_fps>=240 or 'native model-space matrices differ:' not in str(error):raise
            bake_fps=min(240,bake_fps*2)
    match=re.search(r'maxError=([0-9.eE+-]+)',native)
    if match is None:raise ValueError('native checker did not report a matrix result')
    report={'native_roundtrip':'PASS','matrix_tolerance':2e-4,'max_matrix_error':float(match[1]),'samples':len(samples),'bones':45,'includes_intermediate_frames':True,'bake_fps':bake_fps,'requested_bake_fps':requested_bake_fps,
            'scene_sha256':hashlib.sha256(Path(config['scene']).read_bytes()).hexdigest(),'source_sha256_at_prepare':config['source_sha256'],
            'source_unchanged_since_prepare':hashlib.sha256(Path(config['source']).read_bytes()).hexdigest()==config['source_sha256'],
            'runtime_assets_installed':False,'scope':'Offline native interpolation/FK check; gameplay, runtime IK and transitions require PZ.'}
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f'PASS: {clip}\nNative matrix error: {report["max_matrix_error"]:.6g}; report: {output / "report.json"}')
    return output


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    commands=parser.add_subparsers(dest='command',required=True)
    p=commands.add_parser('prepare');p.add_argument('--clip',default='wood_cart_pickup');p.add_argument('--output',type=Path)
    p.add_argument('--game',type=Path);p.add_argument('--jdk',type=Path);p.add_argument('--blender',type=Path)
    p.add_argument('--duration',type=float);p.add_argument('--female',action='store_true');p.add_argument('--workshop',type=Path);p.add_argument('--cart-fbx',type=Path)
    for name in ('edit','export','render'):
        sub=commands.add_parser(name);sub.add_argument('workspace',type=Path)
        if name=='export':sub.add_argument('--bake-fps',type=float)
        if name=='render':sub.add_argument('--frame',type=int,default=20)
    args=parser.parse_args()
    try:
        if args.command=='prepare':prepare(args)
        elif args.command=='export':export_workspace(args.workspace,args.bake_fps)
        else:
            path,config=config_for(args.workspace)
            if args.command=='edit':
                with (path.parent/'edit.log').open('a') as log:
                    subprocess.Popen([config['blender'],config['scene'],'--python-exit-code','1','--python',str(ROOT/'tools/cart_blender_ui.py')],stdout=log,stderr=subprocess.STDOUT)
                print(f'Launched {config["scene"]}; log: {path.parent / "edit.log"}')
            else:
                prefix=path.parent/'preview-'
                run([config['blender'],'--background',config['scene'],'--python-exit-code','1','--render-output',prefix,'--render-frame',str(args.frame)],path.parent/'render.log')
                print(f'Preview: {prefix}{args.frame:04}.png')
    except (ValueError,OSError,subprocess.SubprocessError,TypeError) as error:
        parser.error(str(error))


if __name__=='__main__':main()
