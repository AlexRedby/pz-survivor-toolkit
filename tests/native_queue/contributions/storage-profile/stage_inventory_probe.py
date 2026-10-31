"""Compile and stage a disposable render-scoped Food.updateAge() observer."""
import os
from pathlib import Path
import subprocess
import zipfile


def stage(output, game, jdk, runtime):
    classes = Path(output) / 'inventory-work-probe-classes'
    classes.mkdir()
    subprocess.run([str(Path(jdk) / 'bin/javac'), '--release', '25', '-cp',
        os.pathsep.join(str(Path(game) / jar) for jar in ('projectzomboid.jar', 'ZombieBuddy.jar')),
        '-d', str(classes), str(Path(__file__).parent / 'java/Main.java')],
        check=True, capture_output=True, text=True, timeout=60)
    if any(not (classes / 'toolkit/inventorywork' / name).is_file()
           for name in ('Main.class', 'Main$FoodAge.class')):
        raise ValueError('Inventory-work observer did not compile')
    for role, settings in runtime['roles'].items():
        if role != 'client1':
            raise ValueError('Inventory-work observer requires one owned client')
        cache = Path(settings['cache'])
        helper = cache / 'mods/InventoryWorkProbe/42'
        for layer in ('common', '42'):
            for directory in ('AnimSets', 'actiongroups'):
                (helper.parent / layer / 'media' / directory).mkdir(parents=True, exist_ok=True)
        jar = helper / 'media/java/InventoryWorkProbe.jar'
        jar.parent.mkdir(parents=True)
        with zipfile.ZipFile(jar, 'x', zipfile.ZIP_DEFLATED) as archive:
            for source in sorted(classes.rglob('*.class')):
                archive.write(source, source.relative_to(classes).as_posix())
        (helper / 'mod.info').write_text('name=Disposable inventory-work observer\nid=InventoryWorkProbe\n'
            'versionMin=42.21\nrequire=\\ZombieBuddy\njavaPkgName=toolkit.inventorywork\n'
            'javaJarFile=media/java/InventoryWorkProbe.jar\n')
    runtime['fixture']['mods'].append('InventoryWorkProbe')
