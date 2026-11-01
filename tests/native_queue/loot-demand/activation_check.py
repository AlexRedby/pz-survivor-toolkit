#!/usr/bin/env python3
"""Verify the research candidate in fresh headless JVMs with real Instrumentation.

Uses actual external game classes without initializing them or invoking gameplay.
Output must be a new directory. No installed files or profiles are changed.
"""
import argparse
import hashlib
import json
import os
import secrets
import shutil
from pathlib import Path
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parents[3]
BASE = Path(__file__).resolve().parent
AGENT = r'''
package toolkit.lootactivation;
import java.lang.instrument.*;
import java.lang.reflect.*;
import java.security.ProtectionDomain;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
public final class ActivationAgent {
    public static Instrumentation instrumentation;
    public static final Map<String,String> firstObservation=new ConcurrentHashMap<>();
    @SuppressWarnings("unchecked")
    public static void registerJar(String path)throws Exception {
        Class<?> loader=Class.forName("me.zed_0xff.zombie_buddy.Loader");
        Field field=loader.getDeclaredField("g_known_jars");field.setAccessible(true);
        ((Set<java.nio.file.Path>)field.get(null)).add(java.nio.file.Path.of(path).toRealPath());
    }
    public static void premain(String arguments,Instrumentation supplied)throws Exception {
        instrumentation=supplied;
        supplied.addTransformer(new ClassFileTransformer(){
            public byte[] transform(ClassLoader loader,String name,Class<?> type,ProtectionDomain domain,byte[] bytes){
                if(name!=null && (name.equals("zombie/inventory/ItemPickerJava")
                    ||name.equals("zombie/inventory/ItemContainer")
                    ||name.equals("zombie/LoadGridsquarePerformanceWorkaround$ItemPicker")
                    ||name.equals("zombie/Lua/Event")))
                    firstObservation.putIfAbsent(name,type==null?"initial-definition":"retransformation");
                return null;
            }
        },true);
        // This is the same global read by the actual Buddy PatchEngine.
        Class<?> loader=Class.forName("me.zed_0xff.zombie_buddy.Loader");
        Field field=loader.getDeclaredField("g_instrumentation");field.setAccessible(true);field.set(null,supplied);
    }
}
'''
PROBE = r'''
package toolkit.lootactivation;
import java.lang.instrument.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import net.bytebuddy.jar.asm.*;
import net.alexredby.lootdemand.DemandTransform;
import net.alexredby.lootdemand.LootDemand;
public final class ActivationProbe {
    static final String BRIDGE="net/alexredby/lootdemand/LootDemand";
    static void require(boolean value,String message){if(!value)throw new AssertionError(message);}
    static String sha(byte[] bytes)throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }
    public static void main(String[]args)throws Exception {
        require(args.length==2 && Set.of("first-load","already-loaded").contains(args[0]),"activation mode");
        ActivationAgent.registerJar(args[1]);
        Instrumentation inst=ActivationAgent.instrumentation;
        require(inst!=null && inst.isRetransformClassesSupported(),"real retransformation unavailable");
        ClassLoader loader=ActivationProbe.class.getClassLoader();
        Set<String> targets=new TreeSet<>(DemandTransform.TARGETS);targets.add("zombie/Lua/Event");
        if(args[0].equals("already-loaded"))for(String name:targets)Class.forName(name.replace('/','.'),false,loader);
        Set<String> before=new TreeSet<>();
        for(Class<?> type:inst.getAllLoadedClasses())if(targets.contains(type.getName().replace('.','/')))before.add(type.getName().replace('.','/'));
        if(args[0].equals("already-loaded"))require(before.equals(targets),"explicit preload incomplete");
        System.setProperty("pz.lootDemand.enabled","true");
        require(LootDemand.install(inst),"install refused: "+LootDemand.diagnostic());
        require(LootDemand.installed(),"not active after install");
        Map<String,Map<String,Set<String>>> observed=new ConcurrentHashMap<>();
        Map<String,String> hashes=new ConcurrentHashMap<>();
        ClassFileTransformer observer=new ClassFileTransformer(){
            public byte[] transform(ClassLoader owner,String name,Class<?> type,ProtectionDomain domain,byte[] bytes){
                if(owner!=loader || !targets.contains(name))return null;
                Map<String,Set<String>> methods=new TreeMap<>();
                new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9){
                    public MethodVisitor visitMethod(int access,String method,String desc,String sig,String[]exceptions){
                        return new MethodVisitor(Opcodes.ASM9){
                            public void visitMethodInsn(int op,String receiver,String invoked,String descriptor,boolean itf){
                                if(receiver.equals(BRIDGE))methods.computeIfAbsent(method+desc,k->new TreeSet<>()).add(invoked);
                            }
                        };
                    }
                },ClassReader.SKIP_DEBUG|ClassReader.SKIP_FRAMES);
                observed.put(name,methods);
                try{hashes.put(name,sha(bytes));}catch(Exception failure){throw new AssertionError(failure);}
                return null;
            }
        };
        inst.addTransformer(observer,true);
        try {
            for(String name:targets){
                Class<?> type=Class.forName(name.replace('/','.'),false,loader);
                require(type.getClassLoader()==loader,"foreign classloader: "+name);
                require(inst.isModifiableClass(type),"unmodifiable target: "+name);
                inst.retransformClasses(type);
                // Link and verify method signatures; do not initialize or call native game methods.
                type.getDeclaredMethods();type.getDeclaredConstructors();
            }
        }finally{inst.removeTransformer(observer);}
        require(LootDemand.installed(),"later weaving failed: "+LootDemand.diagnostic());
        require(observed.keySet().equals(targets),"missing transformed target receipt");
        Map<String,Set<String>> expected=Map.of(
            "zombie/inventory/ItemPickerJava",Set.of("enterFill","exitFill","shouldDefer"),
            "zombie/LoadGridsquarePerformanceWorkaround$ItemPicker",Set.of("shouldDefer"),
            "zombie/inventory/ItemContainer",Set.of("beforeDump"),
            "zombie/Lua/Event",Set.of("beforeEvent"));
        for(String name:targets){
            Set<String> calls=new TreeSet<>();for(Set<String> methodCalls:observed.get(name).values())calls.addAll(methodCalls);
            require(calls.containsAll(expected.get(name)),"missing actual woven bridge calls: "+name+" "+calls);
            System.out.println("TARGET "+name+" initiallyLoaded="+before.contains(name)
                +" firstObservation="+ActivationAgent.firstObservation.get(name)+" sha256="+hashes.get(name)+" hooks="+calls);
        }
        long[] counts=LootDemand.counts();for(long value:counts)require(value==0,"gameplay/callback counter unexpectedly changed");
        LootDemand.remove();require(!LootDemand.installed(),"policy stayed active after remove");
        System.out.println("ACTIVATION_PASS mode="+args[0]+" targets="+targets.size()+" verified=true gameplay=false");
    }
}
'''


