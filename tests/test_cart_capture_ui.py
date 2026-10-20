"""Disposable capture controls use the native common UI toggle without saving preferences."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT/'tests/native_queue/contributions/wooden_cart_motion/bootstrap.lua'
GAME = Path(os.environ.get('PZ_GAME', str(Path.home()/'Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java')))
NATIVE = GAME/'media/lua/client/ISUI/ISUIHandler.lua'
LUA = shutil.which('luajit')


@unittest.skipUnless(LUA and NATIVE.is_file(), 'Requires LuaJIT and native ISUIHandler.lua (PZ_GAME)')
class CaptureUIChecks(unittest.TestCase):
    def run_lua(self, checks, *, hide=None, bound=False):
        source=BOOTSTRAP.read_text()
        helper=source.split('-- Capture UI state begin:',1)[1].split('-- Capture UI state end.',1)[0]
        # The comment suffix preceding the first newline is not executable Lua.
        helper=helper.split('\n',1)[1]
        key_handler='CartLabKey=function'+source.split('CartLabKey=function',1)[1].split('Events.OnKeyPressed.Add(CartLabKey)',1)[0]
        initial=next(line for line in source.splitlines() if line=='cartLabCaptureUI(config.hideUI~=false)')
        setup=r'''
            config={disposable=true};world='CartTestArea';client=false;server=false;nativeVisible=true;renderHidden=false
            nativeCalls=0;renderCalls=0;bindingConflict=false;timed=true
            Keyboard={KEY_F5=63,KEY_F6=64,KEY_F7=65,KEY_F8=66,KEY_F9=67}
            local callbacks={}
            Events={}
            for _,name in ipairs({'OnGameStart','OnTick','OnMainMenuEnter'}) do
                local values={};callbacks[name]=values
                Events[name]={Add=function(fn) values[#values+1]=fn end,
                    Remove=function(fn) for i=#values,1,-1 do if values[i]==fn then table.remove(values,i) end end end}
            end
            function fire(name) local copy={};for i,fn in ipairs(callbacks[name]) do copy[i]=fn end;for _,fn in ipairs(copy) do fn() end end
            function count(name) return #callbacks[name] end
            function table.wipe(values) for key in pairs(values) do values[key]=nil end end
            function make(name,visible)
                return {visible=visible,isVisible=function(self) return self.visible end,
                    setVisible=function(self,value) self.visible=value end,toString=function() return name end}
            end
            inventory=make('inventory',true);silhouette=make('silhouette',true);hud=make('hud',true);closed=make('closed',false)
            elements={inventory,silhouette,hud,closed}
            UIManager={getUI=function() return {size=function() return #elements end,get=function(_,i) return elements[i+1] end} end,
                setVisibleAllUI=function(value) nativeVisible=value;nativeCalls=nativeCalls+1 end}
            function cartLabCaptureUIKeyBound(key) assert(key==Keyboard.KEY_F9);return bindingConflict end
            function getWorld() return {getWorld=function() return world end} end
            function isClient() return client end
            function isServer() return server end
            function isIngameState() return true end
            function cartLabCaptureUIVisible() return nativeVisible end
            function cartLabCaptureUIRender(value) renderHidden=value;renderCalls=renderCalls+1 end
            function require(name) assert(name=='ISUI/ISUIHandler') end
            local finished=true
            local player={hasTimedActions=function() return timed end}
            function equip() error('UI toggle must not change cart/equipment') end
        '''
        script=setup+'\ndofile('+json.dumps(str(NATIVE))+')\n'
        script+=f'config.hideUI={"nil" if hide is None else str(hide).lower()};bindingConflict={str(bound).lower()}\n'
        script+='function loadCaptureUI()\n'+helper+'\nend\nloadCaptureUI()\n'+key_handler+'\n'+initial+'\n'+checks
        result=subprocess.run([LUA,'-'],input=script,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_default_hidden_and_toggle_during_native_action_restores_exact_visibility(self):
        self.run_lua('''
            assert(CartLabCaptureUIHidden and renderHidden and not nativeVisible and not ISUIHandler.allUIVisible)
            assert(not inventory.visible and not silhouette.visible and not hud.visible and not closed.visible)
            assert(CartLabCaptureUIKey==Keyboard.KEY_F9)
            -- F8 belongs to PeekAView and must not be captured or rebound.
            CartLabKey(Keyboard.KEY_F8);assert(renderHidden)
            CartLabKey(Keyboard.KEY_F9)
            assert(not renderHidden and nativeVisible and ISUIHandler.allUIVisible)
            assert(inventory.visible and silhouette.visible and hud.visible and not closed.visible)
            assert(#ISUIHandler.visibleUI==0)
        ''')

    def test_explicit_visible_config_does_not_mutate_existing_ui(self):
        self.run_lua('''
            assert(not CartLabCaptureUIHidden and not renderHidden and nativeVisible)
            assert(nativeCalls==0 and inventory.visible and not closed.visible)
        ''',hide=False)

    def test_future_panels_and_programmatic_callbacks_work_behind_render_gate(self):
        self.run_lua('''
            local popup=make('programmatic menu',true);elements[#elements+1]=popup
            local performed=false;local option={onSelect=function() performed=true end}
            option.onSelect();assert(performed and renderHidden)
            assert(popup.visible) -- native update/public menu state stays available; only rendering is gated
            cartLabCaptureUI(false);assert(popup.visible and not renderHidden and inventory.visible)
        ''')

    def test_menu_world_change_and_reload_restore_visibility_without_callback_leaks(self):
        self.run_lua('''
            loadCaptureUI();assert(not renderHidden and inventory.visible and count('OnTick')==1 and count('OnMainMenuEnter')==1)
            cartLabCaptureUI(true);world='PersonalSave';fire('OnTick')
            assert(not renderHidden and inventory.visible and count('OnTick')==0)
            assert(not pcall(cartLabCaptureUI,true))
            world='CartTestArea';cartLabCaptureUI(true);fire('OnMainMenuEnter')
            assert(not renderHidden and inventory.visible and not closed.visible)
        ''')

    def test_binding_conflict_disables_fixture_hotkey_without_disabling_callable(self):
        self.run_lua('''
            assert(CartLabCaptureUIKey==nil and renderHidden)
            CartLabKey(Keyboard.KEY_F9);assert(renderHidden)
            cartLabCaptureUI(false);assert(not renderHidden and nativeVisible)
            assert(not pcall(cartLabCaptureUI,1))
        ''',bound=True)


if __name__=='__main__': unittest.main()
