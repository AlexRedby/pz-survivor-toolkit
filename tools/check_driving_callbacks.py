#!/usr/bin/env python3
"""Reproduce bounded Lua callback checks without launching or installing the game.

All generated classes, agent configuration, recordings and logs remain in a new
--output directory. The production patch jar must match current project sources.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'net.alexredby.drivingperf.'
ADVICE = 'net/alexredby/pztoolkitjavapatches/Main$ActionCallbackResult.class'
BAD_OUTPUT = ('Error during transformation', '[Byte Buddy] ERROR', 'Failed to transform')

# Copy the exact compiled advice. No test creates a completion scope, so its real
# ActionCompletion observer would be inactive; isolate that observer to avoid
# loading unrelated production patches and their runtime dependencies.
OBSERVER_SOURCE = '''package net.alexredby.pztoolkitjavapatches;
public final class ActionCompletion {
    public static void observe(Object callback,Object argument,Object[] result) {}
}
'''
OVERLAY_SOURCE = '''package toolkit.luahookfixture;
import java.lang.instrument.*;
import java.nio.file.*;
import java.security.*;
import me.zed_0xff.zombie_buddy.*;
public final class CompletionFixture {
    public static void main(String[] args) throws Exception {
        var field=Loader.class.getDeclaredField("g_instrumentation");field.setAccessible(true);
        Instrumentation inst=(Instrumentation)field.get(null);
        if(inst==null)throw new IllegalStateException("ZombieBuddy javaagent required");
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches",CompletionFixture.class.getClassLoader());
        if(args[0].equals("capture")) {
            net.alexredby.drivingperf.LuaCallbackCaptureChecks.main(new String[]{args[1]});
            return;
        }
        ClassFileTransformer observer=new ClassFileTransformer() {
            public byte[] transform(ClassLoader l,String n,Class<?> c,ProtectionDomain d,byte[] b) {
                if(n.equals("se/krka/kahlua/integration/LuaCaller")) {
                    try {Files.write(Path.of(args[1]),b);}
                    catch(Exception failure){throw new RuntimeException(failure);}
                }
                return null;
            }
        };
        inst.addTransformer(observer,true);
        try {
            Class<?> caller=Class.forName("se.krka.kahlua.integration.LuaCaller",false,CompletionFixture.class.getClassLoader());
            inst.retransformClasses(caller);
            if(!Files.isRegularFile(Path.of(args[1])))throw new IllegalStateException("No transformed input captured");
        } finally {inst.removeTransformer(observer);}
        System.out.println("LUA_CALLBACK_COMPLETION_OVERLAY_CAPTURE_PASS");
    }
}
'''


def load_build():
    spec = importlib.util.spec_from_file_location('driving_callback_patch_build', ROOT / 'JavaPatches/build.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('game', 'jdk', 'patch-jar', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args(argv)
    game, jdk, patch_jar = (getattr(args, name).expanduser().resolve()
                            for name in ('game', 'jdk', 'patch_jar'))
    requested_output = args.output.expanduser()
    if os.path.lexists(requested_output):
        parser.error('--output must be a new directory')
    output = requested_output.resolve()
    if output == game or game in output.parents:
        parser.error('--output cannot be inside the game installation')
    output.mkdir(parents=True)
    logs = output / 'logs'
    logs.mkdir()
    state = {'status': 'incomplete', 'checks': [], 'game_launched': False,
             'completion_overlay': 'actual-compiled-advice-with-isolated-inactive-observer'}

    def save():
        (output / 'result.json').write_text(json.dumps(state, indent=2, sort_keys=True) + '\n', encoding='utf-8')

    def run(label, command, marker=None):
        log = logs / (label + '.log')
        (logs / (label + '.command.json')).write_text(json.dumps(list(map(str, command)), indent=2) + '\n', encoding='utf-8')
        try:
            with log.open('w', encoding='utf-8') as target:
                completed = subprocess.run(list(map(str, command)), cwd=output, stdout=target,
                                           stderr=subprocess.STDOUT, timeout=90, check=False)
        except subprocess.TimeoutExpired as failure:
            raise RuntimeError('Timed out: ' + label + '; see ' + log.name) from failure
        text = log.read_text(encoding='utf-8', errors='replace')
        if completed.returncode or any(bad in text for bad in BAD_OUTPUT) or marker and marker not in text:
            raise RuntimeError('Failed: ' + label + '; see ' + log.name)
        state['checks'].append(label)
        save()
        print(label + ': PASS', flush=True)

    try:
        save()
        build = load_build()
        build.require_current_patch_jar(patch_jar, ROOT / 'JavaPatches')
        game_jar, buddy, stdlib = game / 'projectzomboid.jar', game / 'ZombieBuddy.jar', game / 'stdlib.lua'
        java, javac = jdk / 'bin/java', jdk / 'bin/javac'
        for path in (game_jar, buddy, stdlib, java, javac):
            if not path.is_file():
                raise ValueError('Required input missing: ' + str(path))
        source = ROOT / 'tests/native_queue/optimizer-benchmark'
        runtime_sources = sorted((source / 'java').glob('*.java'))
        check_sources = [source / 'checks' / (name + '.java') for name in
                         ('LuaCallbackHookChecks', 'LuaCallbacksChecks', 'LuaCallbackCaptureChecks', 'LuaCallbackDetailsChecks')]
        fingerprints = {path.relative_to(ROOT).as_posix(): digest(path)
                        for path in [*runtime_sources, *check_sources, source / 'CallbackDetails.lua', Path(__file__).resolve(),
                                     ROOT / 'tools/queue_checks/callback_metrics.py',
                                     ROOT / 'tools/queue_checks/adapters/optimizer_benchmark.py']}
        with ZipFile(game_jar) as archive:
            native = {name: hashlib.sha256(archive.read(name)).hexdigest() for name in
                      ('se/krka/kahlua/integration/LuaCaller.class',
                       'se/krka/kahlua/vm/KahluaThread.class',
                       'zombie/iso/fboRenderChunk/FBORenderCell.class')}
        with ZipFile(patch_jar) as archive:
            advice = archive.read(ADVICE)
        (output / 'inputs.json').write_text(json.dumps({
            'format': 1, 'sources': fingerprints, 'native_resources': native,
            'patch_jar_sha256': digest(patch_jar), 'buddy_sha256': digest(buddy),
            'completion_advice_sha256': hashlib.sha256(advice).hexdigest(),
            'stdlib_lua_sha256': digest(stdlib),
            'patch_source_manifest_verified': True}, indent=2, sort_keys=True) + '\n', encoding='utf-8')
        shutil.copy2(stdlib, output / 'stdlib.lua')
        run('java-version', [java, '-version'])
        classes, checks, fixture = (output / name for name in ('runtime-classes', 'check-classes', 'completion-fixture'))
        for directory in (classes, checks, fixture):
            directory.mkdir()
        native_cp = os.pathsep.join(map(str, (game_jar, buddy)))
        run('compile-runtime', [javac, '--release', '25', '-cp', native_cp, '-d', classes, *runtime_sources])
        run('compile-checks', [javac, '--release', '25', '-cp', str(classes) + os.pathsep + native_cp,
                               '-d', checks, *check_sources])
        extracted = fixture / ADVICE
        extracted.parent.mkdir(parents=True)
        extracted.write_bytes(advice)
        generated = output / 'fixture-sources'
        generated.mkdir()
        observer_source, overlay_source = generated / 'ActionCompletion.java', generated / 'CompletionFixture.java'
        observer_source.write_text(OBSERVER_SOURCE, encoding='utf-8')
        overlay_source.write_text(OVERLAY_SOURCE, encoding='utf-8')
        base_cp = os.pathsep.join(map(str, (checks, classes, game_jar, buddy)))
        overlay_cp = str(fixture) + os.pathsep + base_cp
        run('compile-completion-fixture', [javac, '--release', '25', '-cp', base_cp,
                                           '-d', fixture, observer_source, overlay_source])

        def command(label, main_class, arguments=(), agent=False, overlay=False):
            result = [java]
            if agent:
                result.append('-javaagent:' + str(buddy) + '=config_dir=' + str(output / ('agent-' + label))
                              + ',policy=deny-new,verbosity=0')
            result += ['-Djava.awt.headless=true', '-Duser.home=' + str(output / ('home-' + label)),
                       '-Dzomboid.steam=0', '-cp', overlay_cp if overlay else base_cp, main_class, *arguments]
            return result

        run('interval-accounting', command('interval', PACKAGE + 'LuaCallbacksChecks'), 'LUA_CALLBACK_INTERVAL_CHECKS_PASS')
        run('hook-native', command('hook-native', PACKAGE + 'LuaCallbackHookChecks'), 'LUA_CALLBACK_HOOK_CHECKS_PASS')
        overlay_bytes = output / 'actual-completion-LuaCaller.class'
        run('capture-completion-overlay', command('capture-overlay', 'toolkit.luahookfixture.CompletionFixture',
                                                  ['snapshot', overlay_bytes], agent=True, overlay=True),
            'LUA_CALLBACK_COMPLETION_OVERLAY_CAPTURE_PASS')
        run('hook-completion', command('hook-completion', PACKAGE + 'LuaCallbackHookChecks', [overlay_bytes], overlay=True),
            'LUA_CALLBACK_HOOK_CHECKS_PASS')
        for label, arguments, overlay in (
                ('install-native', ['--install'], False),
                ('install-completion', ['--install', '--completion'], True),
                ('install-incompatible', ['--install', '--incompatible'], False)):
            run(label, command(label, PACKAGE + 'LuaCallbackHookChecks', arguments, agent=True, overlay=overlay),
                'LUA_CALLBACK_HOOK_INSTALL_REJECTION_PASS' if label.endswith('incompatible') else 'LUA_CALLBACK_HOOK_INSTALL_PASS')
        run('detail-helper-semantics', command('detail-helper', PACKAGE + 'LuaCallbackDetailsChecks',
                                               [source / 'CallbackDetails.lua', output / 'detail-helper-capture'], agent=True),
            'LUA_CALLBACK_DETAILS_CHECKS_PASS')
        captures = []
        for label, overlay in (('capture-native', False), ('capture-completion', True)):
            cache = output / label
            main_class = 'toolkit.luahookfixture.CompletionFixture' if overlay else PACKAGE + 'LuaCallbackCaptureChecks'
            arguments = ['capture', cache] if overlay else [cache]
            run(label, command(label, main_class, arguments, agent=True, overlay=overlay), 'LUA_CALLBACK_CAPTURE_CHECKS_PASS')
            captures.append(cache)
        sys.path.insert(0, str(ROOT / 'tools'))
        from queue_checks.callback_metrics import callback_metrics
        evidence = {cache.name: callback_metrics(cache) for cache in captures}
        (output / 'artifact-evidence.json').write_text(json.dumps(evidence, indent=2, sort_keys=True) + '\n', encoding='utf-8')
        state['checks'].append('joined-artifact-validator-native-and-completion')
        state['status'] = 'complete'
        save()
        print('DRIVING_CALLBACK_CHECKS_PASS output=' + str(output))
        return 0
    except Exception as failure:
        state['error'] = str(failure)
        save()
        print('DRIVING_CALLBACK_CHECKS_FAILED ' + str(failure), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
