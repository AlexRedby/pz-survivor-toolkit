"""Dashboard launch consolidation retains exact authority and cleanup boundaries."""
from copy import deepcopy
import json
from pathlib import Path
import sys
import tempfile
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import vehicle_lights as adapter

FIXTURE = ROOT / 'tests/native_queue/vehicle-lights'


def fixture_runtime():
    lua = LuaRuntime()
    lua.globals().fixture_api = lua.execute((FIXTURE / 'shared/VehicleLightsFixture.lua').read_text())
    return lua


class VehicleLightsTests(unittest.TestCase):
    def selection(self, kind='mp'):
        return dict(suite='vehicle-lights', cases=['road'], kind=kind, mode='toolkit', clients=1,
                    languages=['EN'], mods=adapter.definitions()['vehicle-lights']['default_mods'] + ['RealisticDash'],
                    options=dict(mp_host=True, dashboard=True, push=True, rocker=True,
                                 ffmpeg=sys.executable, ffprobe=sys.executable))

    def test_combined_controls_require_real_dashboard_and_reject_masked_rotary(self):
        selection = self.selection()
        adapter.validate(selection)
        selection['kind'] = 'sp'
        adapter.validate(selection)
        for key, value in [('rotary', True), ('dashboard', False), ('dashboard_compare', True), ('push', 'true')]:
            bad = deepcopy(selection)
            bad['options'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                adapter.validate(bad)
        selection['mods'].remove('RealisticDash')
        with self.assertRaisesRegex(ValueError, 'RealisticDash'):
            adapter.validate(selection)

    def test_server_correlates_ack_and_waits_for_empty_owned_vehicle_before_switch(self):
        lua = fixture_runtime()
        lua.execute(r'''
        logs={};print=function(s)logs[#logs+1]=s end
        Events={OnClientCommand={Add=function(fn)command=fn end},OnTick={Add=function(fn)tick=fn end}}
        now=0;getTimestampMs=function()return now end
        player={getUsername=function()return 'client1'end}
        function vehicle(id,script)
         local v={id=id,script=script,occupied=true,on=false}
         function v:getId()return self.id end
         function v:getScript()return {getFullName=function()return self.script end}end
         function v:isDriver(p)return self.occupied and p==player end
         function v:getHeadlightsOn()return self.on end
         function v:getMaxPassengers()return 1 end
         function v:getCharacter()return self.occupied and player or nil end
         return v
        end
        old=vehicle(17,'Base.SportsCar')
        F=setmetatable({vehicle=old},{__index=fixture_api})
        F.remove=function(v)assert(v==F.vehicle and not v.occupied);F.vehicle=nil;return v.id end
        F.prepare=function(p,x,y,dir,script)assert(not F.vehicle);F.vehicle=vehicle(17,script);return F.vehicle end
        sent={};sendServerCommand=function(p,m,c,a)sent[#sent+1]={command=c,args=a}end
        package.preload.VehicleLightsFixture=function()return F end
        package.preload.QueueLightsConfig=function()return {push=true,rocker=true}end
        ''')
        lua.execute((FIXTURE / 'server/ZZVehicleLightsServer.lua').read_text())
        lua.execute(r'''
        command('VehicleLightsTest','power',player,{id=17,generation=1,family='sport',mode='off',on=false,request=1})
        assert(#sent==1 and sent[1].args.id==17)
        assert(not pcall(command,'VehicleLightsTest','power',player,{id=17,generation=1,family='heavy',mode='off',on=false,request=2}))
        assert(not pcall(command,'VehicleLightsTest','power',player,{id=17,generation=1,family='sport',mode='off',on=false,request=1}))
        command('VehicleLightsTest','replace',player,{id=17,generation=1,x=1,y=2,dir='N',script='Base.PickUpTruck'})
        tick();assert(F.vehicle==old and #sent==1)
        old.occupied=false;tick()
        assert(F.vehicle==nil and sent[2].command=='removed')
        tick();assert(F.vehicle==nil) -- never spawn before the client's absence observation
        command('VehicleLightsTest','removeObserved',player,{id=17,generation=1})
        assert(F.vehicle.id==17 and F.vehicle~=old and sent[3].command=='replacement' and sent[3].args.generation==2)
        assert(not pcall(command,'VehicleLightsTest','remove',player,{id=17,generation=1}))
        F.vehicle.occupied=true
        command('VehicleLightsTest','power',player,{id=17,generation=2,family='heavy',mode='off',on=false,request=2})
        command('VehicleLightsTest','remove',player,{id=17,generation=2})
        F.vehicle.occupied=false;tick();assert(F.vehicle==nil and sent[5].command=='removed')
        authorityX=1;authorityY=2
        player.getVehicle=function()return nil end;player.getX=function()return authorityX end
        player.hasTimedActions=function()return false end;player.isPlayerMoving=function()return false end
        player.getY=function()return authorityY end;player.getZ=function()return 0 end
        primary=99;player.getPrimaryHandItem=function()return {getID=function()return primary end}end
        player.getSecondaryHandItem=function()return nil end
        command('VehicleLightsTest','restoreBaseline',player,{generation=2,x=1.375,y=2.625,z=0,primaryID=42,secondaryID=-1})
        tick();assert(#sent==5) -- delayed native Equip propagation
        primary=42;tick();assert(#sent==5) -- floored teleport is still not the exact baseline
        authorityX=1.375;authorityY=2.625;tick();assert(#sent==5)
        for i=1,15 do now=i*50;tick()end
        assert(#sent==6 and sent[6].command=='baselineRestored'and sent[6].args.primaryID==42)
        assert(not pcall(command,'VehicleLightsTest','restoreBaseline',player,{generation=2,x=1,y=2,z=0,primaryID=42,secondaryID=-1}))
        ''')

    def test_missing_native_equip_propagation_times_out_without_restore_ack(self):
        lua = fixture_runtime()
        lua.execute(r'''
        Events={OnClientCommand={Add=function(fn)command=fn end},OnTick={Add=function(fn)tick=fn end}}
        now=0;getTimestampMs=function()return now end;logs={};print=function(s)logs[#logs+1]=s end
        player={getUsername=function()return 'client1'end,getVehicle=function()return nil end,
         hasTimedActions=function()return false end,isPlayerMoving=function()return false end,
         getX=function()return 1 end,getY=function()return 2 end,getZ=function()return 0 end,
         getPrimaryHandItem=function()return nil end,getSecondaryHandItem=function()return nil end}
        v={getId=function()return 17 end,getMaxPassengers=function()return 0 end}
        F=setmetatable({vehicle=v,remove=function()F.vehicle=nil;return 17 end},{__index=fixture_api})
        package.preload.VehicleLightsFixture=function()return F end
        package.preload.QueueLightsConfig=function()return {}end
        sent={};sendServerCommand=function(p,m,c,a)sent[#sent+1]=c end
        ''')
        lua.execute((FIXTURE / 'server/ZZVehicleLightsServer.lua').read_text())
        lua.execute(r'''
        command('VehicleLightsTest','remove',player,{id=17,generation=1});tick()
        command('VehicleLightsTest','restoreBaseline',player,{generation=1,x=1,y=2,z=0,primaryID=42,secondaryID=-1})
        tick();assert(#sent==1 and sent[1]=='removed')
        now=15001;assert(pcall(tick));assert(#sent==1)
        for i=1,10 do now=now+50;tick()end
        player.getPrimaryHandItem=function()return {getID=function()return 42 end}end
        command('VehicleLightsTest','restoreBaseline',player,{generation=1,x=1,y=2,z=0,primaryID=42,secondaryID=-1})
        for i=1,20 do now=now+50;tick()end
        assert(#sent==1) -- Late propagation cannot re-arm or acknowledge a quarantined phase.
        local failures=0
        for _,line in ipairs(logs)do if line:find('[VEHICLE_LIGHTS] FAIL ',1,true)then failures=failures+1 end end
        assert(failures==1)
        ''')

    def test_exact_owned_removal_refuses_passengers_animals_items_and_towing(self):
        for guard in ('foreign-reference', 'passenger', 'animal', 'item', 'towing', 'clean'):
            lua = fixture_runtime()
            fixture = lua.execute((FIXTURE / 'shared/VehicleLightsFixture.lua').read_text())
            lua.globals().F = fixture
            lua.globals().guard = guard
            lua.execute(r'''
            removed=false
            v={getMaxPassengers=function()return 1 end,getId=function()return -1 end,
             getCharacter=function()return guard=='passenger'and {}or nil end,
             getAnimals=function()return {size=function()return guard=='animal'and 1 or 0 end}end,
             getVehicleTowing=function()return guard=='towing'and {}or nil end,getVehicleTowedBy=function()return nil end,
             getPartCount=function()return 1 end,getPartByIndex=function()return {getItemContainer=function()
              return {getItems=function()return {size=function()return guard=='item'and 1 or 0 end}end}end}end,
             setHeadlightsOn=function()end,shutOff=function()end,permanentlyRemove=function()removed=true end}
            getCell=function()return {getVehicles=function()return {contains=function()return not removed end}end}end
            F.vehicle=guard=='foreign-reference'and {}or v
            local ok=pcall(F.remove,v)
            assert(ok==(guard=='clean')and removed==(guard=='clean'))
            assert((F.vehicle==nil)==(guard=='clean'))
            ''')

    def test_client_waits_for_ack_and_replication_before_replacing_vehicle(self):
        lua = fixture_runtime()
        lua.execute(r'''
        config={kind='mp'};video={push=true,rocker=true,dashboard=true}
        next=nil -- Match stock B42 Kahlua, rather than Lua 5.1's richer globals.
        package.preload.QueueTestSelection=function()return config end
        package.preload.QueueLightsConfig=function()return video end
        package.preload.VehicleLightsFixture=function()return fixture_api end
        Events={};for _,name in ipairs({'OnServerCommand','OnGameStart','OnPostUIDraw','OnTick'})do
         Events[name]={Add=function(fn)_G[name]=fn end}
        end
        logs={};print=function(s)logs[#logs+1]=s end
        now=1000;getTimestampMs=function()return now end
        isClient=function()return true end
        triggerEvent=function()end
        p={getSquare=function()return {}end,teleportTo=function()end,hasTimedActions=function()return nativeBusy end}
        getPlayer=function()return p end
        ISTimedActionQueue={getTimedActionQueue=function()return {queue={}}end}
        old={getId=function()return 17 end,setHeadlightsOn=function()end,exit=function()end}
        new={getId=function()return 17 end}
        present={[17]=old};getVehicleById=function(id)return present[id]end
        sent={};sendClientCommand=function(a,b,c,d)
         if a==p then sent[#sent+1]={module=b,command=c,args=d}
         else sent[#sent+1]={module=a,command=b,args=c}end
        end
        function up(fn,name,value,set)
         for i=1,100 do local key,v=debug.getupvalue(fn,i);if not key then break end
          if key==name then if set then debug.setupvalue(fn,i,value)end;return v end
         end
         error('missing upvalue '..name)
        end
        ''')
        lua.execute((FIXTURE / 'client/ZZVehicleLights.lua').read_text())
        lua.execute(r'''
        run=up(OnTick,'run')
        up(run,'climate',function()end,true);up(run,'hideUI',function()end,true)
        initialX=10640.5;initialY=10144.5
        p.getVehicle=function()return nil end;p.getX=function()return initialX end;p.getY=function()return initialY end;p.getZ=function()return 0 end
        lightsFixtureMotionIdle=function()return not initialMotion end;lightsFixtureMotionProbe=function()return 'motion=observed'end
        local realCapture=up(run,'captureBaseline')
        up(run,'captureBaseline',function()initialCaptures=(initialCaptures or 0)+1;capturedX=p:getX();return {}end,true)
        initialMotion=true;for i=0,20 do now=i*50;run()end;assert(not initialCaptures)
        initialMotion=false;initialX=10640.48828125;initialY=10144.5048828125
        for i=0,14 do now=1200+i*50;run()end;assert(not initialCaptures)
        now=1950;run();assert(initialCaptures==1 and capturedX==initialX)
        up(run,'captureBaseline',realCapture,true);now=1000
        up(run,'baseline',{},true);up(run,'phase',30,true);up(run,'since',0,true)
        up(run,'vehicle',old,true);up(run,'origin',{x=1,y=2,dir='N'},true)
        up(up(run,'owned'),'ownedCount',1,true)
        local capture=up(run,'dashboardCapture');power=up(capture,'powerRequest')
        nativeBusy=true;run();assert(#sent==0);nativeBusy=false
        power({__YourDashFamily='sport'},'off');assert(#sent==1)
        run();assert(#sent==1) -- power acknowledgement still pending
        OnServerCommand('VehicleLightsTest','power',sent[1].args)
        assert(not pcall(OnServerCommand,'VehicleLightsTest','power',sent[1].args))
        run();assert(sent[3].command=='replace'and sent[3].args.id==17)
        OnServerCommand('VehicleLightsTest','removed',{id=17,generation=1})
        run();assert(up(run,'vehicle')==old) -- old vehicle still replicated locally
        present[17]=nil;run();assert(sent[4].command=='removeObserved'and up(run,'vehicle')==old)
        OnServerCommand('VehicleLightsTest','replacement',{old=17,id=17,generation=2})
        run();assert(up(run,'vehicle')==old) -- no replacement object yet
        present[17]=new;run();assert(up(run,'vehicle')==new)
        assert(logs[#logs]=='[VEHICLE_LIGHTS] OWNED index=2 id=17')
        up(run,'phase',41,true);up(run,'baseline',{x=1,y=2,z=0},true);up(run,'since',now,true)
        p.getVehicle=function()return nil end;p.getX=function()return 1 end;p.getY=function()return 2 end;p.getZ=function()return 0 end
        p.getPrimaryHandItem=function()return nil end;p.getSecondaryHandItem=function()return nil end
        lightsFixtureMotionIdle=function()return true end;lightsFixtureMotionProbe=function()return 'idle=true'end
        up(run,'afterSettlement',fixture_api.newPositionSettlement({x=1,y=2,z=0}),true)
        run();assert(logs[#logs]:find('POSITION_SETTLING',1,true))
        now=17000;assert(not pcall(run)) -- missing restoration acknowledgement cannot complete
        now=1000
        assert(not pcall(OnServerCommand,'VehicleLightsTest','baselineRestored',{generation=2,primaryID=-1,secondaryID=-1,x=1,y=2,z=0,stableMs=0,samples=1}))
        OnServerCommand('VehicleLightsTest','baselineRestored',{generation=2,primaryID=-1,secondaryID=-1,x=1,y=2,z=0,stableMs=750,samples=16})
        run();assert(logs[#logs]~='[VEHICLE_LIGHTS] COMPLETE road')
        for i=1,15 do now=1000+i*50;run()end
        run();assert(logs[#logs]=='[VEHICLE_LIGHTS] COMPLETE road')
        ''')

    def test_verifier_requires_both_families_authority_and_ordered_cleanup(self):
        selection = self.selection()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            video = root / 'client1/videos/road.mp4'
            video.parent.mkdir(parents=True)
            video.touch()
            rows = ['ENV time=2 nightDarkness=1 ',
                    'POSITION_SETTLED stage=initial generation=0 stableMs=750 samples=16 observed=1,2,0',
                    'OWNED index=1 id=17']
            for name in adapter.PHASES:
                high = name in ('high', 'original_high', 'reverse_high')
                rear = dict(distance=12 if name.startswith('reverse_') else 3,
                            intensity=.3, g=1 if name.startswith('reverse_') else .2)
                probe = dict(vehicle=True, driver=True, battery=1, HeadlightLeft=dict(distance=54 if high else 36),
                             HeadlightRearLeft=rear, transmission='R' if name.startswith('reverse_') else 'N')
                rows.append(f'PHASE {name} elapsedMs=1 probe=' + json.dumps(probe))
            rows += ['PUSH_CLICK ' + a + ' ' + b for a, b in [('off', 'low'), ('low', 'high'), ('high', 'off'), ('off', 'low'), ('low', 'high')]]
            rows += ['ROCKER_CLICK ' + a + ' ' + b for a, b in [('off', 'low'), ('low', 'high'), ('high', 'low'), ('low', 'off')]]
            server = []
            for number, (family, mode) in enumerate((f, m) for f in ('sport', 'heavy') for m in ('off', 'low', 'high')):
                value = f'family={family} mode={mode} on={str(mode != "off").lower()} id=17 generation={1 if family == "sport" else 2} request={number + 1}'
                rows += ['POWER_REQUEST ' + value, 'POWER_ACK ' + value]
                server.append('POWER_ACK ' + value)
            rows += ['CLEANUP index=1 id=17 queueDrained=true removed=true', 'OWNED index=2 id=17']
            rows += [f'DASHBOARD heavy_scale_{scale} mode=off family=heavy integration=true scale={scale} ' for scale in ('0.75x', '1x', '1.4x', '2x')]
            rows += ['VIDEO_RESULT ' + json.dumps(dict(state='completed', file=str(video), frames=1)),
                     'CLEANUP index=2 id=17 queueDrained=true removed=true',
                     'BASELINE_STATE_RESTORED generation=2 settings=true orientation=true equipment=true',
                     'POSITION_SETTLED stage=before generation=2 stableMs=750 samples=16 observed=3,4,0',
                     'POSITION_RESTORE generation=2 before=target=1,2,0 observed=3,4,0 after=target=1,2,0 observed=1,2,0',
                     'BASELINE_RESTORED generation=2 primaryID=-1 secondaryID=-1 position=true',
                     'POSITION_SETTLED stage=after generation=2 stableMs=750 samples=16 observed=1,2,0',
                     'RESTORED queueDrained=true settings=true', 'COMPLETE road']
            server += ['REMOVED index=1 id=17', 'REMOVED index=2 id=17',
                       'POSITION_SETTLED stage=authority generation=2 stableMs=750 samples=16 observed=1,2,0',
                       'BASELINE_RESTORED generation=2 primaryID=-1 secondaryID=-1 position=true']
            original = '\n'.join(adapter.MARKER + row for row in rows)
            (root / 'server-launch.log').write_text('\n'.join(adapter.MARKER + row for row in server))
            (root / 'client1-launch.log').write_text(original)
            self.assertEqual(adapter.verify(root, selection, {})['issues'], [])
            for before, after in [('POWER_ACK family=heavy', 'POWER_ACK family=sport'),
                                  ('CLEANUP index=1 id=17', 'CLEANUP index=1 id=18'),
                                  ('stableMs=750', 'stableMs=0'),
                                  ('RESTORED queueDrained=true settings=true', 'RESTORED queueDrained=false settings=true')]:
                (root / 'client1-launch.log').write_text(original.replace(before, after))
                with self.subTest(before=before):
                    self.assertTrue(adapter.verify(root, selection, {})['issues'])
            (root / 'client1-launch.log').write_text(original)
            with (root / 'server-launch.log').open('a') as stream:
                stream.write('\n' + adapter.MARKER + 'FAIL authority baseline restoration timeout\n')
            self.assertIn('Authority vehicle lighting fixture quarantined', adapter.verify(root, selection, {})['issues'])

    def test_local_settings_and_equipment_restore_after_recording_and_refuse_pending_actions(self):
        lua = fixture_runtime()
        lua.execute(r'''
        config={kind='sp'};video={dashboard=true}
        now=0;getTimestampMs=function()return now end
        next=nil
        package.preload.QueueTestSelection=function()return config end
        package.preload.QueueLightsConfig=function()return video end
        package.preload.VehicleLightsFixture=function()return fixture_api end
        Events={};for _,name in ipairs({'OnServerCommand','OnGameStart','OnPostUIDraw','OnTick'})do
         Events[name]={Add=function(fn)_G[name]=fn end}
        end
        print=function()end
        function up(fn,name,value,set)
         for i=1,100 do local key,v=debug.getupvalue(fn,i);if not key then break end
          if key==name then if set then debug.setupvalue(fn,i,value)end;return v end
         end;error('missing '..name)
        end
        p={x=1.375,y=2.625,z=0,dir='N',fx=.2,fy=.8,god=false,ghost=false,auto=true,primary={},secondary={}}
        for method,key in pairs({getX='x',getY='y',getZ='z',getDir='dir',getForwardDirectionX='fx',getForwardDirectionY='fy',
         isGodMod='god',isGhostMode='ghost',getAutoDrink='auto',getPrimaryHandItem='primary',getSecondaryHandItem='secondary'})do
         local k=key;p[method]=function(self)return self[k]end
        end
        for method,key in pairs({setDir='dir',setGodMod='god',setGhostMode='ghost',setAutoDrink='auto',setPrimaryHandItem='primary',setSecondaryHandItem='secondary',
         setX='x',setY='y',setZ='z',setNextX='nextX',setNextY='nextY',setLastX='lastX',setLastY='lastY'})do
         local k=key;p[method]=function(self,v)self[k]=v end
        end
        function p:getVehicle()return nil end
        function p:getSquare()return {}end
        function p:hasTimedActions()return false end
        function p:teleportTo(x,y,z)
         positionRestores=(positionRestores or 0)+1
         self.x=math.floor(x);self.y=math.floor(y);self.z=z;self.lastX=self.x;self.lastY=self.y
        end
        function p:setForwardDirection(x,y)self.fx=x;self.fy=y;orientationMotionFrames=2 end
        getPlayer=function()return p end;isClient=function()return false end
        queue={};ISTimedActionQueue={getTimedActionQueue=function()return {queue=queue}end}
        ISUIHandler={allUIVisible=true};ISUIHandler.toggleUI=function()ISUIHandler.allUIVisible=not ISUIHandler.allUIVisible end
        function option(value)return {value=value,getValue=function(self)return self.value end,setValue=function(self,v)self.value=v end}end
        opts={VehicleBeamShape=option(false),VehicleReverseLight=option(1),VehicleLightSpill=option(2)}
        PZAPI={ModOptions={getOptions=function(self,id)if id=='PZSurvivorToolkit'then return {getOption=function(self,key)return opts[key]end}end end}}
        NepHBO7={options={alwaysOn=option(true),lengthMult=option(1),intensityMult=option(1),debugMode=option(false)}}
        PZSurvivorToolkit={VehicleLighting={refreshBeams=function()end,configureReverse=function()end}}
        ClimateManager={FLOAT_AMBIENT=1,FLOAT_DAYLIGHT_STRENGTH=2,FLOAT_NIGHT_STRENGTH=3,FLOAT_FOG_INTENSITY=4,FLOAT_PRECIPITATION_INTENSITY=5,FLOAT_CLOUD_INTENSITY=6}
        climate={};for i=1,6 do climate[i]={value=i/10,enabled=i%2==0,
         isEnableAdmin=function(self)return self.enabled end,getAdminValue=function(self)return self.value end,
         setAdminValue=function(self,v)self.value=v end,setEnableAdmin=function(self,v)self.enabled=v end}end
        getClimateManager=function()return {getClimateFloat=function(self,i)return climate[i]end}end
        time=8;getGameTime=function()return {getTimeOfDay=function()return time end,setTimeOfDay=function(self,v)time=v end}end
        pane={visible=true,getIsVisible=function(self)return self.visible end,setVisible=function(self,v)self.visible=v end}
        SurvivalGuide={instance={visible=true,getIsVisible=function(self)return self.visible end,setVisible=function(self,v)self.visible=v end}}
        getPlayerInventory=function()return pane end;getPlayerLoot=getPlayerInventory;getPlayerInfoPanel=getPlayerInventory
        scale='1.4x';package.preload['YourDash/DashboardCore']=function()return {GetScaleKey=function()return scale end,
         SetTextureSizeIndex=function(i)scale=({'0.75x','1x','1.4x','2x'})[i]end}end
        lightsFixtureRestore=function()cameraRestored=true end
        lightsFixtureMotionIdle=function()return (orientationMotionFrames or 0)==0 end
        lightsFixtureMotionProbe=function()return 'orientationMotionFrames='..tostring(orientationMotionFrames)end
        ''')

        lua.execute((FIXTURE / 'client/ZZVehicleLights.lua').read_text())
        lua.execute(r'''
        run=up(OnTick,'run');capture=up(run,'captureBaseline');restore=up(run,'restoreNonPositionBaseline')
        baseline=capture(p);up(restore,'baseline',baseline,true)
        p.god=true;p.ghost=true;p.auto=false;p.primary={};p.secondary={};p.x=99;p.fx=0
        time=2;ISUIHandler.allUIVisible=false;pane.visible=false;scale='2x';opts.VehicleLightSpill.value=3;SurvivalGuide.instance.visible=false
        NepHBO7.options.lengthMult.value=1.5;climate[1].value=1;climate[1].enabled=true
        queue[1]={};assert(not pcall(restore,p))
        queue={};up(run,'phase',40,true);up(run,'removed',true,true);up(run,'cleanupId',17,true)
        up(up(run,'owned'),'ownedCount',1,true)
        run()
        assert(cameraRestored and not positionRestores and p.x==99)
        -- Logical direction restoration changes the animation target, so its
        -- root motion occurs on following native frames, after the setter.
        for i=1,2 do
         p.x=p.x+.02;orientationMotionFrames=orientationMotionFrames-1;now=now+50;run()
         assert(not positionRestores)
        end
        for i=1,14 do now=now+50;run();assert(not positionRestores)end
        now=now+50;run();assert(positionRestores==1)
        -- Next native integration consumes nextX/nextY; neither floored teleport
        -- coordinates nor stale vehicle motion may replace the baseline.
        p.x=p.nextX;p.y=p.nextY
        assert(cameraRestored and p.x==1.375 and p.y==2.625 and p.lastX==1.375 and p.lastY==2.625 and p.fx==.2 and p.fy==.8)
        assert(not p.god and not p.ghost and p.auto and p.primary==baseline.primary and p.secondary==baseline.secondary)
        assert(time==8 and ISUIHandler.allUIVisible and pane.visible and scale=='1.4x')
        assert(SurvivalGuide.instance.visible)
        assert(opts.VehicleLightSpill.value==2 and NepHBO7.options.lengthMult.value==1 and climate[1].value==.1 and not climate[1].enabled)
        for i=1,16 do now=now+50;run()end
        assert(positionRestores==1 and up(run,'done')==true)
        ''')

    def test_no_write_settlement_rejects_native_motion_drift_and_one_sample_target_match(self):
        lua = fixture_runtime()
        lua.execute(r'''
        p={x=10640.5,y=10144.5,z=0,getX=function(self)return self.x end,getY=function(self)return self.y end,getZ=function(self)return self.z end,
         teleportTo=function()error('settlement must not teleport')end,setX=function()error('settlement must not pin')end}
        local F=fixture_api
        local initial=F.newPositionSettlement(nil)
        for i=0,10 do assert(not F.observePositionSettlement(initial,p,i*50,false))end -- native root motion, empty queues
        p.x=10640.48828125;p.y=10144.5048828125
        for i=0,14 do assert(not F.observePositionSettlement(initial,p,600+i*50,true))end
        assert(F.observePositionSettlement(initial,p,1350,true))
        local target={x=p.x,y=p.y,z=p.z} -- observe the settled initial actor, not frame-one tile center
        local after=F.newPositionSettlement(target)
        assert(not F.observePositionSettlement(after,p,2000,true))
        assert(not F.observePositionSettlement(after,p,3000,true)) -- elapsed time alone does not prove native samples
        p.x=target.x-.01171875
        for i=1,40 do assert(not F.observePositionSettlement(after,p,3000+i*50,true))end -- permanent drift outside unchanged .01 guard
        p.x=target.x
        for i=0,14 do assert(not F.observePositionSettlement(after,p,6000+i*50,true))end
        assert(F.observePositionSettlement(after,p,6750,true))
        assert(not F.observePositionSettlement(after,p,6800,false)) -- renewed motion resets proof
        ''')

if __name__ == '__main__':
    unittest.main()
