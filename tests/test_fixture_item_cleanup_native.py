"""Opt-in execution of the common cleanup module in installed native Kahlua.

PZ_GAME=/path/to/game/Java PZ_JDK=/path/to/jdk python3 -m unittest \
    tests.test_fixture_item_cleanup_native

Compiles a temporary harness only; no game launch, installation or API patch.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import org.luaj.kahluafork.compiler.FuncState;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.*;

public final class FixtureItemCleanupChecks {
    static LuaClosure compile(String source, String name, KahluaTable env) throws Exception {
        String previous=FuncState.currentFile, previousFull=FuncState.currentfullFile;
        try {
            FuncState.currentFile=name;FuncState.currentfullFile=name;
            return LuaCompiler.loadstring(source,name,env);
        } finally { FuncState.currentFile=previous;FuncState.currentfullFile=previousFull; }
    }
    public static void main(String[] args) throws Exception {
        var platform=J2SEPlatform.getInstance();
        // Native newEnvironment expects a source stdlib.lua in cwd, whereas
        // installed distributions supply stdlib.lbc. Register the same core
        // libraries and execute that installation's actual standard library.
        var env=platform.newTable();env.rawset("_G",env);
        se.krka.kahlua.stdlib.BaseLib.register(env);
        se.krka.kahlua.j2se.MathLib.register(platform,env);
        se.krka.kahlua.stdlib.RandomLib.register(platform,env);
        se.krka.kahlua.stdlib.StringLib.register(platform,env);
        se.krka.kahlua.stdlib.CoroutineLib.register(platform,env);
        se.krka.kahlua.stdlib.OsLib.register(platform,env);
        se.krka.kahlua.stdlib.TableLib.register(platform,env);
        var thread=new KahluaThread(System.out,platform,env);
        thread.debugOwnerThread=Thread.currentThread();
        try (var stream=Files.newInputStream(Path.of(args[2]))) {
            thread.call(Prototype.loadByteCode(stream,env),new Object[0]);
        }
        env.rawset("C",thread.call(compile(Files.readString(Path.of(args[0])),"QueueFixtureItemCleanup.lua",env),new Object[0]));
        Object[] result=thread.pcall(compile(Files.readString(Path.of(args[1])),"fixture-cleanup-native-smoke.lua",env),new Object[0]);
        if (!Boolean.TRUE.equals(result[0])) throw new AssertionError(Arrays.toString(result));
        System.out.println("FIXTURE_ITEM_CLEANUP_NATIVE_PASS");
    }
}
'''

SMOKE = r'''
local function fixture(mode)
 local pool={items={},calls=0};local lease={valid=true,guards=0};local entries={}
 function pool:getItems()return {size=function()return #self.items end,get=function(_,i)return self.items[i+1]end}end
 for id=1,2 do
  local value={id=id,container=pool,owner='phase'}
  function value:getID()return self.id end
  function value:getFullType()return 'Base.Nails'end
  function value:getContainer()return self.container end
  pool.items[id]=value;entries[id]={id=id,item=value,container=pool,ft='Base.Nails'}
 end
 local removedFault=false
 function pool:Remove(value)
  self.calls=self.calls+1
  if mode=='before'and not removedFault then removedFault=true;error('before removal')end
  local found=false
  for i,present in ipairs(self.items)do
   if present==value then table.remove(self.items,i);value.container=nil;found=true;break end
  end
  assert(found,'duplicate local removal')
  if mode=='after'and not removedFault then removedFault=true;error('after removal')end
 end
 local attempts,effects=0,0
 sendRemoveItemFromContainer=function()
  attempts=attempts+1
  if mode=='before'and attempts==1 then error('before notice')end
  effects=effects+1
  if mode=='after'and attempts==1 then error('after notice')end
 end
 local journal=C.new(entries,{containers={pool},server=true,
  guard=function()
   lease.guards=lease.guards+1;assert(lease.valid,'generation changed')
   for _,value in ipairs(pool.items)do assert(value.owner=='phase','foreign item')end
  end,
  check=function(entry)assert(entry.item.owner=='phase','owner changed')end})
 return journal,pool,entries,lease,function()return attempts,effects end
end
for _,mode in ipairs({'normal','before','after'})do
 local journal,pool,entries,lease,counts=fixture(mode)
 -- Exercise real Kahlua metatable lookup and protected private-token state.
 assert(getmetatable(journal)=='fixture cleanup journal')
 assert(journal.entries==nil and journal.guard==nil)
 assert(not pcall(function()journal.entries={}end))
 assert(not pcall(setmetatable,journal,{}))
 local receipt=C.run(journal)
 assert(#receipt.removedIds==2 and receipt.removedIds[1]==1 and receipt.removedIds[2]==2)
 assert(C.started(journal)and C.removed(journal,entries[1].item)and C.removed(journal,entries[2].item))
 local attempts,effects=counts()
 assert(pool.calls==(mode=='before'and 3 or 2))
 assert(attempts==(mode=='normal'and 2 or 3))
 assert(effects==(mode=='after'and 3 or 2))
 assert(#receipt.recoveries==(mode=='normal'and 0 or 2))
 if mode~='normal'then
  assert(receipt.recoveries[1].operation=='remove'and not receipt.recoveries[1].publicationUncertain)
  assert(receipt.recoveries[2].operation=='notice'and receipt.recoveries[2].publicationUncertain)
 end
 local guards=lease.guards;C.run(journal)
 assert(lease.guards>guards and pool.calls==(mode=='before'and 3 or 2))
 local again=counts();assert(again==attempts)
 lease.valid=false;assert(not pcall(C.run,journal))
end
local journal,pool,entries,lease,counts=fixture('normal')
entries[1].item.owner='foreign'
assert(not pcall(C.run,journal)and pool.calls==0 and not C.started(journal))
assert(counts()==0)
return true
'''


@unittest.skipUnless(os.environ.get('PZ_GAME') and os.environ.get('PZ_JDK'),
                     'PZ_GAME/PZ_JDK required for installed native Kahlua cleanup test')
class NativeFixtureItemCleanupTests(unittest.TestCase):
    def test_common_cleanup_opaque_handle_and_fault_recovery(self):
        game = Path(os.environ['PZ_GAME'])
        jdk = Path(os.environ['PZ_JDK'])
        jar = game/'projectzomboid.jar'
        with tempfile.TemporaryDirectory(prefix='pz-fixture-cleanup-native-') as temporary:
            build = Path(temporary)
            source = build/'FixtureItemCleanupChecks.java'
            source.write_text(HARNESS)
            smoke = build/'smoke.lua'
            smoke.write_text(SMOKE)
            compiled = subprocess.run([str(jdk/'bin/javac'), '-cp', str(jar), '-d', str(build), str(source)],
                                      capture_output=True, text=True, timeout=30)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = subprocess.run([str(jdk/'bin/java'), '-cp', os.pathsep.join((str(build), str(jar))),
                                     'FixtureItemCleanupChecks',
                                     str(ROOT/'tests/native_queue/support/QueueFixtureItemCleanup.lua'), str(smoke),
                                     str(game/'stdlib.lbc')],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('FIXTURE_ITEM_CLEANUP_NATIVE_PASS', result.stdout)


if __name__ == '__main__':
    unittest.main()
