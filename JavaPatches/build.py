"""Build against local PZ, ZombieBuddy and Kotlin compiler inputs; no downloads."""
import argparse, hashlib, json, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path
from zipfile import ZipFile, BadZipFile

ROOT = Path(__file__).resolve().parent
KOTLIN_VERSION = '2.4.21'
JVM_TARGET = '25'
KOTLIN_MODULE = 'pz_toolkit_java_patches'
KOTLIN_RUNTIME_PACKAGE = 'net/alexredby/pztoolkitruntime/kotlin'
SOURCE_MANIFEST = 'META-INF/pztoolkit-build-inputs.json'


def source_fingerprints(root):
    """Portable fingerprints for the ordinary runtime and its build tools, without local paths."""
    sources = list((root / 'src/net/alexredby/pztoolkitjavapatches').rglob('*'))
    sources = [path for path in sources if path.suffix in ('.java', '.kt') and path.is_file()]
    sources += [path for path in (root / 'build.py', root / 'tools/RelocateKotlin.java') if path.is_file()]
    return {path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(sources)}


def write_source_manifest(root, classes, fingerprints=None):
    target = classes / SOURCE_MANIFEST
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({'format': 1, 'sources': source_fingerprints(root) if fingerprints is None else fingerprints},
                                 sort_keys=True, separators=(',', ':')) + '\n', encoding='utf-8')


def require_current_patch_jar(jar, root):
    """Authoring tools must execute the complete current mixed artifact, not partial Java overlays."""
    try:
        with ZipFile(jar) as archive:
            manifest = json.loads(archive.read(SOURCE_MANIFEST))
    except (OSError, BadZipFile, KeyError, ValueError) as error:
        raise ValueError(f'Cannot verify current patch JAR {jar}: {error}. Rebuild JavaPatches/build.py first.') from error
    if not isinstance(manifest, dict) or manifest.get('format') != 1 or manifest.get('sources') != source_fingerprints(root):
        raise ValueError(f'Patch JAR {jar} does not match the current runtime sources/build tools. Rebuild JavaPatches/build.py first.')


def kotlin_toolchain(home, parser):
    """Resolve a matching local compiler/runtime before touching build output."""
    if home is None:
        configured = os.environ.get('KOTLIN_HOME')
        compiler = shutil.which('kotlinc') if not configured else None
        home = Path(configured) if configured else Path(compiler).resolve().parents[1] if compiler else None
    if home is None:
        parser.error(f'Kotlin {KOTLIN_VERSION} compiler distribution is required; pass --kotlin-home or set KOTLIN_HOME.')
    home = home.resolve()
    for name in ('kotlin-compiler.jar', 'kotlin-stdlib.jar'):
        jar = home / 'lib' / name
        try:
            with ZipFile(jar) as archive:
                manifest = archive.read('META-INF/MANIFEST.MF').decode('utf-8')
            version = re.search(r'^Implementation-Version: (\d+\.\d+\.\d+)(?:[-\r\n]|$)', manifest, re.MULTILINE)
            if version is None or version.group(1) != KOTLIN_VERSION:
                raise ValueError(f'{name} must be version {KOTLIN_VERSION}')
        except (OSError, BadZipFile, KeyError, UnicodeError, ValueError) as error:
            parser.error(f'Invalid Kotlin {KOTLIN_VERSION} distribution at "{home}": {error}. Select it with --kotlin-home or KOTLIN_HOME.')
    for name in ('LICENSE.txt', 'NOTICE.txt', 'COPYRIGHT.txt'):
        if not (home / 'license' / name).is_file():
            parser.error(f'Kotlin distribution is missing license/{name}: {home}')
    return home


