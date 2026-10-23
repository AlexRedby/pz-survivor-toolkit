#!/usr/bin/env python3
"""Gate and reproduce the cart-only common-root native locomotion set."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import shutil
import cart_clip_bake as baker


ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from JavaPatches.build import require_current_patch_jar
CLIPS={
    'Idle':'Bob_Idle', 'Walk':'Bob_Walk', 'Run':'Bob_Run', 'Sprint':'Bob_Sprint',
    'Backward':'Bob_WalkBwdNoAim1Hand',
    'StrafeLeft':'Bob_StrafeNoAim_Left', 'StrafeRight':'Bob_StrafeNoAim_Right',
    'WoodLeft':'Toolkit_WoodCartPivot_Left', 'WoodRight':'Toolkit_WoodCartPivot_Right',
    'StopRun':'Bob_RunToStop2H_Heavy', 'StopSprint':'Bob_SprintToStop2h_Heavy',
}
TREES=('movement/toolkit_cart_pivot_walk.xml','movement/toolkit_cart_wood_pivot_walk.xml',
       'run/toolkit_cart_pivot_run.xml','sprint/toolkit_cart_pivot_sprint.xml')


def native_key_grids(asset,grids):
    """Preserve native nlerp intervals outside the reparameterized root/Pelvis chain."""
    pattern=re.compile(r'( Animation \{\n  \{ (\w+) \}\n  AnimationKey \{\n   4;\n)   \d+;\n(.*?)(\n  \}\n \})',re.S)
    def prune(match):
        bone=match[2];ticks={round(time*baker.TICKS_PER_SECOND) for time in grids[bone]}
        rows=[line.strip().rstrip(',;')+';;' for line in match[3].splitlines()
              if int(line.strip().split(';',1)[0]) in ticks]
        if len(rows)!=len(ticks):raise ValueError(f'Missing native key ticks for {bone}')
        return match[1]+f'   {len(rows)};\n'+',\n'.join('   '+row for row in rows)+';'+match[4]
    result,count=pattern.subn(prune,asset)
    if count!=45:raise ValueError('Expected 45 native joint tracks')
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game',type=Path,required=True)
    parser.add_argument('--jdk',type=Path,required=True)
    parser.add_argument('--cart-idle',type=Path,required=True,help='Original SaucedCarts _Bob_Cart_Idle.fbx')
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--dry-run',action='store_true',help='Run every gate without changing outputs')
    parser.add_argument('--report',type=Path,help='Optional native replay result JSON')
    args=parser.parse_args()
    patch=ROOT/'JavaPatches/build/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar'
    require_current_patch_jar(patch, ROOT / 'JavaPatches')
    native=args.game/'media/anims_X/Bob'
    project=ROOT/'PZSurvivorToolkit/42/media/anims_X/Bob'
    template=native/'Bob_Idle.x'
    classpath=os.pathsep.join(map(str,(patch,args.game/'projectzomboid.jar',args.game/'ZombieBuddy.jar')))
    skinning={}
    for name in ('MaleBody.x','FemaleBody.x','Clothes/Bob_Trousers.x','Clothes/Kate_Trousers.x'):
        path=args.game/'media/models_X/Skinned'/name
        weighted=bool(re.search(r'SkinWeights\s*\{\s*"Bip01"',path.read_text()))
        if weighted:raise ValueError(f'Cannot reparameterize a deforming Bip01 root: {path}')
        skinning[name]=dict(bip01Weighted=False,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    with tempfile.TemporaryDirectory(prefix='cart-locomotion-root-') as directory:
        work=Path(directory)
        sources=[ROOT/'tools/CartShoppingPickupGenerate.java',ROOT/'tools/CartLocomotionClip.java']
        subprocess.run([str(args.jdk/'bin/javac'),'--release','17','-cp',classpath,'-d',str(work),*map(str,sources)],check=True)
        runtime=[str(args.jdk/'bin/java'),'-Xmx512m','-Djava.awt.headless=true',f'-Djava.library.path={args.game}',f'-Dcart.nativeTemplate={template}',
                 f'-Dcart.animSetRoot={ROOT}/PZSurvivorToolkit/42/media/AnimSets/player',
                 '-cp',os.pathsep.join((str(work),classpath)),'net.alexredby.pztoolkitjavapatches.CartLocomotionClip']
        outputs={};results={};aliases={};manifest=[]
        for suffix,name in CLIPS.items():
            original=(project if name.startswith('Toolkit_') else native)/(name+'.x')
            alias='Toolkit_CartPivot_'+suffix
            raw=work/(alias+'.json');clip=work/(alias+'.x');report=work/(alias+'-replay.json')
            subprocess.run([*runtime,'generate',str(original),str(args.cart_idle),str(raw)],check=True)
            poses=json.loads(raw.read_text())
            asset=native_key_grids(baker.bake(template.read_text(),poses,alias),json.loads(Path(str(raw)+'.grid.json').read_text()))
            clip.write_text(asset)
            subprocess.run([*runtime,'replay',str(original),str(args.cart_idle),str(clip),str(report)],check=True)
            result=json.loads(report.read_text())
            result['source']=str(original);result['sourceSha256']=hashlib.sha256(original.read_bytes()).hexdigest()
            result['generatedClipSha256']=hashlib.sha256(asset.encode()).hexdigest();results[alias]=result
            # Keep authored sides and heavy stops only when their native root is already common.
            if suffix.startswith(('Wood','Stop')) and result['sourceRootMismatch']<=5e-5:
                manifest.append(str(original));continue
            aliases[name]=alias;manifest.append(str(clip))
            outputs[ROOT/f'assets/animations/cart_pivot_{suffix.lower()}.json']=json.dumps(poses,separators=(',',':'))+'\n'
            outputs[project/(alias+'.x')]=asset
        # All clip and graph gates must pass before any source output or cart XML is saved.
        graph_manifest=work/'clips.txt';graph_manifest.write_text('\n'.join(manifest)+'\n')
        graph_report=work/'graph.json'
        tree_root=ROOT/'PZSurvivorToolkit/42/media/AnimSets/player'
        staged=work/'AnimSets/player'
        for folder in ('maskingleft','maskingright','idle'):
            for path in (tree_root/folder).glob('toolkit_cart_*.xml'):
                destination=staged/folder/path.name;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,destination)
        for name in TREES:
            path=tree_root/name;content=path.read_text()
            for original,alias in aliases.items():
                content=content.replace(f'<m_AnimName>{original}</m_AnimName>',f'<m_AnimName>{alias}</m_AnimName>')
            if name.startswith('run/'):
                content=content.replace('<m_BlendTime>0.3</m_BlendTime>','<m_BlendTime>0.2</m_BlendTime>')
            outputs[path]=content
            destination=staged/name;destination.parent.mkdir(parents=True,exist_ok=True);destination.write_text(content)
        subprocess.run([*runtime,'graph',str(args.cart_idle),str(graph_manifest),str(graph_report),str(staged)],check=True)
        result=dict(status='pass',clips=results,aliases=aliases,graph=json.loads(graph_report.read_text()),
                    canonicalReference=dict(path=str(args.cart_idle),sha256=hashlib.sha256(args.cart_idle.read_bytes()).hexdigest()),
                    cartTreeSha256={str(path.relative_to(ROOT)):hashlib.sha256(content.encode()).hexdigest()
                                    for path,content in outputs.items() if path.suffix=='.xml'},
                    verifiedNativeMeshes=skinning,nativeDrawVerified=False)
        if args.report:
            args.report.write_text(json.dumps(result,indent=2)+'\n')
            args.report.with_suffix('.jsonl').write_text(Path(str(graph_report)+'.jsonl').read_text())
        if not args.dry_run:
            for path,content in outputs.items():
                if args.check:
                    if path.read_text()!=content:raise ValueError(f'Generated output differs: {path}')
                else:path.write_text(content)
    print(f'CART_LOCOMOTION_{"GATED" if args.dry_run else "REPRODUCED" if args.check else "GENERATED"} clips={len(results)} nativeDrawVerified=false')


if __name__=='__main__':
    main()
