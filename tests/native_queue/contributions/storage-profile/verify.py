"""Require bounded native captures; measurements never imply a performance pass."""
import itertools
import json
import math
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent
CALLBACKS=('ownDiscoveryBody','lootDiscoveryBody','ownUpdateItemCount','lootUpdateItemCount','bcOnButtonsAdded')


def specifications():
    manifest=json.loads((HERE/'manifest.json').read_text())
    rows=[(density,mode,state,'ordinary') for density,mode,state in
          itertools.product(manifest['densities'],manifest['modes'],manifest['states'])]
    return rows+[('dense','clean','both-hidden',name) for name in manifest['feature_controls']]


def number(value,minimum=0,integer=False):
    if type(value) not in (int,float) or not math.isfinite(value) or value<minimum or integer and type(value) is not int:
        raise ValueError('Invalid finite native profile measurement')
    return value


def presentation(value):
    if not isinstance(value,dict):raise ValueError('Missing actual presentation state')
    for key in ('pending','pendingPane','rowsPending','countPending','tooltipsPending','builtWeightValues',
                'pageRefreshIdentityUnchanged','paneRefreshIdentityUnchanged'):
        if type(value.get(key)) is not bool:raise ValueError('Missing actual presentation flag')
    if not value['pageRefreshIdentityUnchanged'] or not value['paneRefreshIdentityUnchanged']:
        raise ValueError('Profiler changed page/pane refresh method identity')
    if value['pending'] != any(value[key] for key in ('rowsPending','countPending','tooltipsPending')):
        raise ValueError('Pending flags disagree')
    if value['pending'] and not value['pendingPane']:raise ValueError('Pending rows belong to a different pane')
    count=number(value.get('nativeBuildCount'),integer=True)
    if count>10000:raise ValueError('Native builder counter outside its reviewed range')
    if value.get('builtWeightField') not in ('nil','boolean'):raise ValueError('Unknown built-weight state')
    if number(value.get('fastWeightGroups'),integer=True)>number(value.get('groups'),integer=True):
        raise ValueError('Impossible stack count')
    selected=value.get('selection',{})
    number(selected.get('count'),integer=True);number(selected.get('anchorIndex'),integer=True)
    if any(not isinstance(selected.get(key),str) for key in ('signature','anchor')):
        raise ValueError('Missing native selection/anchor identity')
    return selected


def physical(value):
    if not isinstance(value,dict) or value.get('exact') is not True or number(value.get('raw'),1,True)!=number(value.get('rows'),1,True):
        raise ValueError('Current raw/row physical-reference coverage differs')


def distribution(value,elapsed):
    number(value.get('samples'),60,True)
    points=[number(value.get(key)) for key in ('p50','p95','max')]
    if points!=sorted(points) or points[-1]>elapsed:raise ValueError('Invalid wall-callback interval distribution')


def page_state(value,state):
    expected={'ownVisible':state!='both-hidden','lootVisible':state in ('loot-collapsed','both-open'),
              'ownCollapsed':False,'lootCollapsed':state=='loot-collapsed'}
    if not isinstance(value,dict) or any(type(value.get(key)) is not bool or value[key]!=target for key,target in expected.items()):
        raise ValueError('Actual page visibility/collapse differs')
    for key in ('ownReallyVisible','lootReallyVisible','ownPaneVisible','lootPaneVisible'):
        if type(value.get(key)) is not bool:raise ValueError('Missing effective native visibility')
    if value['ownReallyVisible']!=expected['ownVisible'] or value['lootReallyVisible']!=expected['lootVisible']:
        raise ValueError('Effective native page visibility differs')