def stage_kotlin_runtime(home, destination):
    """Bundle stdlib in the ordinary mod only; no compiler or early-font dependency."""
    with ZipFile(home / 'lib/kotlin-stdlib.jar') as archive:
        for entry in archive.infolist():
            # The only multi-release entry is the Java 9 module descriptor, irrelevant on the classpath.
            if entry.is_dir() or not (entry.filename.startswith('kotlin/')
                                     or re.fullmatch(r'META-INF/[^/]+\.kotlin_module', entry.filename)):
                continue
            relative = Path(entry.filename)
            if '..' in relative.parts or relative.is_absolute():
                raise ValueError(f'Invalid Kotlin runtime entry: {entry.filename}')
            target = destination / (KOTLIN_RUNTIME_PACKAGE + entry.filename[len('kotlin'):]
                                    if entry.filename.startswith('kotlin/') else relative)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(entry))
    for name in ('LICENSE.txt', 'NOTICE.txt', 'COPYRIGHT.txt'):
        target = destination / 'META-INF/licenses/kotlin' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(home / 'license' / name, target)


def _run_compiler(command):
    return subprocess.run(command, check=True)


def compile_kotlin(jdk, home, classpath, destination, sources, *,
                   module_name=KOTLIN_MODULE, options=(), run=None):
    """Share compiler policy while callers retain classpaths, source order and execution policy."""
    command = [str(Path(jdk) / 'bin/java'), '-jar', str(Path(home) / 'lib/kotlin-compiler.jar'),
               '-kotlin-home', str(home), '-jvm-target', JVM_TARGET, '-module-name', module_name,
               '-no-stdlib', '-no-reflect', *options, '-classpath', classpath,
               '-d', str(destination), *map(str, sources)]
    return (run or _run_compiler)(command)


def build_kotlin_relocator(jdk, home, destination, *, run=None):
    """Compile the build-only tool once and return its invocation prefix for explicit scopes."""
    compiler = str(Path(home) / 'lib/kotlin-compiler.jar')
    (run or _run_compiler)([str(Path(jdk) / 'bin/javac'), '--release', JVM_TARGET,
                           '-cp', compiler, '-d', str(destination), str(ROOT / 'tools/RelocateKotlin.java')])
    return [str(Path(jdk) / 'bin/java'), '-cp', os.pathsep.join([str(destination), compiler]), 'RelocateKotlin']


CHECKS = {'net.alexredby.pztoolkitjavapatches.ScriptItemPropertiesChecks': 'SCRIPT_ITEM_PROPERTIES_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.ItemLaundryPropertiesChecks': 'ITEM_LAUNDRY_PROPERTIES_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.RecipeItemPropertiesChecks': 'RECIPE_ITEM_PROPERTIES_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.FluidScriptPropertiesChecks': 'FLUID_SCRIPT_PROPERTIES_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.RadioDeviceLookupChecks': 'RADIO_DEVICE_LOOKUP_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.WormCompostChecks': 'WORM_COMPOST_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.AlarmClockChecks': 'ALARM_CLOCK_CHECKS_PASS',
          'zombie.vehicles.VehicleInventoryOrderingChecks': 'VEHICLE_INVENTORY_ORDERING_CHECKS_PASS',
          'zombie.radio.devices.RadioInventoryStateChecks': 'RADIO_INVENTORY_STATE_CHECKS_PASS',
          'zombie.network.packets.ItemStatsChecks': 'ITEM_STATS_CHECKS_PASS',
          'net.alexredby.javapatchfixture.KotlinRuntimeChecks': 'KOTLIN_RUNTIME_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.QuartermasterPresetChecks': 'QUARTERMASTER_PRESET_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.SourceProofChecks': 'SOURCE_PROOF_CHECKS_PASS',
          'zombie.core.FitnessConstructorChecks': 'FITNESS_CONSTRUCTOR_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.UITextFitChecks': 'UI_TEXT_FIT_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.ManifestModelChecks': 'MANIFEST_MODEL_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.DrinkFluidCompletionChecks': 'DRINK_FLUID_COMPLETION_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.WashWaterRuleChecks': 'WASH_WATER_RULE_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.QueueOwnershipChecks': 'QUEUE_OWNERSHIP_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.QueueMembershipChecks': 'QUEUE_MEMBERSHIP_CHECKS_PASS',
          'net.alexredby.pztoolkitjavapatches.QueueViewChecks': 'QUEUE_VIEW_CHECKS_PASS',
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
          'zombie.characters.CharacterTimedActions.ActionValidityChecks': 'ACTION_VALIDITY_CHECKS_PASS',
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
          'net.alexredby.pztoolkitjavapatches.CartShoppingTurnTest': 'CART_SHOPPING_TURN_PASS',
          'net.alexredby.pztoolkitjavapatches.CartShoppingGripTest': 'CART_SHOPPING_GRIP_PASS',
          'net.alexredby.pztoolkitjavapatches.CartMetalGripSurfaceChecks': 'CART_METAL_GRIP_SURFACE_PASS',
          'net.alexredby.pztoolkitjavapatches.CartWheelSpinTest': 'CART_WHEEL_SPIN_PASS',
          'net.alexredby.pztoolkitjavapatches.CartWheelWorldTest': 'CART_WHEEL_WORLD_PASS',
          'net.alexredby.pztoolkitjavapatches.CartGroundingTest': 'CART_GROUNDING_PASS',
          'net.alexredby.pztoolkitjavapatches.CartShoppingTest': 'CART_SHOPPING_PASS',
          'net.alexredby.pztoolkitjavapatches.CartShoppingWheelsTest': 'CART_SHOPPING_WHEELS_PASS',
          'net.alexredby.pztoolkitjavapatches.CartTransitionTest': 'CART_TRANSITION_PASS',
          'net.alexredby.pztoolkitjavapatches.CartTransitionMathTest': 'PASS cart transition world/actor roundtrips',
          'net.alexredby.javapatchfixture.CartBootstrapCheck': 'CART_BOOTSTRAP_PASS'}
