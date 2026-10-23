"""Stateful admission regressions for the test-only Lua v2 lease reference model."""
import json
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROTOCOL = ROOT / 'tests/native_queue/contributions/wooden_cart_multiplayer/lease-protocol.lua'
LUA = shutil.which('luajit')

SETUP = r'''
local P = dofile(PROTOCOL_PATH)
local function check(value, message) assert(value, message or 'scenario assertion failed') end
local function copy(row)
    local out={};for k,v in pairs(row) do out[k]=v end;return out
end
local protected={'session','grant','lease','seq','open','body','received','visible'}
local function unchanged(before, after)
    for _,field in ipairs(protected) do
        assert(before[field]==after[field], 'rejection changed '..field)
    end
end
local function binding(mode,item,action,cart)
    return {mode=mode or 'motion',cart=cart or 42,item=item or {},action=action}
end
local function setup(options)
    options=options or {}
    local f={id=7,sourceConnection={},sourceActor={},observerConnection={},observerActor={},
        sourceItem={},observerItem={}}
    f.server=P.server('server-boot-A',options)
    f.sourceBinding=binding('motion',f.sourceItem)
    f.localBinding=binding('motion',f.observerItem)
    check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding),'server native registration')
    f.receiver=P.receiver(f.id,'observer-challenge',options)
    check(f.receiver:native(f.observerConnection,f.observerActor,f.localBinding),'observer native registration')
    function f:bind()
        local challenge=self.receiver:challenge();check(challenge,'fresh challenge')
        local reply=self.server:reply(challenge,self.observerConnection);check(reply,'authoritative reply')
        check(self.receiver:reply(reply,self.observerConnection),'admit current exact reply')
        self.reply=reply;return reply
    end
    function f:envelope(seq,op,body)
        local reply=self.reply
        return {session=reply.session,grant=reply.grant,lease=reply.lease,seq=seq,
            op=op or 'UPDATE',mode=reply.mode,cart=reply.cart,body=op=='END' and '' or body or 'pose-'..seq}
    end
    function f:deliver(envelope,now)
        check(self.server:accept(self.id,self.sourceConnection,self.sourceActor,envelope,now),'authoritative accept')
        check(self.receiver:receive(envelope,now),'observer accept')
    end
    function f:reject(envelope,now)
        local before=self.receiver:snapshot()
        check(not self.receiver:receive(envelope,now),'unexpected observer acceptance')
        unchanged(before,self.receiver:snapshot())
        local serverBefore=self.server:snapshot(self.id)
        check(not self.server:accept(self.id,self.sourceConnection,self.sourceActor,envelope,now),'unexpected server acceptance')
        unchanged(serverBefore,self.server:snapshot(self.id))
    end
    return f
end
'''


