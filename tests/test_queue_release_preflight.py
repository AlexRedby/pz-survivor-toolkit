"""Execute the native release preflight's exact logical/framebuffer selection under Lua."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReleaseViewportPreflightTests(unittest.TestCase):
    def preflight(self, *, suite='optimizer-benchmark', flag='false', observed=None, core=(1600, 900), observer=True):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua runtime unavailable')
        values = observed or (1600, 900, 1600, 900, 1600, 900, 1600, 900)
        source = """
local selection={suite=SUITE, options={optimizer_archive='reviewed',optimizer_enabled=FLAG},mods={},window_size={1600,900},mode='native'}
package.preload.QueueTestSelection=function()return selection end
local start,lines
lines={}
Events={OnGameStart={Add=function(callback)start=callback end}}
getCore=function()return {getScreenWidth=function()return WIDTH end,getScreenHeight=function()return HEIGHT end}end
isClient=function()return false end
print=function(value)lines[#lines+1]=value end
OBSERVER
dofile(arg[1])
start()
io.write(table.concat(lines,'\\n'))
"""
        source = source.replace('SUITE', repr(suite)).replace('FLAG', flag)
        source = source.replace('WIDTH', str(core[0])).replace('HEIGHT', str(core[1]))
        source = source.replace('OBSERVER', 'toolkitTestViewport=function()return {' + ','.join(map(str, values)) + '}end' if observer else '')
        with tempfile.TemporaryDirectory(prefix='release-preflight-') as directory:
            script = Path(directory) / 'check.lua'
            script.write_text(source)
            result = subprocess.run([lua, str(script), str(ROOT / 'tests/native_queue/support/ZZReleasePreflight.lua')],
                                    capture_output=True, text=True, timeout=10, check=True)
        return result.stdout

    def test_explicit_native_logical_and_optimized_framebuffer_contracts(self):
        self.assertIn('PREFLIGHT_COMPLETE', self.preflight())
        native_retina = (1600, 900, 3200, 1800, 1600, 900, 1600, 900)
        self.assertIn('PREFLIGHT_COMPLETE', self.preflight(observed=native_retina))
        optimized = (1600, 900, 3200, 1800, 3200, 1800, 3200, 1800)
        self.assertIn('PREFLIGHT_COMPLETE', self.preflight(flag='true', observed=optimized, core=(3200, 1800)))
        self.assertIn('PREFLIGHT_COMPLETE', self.preflight(suite='health', flag='false', observed=optimized, core=(3200, 1800)))

    def test_contract_selection_does_not_admit_invalid_or_unstable_observations(self):
        invalid = [dict(observer=False), dict(observed=(800, 900, 1600, 900, 1600, 900, 1600, 900)),
                   dict(observed=(1600, 900, 0, 900, 1600, 900, 1600, 900)),
                   dict(observed=(1600, 900, 1600, 900, 3200, 1800, 1600, 900)),
                   dict(observed=(1600, 900, 1600, 900, 1600, 900, 3200, 1800)),
                   dict(observed=(1600, 900, 3200, 1800, 1600, 900, 1600, 900), flag='true'),
                   dict(observed=(1600, 900, 3200, 1800, 1600, 900, 1600, 900), flag='nil'),
                   dict(observed=(1600, 900, 3200, 1800, 1600, 900, 1600, 900), flag="'false'"),
                   dict(observed=(1600, 900, 3200, 1800, 1600, 900, 1600, 900), suite='health')]
        for arguments in invalid:
            with self.subTest(arguments=arguments):
                output = self.preflight(**arguments)
                self.assertIn('FAIL release preflight', output)
                self.assertNotIn('PREFLIGHT_COMPLETE', output)


if __name__ == '__main__':
    unittest.main()