CHECKS['net.alexredby.pztoolkitjavapatches.CartInjuryTest'] = 'CART_INJURY_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartInjuryGripTest'] = 'CART_INJURY_GRIP_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartSpeedParityTest'] = 'CART_SPEED_PARITY_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartLegClearancePaletteTest'] = 'CART_LEG_CLEARANCE_PALETTE_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartLegClearanceTest'] = 'CART_LEG_CLEARANCE_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartAnimationBlendTest'] = 'CART_ANIMATION_BLEND_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartImpactMotionTest'] = 'CART_IMPACT_MOTION_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartImpactPoseTest'] = 'CART_IMPACT_POSE_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartEmergencyDropTest'] = 'CART_EMERGENCY_DROP_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartPickupApproachTest'] = 'CART_PICKUP_APPROACH_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartObserverPoseTest'] = 'CART_OBSERVER_POSE_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.CartObserverRenderTest'] = 'CART_OBSERVER_RENDER_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.DamnLibraryAnimationChecks'] = 'DAMN_LIBRARY_ANIMATION_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.HostLoaderChecks'] = 'HOST_LOADER_CHECKS_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.VehicleStepPoseTest'] = 'VEHICLE_STEP_POSE_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.VehicleTransitionRenderTest'] = 'VEHICLE_TRANSITION_RENDER_PASS'
CHECKS['net.alexredby.pztoolkitjavapatches.VideoChecks'] = 'VIDEO_CHECKS_PASS'
CHECKS['zombie.pathfind.nativeCode.BarricadedDoorPathChecks'] = 'BARRICADED_DOOR_PATH_CHECKS_PASS'
# Workshop-dependent checks require an explicit --test; --check keeps its game-only inputs.
EXPLICIT_ONLY_CHECKS = {'net.alexredby.pztoolkitjavapatches.WashWaterRuleChecks',
                        'net.alexredby.pztoolkitjavapatches.QueueOwnershipChecks'}
TEST_NAMES = {name.rsplit('.', 1)[-1]: name for name in CHECKS}

def positive_timeout(value):
    seconds = int(value)
    if seconds <= 0:
        raise argparse.ArgumentTypeError('must be a positive number of seconds')
    return seconds


