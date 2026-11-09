"""Exercise fixture stage boundaries without native game APIs or processes."""
import json
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / 'tests/native_queue'


class CaseStageLuaTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lines = []
        self.lua.globals().print = lambda value: self.lines.append(str(value))
        self.lua.execute("next=nil")  # Native Kahlua does not expose this Lua global.
        self.lua.execute("package.loaded.QueuePreflightConfig={token=string.rep('a',32),roles={'client1'}}")
        self.lua.globals().package.loaded.QueueHealthEvents = self.lua.execute(
            (NATIVE / 'health/shared/QueueHealthEvents.lua').read_text())
        self.lua.globals().package.loaded.QueueCaseStages = self.lua.execute(
            (NATIVE / 'support/QueueCaseStages.lua').read_text())

    def receipts(self):
        prefix = '[QUEUE_CASE_STAGE] '
        return [json.loads(line[len(prefix):]) for line in self.lines if line.startswith(prefix)]

    def test_each_case_has_fresh_context_and_exact_boundary_sequence(self):
        self.lua.execute("""
            local stages=require('QueueCaseStages').new('device-target-loss','client1')
            for _,identifier in ipairs({'tv-remove','radio-move'})do
                stages:setup(identifier);stages:gameplay();stages:cleanup();stages:complete()
            end
        """)
        rows = self.receipts()
        for offset, case in ((0, 'tv-remove'), (4, 'radio-move')):
            self.assertEqual([('setup', 'started'), ('gameplay', 'started'),
                              ('cleanup', 'started'), ('cleanup', 'passed')],
                             [(row['stage'], row['status']) for row in rows[offset:offset + 4]])
            for row in rows[offset:offset + 4]:
                self.assertEqual(dict(token='a' * 32, suite='device-target-loss', role='client1',
                                      case=case, stage=row['stage'], status=row['status']), row)

    def test_active_failure_preserves_first_stage_and_cannot_restart(self):
        for stage in ('setup', 'gameplay', 'cleanup'):
            with self.subTest(stage=stage):
                self.lines.clear()
                self.lua.globals().target_stage = stage
                self.lua.globals().failure_reason = 'corridor "lost"\nagain'
                self.lua.execute("""
                    local stages=require('QueueCaseStages').new('device-target-loss','client1')
                    stages:setup('tv-remove')
                    if target_stage~='setup'then stages:gameplay()end
                    if target_stage=='cleanup'then stages:cleanup()end
                    stages:fail(failure_reason);stages:fail('secondary')
                    assert(not pcall(stages.setup,stages,'radio-move'))
                    assert(not pcall(stages.complete,stages))
                """)
                failures = [row for row in self.receipts() if row['status'] == 'failed']
                self.assertEqual(1, len(failures))
                self.assertEqual(stage, failures[0]['stage'])
                self.assertEqual('corridor "lost"\nagain', failures[0]['reason'])

    def test_invalid_transitions_and_roles_do_not_emit_receipts(self):
        self.lua.execute("""
            local module=require('QueueCaseStages')
            assert(not pcall(module.new,'device-target-loss','client2'))
            local stages=module.new('device-target-loss','client1')
            stages:fail('before active case')
            assert(not pcall(stages.gameplay,stages))
            assert(not pcall(stages.setup,stages,''))
            stages:setup('tv-remove')
            assert(not pcall(stages.cleanup,stages))
            assert(not pcall(stages.setup,stages,'radio-move'))
            stages:gameplay();assert(not pcall(stages.gameplay,stages))
            stages:cleanup();stages:complete();stages:fail('functional verdict after cleanup')
        """)
        self.assertEqual(4, len(self.receipts()))

    def load_client(self):
        self.lua.execute("""
            for _,name in ipairs({'PZSurvivorToolkit/ActionQueuePanel','RadioCom/ISRadioAction',
                'RadioCom/ISUIRadio/ISItemDropBox','RadioCom/ISUIRadio/ISSpeakerButton',
                'RadioCom/ISUIRadio/ISVolumeBar','RadioCom/RadioWindowModules/RWMVolume',
                'TimedActions/ISReadABook'})do package.loaded[name]={}end
            package.loaded.QueueTestSelection={cases={'tv-remove'},kind='sp',mode='toolkit',
                options={device_target_loss_expect='safe'}}
            fixture={walkCase=function()return false end};package.loaded.QueueDeviceTargetLoss=fixture
            package.loaded.QueueEnergyPlacement={}
            package.loaded.QueuePreflight={
                onGameStart=function(_,fn)gameStart=fn end,onTick=function(_,fn)fixtureTick=fn end}
            Events={OnServerCommand={Add=function(fn)serverCommand=fn end}}
            PZSurvivorToolkit={}
            getTimestampMs=function()return 1000 end
            player={hasTimedActions=function()return false end}
            getPlayer=function()return player end
            work={queue={}};ISTimedActionQueue={getTimedActionQueue=function()return work end}
            ISReadABook={};ISRadioAction={};ISQueueActionsAction={}
        """)
        return self.lua.execute((NATIVE / 'device-target-loss/client/ZZDeviceTargetLoss.lua').read_text() + """
            return {
                prepare=function()
                    gameStart();ready=true;phase='prepare'
                    fixture.choosePlacement=function()error('corridor not loaded')end
                end,
                gameplay=function()
                    gameStart();ready=true;phase='prepared';ids={};state={}
                    fixture.resolve=function()return state end
                    fixture.snapshot=function()return {heldDataSame=true,heldDataParentSame=true,
                        oldPresent=true,destinationPresent=false}end
                    ISReadABook.new=function()error('native action admission failed')end
                end,
                cleanup=function()
                    gameStart();ready=true;phase='cleanup';cleanup=true;state={}
                    stages:gameplay();stages:cleanup()
                    fixture.cleaned=function()error('cleanup replication failed')end
                end,
                verdict=function()
                    gameStart();ready=true;phase='cleanup';cleanup=true;state={}
                    stages:gameplay();stages:cleanup();fixture.cleaned=function()return true end
                    setter={};tracked={[setter]={}};outcome={queueIdle=false}
                    local ok,problem=pcall(finish);assert(not ok);fail(problem)
                end,
                awaiting=function()
                    gameStart();pendingCommand='Prepare';phase='prepared'
                end,
            }
        """)

    def test_fixture_exceptions_report_the_boundary_that_owned_the_work(self):
        for stage, setup in (('setup', 'prepare'), ('gameplay', 'gameplay'), ('cleanup', 'cleanup')):
            with self.subTest(stage=stage):
                self.setUp()
                client = self.load_client()
                client[setup]()
                self.lua.globals().fixtureTick()
                self.assertEqual((stage, 'failed'),
                                 (self.receipts()[-1]['stage'], self.receipts()[-1]['status']))

    def test_safe_verdict_fails_after_cleaning_without_reclassifying_cleanup(self):
        self.load_client().verdict()
        self.assertEqual(('cleanup', 'passed'),
                         (self.receipts()[-1]['stage'], self.receipts()[-1]['status']))
        self.assertFalse(any(row['status'] == 'failed' for row in self.receipts()))
        self.assertTrue(any('safe target loss/tail outcome not observed' in line
                            and '[QUEUE_TEST] FAIL ' in line for line in self.lines))

    def test_server_failure_requires_matching_case_and_outstanding_command(self):
        self.load_client().awaiting()
        self.lua.execute("""
            serverCommand('DeviceTargetLossTest','Failed',{case='radio-move',command='Prepare',error='stale case'})
            serverCommand('DeviceTargetLossTest','Failed',{case='tv-remove',command='Verify',error='stale command'})
        """)
        self.assertEqual(1, len(self.receipts()))
        self.lua.execute("""
            serverCommand('DeviceTargetLossTest','Failed',{case='tv-remove',command='Prepare',error='replica corridor'})
        """)
        self.assertEqual(('setup', 'failed', 'replica corridor'),
                         tuple(self.receipts()[-1][key] for key in ('stage', 'status', 'reason')))

    def test_async_authority_failure_relays_original_case_and_command(self):
        self.lua.execute("""
            isServer=function()return true end
            package.loaded.QueueTestSelection={cases={'tv-remove'},mode='toolkit'}
            package.loaded.QueueDeviceTargetLoss={}
            package.loaded.QueueEnergyPlacement={target=function(value)return value end,
                observe=function()return {}end,poll=function()error('replica corridor')end}
            Events={OnClientCommand={Add=function(fn)clientCommand=fn end},
                OnTick={Add=function(fn)authorityTick=fn end}}
            sendServerCommand=function(_,module,command,args)
                assert(module=='DeviceTargetLossTest'and command=='Failed');failure=args
            end
        """)
        self.lua.execute((NATIVE / 'device-target-loss/server/ZZDeviceTargetLossServer.lua').read_text())
        self.lua.execute("""
            local player={getUsername=function()return 'client1'end}
            clientCommand('DeviceTargetLossTest','Prepare',player,
                {case='tv-remove',clientPlacement={mode='local'},placement={}})
            authorityTick()
            assert(failure.case=='tv-remove'and failure.command=='Prepare')
            assert(failure.error:find('replica corridor',1,true))
        """)


if __name__ == '__main__':
    unittest.main()