def feature_state(row):
    value=row.get('features',{})
    for key in ('normal','ground','wanted'):
        if type(value.get(key)) is not bool:raise ValueError('Missing public highlight/Wishlist state')
    number(value.get('radius'),1)
    expected={'off-empty':(False,True,False),'normal-only':(True,False,False),
              'wishlist-only':(False,True,True),'both-enabled':(True,True,True),'off-repeat':(False,True,False)}
    control=row['control']
    if control!='ordinary' and tuple(value[key] for key in ('normal','ground','wanted'))!=expected[control]:
        raise ValueError('Public highlight/Wishlist control did not commit')
    if control=='ordinary' and value['wanted']:raise ValueError('Ordinary workload has unexpected wanted membership')
    highlight=row.get('highlight',{})
    for key in ('sampleTicks','maxTracked','scanTicks','clearTicks','outlineSamples','maxOwnedHighlighted','maxOwnedOutlined'):
        number(highlight.get(key),integer=True)
    ticks=row['tickIntervalsMs']['samples']
    if highlight['sampleTicks']!=ticks or highlight['scanTicks']>ticks or highlight['clearTicks']>ticks:
        raise ValueError('Highlight observations disagree with actual ticks')
    ground=0 if control=='ordinary' else 200
    if row.get('groundObjects')!=ground or highlight['maxOwnedHighlighted']>ground or highlight['maxOwnedOutlined']>ground:
        raise ValueError('Owned ground/outlining cardinality differs')
    if control!='ordinary':
        number(highlight['outlineSamples'],1,True)
        if control in ('off-empty','off-repeat'):
            if highlight['maxTracked'] or highlight['scanTicks']:raise ValueError('Disabled empty-Wishlist control still scans/tracks')
        elif not highlight['maxTracked'] or not highlight['maxOwnedOutlined']:
            raise ValueError('Enabled highlight control lacks actual native outlining')


def environment(value):
    if not isinstance(value,dict):raise ValueError('Missing actual environment observation')
    for key in ('year','month0','day0','actorRootItems','originX','originY','originZ'):
        number(value.get(key),-100000 if key.startswith('origin') else 0,True)
    for key in ('timeOfDay','rain','fog','wind','cloud','light','actorWeight'):
        number(value.get(key))
    number(value.get('temperature'),-100)
    if value.get('width')!=1280 or value.get('height')!=900 or value.get('gameSpeed')!=1:
        raise ValueError('Viewport or normal game-speed policy changed')
    if value['month0']>11 or value['day0']>30 or value['timeOfDay']>24:
        raise ValueError('Invalid native calendar observation')


def header(value,visible):
    if not isinstance(value,dict):raise ValueError('Missing actual header values')
    number(value.get('count'),integer=True);number(value.get('expected'),integer=True);number(value.get('weight'))
    if visible and value['count']!=value['expected']:raise ValueError('Visible header count is stale')