def _without_comments(text, kotlin=False):
    """Mask comments as whitespace; retain literals and reflection references.

    Kotlin block comments nest and its string templates can contain quoted
    expressions. Java block comments stop at the first closer, and Java text
    blocks allow escapes. This only locates comments, not language dependencies.
    """
    tokens = re.compile(r'"""|["\'`]|//[^\r\n]*|/\*')
    blocks = re.compile(r'/\*|\*/')
    comments = []

    def comment_end(start):
        depth, end = 1, start + 2
        while delimiter := blocks.search(text, end):
            end = delimiter.end()
            if delimiter.group() == '*/':
                depth -= 1
            elif kotlin:
                depth += 1
            if not depth:
                return end
        return len(text)

    def quoted_end(start, quote):
        end = start + len(quote)
        while end < len(text):
            if text.startswith(quote, end):
                return end + len(quote)
            if kotlin and quote in ('"', '"""') and text.startswith('${', end):
                end = template_end(end + 2)
            elif text[end] == '\\' and quote != '`' and not (kotlin and quote == '"""'):
                end += 2
            else:
                end += 1
        return len(text)

    def template_end(end):
        depth = 1
        while end < len(text):
            if text.startswith('/*', end):
                stop = comment_end(end)
                comments.append((end, stop))
                end = stop
            elif text.startswith('//', end):
                newline = text.find('\n', end)
                stop = len(text) if newline < 0 else newline + 1
                comments.append((end, stop))
                end = stop
            elif text[end] in ('"', "'", '`'):
                quote = '"""' if text.startswith('"""', end) else text[end]
                end = quoted_end(end, quote)
            else:
                if text[end] == '{':
                    depth += 1
                elif text[end] == '}':
                    depth -= 1
                    if not depth:
                        return end + 1
                end += 1
        return end

    cursor = 0
    while match := tokens.search(text, cursor):
        token = match.group()
        if token.startswith('//') or token == '/*':
            end = comment_end(match.start()) if token == '/*' else match.end()
            comments.append((match.start(), end))
        else:
            end = quoted_end(match.start(), token)
        cursor = end
    parts, cursor = [], 0
    for start, end in comments:
        parts.append(text[cursor:start])
        parts.append(re.sub(r'[^\r\n]', ' ', text[start:end]))
        cursor = end
    parts.append(text[cursor:])
    return ''.join(parts)


def check_sources(names):
    """Select migrated checks and reachable Java/Kotlin helpers without unrelated checks."""
    directory = ROOT / 'tests'
    selected = []
    for name in dict.fromkeys(names):
        source = directory / name.replace('.', '/')
        kotlin = source.with_suffix('.kt')
        selected.append(kotlin if kotlin.is_file() else source.with_suffix('.java'))
    candidates = sorted(path for path in directory.rglob('*') if path.suffix in ('.java', '.kt'))
    texts = {path: _without_comments(path.read_text(encoding="utf-8"), kotlin=path.suffix == ".kt")
             for path in candidates}
    symbols = {}
    for candidate in candidates:
        exported = {candidate.stem}
        if candidate.suffix == '.kt':
            # Tests may use idiomatic top-level helpers whose name differs from their file.
            # Match unindented public/internal declarations; private or object-member helpers
            # must not pull unrelated checks with common names such as verify/main into a run.
            declarations = re.finditer(
                r'^(?:(?:public|internal|inline|tailrec|suspend|operator|infix|const|lateinit|'
                r'data|sealed|enum|value|open|abstract|actual|expect)\s+)*'
                r'(?:(?:class|object|interface|val|var)\s+([A-Za-z_]\w*)|'
                r'fun\s+(?:<[^>\n]+>\s*)?(?:[\w.*?<>]+\.)?([A-Za-z_]\w*)\s*\()',
                texts[candidate], re.MULTILINE)
            exported.update(match.group(1) or match.group(2) for match in declarations)
        symbols[candidate] = exported
    pending, visited = list(selected), set()
    while pending:
        source = pending.pop()
        if source in visited or not source.is_file():
            continue
        visited.add(source)
        text = texts[source]
        identifiers = set(re.findall(r'\b[A-Za-z_]\w*\b', text))
        for candidate in candidates:
            if candidate in visited or not symbols[candidate].intersection(identifiers):
                continue
            qualified = candidate.relative_to(directory).with_suffix('').as_posix().replace('/', '.')
            package = qualified.rsplit('.', 1)[0]
            if (candidate.parent == source.parent or qualified in text
                    or any(package + '.' + symbol in text for symbol in symbols[candidate])
                    or 'import ' + package + '.*' in text):
                pending.append(candidate)
    # kotlinc uses Java sources for symbol analysis but never emits their classes.
    # Include reachable Java helpers explicitly so a Kotlin-only selection still runs javac.
    helpers = sorted(path for path in visited if path not in selected)
    return selected + helpers

