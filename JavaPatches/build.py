"""Build against locally installed PZ and ZombieBuddy; no downloaded dependencies."""
import argparse, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CHECKS = {'zombie.network.packets.ItemStatsChecks': 'ITEM_STATS_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.QuartermasterPresetChecks': 'QUARTERMASTER_PRESET_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.SourceProofChecks': 'SOURCE_PROOF_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.UITextFitChecks': 'UI_TEXT_FIT_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.ManifestModelChecks': 'MANIFEST_MODEL_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.DrinkFluidCompletionChecks': 'DRINK_FLUID_COMPLETION_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.QueueMembershipChecks': 'QUEUE_MEMBERSHIP_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.InventoryMembershipChecks': 'INVENTORY_MEMBERSHIP_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.ContextMenuDuplicateChecks': 'CONTEXT_MENU_DUPLICATE_CHECKS_PASS',
          'zombie.vehicles.NativeChecks': 'NATIVE_CHECKS_PASS',
          'zombie.entity.CraftBenchChecks': 'CRAFT_BENCH_CHECKS_PASS',
          'zombie.vehicles.VehicleOwnershipChecks': 'VEHICLE_OWNERSHIP_CHECKS_PASS',
          'zombie.vehicles.VehicleTraceChecks': 'VEHICLE_TRACE_CHECKS_PASS',
          'zombie.radio.devices.MediaChecks': 'MEDIA_CHECKS_PASS',
          'zombie.core.BuildChecks': 'BUILD_CHECKS_PASS',
          'zombie.core.QueueManagerChecks': 'QUEUE_MANAGER_CHECKS_PASS',
          'zombie.core.ItemBatchAdmissionChecks': 'ITEM_BATCH_ADMISSION_CHECKS_PASS',
          'zombie.core.ActionAcknowledgementChecks': 'ACTION_ACKNOWLEDGEMENT_CHECKS_PASS',
          'zombie.characters.CharacterTimedActions.ActionCompletionChecks': 'ACTION_COMPLETION_CHECKS_PASS',
          'zombie.characters.AnimalChecks': 'ANIMAL_CHECKS_PASS',
          'zombie.network.packets.EquipmentChecks': 'EQUIPMENT_CHECKS_PASS',
          'zombie.network.packets.MedicalBodyDamageChecks': 'MEDICAL_BODY_DAMAGE_CHECKS_PASS',
          'zombie.characters.MedicalVisualChecks': 'MEDICAL_VISUAL_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.MedicineCooldownChecks': 'MEDICINE_COOLDOWN_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.TVVideoPathChecks': 'TV_VIDEO_PATH_CHECKS_PASS',
          'zombie.core.MedicalTimedActionChecks': 'MEDICAL_TIMED_ACTION_CHECKS_PASS',
          'zombie.iso.objects.HutchChecks': 'HUTCH_CHECKS_PASS',
          'zombie.core.PropertyChecks': 'PROPERTY_CHECKS_PASS',
          'zombie.core.PropertyColdChecks': 'PROPERTY_COLD_CHECKS_PASS',
          'zombie.scripting.entity.components.fluids.FluidChecks': 'FLUID_CHECKS_PASS',
          'zombie.scripting.entity.components.fluids.FoodReplacementOutputChecks': 'FOOD_REPLACEMENT_OUTPUT_CHECKS_PASS',
          'zombie.scripting.entity.components.fluids.FluidColdChecks': 'FLUID_COLD_CHECKS_PASS',
          'zombie.scripting.entity.components.crafting.PianoChecks': 'PIANO_CHECKS_PASS',
          'zombie.iso.FencePropertyChecks': 'FENCE_PROPERTY_CHECKS_PASS',
          'zombie.basements.BasementRoomLookupChecks': 'BASEMENT_ROOM_LOOKUP_CHECKS_PASS',
          'zombie.basements.BasementHallKeyChecks': 'BASEMENT_HALL_KEY_CHECKS_PASS',
          'zombie.iso.MannequinZoneChecks': 'MANNEQUIN_ZONE_CHECKS_PASS',
          'zombie.iso.FenceChecks': 'FENCE_CHECKS_PASS',
          'zombie.core.fonts.FontChecks': 'FONT_CHECKS_PASS',
          'zombie.core.fonts.FontColdChecks': 'FONT_COLD_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.CartSteeringMathTest': 'CART_STEERING_MATH_PASS',
          'net.alexredby.pztoolkitjavapatches.CartSteeringHooksTest': 'CART_STEERING_HOOKS_PASS',
          'net.alexredby.pztoolkitjavapatches.CartMotionSyncTest': 'CART_MOTION_SYNC_PASS',
          'net.alexredby.pztoolkitjavapatches.CartActionSyncTest': 'CART_ACTION_SYNC_PASS',
          'net.alexredby.pztoolkitjavapatches.CartNetworkHeadingTest': 'CART_NETWORK_HEADING_PASS',
          'net.alexredby.pztoolkitjavapatches.CartFootprintTest': 'CART_FOOTPRINT_PASS',
          'net.alexredby.pztoolkitjavapatches.CartLegPaceTest': 'CART_LEG_PACE_PASS',
          'net.alexredby.pztoolkitjavapatches.CartGripTest': 'CART_GRIP_PASS',
          'net.alexredby.pztoolkitjavapatches.CartMetalGripSurfaceChecks': 'CART_METAL_GRIP_SURFACE_PASS',
          'net.alexredby.pztoolkitjavapatches.CartWheelSpinTest': 'CART_WHEEL_SPIN_PASS',
          'net.alexredby.pztoolkitjavapatches.CartWheelWorldTest': 'CART_WHEEL_WORLD_PASS',
          'net.alexredby.pztoolkitjavapatches.CartGroundingTest': 'CART_GROUNDING_PASS',
          'net.alexredby.pztoolkitjavapatches.CartShoppingTest': 'CART_SHOPPING_PASS',
          'net.alexredby.pztoolkitjavapatches.CartShoppingWheelsTest': 'CART_SHOPPING_WHEELS_PASS',
          'net.alexredby.pztoolkitjavapatches.CartTransitionTest': 'CART_TRANSITION_PASS',
          'net.alexredby.pztoolkitjavapatches.CartTransitionMathTest': 'PASS cart transition world/actor roundtrips',
          'net.alexredby.javapatchfixture.CartBootstrapCheck': 'CART_BOOTSTRAP_PASS'}
