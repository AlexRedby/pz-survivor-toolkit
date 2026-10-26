"""Exact first-ingredient water-pot effects; no native deviation waiver."""
import math
from . import craft

RESULTS = {'cook-water-soup': 'Base.PotOfSoupRecipe', 'cook-water-stew': 'Base.PotOfStew', 'cook-water-soup-world': 'Base.PotOfSoupRecipe', 'cook-water-stew-beans': 'Base.PotOfStew', 'cook-water-stew-floor-plus': 'Base.PotOfStew'}
KEYS = {'bags','base','ingredient','spice','dishes','outputIds','outputs','bookId','tailRead'}
def number(value):return type(value) in (int,float) and math.isfinite(value)
def food(value,kind,hunger):
    return (type(value)is dict and set(value)=={'id','kind','hunger'} and type(value.get('id'))is int
            and value.get('kind')==kind and number(value.get('hunger')) and abs(value['hunger']-hunger)<.00001)
FLOOR_CASE='cook-water-stew-floor-plus'
BEAN_CASES={'cook-water-stew-beans',FLOOR_CASE}
WORLD_CASES={'cook-water-soup-world','cook-water-stew-beans'}
def source(value):
    return (type(value)is dict and set(value)=={'x','y','z','objectIndex','containerIndex','sprite','containerType','ownerToken'}
            and all(type(value.get(k))is int for k in ('x','y','z','objectIndex','containerIndex'))
            and value['objectIndex']>=0 and value['containerIndex']>=0 and value['sprite']=='appliances_cooking_01_0'
            and value['containerType']=='stove' and type(value['ownerToken'])is str
            and any(value['ownerToken'].startswith(case+':')for case in WORLD_CASES))
def floor(value):
    return (type(value)is dict and set(value)=={'x','y','z','id','worldObjectIndex','ownerToken'}
            and all(type(value.get(k))is int for k in ('x','y','z','id','worldObjectIndex'))
            and value['worldObjectIndex']>=0 and type(value['ownerToken'])is str
            and value['ownerToken'].startswith(FLOOR_CASE+':'))
def prepared(prep):
    world=prep.get('case')in WORLD_CASES
    beans=prep.get('case')in BEAN_CASES
    ground=prep.get('case')==FLOOR_CASE
    base=prep.get('base',{})
    if (set(prep)!=({'case','bags','book','base','ingredient','spice','baselineDishIds','cookingLevel'}|({'inputDispatch','baselineWorldDishIds'}if ground else set()))
            or prep.get('case')not in RESULTS or type(prep.get('cookingLevel'))is not int or not 0<=prep['cookingLevel']<=10
            or not craft._ids(prep.get('bags'),2) or not craft._ids(prep.get('baselineDishIds')) or type(prep.get('book'))is not int
            or type(base)is not dict or set(base)!=({'id','kind','fluidCapacity','waterAmount'}|({'source'}if world else {'world'}if ground else set())) or type(base.get('id'))is not int
            or ground and (not floor(base.get('world'))or base['world']['id']!=base.get('id'))
            or world and not source(base.get('source')) or base.get('kind')!='Base.Pot' or not number(base.get('fluidCapacity')) or base['fluidCapacity']<=0
            or not number(base.get('waterAmount')) or abs(base['waterAmount']-base['fluidCapacity'])>.00001
            or not food(prep.get('spice'),'Base.Pepper',-.1)):
        return False
    if ground and (prep.get('inputDispatch')!='plus-cook'or not craft._ids(prep.get('baselineWorldDishIds'))):return False
    ingredient=prep.get('ingredient')
    if beans:
        if (type(ingredient)is not dict or set(ingredient)!=({'id','kind','hunger','recipeUse'}|({'source'}if world else set()))
                or not food({k:ingredient.get(k)for k in ('id','kind','hunger')},'Base.DriedWhiteBeans',-.6)
                or ingredient.get('recipeUse')!=10 or world and not craft._same(ingredient.get('source'),base['source'])):return False
    elif not food(ingredient,'Base.Tomato',-.12):return False
    return craft._ids(prep['bags']+[prep['book'],base['id'],prep['ingredient']['id'],prep['spice']['id']]+prep['baselineDishIds']+prep.get('baselineWorldDishIds',[]))

