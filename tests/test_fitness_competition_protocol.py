"""Execute the real Host protocol with transport/pose doubles; no gameplay proof."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / 'tests/native_queue/fitness/server/ZZFitnessQueueServer.lua'

HARNESS = r'''
now=1000;packets={};logs={};handlers={}
function isServer()return true end
function getTimestampMs()return now end
function print(line)logs[#logs+1]=line end
Events={}
for _,name in ipairs({'OnServerStarted','OnClientCommand','OnTick'})do
 local event=name;Events[name]={Add=function(callback)handlers[event]=callback end}
end
observer={records={},active=nil}
local config={kind='mp',mode='toolkit',cases={'storage-peer-pickup'}}
package.preload['QueueTestSelection']=function()return config end
package.preload['QueueFitnessObservation']=function()return observer end
package.preload['QueueHealthEvents']=function()return{encode=function()return '{}'end}end
local squares={}
function square(x,y,z)
 local key=x..':'..y..':'..z
 if not squares[key]then
  local value={x=x,y=y,z=z}
  function value:getX()return self.x end;function value:getY()return self.y end;function value:getZ()return self.z end
  function value:isBlockedTo()return blocked==true end
  squares[key]=value
 end
 return squares[key]
end
function getCell()return{getGridSquare=function(_,x,y,z)return square(x,y,z)end}end
local function player(name,id,x)
 local p={name=name,id=id,x=x,y=20,z=0,pages=0,busy=false,nativeCount=0}
 function p:getUsername()return self.name end;function p:getOnlineID()return self.id end
 function p:getCurrentSquare()return square(self.x,self.y,self.z)end
 function p:getX()return self.x+.5 end;function p:getY()return self.y+.5 end;function p:getZ()return self.z end
 function p:isDead()return self.dead==true end
 function p:setPerkLevelDebug()end
 function p:setAlreadyReadPages(_,value)self.pages=value end;function p:getAlreadyReadPages()return self.pages end
 function p:hasTimedActions()return self.busy end
 function p:getCharacterActions()return{size=function()return self.nativeCount end,isEmpty=function()return self.nativeCount==0 end}end
 function p:getFitness()return{getCurrentExe=function()return nil end}end
 local book={getID=function()return 123 end,getNumberOfPages=function()return 10 end,
  getFullType=function()return 'Base.BookMechanic1'end,setAlreadyReadPages=function()end}
 function p:getInventory()return{AddItem=function()return book end,getItemById=function()return book end,Remove=function()end}end
 return p
end
actor=player('client1',1,10);peer=player('client2',2,20)
local livePeer=peer
function replaceLivePeer()livePeer=player('client2',2,11)end
function getOnlinePlayers()return{size=function()return 2 end,get=function(_,i)return i==0 and actor or livePeer end}end
function sendServerCommand(player,module,name,args)
 assert(module=='FitnessQueueTest');packets[#packets+1]={player=player,name=name,args=args}
end
function sendAddItemToContainer()end
Perks={Mechanics={}}
local spec={origin={x=10,y=20,z=0},bag={id=100,kind='Base.Bag_Schoolbag'},prop={id=101,kind='Base.DumbBell'}}
package.preload['QueueFitnessFixture']=function()return{
 prepare=function(player,id)
  fixtureState={player=player,case=id,ids={case=id,negativeStorage=spec}}
  return fixtureState
 end}end
package.preload['QueueFitnessStorageNegative']=function()return{
 position=function(player)return{x=player:getX(),y=player:getY(),z=player:getZ(),onlineID=player:getOnlineID()}end}end
function command(name,sender,args)handlers.OnClientCommand('FitnessQueueTest',name,sender,args)end
function tick(at)now=at or now;handlers.OnTick()end
function count(name)
 local amount=0
 for _,packet in ipairs(packets)do if packet.name==name then amount=amount+1 end end
 return amount
end
function ready(sender,bag,case)
 command('CompetitionReady',sender or peer,{case=case or 'storage-peer-pickup',bag=bag or 100})
end
function prepare()
 command('Ready',actor,{actor='client1',onlineID=1})
 command('Ready',peer,{actor='client2',onlineID=2});tick()
 assert(count('PeersReady')==2)
 command('Prepare',actor,{case='storage-peer-pickup'})
 assert(fixtureState and fixtureState.ids.peerOnlineID==2)
 packets={}
end
'''


class FitnessCompetitionProtocolTests(unittest.TestCase):
    def setUp(self):
        try:
            from lupa.lua51 import LuaRuntime
        except ImportError:
            self.skipTest('Lupa is required for real server protocol checks')
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(HARNESS)
        self.lua.execute(SERVER.read_text())
        self.lua.execute('prepare()')

    def check(self, code):
        self.lua.execute(code)

    def test_early_ready_waits_for_actual_authority_pose_and_acknowledges_once(self):
        self.check(r'''
ready()
assert(count('Failed')==0 and count('CompetitionReady')==0 and count('CompetitionPickup')==0,
 'early client Ready must wait for its independently arriving native server pose')
assert(fixtureState.pendingPeerReady and fixtureState.pendingPeerReady.since==1000 and fixtureState.pendingPeerReady.onlineID==2)
assert(not fixtureState.peerReady and not fixtureState.peerGrant)
tick(2000);assert(count('Failed')==0 and count('CompetitionReady')==0)
peer.x=11;tick(2100)
assert(count('CompetitionReady')==1 and count('Failed')==0 and count('CompetitionPickup')==0)
assert(not fixtureState.pendingPeerReady and fixtureState.peerReady.onlineID==2)
assert(packets[#packets].player==actor and packets[#packets].args.case=='storage-peer-pickup')
tick(2200);tick(2300);assert(count('CompetitionReady')==1)
''')

    def test_authority_reach_also_requires_same_floor_unblocked_and_idle(self):
        self.check(r'''
ready();peer.x=11;peer.z=1;tick(1500);assert(count('CompetitionReady')==0)
peer.z=0;blocked=true;tick(1600);assert(count('CompetitionReady')==0)
blocked=false;peer.busy=true;tick(1700);assert(count('CompetitionReady')==0)
peer.busy=false;peer.nativeCount=1;tick(1800);assert(count('CompetitionReady')==0)
peer.nativeCount=0;tick(1900)
assert(count('CompetitionReady')==1 and count('Failed')==0 and not fixtureState.peerGrant)
''')

    def test_absolute_deadline_fails_and_late_pose_cannot_acknowledge(self):
        self.check(r'''
ready();tick(5999);assert(count('Failed')==0 and count('CompetitionReady')==0)
tick(6000);assert(count('Failed')>=1 and count('CompetitionReady')==0 and count('CompetitionPickup')==0)
peer.x=11;tick(6001);assert(count('CompetitionReady')==0 and not fixtureState.peerReady)
''')

    def test_invalid_or_duplicate_commands_never_replace_pending_deadline(self):
        for attack in ('foreign', 'wrong-bag', 'wrong-case', 'duplicate'):
            with self.subTest(attack=attack):
                self.setUp()
                mutations = dict(foreign='ready(actor)', **{
                    'wrong-bag': 'ready(peer,999)',
                    'wrong-case': "ready(peer,100,'storage-walk-away')",
                    'duplicate': 'ready()',
                })
                self.check(r'''
ready();local original=fixtureState.pendingPeerReady
assert(original and original.since==1000)
now=4000
''' + mutations[attack] + r'''
assert(count('Failed')>=1 and fixtureState.pendingPeerReady==original and original.since==1000)
assert(count('CompetitionReady')==0 and not fixtureState.peerReady and not fixtureState.peerGrant)
tick(6000);assert(count('CompetitionReady')==0 and count('Failed')>=2)
''')

    def test_invalid_initial_ready_cannot_open_a_wait_or_receive_an_ack(self):
        self.check(r'''
ready(actor);ready(peer,999);ready(peer,100,'storage-walk-away')
assert(count('Failed')==3 and not fixtureState.pendingPeerReady and not fixtureState.peerReady)
peer.x=11;tick(2000);assert(count('CompetitionReady')==0 and count('CompetitionPickup')==0)
''')

    def test_pending_readiness_rejects_changed_online_id_or_connection(self):
        for mutation in ('peer.id=3', 'replaceLivePeer()', 'peer.dead=true'):
            with self.subTest(mutation=mutation):
                self.setUp()
                self.check('ready();assert(fixtureState.pendingPeerReady and count("Failed")==0);peer.x=11;' + mutation + r''';tick(1500)
assert(count('Failed')>=1 and count('CompetitionReady')==0 and not fixtureState.peerReady and not fixtureState.peerGrant)
''')

    def test_already_ready_cannot_reopen_wait_and_picked_keeps_strict_authority_reach(self):
        self.check(r'''
ready();peer.x=11;tick(1500);assert(count('CompetitionReady')==1 and fixtureState.peerReady)
ready();assert(count('Failed')==1 and not fixtureState.pendingPeerReady and count('CompetitionReady')==1)
peer.x=20
command('CompetitionPicked',peer,{case='storage-peer-pickup',proof={}})
assert(count('Failed')==2 and not fixtureState.peerPicked and not fixtureState.peerGrant)
assert(not fixtureState.pendingPeerReady and count('CompetitionReady')==1 and count('CompetitionPickup')==0)
''')


if __name__ == '__main__':
    unittest.main()
