"""Build against locally installed PZ and ZombieBuddy; no downloaded dependencies."""
import argparse, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
game_defaults = {
    'darwin': Path.home() / 'Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java',
    'win32': Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Steam/steamapps/common/ProjectZomboid',
    'linux': Path.home() / '.steam/steam/steamapps/common/ProjectZomboid/projectzomboid',
}
parser.add_argument('--game', type=Path, default=game_defaults.get(sys.platform), help='Folder containing projectzomboid.jar and ZombieBuddy.jar')
parser.add_argument('--jdk', type=Path)
parser.add_argument('--check', action='store_true', help='Run original-engine versus woven-patch regression')
args = parser.parse_args()
if args.game is None:
    parser.error('Pass --game with the folder containing projectzomboid.jar and ZombieBuddy.jar')
if not (args.game / 'projectzomboid.jar').is_file():
    parser.error(f'projectzomboid.jar not found in "{args.game}". Pass --game with the actual game Java folder.')
if not (args.game / 'ZombieBuddy.jar').is_file():
    parser.error(f'ZombieBuddy.jar not found in "{args.game}". Install the ZombieBuddy loader and copy its JAR to this folder.')
if args.jdk is None:
    if 'JAVA_HOME' in os.environ: args.jdk = Path(os.environ['JAVA_HOME'])
    elif Path('/usr/libexec/java_home').exists(): args.jdk = Path(subprocess.check_output(['/usr/libexec/java_home'], text=True).strip())
    elif shutil.which('javac'): args.jdk = Path(shutil.which('javac')).resolve().parents[1]
    else: parser.error('JDK 25 or newer is required; pass --jdk or set JAVA_HOME')
javac = str(args.jdk / 'bin/javac')
try:
    compiler = subprocess.run([javac, '-version'], check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
except (OSError, subprocess.CalledProcessError) as error:
    parser.error(f'Cannot run javac at "{javac}": {error}. Select JDK 25 or newer with --jdk or JAVA_HOME.')
version = re.search(r'^javac (\d+)', compiler.stdout, re.MULTILINE)
if version is None or int(version.group(1)) < 25:
    parser.error(f'B42.21 requires JDK 25 or newer to read game classes. Found "{compiler.stdout.strip()}" at "{javac}". Select JDK 25+ with --jdk or JAVA_HOME.')
classpath = os.pathsep.join(str(args.game / name) for name in ['projectzomboid.jar', 'ZombieBuddy.jar'])
classes = ROOT / 'build/classes'
if classes.exists(): shutil.rmtree(classes)
classes.mkdir(parents=True)
# Output targets Java 17; reading the game's Java 25 classes still requires javac 25+.
subprocess.run([javac, '--release', '17', '-cp', classpath, '-d', str(classes), *map(str, (ROOT/'src').rglob('*.java'))], check=True)
mod = ROOT / 'build/PZNetworkFix'
if mod.exists(): shutil.rmtree(mod)
jar = mod / '42/media/java/PZNetworkFix.jar'
jar.parent.mkdir(parents=True, exist_ok=True)
(mod/'common').mkdir(exist_ok=True)
subprocess.run([str(args.jdk/'bin/jar'), '--create', '--file', str(jar), '-C', str(classes), '.'], check=True)
(mod/'42/mod.info').write_text('name=PZ Network Fix (Experimental)\nid=PZNetworkFix\nversion=0.1.1\nauthor=AlexRedby\nversionMin=42.21\nversionMax=42.21\nrequire=\\ZombieBuddy\njavaJarFile=media/java/PZNetworkFix.jar\njavaPkgName=net.alexredby.pznetworkfix\nZBVersionMin=2.3.4\ndescription=B42.21 fixes for client zombie speed decoding, vehicle interpolation recovery and authoritative cassette restart after stopping. Requires the ZombieBuddy Java agent on clients for network fixes and on the server for cassette playback. Unsupported target bytecode disables the patches.\n')
for base in [mod/'common/media', mod/'42/media']:
    for name in ['AnimSets', 'actiongroups']: (base/name).mkdir(parents=True, exist_ok=True)
print(jar)

if args.check:
    testclasses = ROOT / 'build/test-classes'
    testclasses.mkdir(exist_ok=True)
    checks = {'zombie.vehicles.NativeChecks': 'NATIVE_CHECKS_PASS',
              'zombie.radio.devices.MediaChecks': 'MEDIA_CHECKS_PASS'}
    sources = [ROOT / 'tests' / (name.replace('.', '/') + '.java') for name in checks]
    subprocess.run([javac, '--release', '17', '-cp', classpath + os.pathsep + str(jar), '-d', str(testclasses), *map(str, sources)], check=True)
    for name, marker in checks.items():
        with tempfile.TemporaryDirectory(prefix='pz-network-native-') as cache:
            result = subprocess.run([str(args.jdk/'bin/java'), '-javaagent:' + str(args.game/'ZombieBuddy.jar') + '=config_dir=' + cache + ',policy=deny-new,verbosity=1', '-Djava.awt.headless=true', '-Dzomboid.steam=0', '-Djava.library.path=.', '-cp', os.pathsep.join([str(testclasses), str(jar), classpath]), name], cwd=args.game, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (ROOT / 'build' / (name.rsplit('.', 1)[-1] + '.log')).write_text(result.stdout)
        print(result.stdout)
        result.check_returncode()
        if marker not in result.stdout: raise RuntimeError(name + ' regression did not complete')