@unittest.skipUnless(LUA, 'LuaJIT required for the actual lease controller')
class LeaseProtocolScenarios(unittest.TestCase):
    def scenario(self, script):
        result = subprocess.run([LUA, '-'], input='local PROTOCOL_PATH='+json.dumps(str(PROTOCOL))+'\n'+SETUP+'\n'+script,
                                text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)

    def test_unfamiliar_payload_cannot_authorize_its_own_grant(self):
        self.scenario(r'''
local f=setup()
local fabricated={session='unseen-server',grant=999,lease=999,seq=999,op='OPEN',mode='motion',cart=42,body='cached-old-pose'}
f:reject(fabricated,100)
f:bind();f:deliver(f:envelope(1,'OPEN','fresh'),101)
check(f.receiver:snapshot().body=='fresh')
''')

    def test_grant_requires_fresh_exact_challenge_and_ingress_connection(self):
        self.scenario(r'''
local f=setup()
local challenge=f.receiver:challenge();local reply=f.server:reply(challenge,f.observerConnection)
local wrong=copy(reply);wrong.nonce=reply.nonce..'-old'
local before=f.receiver:snapshot()
check(not f.receiver:reply(wrong,f.observerConnection),'wrong nonce admitted')
unchanged(before,f.receiver:snapshot())
check(not f.receiver:reply(reply,{}),'wrong ingress admitted')
check(f.receiver:reply(reply,f.observerConnection),'valid pending reply was consumed by rejection')
f.reply=reply;f:deliver(f:envelope(1),100)
check(not f.receiver:reply(reply,f.observerConnection),'replayed grant admitted without challenge')
''')

    def test_superseded_challenge_cannot_adopt_old_reply(self):
        self.scenario(r'''
local f=setup()
local first=f.receiver:challenge();local old=f.server:reply(first,f.observerConnection)
local second=f.receiver:challenge();check(first.nonce~=second.nonce,'challenge reused nonce')
local current=f.server:reply(second,f.observerConnection)
check(not f.receiver:reply(old,f.observerConnection),'old challenge reply adopted')
check(f.receiver:reply(current,f.observerConnection),'current challenge rejected')
''')

    def test_pinned_server_session_changes_only_after_native_connection_replacement(self):
        self.scenario(r'''
local f=setup();f:bind();f:deliver(f:envelope(1),100)
local other=P.server('server-boot-B')
check(other:observe(f.id,{}, {},f.sourceBinding))
local request=f.receiver:challenge();local wrongBoot=other:reply(request,f.observerConnection)
check(not f.receiver:reply(wrongBoot,f.observerConnection),'unfamiliar boot adopted on existing connection')
f.observerConnection={};check(f.receiver:native(f.observerConnection,f.observerActor,f.localBinding))
local fresh=f.receiver:challenge();local nextBoot=other:reply(fresh,f.observerConnection)
check(f.receiver:reply(nextBoot,f.observerConnection),'verified native reconnect could not bind new boot')
''')

    def test_unknown_lease_requires_current_authority_even_after_missed_lifetime(self):
        self.scenario(r'''
local f=setup();f:bind();f:deliver(f:envelope(1),100)
local old=f:envelope(2,'UPDATE','prior-held')
-- The observer missed the intervening action and its retirement entirely.
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,binding('action',f.sourceItem,{})))
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,binding('motion',f.sourceItem)))
check(not f.server:accept(f.id,f.sourceConnection,f.sourceActor,old,200),'server relayed previously unseen retired lifetime')
local challenge=f.receiver:challenge();local grant=f.server:reply(challenge,f.observerConnection)
local fresh={session=grant.session,grant=grant.grant,lease=grant.lease,seq=1,
    op='UPDATE',mode=grant.mode,cart=grant.cart,body='current-held'}
local before=f.receiver:snapshot()
check(not f.receiver:receive(fresh,201),'unknown lease adopted from data')
unchanged(before,f.receiver:snapshot())
check(f.receiver:reply(grant,f.observerConnection),'fresh current lease grant rejected')
f.reply=grant;f:deliver(fresh,202);f:reject(old,203)
''')

    def test_rejection_preserves_last_pose_freshness_and_newer_updates(self):
        self.scenario(r'''
local f=setup();f:bind();f:deliver(f:envelope(3,'UPDATE','moving'),100)
for _,packet in ipairs({f:envelope(3,'UPDATE','duplicate'),f:envelope(2,'UPDATE','older'),
                        f:envelope(1,'END','old-terminal')}) do f:reject(packet,900) end
local unknown=f:envelope(4);unknown.grant=unknown.grant+1;f:reject(unknown,901)
local oldLease=f:envelope(4);oldLease.lease=oldLease.lease+10;f:reject(oldLease,902)
f:deliver(f:envelope(4,'UPDATE','newer'),1000)
local final=f.receiver:snapshot();check(final.body=='newer' and final.received==1000,'new valid update failed')
''')

    def test_repeated_native_snapshots_keep_lease_and_accepted_freshness(self):
        self.scenario(r'''
local f=setup();f:bind();f:deliver(f:envelope(3,'UPDATE','stable'),100)
local before=f.receiver:snapshot();local serverBefore=f.server:snapshot(f.id)
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,binding('motion',f.sourceItem)))
check(not f.receiver:native(f.observerConnection,f.observerActor,binding('motion',f.observerItem)),'identical native binding falsely changed')
unchanged(before,f.receiver:snapshot());unchanged(serverBefore,f.server:snapshot(f.id))
f:reject(f:envelope(3,'UPDATE','cached'),500)
''')

    def test_exact_action_instance_replacement_retires_same_item_action_lease(self):
        self.scenario(r'''
local f=setup()
f.sourceBinding=binding('action',f.sourceItem,{});f.localBinding=binding('action',f.observerItem,{})
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding))
check(f.receiver:native(f.observerConnection,f.observerActor,f.localBinding))
f:bind();f:deliver(f:envelope(1,'UPDATE','first-action'),100)
local old=f:envelope(2,'END')
f.sourceBinding=binding('action',f.sourceItem,{});f.localBinding=binding('action',f.observerItem,{})
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding))
check(f.receiver:native(f.observerConnection,f.observerActor,f.localBinding))
f:bind();f:deliver(f:envelope(1,'UPDATE','next-action'),200)
f:reject(old,201)
''')

    def test_signed_cart_id_and_exact_control_binding_are_validated(self):
        self.scenario(r'''
local f=setup()
f.sourceBinding=binding('motion',f.sourceItem,nil,-2147483648)
f.localBinding=binding('motion',f.observerItem,nil,-2147483648)
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding))
check(f.receiver:native(f.observerConnection,f.observerActor,f.localBinding))
local pending=f.receiver:challenge();local reply=f.server:reply(pending,f.observerConnection)
for _,change in ipairs({{actor=8},{mode='action'},{cart=42},{grant=0},{lease=0}}) do
    local wrong=copy(reply);for k,v in pairs(change) do wrong[k]=v end
    check(not f.receiver:reply(wrong,f.observerConnection),'malformed or foreign control adopted')
end
check(f.receiver:reply(reply,f.observerConnection),'valid control rejected after bad proposals')
f.reply=reply;f:deliver(f:envelope(1),100)
''')

    def test_end_before_open_is_a_permanent_sequenced_tombstone(self):
        self.scenario(r'''
local f=setup();f:bind();f:deliver(f:envelope(2,'END','terminal'),100)
f:reject(f:envelope(1,'OPEN'),101)
f:reject(f:envelope(2,'END'),102)
f:reject(f:envelope(99,'UPDATE'),103)
check(not f.receiver:snapshot().open,'closed lease reopened')
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding),'same native observation')
local challenge=f.receiver:challenge();local repeatGrant=f.server:reply(challenge,f.observerConnection)
check(repeatGrant and not repeatGrant.open,'same native binding reopened server lease')
f.receiver:reply(repeatGrant,f.observerConnection)
f:reject(f:envelope(100,'OPEN'),104)
''')

    def test_shared_motion_action_motion_leases_reject_old_action_end(self):
        self.scenario(r'''
local f=setup();f:bind();f:deliver(f:envelope(1,'OPEN','held-first'),100)
local held=f:envelope(2,'UPDATE','old-held')
f.sourceBinding=binding('action',f.sourceItem,{})
f.localBinding=binding('action',f.observerItem,{})
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding))
check(f.receiver:native(f.observerConnection,f.observerActor,f.localBinding))
f:bind();f:deliver(f:envelope(1,'OPEN','action-first'),200)
local actionEnd=f:envelope(2,'END','old-action-end')
f.sourceBinding=binding('motion',f.sourceItem)
f.localBinding=binding('motion',f.observerItem)
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding))
check(f.receiver:native(f.observerConnection,f.observerActor,f.localBinding))
f:bind();f:deliver(f:envelope(1,'OPEN','held-next'),300)
f:reject(held,400);f:reject(actionEnd,401)
check(f.receiver:snapshot().body=='held-next','old mode altered current held pose')
''')

    def test_lost_end_native_release_blocks_even_unseen_late_lease(self):
        self.scenario(r'''
local f=setup();f:bind()
local delayed=f:envelope(1,'OPEN','never-delivered')
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,nil),'native release')
f.receiver:native(f.observerConnection,f.observerActor,nil)
f:reject(delayed,100)
f.sourceBinding=binding('motion',f.sourceItem);f.localBinding=binding('motion',f.observerItem)
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding))
check(f.receiver:native(f.observerConnection,f.observerActor,f.localBinding))
f:reject(delayed,101)
f:bind();f:deliver(f:envelope(1,'OPEN','new-lifetime'),102)
f:reject(delayed,103)
''')

    def test_fresh_closed_authority_reply_retires_lost_end_without_local_release(self):
        self.scenario(r'''
local f=setup();f:bind();f:deliver(f:envelope(1,'UPDATE','held'),100)
local delayed=f:envelope(2,'UPDATE','cached-held')
local challenge=f.receiver:challenge()
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,nil),'server observed native release')
local closed=f.server:reply(challenge,f.observerConnection)
check(closed and not closed.open,'release authority advertised an open lease')
check(f.receiver:reply(closed,f.observerConnection),'current closed reply was not admitted')
check(not f.receiver:snapshot().open and not f.receiver:snapshot().visible,'lost END retained presentation permission')
f:reject(delayed,200)
''')

    def test_same_numeric_cart_id_new_native_item_requires_new_bind(self):
        self.scenario(r'''
local f=setup();f:bind();f:deliver(f:envelope(1),100)
local delayed=f:envelope(2,'UPDATE','old-object')
local pending=f.receiver:challenge();local oldReply=f.server:reply(pending,f.observerConnection)
f.sourceBinding=binding('motion',{});f.localBinding=binding('motion',{})
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding))
check(f.receiver:native(f.observerConnection,f.observerActor,f.localBinding))
check(not f.receiver:reply(oldReply,f.observerConnection),'same cart ID bypassed exact object fence')
f:reject(delayed,200);f:bind();f:deliver(f:envelope(1,'OPEN','replacement'),201)
f:reject(delayed,202)
''')

    def test_native_revision_fences_an_unpolled_release_and_reacquire(self):
        self.scenario(r'''
local f=setup()
f.sourceBinding.lifetime='server:actor:1';f.localBinding.lifetime='observer:actor:9'
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding))
check(f.receiver:native(f.observerConnection,f.observerActor,f.localBinding))
f:bind();f:deliver(f:envelope(3,'UPDATE','before-cycle'),100)
local delayed=f:envelope(4,'UPDATE','retired-cycle')
local request=f.receiver:challenge();local pending=f.server:reply(request,f.observerConnection)
-- Both native hand setters witnessed release/reacquire between these polls.
-- Exact actor/item/cart and connection references are otherwise unchanged.
f.sourceBinding.lifetime='server:actor:5';f.localBinding.lifetime='observer:actor:13'
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding))
check(f.receiver:native(f.observerConnection,f.observerActor,f.localBinding))
check(not f.receiver:reply(pending,f.observerConnection),'unpolled cycle admitted stale challenge reply')
f:reject(delayed,200)
local fresh=f:bind();check(fresh.lease>pending.lease,'server native cycle did not advance lease')
f:deliver(f:envelope(1,'OPEN','after-cycle'),201);f:reject(delayed,202)
check(f.receiver:snapshot().body=='after-cycle','old payload replaced fresh lifetime')
''')

    def test_native_revision_is_local_identity_and_stable_observation_does_not_reset(self):
        self.scenario(r'''
local f=setup()
f.sourceBinding.lifetime='server-native-revision';f.localBinding.lifetime='observer-native-revision'
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding))
check(f.receiver:native(f.observerConnection,f.observerActor,f.localBinding))
f:bind();f:deliver(f:envelope(3),100)
local before=f.receiver:snapshot();local serverBefore=f.server:snapshot(f.id)
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding))
check(not f.receiver:native(f.observerConnection,f.observerActor,f.localBinding))
unchanged(before,f.receiver:snapshot());unchanged(serverBefore,f.server:snapshot(f.id))
f:deliver(f:envelope(4),200)
''')

    def test_actor_id_reuse_and_connection_replacement_need_new_authority(self):
        self.scenario(r'''
for _,replacement in ipairs({'actor','connection'}) do
    local f=setup();f:bind();f:deliver(f:envelope(1),100)
    local old=f:envelope(2,'UPDATE','prior-incarnation')
    local pending=f.receiver:challenge();local oldReply=f.server:reply(pending,f.observerConnection)
    if replacement=='actor' then f.sourceActor={};f.observerActor={}
    else f.sourceConnection={};f.observerConnection={} end
    check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding))
    check(f.receiver:native(f.observerConnection,f.observerActor,f.localBinding))
    check(not f.receiver:reply(oldReply,f.observerConnection),'old native incarnation reply admitted')
    f:reject(old,200);f:bind();f:deliver(f:envelope(1,'OPEN','new-incarnation'),201)
    f:reject(old,202)
end
''')

    def test_visual_suspension_retains_accepted_state_and_ordering_fences(self):
        self.scenario(r'''
local f=setup();f:bind();f:deliver(f:envelope(5,'UPDATE','accepted-moving'),100)
local before=f.receiver:snapshot();f.receiver:suspend();local hidden=f.receiver:snapshot()
for _,field in ipairs({'grant','lease','seq','body','received'}) do check(before[field]==hidden[field],'suspend erased '..field) end
check(not hidden.visible,'suspension left presentation visible')
f:reject(f:envelope(5,'UPDATE','cached-moving'),999)
f:deliver(f:envelope(6,'UPDATE','resumed'),1000)
check(f.receiver:snapshot().visible,'strictly newer valid state did not resume')
''')

    def test_server_rejects_wrong_native_source_before_acceptance_mutation(self):
        self.scenario(r'''
local f=setup();f:bind();f:deliver(f:envelope(1),100)
local before=f.server:snapshot(f.id)
check(not f.server:accept(f.id,{},f.sourceActor,f:envelope(2),200),'foreign connection accepted')
check(not f.server:accept(f.id,f.sourceConnection,{},f:envelope(2),201),'foreign actor accepted')
unchanged(before,f.server:snapshot(f.id))
check(f.server:accept(f.id,f.sourceConnection,f.sourceActor,f:envelope(2),202),'current source blocked after rejection')
''')

    def test_state_cap_never_evicts_existing_replay_floor(self):
        self.scenario(r'''
local f=setup({limit=1});f:bind();f:deliver(f:envelope(2,'END'),100)
check(not f.server:observe(8,{},{},binding('motion',{})),'cap admitted another actor')
f:reject(f:envelope(3,'OPEN'),200)
check(not f.server:accept(f.id,f.sourceConnection,f.sourceActor,f:envelope(3,'OPEN'),201),'cap evicted old terminal floor')
''')

    def test_bad_shape_numeric_bounds_and_body_limit_never_refresh_admission(self):
        self.scenario(r'''
local f=setup();f:bind();f:deliver(f:envelope(1,'UPDATE','moving'),100)
for _,change in ipairs({{seq=0},{seq=-1},{seq=1.5},{seq=0/0},{seq=math.huge},
                        {lease=0},{grant=0},{cart=2147483648},{cart=-2147483649},
                        {op='CLEAR'},{mode='other'},{body=string.rep('x',1000000)}}) do
    local packet=f:envelope(2)
    for k,v in pairs(change) do packet[k]=v end
    f:reject(packet,200)
end
f:deliver(f:envelope(2,'UPDATE','still-current'),201)
''')

    def test_counter_exhaustion_never_wraps_or_reuses_challenge(self):
        self.scenario(r'''
local f=setup({maxCounter=2});f:bind()
local second=f.receiver:challenge();check(second and second.nonce~=f.reply.nonce,'second challenge reused identity')
check(not f.receiver:challenge(),'exhausted challenge counter wrapped')
check(not f.receiver:challenge(),'exhausted challenge counter later revived')
''')

    def test_native_lease_counter_exhaustion_disables_old_native_binding(self):
        self.scenario(r'''
local f=setup({maxCounter=2});f:bind();f:deliver(f:envelope(1),100)
f.sourceBinding=binding('action',f.sourceItem,{})
check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding),'second native lease')
local challenge=f.receiver:challenge();local second=f.server:reply(challenge,f.observerConnection)
check(second and second.lease>f.reply.lease,'lease did not advance')
local old={session=second.session,grant=second.grant,lease=second.lease,seq=1,
    op='UPDATE',mode=second.mode,cart=second.cart,body='old-action'}
check(not f.server:observe(f.id,f.sourceConnection,f.sourceActor,binding('motion',f.sourceItem)),'lease counter silently wrapped')
check(not f.server:accept(f.id,f.sourceConnection,f.sourceActor,old,200),'exhaustion preserved old native authority')
''')

    def test_actor_grant_counter_exhaustion_never_reauthorizes_retired_actor(self):
        self.scenario(r'''
local f=setup({maxCounter=2});f:bind()
f.sourceActor={};check(f.server:observe(f.id,f.sourceConnection,f.sourceActor,f.sourceBinding),'second actor grant')
local challenge=f.receiver:challenge();local second=f.server:reply(challenge,f.observerConnection)
check(second and second.grant>f.reply.grant,'actor replacement did not advance grant')
local retiredActor=f.sourceActor
local old={session=second.session,grant=second.grant,lease=second.lease,seq=1,
    op='UPDATE',mode=second.mode,cart=second.cart,body='retired-actor'}
check(not f.server:observe(f.id,f.sourceConnection,{},f.sourceBinding),'actor grant counter wrapped')
check(not f.server:accept(f.id,f.sourceConnection,retiredActor,old,200),'retired actor retained authority after exhaustion')
''')

    def test_sequence_maximum_is_not_a_reset_or_wrap_permission(self):
        self.scenario(r'''
local f=setup({maxCounter=3});f:bind();f:deliver(f:envelope(3,'UPDATE','last-sequence'),100)
f:reject(f:envelope(1,'OPEN','wrapped'),101);f:reject(f:envelope(4,'UPDATE','overflow'),102)
check(not f.server:accept(f.id,f.sourceConnection,f.sourceActor,f:envelope(1,'OPEN'),103),'server accepted sequence wrap')
check(not f.server:accept(f.id,f.sourceConnection,f.sourceActor,f:envelope(4),104),'server accepted sequence overflow')
''')


if __name__ == '__main__':
    unittest.main()