def floor_flow(row, prep, selection):
    trace, plus, observations = (row.get(key) for key in ('baseTransferTrace', 'plusCook', 'floorObservations'))
    if not all(isinstance(value, dict) for value in (trace, plus)) or not isinstance(observations, list):
        return False
    if not craft._matches(plus, dict(selectedCount=1, displayItemId=prep['ingredient']['id'], recipeUse=10,
                                    baseItemHandling='keep_inventory', cookButtonVisible=True, cookButtonEnabled=True)):
        return False
    clocks = (trace.get('selectionTimestampMs'), trace.get('rootArrivalTimestampMs'),
              trace.get('slotTimestampMs'), plus.get('plusTimestampMs'), plus.get('cookTimestampMs'))
    if not all(number(value) for value in clocks) or list(clocks) != sorted(clocks) or trace.get('progress') is not True:
        return False
    trace_cost = 'transactionDuration' if selection.get('kind', 'mp') == 'mp' else 'nativeDuration'
    action_cost = 'transactionDuration' if selection.get('kind', 'mp') == 'mp' else 'duration'
    if not number(trace.get(trace_cost)) or trace[trace_cost] <= 1:
        return False
    actions = trace.get('actions')
    if not isinstance(actions, list) or any(not isinstance(action, dict) for action in actions):
        return False
    pickups = [action for action in actions if action.get('id') == prep['base']['id'] and action.get('destinationIsRoot') is True]
    if len(pickups) != 1 or not craft._matches(pickups[0], dict(kind='Base.Pot', sourceIsRoot=False,
            destinationIsRoot=True, started=True, progress=True, sourceMethodsUnchanged=True)):
        return False
    if not number(pickups[0].get(action_cost)) or pickups[0][action_cost] <= 1:
        return False
    before = [value for value in observations if isinstance(value, dict) and value.get('event') == 'base-pickup-queued']
    after = [value for value in observations if isinstance(value, dict) and value.get('event') == 'base-pickup-idle']
    if not before or len(after) != 1:
        return False
    if not any(craft._matches(value, dict(worldCount=1, worldObjectIndex=prep['base']['world']['worldObjectIndex'],
            worldObjectIsOriginal=True, selectedIsWorldReference=True))
            and craft._matches(value.get('worldItem'), dict(id=prep['base']['id'], kind='Base.Pot',
                hasWorldItem=True, worldItemMatches=True, worldPresent=True)) for value in before):
        return False
    if not craft._matches(after[0], dict(worldCount=0, selectedIsRootReference=True)) or not craft._matches(
            after[0].get('rootItem'), dict(id=prep['base']['id'], kind='Base.Pot', root=True)):
        return False
    transfers = row.get('ingredientTransfers')
    return (isinstance(transfers, list) and len(transfers) == 2
            and craft._matches(transfers[0], dict(id=prep['ingredient']['id'], pickup=True, returned=False, progress=True))
            and craft._matches(transfers[1], dict(id=prep['ingredient']['id'], pickup=False, returned=True, progress=True))
            and all(number(value.get(action_cost)) and value[action_cost] > 1 for value in transfers))