# Canonical generated mod metadata; importing this module never starts a build.
MOD_INFO = {
    'name': 'Toolkit Java Patches (Experimental)',
    'id': 'PZToolkitJavaPatches',
    'version': '0.1.71',
    'author': 'AlexRedby',
    'versionMin': '42.21',
    'versionMax': '42.21',
    'require': '\\ZombieBuddy',
    'javaJarFile': 'media/java/PZToolkitJavaPatches.jar',
    'javaPkgName': 'net.alexredby.pztoolkitjavapatches',
    'ZBVersionMin': '2.3.4',
    'description': 'B42.21 fixes for barricaded-door pathfinding, skipped alarm-clock triggers and duplicate alarm-setting packets, stale optional item-stat fields in reused network packets, item-transaction cancellation ownership and aggregate ordinary container-batch admission, missing-action completion detection, common action completion boundaries and native action outcome acknowledgements, client zombie speed decoding, vehicle interpolation recovery, authoritative cassette restart after stopping, multiplayer build cancellation acknowledgements, stale workstation component references after square object-index changes, live-animal trailer location reconciliation, incomplete equipment acknowledgement handling, late medical updates and requests after patient disconnect, medical visual removal synchronization, null-animal hutch unloading crashes, five native string-property startup exceptions, two malformed native fluid-container names, premature breakable-fence validation, missing level-three wooden-fence material metadata, the native Piano recipe icon, cross-cell basement room lookup loss, the duplicate stock basement-access hall persistent key, the malformed stock mannequin zone, early native font-page loading and occupied-vehicle authority loss after collision handoff. Requires the ZombieBuddy Java agent on clients for zombie, vehicle, animal and equipment patches and on the server for alarm catch-up, cassette playback, safe queue build interruption, workstation reference recovery and vehicle authority recovery. The hutch unloading, native string-property and fluid-name guards apply in clients, single-player and servers. The font startup fix requires explicit early patches_jar activation of the separate local font JAR; enabling the mod alone is insufficient. Includes client cart steering and floor contact for the selected shopping cart and wheelbarrows. Unsupported target bytecode disables the patches.',
}