DIRECT_MAIN = r'''
package toolkit.lootactivation;
/** Deliberately no DemandTransform/LootDemand reference before the real Main. */
public final class DirectMainProbe {
    public static void main(String[]args)throws Exception {
        if(args.length!=2)throw new IllegalArgumentException("owned cache and dynamically appended JAR required");
        ClassLoader loader=DirectMainProbe.class.getClassLoader();
        try {
            Class.forName("toolkit.lootdemandruntime.Main",false,loader);
            throw new AssertionError("fixture was incorrectly present on startup classpath");
        }catch(ClassNotFoundException expected){}
        zombie.ZomboidFileSystem.instance.setCacheDir(args[0]);
        // Keep the JarFile open exactly as Buddy's dynamic installation does.
        var jar=new java.util.jar.JarFile(args[1]);
        ActivationAgent.instrumentation.appendToSystemClassLoaderSearch(jar);
        ActivationAgent.registerJar(args[1]);
        var packages=loader.getResources("net/alexredby/lootdemand");int packageCount=0;
        while(packages.hasMoreElements()){packages.nextElement();packageCount++;}
        System.out.println("DYNAMIC_PACKAGE_RESOURCES count="+packageCount);
        Class<?> main=Class.forName("toolkit.lootdemandruntime.Main",true,loader);
        main.getMethod("main",String[].class).invoke(null,(Object)new String[0]);
        if(!Boolean.TRUE.equals(main.getMethod("installed").invoke(null)))throw new AssertionError("actual Main not active");
        System.out.println("DIRECT_MAIN_PASS entry=actual-fixture-Main dynamicAppend=true gameplay=false");
    }
}
'''


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(game, jdk, output, rejected_artifact=None, rejected_packaging_artifact=None):
    game, jdk, output = map(lambda value: Path(value).resolve(), (game, jdk, output))
    if output.exists():
        raise ValueError('Activation output must be a new directory')
    jars = [game / 'projectzomboid.jar', game / 'ZombieBuddy.jar']
    java, javac = jdk / 'bin/java', jdk / 'bin/javac'
    inputs = [*jars, java, javac]
    if any(not path.is_file() for path in inputs):
        raise ValueError('Supply actual game Java directory and JDK with java/javac')
    candidate = sorted((BASE / 'java').glob('*.java')) + sorted((BASE / 'runtime').glob('*.java'))
    if not candidate:
        raise ValueError('Candidate Java sources missing')
    output.mkdir(parents=True)
    generated, classes = output / 'source', output / 'classes'
    generated.mkdir(); classes.mkdir()
    for name, source in [('ActivationAgent.java', AGENT), ('ActivationProbe.java', PROBE),
                         ('DirectMainProbe.java', DIRECT_MAIN)]:
        (generated / name).write_text(source)
    env = {key: value for key, value in os.environ.items()
           if key not in ('JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS', 'JDK_JAVA_OPTIONS', 'CLASSPATH')}
    (output / 'home').mkdir()
    receipt = dict(format=1, scope='real Instrumentation and JVM class verification only; no gameplay or world/GUI initialization',
        sources={str(path.relative_to(ROOT)): digest(path) for path in [Path(__file__).resolve(), *candidate]},
        external_inputs={path.name: digest(path) for path in inputs}, runs=[])

    def command(name, arguments, expected_failure=False):
        result = subprocess.run(list(map(str, arguments)), cwd=output, env=env,
            capture_output=True, text=True, timeout=90)
        (output / (name + '.stdout.log')).write_text(result.stdout)
        (output / (name + '.stderr.log')).write_text(result.stderr)
        receipt['runs'].append(dict(name=name, command=list(map(str, arguments)), exit_code=result.returncode,
            expected_failure=expected_failure))
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        if not expected_failure:
            result.check_returncode()
        return result

    classpath = os.pathsep.join(map(str, jars))
    command('compile', [javac, '--release', '25', '-cp', classpath, '-d', classes,
        *candidate, *sorted(generated.glob('*.java'))])
    agent = output / 'activation-agent.jar'
    with zipfile.ZipFile(agent, 'x', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('META-INF/MANIFEST.MF', 'Manifest-Version: 1.0\nPremain-Class: toolkit.lootactivation.ActivationAgent\n'
            'Can-Retransform-Classes: true\nCan-Redefine-Classes: true\n\n')
        for path in sorted((classes / 'toolkit/lootactivation').glob('ActivationAgent*.class')):
            archive.write(path, path.relative_to(classes).as_posix())
    # The real entry test MUST NOT have compiled candidate classes ahead of its
    # fixture JAR. Otherwise the old-artifact regression would accidentally load
    # freshly compiled helpers and hide the first-load failure again.
    probes = output / 'probe-classes'
    shutil.copytree(classes / 'toolkit/lootactivation', probes / 'toolkit/lootactivation')
    fixture = output / 'PZLootDemandExperiment.jar'
    token = secrets.token_hex(16)
    with zipfile.ZipFile(fixture, 'x', zipfile.ZIP_DEFLATED) as archive:
        packaged = [path for path in sorted(classes.rglob('*.class'))
                    if not path.is_relative_to(classes / 'toolkit/lootactivation')]
        for path in packaged:
            archive.write(path, path.relative_to(classes).as_posix())
        archive.writestr('loot-demand-token.txt', token)
    receipt['packaged_fixture_sha256'] = digest(fixture)

    def direct_main(name, artifact, expected_failure=False):
        artifact = Path(artifact).resolve()
        with zipfile.ZipFile(artifact) as archive:
            authorization = archive.read('loot-demand-token.txt').decode('ascii').strip()
        if len(authorization) != 32 or any(char not in '0123456789abcdef' for char in authorization):
            raise ValueError('Invalid explicit fixture artifact token')
        cache = output / (name + '-cache')
        (cache / 'Lua').mkdir(parents=True)
        (cache / 'Lua/smoke-user.txt').write_text('client1\n')
        (cache / 'loot-demand.opt-in').write_text(authorization + '\n')
        cp = os.pathsep.join(map(str, [probes, *jars]))
        return command(name, [java, '-Xverify:all', '-Xms128m', '-Xmx256m', '-Djava.awt.headless=true',
            '-Duser.home=' + str(output / 'home'), '-javaagent:' + str(agent), '-cp', cp,
            'toolkit.lootactivation.DirectMainProbe', cache, artifact], expected_failure=expected_failure)

    if rejected_artifact is not None:
        rejected_artifact = Path(rejected_artifact).resolve()
        receipt['rejected_artifact'] = dict(path=str(rejected_artifact), sha256=digest(rejected_artifact))
        old = direct_main('rejected-direct-main', rejected_artifact, expected_failure=True)
        old_text = old.stdout + old.stderr
        if old.returncode == 0 or not all(marker in old_text for marker in
                ('LinkageError', 'duplicate class definition', 'DemandTransform')):
            raise ValueError('Old artifact did not reproduce the specific first-load recursive-transformer failure')
        receipt['rejected_artifact']['confirmed_failure'] = 'LinkageError duplicate DemandTransform definition'
    if rejected_packaging_artifact is not None:
        old_jar = Path(rejected_packaging_artifact).resolve()
        receipt['rejected_packaging_artifact'] = dict(path=str(old_jar), sha256=digest(old_jar))
        old = direct_main('rejected-packaging-direct-main', old_jar, expected_failure=True)
        old_text = old.stdout + old.stderr
        if old.returncode == 0 or not all(marker in old_text for marker in
                ('Scanned 0 classes in package net.alexredby.lootdemand',
                 'Event prefix was not woven before listeners', 'DYNAMIC_PACKAGE_RESOURCES count=0')):
            raise ValueError('Old packaging did not reproduce exact dynamic class-scan/Event-prefix failure')
        repaired = output / 'directory-only-repaired-artifact.jar'
        with zipfile.ZipFile(old_jar) as source, zipfile.ZipFile(repaired, 'x', zipfile.ZIP_DEFLATED) as target:
            entries = {info.filename: source.read(info) for info in source.infolist()}
            directories = set()
            for name in entries:
                parts = name.split('/')
                for index in range(1, len(parts)):
                    directories.add('/'.join(parts[:index]) + '/')
            for name in sorted(directories - entries.keys()):
                target.writestr(name, b'')
            for info in source.infolist():
                target.writestr(info, entries[info.filename])
        with zipfile.ZipFile(repaired) as archive:
            if any(archive.read(name) != data for name, data in entries.items()):
                raise AssertionError('Directory repair changed existing artifact data')
        fixed = direct_main('directory-only-repaired-direct-main', repaired, expected_failure=True)
        fixed_text = fixed.stdout + fixed.stderr
        if fixed.returncode == 0 or not all(marker in fixed_text for marker in
                ('DYNAMIC_PACKAGE_RESOURCES count=1', 'Scanned 0 classes in package net.alexredby.lootdemand',
                 'Event prefix was not woven before listeners')):
            raise ValueError('Directory-only repair did not reproduce the expected remaining scanner failure')
        receipt['rejected_packaging_artifact'].update(
            confirmed_failure='dynamic package discovery empty; Event prefix unpatched',
            directory_only_repair_passed=False, existing_entry_bytes_unchanged=True,
            diagnosis="nonnull ClassGraph overrideClassLoaders misses appended JAR despite directory resource; use Buddy known_jars scanner path",
            repaired_sha256=digest(repaired))
    direct = direct_main('direct-main', fixture)
    if direct.stdout.count('DIRECT_MAIN_PASS entry=actual-fixture-Main dynamicAppend=true gameplay=false') != 1:
        raise ValueError('Actual fixture Main did not complete')
    classpath = os.pathsep.join(map(str, [classes, *jars]))
    for mode in ('first-load', 'already-loaded'):
        result = command(mode, [java, '-Xverify:all', '-Xms128m', '-Xmx256m', '-Djava.awt.headless=true',
            '-Duser.home=' + str(output / 'home'), '-javaagent:' + str(agent), '-cp', classpath,
            'toolkit.lootactivation.ActivationProbe', mode, fixture])
        if result.stdout.count('ACTIVATION_PASS mode=' + mode + ' targets=4 verified=true gameplay=false') != 1:
            raise ValueError('Missing exact activation completion marker: ' + mode)
    current = {str(path.relative_to(ROOT)): digest(path) for path in [Path(__file__).resolve(), *candidate]}
    if receipt['sources'] != current:
        raise ValueError('Candidate sources changed during activation checks; rerun after source freeze')
    receipt['status'] = 'passed'
    receipt['limits'] = ['Direct Main initializes only ZomboidFileSystem to select an owned empty cache; no gameplay/world/GUI or Lua callback is invoked.',
        'Metadata-only first-load mode initializes DemandTransform before installation; dynamically appended direct-main is the actual unprimed packaging/entry regression gate.',
        'First-load mode does not explicitly preload targets; individual initiallyLoaded records expose incidental JVM dependency loading.',
        'Checks native classes, not the optional full selected Toolkit/Fence advice or official overlay composition.']
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', required=True, type=Path)
    parser.add_argument('--jdk', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--rejected-packaging-artifact', type=Path,
        help='Optional old JAR: verify dynamic scanner failure and that ZIP directories alone are insufficient')
    parser.add_argument('--rejected-artifact', type=Path,
        help='Optional old fixture JAR which must reproduce duplicate DemandTransform LinkageError')
    args = parser.parse_args()
    result = run(args.game, args.jdk, args.output, args.rejected_artifact, args.rejected_packaging_artifact)
    print(json.dumps(dict(status=result['status'], output=str(args.output.resolve()),
        checks=[row['name'] for row in result['runs']], limits=result['limits']), indent=2))


if __name__ == '__main__':
    main()