CHECKS['net.alexredby.pztoolkitjavapatches.CartImpactMotionTest'] = 'CART_IMPACT_MOTION_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartImpactPoseTest'] = 'CART_IMPACT_POSE_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartEmergencyDropTest'] = 'CART_EMERGENCY_DROP_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartPickupApproachTest'] = 'CART_PICKUP_APPROACH_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartObserverPoseTest'] = 'CART_OBSERVER_POSE_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartObserverRenderTest'] = 'CART_OBSERVER_RENDER_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.VideoChecks'] = 'VIDEO_CHECKS_PASS'
TEST_NAMES = {name.rsplit('.', 1)[-1]: name for name in CHECKS}

def positive_timeout(value):
    seconds = int(value)
    if seconds <= 0:
        raise argparse.ArgumentTypeError('must be a positive number of seconds')
    return seconds

parser = argparse.ArgumentParser()
game_defaults = {
    'darwin': Path.home() / 'Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java',
    'win32': Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Steam/steamapps/common/ProjectZomboid',
    'linux': Path.home() / '.steam/steam/steamapps/common/ProjectZomboid/projectzomboid',
}
parser.add_argument('--game', type=Path, default=game_defaults.get(sys.platform), help='Folder containing projectzomboid.jar and ZombieBuddy.jar')
parser.add_argument('--jdk', type=Path)
parser.add_argument('--check', action='store_true', help='Run original-engine versus woven-patch regression')
parser.add_argument('--check-video', action='store_true', help='Run headless video timeline/FFmpeg regression (PZ_TEST_FFMPEG selects executable)')
parser.add_argument('--test', action='append', choices=TEST_NAMES, default=[], metavar='NAME', help='Run only selected regressions; repeat for multiple. Names: ' + ', '.join(TEST_NAMES))
parser.add_argument('--test-timeout', type=positive_timeout, default=120, metavar='SECONDS', help='Timeout for each Java regression invocation (default: 120 seconds)')
args = parser.parse_args()
if args.test:
    selected = [TEST_NAMES[name] for name in args.test]
else:
    selected = [name for name in CHECKS if (args.check_video if name.endswith('.VideoChecks') else args.check)]
if args.game is None:
    parser.error('Pass --game with the folder containing projectzomboid.jar and ZombieBuddy.jar')
args.game = args.game.resolve()
if not (args.game / 'projectzomboid.jar').is_file():
    parser.error(f'projectzomboid.jar not found in "{args.game}". Pass --game with the actual game Java folder.')
if not (args.game / 'ZombieBuddy.jar').is_file():
    parser.error(f'ZombieBuddy.jar not found in "{args.game}". Install the ZombieBuddy loader and copy its JAR to this folder.')
