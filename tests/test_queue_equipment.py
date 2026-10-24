"""Equipment reports require native effects and exact selected lifecycle evidence."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import equipment


class EquipmentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = {'suite': 'equipment', 'cases': equipment.CASES, 'kind': 'sp', 'mode': 'toolkit',
                          'clients': 1, 'languages': ['EN'], 'mods': ['PZSurvivorToolkit'], 'options': {}}

    def records(self):
        cases, enabled = self.selection['cases'], self.selection['mode'] == 'toolkit'
        rows = [{'event': 'setup', 'cases': cases, 'expected': len(cases), 'nativeDurations': True, 'queueEnabled': enabled}]
        for case in cases:
            result = dict(inventoryPreserved=True, frontCompleted=True, tailCompleted=True,
                          equipmentMatches=True, nativeDurations=True, postprocessingVerified=True, policyChecked=enabled)
            if 'P4TidyUpMeister' in self.selection['mods']:
                count = (3 if case == 'tidy-multigroup' else 1)*int(enabled and case in equipment.TIDY_RETURN_CASES)
                result['tidyCompletion'] = dict(perform=count, complete=count if self.selection['kind'] == 'sp' else 0,
                                               flush=int(bool(count)) if case == 'tidy-multigroup' else count, legacy=0, explicitConfirmed=3 if case == 'hands-chain' else 0,
                                               authoritativeIntent=3 if case == 'hands-chain' and self.selection['kind'] == 'mp' else 0,
                                               cleanupConfirmed=(4*int(enabled) if case == 'tidy-multigroup' else count*(2 if case == 'tidy-group' else 1)) if case in equipment.TIDY_RETURN_EXACT_CASES else 0,
                                               authoritativeCleanup=(4*int(enabled) if case == 'tidy-multigroup' else count*(2 if case == 'tidy-group' else 1)) if case in equipment.TIDY_RETURN_EXACT_CASES and self.selection['kind'] == 'mp' else 0)
            if case == 'hands-chain':
                result.update(activeProgress=True, activeProtected=enabled)
            if case == 'waiting-cancel':
                result['cancelled'] = enabled
            if case == 'bag-capacity':
                result['capacityBarrier'] = enabled
            if case in ('belt-knife', 'belt-hammer'):
                result.update(policyChecked=False, slotsVerified=True, belt=True, emptyQueueClick=True, favoritePreserved=True)
                if self.selection['options'].get('belt_walk'):
                    result.update(walkingVerified=True, walkedDuringTransfer=True, walkedDuringAttach=True, walkReleased=True, walkDistance=0.75)
            if case in ('clothing-chain', 'hotbar-chain'):
                result.update(slotsVerified=True, clothing=case == 'clothing-chain', hotbar=case == 'hotbar-chain')
            if case in equipment.HOTBAR_CASES:
                tidy = 'P4TidyUpMeister' in self.selection['mods']
                spec = equipment.HOTBAR_CASES[case]
                provider = not spec['twoHands']
                ordinary, prior, radio = bool(spec.get('ordinary')), bool(spec.get('priorSecondary')), bool(spec.get('radio'))
                flashlight = spec.get('flashlight')
                passive = ordinary or radio or bool(flashlight)
                effect = dict(case=case, providerItem=957 if provider else False, providerType=('Base.SCBA_notank' if flashlight else 'Base.Belt2' if ordinary or radio else 'Base.HolsterDouble') if provider else False,
                              providerLocation=('base:scbanotank' if flashlight else 'base:belt' if ordinary or radio else 'base:beltextra') if provider else False, providerWorn=provider,
                              id=956, fullType=spec['fullType'], container='root', slotIndex=(7 if case.endswith('left') else 8) if provider else 1,
                              slotType=spec['slotType'], model=spec['model'],
                              attached=tidy, primary=False if tidy else 956, secondary=956 if not tidy and spec['twoHands'] else False, worn=False, producer='onRackGun',
                              producerCompleted=True, ammoUnchanged=True, unrelatedAttachmentsPreserved=True)
                if ordinary:
                    effect.pop('ammoUnchanged')
                    effect.update(producer='ISCutHair', primary=False if tidy or not prior else 956,
                                  secondary=(951 if prior else False) if tidy else (951 if prior else 956),
                                  ordinary=dict(condition=10, sharpness=1.0, hairStyle='CrewCut', hairColor=dict(r=0.2, g=0.3, b=0.4), nonAttachedHair=False,
                                                secondary=dict(id=951, fullType='Base.Screwdriver', container='root') if prior else False))
                if radio:
                    effect.pop('ammoUnchanged')
                    effect.update(producer='ISCutHair', primary=False, secondary=False if tidy else 956,
                                  radio={'class': 'Radio', 'deviceClass': 'DeviceData', 'parent': True, 'canonical': True,
                                         'portable': True, 'batteryPowered': True, 'television': False, 'hasBattery': True,
                                         'turnedOn': spec['on'] and not tidy, 'power': 0.98 if spec['on'] else 1, 'channel': 88000, 'volume': 0.25 if spec['on'] else equipment.RADIO_OFF_VOLUME,
                                         'micMuted': True, 'headphones': -1, 'hasMedia': False, 'playingMedia': False,
                                         'activated': False, 'equippedRadio': not tidy, 'emitter': spec['on'] and not tidy,
                                         'scissors': dict(id=958, fullType='Base.ScissorsBluntMedical', container='root'),
                                         'producer': dict(condition=10, sharpness=1.0, hairStyle='CrewCut', hairColor=dict(r=0.2, g=0.3, b=0.4), nonAttachedHair=False, secondary=False)})
                if flashlight:
                    effect.pop('ammoUnchanged')
                    effect.update(producer='ISCutHair', primary=False, secondary=False if tidy else 956,
                                  flashlight={'class': 'DrainableComboItem', 'canonical': True, 'flashlight': True, 'canActivate': True,
                                              'keepOnDeplete': True, 'useWhileEquipped': True, 'useWhileUnequipped': False,
                                              'replaceOnDeplete': False, 'cookable': False, 'onCooked': False, 'onEat': False,
                                              'lightStrength': 1.5, 'lightDistance': 15, 'torchCone': True, 'useDelta': equipment.FLASHLIGHT_USE_DELTA,
                                              'maxUses': 166, 'uses': 165 if flashlight == 'charged' else 0,
                                              'activated': flashlight != 'empty' and not tidy, 'emitting': flashlight == 'charged' and not tidy,
                                              'scissors': dict(id=958, fullType='Base.ScissorsBluntMedical', container='root'),
                                              'producer': dict(condition=10, sharpness=1.0, hairStyle='CrewCut', hairColor=dict(r=0.2, g=0.3, b=0.4), nonAttachedHair=False, secondary=False)})
                count = int(enabled and tidy)
                result.update(hotbarItem=956, hotbarCheckpoint=dict(effect, attached=False, primary=956 if not passive or prior else False, secondary=(951 if prior else 956) if passive else 956 if spec['twoHands'] else False),
                              tidyHotbar=dict(effect, nativeGenerated=int(tidy), authoritativeRestore=tidy and self.selection['kind'] == 'mp',
                                              sourceSession=18 if tidy else False, sourceCompleted=tidy, attachConnectObserved=tidy,
                                              uiHotbarIdentity=True, unrelatedTailPreserved=True,
                                              sharedCompletion=dict(perform=count, complete=count if self.selection['kind'] == 'sp' else 0,
                                                                    flush=count, legacy=0)))
                if radio:
                    result['hotbarCheckpoint']['radio'] = copy.deepcopy(effect['radio'])
                    result['hotbarCheckpoint']['radio']['turnedOn'] = spec['on']
                    result['hotbarCheckpoint']['radio']['equippedRadio'] = True
                    result['hotbarCheckpoint']['radio']['emitter'] = spec['on']
                    result['tidyHotbar']['radioBaseline'] = dict(copy.deepcopy(effect['radio']), power=1, equippedRadio=False, emitter=False, turnedOn=spec['on'])
                    result['tidyHotbar']['radioLifecycle'] = dict(heldPointer=True, emitterCreated=spec['on'], emitterCleaned=spec['on'] and tidy)
                    actions = [dict(kind='ISEquipWeaponAction', id=956), dict(kind='ISCutHair', id=958)] + ([dict(kind='ISUnequipAction', id=956)] if tidy else [])
                    result['tidyHotbar']['acknowledgements'] = [dict(action, state='completed') for action in actions] if self.selection['kind'] == 'mp' else []
                if flashlight:
                    result['hotbarCheckpoint']['flashlight'] = copy.deepcopy(effect['flashlight'])
                    result['hotbarCheckpoint']['flashlight']['activated'] = flashlight != 'empty'
                    result['hotbarCheckpoint']['flashlight']['emitting'] = flashlight == 'charged'
                    result['tidyHotbar']['flashlightBaseline'] = dict(copy.deepcopy(effect['flashlight']), uses=166 if flashlight == 'charged' else 1 if flashlight == 'deplete' else 0, activated=False, emitting=False)
                    result['tidyHotbar']['flashlightLifecycle'] = dict(held=True, activated=flashlight != 'empty', emitted=flashlight != 'empty', depleted=flashlight == 'deplete', deactivated=tidy and flashlight != 'empty')
                    actions = [dict(kind='ISEquipWeaponAction', id=956), dict(kind='ISCutHair', id=958)] + ([dict(kind='ISUnequipAction', id=956)] if tidy else [])
                    result['tidyHotbar']['acknowledgements'] = [dict(action, state='completed') for action in actions] if self.selection['kind'] == 'mp' else []
                if ordinary:
                    result['tidyHotbar']['ordinaryBaseline'] = copy.deepcopy(effect['ordinary'])
                    actions = [dict(kind='ISEquipWeaponAction', id=956), dict(kind='ISCutHair', id=956)] + ([dict(kind='ISUnequipAction', id=956)] if tidy else [])
                    result['tidyHotbar']['acknowledgements'] = [dict(action, state='completed') for action in actions] if self.selection['kind'] == 'mp' else []
            if case in equipment.CLOTHING_CASES:
                tidy = 'P4TidyUpMeister' in self.selection['mods']
                spec = equipment.CLOTHING_SPECS[case]
                effect = dict(id=955, fullType=spec['fullType'], bodyLocation=spec['location'], container='root', worn=not tidy if spec.get('remove') else tidy,
                              producer='ISCutHair', producerCompleted=True, hairUnchanged=True, hairStyle='CrewCut',
                              unrelatedHandsPreserved=True)
                if spec.get('overlapHand'):
                    hand = spec['overlapHand']
                    remove = bool(spec.get('remove'))
                    original_p = 955 if not remove and hand in ('primary', 'both') else 950
                    original_s = 955 if not remove and hand in ('secondary', 'both') else 951
                    checkpoint_p = (955 if remove else False) if hand in ('primary', 'both') else original_p
                    checkpoint_s = (955 if remove else False) if hand in ('secondary', 'both') else original_s
                    effect.update(primary=original_p if tidy else checkpoint_p, secondary=original_s if tidy else checkpoint_s,
                                  originalPrimary=original_p, originalSecondary=original_s)
                if spec.get('temporaryType'):
                    effect['temporary'] = dict(id=957, fullType=spec['temporaryType'], bodyLocation=spec['temporaryLocation'], container='root', worn=not tidy)
                if spec.get('watch'):
                    effect['watch'] = dict(alarmHour=23, alarmMinute=40, alarmSet=spec['alarm'], ringing=bool(spec.get('ringing')))
                if spec.get('ringing'):
                    effect['watchTiming'] = dict(startedAgeHours=100.0, observedAgeHours=100.1)
                count = int(enabled and tidy)
                result.update(clothingItem=955, clothingCheckpoint=dict(effect, worn=bool(spec.get('remove')), **(dict(primary=checkpoint_p, secondary=checkpoint_s) if spec.get('overlapHand') else {})),
                              tidyClothing=dict(effect, nativeGenerated=int(tidy), authoritativeRestore=tidy and self.selection['kind'] == 'mp',
                                                sourceSession=17 if tidy else False, sourceCompleted=tidy,
                                                sharedCompletion=dict(perform=count, complete=count if self.selection['kind'] == 'sp' else 0,
                                                                      flush=count, legacy=0), unrelatedTailPreserved=True))
                if spec.get('mohawk'):
                    def appearance(model, uses):
                        return dict(hairModel=model, nonAttachedHair=False, hairColor=dict(r=0.2, g=0.3, b=0.4), hairGrowthTime=False,
                                    gel=dict(id=958, fullType='Base.Hairgel', container='root', uses=uses))
                    final_model = 'MohawkFlat' if tidy and self.selection['kind'] == 'sp' else 'MohawkFan'
                    result['clothingCheckpoint'].update(hairUnchanged=True, hairStyle='MohawkFan', appearance=appearance('MohawkFan', 19))
                    result['tidyClothing'].update(hairUnchanged=final_model == 'MohawkFan', hairStyle=final_model, appearance=appearance(final_model, 19),
                                                appearanceBaseline=appearance('MohawkFan', 20), appearanceCheckpoint=appearance('MohawkFan', 19),
                                                appearanceAcknowledgements=[dict(kind='ISWearClothing' if spec.get('remove') else 'ISUnequipAction', id=955, state='completed'),
                                                    dict(kind='ISCutHair', id=False, state='completed'),
                                                    *([dict(kind='ISUnequipAction' if spec.get('remove') else 'ISWearClothing', id=955, state='completed')] if tidy else [])] if self.selection['kind'] == 'mp' else [])
                if spec.get('temporaryType'):
                    result['clothingCheckpoint']['temporary'] = dict(effect['temporary'], worn=True)
                    cleanup = ([dict(kind='ISUnequipAction', id=957)] if spec['temporaryLocation'] != spec['location'] else []) + [dict(kind='ISWearClothing', id=955)]
                    producers = [dict(kind='ISWearClothing', id=957), dict(kind='ISCutHair', id=False)]
                    result['tidyClothing']['displacement'] = dict(cleanup=cleanup if tidy else [], acknowledgements=[dict(row, state='completed') for row in producers + (cleanup if tidy else [])] if self.selection['kind'] == 'mp' else [])
                    total = count * len(cleanup)
                    result['tidyClothing']['sharedCompletion'] = dict(perform=total, complete=total if self.selection['kind'] == 'sp' else 0, flush=total, legacy=0)
                if spec.get('watch'):
                    result['tidyClothing']['watchBaseline'] = dict(effect['watch'])
                    result['tidyClothing']['watchSetup'] = dict(emptyExclusiveSlots=True, capacityBeforeRemoval=True)
                    if not spec.get('overlapHand'):
                        result['tidyClothing']['watchAcknowledgements'] = [
                            dict(kind='ISWearClothing' if spec.get('remove') else 'ISUnequipAction', id=955, state='completed'),
                            dict(kind='ISCutHair', id=False, state='completed'),
                            *([dict(kind='ISUnequipAction' if spec.get('remove') else 'ISWearClothing', id=955, state='completed')] if tidy else [])
                        ] if self.selection['kind'] == 'mp' else []
                    if self.selection['kind'] == 'sp':
                        result['clothingCheckpoint']['watchProcessing'] = dict(active=bool(spec['alarm'] and spec.get('remove')), pendingRemoval=False)
                        result['tidyClothing']['watchProcessing'] = dict(active=bool(spec['alarm'] and effect['worn']), pendingRemoval=False)
                if spec.get('headwear'):
                    result['tidyClothing']['headwearSetup'] = dict(emptyExclusiveSlots=True, capacityBeforeRemoval=True)
                if spec.get('overlapHand'):
                    cleanup = []
                    if tidy:
                        if remove and hand in ('primary', 'both'):
                            cleanup += [dict(kind='ISEquipWeaponAction', id=950, primary=True, twoHands=False), dict(kind='P4RestoreAction', id=950, activated=False)]
                        if remove and hand in ('secondary', 'both'):
                            cleanup += [dict(kind='ISEquipWeaponAction', id=951, primary=False, twoHands=False), dict(kind='P4RestoreAction', id=951, activated=False)]
                        if remove:
                            cleanup += [dict(kind='ISUnequipAction', id=955)]
                        else:
                            cleanup = [dict(kind='ISEquipWeaponAction', id=955, primary=hand != 'secondary', twoHands=hand == 'both'),
                                       dict(kind='P4RestoreAction', id=955, activated=False), dict(kind='ISWearClothing', id=955)]
                    producers = ([dict(kind='ISEquipWeaponAction', id=955), dict(kind='ISWearClothing', id=955)] if remove else [dict(kind='ISUnequipAction', id=955)]) + [dict(kind='ISCutHair', id=False)]
                    actions = producers + [dict(kind=row['kind'], id=row['id']) for row in cleanup]
                    hand_count = (2 if remove and hand == 'both' else 1) * count
                    result['tidyClothing']['overlap'] = dict(
                        intermediate=dict(primary=checkpoint_p, secondary=checkpoint_s, worn=955 if remove else False, container='root'), cleanup=cleanup,
                        acknowledgements=[dict(item, state='completed') for item in actions] if self.selection['kind'] == 'mp' else [],
                        sharedHands=dict(perform=2*hand_count, complete=2*hand_count if self.selection['kind'] == 'sp' else 0,
                                         flush=2*hand_count, legacy=0, equip=hand_count, activation=hand_count, unequip=0))
            if case in ('tidy-hands', 'tidy-empty-hands'):
                result.update(rackWholeOperationMoveVerified=enabled, rackCancellationProtected=enabled, independentMoveVerified=enabled)
            if case in ('tidy-hands', 'tidy-floor', 'tidy-empty-hands', 'tidy-group', 'tidy-multigroup'):
                count = int(enabled and 'P4TidyUpMeister' in self.selection['mods'])
                empty = case == 'tidy-empty-hands'
                actions = count if empty else 4*count
                result['primary'] = 731
                result.update(restoreVerified=True, floorRestoreVerified=case == 'tidy-floor' and 'P4TidyUpMeister' in self.selection['mods'],
                              restoreCompletion=dict(perform=actions, complete=actions if self.selection['kind'] == 'sp' else 0,
                                                     flush=actions, legacy=0, equip=0 if empty else 2*count,
                                                     activation=0 if empty else 2*count, unequip=count if empty else 0))
            if case in ('tidy-group', 'tidy-multigroup'):
                tidy = 'P4TidyUpMeister' in self.selection['mods']
                multi = case == 'tidy-multigroup'
                items = [dict(id=i, fullType='Base.Nails' if i < 903 else 'Base.Hammer', container='worn-bag' if tidy else 'root') for i in ((901, 902, 903, 904) if multi else (901, 902))]
                result['tidyGroup'] = dict(nativeGroups=(3 if multi else 1) if tidy else 0, nativeItems=len(items) if tidy else 0,
                                           groupSizes=([1, 1, 2] if multi else [2]) if tidy else [],
                                           obligationGroups=int(tidy and enabled), unrelatedTailPreserved=True, items=items,
                                           completedItems=[dict(id=item['id'], fullType=item['fullType'], state='completed') for item in items] if tidy and enabled else [])
                pickups = [dict(id=item['id'], fullType=item['fullType'], owner=1, shared=False, pickupAttempt=1,
                                pickupTransaction=31 if self.selection['kind'] == 'mp' else 0,
                                pickupAuthority='completed' if self.selection['kind'] == 'mp' else 'native')
                           for item in items] if tidy and enabled else []
                result['tidyGroup'].update(pickupOperations=int(bool(pickups)), pickupItems=pickups,
                                           ownershipAtBegin=[dict(item, state='active') for item in pickups],
                                           ownershipCompleted=[dict(item, state='completed') for item in pickups])
                if multi:
                    attempts = []
                    if tidy and enabled:
                        for ordinal, members in enumerate(([items[2]], [items[3]], items[:2]), 1):
                            attempts.append(dict(ordinal=ordinal, phase='perform', state='completed',
                                                 transaction=ordinal if self.selection['kind'] == 'mp' else 0,
                                                 authority='completed' if self.selection['kind'] == 'mp' else 'native',
                                                 items=[dict(id=item['id'], fullType=item['fullType'], state='completed') for item in members]))
                    result['tidyGroup'].update(executorCount=(1 if tidy else 0),
                                               sameNativeExecutor=True, attempts=attempts)
            if case == 'floor-pickup':
                result.update(floorPickup=True, pickupWorldRemoved=True)
            if case.startswith('bulk-'):
                result.update(bulkPickup=True, exactBulkContainers=True)
                if case == 'bulk-waiting-cancel':
                    result.update(bulkCancelled=True, unrelatedTailPreserved=True)
                else:
                    result.update(lightMerged=True, heavySeparate=True, childrenWiped=True, sharedExecutor=case == 'bulk-mixed')
                if case == 'bulk-mixed':
                    result['borrowedReturned'] = 'P4TidyUpMeister' in self.selection['mods']
            if self.selection['kind'] == 'mp':
                result.update(authoritative=True, receipts=0 if case == 'waiting-cancel' and enabled else equipment.RECEIPTS[case])
                result['receiptStates'] = ['completed'] * result['receipts']
            rows.append({'event': 'case', 'id': case, 'status': 'passed', 'outcome': result})
        rows.append({'event': 'complete', 'cases': cases, 'expected': len(cases), 'performed': len(cases), 'skipped': 0, 'failed': 0})
        return [dict(row, suite='equipment', kind=self.selection['kind'], mode=self.selection['mode'], actor='client1') for row in rows]

    def scene_marker(self):
        headwear = any(equipment.CLOTHING_SPECS.get(case, {}).get('headwear') for case in self.selection['cases'])
        watch = any(equipment.CLOTHING_SPECS.get(case, {}).get('watch') for case in self.selection['cases'])
        if not headwear and not watch:
            return ''
        proof = dict(prepared=True, authority='server' if self.selection['kind'] == 'mp' else 'sp', rootRetained=True,
                     normalizedItems=[dict(id=900, fullType='Base.Glasses_Cosmetic_Normal', location='base:eyes' if headwear else 'base:forearm_left')])
        if watch:
            proof['targetLocations'] = sorted(({'base:hat', 'base:fullhat'} if headwear else set()) | {equipment.CLOTHING_SPECS[case]['location'] for case in self.selection['cases'] if equipment.CLOTHING_SPECS.get(case, {}).get('watch')})
        return '[EQUIPMENT_TEST] SCENE_HEADWEAR ' + json.dumps(proof) + '\n'

    def logs(self, records=None):
        captures=[]
        if self.selection['kind'] == 'mp':
            for case in self.selection['cases']:
                count=0 if case == 'waiting-cancel' and self.selection['mode'] == 'toolkit' else equipment.RECEIPTS[case]
                for _ in range(count):
                    captures.append('[EQUIPMENT_TEST] CAPTURE case=' + case + ' kind=ISEquipWeaponAction token=00000000-0000-0000-0000-' + str(len(captures)+1).zfill(12))
        captures.extend('[EQUIPMENT_TEST] WATCH_CLEANUP ' + json.dumps(dict(id=row['outcome']['tidyClothing']['id'], watch=dict(row['outcome']['tidyClothing']['watch'], ringing=False)))
                        for row in self.records() if equipment.CLOTHING_SPECS.get(row.get('id'), {}).get('ringing'))
        return (self.scene_marker() if self.selection['kind'] == 'sp' else '') + '\n'.join(captures + ['[QUEUE_CHECK] ' + json.dumps(row) for row in (records or self.records())]
                         + ['[EQUIPMENT_TEST] RECEIPT case=' + case for case in self.selection['cases']]
                         + ['[EQUIPMENT_TEST] COMPLETE'])

    def verify(self, text):
        (self.root / 'client1-launch.log').write_text(text)
        if self.selection['kind'] == 'mp' and not (self.root / 'server-launch.log').exists():
            (self.root / 'server-launch.log').write_text(self.scene_marker() + '[EQUIPMENT_TEST] TRANSFER_PROBE active=true\n[EQUIPMENT_TEST] SERVER_READY\n' + '\n'.join('[EQUIPMENT_TEST] CHECKPOINT case=' + case + '\n[EQUIPMENT_TEST] AUTHORITY case=' + case + ' inventoryPreserved=true equipmentMatches=true tailCompleted=true' for case in self.selection['cases']))
            for case in self.selection['cases']:
                if case in ('tidy-group', 'tidy-multigroup'):
                    with (self.root / 'server-launch.log').open('a') as log:
                        row = next(row for row in (self.records()) if row.get('id') == case)
                        log.write('\n[EQUIPMENT_TEST] GROUP_AUTHORITY ' + json.dumps(dict(case=case, items=row['outcome']['tidyGroup']['items'], tailCompleted=True)) + '\n')
            if 'tidy-floor' in self.selection['cases'] and 'P4TidyUpMeister' in self.selection['mods']:
                with (self.root / 'server-launch.log').open('a') as log:
                    log.write('\n[EQUIPMENT_TEST] FLOOR_RESTORE id=731 result=true\n')
            for case in self.selection['cases']:
                if case in equipment.CLOTHING_CASES:
                    row = next(row for row in self.records() if row.get('id') == case)
                    effect = {key: row['outcome']['tidyClothing'][key] for key in equipment.clothing_effect_keys(case)}
                    if equipment.CLOTHING_SPECS[case].get('mohawk'):
                        effect['hairStyle'] = 'MohawkFlat' if 'P4TidyUpMeister' in self.selection['mods'] and not equipment.CLOTHING_SPECS[case].get('remove') else 'MohawkFan'
                        effect['hairUnchanged'] = effect['hairStyle'] == 'MohawkFan'
                        effect['appearance'] = dict(effect['appearance'], hairModel=effect['hairStyle'])
                        for key in ('appearanceBaseline', 'appearanceCheckpoint'):
                            effect[key] = row['outcome']['tidyClothing'][key]
                    if equipment.CLOTHING_SPECS[case].get('watch'):
                        effect['watchProcessing'] = dict(active=bool(equipment.CLOTHING_SPECS[case]['alarm'] and effect['worn']), pendingRemoval=False)
                    with (self.root / 'server-launch.log').open('a') as log:
                        log.write('\n[EQUIPMENT_TEST] CLOTHING_AUTHORITY ' + json.dumps(effect) + '\n')
                        if equipment.CLOTHING_SPECS[case].get('mohawk'):
                            log.write('[EQUIPMENT_TEST] APPEARANCE_CHECKPOINT ' + json.dumps(dict(id=effect['id'], appearance=effect['appearanceCheckpoint'])) + '\n')
                        if equipment.CLOTHING_SPECS[case].get('watch'):
                            before = row['outcome']['clothingCheckpoint']
                            checkpoint = dict(id=before['id'], watch=before['watch'], **({'watchTiming': before['watchTiming']} if equipment.CLOTHING_SPECS[case].get('ringing') else {}), watchProcessing=dict(active=bool(equipment.CLOTHING_SPECS[case]['alarm'] and before['worn']), pendingRemoval=False))
                            log.write('[EQUIPMENT_TEST] WATCH_CHECKPOINT ' + json.dumps(checkpoint) + '\n')
                        if equipment.CLOTHING_SPECS[case].get('ringing'):
                            log.write('[EQUIPMENT_TEST] WATCH_CLEANUP ' + json.dumps(dict(id=effect['id'], watch=dict(effect['watch'], ringing=False))) + '\n')
            for case in self.selection['cases']:
                if case in equipment.HOTBAR_CASES:
                    row = next(row for row in self.records() if row.get('id') == case)
                    effect = {key: row['outcome']['tidyHotbar'][key] for key in equipment.hotbar_authority_keys(case)}
                    if equipment.HOTBAR_CASES[case].get('radio'):
                        effect = copy.deepcopy(effect)
                        effect['radio']['turnedOn'] = equipment.HOTBAR_CASES[case]['on'] and not effect['attached']
                        effect['radio']['equippedRadio'] = False
                        effect['radio']['emitter'] = False
                    with (self.root / 'server-launch.log').open('a') as log:
                        log.write('\n[EQUIPMENT_TEST] HOTBAR_AUTHORITY ' + json.dumps(effect) + '\n')
        return equipment.verify(self.root, self.selection, {})

    def test_native_lua_selection_accepts_exact_report_cases_and_rejects_unknown_duplicates(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        ids = ','.join(json.dumps(case) for case in equipment.CASES)
        source = "local expected={" + ids + "}\n" + r"""
