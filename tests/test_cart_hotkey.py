"""Hotkey evidence must prove its input route and the serialized world placement."""
import copy
import json
import unittest
from test_cart_repeat import analyzer, fixture, edit_log


def hotkey_fixture():
    values=list(copy.deepcopy(fixture()))
    def update(row):
        if row['actionType']=='ToolkitWoodCartSetdown': row['actionType']='ToolkitWoodCartDrop'
        row.update(worldX=20.25,worldY=30.75,worldZ=7,worldRotation=135)
    values=list(edit_log(values,update))
    rows=[json.loads(line.split('] ',1)[1]) for line in values[0].splitlines() if line.startswith('[WOOD_INTERACTION_EVENT] ')]
    extra=[]
    for index,name in enumerate(analyzer.CASES):
        starts=[r for r in values[1] if r['event']=='start' and r['metaType']=='ToolkitWoodCartSetdown' and 100000+index*25000<=r['wallTimeMillis']<120000+index*25000]
        for event in [r for r in rows if r['case']==name and r['event']=='actionQueued']:
            start=next((r for r in starts if r['nativeActionId']==index*4+event['actionSerial']),None)
            if start is None: continue
            for kind,wall in [('queued',event['wall']),('started',start['wallTimeMillis']+25)]:
                extra.append('[WOOD_HOTKEY] '+json.dumps(dict(event=kind,case=name,start=event['start'],wall=wall,actionSerial=event['actionSerial'],id=event['id'],key=47,actionType='ToolkitWoodCartDrop',route='OnKeyStartPressed',x=20.25,y=30.75,z=7,rotation=135,actorX=20.3,actorY=29.5,actorZ=7)))
            extra.append('[WOOD_HOTKEY_RELEASE] '+json.dumps(dict(case=name,start=event['start'],wall=event['wall']+25,actionSerial=event['actionSerial'],id=event['id'],key=47)))
    for row in values[1]:
        if row['metaType']=='ToolkitWoodCartSetdown': row['metaType']='ToolkitWoodCartDrop'
    values[0]+='\n'+'\n'.join(extra)
    return values


class HotkeyChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.values=hotkey_fixture()

    def test_native_hotkey_bank(self):
        self.assertTrue(analyzer.analyze(*self.values,hotkey=True)['functionalPass'])

    def test_menu_bank_cannot_impersonate_hotkey(self):
        with self.assertRaisesRegex(AssertionError,'lifecycle'):
            analyzer.analyze(*fixture(),hotkey=True)

    def test_missing_entry_or_start_receipt(self):
        values=self.values[:]
        values[0]=values[0].replace('[WOOD_HOTKEY] ','[OMITTED] ',1)
        with self.assertRaisesRegex(AssertionError,'hotkey entry'):
            analyzer.analyze(*values,hotkey=True)

    def test_world_position_and_rotation_are_checked(self):
        for field,value in [('worldX',20.3),('worldRotation',136)]:
            def corrupt(row):
                if row['case']==analyzer.CASES[0] and row.get('event')=='actionCompleted' and row['actionSerial']==2: row[field]=value
            with self.subTest(field=field), self.assertRaisesRegex(AssertionError,'world placement|world rotation'):
                analyzer.analyze(*edit_log(self.values,corrupt),hotkey=True)

    def test_missing_key_release_is_rejected(self):
        values=self.values[:];values[0]=values[0].replace('[WOOD_HOTKEY_RELEASE]','[OMITTED]',1)
        with self.assertRaisesRegex(AssertionError,'release receipts'):
            analyzer.analyze(*values,hotkey=True)

    def test_same_square_is_not_adjacent_coverage(self):
        values=self.values[:]
        values[0]=values[0].replace('"actorY": 29.5','"actorY": 30.5')
        with self.assertRaisesRegex(AssertionError,'adjacent-square'):
            analyzer.analyze(*values,hotkey=True)


if __name__=='__main__': unittest.main()
