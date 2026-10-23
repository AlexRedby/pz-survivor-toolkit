"""Compile disposable cart fixtures with the project's pinned, private Kotlin runtime."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def patch_build():
    spec = importlib.util.spec_from_file_location('cart_patch_build', ROOT / 'JavaPatches/build.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Configuration:
    @staticmethod
    def error(message):
        raise ValueError(message)


def clean_environment():
    return {key: value for key, value in os.environ.items()
            if key not in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS')}


def run(command):
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True,
                            timeout=120, env=clean_environment())
    if result.returncode:
        raise ValueError(f'Cart JVM compiler failed ({result.returncode}):\n'
                         + result.stdout + result.stderr)


def compile_sources(jdk, classpath, classes, sources, *, kotlin_home=None):
    """Compile mixed fixture sources, then stage and relocate their private Kotlin runtime."""
    build = patch_build()
    jdk, classes = Path(jdk), Path(classes)
    sources = list(map(Path, sources))
    if not sources or any(not path.is_file() or path.suffix not in ('.java', '.kt') for path in sources):
        raise ValueError('Cart compiler requires existing Java/Kotlin sources')
    kotlin = [path for path in sources if path.suffix == '.kt']
    java = [path for path in sources if path.suffix == '.java']
    home = build.kotlin_toolchain(Path(kotlin_home) if kotlin_home else None, Configuration()) if kotlin else None
    classes.mkdir(parents=True)
    compilepath = classpath
    if home:
        stdlib = home / 'lib/kotlin-stdlib.jar'
        compilepath = os.pathsep.join([str(classes), str(stdlib), classpath])
        command = [jdk/'bin/java', '-jar', home/'lib/kotlin-compiler.jar', '-kotlin-home', home,
                   '-jvm-target', build.JVM_TARGET, '-module-name', 'cart_lab', '-no-stdlib', '-no-reflect',
                   '-classpath', compilepath, '-d', classes]
        run([*command, *sources])
    if java:
        run([jdk/'bin/javac', '--release', build.JVM_TARGET, '-cp', compilepath, '-d', classes, *java])
    if not list(classes.rglob('*.class')):
        raise ValueError('Cart compiler produced no classes')
    if home:
        build.stage_kotlin_runtime(home, classes)
        with tempfile.TemporaryDirectory(prefix='cart-kotlin-relocate-') as directory:
            compiler = home/'lib/kotlin-compiler.jar'
            run([jdk/'bin/javac', '--release', build.JVM_TARGET, '-cp', compiler, '-d', directory,
                 ROOT/'JavaPatches/tools/RelocateKotlin.java'])
            run([jdk/'bin/java', '-cp', os.pathsep.join([directory, str(compiler)]),
                 'RelocateKotlin', classes, '--tests'])
