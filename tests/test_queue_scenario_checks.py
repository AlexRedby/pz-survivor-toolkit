"""Shared queue controls reject partial cancellation and concealed mutations."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class QueueScenarioChecksTests(unittest.TestCase):
    def run_lua(self, code):
        lua = shutil.which('luajit') or shutil.which('lua')
        if not lua:
            self.skipTest('Lua interpreter unavailable')
        setup = r'''
local Checks=dofile(arg[1]..'/tests/native_queue/support/QueueScenarioChecks.lua')
local function fixture()
 local front,pickup,equip,tail={},{},{},{}
 local queue={queue={front,pickup,equip,tail}}
 function queue:indexOf(action)
  for i,member in ipairs(self.queue) do if member==action then return i end end;return -1
 end
 return queue,front,pickup,equip,tail
end
local function rejected(fn,message)
 local ok,problem=pcall(fn)
 assert(not ok,'broken control passed')
 assert(tostring(problem):find(message,1,true),tostring(problem))
end
'''
        result = subprocess.run([lua, '-', str(ROOT)], input=setup + code,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_snapshot_keeps_identity_and_detects_order_or_size_changes(self):
        self.run_lua(r'''
local queue,front,pickup=fixture()
local before=Checks.snapshot(queue)
assert(before~=queue.queue and before[1]==front and before[2]==pickup)
Checks.unchanged(queue,before)
queue.queue[1],queue.queue[2]=queue.queue[2],queue.queue[1]
rejected(function()Checks.unchanged(queue,before)end,'queue order')
table.remove(queue.queue)
rejected(function()Checks.unchanged(queue,before)end,'queue size')
Checks.unchanged({queue={}},Checks.snapshot({queue={}}))
''')

    def test_denied_move_checks_policy_api_and_mutation(self):
        self.run_lua(r'''
local function run(fault)
 local queue,front,pickup,equip,tail=fixture()
 local policy={evaluateMove=function(q,a,target,after)
  assert(q==queue and a==pickup and target==tail and after==true)
  return {allowed=fault=='policy-allowed',reason=fault=='policy-reason' and 'other' or 'container_capacity'}
 end}
 local api={move=function(q,a,target,after)
  assert(q==queue and a==pickup and target==tail and after==true)
  if fault=='drop' then table.remove(q.queue)
  elseif fault=='reorder' then q.queue[1],q.queue[2]=q.queue[2],q.queue[1] end
  return fault=='api-allowed',fault=='api-reason' and 'other' or 'container_capacity'
 end}
 Checks.deniedMove(queue,api,policy,pickup,tail,true,'container_capacity')
end
run()
for _,fault in ipairs({'policy-allowed','policy-reason'}) do
 rejected(function()run(fault)end,'unexpected policy barrier')
end
for _,fault in ipairs({'api-allowed','api-reason'}) do
 rejected(function()run(fault)end,'queue API did not preserve policy barrier')
end
rejected(function()run('drop')end,'queue size')
rejected(function()run('reorder')end,'queue order')
''')

    def test_waiting_cancel_removes_whole_operation_and_retains_unrelated_actions(self):
        self.run_lua(r'''
local function run(fault)
 local queue,front,pickup,equip,tail=fixture()
 if fault=='drop-unlisted' then queue.queue[#queue.queue+1]={} end
 local policy={evaluateCancel=function(q,a,operation)
  assert(q==queue and a==pickup and operation==true)
  return {allowed=fault~='policy-denied',reason='blocked'}
 end}
 local api={cancelOperation=function(q,a)
  assert(q==queue and a==pickup)
  q.queue=fault=='partial' and {front,equip,tail} or fault=='drop-unrelated' and {front}
   or fault=='duplicate' and {front,tail,tail} or fault=='reorder' and {tail,front} or {front,tail}
  return fault~='api-denied'
 end}
 Checks.waitingCancel(queue,api,policy,pickup,{pickup,equip},{front,tail})
end
run()
rejected(function()run('partial')end,'whole operation was not removed')
rejected(function()run('drop-unrelated')end,'cancellation removed unrelated actions')
rejected(function()run('drop-unlisted')end,'queue size')
rejected(function()run('duplicate')end,'queue size')
rejected(function()run('reorder')end,'queue order')
rejected(function()run('policy-denied')end,'waiting operation cannot be cancelled')
rejected(function()run('api-denied')end,'waiting operation cancellation failed')
''')

    def test_active_cancel_checks_denial_and_unchanged_queue(self):
        self.run_lua(r'''
local function run(fault)
 local queue,front,pickup=fixture()
 local policy={evaluateCancel=function(q,a,operation)
  assert(q==queue and a==pickup and operation==true)
  return {allowed=fault=='policy-allowed',reason=fault=='policy-reason' and 'other' or 'operation_dependent'}
 end}
 local api={cancelOperation=function(q,a)
  assert(q==queue and a==pickup)
  if fault=='drop' then table.remove(q.queue,2)
  elseif fault=='reorder' then q.queue[1],q.queue[2]=q.queue[2],q.queue[1] end
  return fault=='api-allowed',fault=='api-reason' and 'other' or 'operation_dependent'
 end}
 Checks.deniedCancel(queue,api,policy,pickup,'operation_dependent')
end
run()
for _,fault in ipairs({'policy-allowed','policy-reason'}) do
 rejected(function()run(fault)end,'active operation must remain protected')
end
for _,fault in ipairs({'api-allowed','api-reason'}) do
 rejected(function()run(fault)end,'active cancellation bypassed policy')
end
rejected(function()run('drop')end,'queue size')
rejected(function()run('reorder')end,'queue order')
''')

    def test_independent_move_roundtrip_restores_exact_queue(self):
        self.run_lua(r'''
local function run(fault)
 local queue,front,pickup,equip,tail=fixture()
 local calls=0
 local policy={evaluateMove=function(q,a,target,after)
  assert(q==queue and a==tail and target==pickup and after==false)
  return {allowed=fault~='policy-denied'}
 end}
 local api={move=function(q,a,target,after)
  calls=calls+1;assert(q==queue and a==tail)
  assert(target==(calls==1 and pickup or equip) and after==(calls==2))
  if fault=='move-denied' and calls==1 or fault=='restore-denied' and calls==2 then return false end
  if fault=='noop' or fault=='restore-noop' and calls==2 then return true end
  table.remove(q.queue,q:indexOf(a))
  table.insert(q.queue,q:indexOf(target)+(after and 1 or 0),a)
  if calls==1 and fault=='wrong-position' then q.queue[1],q.queue[2]=q.queue[2],q.queue[1] end
  if calls==1 and fault=='missing-action' then table.remove(q.queue,q:indexOf(a)) end
  if calls==1 and fault=='missing-target' then table.remove(q.queue,q:indexOf(target)) end
  if calls==2 and fault=='mismatch' then q.queue[1],q.queue[2]=q.queue[2],q.queue[1] end
  if calls==2 and fault=='drop' then table.remove(q.queue,1) end
  return true
 end}
 Checks.moveRoundtrip(queue,api,policy,tail,pickup,false,equip,true)
 assert(calls==2)
end
run()
rejected(function()run('policy-denied')end,'independent action move should be allowed')
rejected(function()run('move-denied')end,'independent action move failed')
rejected(function()run('restore-denied')end,'independent action restore failed')
rejected(function()run('noop')end,'move did not reach requested side of target')
rejected(function()run('restore-noop')end,'move did not reach requested side of target')
rejected(function()run('missing-action')end,'move action or target missing')
rejected(function()run('missing-target')end,'move action or target missing')
rejected(function()run('wrong-position')end,'queue order')
rejected(function()run('mismatch')end,'queue order')
rejected(function()run('drop')end,'queue size')
''')


if __name__ == '__main__':
    unittest.main()
