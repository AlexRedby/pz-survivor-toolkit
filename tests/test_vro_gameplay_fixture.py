"""Authority gates must reject stale baselines before accepting replicated effects."""
import json
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
LUA = shutil.which('luajit') or shutil.which('lua')


@unittest.skipUnless(LUA, 'Lua runtime unavailable')
class VROGameplayFixtureTests(unittest.TestCase):
    def run_lua(self, source):
        path = ROOT / 'tests/native_queue/vro-gameplay/shared/VROGameplayFixture.lua'
        harness = '''
next=nil
events=0
function require(name)
 if name=='QueueHealthEvents' then return {encode=function()events=events+1;return '{}'end}end
 return family
end
function print()end
family={observe=function()return observed end,validate=function(a,b,mode)validations=validations+1;assert(mode=='complete')end}
validations=0
'''
        result = subprocess.run([LUA, '-'], text=True, capture_output=True,
            input=harness + '\nlocal F=dofile(' + json.dumps(str(path)) + ')\n' + source)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_replication_wait_is_quiet_and_only_matching_native_baseline_is_accepted(self):
        self.run_lua('''
F.active={phase='repair-complete',index=2,ids={vehicleID=10},before={condition=40}}
F.world=function()return {vehicleID=10,condition=76}end
local receipt={vehicleID=10,mode='complete',started=true,menuCallback=true,nativeDuration=280,
 before={condition=40},after={condition=76}}
observed={condition=40}
assert(F.after({},receipt)==nil and events==0 and validations==0)
observed={condition=76}
assert(F.after({},receipt).condition==76 and events==1 and validations==1)
receipt.before.condition=39
assert(not pcall(F.after,{},receipt) and events==1)
receipt.before.condition=40;receipt.started=false
assert(not pcall(F.after,{},receipt) and events==1)
''')

    def test_sp_and_network_tombstones_are_absent_without_synthetic_ids(self):
        self.run_lua('''
local value={isRemovedFromWorld=function()return false end}
function getVehicleById(id)assert(id==9);return value end
assert(F.resolve({vehicleID=9})==value)
value.isRemovedFromWorld=function()return true end
assert(F.resolve({vehicleID=9})==nil)
function getVehicleById()error('SP cannot use the network registry')end
assert(F.resolve({vehicleID=-1,vehicle=value})==nil)
value.isRemovedFromWorld=function()return false end
assert(F.resolve({vehicleID=-1,vehicle=value})==value)
''')

    def test_free_tiles_with_blocked_or_hoppable_edges_are_not_an_open_fixture_area(self):
        self.run_lua('''
local squares={}
for x=-4,4 do for y=-5,5 do
 local sq={x=x,y=y}
 function sq:isOutside()return true end
 function sq:isFree(flag)assert(flag==false);return true end
 function sq:getMovingObjects()return {size=function()return 0 end}end
 function sq:isBlockedTo(other)return blocked and self.x==1 and other.x==0 and self.y==other.y end
 function sq:isHoppableTo(other)return hoppable and self.x==0 and other.x==1 and self.y==other.y end
 squares[x..':'..y]=sq
end end
function getCell()return {getGridSquare=function(_,x,y,z)assert(z==0);return squares[x..':'..y]end}end
assert(F.clear(0,0),'connected open area rejected')
blocked=true;assert(not F.clear(0,0),'reverse-direction wall edge ignored');blocked=false
hoppable=true;assert(not F.clear(0,0),'fence traversal admitted into the clear margin');hoppable=false
squares['4:5']=nil;assert(not F.clear(0,0),'unloaded margin admitted')
''')


if __name__ == '__main__':
    unittest.main()
