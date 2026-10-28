#!/usr/bin/env python3
"""Reproduce the standing shopping-cart body clip from the native Bob endpoints.

Runtime IK supplies model-specific hand contact once; this asset contains native
joint interpolation only, without looting motion, deferred movement or baked IK.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import cart_clip_bake as baker

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from JavaPatches.build import require_current_patch_jar
CLIP='Toolkit_ShoppingCart_Pickup'

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game',required=True,type=Path)
    parser.add_argument('--jdk',required=True,type=Path)
    parser.add_argument('--cart-idle',required=True,type=Path,help='Original SaucedCarts _Bob_Cart_Idle.fbx')
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    patch=ROOT/'JavaPatches/build/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar'
    require_current_patch_jar(patch, ROOT / 'JavaPatches')
    classpath=os.pathsep.join(map(str,(patch,args.game/'projectzomboid.jar',args.game/'ZombieBuddy.jar')))
    idle=args.game/'media/anims_X/Bob/Bob_Idle.x'
    cart=args.cart_idle
    with tempfile.TemporaryDirectory(prefix='cart-shopping-clip-') as directory:
        work=Path(directory)
        sources=[ROOT/'tools/CartShoppingPickupGenerate.java',ROOT/'tools/CartShoppingPickupReplay.java',ROOT/'tools/CartClipCheck.java']
        subprocess.run([str(args.jdk/'bin/javac'),'--release','25','-cp',classpath,'-d',str(work),*map(str,sources)],check=True)
        runtime=[str(args.jdk/'bin/java'),'-Djava.awt.headless=true',f'-Djava.library.path={args.game}',
                 '-cp',os.pathsep.join((str(work),classpath))]
        raw=work/'poses.json'
        subprocess.run([*runtime,'net.alexredby.pztoolkitjavapatches.CartShoppingPickupGenerate',str(idle),str(cart),str(raw)],check=True)
        poses=json.loads(raw.read_text());asset=baker.bake(idle.read_text(),poses,CLIP)
        clip=work/(CLIP+'.x');clip.write_text(asset)
        expected=work/'expected.tsv'
        expected.write_text(''.join(str(sample['time'])+'\t'+name+'\t'+'\t'.join(map(str,matrix))+'\n'
            for sample in poses for name,matrix in sample['bones'].items()))
        subprocess.run([*runtime,'CartClipCheck',str(clip),str(expected)],check=True)
        subprocess.run([*runtime,'net.alexredby.pztoolkitjavapatches.CartShoppingPickupReplay',str(clip),str(cart)],check=True)
        outputs={ROOT/'assets/animations/shopping_cart_pickup.json':json.dumps(poses,separators=(',',':'))+'\n',
                 ROOT/f'PZSurvivorToolkit/42/media/anims_X/Bob/{CLIP}.x':asset}
        for path,content in outputs.items():
            if args.check:
                if path.read_text()!=content:raise ValueError(f'Generated output differs: {path}')
            else:path.write_text(content)
    print(f'SHOPPING_PICKUP_{"REPRODUCED" if args.check else "GENERATED"} samples={len(poses)} standing=true runtimeIK=true')

if __name__=='__main__':main()
