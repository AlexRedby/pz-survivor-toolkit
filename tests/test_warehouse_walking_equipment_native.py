"""Opt-in bytecode contract for silent native fixture clothing transitions.

PZ_NATIVE_WALKING_EQUIPMENT_CHECK=1 PZ_GAME=/path/to/game/Java python3 -m unittest
    tests.test_warehouse_walking_equipment_native

Reads javap output only: no compilation, game launch, installation or API patch.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest


@unittest.skipUnless(os.environ.get('PZ_NATIVE_WALKING_EQUIPMENT_CHECK') == '1',
                     'opt-in installed native equipment bytecode contract')
class NativeEquipmentBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        game = Path(os.environ['PZ_GAME'])
        javap = str(Path(os.environ['PZ_JDK'])/'bin/javap') if os.environ.get('PZ_JDK') else shutil.which('javap')
        if not javap:
            raise RuntimeError('javap unavailable')
        cls.code = {}
        for name in ('zombie.characters.IsoGameCharacter', 'zombie.characters.WornItems.WornItems',
                     'zombie.Lua.LuaManager$Exposer', 'zombie.network.packets.SyncClothingPacket',
                     'zombie.scripting.objects.ItemBodyLocation', 'zombie.iso.IsoCell'):
            cls.code[name] = subprocess.run([javap, '-classpath', str(game/'projectzomboid.jar'), '-p', '-c', name],
                                            check=True, capture_output=True, text=True).stdout

    def method(self, owner, signature):
        code = self.code[owner]
        start = code.index('  ' + signature + ';\n')
        tail = code[start + len('  ' + signature + ';\n'):]
        next_method = re.search(r'^  (?:public|protected|private|static) ', tail, re.M)
        return tail[:next_method.start()] if next_method else tail

    def test_standard_setter_sends_and_packets_can_recreate_orphan_clothes(self):
        setter = self.method('zombie.characters.IsoGameCharacter',
                             'public void setWornItem(zombie.scripting.objects.ItemBodyLocation, zombie.inventory.InventoryItem, boolean)')
        self.assertIn('PacketTypes$PacketType.SyncClothing', setter)
        self.assertIn('INetworkPacket.send:', setter)
        self.assertIn('INetworkPacket.sendToAll:', setter)
        packet = self.method('zombie.network.packets.SyncClothingPacket', 'private void process()')
        self.assertIn('WornItems.remove:', packet)
        self.assertIn('InventoryItemFactory.CreateItem:', packet)
        self.assertIn('InventoryItem.setID:', packet)

    def test_bulk_clear_and_low_level_set_are_silent_and_update_required_caches(self):
        clear = self.method('zombie.characters.IsoGameCharacter', 'public void clearWornItems()')
        self.assertIn('WornItems.clear:', clear)
        self.assertIn('ClothingWetness.changed:', clear)
        self.assertIn('onWornItemsChanged:', clear)
        methods = [clear,
                   self.method('zombie.characters.WornItems.WornItems', 'public void clear()'),
                   self.method('zombie.characters.WornItems.WornItems',
                               'public void setItem(zombie.scripting.objects.ItemBodyLocation, zombie.inventory.InventoryItem)'),
                   self.method('zombie.characters.IsoGameCharacter', 'public void onWornItemsChanged()'),
                   self.method('zombie.characters.IsoGameCharacter', 'public void OnClothingUpdated()'),
                   self.method('zombie.characters.IsoGameCharacter', 'public void resetModelNextFrame()')]
        for method in methods:
            self.assertNotRegex(method, r'// (?:Interface)?Method zombie/network/')
            self.assertNotIn('setWornItem:', method)
        exposed = self.code['zombie.Lua.LuaManager$Exposer']
        self.assertIn('class zombie/characters/WornItems/WornItems', exposed)
        self.assertIn('class zombie/characters/IsoGameCharacter', exposed)
        self.assertIn('class zombie/iso/IsoCell', exposed)

    def test_process_queues_and_registry_slot_strings_have_no_transport(self):
        for signature in ('public void addToProcessItems(zombie.inventory.InventoryItem)',
                          'public void addToProcessItemsRemove(zombie.inventory.InventoryItem)'):
            method = self.method('zombie.iso.IsoCell', signature)
            self.assertNotRegex(method, r'// (?:Interface)?Method zombie/network/')
        location = self.method('zombie.scripting.objects.ItemBodyLocation', 'public java.lang.String toString()')
        self.assertIn('Registry.getLocation:', location)
        self.assertIn('ResourceLocation.toString:', location)
        self.assertNotIn('getTranslationName:', location)


if __name__ == '__main__':
    unittest.main()
