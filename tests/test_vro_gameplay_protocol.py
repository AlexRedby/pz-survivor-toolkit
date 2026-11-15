"""Exercise real protocol callbacks; these mocks do not establish native effects."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).parent / 'native_queue/vro-gameplay'
HARNESS = r'''
next=nil
clock=0;skills=0;begins=0;finished=0;sent={};events={};placementReady=false;effectsReady=false
function getTimestampMs()return clock end
local function event()return {Add=function(fn)return fn end}end
Events={OnServerCommand=event(),OnMainMenuEnter=event(),OnClientCommand=event()}
function Events.OnClientCommand.Add(fn)command=fn end
function Events.OnServerCommand.Add(fn)serverCommand=fn end
local function player(name)return {getUsername=function()return name end,getSquare=function()return {}end}end
actor=player('client1');observer=player('client2')
function getPlayer()return actor end
function isClient()return client or false end
function isIngameState()return true end
function print(value)events[#events+1]=value end
function getFileReader()return nil end
function sendServerCommand(player,module,command,args)sent[#sent+1]={role=player:getUsername(),command=command,args=args}end
function sendClientCommand(module,command,args)sent[#sent+1]={command=command,args=args}end
F={phases={'repair-cancel','repair-complete','salvage-cancel','salvage-complete'}}
function F.same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not F.same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
function F.emit(event,row)events[#events+1]=event end
function F.actor()return {original=true}end
function F.skills()skills=skills+1 end
function F.prepare()F.packet={repair={x=10,y=20,z=0},salvage={x=30,y=40,z=0}};return F.packet end
function F.ids(packet,phase)return packet[phase:find('repair',1,true)and'repair'or'salvage']end
function F.begin()begins=begins+1;return F.packet end
function F.after()if effectsReady then return {observed=true}end end
function F.finishPhase()finished=finished+1 end
function F.ready()return false end
P={}
function P.beginCentered(player,target)return {target=target}end
function P.observeCentered(player,target)return {target=target}end
function P.poll()if placementReady then return {}end end
config={case='bank'}
package.preload.VROGameplayFixture=function()return F end
package.preload.QueueEnergyPlacement=function()return P end
package.preload.QueueVROGameplayConfig=function()return config end
package.preload.QueuePreflight=function()return {onTick=function(events,fn)tick=fn end}end
'''


class VROGameplayProtocolTests(unittest.TestCase):
    def lua(self, side):
        lua = LuaRuntime()
        lua.execute(HARNESS)
        lua.execute((ROOT / side / ('ZZVROGameplayServer.lua' if side == 'server' else 'ZZVROGameplay.lua')).read_text())
        return lua

    def test_authority_waits_for_both_placements_effects_and_peer_observations(self):
        lua = self.lua('server')
        lua.execute(r'''
command('VROGameplayTest','ready',actor,{original={}})
assert(#sent==0 and begins==0)
command('VROGameplayTest','ready',observer,{original={}})
assert(#sent==2 and sent[1].command=='place')
command('VROGameplayTest','placed',actor,{index=1,target={x=14,y=20,z=0}})
placementReady=true;tick();assert(begins==0)
command('VROGameplayTest','placed',observer,{index=1,target={x=14,y=23,z=0}})
tick();assert(begins==1 and #sent==3 and sent[3].role=='client1' and sent[3].command=='action')
command('VROGameplayTest','action',actor,{index=1,receipt={native=true}})
tick();assert(#sent==3)
effectsReady=true;tick();assert(#sent==5 and sent[4].command=='world')
command('VROGameplayTest','peer',actor,{index=1,world={observed=true}})
assert(finished==0 and #sent==5)
command('VROGameplayTest','peer',observer,{index=1,world={observed=true}})
assert(finished==1 and #sent==7 and sent[6].command=='place' and sent[6].args.index==2)
''')

    def test_local_debug_perks_change_only_after_authority_captures_original(self):
        lua = self.lua('client')
        lua.execute(r'''
client=true;tick()
assert(skills==0 and sent[1].command=='ready' and sent[1].args.original.original)
F.prepare()
serverCommand('VROGameplayTest','place',{packet=F.packet,index=1})
placementReady=true;tick();assert(sent[2].command=='placed' and skills==0)
serverCommand('VROGameplayTest','action',{packet=F.packet,index=1})
assert(skills==1)
tick();assert(skills==1,'input replication polling reset earned XP')
''')


if __name__ == '__main__':
    unittest.main()