local config={cases=expected,kind='mp',mode='toolkit',clients=1,languages={'EN'},options={}}
require=function(name)assert(name=='QueueTestSelection');return config end
local selected=dofile(arg[1])
assert(#selected.cases==#expected,'native selection omitted a declared report case')
for i,id in ipairs(expected)do assert(selected.cases[i]==id,'native/report selection ordering differs')end
config.cases={'unsupported-case'};assert(not pcall(dofile,arg[1]))
config.cases={expected[1],expected[1]};assert(not pcall(dofile,arg[1]))
"""
        script = self.root / 'selection-check.lua'; script.write_text(source)
        result = subprocess.run([lua, str(script), str(ROOT / 'tests/native_queue/equipment/shared/QueueEquipmentSelection.lua')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_tidy_hotbar_requires_exact_native_effect_session_phases_and_completed_host_receipt(self):
        self.selection.update(cases=['tidy-hotbar'], mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('native', 'toolkit'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for field in equipment.HOTBAR_EFFECT_KEYS | {'nativeGenerated', 'sourceSession', 'sourceCompleted', 'attachConnectObserved',
                                                            'uiHotbarIdentity', 'authoritativeRestore', 'unrelatedTailPreserved'}:
                    rows = self.records(); rows[1]['outcome']['tidyHotbar'].pop(field)
                    self.assertTrue(self.verify(self.logs(rows))['issues'], field)
                for field, value in (('id', True), ('slotIndex', True), ('slotIndex', 2), ('slotType', 'SmallBeltLeft'),
                                     ('model', 'Rifle On Back'), ('fullType', 'Base.Pistol'), ('container', 'worn-bag'),
                                     ('primary', 956), ('secondary', 956), ('worn', True), ('attached', False),
                                     ('producer', 'ISAttachItemHotbar'), ('nativeGenerated', 0), ('sourceSession', 0),
                                     ('sourceCompleted', False), ('attachConnectObserved', False), ('uiHotbarIdentity', False)):
                    rows = self.records(); rows[1]['outcome']['tidyHotbar'][field] = value
                    self.assertTrue(self.verify(self.logs(rows))['issues'], (kind, mode, field, value))
                for field in ('perform', 'complete', 'flush', 'legacy'):
                    rows = self.records(); rows[1]['outcome']['tidyHotbar']['sharedCompletion'][field] += 1
                    self.assertTrue(self.verify(self.logs(rows))['issues'], field)
                rows = self.records(); rows[1]['outcome']['hotbarCheckpoint']['attached'] = True
                self.assertTrue(self.verify(self.logs(rows))['issues'])
                if kind == 'mp':
                    rows = self.records(); rows[1]['outcome']['receiptStates'] = ['canceled']
                    self.assertTrue(self.verify(self.logs(rows))['issues'])
                    server = self.root / 'server-launch.log'; original = server.read_text()
                    marker = next(line for line in original.splitlines() if '[EQUIPMENT_TEST] HOTBAR_AUTHORITY ' in line)
                    for replacement in ('', marker + '\n' + marker, marker.replace('956', '957'), marker.replace('"attached": true', '"attached": false')):
                        server.write_text(original.replace(marker, replacement))
                        self.assertTrue(self.verify(self.logs())['issues'])
                    server.write_text(original)

    def test_ordinary_hotbar_requires_native_hand_selection_exact_provider_and_tool_conservation(self):
        selected = [case for case, spec in equipment.HOTBAR_CASES.items() if spec.get('ordinary')]
        self.selection.update(cases=selected, mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('native', 'toolkit'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for case in selected:
                    for field, change in [('condition', 9), ('sharpness', 0.5), ('sharpness', True), ('hairStyle', 'MohawkFan'), ('nonAttachedHair', 'Ponytail')]:
                        rows = self.records();value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                        value['ordinary'][field] = change
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (case, field, change))
                    for field, change in [('providerType', 'Base.HolsterDouble'), ('providerLocation', 'base:beltextra'), ('primary', 956), ('producer', 'onRackGun')]:
                        rows = self.records();value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                        value[field] = change
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (case, field))
                    rows = self.records();value = next(row['outcome']['hotbarCheckpoint'] for row in rows if row.get('id') == case)
                    value['primary'], value['secondary'] = value['secondary'], value['primary']
                    self.assertTrue(self.verify(self.logs(rows))['issues'], 'wrong native selected hand')
                    if equipment.HOTBAR_CASES[case].get('priorSecondary'):
                        rows = self.records();value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                        value['ordinary']['secondary']['id'] = 956
                        self.assertTrue(self.verify(self.logs(rows))['issues'])
                    if kind == 'mp':
                        rows = self.records();value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                        value['acknowledgements'].pop(1)
                        self.assertTrue(self.verify(self.logs(rows))['issues'])

    def test_flashlight_hotbar_requires_native_activation_depletion_and_exact_host_state(self):
        cases = ['tidy-hotbar-flashlight-' + mode for mode in ('charged', 'empty', 'deplete')]
        self.selection.update(cases=cases, mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('native', 'toolkit'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for case in cases:
                    for field, wrong in [('class', 'ComboItem'), ('canonical', False), ('keepOnDeplete', False), ('useWhileUnequipped', True),
                                         ('replaceOnDeplete', 'Base.Battery'), ('cookable', True), ('onCooked', 'callback'), ('lightStrength', 0),
                                         ('uses', -1), ('uses', 167), ('uses', True), ('activated', True), ('emitting', True)]:
                        rows = self.records(); value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                        value['flashlight'][field] = wrong
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (kind, mode, case, field))
                    for malformed in (False, [], 'light', None):
                        rows = self.records(); value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                        value['flashlight'] = malformed
                        self.assertTrue(self.verify(self.logs(rows))['issues'], ('malformed flashlight', malformed))
                    rows = self.records(); value = next(row['outcome']['hotbarCheckpoint'] for row in rows if row.get('id') == case)
                    value['flashlight']['activated'] = not value['flashlight']['activated']
                    self.assertTrue(self.verify(self.logs(rows))['issues'], 'incorrect native held activation')
                    rows = self.records(); value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                    value['flashlightLifecycle']['depleted'] = not value['flashlightLifecycle']['depleted']
                    self.assertTrue(self.verify(self.logs(rows))['issues'], 'missing/false native depletion evidence')
                    rows = self.records(); value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                    value['flashlight']['scissors']['id'] = value['id']
                    self.assertTrue(self.verify(self.logs(rows))['issues'], 'flashlight used as scissors')
                if kind == 'mp':
                    self.logs(); server = self.root / 'server-launch.log'; original = server.read_text()
                    marker = next(line for line in original.splitlines() if '[EQUIPMENT_TEST] HOTBAR_AUTHORITY ' in line and 'tidy-hotbar-flashlight-charged' in line)
                    for field, wrong in [('activated', True), ('uses', 164), ('keepOnDeplete', False)]:
                        value = json.loads(marker.split('HOTBAR_AUTHORITY ', 1)[1]); value['flashlight'][field] = wrong
                        server.write_text(original.replace(marker, '[EQUIPMENT_TEST] HOTBAR_AUTHORITY ' + json.dumps(value)))
                        self.assertTrue(self.verify(self.logs())['issues'], ('server exact state', field))
                    server.write_text(original)

    def test_radio_hotbar_requires_owned_device_separate_scissors_and_natural_power(self):
        self.selection.update(cases=['tidy-hotbar-radio-off', 'tidy-hotbar-radio-on'], mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('native', 'toolkit'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for case in self.selection['cases']:
                    for field, change in [('parent', False), ('deviceClass', 'CustomDeviceData'), ('portable', False), ('batteryPowered', False),
                                          ('television', True), ('channel', 90000), ('volume', 0.5), ('micMuted', False), ('hasMedia', True),
                                          ('playingMedia', True), ('activated', True), ('equippedRadio', True), ('power', 1.1), ('power', True)]:
                        rows = self.records(); value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                        value['radio'][field] = change
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (kind, mode, case, field))
                    for malformed in (False, [], 'radio', None):
                        rows = self.records(); value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                        value['radio'] = malformed
                        self.assertTrue(self.verify(self.logs(rows))['issues'], ('malformed radio', malformed))
                        rows = self.records(); value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                        value['radio']['scissors'] = malformed
                        self.assertTrue(self.verify(self.logs(rows))['issues'], ('malformed scissors', malformed))
                    rows = self.records(); value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                    value['radio']['scissors']['id'] = value['id']
                    self.assertTrue(self.verify(self.logs(rows))['issues'], 'radio passed as haircut tool')
                    rows = self.records(); value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                    value['radio']['producer']['sharpness'] = 0.5
                    self.assertTrue(self.verify(self.logs(rows))['issues'])
                    rows = self.records(); value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                    value['radio']['turnedOn'] = True
                    self.assertTrue(self.verify(self.logs(rows))['issues'], 'native/UI final radio power-off missing')
                    rows = self.records(); value = next(row['outcome']['hotbarCheckpoint'] for row in rows if row.get('id') == case)
                    value['radio']['turnedOn'] = not equipment.HOTBAR_CASES[case]['on']
                    self.assertTrue(self.verify(self.logs(rows))['issues'], 'incorrect held radio power')
                    rows = self.records(); value = next(row['outcome']['hotbarCheckpoint'] for row in rows if row.get('id') == case)
                    value['radio']['equippedRadio'] = False
                    self.assertTrue(self.verify(self.logs(rows))['issues'])
                    if kind == 'mp':
                        rows = self.records(); value = next(row['outcome']['tidyHotbar'] for row in rows if row.get('id') == case)
                        value['acknowledgements'][1]['id'] = value['id']
                        self.assertTrue(self.verify(self.logs(rows))['issues'])
                # Client/server power can differ within their monotonic native ranges.
                if kind == 'mp':
                    self.logs(); server = self.root / 'server-launch.log'
                    server.write_text(server.read_text().replace('"power": 0.98', '"power": 0.99'))
                    self.assertEqual(self.verify(self.logs())['issues'], [])
                    original = server.read_text()
                    marker = next(line for line in original.splitlines() if '[EQUIPMENT_TEST] HOTBAR_AUTHORITY ' in line and 'tidy-hotbar-radio-on' in line)
                    authority = json.loads(marker.split('HOTBAR_AUTHORITY ', 1)[1])
                    authority['radio']['turnedOn'] = True
                    server.write_text(original.replace(marker, '[EQUIPMENT_TEST] HOTBAR_AUTHORITY ' + json.dumps(authority)))
                    self.assertTrue(self.verify(self.logs())['issues'], 'retained server on must fail repaired native off receipt')
                    server.write_text(original)

    def test_tidy_clothing_requires_exact_p4_generation_shared_phases_and_conserved_effects(self):
        self.selection.update(cases=['tidy-clothing'], mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('native', 'toolkit'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for field in equipment.CLOTHING_EFFECT_KEYS | {'nativeGenerated', 'authoritativeRestore', 'unrelatedTailPreserved', 'sourceSession', 'sourceCompleted'}:
                    rows = self.records(); rows[1]['outcome']['tidyClothing'].pop(field)
                    self.assertTrue(self.verify(self.logs(rows))['issues'], field)
                for field in ('perform', 'complete', 'flush', 'legacy'):
                    for change in (True, -1, '1', 1.0, 2):
                        rows = self.records(); rows[1]['outcome']['tidyClothing']['sharedCompletion'][field] = change
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (kind, mode, field, change))
                for field, value in (('id', True), ('fullType', 'Base.Socks_Long'), ('bodyLocation', 'base:hat'),
                                     ('container', 'worn-bag'), ('worn', False), ('producer', 'ISWearClothing'),
                                     ('hairStyle', 'Mohawk'), ('nativeGenerated', 0), ('hairUnchanged', False),
                                     ('unrelatedHandsPreserved', False), ('unrelatedTailPreserved', False)):
                    rows = self.records(); rows[1]['outcome']['tidyClothing'][field] = value
                    self.assertTrue(self.verify(self.logs(rows))['issues'], (field, value))
                rows = self.records(); rows[1]['outcome']['clothingCheckpoint']['id'] += 1
                self.assertTrue(self.verify(self.logs(rows))['issues'])
                for session in (0, -1, True, '17', None):
                    rows = self.records(); rows[1]['outcome']['tidyClothing']['sourceSession'] = session
                    self.assertTrue(self.verify(self.logs(rows))['issues'])
                if kind == 'mp':
                    server = self.root / 'server-launch.log'; original = server.read_text()
                    marker = next(line for line in original.splitlines() if '[EQUIPMENT_TEST] CLOTHING_AUTHORITY ' in line)
                    for replacement in ('', marker + '\n' + marker, marker.replace('955', '956'), marker.replace('"worn": true', '"worn": false')):
                        server.write_text(original.replace(marker, replacement))
                        self.assertTrue(self.verify(self.logs())['issues'])
                    server.write_text(original)

    def test_mohawk_requires_exact_per_role_appearance_native_consumption_and_receipts(self):
        selected = [case for case, spec in equipment.CLOTHING_SPECS.items() if spec.get('mohawk')]
        self.selection.update(cases=selected, mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('native', 'toolkit'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for case in selected:
                    for phase in ('tidyClothing', 'clothingCheckpoint'):
                        rows = self.records()
                        target = next(row['outcome'][phase] for row in rows if row.get('id') == case)
                        target['hairUnchanged'] = not target['hairUnchanged']
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (kind, mode, case, phase, 'hairUnchanged'))
                    for field, replacement in [('hairModel', 'CrewCut'), ('nonAttachedHair', 'Ponytail'), ('hairGrowthTime', 1), ('hairColor', dict(r=True, g=0.3, b=0.4))]:
                        rows = self.records()
                        target = next(row['outcome']['tidyClothing'] for row in rows if row.get('id') == case)
                        target['appearance'][field] = replacement
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (kind, mode, case, field))
                    for field, replacement in [('uses', 20), ('uses', 18), ('id', 955), ('id', True), ('container', 'worn-bag'), ('fullType', 'Base.Hairspray2')]:
                        rows = self.records()
                        target = next(row['outcome']['tidyClothing'] for row in rows if row.get('id') == case)
                        target['appearance']['gel'][field] = replacement
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (case, field, replacement))
                    for field in ('appearanceBaseline', 'appearanceCheckpoint', 'appearanceAcknowledgements'):
                        rows = self.records()
                        target = next(row['outcome']['tidyClothing'] for row in rows if row.get('id') == case)
                        target.pop(field)
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (case, field))
                    if kind == 'mp':
                        rows = self.records()
                        target = next(row['outcome']['tidyClothing'] for row in rows if row.get('id') == case)
                        target['appearanceAcknowledgements'].pop(1)
                        self.assertTrue(self.verify(self.logs(rows))['issues'])
        self.selection.update(kind='mp', mode='toolkit')
        self.assertEqual(self.verify(self.logs())['issues'], [])
        server = self.root / 'server-launch.log'
        original = server.read_text()
        server.write_text(original.replace('APPEARANCE_CHECKPOINT', 'MISSING_APPEARANCE'))
        self.assertTrue(self.verify(self.logs())['issues'])
        for line in original.splitlines():
            if '[EQUIPMENT_TEST] CLOTHING_AUTHORITY ' not in line:
                continue
            payload = json.loads(line.split('CLOTHING_AUTHORITY ', 1)[1])
            model = payload['hairStyle']
            counterpart = 'MohawkFlat' if model == 'MohawkFan' else 'MohawkFan'
            changed = copy.deepcopy(payload)
            changed['hairStyle'] = changed['appearance']['hairModel'] = counterpart
            changed['hairUnchanged'] = counterpart == 'MohawkFan'
            server.write_text(original.replace(line, '[EQUIPMENT_TEST] CLOTHING_AUTHORITY ' + json.dumps(changed)))
            self.assertTrue(self.verify(self.logs())['issues'], ('server exact counterpart rejected', payload['fullType'], model))
        server.write_text(original)

    def test_tidy_clothing_remove_requires_empty_final_slot_and_exact_source_lifecycle(self):
        self.selection.update(cases=['tidy-clothing-remove'], mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('native', 'toolkit'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for field in equipment.CLOTHING_EFFECT_KEYS | {'nativeGenerated', 'authoritativeRestore', 'sourceSession', 'sourceCompleted', 'unrelatedTailPreserved'}:
                    rows = self.records(); rows[1]['outcome']['tidyClothing'].pop(field)
                    self.assertTrue(self.verify(self.logs(rows))['issues'], field)
                for field, value in (('id', 956), ('worn', True), ('container', 'worn-bag'), ('nativeGenerated', 2),
                                     ('sourceSession', True), ('sourceCompleted', False), ('hairUnchanged', False),
                                     ('unrelatedHandsPreserved', False), ('unrelatedTailPreserved', False)):
                    rows = self.records(); rows[1]['outcome']['tidyClothing'][field] = value
                    self.assertTrue(self.verify(self.logs(rows))['issues'], (kind, mode, field))
                for field in ('perform', 'complete', 'flush', 'legacy'):
                    rows = self.records(); rows[1]['outcome']['tidyClothing']['sharedCompletion'][field] += 1
                    self.assertTrue(self.verify(self.logs(rows))['issues'], field)
                rows = self.records(); rows[1]['outcome']['clothingCheckpoint']['worn'] = False
                self.assertTrue(self.verify(self.logs(rows))['issues'])
                if kind == 'mp':
                    server = self.root / 'server-launch.log'; original = server.read_text()
                    marker = next(line for line in original.splitlines() if '[EQUIPMENT_TEST] CLOTHING_AUTHORITY ' in line)
                    for replacement in ('', marker + '\n' + marker, marker.replace('955', '956'), marker.replace('"worn": false', '"worn": true')):
                        server.write_text(original.replace(marker, replacement))
                        self.assertTrue(self.verify(self.logs())['issues'])
                    server.write_text(original)

    def test_clothing_overlap_requires_real_transition_order_hands_and_every_native_receipt(self):
        self.selection.update(cases=list(equipment.CLOTHING_CASES), mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('native', 'toolkit'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for case, spec in equipment.CLOTHING_SPECS.items():
                    if not spec.get('overlapHand'):
                        continue
                    def target(rows):
                        return next(row['outcome'] for row in rows if row.get('id') == case)
                    for field in ('primary', 'secondary', 'originalPrimary', 'originalSecondary', 'overlap'):
                        rows = self.records(); target(rows)['tidyClothing'].pop(field)
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (case, field))
                    for field in ('primary', 'secondary', 'originalPrimary', 'originalSecondary'):
                        rows = self.records(); value = target(rows)['tidyClothing']; value[field] = float(value[field])
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (case, field, 'float'))
                    rows = self.records(); value = target(rows)['tidyClothing']; checkpoint = target(rows)['clothingCheckpoint']
                    value['originalPrimary'] = []; checkpoint['originalPrimary'] = []
                    if spec['overlapHand'] == 'secondary':
                        checkpoint['primary'] = []
                    self.assertTrue(self.verify(self.logs(rows))['issues'], (case, 'unhashable baseline'))
                    changes = [lambda p: p['intermediate'].update(primary=999),
                               lambda p: p['intermediate'].update(secondary=999),
                               lambda p: p['intermediate'].update(worn=False if spec.get('remove') else 955),
                               lambda p: p['cleanup'].reverse(), lambda p: p['cleanup'].pop(),
                               lambda p: p['cleanup'][0].update(id=999),
                               lambda p: p['cleanup'][0].update(primary=not p['cleanup'][0]['primary']),
                               lambda p: p['cleanup'][0].update(primary=1),
                               lambda p: p['cleanup'][0].update(twoHands=not p['cleanup'][0]['twoHands']),
                               lambda p: p['cleanup'][1].update(activated=True),
                               lambda p: p['sharedHands'].update(perform=True),
                               lambda p: p['sharedHands'].update(complete=99),
                               lambda p: p['sharedHands'].update(legacy=1)]
                    if kind == 'mp':
                        changes += [lambda p: p['acknowledgements'].pop(),
                                    lambda p: p['acknowledgements'][4].update(state='canceled'),
                                    lambda p: p['acknowledgements'][2].update(id=0),
                                    lambda p: p['acknowledgements'].reverse()]
                    for change in changes:
                        rows = self.records(); change(target(rows)['tidyClothing']['overlap'])
                        self.assertTrue(self.verify(self.logs(rows))['issues'], case)
                    for field in ('primary', 'secondary'):
                        rows = self.records(); target(rows)['clothingCheckpoint'][field] = 999
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (case, field))
                if kind == 'mp':
                    server = self.root / 'server-launch.log'; original = server.read_text()
                    markers = [line for line in original.splitlines() if 'CLOTHING_AUTHORITY ' in line and 'originalPrimary' in line]
                    self.assertEqual(len(markers), 14)
                    for marker in markers:
                        prefix, payload = marker.split('CLOTHING_AUTHORITY ', 1)
                        value = json.loads(payload); value['originalPrimary'] = 999
                        server.write_text(original.replace(marker, prefix + 'CLOTHING_AUTHORITY ' + json.dumps(value)))
                        self.assertTrue(self.verify(self.logs())['issues'])
                    server.write_text(original)

    def test_wristwatch_preserves_alarm_state_processing_and_every_native_receipt(self):
        cases = [case for case, spec in equipment.CLOTHING_SPECS.items() if spec.get('watch')]
        self.selection.update(cases=cases, mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('native', 'toolkit'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for case in cases:
                    def target(rows):
                        return next(row['outcome'] for row in rows if row.get('id') == case)
                    def receipts(out):
                        value = out['tidyClothing']
                        return value['overlap']['acknowledgements'] if equipment.CLOTHING_SPECS[case].get('overlapHand') else value['watchAcknowledgements']
                    changes = [lambda out: out['tidyClothing']['watch'].update(alarmHour=True),
                               lambda out: out['tidyClothing']['watch'].update(alarmMinute=41),
                               lambda out: out['tidyClothing']['watch'].update(ringing=not out['tidyClothing']['watch']['ringing']),
                               lambda out: out['tidyClothing']['watch'].update(alarmSet=int(out['tidyClothing']['watch']['alarmSet'])),
                               lambda out: out['clothingCheckpoint']['watch'].update(alarmHour=22),
                               lambda out: out['tidyClothing']['watchBaseline'].update(alarmHour=24),
                               lambda out: out['tidyClothing']['watchBaseline'].update(extra=True),
                               lambda out: out['tidyClothing'].pop('watchBaseline'),
                               lambda out: out.update(clothingCheckpoint=None),
                               lambda out: out['tidyClothing']['watchSetup'].update(capacityBeforeRemoval=1),
                               lambda out: out['tidyClothing']['watchSetup'].update(emptyExclusiveSlots=False)]
                    if equipment.CLOTHING_SPECS[case].get('ringing'):
                        for field in ('clothingCheckpoint', 'tidyClothing'):
                            changes.extend([lambda out, field=field: out[field]['watchTiming'].update(startedAgeHours=True),
                                            lambda out, field=field: out[field]['watchTiming'].update(observedAgeHours=float('nan')),
                                            lambda out, field=field: out[field]['watchTiming'].update(observedAgeHours=float('inf')),
                                            lambda out, field=field: out[field]['watchTiming'].update(observedAgeHours=100.5),
                                            lambda out, field=field: out[field]['watchTiming'].update(observedAgeHours=99.9)])
                    if kind == 'sp':
                        for field in ('clothingCheckpoint', 'tidyClothing'):
                            changes.extend([lambda out, field=field: out[field]['watchProcessing'].update(active=1),
                                            lambda out, field=field: out[field]['watchProcessing'].update(active=not out[field]['watchProcessing']['active']),
                                            lambda out, field=field: out[field]['watchProcessing'].update(pendingRemoval=True),
                                            lambda out, field=field: out[field].pop('watchProcessing')])
                    else:
                        changes.extend([lambda out: receipts(out).pop(),
                                        lambda out: receipts(out).reverse(),
                                        lambda out: receipts(out)[0].update(id=False),
                                        lambda out: receipts(out)[1].update(state='started')])
                    for change in changes:
                        rows = copy.deepcopy(self.records()); change(target(rows))
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (case, kind, mode))
                if kind == 'mp':
                    server = self.root / 'server-launch.log'; original = server.read_text()
                    for label in ('CLOTHING_AUTHORITY', 'WATCH_CHECKPOINT'):
                        marker = next(line for line in original.splitlines() if label + ' ' in line)
                        payload = json.loads(marker.split(label + ' ', 1)[1])
                        for changed in (dict(payload, watchProcessing=dict(active=True, pendingRemoval=True)),
                                        dict(payload, watchProcessing=dict(active=1, pendingRemoval=False)),
                                        dict(payload, watchProcessing=dict(active=not payload['watchProcessing']['active'], pendingRemoval=False)),
                                        dict(payload, watch=dict(payload['watch'], alarmSet=int(payload['watch']['alarmSet'])))):
                            server.write_text(original.replace(marker, '[EQUIPMENT_TEST] ' + label + ' ' + json.dumps(changed)))
                            self.assertTrue(self.verify(self.logs())['issues'], label)
                        server.write_text(original.replace(marker, marker + '\n' + marker))
                        self.assertTrue(self.verify(self.logs())['issues'], label)
                        server.write_text(original)

    def test_displaced_clothing_preserves_both_exact_items_and_cleanup_prefix(self):
        cases = [case for case, spec in equipment.CLOTHING_SPECS.items() if spec.get('temporaryType')]
        self.selection.update(cases=cases, mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            self.assertEqual(self.verify(self.logs())['issues'], [])
            for case in cases:
                for change in (lambda out: out['tidyClothing']['temporary'].update(id=955),
                               lambda out: out['tidyClothing']['temporary'].update(fullType='Base.Other'),
                               lambda out: out['tidyClothing']['temporary'].update(container='world'),
                               lambda out: out['tidyClothing']['temporary'].update(worn=True),
                               lambda out: out['clothingCheckpoint']['temporary'].update(worn=False),
                               lambda out: out['tidyClothing']['displacement']['cleanup'].pop(),
                               lambda out: out['tidyClothing']['sharedCompletion'].update(perform=0)):
                    rows = self.records(); change(next(row['outcome'] for row in rows if row.get('id') == case))
                    self.assertTrue(self.verify(self.logs(rows))['issues'], (kind, case))
                if kind == 'mp':
                    rows = self.records(); next(row['outcome'] for row in rows if row.get('id') == case)['tidyClothing']['displacement']['acknowledgements'].pop()
                    self.assertTrue(self.verify(self.logs(rows))['issues'], 'every producer/prefix/restore receipt is required')
            (self.root / 'server-launch.log').unlink(missing_ok=True)

    def test_ringing_lifetime_authority_observations_and_cleanup_are_independent(self):
        cases = [case for case, spec in equipment.CLOTHING_SPECS.items() if spec.get('ringing')]
        self.selection.update(cases=cases, mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            self.assertEqual(self.verify(self.logs())['issues'], [])
            original = self.logs()
            cleanup = next(line for line in original.splitlines() if 'WATCH_CLEANUP ' in line)
            for broken in (original.replace(cleanup, ''), original.replace(cleanup, cleanup + '\n' + cleanup),
                           original.replace(cleanup, cleanup.replace('"ringing": false', '"ringing": true'))):
                self.assertTrue(self.verify(broken)['issues'])
            for field in ('clothingCheckpoint', 'tidyClothing'):
                rows = self.records()
                next(row['outcome'] for row in rows if row.get('id') == cases[0])[field]['watchTiming'] = None
                self.assertTrue(self.verify(self.logs(rows))['issues'])
            if kind == 'mp':
                server = self.root / 'server-launch.log'; saved = server.read_text()
                for label in ('WATCH_CHECKPOINT', 'CLOTHING_AUTHORITY'):
                    marker = next(line for line in saved.splitlines() if label + ' ' in line)
                    value = json.loads(marker.split(label + ' ', 1)[1])
                    value['watchTiming']['observedAgeHours'] = 100.2 if label == 'CLOTHING_AUTHORITY' else 100.05
                    changed = saved.replace(marker, '[EQUIPMENT_TEST] ' + label + ' ' + json.dumps(value))
                    server.write_text(changed)
                    self.assertEqual(self.verify(original)['issues'], [], 'authority observation time need not equal the client')
                    if label == 'CLOTHING_AUTHORITY':
                        value['watchTiming']['observedAgeHours'] = 100.05
                        server.write_text(saved.replace(marker, '[EQUIPMENT_TEST] ' + label + ' ' + json.dumps(value)))
                        self.assertTrue(self.verify(original)['issues'], 'authority final clock must not precede its checkpoint')
                    value['watchTiming']['startedAgeHours'] = 100.01
                    server.write_text(saved.replace(marker, '[EQUIPMENT_TEST] ' + label + ' ' + json.dumps(value)))
                    self.assertTrue(self.verify(original)['issues'], 'authority must identify the same native ring start')
                server.write_text(saved)
            (self.root / 'server-launch.log').unlink(missing_ok=True)

    def test_headwear_requires_configured_type_slot_setup_and_exact_server_correlation(self):
        self.selection.update(cases=list(equipment.CLOTHING_CASES), mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('native', 'toolkit'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for case in (case for case, spec in equipment.CLOTHING_SPECS.items() if spec.get('headwear') and not spec.get('mohawk')):
                    def target(rows):
                        return next(row['outcome']['tidyClothing'] for row in rows if row.get('id') == case)
                    for field, value in (('fullType', 'Base.Socks_Ankle'), ('bodyLocation', 'base:socks'), ('worn', bool(equipment.CLOTHING_SPECS[case].get('remove'))),
                                         ('hairStyle', 'MohawkFlat'), ('sourceCompleted', False), ('nativeGenerated', 2)):
                        rows = self.records(); target(rows)[field] = value
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (case, field))
                    for field in ('emptyExclusiveSlots', 'capacityBeforeRemoval'):
                        for changed in (False, 1, None):
                            rows = self.records(); target(rows)['headwearSetup'][field] = changed
                            self.assertTrue(self.verify(self.logs(rows))['issues'], (case, field, changed))
                    rows = self.records(); target(rows).pop('headwearSetup')
                    self.assertTrue(self.verify(self.logs(rows))['issues'])
                if kind == 'mp':
                    server = self.root / 'server-launch.log'; original = server.read_text()
                    marker = next(line for line in original.splitlines() if 'CLOTHING_AUTHORITY ' in line and 'Hat_Beany' in line)
                    server.write_text(original.replace(marker, marker.replace('Hat_Beany', 'Hat_BoxingRed')))
                    self.assertTrue(self.verify(self.logs())['issues'])
                    server.write_text(original)

    def test_headwear_scene_requires_single_authority_root_conservation_proof(self):
        self.selection.update(cases=list(equipment.CLOTHING_CASES), mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            text = self.logs()
            self.assertEqual(self.verify(text)['issues'], [])
            path = self.root / ('server-launch.log' if kind == 'mp' else 'client1-launch.log')
            original = path.read_text()
            marker = self.scene_marker().strip()
            proof = json.loads(marker.split('SCENE_HEADWEAR ', 1)[1])
            invalid = [None, dict(proof, authority='client'), dict(proof, rootRetained=1),
                       dict(proof, prepared=False), dict(proof, extra=True),
                       dict(proof, normalizedItems=proof['normalizedItems'] * 2)]
            for field, value in (('id', True), ('id', -1), ('fullType', ''), ('location', ''), ('extra', True)):
                changed = copy.deepcopy(proof); changed['normalizedItems'][0][field] = value; invalid.append(changed)
            for changed in invalid:
                replacement = '' if changed is None else '[EQUIPMENT_TEST] SCENE_HEADWEAR ' + json.dumps(changed)
                altered = original.replace(marker, replacement)
                if kind == 'mp':
                    path.write_text(altered); result = self.verify(text)
                else:
                    result = self.verify(altered)
                self.assertTrue(result['issues'], (kind, changed))
            duplicated = original.replace(marker, marker + '\n' + marker)
            if kind == 'mp':
                path.write_text(duplicated); result = self.verify(text)
            else:
                result = self.verify(duplicated)
            self.assertTrue(result['issues'])
            path.write_text(original)
        self.selection['cases'] = ['hands-chain']
        self.assertEqual(equipment._verify_scene('', self.selection), ([], None))
        self.assertTrue(equipment._verify_scene(self.scene_marker() + marker, self.selection)[0])

    def test_belt_requires_empty_queue_and_exact_effect_checks(self):
        self.selection['cases'] = ['belt-knife', 'belt-hammer']
        self.assertEqual(self.verify(self.logs())['issues'], [])
        for case in self.selection['cases']:
            for field in ('emptyQueueClick', 'slotsVerified', 'belt', 'favoritePreserved', 'postprocessingVerified'):
                with self.subTest(case=case, field=field):
                    rows = self.records()
                    next(row for row in rows if row.get('id') == case)['outcome'].pop(field)
                    self.assertTrue(self.verify(self.logs(rows))['issues'])

    def test_walking_belt_requires_real_motion_and_isolated_probe(self):
        self.selection.update(cases=['belt-knife', 'belt-hammer'],
                              mods=['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'], options={'belt_walk': True})
        equipment.validate(self.selection)
        self.assertEqual(self.verify(self.logs())['issues'], [])
        for field in ('walkingVerified', 'walkedDuringTransfer', 'walkedDuringAttach', 'walkReleased', 'walkDistance'):
            rows = self.records()
            next(row for row in rows if row.get('id') == 'belt-knife')['outcome'].pop(field)
            self.assertTrue(self.verify(self.logs(rows))['issues'], field)
        for key, value in (('belt_walk', 1), ('belt_favorite', 'true')):
            with self.assertRaises(ValueError):
                equipment.validate(dict(self.selection, options={key: value}))
        with self.assertRaises(ValueError):
            equipment.validate(dict(self.selection, mods=['PZSurvivorToolkit']))
        with self.assertRaises(ValueError):
            equipment.validate(dict(self.selection, cases=['hands-chain']))
        for role in ('client1',):
            (self.root / role / 'mods/ActionQueueTest/42/media/lua/shared').mkdir(parents=True)
        probe = self.root / 'walk-probe.jar'
        probe.write_bytes(b'isolated native walking probe')
        runtime = {'roles': {'client1': {}}}
        with patch.object(equipment, '_transfer_probe', return_value=probe) as compile_probe:
            equipment.stage(ROOT, self.root, None, None, self.selection, {}, runtime)
            compile_probe.assert_called_once()
        self.assertEqual(runtime['fixture']['mods'], ['EquipmentTransferProbe'])

    def test_restore_requires_positive_exact_phases_and_world_effects(self):
        self.selection.update(cases=['tidy-hands', 'tidy-floor', 'tidy-empty-hands'], mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('toolkit', 'native'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for index in (1, 3):
                    for key in ('perform', 'complete', 'flush', 'legacy', 'equip', 'activation', 'unequip'):
                        rows = self.records()
                        rows[index]['outcome']['restoreCompletion'][key] += 1
                        self.assertTrue(self.verify(self.logs(rows))['issues'])
                rows = self.records(); rows[2]['outcome']['floorRestoreVerified'] = False
                self.assertTrue(self.verify(self.logs(rows))['issues'])
                if kind == 'mp':
                    server = self.root / 'server-launch.log'
                    original = server.read_text()
                    marker = '[EQUIPMENT_TEST] FLOOR_RESTORE id=731 result=true'
                    for replacement in ('', marker + '\n' + marker, marker.replace('731', '732'), marker.replace('true', 'false')):
                        server.write_text(original.replace(marker, replacement))
                        self.assertTrue(self.verify(self.logs())['issues'])
                    server.write_text(original)

    def test_subset_and_mode_selection(self):
        for mode in ('native', 'toolkit'):
            for cases in ([case] for case in equipment.CASES):
                equipment.validate(dict(self.selection, mode=mode, cases=cases, languages=['RU']))
        for change in ({'cases': []}, {'cases': ['unknown']}, {'cases': ['waiting-cancel', 'hands-chain']},
                       {'cases': ['hands-chain', 'hands-chain']}, {'clients': True}, {'clients': 2},
                       {'kind': 'mp'}, {'mode': 'unknown'}, {'languages': ['EN', 'RU']}, {'mods': []},
                       {'options': {'world_template': '/saved/world'}}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                equipment.validate(dict(self.selection, **change))

    def test_native_and_toolkit_keep_their_distinct_outcomes(self):
        for mode in ('native', 'toolkit'):
            self.selection['mode'] = mode
            self.assertEqual(self.verify(self.logs())['issues'], [])
        self.selection['cases'] = ['bag-capacity']
        self.assertEqual(self.verify(self.logs())['issues'], [])

    def test_mp_requires_server_and_correlated_native_outcomes(self):
        self.selection.update(kind='mp', mods=['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'])
        equipment.validate(self.selection)
        for mode in ('native', 'toolkit'):
            self.selection['mode'] = mode
            self.assertEqual(self.verify(self.logs())['issues'], [])
            changed = self.records()
            changed[1]['outcome']['authoritative'] = False
            self.assertTrue(self.verify(self.logs(changed))['issues'])
            changed = self.records()
            changed[1]['outcome']['receipts'] = True
            self.assertTrue(self.verify(self.logs(changed))['issues'])
            text = self.logs()
            self.assertTrue(self.verify(text.replace('[EQUIPMENT_TEST] CAPTURE case=hands-chain', '[IGNORED] CAPTURE case=hands-chain', 1))['issues'])
        (self.root / 'server-launch.log').write_text('[EQUIPMENT_TEST] SERVER_READY\n')
        self.assertTrue(self.verify(self.logs())['issues'])

    def test_only_client_owned_hotbar_timer_may_cancel_with_authoritative_effects(self):
        self.selection.update(kind='mp', mods=['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'])
        rows = self.records()
        hotbar = next(row for row in rows if row.get('id') == 'hotbar-chain')
        hotbar['outcome']['receiptStates'] = ['canceled']
        self.assertEqual(self.verify(self.logs(rows))['issues'], [])
        for states in (['started'], ['rejected'], [], ['completed', 'canceled'], None):
            changed = copy.deepcopy(rows)
            next(row for row in changed if row.get('id') == 'hotbar-chain')['outcome']['receiptStates'] = states
            self.assertTrue(self.verify(self.logs(changed))['issues'])
        for case in ('hands-chain', 'waiting-cancel', 'bag-capacity', 'clothing-chain'):
            changed = copy.deepcopy(rows)
            target = next(row for row in changed if row.get('id') == case)['outcome']
            target['receiptStates'] = ['canceled'] * target['receipts']
            if target['receipts']:
                self.assertTrue(self.verify(self.logs(changed))['issues'])
        hotbar['outcome']['authoritative'] = False
        self.assertTrue(self.verify(self.logs(rows))['issues'])

    def test_mp_stage_pins_read_only_transfer_probe_for_both_roles(self):
        self.selection.update(kind='mp', mods=['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'])
        for role in ('server', 'client1'):
            (self.root / role / 'mods/ActionQueueTest/42/media/lua/shared').mkdir(parents=True)
        probe = self.root / 'probe.jar'
        probe.write_bytes(b'read-only fixture probe')
        runtime = {'roles': {'server': {}, 'client1': {}}, 'fixture': {'mods': []}}
        with patch.object(equipment, '_transfer_probe', return_value=probe), patch.object(equipment, '_item_shape_probe'):
            equipment.stage(ROOT, self.root, None, None, self.selection, {}, runtime)
        self.assertEqual(runtime['fixture']['mods'], ['EquipmentTransferProbe'])
        for role in ('server', 'client1'):
            layer = self.root / role / 'mods/EquipmentTransferProbe/42'
            self.assertEqual((layer / 'media/java/EquipmentTransferProbe.jar').read_bytes(), probe.read_bytes())
            self.assertIn('javaPkgName=net.alexredby.equipmentprobe', (layer / 'mod.info').read_text())
        self.assertIn(ROOT / 'tests/native_queue/equipment/java/Main.java', equipment.sources(ROOT, self.selection))

    def test_composite_rack_control_replays_real_move_and_rejects_split_or_incomplete_roundtrip(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        script = r'''
local root=arg[1]
local function read(path)local f=assert(io.open(root..'/'..path));local s=f:read('*a');f:close();return s end
local function excerpt(source,first,last)
 local start=assert(source:find(first,1,true));local finish=assert(source:find(last,start+#first,true))
 assert(loadstring(source:sub(start,finish-1)))()
end
local checks=dofile(root..'/tests/native_queue/support/QueueScenarioChecks.lua')
require=function(name)assert(name=='QueueScenarioChecks');return checks end
local rackControls=dofile(root..'/tests/native_queue/equipment/shared/QueueEquipmentRack.lua')
Operations={};excerpt(read('PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua'),
 'function Operations.bounds(queue, action)','local canMerge =')
Queue={};Toolkit={}
excerpt(read('PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueue.lua'),
 'function Queue.move(queue, action, target, after)','local function clearStop(queue)')
local function run(id,fault)
 local token={};local front={toolkitQueueOperation={},action={}};local tail={toolkitQueueOperation={}}
 local pickup={toolkitQueueOperation=token};local equip={toolkitQueueOperation=token};local rack={toolkitQueueOperation=token}
 local player={};local item={getID=function()return 7 end,getAmmoType=function()return {getItemKey=function()return 'Base.Bullets9mm'end}end}
 local state={id=id,player=player,pickup=item,frontAction=front,tailAction=tail,pickupAction=pickup,rackEquipAction=equip,rackAction=rack}
 local queue={queue={front,pickup,equip,rack,tail},current=front}
 function queue:indexOf(action)for i,value in ipairs(self.queue)do if value==action then return i end end;return -1 end
 Policy={record=function()end,editUnchanged=function()return true end,
  evaluateCancel=function()return {allowed=fault=='cancel-permitted',reason='operation_dependent'}end}
 function Policy.evaluateMove(q,action,target,after)
  local first,last=Operations.bounds(q,action);local targetFirst,targetLast=Operations.bounds(q,target)
  if fault=='split'then first,last=q:indexOf(action),q:indexOf(action)end
  local to=after and targetLast+1 or targetFirst;if first<to then to=to-(last-first+1)end
  return {allowed=fault~='stale-denial',reason='move_dependent',first=first,last=last,to=to,snapshot={}}
 end
 local moves=0
 local api={cancelOperation=function()return false,'operation_dependent'end}
 function api.move(...)
  moves=moves+1
  if fault=='incomplete-restore'and moves==2 then return true end
  local ok=Queue.move(...)
  if fault=='current'then queue.current=tail end
  if fault=='ownership'then equip.toolkitQueueOperation={}end
  if fault=='internal-order'then queue.queue[4],queue.queue[5]=queue.queue[5],queue.queue[4]end
  return ok
 end
 local definitions={inspect=function()return {knownInputs=true,items={[7]=true},equipment=player,
  outputTypes={['Base.Bullets9mm']=true},cancelOperation=fault=='unsafe-contract'},'native.ISRackFirearm'end}
 rackControls.controls(state,{queue=function()return queue end,api=api,policy=Policy,operations=Operations,definitions=definitions})
 assert(moves==2 and state.rackWholeOperationMoveVerified and state.rackCancellationProtected and state.independentMoveVerified)
 checks.unchanged(queue,{front,pickup,equip,rack,tail})
end
for _,id in ipairs({'tidy-hands','tidy-empty-hands'})do
 run(id)
 for _,fault in ipairs({'split','incomplete-restore','internal-order','current','ownership','stale-denial','cancel-permitted','unsafe-contract'})do
  assert(not pcall(run,id,fault),'fixture accepted unsafe/incomplete composite proof '..fault)
 end
end
'''
        target = self.root / 'rack-controls.lua'
        target.write_text(script)
        result = subprocess.run([lua, str(target), str(ROOT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_rack_controls_require_verified_whole_operation_move_and_preserved_cancellation_guard(self):
        self.selection['cases'] = ['tidy-hands', 'tidy-empty-hands']
        self.assertEqual(self.verify(self.logs())['issues'], [])
        for field in ('rackWholeOperationMoveVerified', 'rackCancellationProtected', 'independentMoveVerified'):
            for index in (1, 2):
                for value in (False, None, 1):
                    rows = self.records(); rows[index]['outcome'][field] = value
                    self.assertTrue(self.verify(self.logs(rows))['issues'], (field, index, value))

    def test_missing_effect_or_policy_proof_fails(self):
        records = self.records()
        for key in records[1]['outcome']:
            for value in (False, 1, None):
                changed = copy.deepcopy(records)
                changed[1]['outcome'][key] = value
                with self.subTest(key=key, value=value):
                    self.assertTrue(self.verify(self.logs(changed))['issues'])
        for index, key in ((0, 'queueEnabled'), (0, 'nativeDurations'), (-1, 'performed')):
            changed = copy.deepcopy(records)
            changed[index][key] = True if key == 'performed' else 1
            self.assertTrue(self.verify(self.logs(changed))['issues'])

    def test_event_context_duplicates_and_order_fail(self):
        records = self.records()
        for changed in (records[1:], records + [records[-1]], [records[0], records[2], records[1], *records[3:]]):
            self.assertTrue(self.verify(self.logs(changed))['issues'])
        for key, value in (('mode', 'native'), ('actor', 'client2'), ('suite', 'health')):
            changed = copy.deepcopy(records)
            changed[1][key] = value
            self.assertTrue(self.verify(self.logs(changed))['issues'])

    def test_receipts_and_completion_cannot_be_missing_or_duplicated(self):
        text = self.logs()
        for changed in (text.replace('[EQUIPMENT_TEST] RECEIPT case=hands-chain', ''),
                        text + '\n[EQUIPMENT_TEST] RECEIPT case=hands-chain',
                        text.replace('[EQUIPMENT_TEST] COMPLETE', '[EQUIPMENT_TEST] COMPLETE_PENDING'),
                        text + '\n[QUEUE_TEST] FAIL fixture', text + '\n[EQUIPMENT_TEST] COMPLETE'):
            self.assertTrue(self.verify(changed)['issues'])
        self.assertFalse(equipment.complete(self.selection, 'client2', text))

    def test_bulk_requires_merge_cancellation_and_postprocess_evidence(self):
        self.selection['mods'].append('P4TidyUpMeister')
        for mode in ('native', 'toolkit'):
            self.selection['mode'] = mode
            for case in ('bulk-pickup', 'bulk-waiting-cancel', 'bulk-mixed'):
                self.selection['cases'] = [case]
                self.assertEqual(self.verify(self.logs())['issues'], [])
                keys = ['exactBulkContainers']
                keys += ['bulkCancelled', 'unrelatedTailPreserved'] if case == 'bulk-waiting-cancel' else ['lightMerged', 'heavySeparate', 'childrenWiped']
                if case == 'bulk-mixed':
                    keys += ['borrowedReturned', 'sharedExecutor']
                for key in keys:
                    rows = self.records()
                    rows[1]['outcome'][key] = False
                    with self.subTest(mode=mode, case=case, key=key):
                        self.assertTrue(self.verify(self.logs(rows))['issues'])

    def test_native_item_shape_preflight_runs_once_only_for_selected_ordinary_hotbar_cases(self):
        for cases in (['tidy-hotbar'], ['tidy-hotbar-normal-left'], ['tidy-hotbar-normal-right'],
                      ['tidy-hotbar-normal-left', 'tidy-hotbar-normal-right'], ['tidy-hotbar-radio-off'], ['tidy-hotbar-radio-on']):
            self.selection['cases'] = cases
            with patch.object(equipment, '_item_shape_probe') as probe:
                equipment.stage(ROOT, self.root, None, None, self.selection, {}, {'roles': {}})
                if any(equipment.HOTBAR_CASES[case].get('ordinary') or equipment.HOTBAR_CASES[case].get('radio') for case in cases):
                    probe.assert_called_once_with(ROOT, self.root, None, None)
                else:
                    probe.assert_not_called()

    def test_native_item_shape_failure_stops_stage_before_transfer_probe_or_role_staging(self):
        self.selection.update(cases=['tidy-hotbar-normal-left'], kind='mp',
                              mods=['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'])
        with patch.object(equipment, '_item_shape_probe', side_effect=ValueError('native item shape rejected')), \
                patch.object(equipment, '_transfer_probe') as transfer, patch.object(equipment.shutil, 'copy2') as copy_file:
            with self.assertRaisesRegex(ValueError, 'native item shape rejected'):
                equipment.stage(ROOT, self.root, None, None, self.selection, {}, {'roles': {'client1': {}}})
            transfer.assert_not_called()
            copy_file.assert_not_called()

    def test_stage_pins_shared_json_writer_and_only_equipment_sources(self):
        target = self.root / 'client1/mods/ActionQueueTest/42/media/lua/shared'
        target.mkdir(parents=True)
        runtime = {'fixture': {'mods': []}}
        with patch.object(equipment, '_item_shape_probe'):
            equipment.stage(ROOT, self.root, None, None, self.selection, {}, runtime)
        self.assertEqual((target / 'QueueHealthEvents.lua').read_bytes(),
                         (ROOT / 'tests/native_queue/health/shared/QueueHealthEvents.lua').read_bytes())
        self.assertEqual(runtime['fixture']['server_ready'], '[EQUIPMENT_TEST] SERVER_READY')
        self.assertTrue((target.parent / 'client/ZZStartup.lua').is_file())
        sources = equipment.sources(ROOT, self.selection)
        self.assertTrue(any('equipment' in path.parts for path in sources))
        self.assertTrue(all('equipment' in path.parts or path.name in ('QueueHealthEvents.lua', 'QueueScenarioChecks.lua', 'ZZStartup.lua') for path in sources))

    def test_tidy_shared_completion_requires_real_returns_and_exact_phase_counts(self):
        self.selection['mods'].append('P4TidyUpMeister')
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('toolkit', 'native'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for key in ('perform', 'complete', 'flush', 'legacy', 'cleanupConfirmed', 'authoritativeCleanup'):
                    for value in (None, True, -1, '1', 1.0):
                        rows = self.records()
                        rows[1]['outcome']['tidyCompletion'][key] = value
                        with self.subTest(kind=kind, mode=mode, key=key, value=value):
                            self.assertTrue(self.verify(self.logs(rows))['issues'])
                for value in (None, {}, [], dict(perform=0, complete=0, flush=0, legacy=0, extra=0)):
                    rows = self.records()
                    rows[1]['outcome']['tidyCompletion'] = value
                    self.assertTrue(self.verify(self.logs(rows))['issues'])
                rows = self.records()
                del rows[1]['outcome']['tidyCompletion']
                self.assertTrue(self.verify(self.logs(rows))['issues'])
                for key in ('complete', 'flush', 'legacy', 'cleanupConfirmed', 'authoritativeCleanup'):
                    rows = self.records()
                    rows[1]['outcome']['tidyCompletion'][key] += 1
                    self.assertTrue(self.verify(self.logs(rows))['issues'])
                for case in equipment.TIDY_RETURN_CASES:
                    rows = self.records()
                    target = next(row for row in rows if row.get('id') == case)['outcome']
                    count = 0 if mode == 'toolkit' else 1
                    target['tidyCompletion'].update(perform=count, complete=count if kind == 'sp' else 0, flush=count, legacy=0)
                    if mode == 'native' or case in equipment.TIDY_RETURN_EXACT_CASES:
                        self.assertTrue(self.verify(self.logs(rows))['issues'])
                    else:
                        self.assertEqual(self.verify(self.logs(rows))['issues'], [])

    def test_tidy_explicit_intent_evidence_requires_strict_correlated_counts(self):
        self.selection.update(cases=['hands-chain', 'clothing-chain', 'tidy-hands', 'tidy-empty-hands'],
                              mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('native', 'toolkit'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for field in ('explicitConfirmed', 'authoritativeIntent', 'cleanupConfirmed', 'authoritativeCleanup'):
                    for value in (None, True, False, -1, '3', 3.0, {}, []):
                        rows = self.records()
                        rows[1]['outcome']['tidyCompletion'][field] = value
                        with self.subTest(kind=kind, mode=mode, field=field, value=value):
                            self.assertTrue(self.verify(self.logs(rows))['issues'])
                    rows = self.records()
                    del rows[1]['outcome']['tidyCompletion'][field]
                    self.assertTrue(self.verify(self.logs(rows))['issues'])
                for explicit, authoritative in ((0, 0), (2, 2 if kind == 'mp' else 0),
                                                 (4, 3 if kind == 'mp' else 0),
                                                 (3, 2 if kind == 'mp' else 1)):
                    rows = self.records()
                    rows[1]['outcome']['tidyCompletion'].update(explicitConfirmed=explicit,
                                                                authoritativeIntent=authoritative)
                    with self.subTest(kind=kind, mode=mode, explicit=explicit, authoritative=authoritative):
                        self.assertTrue(self.verify(self.logs(rows))['issues'])
                expected_cleanup = int(mode == 'toolkit')
                for confirmed, authoritative in ((expected_cleanup + 1, expected_cleanup if kind == 'mp' else 0),
                                                 (expected_cleanup, expected_cleanup + 1)):
                    rows = self.records()
                    rows[1]['outcome']['tidyCompletion'].update(cleanupConfirmed=confirmed,
                                                                authoritativeCleanup=authoritative)
                    with self.subTest(kind=kind, mode=mode, confirmed=confirmed, authoritative=authoritative):
                        self.assertTrue(self.verify(self.logs(rows))['issues'])
                for case in ('tidy-hands', 'tidy-empty-hands'):
                    rows = self.records()
                    target = next(row for row in rows if row.get('id') == case)['outcome']['tidyCompletion']
                    target.update(explicitConfirmed=1, authoritativeIntent=0)
                    self.assertTrue(self.verify(self.logs(rows))['issues'])
                rows = self.records()
                target = next(row for row in rows if row.get('id') == 'clothing-chain')['outcome']['tidyCompletion']
                target.update(explicitConfirmed=1, authoritativeIntent=2)
                self.assertTrue(self.verify(self.logs(rows))['issues'])
                # Other scenarios validate the count shape without inventing an expected number of intents.
                target.update(explicitConfirmed=7, authoritativeIntent=4)
                self.assertEqual(self.verify(self.logs(rows))['issues'], [])

    def test_bounded_p4_group_requires_every_exact_return_and_server_inventory(self):
        self.selection.update(cases=['tidy-empty-hands', 'tidy-group'], mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('native', 'toolkit'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for missing in (None, {}, [], True):
                    rows = self.records()
                    rows[2]['outcome']['tidyGroup'] = missing
                    self.assertTrue(self.verify(self.logs(rows))['issues'])
                for key in ('nativeGroups', 'nativeItems', 'groupSizes', 'obligationGroups', 'completedItems', 'items', 'unrelatedTailPreserved'):
                    rows = self.records()
                    del rows[2]['outcome']['tidyGroup'][key]
                    self.assertTrue(self.verify(self.logs(rows))['issues'], key)
                for mutation in ('one-item', 'duplicate', 'wrong-container', 'wrong-type', 'partial', 'missing-completion', 'extra-group'):
                    rows = self.records()
                    group = rows[2]['outcome']['tidyGroup']
                    if mutation == 'one-item': group['items'].pop()
                    elif mutation == 'duplicate': group['items'][1]['id'] = group['items'][0]['id']
                    elif mutation == 'wrong-container': group['items'][1]['container'] = 'root'
                    elif mutation == 'wrong-type': group['items'][1]['fullType'] = 'Base.Screwdriver'
                    elif mutation == 'extra-group': group['nativeGroups'] += 1
                    elif mode == 'toolkit':
                        if mutation == 'partial': group['completedItems'][1]['state'] = 'waiting'
                        else: group['completedItems'].pop()
                    else: group['completedItems'] = [dict(id=901, fullType='Base.Nails', state='completed')]
                    self.assertTrue(self.verify(self.logs(rows))['issues'], mutation)
                if kind == 'mp':
                    server = self.root / 'server-launch.log'
                    valid = server.read_text()
                    server.write_text(valid.replace('GROUP_AUTHORITY', 'GROUP_MISSING'))
                    self.assertTrue(self.verify(self.logs())['issues'])
                    server.write_text(valid)

    def test_p4_multigroup_requires_three_attempts_one_executor_and_exact_ledger(self):
        self.selection.update(cases=['tidy-multigroup'], mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('native', 'toolkit'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for field in ('executorCount', 'attempts', 'sameNativeExecutor'):
                    rows = self.records()
                    del rows[1]['outcome']['tidyGroup'][field]
                    self.assertTrue(self.verify(self.logs(rows))['issues'], field)
                rows = self.records()
                rows[1]['outcome']['tidyGroup']['groupSizes'] = [2, 2] if mode == 'toolkit' else [1, 1, 1, 1]
                self.assertTrue(self.verify(self.logs(rows))['issues'])
                if mode == 'native':
                    continue
                for field, value in (('perform', 1), ('flush', 3), ('cleanupConfirmed', 3), ('complete', 1 if kind == 'sp' else 3)):
                    rows = self.records()
                    rows[1]['outcome']['tidyCompletion'][field] = value
                    self.assertTrue(self.verify(self.logs(rows))['issues'], field)
                for mutation in ('missing', 'duplicate-ordinal', 'bool-ordinal', 'wrong-phase', 'waiting', 'authority',
                                 'transaction', 'duplicate-item', 'missing-item', 'heavy-merged', 'extra-key', 'split-executor'):
                    rows = self.records()
                    group = rows[1]['outcome']['tidyGroup']
                    attempts = group['attempts']
                    if mutation == 'missing': attempts.pop()
                    elif mutation == 'duplicate-ordinal': attempts[1]['ordinal'] = 1
                    elif mutation == 'bool-ordinal': attempts[0]['ordinal'] = True
                    elif mutation == 'wrong-phase': attempts[1]['phase'] = 'stop'
                    elif mutation == 'waiting': attempts[1]['state'] = 'waiting'
                    elif mutation == 'authority': attempts[1]['authority'] = 'unavailable'
                    elif mutation == 'transaction': attempts[1]['transaction'] = 0 if kind == 'mp' else 1
                    elif mutation == 'duplicate-item': attempts[1]['items'] = copy.deepcopy(attempts[0]['items'])
                    elif mutation == 'missing-item': attempts[2]['items'].pop()
                    elif mutation == 'heavy-merged': attempts[2]['items'][0], attempts[0]['items'][0] = attempts[0]['items'][0], attempts[2]['items'][0]
                    elif mutation == 'extra-key': attempts[1]['retry'] = True
                    elif mutation == 'split-executor': group['executorCount'] = 3
                    self.assertTrue(self.verify(self.logs(rows))['issues'], mutation)
                if kind == 'mp':
                    # Native transaction bytes can wrap. The sealed ordinal identifies each attempt.
                    rows = self.records()
                    for attempt in rows[1]['outcome']['tidyGroup']['attempts']:
                        attempt['transaction'] = -127
                    self.assertEqual(self.verify(self.logs(rows))['issues'], [])
                    server = self.root / 'server-launch.log'
                    valid = server.read_text()
                    server.write_text(valid.replace('GROUP_AUTHORITY', 'GROUP_MISSING'))
                    self.assertTrue(self.verify(self.logs())['issues'])
                    server.write_text(valid)

    def test_p4_return_ownership_requires_exact_original_confirmed_pickups(self):
        self.selection.update(cases=['tidy-group', 'tidy-multigroup'], mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for mode in ('native', 'toolkit'):
                self.selection['mode'] = mode
                self.assertEqual(self.verify(self.logs())['issues'], [])
                for case in self.selection['cases']:
                    for field in ('pickupOperations', 'pickupItems', 'ownershipAtBegin', 'ownershipCompleted'):
                        rows = self.records()
                        group = next(row['outcome']['tidyGroup'] for row in rows if row.get('id') == case)
                        del group[field]
                        self.assertTrue(self.verify(self.logs(rows))['issues'], (kind, mode, case, field))
                    if mode == 'native':
                        for field in ('pickupItems', 'ownershipAtBegin', 'ownershipCompleted'):
                            rows = self.records()
                            group = next(row['outcome']['tidyGroup'] for row in rows if row.get('id') == case)
                            group[field] = [dict(id=901, fullType='Base.Nails', owner=1)]
                            self.assertTrue(self.verify(self.logs(rows))['issues'], (mode, field))
                        continue
                    for field in ('pickupItems', 'ownershipAtBegin', 'ownershipCompleted'):
                        for mutation in ('missing', 'duplicate', 'foreign-id', 'type', 'owner', 'bool-owner', 'attempt',
                                         'bool-attempt', 'transaction', 'authority', 'extra', 'partial', 'shared', 'non-bool-shared'):
                            rows = self.records()
                            values = next(row['outcome']['tidyGroup'][field] for row in rows if row.get('id') == case)
                            if mutation == 'missing': values.pop()
                            elif mutation == 'duplicate': values[1] = copy.deepcopy(values[0])
                            elif mutation == 'foreign-id': values[0]['id'] = 999
                            elif mutation == 'type': values[0]['fullType'] = 'Base.Screwdriver'
                            elif mutation == 'owner': values[0]['owner'] = 2
                            elif mutation == 'bool-owner': values[0]['owner'] = True
                            elif mutation == 'attempt': values[0]['pickupAttempt'] = 0
                            elif mutation == 'bool-attempt': values[0]['pickupAttempt'] = True
                            elif mutation == 'transaction': values[0]['pickupTransaction'] = 0 if kind == 'mp' else 3
                            elif mutation == 'authority': values[0]['pickupAuthority'] = 'waiting'
                            elif mutation == 'extra': values[0]['executor'] = 1
                            elif mutation == 'partial': values[0]['state'] = 'unbound'
                            elif mutation == 'shared': values[0]['shared'] = True
                            elif mutation == 'non-bool-shared': values[0]['shared'] = 0
                            self.assertTrue(self.verify(self.logs(rows))['issues'], (kind, case, field, mutation))

    def test_p4_unrelated_ownership_requires_exclusive_frozen_pickup_expectation(self):
        self.selection.update(cases=['tidy-group', 'tidy-multigroup'], mods=['PZSurvivorToolkit', 'P4TidyUpMeister'])
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            rows = self.records()
            for row in rows:
                group = row.get('outcome', {}).get('tidyGroup')
                if group:
                    for field in ('pickupItems', 'ownershipAtBegin', 'ownershipCompleted'):
                        for item in group[field]:
                            item['shared'] = True
            self.assertTrue(self.verify(self.logs(rows))['issues'], 'unrelated items must not remain shared')
            for field in ('pickupItems', 'ownershipAtBegin', 'ownershipCompleted'):
                for expected_shared in (False, True):
                    changed = copy.deepcopy(rows)
                    for row in changed:
                        group = row.get('outcome', {}).get('tidyGroup')
                        if group:
                            for other in ('pickupItems', 'ownershipAtBegin', 'ownershipCompleted'):
                                for item in group[other]:
                                    item['shared'] = expected_shared
                            group[field][0]['shared'] = not expected_shared
                    self.assertTrue(self.verify(self.logs(changed))['issues'], (kind, field, expected_shared))

    def test_p4_multigroup_observer_tracks_native_member_changes_and_one_flush(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        script = r'''
local root=arg[1]
local function run(kind,fault)
 require=function(name)if name=='QueueEquipmentClothing'or name=='QueueEquipmentHotbar'then return dofile(root..'/tests/native_queue/equipment/shared/'..name..'.lua')end end
 isClient=function()return kind=='mp'end
 Events={OnGameStart={Add=function()end}}
 ISQueueActionsAction={start=function()end}
 getActivatedMods=function()return {contains=function()return true end}end
 local inventory,source={},{}
 local items={}
 for id=1,4 do
  local value={id=id,kind=id<3 and 'Base.Nails' or 'Base.Hammer'}
  function value:getID()return self.id end
  function value:getFullType()return self.kind end
  function value:getWeight()return self.id<3 and 0.01 or 1 end
  function value:getContainer()return self.container end
  value.container=source
  items[id]=value
 end
 function inventory:getItemById(id)
  for _,item in ipairs(items) do
   if item:getID()==id and item:getContainer()==self then return item end
  end
 end
 local groups={{items={items[3]},time=50},{items={items[1],items[2]},time=5},{items={items[4]},time=50}}
 local present=true
 local player={getCharacterActions=function()return {contains=function()return present end}end}
 local action={character=player,item=items[3],srcContainer=inventory,destContainer=source,action={},toolkitQueueOperation={},queueList=groups}
 local native=action.action
 local queue={character=player,current=action,queue={action},onCompleted=function(self,a)
  assert(self.current==a);self.current=nil;self.queue={}
 end}
 ISTimedActionQueue={queues={[player]=queue}}
 PZSurvivorToolkit={Settings={actionQueue=function()return true end}}
 local toolkit=PZSurvivorToolkit
 local lifecycle=dofile(root..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua')
 toolkit.ActionQueueOperations={perform=function()end,deferCompletion=lifecycle.deferCompletion}
 toolkit.ActionQueueDefinitions={inspect=function(value)if value.srcContainer==inventory then return {},'compat.tidy-transfers' end;return {} end}
 local callback
 toolkit.ActionQueueTidyIntent={status=function()return true end,begin=function()end,finish=function()end,
  observeTransfers=function(value)callback=value end}
 toolkit.ActionQueueCarts=nil
 toolkit.ActionQueueCompat={isInstalled=function()return false end,verifySources=function()return false end}
 toolkit.ActionQueueAcknowledgements={}
 ISInventoryPaneContextMenu={OnTwoHandsEquip=function()end,OnPrimaryWeapon=function()end,equipWeapon=function()end}
 ISInventoryPane={getActualItems=function()end}
 getFilenameOfClosure=function()return 'fixture' end
 isItemTransactionDone=function()return true end
 isItemTransactionRejected=function()return false end
 local attempts={}
 local sourceOwner={}
 local returnMerged=false
 local completed={}
 for _,item in ipairs(items) do completed[#completed+1]={id=item:getID(),fullType=item:getFullType(),state='completed'} end
 toolkit.ActionQueueSettlement={captureEffect=function()end,confirmEffect=function()end,remember=function()return true end,
  beginReturn=function()return true end,finishReturn=function()return true end,
  returnState=function()return 'completed' end,returnItems=function()return completed end,
  returnAttempts=function()return attempts end,
  returnOwnership=function()
   local values={}
   for _,item in ipairs(items) do
    local ordinal=item.id<3 and 1 or item.id-1
    values[#values+1]={id=item:getID(),fullType=item:getFullType(),owner=sourceOwner,shared=fault=='unknown-sibling',
     state=#attempts==3 and 'completed' or 'active',pickupAttempt=ordinal,
     pickupTransaction=kind=='mp' and -120+ordinal or 0,pickupAuthority=kind=='mp' and 'completed' or 'native'}
   end
   if kind=='sp' and not returnMerged then values={values[3]} end
   if fault=='owner' then values[1].owner=action.toolkitQueueOperation end
   if fault=='partial' then table.remove(values) end
   if fault=='duplicate' then values[2]=values[1] end
   if fault=='unbound' then values[1].state='unbound';values[1].owner=nil end
   if fault=='authority' then values[1].pickupAuthority='waiting' end
   if fault=='attempt' then values[1].pickupAttempt=9 end
   if fault=='transaction' then values[1].pickupTransaction=kind=='mp' and 0 or 99 end
   if fault=='shared' then values[1].shared=true end
   return values
  end}
 local observer=dofile(root..'/tests/native_queue/equipment/shared/QueueEquipmentCompletion.lua').observe(toolkit,{kind=kind,mode='toolkit'})
 observer.watch({id='tidy-multigroup',root=inventory,source=source,baseline=items,
  groupOne=items[1],groupTwo=items[2],groupHeavyOne=items[3],groupHeavyTwo=items[4]})
 -- Observe the source executor independently, with an operation distinct from cleanup.
 local pickupGroups={{items={items[1],items[2]}},{items={items[3]}},{items={items[4]}}}
 local pickup={character=player,item=items[1],srcContainer=source,destContainer=inventory,action={},
  toolkitQueueOperation=sourceOwner,queueList=pickupGroups}
 queue.current=pickup;queue.queue={pickup}
 local scope={}
 toolkit.ActionQueueSettlement.remember(scope,pickup,{knownInputs=true,items={[1]=true,[2]=true,[3]=true,[4]=true}})
 if fault=='unknown-sibling' or fault=='unknown-sibling-exclusive' then
  local contract={knownInputs=false,items={}}
  toolkit.ActionQueueSettlement.remember(scope,{Type='UnknownSibling',toolkitQueueOperation={}},contract)
  -- Accepted contracts are snapshots; later mutation cannot erase uncertainty.
  contract.knownInputs=true;contract.items[99]=true
 elseif fault=='known-nil-sibling' then
  -- Native item contracts omit knownInputs when their exact resources are known.
  toolkit.ActionQueueSettlement.remember(scope,{Type='KnownSibling',toolkitQueueOperation={}},{items={[99]=true}})
 end
 for ordinal=1,3 do
  pickup.item=pickupGroups[1].items[1];pickup.transactionId=kind=='mp' and -120+ordinal or 0
  if fault=='pickup-owner' and ordinal==2 then pickup.toolkitQueueOperation={} end
  if kind=='sp' and ordinal==1 then pickupGroups[1].items={items[1]} end
  assert(lifecycle.begin(pickup,'perform'))
  assert(toolkit.ActionQueueSettlement.beginReturn(pickup,{})) -- Internal pickup handle is not cleanup.
  if kind=='sp' and ordinal==1 then pickupGroups[1].items={items[1],items[2]};callback(pickup) end
  assert(lifecycle.deferCompletion(queue,pickup))
  for _,item in ipairs(pickupGroups[1].items) do item.container=inventory end
  table.remove(pickupGroups,1)
  lifecycle.finish(pickup,'perform',true)
  if kind=='sp' then lifecycle.begin(pickup,'complete');lifecycle.finish(pickup,'complete',true) end
 end
 present=false;assert(lifecycle.flush(queue)=='completed');present=true
 queue.current=action;queue.queue={action}
 callback(action)
 local obligation={}
 for ordinal=1,3 do
  action.item=action.queueList[1].items[1]
  action.transactionId=kind=='mp' and -127 or 0
  if fault=='native' and ordinal==2 then action.action={} end
  assert(lifecycle.begin(action,'perform'))
  assert(toolkit.ActionQueueSettlement.beginReturn(action,obligation))
  if ordinal==1 then returnMerged=true;callback(action) end -- SP adds members before effects.
  assert(lifecycle.deferCompletion(queue,action))
  local members={}
  for _,item in ipairs(action.queueList[1].items) do members[#members+1]={id=item:getID(),fullType=item:getFullType(),state='completed'} end
  attempts[#attempts+1]={ordinal=ordinal,phase='perform',state='completed',transaction=action.transactionId,
   authority=kind=='mp' and 'completed' or 'native',items=members}
  toolkit.ActionQueueSettlement.finishReturn(obligation,true)
  lifecycle.finish(action,'perform',true)
  if kind=='sp' then lifecycle.begin(action,'complete');lifecycle.finish(action,'complete',true) end
  table.remove(action.queueList,1)
  callback(action) -- Includes the final empty native queueList; observers cannot throw.
  assert(lifecycle.flush(queue)=='waiting')
 end
 assert(action.action==native)
 present=false;assert(lifecycle.flush(queue)=='completed')
 local counts=observer.settled();local group=observer.group()
 assert(counts.perform==3 and counts.complete==(kind=='sp' and 3 or 0) and counts.flush==1 and counts.cleanupConfirmed==4)
 assert(group.nativeGroups==3 and group.executorCount==1 and #group.attempts==3)
 assert(group.groupSizes[1]==1 and group.groupSizes[2]==1 and group.groupSizes[3]==2)
 assert(group.pickupOperations==1 and #group.pickupItems==4 and #group.ownershipAtBegin==4 and #group.ownershipCompleted==4)
end
for _,kind in ipairs({'sp','mp'}) do
 run(kind)
 run(kind,'known-nil-sibling')
 run(kind,'unknown-sibling')
 assert(not pcall(run,kind,'unknown-sibling-exclusive'),'unknown sibling was allowed an exclusive native receipt')
 assert(not pcall(run,kind,'native'),'multi-group observer accepted changed native executor')
 for _,fault in ipairs({'owner','partial','duplicate','unbound','authority','attempt','transaction','shared','pickup-owner'}) do
  assert(not pcall(run,kind,fault),'multi-group observer accepted foreign/incomplete ownership: '..fault)
 end
end
'''
        target = self.root / 'multigroup-completion-check.lua'
        target.write_text(script)
        result = subprocess.run([lua, str(target), str(ROOT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_tidy_observer_rejects_wrong_identity_ownership_early_flush_and_legacy_scope(self):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        script = r'''
local root=arg[1]
local function run(kind,mode,fault,equipment)
 getActivatedMods=function()return {contains=function()return true end}end
 local enabled=mode=='toolkit'
 local item={getID=function()return 7 end,getFullType=function()return 'Base.Nails'end}
 local inventory,source={},{}
 local present=true
 local player={getCharacterActions=function()return {contains=function()return present end}end}
 local action={character=player,item=item,srcContainer=inventory,destContainer=source,action={},toolkitQueueOperation={}}
 local queue={character=player,current=action,queue={action},onCompleted=function(self,a)
  assert(self.current==a);self.current=nil;self.queue={}
 end}
 ISTimedActionQueue={queues={[player]=queue}}
 ISQueueActionsAction={start=function()end}
 isClient=function()return kind=='mp'end
 Events={OnGameStart={Add=function()end}}
 require=function(name)if name=='QueueEquipmentClothing'or name=='QueueEquipmentHotbar'then return dofile(root..'/tests/native_queue/equipment/shared/'..name..'.lua')end end
 PZSurvivorToolkit={Settings={actionQueue=function()return enabled end}}
 local lifecycle=dofile(root..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua')
 local toolkit=PZSurvivorToolkit
 ISInventoryTransferAction={}
 local operations=dofile(root..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua')
 operations.registerProducer('fixture.tidy',function(a)return a==action end,function()return false end,fault~='legacy')
 toolkit.ActionQueueDefinitions={inspect=function()if enabled then return {},equipment and 'compat.tidy-equipment' or 'compat.tidy-transfers'end end}
 toolkit.ActionQueuePolicy={evaluateCancel=function()return {allowed=false}end}
 -- This timing fixture has no explicit UI intent; added provenance observers must stay unused.
 toolkit.ActionQueueSettlement={captureEffect=function()error('unexpected explicit effect capture')end,
  confirmEffect=function()error('unexpected explicit effect confirmation')end}
 toolkit.ActionQueueAcknowledgements={capture=function()end}
 toolkit.ActionQueueTidyIntent={status=function()return true end,begin=function()end,finish=function()end}
 toolkit.ActionQueueCompat={isInstalled=function()return false end,verifySources=function()return false end}
 ISInventoryPaneContextMenu={OnTwoHandsEquip=function()end,OnPrimaryWeapon=function()end,equipWeapon=function()end}
 ISInventoryPane={getActualItems=function()end}
 getFilenameOfClosure=function()return 'fixture' end
 action.Type,action.primary,action.twoHands='ISEquipWeaponAction',true,false
 local headwear=equipment=='headwear-wear'
 local clothing=equipment=='clothing-remove' or equipment=='clothing-wear' or headwear
 local hotbar=equipment=='hotbar'
 if hotbar then
  action.Type='ISUnequipAction';action.fromHotbar=true
  item.getFullType=function()return 'Base.Shotgun'end;item.getContainer=function()return inventory end
  item.getAttachedSlot=function()return 1 end;item.getAttachedSlotType=function()return 'Back'end
  item.getAttachedToModel=function()return 'Rifle On Back with Bag'end
  player.getAttachedItems=function()return {getItem=function()return fault~='attach-connect'and item or nil end}end
  player.getPrimaryHandItem=function()return kind=='mp'and nil or item end
  player.getSecondaryHandItem=function()return kind=='mp'and nil or item end
 end
 if clothing then
  action.Type=equipment=='clothing-remove'and 'ISUnequipAction'or 'ISWearClothing'
  item.getFullType=function()return headwear and 'Base.Hat_Beany'or 'Base.Socks_Ankle'end
  item.getBodyLocation=function()return headwear and 'base:hat'or 'base:socks'end;item.getContainer=function()return inventory end
 end
 if fault=='early-flush' then lifecycle.flush=function()return 'completed',action end end
 local observer=dofile(root..'/tests/native_queue/equipment/shared/QueueEquipmentCompletion.lua').observe(toolkit,{kind=kind,mode=mode})
 observer.watch({id=hotbar and 'tidy-hotbar'or headwear and 'tidy-headwear-hat-restore'or clothing and (equipment=='clothing-remove'and 'tidy-clothing-remove'or 'tidy-clothing')or nil,
  root=inventory,source=source,baseline={[7]=item},hammer={getID=item.getID,getFullType=item.getFullType},
  clothingItem=clothing and item or nil,clothingLocation=headwear and 'base:hat'or 'base:socks',
  clothingRestoreType=headwear and 'ISWearClothing'or nil,pickup=hotbar and item or nil,hotbarDetached=true,
  hotbarIndex=1,hotbarType='Back',hotbarLocation='Rifle On Back with Bag',hotbarRestoreAction=hotbar and action or nil,hotbarTwoHands=hotbar})
 if equipment and not clothing and not hotbar then action.item={getID=item.getID,getFullType=item.getFullType} end
 if not enabled then
  lifecycle.begin(action,'perform');lifecycle.finish(action,'perform',true)
  local counts=observer.settled();assert(counts.perform==0 and counts.complete==0 and counts.flush==0);return
 end
 assert(lifecycle.begin(action,'perform'))
 if fault=='duplicate-perform' then lifecycle.begin(action,'perform');return end
 toolkit.ActionQueueOperations.perform(action,function(parent)
  assert(parent==action and lifecycle.current(player)==action)
  assert(lifecycle.deferCompletion(queue,action))
 end)
 if fault=='id' then action.item={getID=function()return 8 end,getFullType=item.getFullType}
 elseif fault=='endpoint' then action.destContainer={}
 elseif fault=='token' then action.toolkitQueueOperation={}
 elseif fault=='handle' then action.action={}
 elseif fault=='parent' then queue.current=nil end
 lifecycle.finish(action,'perform',fault~='failed')
 if kind=='sp' or fault=='host-complete' then
  lifecycle.begin(action,'complete');lifecycle.finish(action,'complete',true)
 end
 if fault=='unflushed' then observer.settled();return end
 if fault~='early-flush' then assert(lifecycle.flush(queue)=='waiting');present=false end
 assert(lifecycle.flush(queue)=='completed')
 assert(lifecycle.flush(queue)==nil)
 local counts=hotbar and observer.hotbar()or clothing and observer.clothing()or equipment and observer.restores() or observer.settled()
 assert(counts.perform==1 and counts.complete==(kind=='sp' and 1 or 0) and counts.flush==1 and counts.legacy==0)
end
for _,kind in ipairs({'sp','mp'})do
 for _,mode in ipairs({'native','toolkit'})do
  run(kind,mode);run(kind,mode,nil,true);run(kind,mode,nil,'clothing-wear');run(kind,mode,nil,'clothing-remove');run(kind,mode,nil,'headwear-wear');run(kind,mode,nil,'hotbar')
 end
 for _,fault in ipairs({'id','endpoint','token','handle','parent','failed','duplicate-perform','legacy','early-flush','unflushed'})do
  local ok=pcall(run,kind,'toolkit',fault);assert(not ok,'observer accepted '..kind..' '..fault)
 end
end
assert(not pcall(run,'mp','toolkit','host-complete'))
assert(not pcall(run,'mp','toolkit','host-complete','clothing-remove'))
assert(not pcall(run,'mp','toolkit','host-complete','headwear-wear'))
assert(not pcall(run,'mp','toolkit','host-complete','hotbar'))
assert(not pcall(run,'sp','toolkit','attach-connect','hotbar'))
'''
        target = self.root / 'completion-check.lua'
        target.write_text(script)
        result = subprocess.run([lua, str(target), str(ROOT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
