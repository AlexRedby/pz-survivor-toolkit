"""Execute the real inlined CartLab UI advice across a foreign class boundary, offline."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from cart_jvm import compile_sources, clean_environment
GAME=Path(os.environ.get('PZ_GAME',str(Path.home()/'Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java')))
PATCH=Path(os.environ.get('PZ_PATCH_JAR',str(ROOT/'JavaPatches/build/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar')))


def java_home():
    if os.environ.get('JAVA_HOME'): return Path(os.environ['JAVA_HOME'])
    if Path('/usr/libexec/java_home').is_file():
        result=subprocess.run(['/usr/libexec/java_home','-v','25'],text=True,capture_output=True)
        if result.returncode==0: return Path(result.stdout.strip())
    compiler=shutil.which('javac')
    return Path(compiler).resolve().parents[1] if compiler else None


JDK=java_home()


@unittest.skipUnless(JDK and PATCH.is_file() and all((GAME/name).is_file() for name in ('projectzomboid.jar','ZombieBuddy.jar')),
                     'Requires JDK25+, game/ZombieBuddy jars (PZ_GAME) and current patch jar (PZ_PATCH_JAR)')
class CaptureUIAdviceChecks(unittest.TestCase):
    def test_actual_advice_executes_in_foreign_renderer_and_restores_native_scope(self):
        suffix='.exe' if os.name=='nt' else ''
        jars=[GAME/'projectzomboid.jar',GAME/'ZombieBuddy.jar',PATCH]
        with tempfile.TemporaryDirectory(prefix='cart-ui-advice-') as temporary:
            output=Path(temporary)
            classes=output/'classes'
            try:
                compile_sources(JDK,os.pathsep.join(map(str,jars)),classes,
                    [ROOT/'tests/native_queue/contributions/wooden_cart_motion/Main.kt',
                     ROOT/'tests/native_queue/contributions/wooden_cart_motion/MainAdvice.java',
                     ROOT/'tests/java/CartCaptureUIAdviceChecks.java'])
            except subprocess.CalledProcessError as error:
                self.fail((error.stdout or '')+(error.stderr or ''))
            self.assertTrue((classes/'net/alexredby/pztoolkitruntime/kotlin/jvm/internal/Intrinsics.class').is_file())
            self.assertFalse((classes/'kotlin').exists())
            agent=output/'offline-check-agent.jar'
            with zipfile.ZipFile(agent,'w') as jar:
                jar.writestr('META-INF/MANIFEST.MF','Manifest-Version: 1.0\nPremain-Class: net.alexredby.cartlabchecks.CartCaptureUIAdviceChecks\nCan-Redefine-Classes: true\n\n')
                jar.write(classes/'net/alexredby/cartlabchecks/CartCaptureUIAdviceChecks.class','net/alexredby/cartlabchecks/CartCaptureUIAdviceChecks.class')
            result=subprocess.run([str(JDK/'bin'/('java'+suffix)),'-javaagent:'+str(agent),
                '-Djava.awt.headless=true','-cp',os.pathsep.join([str(classes),*map(str,jars)]),
                'net.alexredby.cartlabchecks.CartCaptureUIAdviceChecks'],cwd=GAME,text=True,capture_output=True,
                env=dict(clean_environment(),PZ_CART_TEST_PAD='false',PZ_CART_RUNTIME_FILE=str(output/'runtime.lua'),
                         PZ_CART_COMMAND_FILE=str(output/'commands.txt')),timeout=30)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn('CART_CAPTURE_UI_ADVICE_PASS',result.stdout)


if __name__=='__main__': unittest.main()
