"""Cart E arbitration with the installed SaucedCarts producer and Lua 5.1.

The Java player-update fixture models the B42.21 bytecode ordering; this does
not replace an in-game check of movement, animation, or Host replication.
"""
import os
from pathlib import Path
import unittest

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "PZSurvivorToolkit/42/media/lua/client"
WORKSHOP = Path(os.environ.get("PZ_WORKSHOP", str(
    Path.home() / "Library/Application Support/Steam/steamapps/workshop/content/108600")))
UPSTREAM = Path(os.environ.get("PZ_SAUCEDCARTS_HOTKEYS", str(
    WORKSHOP / "3651954650/mods/SaucedCarts/42/media/lua/client/SaucedCarts/Hotkeys.lua")))


@unittest.skipUnless(LuaRuntime is not None and UPSTREAM.is_file(),
                     "Requires Lupa Lua51 and installed SaucedCarts (PZ_SAUCEDCARTS_HOTKEYS)")
class CartHotkeysTests(unittest.TestCase):
    def boot(self, upstream_first=False, enabled=True, cart_state_listener=False):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(r'''
            logs = {}; modules = {}; sources = {}; nativeContexts = 0
            Keyboard = {KEY_E=18, KEY_V=47}; KeybindId = {INTERACT='Interact'}
            physical = {}; interactKey = 18; settingsCalls = 0
            getText = function(text) return text end
            isServer = function() return false end
            isClient = function() return false end
            print = function(text) logs[#logs+1] = text end
            Events = {}
            for _, name in ipairs({'OnKeyStartPressed', 'OnGameStart', 'OnPlayerUpdate',
                    'OnTick', 'OnTickEvenPaused', 'OnPlayerDeath', 'OnMainMenuEnter'}) do
                local callbacks = {}
                Events[name] = {callbacks=callbacks,
                    Add=function(callback)
                        for _, old in ipairs(callbacks) do if old == callback then return end end
                        callbacks[#callbacks+1] = callback
                    end,
                    Remove=function(callback)
                        for i=#callbacks,1,-1 do
                            if callbacks[i] == callback then table.remove(callbacks,i) end
                        end
                    end}
            end
            function fire(name, value)
                for _, callback in ipairs(Events[name].callbacks) do callback(value) end
            end
            local externalModules = {
                ['TimedActions/ISTimedActionQueue']=true,
                ['SaucedCarts/Core']=true, ['SaucedCarts/CartData']=true,
                ['SaucedCarts/CorpseStorage']=true,
                ['SaucedCarts/TimedActions/ISCartPickupAction']=true,
                ['SaucedCarts/TimedActions/ISCartEquipAction']=true,
                ['SaucedCarts/TimedActions/ISCartLoadCorpseAction']=true,
                ['TimedActions/ISDropWorldItemAction']=true}
            function require(name)
                if modules[name] ~= nil then return modules[name] end
                if sources[name] then
                    local result = assert(loadstring(sources[name], '@' .. name))()
                    modules[name] = result or true
                elseif externalModules[name] then
                    modules[name] = true
                else
                    error('Fixture must explicitly provide required module: ' .. name)
                end
                return modules[name]
            end
            binding = {value=18, defaultkey=47,
                getValue=function(self) return self.value end,
                setValue=function(self,value) self.value=value end}
            options = {addKeyBind=function() return binding end,
                       getOption=function() return binding end}
            PZAPI = {ModOptions={create=function() return options end,
                                getOptions=function() return options end}}
            modules['PZSurvivorToolkit/CartKeySettings'] = {
                configureDefault=function() end,
                migrate=function() settingsCalls=settingsCalls+1; return true, 'preserved' end}
            getCore = function() return {isKey=function(_,id,key) return id=='Interact' and key==interactKey end} end
            isKeyDown = function(key) return physical[key] or false end
            activeMods = true
            getActivatedMods = function() return {contains=function() return activeMods end} end
            SandboxVars = {SaucedCarts={EnableMod=true}}
            function list(values)
                return {size=function() return #values end, get=function(_,i) return values[i+1] end}
            end
            function cart(id)
                return {cart=true, id=id or 1, getID=function(self) return self.id end}
            end
            ground = {}; walkAllowed=true; insertWalk=true
            origin = {getX=function() return 0 end, getY=function() return 0 end,
                      getZ=function() return 0 end, canReachTo=function() return true end}
            function putGroundCart(x,y,item)
                local square = {getWorldObjects=function() return list({ground.object}) end}
                ground = {x=x,y=y,square=square,object={world=true,
                    getItem=function() return item end, getSquare=function() return square end}}
            end
            getCell = function() return {getGridSquare=function(_,x,y,z)
                if ground.x==x and ground.y==y and z==0 then return ground.square end
            end} end
            instanceof = function(object, kind) return kind=='IsoWorldInventoryObject' and object.world end
            function newPlayer()
                return {ignore=false, dead=false, vehicle=nil, items={}, queue={},
                    interact=false, timePressedContext=0, pressContext=false,
                    isIgnoreContextKey=function(self) return self.ignore end,
                    setIgnoreContextKey=function(self,value) self.ignore=value end,
                    isDead=function(self) return self.dead end,
                    getVehicle=function(self) return self.vehicle end,
                    isInteractButtonDown=function(self) return self.interact end,
                    getCurrentSquare=function(self) if not self.noSquare then return origin end end,
                    getPrimaryHandItem=function(self) return self.primary end,
                    isDraggingCorpse=function(self) return self.dragging end,
                    getInventory=function(self) return {getItems=function() return list(self.items) end} end}
            end
            player = newPlayer(); currentPlayer=player
            getSpecificPlayer = function(index) assert(index==0); return currentPlayer end
            ISTimedActionQueue = {
                getTimedActionQueue=function(character) return {queue=character.queue} end,
                add=function(action) table.insert(action.character.queue, action) end}
            luautils = {walkAdj=function(character)
                if not walkAllowed then return false end
                if insertWalk then table.insert(character.queue,{Type='ISWalkToTimedAction',character=character}) end
                return true
            end}
            ISCartPickupAction = {FromWorldItem=function(character,object)
                return {Type='ISCartPickupAction',character=character,worldItem=object}
            end}
            ISCartEquipAction = {FromCart=function(character,item)
                return {Type='ISCartEquipAction',character=character,item=item}
            end}
            ISCartLoadCorpseAction = {new=function(_,character,item)
                return {Type='ISCartLoadCorpseAction',character=character,item=item}
            end}
            ISDropWorldItemAction = {new=function(_,character,item)
                return {Type='ISDropWorldItemAction',character=character,item=item}
            end}
            corpseEnabled=false; corpseAllowed=true
            SaucedCarts = {isCart=function(item) return item and item.cart end,
                debug=function(text) logs[#logs+1]=text end,
                CorpseStorage={isEnabled=function() return corpseEnabled end,
                    canLoadCorpseIntoCart=function() return corpseAllowed, 'cart full' end}}
            -- B42.21: keyboard event precedes player frameStep; OnPlayerUpdate
            -- precedes updateUseKey; OnTick follows the world/player updates.
            function press(key)
                key=key or 18; physical[key]=true
                fire('OnKeyStartPressed',key)
            end
            function release(key) physical[key or 18]=false end
            function frame(mode,dt)
                mode=mode or 'normal'; dt=dt or 0.05
                if mode=='paused' then fire('OnTickEvenPaused',0); return end
                local p=currentPlayer
                if p and mode~='missing' then
                    p.interact = isKeyDown(interactKey)
                    fire('OnPlayerUpdate',p)
                    if not p.dead and not p.vehicle then
                        if mode=='blocked' then
                            p.pressContext=false; p.timePressedContext=0
                        else
                            p.timePressedContext=p.timePressedContext+dt
                            if p.interact and p.timePressedContext<0.5 then
                                p.pressContext=true
                            else
                                if p.pressContext and not p.ignore then
                                    nativeContexts=nativeContexts+1
                                    p.pressContext=false; p.timePressedContext=0
                                end
                                if not p.interact then p.pressContext=false; p.timePressedContext=0 end
                            end
                        end
                    end
                end
                fire('OnTick',0)
            end
        ''')
        lua.globals().sources['SaucedCarts/Hotkeys'] = UPSTREAM.read_text()
        lua.globals().sources['PZSurvivorToolkit/CartHotkeys'] = (
            CLIENT / 'PZSurvivorToolkit/CartHotkeys.lua').read_text()
        lua.globals().activeMods = enabled
        if upstream_first:
            lua.execute("require 'SaucedCarts/Hotkeys'")
        lua.execute((CLIENT / '000ToolkitCartHotkeys.lua').read_text())
        if cart_state_listener:
            lua.execute('''
                -- CartStateHandler.lua registers at file load, after our early
                -- loader but before OnGameStart. Its verified held->empty
                -- transition defensively clears ignoreContextKey (lines 199-203).
                local held = {}
                upstreamContextClears = 0
                Events.OnPlayerUpdate.Add(function(character)
                    local primary = character:getPrimaryHandItem()
                    local hasCart = primary and SaucedCarts.isCart(primary) or false
                    if held[character] and not hasCart then
                        character:setIgnoreContextKey(false)
                        upstreamContextClears = upstreamContextClears + 1
                    end
                    held[character] = hasCart or nil
                end)
            ''')
        lua.execute("fire('OnGameStart')")
        return lua

    def assert_drained(self, lua, expected=False):
        lua.execute('release(); frame()')
        self.assertTrue(lua.eval('player.ignore'), 'first completed release update must remain ignored')
        self.assertEqual(lua.eval('player.timePressedContext'), 0)
        self.assertFalse(lua.eval('player.pressContext'))
        lua.execute('frame()')
        self.assertEqual(lua.eval('player.ignore'), expected)
        self.assertEqual(lua.eval('nativeContexts'), 0)

    def test_actual_producer_queues_pickup_equip_drop_and_corpse_load(self):
        cases = [
            ("putGroundCart(1,0,cart())", 'ISCartPickupAction', 2),
            ("player.items={cart()}", 'ISCartEquipAction', 1),
            ("player.primary=cart()", 'ISDropWorldItemAction', 1),
            ("player.primary=cart(); player.dragging=true; corpseEnabled=true", 'ISCartLoadCorpseAction', 1),
        ]
        for setup, action_type, count in cases:
            for upstream_first in (False, True):
                with self.subTest(action_type=action_type, upstream_first=upstream_first):
                    lua = self.boot(upstream_first)
                    lua.execute(setup + '; press(); frame()')
                    self.assertEqual(lua.eval('#player.queue'), count)
                    self.assertEqual(lua.eval('player.queue[#player.queue].Type'), action_type)
                    self.assertTrue(lua.eval('player.ignore'), 'before/upstream/after registration order failed')
                    self.assertEqual(lua.eval('#Events.OnKeyStartPressed.callbacks'), 3)
                    self.assert_drained(lua)

    def test_no_accepted_cart_keeps_native_interact_available(self):
        for setup in ('do end', 'SandboxVars.SaucedCarts.EnableMod=false', 'player.noSquare=true',
                      'putGroundCart(1,0,cart()); walkAllowed=false',
                      'player.primary=cart(); player.dragging=true',
                      'player.primary=cart(); player.dragging=true; corpseEnabled=true; corpseAllowed=false'):
            with self.subTest(setup=setup):
                lua = self.boot()
                lua.execute(setup + '; press(); frame(); release(); frame()')
                self.assertFalse(lua.eval('player.ignore'))
                self.assertEqual(lua.eval('#player.queue'), 0)
                self.assertEqual(lua.eval('nativeContexts'), 1)

    def test_hold_then_cancel_still_suppresses_native_release(self):
        lua = self.boot()
        lua.execute('player.items={cart()}; press(); frame(); player.queue={} '
                    'for i=1,20 do frame() end')
        self.assertEqual(lua.eval('nativeContexts'), 0)
        self.assertTrue(lua.eval('player.ignore'))
        self.assert_drained(lua)
        lua.execute('player.items={}; player.queue={}; press(); frame(); release(); frame()')
        self.assertEqual(lua.eval('nativeContexts'), 1, 'subsequent no-cart E must work normally')

    def test_upstream_unequip_clear_cannot_expose_held_drop_to_native_context(self):
        for previous in (False, True):
            with self.subTest(previous=previous):
                lua = self.boot(cart_state_listener=True)
                lua.globals().player.ignore = previous
                lua.execute('player.primary=cart(); frame(); press(); frame(); '
                            'player.primary=nil; for i=1,12 do frame() end')
                self.assertEqual(lua.eval('player.queue[1].Type'), 'ISDropWorldItemAction')
                self.assertEqual(lua.eval('upstreamContextClears'), 1,
                                 'fixture must run the upstream held-to-empty transition')
                self.assertEqual(lua.eval('nativeContexts'), 0,
                                 'upstream defensive clear must not open a door at the hold threshold')
                self.assertTrue(lua.eval('player.ignore'))
                self.assert_drained(lua, expected=previous)
                if not previous:
                    lua.execute('player.queue={}; press(); frame(); release(); frame()')
                    self.assertEqual(lua.eval('nativeContexts'), 1,
                                     'a later no-cart gesture must retain native interaction')
                    self.assertFalse(lua.eval('player.ignore'))

    def test_upstream_unequip_clear_on_release_is_reasserted_before_native_update(self):
        lua = self.boot(cart_state_listener=True)
        lua.execute('player.primary=cart(); frame(); press(); frame(); player.primary=nil')
        self.assert_drained(lua)
        self.assertEqual(lua.eval('upstreamContextClears'), 1)
        lua.execute('player.queue={}; press(); frame(); release(); frame()')
        self.assertEqual(lua.eval('nativeContexts'), 1)
        self.assertFalse(lua.eval('player.ignore'))

    def test_fast_repeat_renews_barrier_without_losing_original_ignore_value(self):
        for previous in (False, True):
            with self.subTest(previous=previous):
                lua = self.boot()
                lua.globals().player.ignore = previous
                lua.execute('player.items={cart()}; press(); frame(); release(); frame(); '
                            'player.queue={}; press(); frame()')
                self.assertEqual(lua.eval('#player.queue'), 1)
                self.assertTrue(lua.eval('player.ignore'))
                self.assert_drained(lua, expected=previous)

    def test_rejected_fast_repeat_after_drained_release_gets_native_fallback(self):
        lua = self.boot()
        lua.execute('player.items={cart()}; press(); frame(); release(); frame(); '
                    'player.queue={}; player.items={}; press(); frame(); release(); frame()')
        self.assertEqual(lua.eval('nativeContexts'), 1,
                         'new rejected E after completed native release must not inherit old capture')

    def test_repeat_before_any_native_release_update_keeps_continuous_hold_ignored(self):
        lua = self.boot()
        lua.execute('player.items={cart()}; press(); frame(); release(); '
                    'player.queue={}; player.items={}; press(); frame()')
        self.assertTrue(lua.eval('player.ignore'))
        self.assert_drained(lua)

    def test_missing_paused_and_vehicle_updates_do_not_drain_release(self):
        for mode in ('missing', 'paused', 'vehicle'):
            with self.subTest(mode=mode):
                lua = self.boot()
                lua.execute('player.items={cart()}; press(); frame(); release()')
                if mode == 'vehicle':
                    lua.execute('player.vehicle={}')
                lua.execute("for i=1,5 do frame('%s') end" % mode)
                self.assertTrue(lua.eval('player.ignore'))
                self.assertTrue(lua.eval('player.pressContext'), 'fixture must retain stale native context')
                lua.execute('player.vehicle=nil')
                self.assert_drained(lua)

    def test_missing_update_interrupts_consecutive_release_barrier(self):
        lua = self.boot()
        lua.execute("player.items={cart()}; press(); frame(); release(); frame(); frame('missing'); frame()")
        self.assertTrue(lua.eval('player.ignore'))
        lua.execute('frame()')
        self.assertFalse(lua.eval('player.ignore'))
        self.assertEqual(lua.eval('nativeContexts'), 0)

    def test_death_replacement_and_menu_restore_captured_player_only(self):
        for cleanup in ("player.dead=true; fire('OnPlayerDeath',player)",
                        'player.dead=true; frame()',
                        'currentPlayer=newPlayer(); frame()',
                        "fire('OnMainMenuEnter')"):
            with self.subTest(cleanup=cleanup):
                lua = self.boot()
                lua.execute('player.items={cart()}; press(); frame(); ' + cleanup)
                self.assertFalse(lua.eval('player.ignore'))
                self.assertFalse(lua.eval('currentPlayer.ignore'))

    def test_custom_bind_or_absent_upstream_does_not_capture_native_e(self):
        lua = self.boot()
        lua.execute('binding.value=47; player.items={cart()}; press(47); frame(); release(47); frame()')
        self.assertEqual(lua.eval('#player.queue'), 1)
        self.assertFalse(lua.eval('player.ignore'))
        lua = self.boot(enabled=False)
        self.assertEqual(lua.eval('#Events.OnKeyStartPressed.callbacks'), 0)
        self.assertEqual(lua.eval('settingsCalls'), 0)

    def test_busy_queue_and_non_cart_drop_are_not_claimed(self):
        lua = self.boot()
        lua.execute("player.items={cart()}; player.queue={{Type='ExistingAction',character=player}}; press(); frame()")
        self.assertFalse(lua.eval('player.ignore'))
        self.assertEqual(lua.eval('#player.queue'), 1)
        # Exercise observer classification without replacing the real producer.
        lua.execute("player.queue={}; hotkeys=require 'PZSurvivorToolkit/CartHotkeys'; "
                    "hotkeys.beforePress(18,binding); player.queue={{Type='ISDropWorldItemAction',character=player,item={}}}; "
                    'hotkeys.afterPress(18)')
        self.assertFalse(lua.eval('player.ignore'))

    def test_toolkit_action_variants_from_cart_factory_are_claimed(self):
        for action_type, marker in (
                ('ToolkitWoodCartPickup', False), ('ToolkitWoodCartDrop', False),
                ('ToolkitWoodCartSetdown', False), ('CustomCartAction', True)):
            with self.subTest(action_type=action_type, marker=marker):
                lua = self.boot()
                lua.globals().actionType = action_type
                lua.globals().useMarker = marker
                lua.execute('''
                    player.items={cart()}
                    ISCartEquipAction.FromCart=function(character,item)
                        return {Type=actionType,character=character,
                            toolkitWoodCartItem=useMarker and item or nil}
                    end
                    press(); frame()
                ''')
                self.assertTrue(lua.eval('player.ignore'))
                self.assert_drained(lua)

    def test_foreign_character_and_non_cart_marker_do_not_capture(self):
        for action in ("{Type='ISCartEquipAction',character=newPlayer()}",
                       "{Type='CustomCartAction',character=player,toolkitWoodCartItem={}}"):
            with self.subTest(action=action):
                lua = self.boot()
                lua.execute("hotkeys=require 'PZSurvivorToolkit/CartHotkeys'; "
                            'hotkeys.beforePress(18,binding); player.queue={' + action + '}; '
                            'hotkeys.afterPress(18)')
                self.assertFalse(lua.eval('player.ignore'))


if __name__ == '__main__':
    unittest.main()
