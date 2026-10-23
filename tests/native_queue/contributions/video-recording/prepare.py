"""Prepare a disposable macOS B42.21 video fixture; never launch the game."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent


def prepare(args):
    if sys.platform != 'darwin':
        raise ValueError('This native launcher is verified only on macOS')
    profile = args.profile.expanduser()
    if not profile.is_absolute() or profile.exists() or profile.is_symlink():
        raise ValueError('Use a new, nonexistent absolute profile path')
    profile = profile.resolve()
    if profile.is_relative_to(HERE) or any(c in str(profile) for c in ',:\n\r'):
        raise ValueError('Profile must be outside the contribution and contain no comma, colon or newline')
    game, jdk, java, buddy, patch, ffmpeg = [getattr(args, name).expanduser().resolve() for name in
        ('game', 'jdk', 'java', 'zombie_buddy_mod', 'patch_mod', 'ffmpeg')]
    for source in (game, jdk, buddy, patch):
        if profile.is_relative_to(source):
            raise ValueError('Profile must be outside dependency directories')
    for file in (game/'projectzomboid.jar', game/'ZombieBuddy.jar', buddy/'42/mod.info',
                 buddy/'libs/ZombieBuddy.jar', patch/'42/mod.info', patch/'42/media/java/PZToolkitJavaPatches.jar'):
        if not file.is_file():
            raise ValueError(f'Missing dependency: {file}')
    for file in (java, jdk/'bin/javac', ffmpeg):
        if not file.is_file() or not os.access(file, os.X_OK):
            raise ValueError(f'Missing executable: {file}')
    if ':' in str(game):
        raise ValueError('Game path cannot contain a classpath separator')
    version = subprocess.run([str(jdk/'bin/javac'), '-version'], check=True, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15).stdout
    match = re.search(r'^javac (\d+)', version, re.MULTILINE)
    if match is None or int(match[1]) < 25:
        raise ValueError('JDK 25+ is required to read B42.21 classes')

    profile.mkdir(parents=True, exist_ok=False)
    for name in ('Lua', 'classes', 'zombie-buddy', 'mods'):
        (profile/name).mkdir()
    for name, source in [('ZombieBuddy', buddy), ('PZToolkitJavaPatches', patch)]:
        for part in ('42', 'common', 'libs'):
            if (source/part).is_dir():
                shutil.copytree(source/part, profile/'mods'/name/part)
    jar = profile/'mods/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar'
    approvals = {'formatVersion': 2, 'mods': [{'id': 'PZToolkitJavaPatches',
        'jar_hash': hashlib.sha256(jar.read_bytes()).hexdigest(), 'decision': True,
        'time': datetime.now(timezone.utc).isoformat()}]}
    (profile/'zombie-buddy/mod_approvals.json').write_text(json.dumps(approvals, indent=2))
    fixture = profile/'mods/VideoFixture'
    for part in ('common/media/AnimSets', 'common/media/actiongroups', '42/media/AnimSets',
                 '42/media/actiongroups', '42/media/lua/client'):
        (fixture/part).mkdir(parents=True, exist_ok=True)
    (fixture/'42/mod.info').write_text('name=Video Fixture\nid=VideoFixture\nversionMin=42.21\nversionMax=42.21\n')
    lua = fixture/'42/media/lua/client'
    shutil.copyfile(HERE/'VideoFixture.lua', lua/'ZZVideoFixture.lua')
    config = {'output': str(profile/'videos'), 'ffmpeg': str(ffmpeg)}
    (lua/'ToolkitVideoConfig.lua').write_text('return {\n' + ''.join(
        f'    {key} = {json.dumps(value, ensure_ascii=False)},\n' for key, value in config.items()) + '}\n', encoding='utf-8')
    (profile/'mods/default.txt').write_text('VERSION = 1,\nmods\n{\n mod = ZombieBuddy,\n mod = PZToolkitJavaPatches,\n mod = VideoFixture,\n}\nmaps\n{\n}\n')
    (profile/'mods/reset-mods-42_00.txt').write_text('')
    (profile/'options.ini').write_text('version=10\nwidth=1280\nheight=720\nfullScreen=false\nborderless=false\nmusicVolume=0\nsoundVolume=0\nvoiceEnable=false\npauseOnFocusLoss=false\nlanguage=' + args.language + '\n')
    subprocess.run([str(jdk/'bin/javac'), '--release', '25', '-cp', str(game/'projectzomboid.jar'),
                    '-d', str(profile/'classes'), str(HERE/'ToolkitVideoLauncher.java')], check=True, timeout=60)
    # Keep inherited agent options from starting a second loader outside this profile.
    argv = ['/usr/bin/env', 'JDK_JAVA_OPTIONS=', 'JAVA_TOOL_OPTIONS=', '_JAVA_OPTIONS=',
        'launchctl', 'asuser', str(os.getuid()), str(java), '-XstartOnFirstThread', '-Djava.awt.headless=true',
        '--enable-native-access=ALL-UNNAMED', '--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED',
        '-Dzomboid.steam=0', '-Djava.library.path=.', '-Xmx2048m', '-XX:+UseZGC',
        '-javaagent:' + str(game/'ZombieBuddy.jar') + '=config_dir=' + str(profile/'zombie-buddy') + ',policy=deny-new,verbosity=1',
        '-cp', str(profile/'classes') + os.pathsep + str(game/'projectzomboid.jar'), 'ToolkitVideoLauncher',
        '-nosteam', '-novoip', '-cachedir=' + str(profile)]
    (profile/'launch.json').write_text(json.dumps({'cwd': str(game), 'argv': argv}, indent=2))
    return profile/'launch.json'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ('game', 'jdk', 'java', 'zombie-buddy-mod', 'patch-mod', 'ffmpeg', 'profile'):
        parser.add_argument('--' + flag, type=Path, required=True)
    parser.add_argument('--language', choices=('EN', 'RU'), default='EN')
    args = parser.parse_args()
    try:
        print(prepare(args))
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