def verify(root,text):
    if '[STORAGE_PROFILE] FAIL' in text or 'KahluaException' in text:raise ValueError('Native storage profile failed')
    def receipts(kind):
        return [json.loads(value) for value in re.findall(r'\[STORAGE_PROFILE\] '+kind+r' (\{[^\r\n]+\})',text)]
    setup=receipts('SETUP')
    if len(setup)!=1 or setup[0]!={'native':True,'crates':12,'itemType':'Base.Nails','clock':'getTimestampMs',
                                  'resolutionMs':1,'movement':'ISWalkToTimedAction','setupTeleport':True,'video':False,
                                  'proximity':True,'discoveryScope':'native-begin-end-events'}:
        raise ValueError('Missing native storage setup proof')
    startup=receipts('STARTUP')
    if len(startup)!=1 or startup[0].get('untoggled') is not True or startup[0].get('mode') not in ('clean','vanilla'):
        raise ValueError('Missing untoggled initial-instance observation')
    presentation(startup[0].get('presentation'));physical(startup[0].get('physical'))
    rows=receipts('PHASE');expected=specifications()
    if len(rows)!=len(expected):raise ValueError('Missing exact warehouse/control phase coverage')
    for index,(row,spec) in enumerate(zip(rows,expected),1):
        density,mode,state,control=spec
        if tuple(row.get(key) for key in ('index','density','mode','state','control'))!=(index,density,mode,state,control):
            raise ValueError('Duplicated/reordered warehouse phase')
        if row.get('sourceCrates')!=12 or row.get('sourceItems')!=(12 if density=='sparse' else 4800):
            raise ValueError('Native sparse/dense crate cardinality differs')
        if any(row.get(key)!=target for key,target in [('clockResolutionMs',1),('warmupMs',2000),('teleportsDuringMeasurement',0),('stateViolations',0),('discoveryPending',0)]):
            raise ValueError('Native profile measurement policy changed')
        page_state(row.get('initialState'),state);page_state(row.get('finalState'),state)
        elapsed=number(row.get('elapsedMs'),12000)
        if elapsed>=60000:raise ValueError('Native traversal exceeded its deadline')
        number(row.get('distance'),14);number(row.get('movementTicks'),30,True);number(row.get('tileChanges'),12,True)
        reached=number(row.get('reached'),4,True)
        if row.get('nativeActions')!=reached or reached%2:raise ValueError('Actual native walk did not complete its return route')
        environment(row.get('environmentInitial'));environment(row.get('environmentFinal'))
        for key in ('headerInitial','headerFinal'):header(row.get(key),state in ('loot-collapsed','both-open'))
        before=presentation(row.get('initialPresentation'));after=presentation(row.get('finalPresentation'))
        if before['signature']!=after['signature'] or before['anchor']!=after['anchor']:
            raise ValueError('Measured walking changed selection/anchor')
        delta=(row['finalPresentation']['nativeBuildCount']-row['initialPresentation']['nativeBuildCount'])%10001
        if row.get('nativeBuildDelta')!=delta:raise ValueError('Native builder counter delta differs')
        distribution(row.get('tickIntervalsMs',{}),elapsed);distribution(row.get('uiDrawIntervalsMs',{}),elapsed)
        if number(row.get('pendingTicks'),integer=True)>row['tickIntervalsMs']['samples']:raise ValueError('Pending count exceeds observed ticks')
        number(row.get('observedNearbyMaxItems'),1 if density=='sparse' else 400,True)
        number(row.get('observedNearbyMaxContainers'),1,True)
        callbacks=row.get('callbacks',{})
        if set(callbacks)!=set(CALLBACKS):raise ValueError('Missing native callback observations')
        for sample in callbacks.values():
            for key in ('calls','items','maxItems','maxContainers'):number(sample.get(key),integer=True)
            if number(sample.get('maxMs'))>number(sample.get('ms')) or sample['maxItems']>sample['items']:
                raise ValueError('Inconsistent inclusive callback measurement')
            if not sample['calls'] and any(sample.values()):raise ValueError('Callback work without a call')
        if state=='both-open' and any(callbacks[key]['calls']==0 for key in ('lootDiscoveryBody','bcOnButtonsAdded')):
            raise ValueError('Visible-loot control did not execute actual discovery/aggregation')
        feature_state(row)
    if receipts('GROUND')!=[{'objects':200,'kind':'Base.Nails','native':True}]:raise ValueError('Dense ground objects were not created/verified')
    reopens=receipts('REOPEN')
    if len(reopens)!=len(expected):raise ValueError('Missing same-count reopening coverage')
    for index,(gate,row) in enumerate(zip(reopens,rows),1):
        if gate.get('index')!=index or gate.get('replaced') is not True or gate.get('normalPostDraw') is not True or gate.get('sourceItems')!=row['sourceItems']:
            raise ValueError('Reopening replacement/lifecycle differs')
        if not isinstance(gate.get('oldId'),str) or not isinstance(gate.get('newId'),str) or gate['oldId']==gate['newId']:
            raise ValueError('Reopening did not replace an exact native identity')
        physical(gate.get('physical'));before=presentation(gate.get('before'));after=presentation(gate.get('after'))
        if gate.get('route')!=('native-pin' if row['state']=='loot-collapsed' else 'show'):
            raise ValueError('Collapsed reopening did not use native pin expansion')
        header(gate.get('header'),True)
        tooltips=gate.get('tooltips',{})
        if tooltips.get('fresh') is not True or number(tooltips.get('checked'),integer=True)<(1 if row['mode']=='clean' else 0):
            raise ValueError('Expanded owned-container tooltip freshness is unproven')
        if gate.get('pendingBefore')!=gate['before']['pending'] or gate.get('pendingAfter') is not False or gate['after']['pending']:
            raise ValueError('Normal show/draw retained pending work')
        if before['signature']!=after['signature'] or before['anchor']!=after['anchor']:
            raise ValueError('Reopening lost selection/anchor')
    guards=receipts('SELECTION')
    if [gate.get('mode') for gate in guards]!=['clean','vanilla']:raise ValueError('Missing nonempty native selection checks')
    for gate in guards:
        number(gate.get('nativeUpdates'),1,True)
        before=presentation(gate.get('before'));hidden=presentation(gate.get('hidden'));after=presentation(gate.get('after'));physical(gate.get('physical'))
        if before['count']<1 or not before['anchor'] or gate.get('preserved') is not True:raise ValueError('Selection check has no real physical selection/anchor')
        if gate['hidden']['pending'] or gate['after']['pending'] or any(value['signature']!=before['signature'] or value['anchor']!=before['anchor'] for value in (hidden,after)):
            raise ValueError('Selected hidden refresh lost live input/anchor')
    fairness=receipts('FAIRNESS')
    if [gate.get('control') for gate in fairness]!=['normal-only','wishlist-only']:
        raise ValueError('Missing native moving-ground discovery controls')
    for gate in fairness:
        if any(gate.get(key)!=3000 for key in ('objects','eligible','outlinedDuringMovement')):
            raise ValueError('Moving native pile was not completely discovered')
        if gate.get('nativeActions')!=12 or gate.get('reached')!=12 or gate.get('teleports')!=0:
            raise ValueError('Native fairness route did not complete')
        if gate.get('disabledBefore') is not True or gate.get('observationalTiming') is not False:
            raise ValueError('Fairness control/timing boundary changed')
        number(gate.get('distance'),40);number(gate.get('tileChanges'),40,True)
        number(gate.get('movementTicks'),100,True);number(gate.get('samples'),10,True)
        number(gate.get('maxTileGapTicks'),1,True)
        if not 12000<=number(gate.get('elapsedMs'))<90000:raise ValueError('Invalid fairness duration')
        features=gate.get('features',{})
        normal=gate['control']=='normal-only'
        if any(features.get(key) is not value for key,value in (('normal',normal),('ground',not normal),('wanted',not normal))):
            raise ValueError('Native fairness public feature control differs')
        number(features.get('radius'),3)
    if receipts('RESTORED')!=[{'wrappers':True,'cratesRemoved':12,'groundRemoved':200,'fairnessRemoved':3000,'features':True,'phases':len(expected)}]:
        raise ValueError('Owned objects/settings/list/helpers were not restored')
    events=re.findall(r'\[STORAGE_PROFILE\] (SETUP|STARTUP|PHASE|REOPEN|GROUND|SELECTION|FAIRNESS|RESTORED|COMPLETE)\b',text)
    if events!=['SETUP','STARTUP']+['PHASE','REOPEN']*16+['GROUND']+['PHASE','REOPEN']*5+['SELECTION','SELECTION','FAIRNESS','FAIRNESS','RESTORED','COMPLETE']:
        raise ValueError('Profile lifecycle reordered')
    return {'phases':rows,'startup':startup[0],'reopening':reopens,'selection':guards,'fairness':fairness,'limits':[
        'Actual native walking in a disposable SP sparse/dense corridor; not a user-save stutter reproduction or performance pass.',
        'OnTick and OnPreUIDraw wall-callback intervals are not GPU timing or FPS. Timings have 1 ms resolution.',
        'Discovery body is passive native begin/end timing and excludes outer tails; callback times are inclusive and must not be summed.',
        'Native builder counts use the reviewed refreshContainerCount modulo 10001. Timed phases preserve page/pane refresh method identity; builder CPU is not isolated. The later selection guard temporarily observes pane.update.',
        'Visible header counts are checked against native recursive inventory counts; collapsed reopening uses native pin/update without setVisible, then checks actual owned-crate capacity tooltips in CleanUI.',
        'Selection checks observe a natural pane update before the following draw. Moving-ground controls sample 3000 native objects during real walking for normal and Wishlist-only discovery; this correctness instrumentation is not a CPU/FPS measurement or proof that an old scanner would fail at the observed native walking cadence.',
        'Item setup and two-second warmups are excluded. Public highlighter state is read per tick; owned native outline flags are sampled at most once per second during controls.',
        'Timed ground controls use 200 distinct native objects; the later correctness-only movement controls add a separate 3000-object pile. Public settings and Wishlist requests are used and restored; no per-item mocks.',
        'Fixed sandbox starting month/day/time and viewport; weather and random actor appearance are not overridden and per-phase conditions are recorded.',
        'Programmatic UI setup and SP movement do not establish physical input, Host walking, Windows or all gameplay coverage.']}
