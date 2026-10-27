"""Toolkit compatibility against original external NewMusic in Lua 5.1.

Set PZ_NEWMUSIC_SOURCE to an unmodified complete Workshop mod root. Engine
objects, catalogs and event dispatch are doubles, not an in-game boot test.
"""
import hashlib
import os
from pathlib import Path
import unittest

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'PZSurvivorToolkit/42/media/lua'
CONFIG = '42/media/lua/shared/core/NMRuntimeConfig.lua'
CONVERTER = '42/media/lua/server/loot/NMVanillaCDLootConverter.lua'
RESOLVER = '42/media/lua/server/loot/NMLootPlaceholderResolver.lua'
CLIENT = '42/media/lua/client/main/NMClientMain.lua'
PROBE_PATH = '42/media/lua/client/runtime/NMClientVanillaDiscVisibleProbe.lua'
SHARED_ENTRY = LUA / 'shared/000ToolkitNewMusicCompatibility.lua'
CLIENT_ENTRY = LUA / 'client/000ToolkitNewMusicClientCompatibility.lua'
COMPAT = 'PZSurvivorToolkit/NewMusicCompatibility'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def runtime(source=None, active=True):
    lua = LuaRuntime(unpack_returned_tuples=True)
    sources = {
        'PZSurvivorToolkit': LUA / 'shared/PZSurvivorToolkit.lua',
        COMPAT: LUA / 'shared/PZSurvivorToolkit/NewMusicCompatibility.lua',
    }
    if source:
        sources.update({'core/NMRuntimeConfig': source / CONFIG,
                        'runtime/NMClientVanillaDiscVisibleProbe': source / PROBE_PATH})
    lua.globals().loadSource = lambda name: sources[name].read_text() if name in sources else None
    lua.globals().activeMod = active
    lua.execute(r'''
        required, loaded = {}, {}
        function require(name)
            required[#required+1]=name
            if loaded[name]~=nil then return loaded[name] end
            local source=loadSource(name)
            local result=true
            if source then result=assert(loadstring(source,'@'..name..'.lua'))() end
            loaded[name]=result or true
            return loaded[name]
        end
        function getActivatedMods()
            return {contains=function(_,id)return activeMod and id=='NewMusic'end}
        end
        Events=setmetatable({}, {__index=function(t,key)
            local event={callbacks={}}
            function event.Add(fn)
                for _,existing in ipairs(event.callbacks)do if existing==fn then return end end
                event.callbacks[#event.callbacks+1]=fn
            end
            function event.Remove(fn)
                for i=#event.callbacks,1,-1 do
                    if event.callbacks[i]==fn then table.remove(event.callbacks,i)end
                end
            end
            rawset(t,key,event);return event
        end})
        function fire(name)
            local callbacks={}
            for i,fn in ipairs(Events[name].callbacks)do callbacks[i]=fn end
            for _,fn in ipairs(callbacks)do fn()end
        end
        NMCore={NetModule='fixture',isSubsystemDebugEnabled=function()return true end,
            setSubsystemDebugEnabled=function()end,logBuildVersionLine=function()end,
            logChannel=function()end}
        function print()end
    ''')
    return lua


@unittest.skipUnless(LuaRuntime, 'Lua 5.1 runtime required: lupa.lua51')
class NewMusicAbsentTests(unittest.TestCase):
    def test_inactive_mod_does_not_require_upstream_or_register_callbacks(self):
        lua=runtime(active=False)
        lua.execute(SHARED_ENTRY.read_text())
        lua.execute(CLIENT_ENTRY.read_text())
        self.assertEqual(lua.eval('#required'),0)
        self.assertIsNone(lua.eval('NMRuntimeConfig'))
        self.assertIsNone(lua.eval('NMClientVanillaDiscVisibleProbe'))
        self.assertIsNone(lua.eval('next(Events)'))


@unittest.skipUnless(os.environ.get('PZ_NEWMUSIC_SOURCE'),
                     'external NewMusic input required: PZ_NEWMUSIC_SOURCE')