def main(argv=None):
    parser = argparse.ArgumentParser()
    game_defaults = {
        'darwin': Path.home() / 'Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java',
        'win32': Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Steam/steamapps/common/ProjectZomboid',
        'linux': Path.home() / '.steam/steam/steamapps/common/ProjectZomboid/projectzomboid',
    }
    parser.add_argument('--game', type=Path, default=game_defaults.get(sys.platform), help='Folder containing projectzomboid.jar and ZombieBuddy.jar')
    parser.add_argument('--jdk', type=Path)
    parser.add_argument('--kotlin-home', type=Path, help=f'Kotlin {KOTLIN_VERSION} compiler distribution (or KOTLIN_HOME / kotlinc on PATH)')
    parser.add_argument('--check', action='store_true', help='Run original-engine versus woven-patch regression')
    parser.add_argument('--check-video', action='store_true', help='Run headless video timeline/FFmpeg regression (PZ_TEST_FFMPEG selects executable)')
    parser.add_argument('--test', action='append', choices=TEST_NAMES, default=[], metavar='NAME', help='Run only selected regressions; repeat for multiple. WashWaterRuleChecks and QueueOwnershipChecks require PZ_TEST_WORKSHOP with the Workshop content root. Names: ' + ', '.join(TEST_NAMES))
    parser.add_argument('--test-timeout', type=positive_timeout, default=120, metavar='SECONDS', help='Timeout for each Java regression invocation (default: 120 seconds)')
    args = parser.parse_args(argv)
    if args.test:
        selected = [TEST_NAMES[name] for name in args.test]
    else:
        selected = [name for name in CHECKS if name not in EXPLICIT_ONLY_CHECKS
                    and (args.check_video if name.endswith('.VideoChecks') else args.check)]
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
    test_sources = check_sources(selected) if selected else []
    kotlin_tests = [source for source in test_sources if source.suffix == '.kt']
    kotlin_sources = sorted((ROOT / 'src').rglob('*.kt'))
    java_sources = sorted((ROOT / 'src').rglob('*.java'))
    kotlin_home = kotlin_toolchain(args.kotlin_home, parser) if kotlin_sources or kotlin_tests else None
    fingerprints = source_fingerprints(ROOT)
    build.mkdir(exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='.build-', dir=build))
    previous = temporary / 'previous'
    promoted = False
    try:
        classes = temporary / 'classes'
        classes.mkdir()
        compilepath = classpath
        if kotlin_home is not None:
            stdlib = kotlin_home / 'lib/kotlin-stdlib.jar'
            compile_kotlin(args.jdk, kotlin_home, os.pathsep.join([str(stdlib), classpath]),
                           classes, [*kotlin_sources, *java_sources])
            compilepath = os.pathsep.join([str(classes), str(stdlib), classpath])
        # Match the supported game's Java 25 runtime for both Kotlin and Java output.
        subprocess.run([javac, '--release', JVM_TARGET, '-cp', compilepath, '-d', str(classes), *map(str, java_sources)], check=True)
        if source_fingerprints(ROOT) != fingerprints:
            raise ValueError('Runtime sources or build tools changed during compilation; rebuild the candidate.')
        write_source_manifest(ROOT, classes, fingerprints)
        test_api = temporary / 'test-api'
        if kotlin_tests:
            # Kotlin tests see original module metadata and internals before runtime relocation.
            shutil.copytree(classes, test_api)
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
        runtime_entries = []
        if kotlin_home is not None:
            stage_kotlin_runtime(kotlin_home, classes)
            # PZ itself ships Kotlin 1.4.10. Relocate our stdlib and its references instead of
            # relying on system-classpath ordering or replacing the game's runtime.
            build_tools = temporary / 'build-tools'
            build_tools.mkdir()
            relocator = build_kotlin_relocator(args.jdk, kotlin_home, build_tools)
            subprocess.run([*relocator, str(classes)], check=True)
            runtime_entries = ['-C', str(classes), KOTLIN_RUNTIME_PACKAGE]
        subprocess.run([str(args.jdk/'bin/jar'), '--create', jar_date, '--file', str(jar), '-C', str(classes), 'net/alexredby/pztoolkitjavapatches', *runtime_entries, '-C', str(classes), 'META-INF'], check=True)
        subprocess.run([str(args.jdk/'bin/jar'), '--create', jar_date, '--file', str(fontjar), '--manifest', str(manifest), '-C', str(classes), 'net/alexredby/pztoolkitbootstrap'], check=True)
        (mod/'42/mod.info').write_text(''.join(f'{key}={value}\n' for key, value in MOD_INFO.items()))
        for base in [mod/'common/media', mod/'42/media']:
            for name in ['AnimSets', 'actiongroups']: (base/name).mkdir(parents=True, exist_ok=True)

        if selected:
            testclasses = temporary / 'test-classes'
            testclasses.mkdir(exist_ok=True)
            checks = {name: CHECKS[name] for name in selected}
            if kotlin_tests:
                compile_kotlin(args.jdk, kotlin_home, os.pathsep.join([str(stdlib), str(test_api), classpath]),
                               testclasses, kotlin_tests, module_name=KOTLIN_MODULE + '_tests',
                               options=['-Xfriend-paths=' + str(test_api),
                                        '-Xjava-source-roots=' + str(ROOT / 'tests')])
                # Only Kotlin-produced test classes exist yet. Keep cold Java fixtures' literal
                # runtime probes and initial classpaths untouched when javac compiles them next.
                subprocess.run([*relocator, str(testclasses), '--tests'], check=True)
            java_tests = [source for source in test_sources if source.suffix == '.java']
            if java_tests:
                subprocess.run([javac, '--release', JVM_TARGET, '-cp', os.pathsep.join([str(testclasses), classpath, str(jar), str(fontjar)]), '-sourcepath', str(ROOT / 'tests'), '-d', str(testclasses), *map(str, java_tests)], check=True)
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
                        cold_kotlin = name == 'net.alexredby.javapatchfixture.KotlinRuntimeChecks'
                        testpath = [str(testclasses), classpath] if cold_fonts or cold_kotlin else [str(runtime_classes), str(jar), str(fontjar), classpath]
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


if __name__ == '__main__':
    main()
