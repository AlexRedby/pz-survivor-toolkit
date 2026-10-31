"""Optional actual-game-Kahlua clock check, without launching the game."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class BookControlsClockTests(unittest.TestCase):
    def test_actual_kahlua_monotonic_clock(self):
        game = os.environ.get('PZ_GAME_JAVA_DIR')
        jdk = os.environ.get('PZ_JDK_HOME')
        if not game or not jdk:
            self.skipTest('Set PZ_GAME_JAVA_DIR and PZ_JDK_HOME for the optional stock Kahlua check')
        suffix = '.exe' if os.name == 'nt' else ''
        java, javac = (Path(jdk) / 'bin' / (name + suffix) for name in ('java', 'javac'))
        jars = [Path(game) / name for name in ('projectzomboid.jar', 'ZombieBuddy.jar')]
        if any(not path.is_file() for path in (java, javac, *jars)):
            self.skipTest('Optional game JARs, ZombieBuddy or JDK binaries are absent')
        sources = ROOT / 'tests/native_queue/book-controls/java'
        classpath = os.pathsep.join(map(str, jars))
        with tempfile.TemporaryDirectory(prefix='book-controls-clock-') as directory:
            subprocess.run([str(javac), '--release', '25', '-cp', classpath, '-d', directory,
                            str(sources / 'Main.java'), str(sources / 'MonotonicClockChecks.java')],
                           check=True, capture_output=True, text=True, timeout=60)
            result = subprocess.run([str(java), '-cp', os.pathsep.join((directory, classpath)),
                                     'net.alexredby.bookcontrolsprobe.MonotonicClockChecks'],
                                    check=True, capture_output=True, text=True, timeout=30)
        self.assertIn('BOOK_CONTROLS_MONOTONIC_CLOCK_PASS', result.stdout)


if __name__ == '__main__':
    unittest.main()