@unittest.skipUnless(LuaRuntime, 'Lua 5.1 runtime required: lupa.lua51')
class NewMusicRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=Path(os.environ['PZ_NEWMUSIC_SOURCE']).expanduser().resolve()
        if not cls.source.is_dir():
            raise AssertionError('PZ_NEWMUSIC_SOURCE must be a complete NewMusic mod directory')
        cls.original_hashes={p:digest(cls.source/p) for p in (CONFIG,CONVERTER,RESOLVER,CLIENT,PROBE_PATH,
            '42/media/lua/server/loot/NMLootRoutePlanner.lua',
            '42/media/lua/server/NMServerSandboxLootController.lua')}

    def runtime(self, client=False):
        lua=runtime(self.source)
        self.assertEqual(lua.eval('_VERSION'),'Lua 5.1')
        lua.execute(SHARED_ENTRY.read_text())
        if client: lua.execute(CLIENT_ENTRY.read_text())
        return lua

    def test_saved_sandbox_and_runtime_resync_cannot_enable_or_touch_inventory(self):
        lua=self.runtime()
        lua.execute('''
            accesses,resolutions=0,0
            NMLootDebugHelpers={resolveMutableContainer=function()
                resolutions=resolutions+1;error('disabled converter accessed inventory')end}
            bomb=setmetatable({}, {__index=function(_,key)
                accesses=accesses+1;error('disabled converter read '..tostring(key))end})
            context={shape='world',routeClass='fixture'}
        ''')
        lua.execute((self.source/CONVERTER).read_text())
        cases=('nil','{}','{NewMusic={}}','{NewMusic={ConvertVanillaCDsAndCDPlayers=true}}',
               '{NewMusic={ConvertVanillaCDsAndCDPlayers=false}}',
               '{NewMusic={ConvertVanillaCDsAndCDPlayers="true"}}')
        for sandbox in cases:
            with self.subTest(sandbox=sandbox):
                lua.execute('SandboxVars='+sandbox)
                for resync in ('','SandboxVars={NewMusic={ConvertVanillaCDsAndCDPlayers=true}}',
                               'NMRuntimeConfig.set("ConvertVanillaCDsAndCDPlayers",true)'):
                    lua.execute(resync)
                    self.assertFalse(lua.eval('NMRuntimeConfig.getConvertVanillaCDsAndCDPlayersEnabled()'))
                    self.assertFalse(lua.eval('NMVanillaCDLootConverter.isEnabled()'))
                    self.assertIsNone(lua.eval('NMVanillaCDLootConverter.processContainer(bomb,context)'))
        # A fresh source execution can redefine the getter; the boot/session
        # hooks restore policy before gameplay without recurring maintenance.
        for event in ('OnGameBoot','OnInitGlobalModData','OnGameStart','OnServerStarted'):
            lua.execute((self.source/CONFIG).read_text())
            lua.execute('fire("'+event+'")')
            self.assertFalse(lua.eval('NMRuntimeConfig.getConvertVanillaCDsAndCDPlayersEnabled()'))
            self.assertIsNone(lua.eval('NMVanillaCDLootConverter.processContainer(bomb,context)'))
        self.assertEqual(lua.eval('accesses'),0)
        self.assertEqual(lua.eval('resolutions'),0)
        for field in ('replaced','discarded','observedVanillaCDs','observedVanillaCDPlayers',
                      'cdPlayerReplaced','cdPlayerDiscarded'):
            self.assertEqual(lua.eval('NMVanillaCDLootConverter.getStats().'+field),0)

    def test_client_load_order_debug_and_repeat_install_preserve_other_events(self):
        for upstream_first in (False,True):
            with self.subTest(upstream_first=upstream_first):
                lua=runtime(self.source)
                lua.execute('''
                    otherTicks,otherRefreshes,accesses,rpc=0,0,0,0
                    otherTick=function()otherTicks=otherTicks+1 end
                    otherRefresh=function()otherRefreshes=otherRefreshes+1 end
                    Events.OnTick.Add(otherTick)
                    Events.OnRefreshInventoryWindowContainers.Add(otherRefresh)
                    function sendClientCommand()rpc=rpc+1 end
                    function getPlayerLoot()accesses=accesses+1;error('scan reached UI')end
                    function getPlayerInventory()accesses=accesses+1;error('scan reached UI')end
                    bomb=setmetatable({}, {__index=function()accesses=accesses+1;error('scan accessed page')end})
                    SandboxVars={NewMusic={ConvertVanillaCDsAndCDPlayers=true}}
                ''')
                if upstream_first:
                    lua.execute('require "core/NMRuntimeConfig"; require "runtime/NMClientVanillaDiscVisibleProbe"')
                lua.execute(SHARED_ENTRY.read_text())
                lua.execute(CLIENT_ENTRY.read_text())
                lua.execute('''
                    compatibility=PZSurvivorToolkit.NewMusicCompatibility
                    firstNoop=compatibility.noop;firstGetter=compatibility.disabled
                    for i=1,3 do
                        compatibility.installClient()
                        NMClientVanillaDiscVisibleProbe.scanVisibleLoot('debug')
                        NMClientVanillaDiscVisibleProbe.onRefreshInventoryWindowContainers(bomb,'end')
                        NMClientVanillaDiscVisibleProbe.onTick()
                    end
                    fire('OnGameBoot');fire('OnGameStart')
                    for i=1,601 do fire('OnTick')end
                    fire('OnRefreshInventoryWindowContainers')
                    assert(#Events.OnTick.callbacks==1 and Events.OnTick.callbacks[1]==otherTick)
                    assert(#Events.OnRefreshInventoryWindowContainers.callbacks==1
                        and Events.OnRefreshInventoryWindowContainers.callbacks[1]==otherRefresh)
                    assert(compatibility.sharedInstalled and compatibility.clientInstalled)
                    assert(NMClientVanillaDiscVisibleProbe.scanVisibleLoot==firstNoop)
                    assert(NMClientVanillaDiscVisibleProbe.onTick==firstNoop)
                    assert(NMRuntimeConfig.getConvertVanillaCDsAndCDPlayersEnabled==firstGetter)
                ''')
                self.assertEqual(lua.eval('accesses'),0)
                self.assertEqual(lua.eval('rpc'),0)
                self.assertEqual(lua.eval('otherTicks'),601)
                self.assertEqual(lua.eval('otherRefreshes'),1)
                before=lua.eval('#Events.OnGameStart.callbacks')
                lua.execute(SHARED_ENTRY.read_text());lua.execute(CLIENT_ENTRY.read_text())
                self.assertEqual(lua.eval('#Events.OnGameStart.callbacks'),before)

    def test_boot_reapply_removes_late_autoload_and_normal_main_stays_registered(self):
        lua=self.runtime(client=True)
        lua.execute((self.source/CONFIG).read_text())
        lua.execute((self.source/PROBE_PATH).read_text())
        lua.execute('''
            tickGates,mainRefreshes=0,0
            NMClientMainRuntime=setmetatable({registerTickGate=function()tickGates=tickGates+1 end,
                onRefreshInventoryWindowContainers=function()mainRefreshes=mainRefreshes+1 end},
                {__index=function()return function()end end})
            function sendClientCommand()end
            function isClient()return true end
            function isServer()return false end
        ''')
        lua.execute((self.source/CLIENT).read_text())
        lua.execute('''
            fire('OnGameBoot');fire('OnGameStart')
            NMDevicesClient.enableLootProbe()
            NMClientVanillaDiscVisibleProbe.scanVisibleLoot('debug')
            NMClientVanillaDiscVisibleProbe.onRefreshInventoryWindowContainers({},'end')
            for _,fn in ipairs(Events.OnRefreshInventoryWindowContainers.callbacks)do fn({},'end')end
            assert(#Events.OnRefreshInventoryWindowContainers.callbacks==1)
            assert(Events.OnRefreshInventoryWindowContainers.callbacks[1]
                ==NMClientMainRuntime.onRefreshInventoryWindowContainers)
            assert(#Events.OnTick.callbacks==0)
            assert(NMRuntimeConfig.getConvertVanillaCDsAndCDPlayersEnabled()==false)
        ''')
        self.assertEqual(lua.eval('tickGates'),1)
        self.assertEqual(lua.eval('mainRefreshes'),1)

    def test_incompatible_upstream_api_fails_clearly_without_claiming_success(self):
        lua=self.runtime(client=True)
        lua.execute('NMRuntimeConfig.getConvertVanillaCDsAndCDPlayersEnabled=nil')
        with self.assertRaisesRegex(Exception,'Incompatible NewMusic conversion API:.*getter|Incompatible NewMusic conversion API: getConvert'):
            lua.execute('PZSurvivorToolkit.NewMusicCompatibility.installShared()')
        self.assertFalse(lua.eval('PZSurvivorToolkit.NewMusicCompatibility.sharedInstalled'))
        lua.execute((self.source/CONFIG).read_text())
        lua.execute('NMClientVanillaDiscVisibleProbe.scanVisibleLoot=nil')
        with self.assertRaisesRegex(Exception,'visible-loot probe entrypoints missing'):
            lua.execute('PZSurvivorToolkit.NewMusicCompatibility.installClient()')
        self.assertFalse(lua.eval('PZSurvivorToolkit.NewMusicCompatibility.clientInstalled'))

    def test_original_placeholder_resolver_preserves_all_media_device_categories(self):
        # Keep the original resolver body; configure one deterministic candidate
        # per category/route and use minimal mutable container/item doubles.
        lua = self.runtime()
        lua.execute('''
            NMManagedSpawnCatalog={};NMLootResolvedPools={}
            NMWorldItemVisuals=nil
            NMLootDebugHelpers={resolveMutableContainer=function(c)return c,c:getItems()end,
                logLoot=function()end,formatContainerContext=function()return 'fixture'end}
            function ZombRandFloat(lo,hi)return lo end
            function makeItem(fullType)
                local item={fullType=fullType,modData={}}
                function item:getFullType()return self.fullType end
                function item:getModData()return self.modData end
                return item
            end
            function makeContainer(input)
                local c={values=input,added=0,removed=0}
                local items={}
                function items:size()return #c.values end
                function items:get(index)return c.values[index+1]end
                function c:getItems()return items end
                function c:AddItem(fullType)
                    local item=makeItem(fullType);self.values[#self.values+1]=item
                    self.added=self.added+1;return item
                end
                function c:DoRemoveItem(item)
                    for i,value in ipairs(self.values)do
                        if value==item then table.remove(self.values,i);self.removed=self.removed+1;return end
                    end
                    error('removed item was not present')
                end
                return c
            end
        ''')
        lua.execute((self.source / RESOLVER).read_text())
        lua.execute('''
            resolver=NMLootPlaceholderResolver
            media={'cassettes','cds','vinyl'}
            devices={'walkman','cdplayer','boombox','recordplayer'}
            config={routes={},policy={casesEnabled=true,ostEnabled=true},cacheKey='fixture',
                realizationAuthority={profiles={fixture={attempts={{route='standard',kind='media',maxAdds=1}}}}}}
            for _,route in ipairs({'standard','topUp'})do
                local bucket={media={},devices={}};config.routes[route]=bucket
                for _,category in ipairs(media)do bucket.media[category]={{spawnFullType='Fixture.'..category,variantWeight=1}}end
                for _,category in ipairs(devices)do bucket.devices[category]={{spawnFullType='Fixture.'..category,variantWeight=1}}end
            end
            resolver.configure(config)
            exercised=0
            for _,route in ipairs({'standard','topUp'})do
                local values={};local expected={}
                local vanillaDisc=makeItem('Base.Disc_Retail')
                local vanillaPlayer=makeItem('Base.CDplayer')
                local ordinary=makeItem('Base.WaterBottle')
                local existingMusic=makeItem('NewMusic.AlreadyResolved')
                values={vanillaDisc,vanillaPlayer,ordinary,existingMusic}
                for _,category in ipairs(media)do
                    values[#values+1]=makeItem(assert(resolver.getMediaPlaceholderFullType(category,route)))
                    expected['Fixture.'..category]=true
                end
                for _,category in ipairs(devices)do
                    values[#values+1]=makeItem(assert(resolver.getDevicePlaceholderFullType(category,route)))
                    expected['Fixture.'..category]=true
                end
                local container=makeContainer(values)
                assert(resolver.replacePlaceholdersInContainer(container,{routeClass='fixture',shape='world'})==7)
                assert(container.added==7 and container.removed==7 and #container.values==11)
                assert(container.values[1]==vanillaDisc and container.values[2]==vanillaPlayer
                    and container.values[3]==ordinary and container.values[4]==existingMusic)
                for i=5,#container.values do
                    local item=container.values[i];assert(expected[item:getFullType()])
                    expected[item:getFullType()]=nil
                    assert(item:getModData().nmLootResolved==true)
                    assert(item:getModData().nmLootSource==route)
                end
                assert(next(expected)==nil)
                assert(resolver.replacePlaceholdersInContainer(container,{routeClass='fixture'})==0)
                assert(container.added==7 and container.removed==7)
                exercised=exercised+7
            end
        ''')
        self.assertEqual(lua.eval('exercised'), 14)
        self.assertEqual(lua.eval('resolver.getReplacementStats().failed'), 0)

    def test_workshop_sources_are_unchanged(self):
        self.runtime(client=True)
        for relative,expected in self.original_hashes.items():
            with self.subTest(path=relative):
                self.assertEqual(digest(self.source/relative),expected)


if __name__ == '__main__':
    unittest.main()
