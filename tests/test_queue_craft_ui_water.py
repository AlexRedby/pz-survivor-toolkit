"""Falsify first native water-pot ingredient receipts, including queue-off."""
import copy
import unittest
import test_queue_craft_ui as base
from queue_checks.adapters import craft_ui, craft_ui_water

class WaterCookTests(unittest.TestCase):
    def evidence(self,case='cook-water-stew',level=0,enabled=True):
        prep=dict(case=case,bags=[1,2],book=3,base=dict(id=4,kind='Base.Pot',fluidCapacity=3,waterAmount=3),
                  ingredient=dict(id=5,kind='Base.Tomato',hunger=-.12),spice=dict(id=6,kind='Base.Pepper',hunger=-.1),
                  baselineDishIds=[],cookingLevel=level)
        hunger=-.12+.12*(1-.03*level);consumed=hunger>=-.0200001
        dish=dict(id=7,kind=craft_ui_water.RESULTS[case],sourceCount=0,rootCount=1,totalCount=1,extras=['Base.Tomato'],spices=[])
        receipt=dict(case=case,bags=[1,2],base=dict(id=4,totalCount=0),ingredient=dict(id=5,kind='Base.Tomato',
                     hunger=0 if consumed else hunger,sourceCount=0 if consumed else 1,rootCount=0,totalCount=0 if consumed else 1),
                     spice=dict(id=6,kind='Base.Pepper',hunger=-.1,sourceCount=1,totalCount=1),dishes=[dish],outputIds=[7],outputs=1,bookId=3,tailRead=True)
        row=dict(event='case',id=case,status='passed',reason=None,requested=1,actions=1,actionInputIds=[5],progressIds=[1],
                 nativeDurations=[100-level*2.5],cookingLevel=level,sourceMethodsUnchanged=True,callbackClass='PJCK_EvoPanel',
                 sourceDeferred=False,sourceVerified=True,tokensGrouped=enabled,tailIndependent=True,tailProgress=True,
                 returnsBeforeRead=True,selectedDishId=7,dispatchMethod='PJCK_ItemSlot.onMouseDoubleClick',recipeUse=12,
                 fluidCapacity=3,waterAmount=3,inputObservations=[dict(event='queued')])
        if case in craft_ui_water.WORLD_CASES:
            source=dict(x=10,y=20,z=0,objectIndex=1,containerIndex=0,sprite='appliances_cooking_01_0',containerType='stove',ownerToken=case+':client1:1')
            prep['base']['source']=source
            receipt['base'].update(rootCount=0,sourceCount=0,sourceItemCount=0,source=source)
            row.update(basePickupNative=True,originalBaseSource=source,inputObservations=[
                dict(event='base-pickup-queued',sourceLive=True,sourceBaseCount=1,rootBaseCount=0,source=source),
                dict(event='base-pickup-idle',sourceLive=True,sourceBaseCount=0,rootBaseCount=1,source=source)])
        if case in craft_ui_water.BEAN_CASES:
            source=prep['base'].get('source');prep['ingredient'].update(kind='Base.DriedWhiteBeans',hunger=-.6,recipeUse=10)
            if source:prep['ingredient']['source']=source
            receipt['ingredient'].update(kind='Base.DriedWhiteBeans',hunger=-.6+.1*(1-.03*level),totalCount=1,sourceCount=1)
            if source:receipt['ingredient']['source']=source
            if source:receipt['base']['sourceItemCount']=1
            receipt['dishes'][0]['extras']=['Base.DriedWhiteBeans']
            row.update(recipeUse=10,originalIngredientSource=source,ingredientTransfers=[
                dict(id=5,pickup=True,returned=False,duration=100,transactionDuration=50,progress=True),
                dict(id=5,pickup=False,returned=True,duration=83,transactionDuration=50,progress=True)])
        if case==craft_ui_water.FLOOR_CASE:
            world=dict(x=10,y=20,z=0,id=4,worldObjectIndex=0,ownerToken=case+':client1:1')
            prep['base']['world']=world;prep.update(inputDispatch='plus-cook',baselineWorldDishIds=[])
            receipt['base'].update(rootCount=0,worldCount=0,world=world)
            receipt['dishes'][0]['worldCount']=0
            row.update(dispatchMethod='PJCK_ItemSlot.onAddButton+PJCK_BaseItem.onCook',
                plusButtonNative=True,cookButtonNative=True,preCookRequests=1,basePickupNative=True,originalBaseWorld=world)
            row.update(plusCook=dict(selectedCount=1, displayItemId=5, recipeUse=10, baseItemHandling='keep_inventory',
                cookButtonVisible=True,cookButtonEnabled=True,plusTimestampMs=3100,cookTimestampMs=3200),
                baseTransferTrace=dict(selectionTimestampMs=1000,rootArrivalTimestampMs=3000,slotTimestampMs=3050,
                    progress=True,transactionDuration=100,nativeDuration=100,actions=[dict(id=4,kind='Base.Pot',sourceIsRoot=False,
                    destinationIsRoot=True,started=True,progress=True,sourceMethodsUnchanged=True,transactionDuration=100,duration=100)]),
                floorObservations=[dict(event='base-pickup-queued',worldCount=1,worldObjectIndex=0,worldObjectIsOriginal=True,
                    selectedIsWorldReference=True,worldItem=dict(id=4,kind='Base.Pot',hasWorldItem=True,worldItemMatches=True,worldPresent=True)),
                    dict(event='base-pickup-idle',worldCount=0,selectedIsRootReference=True,rootItem=dict(id=4,kind='Base.Pot',root=True))])
        row['nativeDurations']=[int(v)if float(v).is_integer()else v for v in row['nativeDurations']]
        row.update({k:copy.deepcopy(v)for k,v in receipt.items()if k!='case'})
        return row,prep,receipt
    def test_native_soup_and_stew_with_full_and_partial_native_portions(self):
        for case in craft_ui.WATER_CASES:
            for level in (0,5,6):
                for mode in ('native','toolkit'):
                    row,prep,receipt=self.evidence(case,level,mode=='toolkit')
                    self.assertEqual(craft_ui_water.verify(dict(mode=mode),row,prep,receipt),[])
    def test_receipt_mutations_never_pass_either_queue_mode(self):
        for mode in ('native','toolkit'):
            for change in ('empty-water','fake-action','double-use','wrong-dish','retained-base','lost-spice','changed-spice','missing-reader','wrong-owner','wrong-id','no-diagnostics','no-slot','free-ingredient'):
                row,prep,receipt=self.evidence(enabled=mode=='toolkit')
                if change=='empty-water':prep['base']['waterAmount']=0
                elif change=='fake-action':row['actions']=0
                elif change=='double-use':receipt['dishes'][0]['extras'].append('Base.Tomato')
                elif change=='wrong-dish':receipt['dishes'][0]['kind']='Base.Salad'
                elif change=='retained-base':receipt['base']['totalCount']=1
                elif change=='lost-spice':receipt['spice']['totalCount']=0
                elif change=='changed-spice':receipt['spice']['hunger']=-.01
                elif change=='missing-reader':receipt['tailRead']=False
                elif change=='wrong-owner':receipt['dishes'][0].update(sourceCount=1,rootCount=0)
                elif change=='wrong-id':receipt['outputIds']=[4]
                elif change=='no-diagnostics':row['inputObservations']=[]
                elif change=='no-slot':row['dispatchMethod']='replacement'
                else:receipt['ingredient'].update(totalCount=1,rootCount=1,hunger=-.12)
                with self.subTest(mode=mode,change=change):self.assertTrue(craft_ui_water.verify(dict(mode=mode),row,prep,receipt))
    def test_shared_runner_receives_actual_authority_and_retains_native_failure(self):
        for mode in ('native','toolkit'):
            for kind in ('sp','mp'):
                h=base.CraftUIAdapterTests();h.setUp();self.addCleanup(h.doCleanups)
                h.selection.update(cases=['cook-water-stew'],kind=kind,mode=mode)
                row,prep,receipt=self.evidence(enabled=mode=='toolkit')
                context=dict(suite='craft-ui',kind=kind,mode=mode,actor='client1')
                rows=[dict(event='setup',cases=h.selection['cases'],expected=1,queueEnabled=mode=='toolkit',nativeDurations=True),row,
                      dict(event='complete',cases=h.selection['cases'],expected=1,performed=1,failed=0,skipped=0)]
                rows=[dict(r,**context)for r in rows];raw=[('PREPARED',prep),('VERIFIED',receipt)]
                self.assertEqual(h.verify((rows,raw))['issues'],[])
                receipt['ingredient']['totalCount']=1
                self.assertTrue(h.verify((rows,raw))['issues'])
    def test_lua_json_whole_durations_are_numeric_and_bools_are_rejected(self):
        for duration in (100,100.0):
            row,prep,receipt=self.evidence();row['nativeDurations']=[duration]
            self.assertEqual(craft_ui_water.verify(dict(mode='toolkit'),row,prep,receipt),[])
        row,prep,receipt=self.evidence();row['nativeDurations']=[True]
        self.assertTrue(craft_ui_water.verify(dict(mode='toolkit'),row,prep,receipt))
    def test_world_source_and_actual_pickup_boundaries_cannot_be_substituted(self):
        for mutation in ('owner','source-kind','initial-count','after-count','retained-source','missing-native'):
            row,prep,receipt=self.evidence('cook-water-soup-world')
            if mutation=='owner':prep['base']['source']['ownerToken']='foreign'
            elif mutation=='source-kind':prep['base']['source']['containerType']='microwave'
            elif mutation=='initial-count':row['inputObservations'][0]['sourceBaseCount']=0
            elif mutation=='after-count':row['inputObservations'][1]['rootBaseCount']=0
            elif mutation=='retained-source':receipt['base']['sourceItemCount']=1
            else:row['basePickupNative']=False
            with self.subTest(mutation=mutation):self.assertTrue(craft_ui_water.verify(dict(mode='toolkit'),row,prep,receipt))
    def test_floor_plus_cook_requires_original_world_and_paid_consumption(self):
        for mode in ('native','toolkit'):
            for change in ('world-id','world-owner','world-remains','no-plus','no-cook','no-pickup','wrong-source','dish-floor','duplicate-world','no-paid-pickup','wrong-reference','cook-hidden','no-trace'):
                row,prep,receipt=self.evidence(craft_ui_water.FLOOR_CASE,enabled=mode=='toolkit')
                if change=='world-id':prep['base']['world']['id']=999
                elif change=='world-owner':prep['base']['world']['ownerToken']='foreign'
                elif change=='world-remains':receipt['base']['worldCount']=1
                elif change=='no-plus':row['plusButtonNative']=False
                elif change=='no-cook':row['cookButtonNative']=False
                elif change=='no-pickup':row['basePickupNative']=False
                elif change=='wrong-source':receipt['ingredient']['rootCount']=1
                elif change=='dish-floor':receipt['dishes'][0].update(rootCount=0,worldCount=1)
                elif change=='duplicate-world':receipt['dishes'][0]['worldCount']=1
                elif change=='no-paid-pickup':row['baseTransferTrace']['transactionDuration']=0
                elif change=='wrong-reference':row['floorObservations'][1]['selectedIsRootReference']=False
                elif change=='cook-hidden':row['plusCook']['cookButtonVisible']=False
                else:row.pop('baseTransferTrace')
                with self.subTest(mode=mode,change=change):self.assertTrue(craft_ui_water.verify(dict(mode=mode),row,prep,receipt))
    def test_floor_sp_uses_native_durations_without_network_transactions(self):
        for mode in ('native','toolkit'):
            row,prep,receipt=self.evidence(craft_ui_water.FLOOR_CASE,enabled=mode=='toolkit')
            row['baseTransferTrace'].pop('transactionDuration')
            row['baseTransferTrace']['actions'][0].pop('transactionDuration')
            for value in row['ingredientTransfers']:value.pop('transactionDuration')
            self.assertEqual(craft_ui_water.verify(dict(kind='sp',mode=mode),row,prep,receipt),[])
            self.assertTrue(craft_ui_water.verify(dict(kind='mp',mode=mode),row,prep,receipt))
            row['baseTransferTrace']['nativeDuration']=0
            self.assertTrue(craft_ui_water.verify(dict(kind='sp',mode=mode),row,prep,receipt))
    def test_source_manifest_includes_water_verifier(self):
        self.assertIn('craft_ui_water.py',[p.name for p in craft_ui.sources(craft_ui.Path('.'),{})])

if __name__=='__main__':unittest.main()
