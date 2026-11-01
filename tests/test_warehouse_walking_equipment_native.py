"""Opt-in bytecode contracts for fixture equipment, allocation and cleanup.

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
                     'zombie.scripting.objects.ItemBodyLocation', 'zombie.iso.IsoCell',
                     'zombie.Lua.LuaManager$GlobalObject', 'zombie.inventory.InventoryItemFactory',
                     'zombie.inventory.ItemContainer',
                     'zombie.network.packets.RemoveInventoryItemFromContainerPacket',
                     'zombie.network.packets.RemoveItemFromSquarePacket'):
            options = ['-v'] if name == 'zombie.Lua.LuaManager$GlobalObject' else []
            cls.code[name] = subprocess.run([javap, '-classpath', str(game/'projectzomboid.jar'), '-p', '-c', *options, name],
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

    def test_detached_factory_has_a_lua_global_and_keeps_native_random_ids(self):
        entry = self.method('zombie.Lua.LuaManager$GlobalObject',
                            'public static zombie.inventory.InventoryItem instanceItem(java.lang.String)')
        self.assertIn('InventoryItemFactory.CreateItem:(Ljava/lang/String;)', entry)
        self.assertRegex(entry, r'LuaMethod\(\s+name="instanceItem"\s+global=true')
        factory = self.method('zombie.inventory.InventoryItemFactory',
                              'private static zombie.inventory.InventoryItem createItemInternal(java.lang.String, float, boolean, boolean)')
        self.assertRegex(factory, r'int 2146250223\s+\d+: invokestatic\s+#[0-9]+\s+// Method zombie/core/random/Rand.Next:\(I\)I\s+\d+: ldc\s+#[0-9]+\s+// int 1233423\s+\d+: iadd\s+\d+: putfield\s+#[0-9]+\s+// Field zombie/inventory/InventoryItem.id:I')
        self.assertNotIn('ItemContainer.', factory)
        self.assertNotIn('InventoryItem.container:', factory)
        self.assertNotIn('INetworkPacket.send', factory)

    def test_object_insertion_checks_id_before_attaching_and_returns_exact_object(self):
        add = self.method('zombie.inventory.ItemContainer',
                          'public zombie.inventory.InventoryItem AddItem(zombie.inventory.InventoryItem)')
        self.assertLess(add.index('Method containsID:'), add.index('Field zombie/inventory/InventoryItem.container:'))
        self.assertIn('Method getItemWithID:', add)
        self.assertRegex(add, r'aload_1\s+\d+: aload_0\s+\d+: putfield\s+#[0-9]+\s+// Field zombie/inventory/InventoryItem.container:')
        self.assertRegex(add, r'aload_1\s+\d+: areturn\s*$')
        self.assertNotIn('InventoryItemFactory.CreateItem:', add)
        self.assertNotIn('InventoryItem.setID:', add)
        self.assertNotIn('INetworkPacket.send', add)
        text_add = self.method('zombie.inventory.ItemContainer',
                               'public zombie.inventory.InventoryItem AddItem(java.lang.String)')
        self.assertIn('InventoryItemFactory.CreateItem:', text_add)
        self.assertIn('Field zombie/inventory/InventoryItem.container:', text_add)
        self.assertNotIn('Method containsID:', text_add)

    def test_item_removal_hook_precedes_list_removal_and_direct_pointer_clear(self):
        remove = self.method('zombie.inventory.ItemContainer',
                             'public void Remove(zombie.inventory.InventoryItem)')
        hook = remove.index('InventoryItem.OnBeforeRemoveFromContainer:')
        mutation = remove.index('java/util/ArrayList.remove:(I)')
        clear = remove.index('Field zombie/inventory/InventoryItem.container:')
        self.assertLess(hook, mutation)
        self.assertLess(mutation, clear)
        # No callback or setter can throw between the successful list mutation
        # and the direct null assignment. Physical reconciliation still checks
        # both the list and pointer, rather than relying on this order alone.
        self.assertRegex(remove, r'ArrayList.remove:\(I\)Ljava/lang/Object;\s+'
                         r'\d+: pop\s+\d+: aload_1\s+\d+: aconst_null\s+'
                         r'\d+: putfield\s+#[0-9]+\s+// Field zombie/inventory/InventoryItem.container:')
        self.assertNotIn('INetworkPacket.send', remove)

    def test_inventory_remove_notice_uses_id_and_missing_id_is_a_noop(self):
        packet = self.method('zombie.network.packets.RemoveInventoryItemFromContainerPacket',
                             'public void processClient(zombie.core.raknet.UdpConnection)')
        self.assertIn('ContainerID.getContainer:', packet)
        self.assertRegex(packet, r'ItemContainer.removeItemWithID:\(I\)Z\s+\d+: pop')
        self.assertNotIn('InventoryItemFactory.', packet)
        self.assertNotIn('getModData:', packet)
        remove_id = self.method('zombie.inventory.ItemContainer', 'public boolean removeItemWithID(int)')
        self.assertIn('Field zombie/inventory/InventoryItem.id:I', remove_id)
        self.assertIn('if_icmpne', remove_id)
        self.assertRegex(remove_id, r'Method Remove:\(Lzombie/inventory/InventoryItem;\)V\s+'
                         r'\d+: iconst_1\s+\d+: ireturn')
        self.assertRegex(remove_id, r'\d+: iconst_0\s+\d+: ireturn\s*$')
        # This is a numeric-ID contract within a frozen container namespace,
        # not protection against an ID reused by another item or generation.
        self.assertNotIn('getModData:', remove_id)

    def test_world_remove_notice_addresses_mutable_index_and_excludes_inventory_retry(self):
        owner = 'zombie.network.packets.RemoveItemFromSquarePacket'
        packet = self.method(owner, 'public void processClient(zombie.core.raknet.UdpConnection)')
        self.assertRegex(packet, r'Field index:S\s+\d+: invokevirtual\s+#[0-9]+\s+'
                         r'// Method zombie/util/list/PZArrayList.get:\(I\)Ljava/lang/Object;')
        self.assertIn('IsoGridSquare.RemoveTileObject:', packet)
        self.assertLess(packet.index('PZArrayList.get:'), packet.index('IsoGridSquare.RemoveTileObject:'))
        self.assertNotIn('getModData:', packet)
        self.assertNotIn('removeItemWithID:', packet)
        write = self.method(owner, 'public void write(zombie.core.network.ByteBufferWriter)')
        for field in ('x:I', 'y:I', 'z:B', 'index:S'):
            self.assertIn('Field ' + field, write)
        self.assertEqual(len(re.findall(r'ByteBufferWriter.put(?:Int|Byte|Short):', write)), 4)
        # After one removal the same index may name a different object. Keep
        # the common journal restricted to inventory notices, never this API.
        journal = (Path(__file__).parent/'native_queue/support/QueueFixtureItemCleanup.lua').read_text()
        self.assertIn('World-object removal packets use mutable square indices', journal)
        self.assertNotIn('transmitRemoveItemFromSquare', journal)
        self.assertNotIn('RemoveItemFromMap', journal)


if __name__ == '__main__':
    unittest.main()