if args.jdk is None:
    if 'JAVA_HOME' in os.environ: args.jdk = Path(os.environ['JAVA_HOME'])
    elif Path('/usr/libexec/java_home').exists(): args.jdk = Path(subprocess.check_output(['/usr/libexec/java_home'], text=True).strip())
    elif shutil.which('javac'): args.jdk = Path(shutil.which('javac')).resolve().parents[1]
    else: parser.error('JDK 25 or newer is required; pass --jdk or set JAVA_HOME')
args.jdk = args.jdk.resolve()
javac = str(args.jdk / 'bin/javac')
try:
    compiler = subprocess.run([javac, '-version'], check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
except (OSError, subprocess.CalledProcessError) as error:
    parser.error(f'Cannot run javac at "{javac}": {error}. Select JDK 25 or newer with --jdk or JAVA_HOME.')
version = re.search(r'^javac (\d+)', compiler.stdout, re.MULTILINE)
if version is None or int(version.group(1)) < 25:
    parser.error(f'B42.21 requires JDK 25 or newer to read game classes. Found "{compiler.stdout.strip()}" at "{javac}". Select JDK 25+ with --jdk or JAVA_HOME.')
classpath = os.pathsep.join(str(args.game / name) for name in ['projectzomboid.jar', 'ZombieBuddy.jar'])
build = ROOT / 'build'
destination = build / 'PZToolkitJavaPatches'
for directory in (build, destination):
    if directory.is_symlink() or (directory.exists() and not directory.is_dir()):
        parser.error(f'Build output must be a regular directory: {directory}')

def log_path(name, trace):
    return build / (name.rsplit('.', 1)[-1] + ('-trace' if trace else '') + '.log')

for name in selected:
    for trace in ([False, True] if name.endswith('VehicleTraceChecks') else [False]):
        log = log_path(name, trace)
        if log.is_symlink() or (log.exists() and not log.is_file()):
            parser.error(f'Check log must be a regular file: {log}')
build.mkdir(exist_ok=True)
temporary = Path(tempfile.mkdtemp(prefix='.build-', dir=build))
previous = temporary / 'previous'
promoted = False
try:
    classes = temporary / 'classes'
    classes.mkdir()
    # Output targets Java 17; reading the game's Java 25 classes still requires javac 25+.
    subprocess.run([javac, '--release', '17', '-cp', classpath, '-d', str(classes), *map(str, (ROOT/'src').rglob('*.java'))], check=True)
    mod = temporary / 'PZToolkitJavaPatches'
    jar = mod / '42/media/java/PZToolkitJavaPatches.jar'
    jar.parent.mkdir(parents=True, exist_ok=True)
    (mod/'common').mkdir(exist_ok=True)
    fontjar = mod / '42/media/bootstrap/PZToolkitFonts.jar'
    fontjar.parent.mkdir(parents=True, exist_ok=True)
    manifest = temporary / 'FONT-MANIFEST.MF'
    manifest.write_text('Manifest-Version: 1.0\nZB-Preload: true\n\n')
    # Stable ZIP dates preserve approval hashes when the compiled contents do not change.
    jar_date = '--date=2000-01-01T00:00:00Z'
    subprocess.run([str(args.jdk/'bin/jar'), '--create', jar_date, '--file', str(jar), '-C', str(classes), 'net/alexredby/pztoolkitjavapatches'], check=True)
    subprocess.run([str(args.jdk/'bin/jar'), '--create', jar_date, '--file', str(fontjar), '--manifest', str(manifest), '-C', str(classes), 'net/alexredby/pztoolkitbootstrap'], check=True)
    (mod/'42/mod.info').write_text('name=Toolkit Java Patches (Experimental)\nid=PZToolkitJavaPatches\nversion=0.1.44\nauthor=AlexRedby\nversionMin=42.21\nversionMax=42.21\nrequire=\\ZombieBuddy\njavaJarFile=media/java/PZToolkitJavaPatches.jar\njavaPkgName=net.alexredby.pztoolkitjavapatches\nZBVersionMin=2.3.4\ndescription=B42.21 fixes for stale optional item-stat fields in reused network packets, item-transaction cancellation ownership and aggregate ordinary container-batch admission, missing-action completion detection, common action completion boundaries and native action outcome acknowledgements, client zombie speed decoding, vehicle interpolation recovery, authoritative cassette restart after stopping, multiplayer build cancellation acknowledgements, stale workstation component references after square object-index changes, live-animal trailer location reconciliation, incomplete equipment acknowledgement handling, late medical updates and requests after patient disconnect, medical visual removal synchronization, null-animal hutch unloading crashes, five native string-property startup exceptions, two malformed native fluid-container names, premature breakable-fence validation, missing level-three wooden-fence material metadata, the native Piano recipe icon, cross-cell basement room lookup loss, the duplicate stock basement-access hall persistent key, the malformed stock mannequin zone, early native font-page loading and occupied-vehicle authority loss after collision handoff. Requires the ZombieBuddy Java agent on clients for zombie, vehicle, animal and equipment patches and on the server for cassette playback, safe queue build interruption, workstation reference recovery and vehicle authority recovery. The hutch unloading, native string-property and fluid-name guards apply in clients, single-player and servers. The font startup fix requires explicit early patches_jar activation of the separate local font JAR; enabling the mod alone is insufficient. Includes client cart steering and floor contact for the selected shopping cart and wheelbarrows. Unsupported target bytecode disables the patches.\n')
    for base in [mod/'common/media', mod/'42/media']:
        for name in ['AnimSets', 'actiongroups']: (base/name).mkdir(parents=True, exist_ok=True)

    if selected:
        testclasses = temporary / 'test-classes'
        testclasses.mkdir(exist_ok=True)
        checks = {name: CHECKS[name] for name in selected}
        sources = [ROOT / 'tests' / (name.replace('.', '/') + '.java') for name in checks]
        subprocess.run([javac, '--release', '17', '-cp', os.pathsep.join([classpath, str(jar), str(fontjar)]), '-sourcepath', str(ROOT / 'tests'), '-d', str(testclasses), *map(str, sources)], check=True)
        for name, marker in checks.items():
            for trace in ([False, True] if name.endswith("VehicleTraceChecks") else [False]):
                with tempfile.TemporaryDirectory(prefix='pz-java-native-') as cache:
                    runtime_classes = testclasses
                    if name == 'net.alexredby.javapatchfixture.CartBootstrapCheck':
                        runtime_classes = Path(cache) / 'classes'
                        relative = Path(name.replace('.', '/') + '.class')
                        (runtime_classes / relative).parent.mkdir(parents=True)
                        shutil.copy2(testclasses / relative, runtime_classes / relative)
                    cold_fonts = name == 'zombie.core.fonts.FontColdChecks'
                    testpath = [str(testclasses), classpath] if cold_fonts else [str(runtime_classes), str(jar), str(fontjar), classpath]
                    log = log_path(name, trace)
                    try:
                        with log.open('w') as output:
                            result = subprocess.run([str(args.jdk/'bin/java'), '-javaagent:' + str(args.game/'ZombieBuddy.jar') + '=config_dir=' + cache + ',policy=deny-new,verbosity=1' + (',patches_jar=' + str(fontjar) + ':net.alexredby.pztoolkitbootstrap' if cold_fonts else ''), '-Dpz.vehicle.trace=' + str(trace).lower(), '-Djava.awt.headless=true', '-Dpz.test.cache=' + cache, '-Dpz.test.project=' + str(ROOT.parent), '-Dpz.test.patch.jar=' + str(jar), '-Dzomboid.steam=0', '-Djava.library.path=.', '-cp', os.pathsep.join(testpath), name], cwd=args.game, text=True, stdout=output, stderr=subprocess.STDOUT, timeout=args.test_timeout)
                    except subprocess.TimeoutExpired as error:
                        print(log.read_text(errors='replace'))
                        raise RuntimeError(f'{name} timed out after {args.test_timeout} seconds; output saved to {log}') from error
                output = log.read_text(errors='replace')
                print(output)
                result.check_returncode()
                if 'ERROR transforming' in output: raise RuntimeError(name + ' bytecode transformation failed')
                if marker not in output: raise RuntimeError(name + ' regression did not complete')
                if name == 'net.alexredby.javapatchfixture.CartBootstrapCheck' and '[ZB] Transformed: zombie.core.skinnedmodel.ModelManager (retransformed)' not in output:
                    raise RuntimeError('cold bootstrap did not apply the model recovery patch')
    if destination.exists():
        destination.rename(previous)
    try:
        mod.rename(destination)
    except OSError:
        if previous.exists():
            try:
                previous.rename(destination)
            except OSError as error:
                raise OSError(f'Previous Java mod is preserved at {previous}; restore failed') from error
        raise
    promoted = True
finally:
    if promoted or not previous.exists():
        shutil.rmtree(temporary)
print(destination / '42/media/java/PZToolkitJavaPatches.jar')