def verify(selection,row,prep,receipt):
    if not prepared(prep):return ['Craft UI water preparation or native fluid differs']
    issues=[];enabled=selection['mode']=='toolkit';level=prep['cookingLevel'];output=RESULTS[prep['case']]
    beans=prep['case']in BEAN_CASES;recipe_use=10 if beans else 12;source_items=1 if beans else 0
    def fail(message):issues.append('Craft UI water '+message+': '+prep['case'])
    if (not craft._matches(row,dict(status='passed',reason=None,requested=1,actions=1,actionInputIds=[prep['ingredient']['id']],
            progressIds=[1],cookingLevel=level,sourceMethodsUnchanged=True,
            callbackClass='PJCK_EvoPanel',sourceVerified=True,tokensGrouped=enabled,tailIndependent=True,
            tailProgress=True,returnsBeforeRead=True,dispatchMethod=('PJCK_ItemSlot.onAddButton+PJCK_BaseItem.onCook'if prep['case']==FLOOR_CASE else 'PJCK_ItemSlot.onMouseDoubleClick'),recipeUse=recipe_use,
            fluidCapacity=prep['base']['fluidCapacity'],waterAmount=prep['base']['waterAmount']))):
        fail('native first slot, action, duration or reader differs')
    durations=row.get('nativeDurations')
    if type(durations)is not list or len(durations)!=1 or not number(durations[0])or durations[0]!=100-level*2.5:
        fail('native duration differs')
    if (type(receipt)is not dict or set(receipt)!=(KEYS|{'case'}) or receipt.get('case')!=prep['case']
            or not craft._matches(row,{k:receipt.get(k)for k in KEYS})):fail('authority differs from client')
    expected_base=dict(id=prep['base']['id'],totalCount=0)
    if prep['case']in WORLD_CASES:
        expected_base.update(rootCount=0,sourceCount=0,sourceItemCount=source_items,source=prep['base']['source'])
    if prep['case']==FLOOR_CASE:expected_base.update(rootCount=0,worldCount=0,world=prep['base']['world'])
    if not craft._matches(receipt,dict(bags=prep['bags'],bookId=prep['book'],tailRead=True,
            base=expected_base,spice=dict(id=prep['spice']['id'],kind='Base.Pepper',totalCount=1,
            sourceCount=1,hunger=prep['spice']['hunger']))):fail('base replacement or untouched spice differs')
    hunger=prep['ingredient']['hunger']+recipe_use/100*(1-.03*level);consumed=hunger>=-.0200001
    expected=dict(id=prep['ingredient']['id'],kind=prep['ingredient']['kind'],hunger=0 if consumed else hunger,
                  totalCount=0 if consumed else 1,sourceCount=0 if consumed else 1,rootCount=0)
    if beans and prep['case']in WORLD_CASES:expected['source']=prep['ingredient']['source']
    ingredient=receipt.get('ingredient')
    if (type(ingredient)is not dict or set(ingredient)!=set(expected)
            or any(type(ingredient.get(k))is not int or ingredient[k]!=expected[k]for k in ('id','totalCount','sourceCount','rootCount'))
            or ingredient.get('kind')!=expected['kind'] or not number(ingredient.get('hunger'))
            or abs(ingredient['hunger']-expected['hunger'])>.00001
            or 'source'in expected and not craft._same(ingredient.get('source'),expected['source'])):fail('one paid ingredient use or leftover return differs')
    dishes=receipt.get('dishes');output_ids=receipt.get('outputIds')
    owned=prep['bags']+[prep['book'],prep['base']['id'],prep['ingredient']['id'],prep['spice']['id']]+prep['baselineDishIds']+prep.get('baselineWorldDishIds',[])
    if (type(receipt.get('outputs'))is not int or receipt['outputs']!=1 or not craft._ids(output_ids,1)
            or not craft._ids(owned+(output_ids if type(output_ids)is list else []))
            or type(dishes)is not list or len(dishes)!=1 or type(dishes[0])is not dict
            or not craft._matches(dishes[0],dict(id=output_ids[0],kind=output,totalCount=1,rootCount=1,sourceCount=0,
                extras=[prep['ingredient']['kind']],spices=[])) or row.get('selectedDishId')!=output_ids[0]):
        fail('single exact transformed dish or selected replica differs')
    if prep['case']in WORLD_CASES:
        base=receipt.get('base',{})
        if (not craft._matches(row,dict(basePickupNative=True,originalBaseSource=prep['base']['source']))
                or not craft._matches(base,dict(rootCount=0,sourceCount=0,sourceItemCount=source_items,source=prep['base']['source']))):
            fail('original stove source, paid pickup or conservation differs')
    observations=row.get('inputObservations')
    if not isinstance(observations,list)or not observations or len(observations)>24:
        fail('input identity diagnostics missing')
    elif prep['case']in WORLD_CASES:
        before=[v for v in observations if isinstance(v,dict)and v.get('event')=='base-pickup-queued']
        after=[v for v in observations if isinstance(v,dict)and v.get('event')=='base-pickup-idle']
        if (len(before)!=1 or len(after)!=1
                or not craft._matches(before[0],dict(sourceLive=True,sourceBaseCount=1,rootBaseCount=0,source=prep['base']['source']))
                or not craft._matches(after[0],dict(sourceLive=True,sourceBaseCount=0,rootBaseCount=1,source=prep['base']['source']))):
            fail('actual original source-to-root boundary missing')
    if beans and prep['case']in WORLD_CASES:
        transfers=row.get('ingredientTransfers')
        if (not craft._same(row.get('originalIngredientSource'),prep['ingredient']['source'])
                or not isinstance(transfers,list)or len(transfers)!=2
                or not craft._matches(transfers[0],dict(id=prep['ingredient']['id'],pickup=True,returned=False,progress=True))
                or not craft._matches(transfers[1],dict(id=prep['ingredient']['id'],pickup=False,returned=True,progress=True))):
            fail('paid original bean pickup and exact leftover return differ')
    if prep['case']==FLOOR_CASE:
        if (not craft._matches(row,dict(basePickupNative=True,originalBaseWorld=prep['base']['world'],
                plusButtonNative=True,cookButtonNative=True,preCookRequests=1))
                or not isinstance(dishes,list)or len(dishes)!=1 or type(dishes[0].get('worldCount'))is not int
                or dishes[0]['worldCount']!=0 or not floor_flow(row,prep,selection)):
            fail('real floor pickup or plus/Cook path differs')
    return issues
