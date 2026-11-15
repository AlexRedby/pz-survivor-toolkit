"""Saved-world witness verifies identity; engine collections are explicit doubles."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from lupa.lua51 import LuaRuntime
from tools.queue_checks.adapters import startup

ROOT = Path(__file__).resolve().parents[1]
WITNESS = {'name': 'Saved Survivor', 'items': [
    {'id': 10, 'fullType': 'Base.Bag', 'parent': 'root', 'count': 1},
    {'id': 20, 'fullType': 'Base.Book', 'parent': 10, 'count': 1}],
    'primary': False, 'secondary': False, 'worn': [{'id': 10, 'location': 'Back'}]}


class StartupWorldTests(unittest.TestCase):
    def selection(self, expected):
        return {'suite': 'startup', 'cases': ['loaded'], 'kind': 'mp', 'mode': 'toolkit',
                'clients': 1, 'languages': ['EN'], 'mods': ['PZSurvivorToolkit'],
                'options': {'mp_host': True, 'startup_world': expected}}

    def verify(self, value, expected=None, before_ready=False, native_prefix=False):
        row = '[STARTUP_TEST] WORLD_WITNESS ' + json.dumps(value) + '\n'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            text = ('[QUEUE_TEST] NATIVE_CONNECTED\n[QUEUE_TEST] PREFLIGHT_COMPLETE mods=1 mode=toolkit\n'
                    '[STARTUP_TEST] GAME_START kind=mp mode=toolkit\n')
            ready = '[STARTUP_TEST] PLAYER_READY square=1,2,0 tick=true\n'
            text += row + ready if before_ready else ready + row
            text += '[STARTUP_TEST] COMPLETE case=loaded\n'
            if native_prefix:
                text = ''.join('LOG : General f:0> ' + line + '\n' for line in text.splitlines())
            (root / 'client1-launch.log').write_text(text)
            (root / 'server-launch.log').write_text('[STARTUP_TEST] SERVER_READY\n')
            return startup.verify(root, self.selection(expected or WITNESS), {})

    def test_named_capture_and_exact_inventory_comparison(self):
        for expected in (WITNESS, {'name': WITNESS['name']}):
            startup.validate(self.selection(expected))
            result = self.verify(WITNESS, expected)
            self.assertEqual(result['issues'], [])
            self.assertEqual(result['evidence']['world_witness'], WITNESS)
        reordered = copy.deepcopy(WITNESS)
        reordered['items'].reverse()
        self.assertEqual(self.verify(reordered)['issues'], [])
        for changed in ('name', 'items', 'primary', 'worn'):
            row = copy.deepcopy(WITNESS)
            if changed == 'name': row[changed] = 'New Survivor'
            elif changed == 'primary': row[changed] = 20
            else: row[changed] = []
            self.assertTrue(self.verify(row)['issues'], changed)
        self.assertTrue(self.verify(WITNESS, before_ready=True)['issues'])
        self.assertEqual(self.verify(WITNESS, native_prefix=True)['issues'], [])

    def test_invalid_selection_and_missing_item_references_are_rejected(self):
        for value in ({}, {'name': ''}, {'name': 'bad\nname'}, dict(WITNESS, primary=True),
                      dict(WITNESS, secondary=99), dict(WITNESS, items=WITNESS['items'] * 2),
                      dict(WITNESS, worn=[{'id': 99, 'location': 'Back'}])):
            with self.subTest(value=value), self.assertRaises(ValueError):
                startup.validate(self.selection(value))
        selection = self.selection(WITNESS)
        selection['options']['mp_host'] = False
        with self.assertRaises(ValueError): startup.validate(selection)
        for parent in (10, 20):
            value = copy.deepcopy(WITNESS)
            value['items'][0]['parent'] = parent
            with self.assertRaises(ValueError): startup.validate(self.selection(value))

    def test_capture_preserves_nested_ids_counts_and_equipment(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
            function list(values)return {size=function()return #values end,get=function(_,i)return values[i+1]end}end
            function item(id,fullType,children)
                return {id=id,getID=function()return id end,getFullType=function()return fullType end,
                    getCount=function()return 1 end,bag=children~=nil,
                    getInventory=function()return {getItems=function()return list(children)end}end}
            end
            instanceof=function(value,name)return name=='InventoryContainer'and value.bag end
            book=item(20,'Base.Book');bag=item(10,'Base.Bag',{book})
            player={getDescriptor=function()return {getForename=function()return 'Saved'end,getSurname=function()return 'Survivor'end}end,
                getInventory=function()return {getItems=function()return list({bag})end}end,
                getPrimaryHandItem=function()end,getSecondaryHandItem=function()end,
                getWornItems=function()return list({{getItem=function()return bag end,getLocation=function()return 'Back'end}})end}
        ''')
        lua.globals().capture = lua.execute((ROOT / 'tests/native_queue/support/QueueStartupWorld.lua').read_text())
        lua.globals().JSON = lua.execute((ROOT / 'tests/native_queue/health/shared/QueueHealthEvents.lua').read_text())
        self.assertEqual(json.loads(lua.eval('JSON.encode(capture.capture(player))')), WITNESS)
        lua.execute("outside=item(20,'Base.Axe');player.getPrimaryHandItem=function()return outside end")
        with self.assertRaises(Exception): lua.eval('capture.capture(player)')
        lua.execute('player.getPrimaryHandItem=function()end')
        lua.execute("player.getWornItems=function()return list({{getItem=function()return outside end,getLocation=function()return 'Back'end}})end")
        with self.assertRaises(Exception): lua.eval('capture.capture(player)')
        lua.execute("player.getWornItems=function()return list({})end")
        lua.execute('book.getID=function()return 10 end')
        with self.assertRaises(Exception): lua.eval('capture.capture(player)')

    def test_recovery_probe_stages_only_immutable_lua_not_mutable_preferences(self):
        selection = self.selection(WITNESS)
        selection['mods'] += ['PeekAView', 'SaucedCarts']
        selection['options']['startup_recovery_probe'] = True
        startup.validate(selection)
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / 'client1'
            runtime = {'roles': {'client1': {'cache': str(cache)}}}
            startup.stage(ROOT, Path(directory), None, None, selection, {}, runtime)
            lua = cache / 'mods/ActionQueueTest/42/media/lua'
            self.assertTrue((lua / 'client/00000QueueStartupRecoverySeed.lua').is_file())
            self.assertIn('SEALED|', (lua / 'shared/QueueStartupRecoveryConfig.lua').read_text())
            self.assertFalse((cache / 'Lua/ModOptions.ini').exists())
        selection['mods'].remove('PeekAView')
        with self.assertRaises(ValueError): startup.validate(selection)


if __name__ == '__main__':
    unittest.main()
