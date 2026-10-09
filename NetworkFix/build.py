"""Build against locally installed PZ and ZombieBuddy; no downloaded dependencies."""
import argparse, os, shutil, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--game', type=Path, default=Path.home() / 'Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java')
parser.add_argument('--jdk', type=Path)
parser.add_argument('--check', action='store_true', help='Run original-engine versus woven-patch regression')
args = parser.parse_args()
if args.jdk is None:
    if 'JAVA_HOME' in os.environ: args.jdk = Path(os.environ['JAVA_HOME'])
    elif Path('/usr/libexec/java_home').exists(): args.jdk = Path(subprocess.check_output(['/usr/libexec/java_home'], text=True).strip())
    elif shutil.which('javac'): args.jdk = Path(shutil.which('javac')).resolve().parents[1]
    else: parser.error('A JDK is required; pass --jdk or set JAVA_HOME')
classpath = os.pathsep.join(str(args.game / name) for name in ['projectzomboid.jar', 'ZombieBuddy.jar'])
classes = ROOT / 'build/classes'
if classes.exists(): shutil.rmtree(classes)
classes.mkdir(parents=True)
subprocess.run([str(args.jdk / 'bin/javac'), '--release', '17', '-cp', classpath, '-d', str(classes), *map(str, (ROOT/'src').rglob('*.java'))], check=True)
mod = ROOT / 'build/PZNetworkFix'
jar = mod / '42/media/java/client/PZNetworkFix.jar'
jar.parent.mkdir(parents=True, exist_ok=True)
(mod/'common').mkdir(exist_ok=True)
subprocess.run([str(args.jdk/'bin/jar'), '--create', '--file', str(jar), '-C', str(classes), '.'], check=True)
(mod/'42/mod.info').write_text('name=PZ Network Fix (Experimental)\nid=PZNetworkFix\nversion=0.1.0\nauthor=AlexRedby\nversionMin=42.21\nversionMax=42.21\nrequire=\\ZombieBuddy\njavaJarFile=media/java/client/PZNetworkFix.jar\njavaPkgName=net.alexredby.pznetworkfix\nZBVersionMin=2.3.4\ndescription=Experimental B42.21 client patch for zombie speed decoding and vehicle interpolation recovery. Requires the ZombieBuddy Java agent. Unsupported target bytecode disables the patches.\n')
for base in [mod/'common/media', mod/'42/media']:
    for name in ['AnimSets', 'actiongroups']: (base/name).mkdir(parents=True, exist_ok=True)
print(jar)

if args.check:
    testclasses = ROOT / 'build/test-classes'
    testclasses.mkdir(exist_ok=True)
    subprocess.run([str(args.jdk/'bin/javac'), '--release', '17', '-cp', classpath + os.pathsep + str(jar), '-d', str(testclasses), str(ROOT/'tests/zombie/vehicles/NativeChecks.java')], check=True)
    with tempfile.TemporaryDirectory(prefix='pz-network-native-') as cache:
        result = subprocess.run([str(args.jdk/'bin/java'), '-javaagent:' + str(args.game/'ZombieBuddy.jar') + '=config_dir=' + cache + ',policy=deny-new,verbosity=1', '-Djava.awt.headless=true', '-Dzomboid.steam=0', '-Djava.library.path=.', '-cp', os.pathsep.join([str(testclasses), str(jar), classpath]), 'zombie.vehicles.NativeChecks'], cwd=args.game, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (ROOT/'build/native-checks.log').write_text(result.stdout)
    print(result.stdout)
    result.check_returncode()
    if 'NATIVE_CHECKS_PASS' not in result.stdout: raise RuntimeError('Native regression did not complete')
