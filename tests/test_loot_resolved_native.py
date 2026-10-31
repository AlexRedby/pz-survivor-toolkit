"""Boundary tests for the native loot opt-in, authority handshake and captured receipts."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import subprocess
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import native
from queue_checks.adapters import loot_resolved as A
LUAJIT = shutil.which('luajit')

F = ROOT / 'tests/chunk_integration/loot_resolved_runtime'
spec = importlib.util.spec_from_file_location('_loot_build_contract', F / 'build.py')
BUILD = importlib.util.module_from_spec(spec); spec.loader.exec_module(BUILD)
spec = importlib.util.spec_from_file_location('_loot_compare_contract', F / 'compare.py')
COMPARE = importlib.util.module_from_spec(spec); spec.loader.exec_module(COMPARE)


class LootResolvedNative(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = ROOT
        self.selection = dict(suite=A.SUITE, cases=['bank'], kind='sp', mode='toolkit', clients=1,
            languages=['EN'], mods=A.MODS, resources={'exclusive': True},
            options=dict(loot_runtime_mode='control', preload_toolkit_fonts=True,
                         mod_sources={A.MOD: str(self.root / 'explicit-source')}))
        source = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in F.iterdir() if p.is_file()}
        for name, path in [('ResolvedCandidate.java', F.parent/'loot_resolved/ResolvedCandidate.java'),
                           ('../loot_resolved/run.py', F.parent/'loot_resolved/run.py')]:
            source[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.receipt = dict(format=1, test_only=True, mode='control', sources=source,
            native_hashes=BUILD.load_guards(), runtime_hashes=BUILD.load_guards(),
            optimizer_manifest_sha256=None, optimizer_archive_sha256=None, optimizer_profile=None, headless_checks=['missing-token','already-loaded','initial-definition','preload'],
            success_path_checked=False, entry_point='lootResolvedRuntimeRun',
            terminal_marker='[LOOT_RESOLVED_RUNTIME] FINISH status=', required_preload=A.BOOT)
        self.cache = self.root / 'client1'
        self.mod(self.cache)

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text)

    def mod(self, cache, receipt=None, manifest=True):
        value = self.receipt if receipt is None else receipt
        layer = cache/'mods'/A.MOD
        self.write(layer/'42/mod.info', (F/'mod.info.template').read_text())
        self.write(layer/'42/media/lua/shared/ZZLootResolvedRuntime.lua', (F/'ZZLootResolvedRuntime.lua').read_text())
        for name in (A.BOOT, A.RUNTIME):
            path = layer/name; path.parent.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(path, 'w') as jar:
                jar.writestr('META-INF/loot-runtime-inputs.json', json.dumps(value))
                if name == A.BOOT:
                    jar.writestr('META-INF/MANIFEST.MF', 'Manifest-Version: 1.0\nZB-Preload: '+str(manifest).lower()+'\n\n')
                    jar.writestr('toolkit/lootresolved/bootstrap/token.txt', 'a'*32+'\n')
                    jar.writestr('toolkit/lootresolved/bootstrap/mode.txt', value['mode']+'\n')
        fonts = cache/'mods/PZToolkitJavaPatches/42'
        self.write(fonts/'mod.info', 'id=PZToolkitJavaPatches\njavaPkgName=net.alexredby.pztoolkitjavapatches\njavaJarFile=media/java/PZToolkitJavaPatches.jar\n')
        self.write(fonts/'media/java/PZToolkitJavaPatches.jar', 'ordinary runtime')
        path=fonts/'media/bootstrap/PZToolkitFonts.jar';path.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(path,'w') as jar: jar.writestr('META-INF/MANIFEST.MF','Manifest-Version: 1.0\nZB-Preload: true\n\n')

    def optimizer(self):
        # A synthetic pinned archive/manifest tests admission without a large external dependency.
        self.project = self.root / 'project'
        target = self.project / 'tests/chunk_integration/loot_resolved_runtime'
        shutil.copytree(F, target)
        source = target.parent / 'loot_resolved'; source.mkdir()
        for name in ('ResolvedCandidate.java', 'run.py'):
            shutil.copy2(F.parent / 'loot_resolved' / name, source / name)
        archive = self.root / 'official.zip'; archive.write_bytes(b'pinned-synthetic-optimizer')
        self.manifest = dict(release_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
            selected_files={'zombie/Lua/LuaEventManager.class':
                'd786c342e563fb735727beb268e39a9a40726c2e83a8ac15ec06c753580b524b'},
            profile={'id':'test-profile', 'properties':{'feature':'false'}})
        path = self.project / 'tests/optimizer_trial/candidate-manifest.json'
        self.write(path, json.dumps(self.manifest))
        self.selection['options'].update(optimizer_archive=str(archive), optimizer_prewarm=True)
        self.receipt['sources']['../../optimizer_trial/candidate-manifest.json'] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.receipt.update(runtime_hashes={**self.receipt['native_hashes'], **self.manifest['selected_files']},
            optimizer_manifest_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
            optimizer_archive_sha256=self.manifest['release_sha256'], optimizer_profile=self.manifest['profile'])
        self.mod(self.cache)
        return archive, path

    def event(self, kind, value): return A.MARKER+kind+' '+json.dumps(value)+'\n'

    def authority(self, source, role='client1'):
        return self.event('AUTHORITY', dict(role=role, case='bank', runtimeMode='control', status='complete',cases=8,source=source))

    def completed(self):
        return self.event('COMPLETE', dict(role='client1',case='bank',runtimeMode='control',status='complete',authority=True))

    def finish(self): return '[LOOT_RESOLVED_RUNTIME] FINISH status=complete cases=8 reason=\n'

    def apple_rows(self, hours=2.0, apo=1, rot=3):
        # Test data generation is separate from the parser; every receipt field remains mutable
        # for negative tests, including exact clock/options, raw age and bound item identity.
        bits=lambda x: format(struct.unpack('>I',struct.pack('>f',x))[0],'x')
        double=lambda x: format(struct.unpack('>Q',struct.pack('>d',x))[0],'x')
        rounded=lambda x: struct.unpack('>f',struct.pack('>f',x))[0]
        days=hours/24+(apo-1)*30;factor=rounded({1:1.7,2:1.4,3:1,4:.7,5:.4}[rot])
        age=bits(rounded(days)*factor)
        fields=dict(fulltype='Base.Apple',id='42',days_before=double(days),days_after=double(days),
                    hours_before=double(hours),hours_after=double(hours),time_since_apo_before=str(apo),
                    time_since_apo_after=str(apo),rot_option_before=str(rot),rot_option_after=str(rot),
                    rot_factor=bits(factor),expected_age=age,actual_age=age,is_fridge='false',is_freezer='false')
        return [f'ITEM\tdirect-real-items\tdirect/2:zombie.inventory.types.Food:Base.Apple:id=42:condition=10:age={age}:uses=1:initialized=true:heat=3f800000:frozen=false\n',
                'CLOCK\tdirect-real-items\tdirect/2:'+':'.join(k+'='+v for k,v in fields.items())+'\n']

    def bank(self, pid=100):
        h=self.receipt['native_hashes']['zombie/inventory/ItemPickerJava.class']
        manifest_sha=self.receipt['optimizer_manifest_sha256'] or 'none'
        for process in ({100,pid}):
            profile = ('native-host' if process != 100 else 'optimized-client') if self.selection['options'].get('optimizer_archive') else 'native'
            checked='true' if pid==100 or process==pid else 'false'
            self.write(self.cache/f'loot-resolved-runtime-activation-{process}.txt',
                f'state=active\nmode=control\npid={process}\ndefinitions=1\ninput={h}\noutput={h}\nresource_profile={profile}\noptimizer_manifest_sha256={manifest_sha}\nruntime_profile_checked={checked}\n'+''.join(k+'='+v+'\n' for k,v in COMPARE.RNG_ACTIVATION.items()))
        authority_profile=('native-host' if pid!=100 else 'optimized-client') if self.selection['options'].get('optimizer_archive') else 'native'
        self.write(self.cache/'loot-resolved-runtime-status.txt',f'resource_profile={authority_profile}\noptimizer_manifest_sha256={manifest_sha}\nruntime_profile_checked=true\nstatus=complete\nmode=control\npid={pid}\ncases=8\nreason=\nsource_square=uncovered\nlive_script_reload=uncovered\nmodule_item_replacement=uncovered\n')
        with (self.cache/'loot-resolved-runtime-status.txt').open('a') as stream:
            stream.write(f'rng_scope={COMPARE.RNG_SCOPE}\nrng_scope_complete=true\n')
        self.write(self.cache/f'loot-resolved-runtime-rng-{pid}.txt',
            f'rng_scope={COMPARE.RNG_SCOPE}\nrng_scope_complete=true\nreason=null\nowner_wrapper_selections=123\n'
            'owner_receiver_entries=246\nowner_bypass_rejections=0\nowner_unseeded_float_bool_rejections=0\n'
            'foreign_private_receiver_rejections=0\nshared_singleton_writes=0\nforeign_counts_scope=nonblocking-entry-snapshot\n'
            'foreign_wrapper_selections=0\nforeign_receiver_entries=0\nforeign_first_thread=none\n'
            'foreign_first_thread_id=0\nforeign_first_caller=none\nforeign_first_entry=none\n')
        rows=['kind\tcase\tdetail\n']
        for case in COMPARE.EXPECTED_CASES:
            rows.append(f'BEGIN\t{case}\tseed\n')
            if case in ('direct-real-items','bag-real-items'):rows.append(f'ITEM\t{case}\tBase.Nails:initialized=true\n')
            if case=='direct-real-items':rows.extend(self.apple_rows())
            if case=='native-nested-fill-reentrant':rows.append(f'FILL\t{case}\tactual callback\n')
            rows.extend([f'CLEANUP\t{case}\tdone\n',f'END\t{case}\trng=1\n'])
        self.write(self.cache/'loot-resolved-runtime.tsv',''.join(rows))

    def run_files(self, host=False):
        self.bank(200 if host else 100)
        if host:
            self.write(self.cache/A.HOST_AUTHORITY, 'a'*32+'\n')
        else:
            (self.cache/A.HOST_AUTHORITY).unlink(missing_ok=True)
        runtime=dict(project=str(self.project),roles={'client1':{'cache':str(self.cache)}})
        processes={'client1':{'pid':100}}
        if host:
            self.selection['kind']='mp';self.selection['options']['mp_host']=True
            runtime['host_cache']=str(self.cache)
            processes['server']=dict(pid=200,parent_role='client1',cache=str(self.cache))
            request=dict(role='client1',case='bank',runtimeMode='control',onlineID=3)
            self.write(self.root/'client1-launch.log',self.event('REQUEST',request)+self.authority('server-response')+self.completed())
            request['role']='server'
            self.write(self.root/'server-launch.log',self.event('REQUEST',request)+A.DIAGNOSTIC+'\n'+self.finish()+self.authority('server-main-tick','server'))
        else:self.write(self.root/'client1-launch.log',A.DIAGNOSTIC+'\n'+self.finish()+self.authority('sp-main-tick')+self.completed())
        self.write(self.root/'runtime.json',json.dumps(runtime));self.write(self.root/'execution.json',json.dumps({'processes':processes}))

    def test_strict_selection_and_optimizer_opt_in(self):
        A.validate(self.selection)
        for update in ({'clients':True},{'languages':['RU']},{'mode':'native'},{'resources':{}},{'kind':'mp'}):
            with self.subTest(update=update), self.assertRaises(ValueError):A.validate(dict(self.selection,**update))
        for key,value in [('preload_toolkit_fonts',False),('loot_runtime_mode','patched'),('world_template','/old')]:
            s=dict(self.selection, options=dict(self.selection['options'],**{key:value}))
            with self.subTest(key=key),self.assertRaises(ValueError):A.validate(s)
        archive=self.root/'official.zip';archive.write_bytes(b'fixture')
        s=dict(self.selection, options=dict(self.selection['options'],optimizer_archive=str(archive)))
        with self.assertRaises(ValueError):A.validate(s)
        s['options']['optimizer_prewarm']=True;A.validate(s)

    def test_one_composed_loader_parameter_and_ordinary_approvals(self):
        value=native.font_preload(self.cache,self.selection,project=ROOT)
        self.assertEqual(value.count(',patches_jar='),1)
        parts=value.removeprefix(',patches_jar=').split(';')
        self.assertEqual(len(parts),2)
        self.assertTrue(parts[0].endswith('PZToolkitFonts.jar:net.alexredby.pztoolkitbootstrap'))
        self.assertTrue(parts[1].endswith('PZLootResolvedBootstrap.jar:'+A.PACKAGE))
        approved=native._approvals(self.cache,['PZToolkitJavaPatches',A.MOD])
        self.assertEqual({x['jar_hash'] for x in approved},{native.sha256(self.cache/'mods/PZToolkitJavaPatches/42/media/java/PZToolkitJavaPatches.jar'),native.sha256(self.cache/'mods'/A.MOD/A.RUNTIME)})
        other=dict(self.selection,suite='startup')
        self.assertNotIn('PZLootResolvedBootstrap',native.font_preload(self.cache,other,project=ROOT))
        self.assertFalse((self.cache/A.TOKEN).exists())

    def test_foreign_sources_mode_and_manifest_cannot_arm(self):
        value=json.loads(json.dumps(self.receipt));value['sources']['Main.java']='0'*64;self.mod(self.cache,value)
        with self.assertRaisesRegex(ValueError,'Foreign/stale'):A.early_preload(self.cache,self.selection,project=ROOT)
        self.mod(self.cache,manifest=False)
        with self.assertRaisesRegex(ValueError,'manifest'):A.early_preload(self.cache,self.selection,project=ROOT)
        self.mod(self.cache)
        bad=dict(self.selection,options=dict(self.selection['options'],loot_runtime_mode='candidate'))
        with self.assertRaisesRegex(ValueError,'mode'):A.early_preload(self.cache,bad,project=ROOT)
        badcache=self.root/'bad;cache';self.mod(badcache)
        with self.assertRaisesRegex(ValueError,'separators'):A.early_preload(badcache,self.selection,project=ROOT)

    def test_optimizer_receipt_requires_exact_archive_manifest_and_effective_guards(self):
        archive, manifest = self.optimizer()
        self.assertEqual(A.bundle(self.cache, self.selection, self.project)[1], self.receipt)
        self.assertEqual(len(self.receipt['runtime_hashes']), len(self.receipt['native_hashes']))
        for field in ('native_hashes', 'runtime_hashes', 'optimizer_manifest_sha256',
                      'optimizer_archive_sha256', 'optimizer_profile'):
            broken = json.loads(json.dumps(self.receipt)); broken[field] = None
            self.mod(self.cache, broken)
            with self.subTest(field=field), self.assertRaises(ValueError):
                A.bundle(self.cache, self.selection, self.project)
        self.mod(self.cache)
        archive.write_bytes(b'foreign archive')
        with self.assertRaisesRegex(ValueError, 'reviewed release'):
            A.bundle(self.cache, self.selection, self.project)
        archive.write_bytes(b'pinned-synthetic-optimizer')
        manifest.write_text(manifest.read_text() + '\n')
        self.receipt['sources']['../../optimizer_trial/candidate-manifest.json'] = hashlib.sha256(manifest.read_bytes()).hexdigest()
        self.mod(self.cache)
        with self.assertRaisesRegex(ValueError, 'effective optimizer'):
            A.bundle(self.cache, self.selection, self.project)
        for overlap in ({'zombie/Lua/LuaEventManager.class':'0'*64},
                        {**self.manifest['selected_files'], 'zombie/inventory/ItemPickerJava.class':'0'*64}):
            altered = dict(self.manifest, selected_files=overlap)
            manifest.write_text(json.dumps(altered))
            self.receipt['optimizer_manifest_sha256'] = hashlib.sha256(manifest.read_bytes()).hexdigest()
            self.receipt['sources']['../../optimizer_trial/candidate-manifest.json'] = self.receipt['optimizer_manifest_sha256']
            self.receipt['runtime_hashes'] = {**self.receipt['native_hashes'], **overlap}
            self.mod(self.cache)
            with self.subTest(overlap=overlap), self.assertRaisesRegex(ValueError, 'overlap changed'):
                A.bundle(self.cache, self.selection, self.project)
        # An optimized fixture cannot arm when the archive option is absent.
        self.selection['options'].pop('optimizer_archive');self.selection['options'].pop('optimizer_prewarm')
        self.receipt['sources'].pop('../../optimizer_trial/candidate-manifest.json');self.mod(self.cache)
        with self.assertRaisesRegex(ValueError, 'effective optimizer'):
            A.bundle(self.cache, self.selection, self.project)

    def test_optimizer_manifest_source_fingerprint_is_required_and_current(self):
        self.optimizer()
        key='../../optimizer_trial/candidate-manifest.json'
        good=json.loads(json.dumps(self.receipt))
        for missing in (True,False):
            bad=json.loads(json.dumps(good))
            if missing:bad['sources'].pop(key)
            else:bad['sources'][key]='0'*64
            self.mod(self.cache,bad)
            with self.subTest(missing=missing),self.assertRaisesRegex(ValueError,'Foreign/stale'):
                A.bundle(self.cache,self.selection,self.project)
        self.mod(self.cache,good)
        self.assertEqual(A.bundle(self.cache,self.selection,self.project)[1]['sources'][key],good['optimizer_manifest_sha256'])

    def test_native_receipt_requires_explicit_unmodified_runtime_map_and_null_optimizer(self):
        A.bundle(self.cache, self.selection)
        for field, value in [('runtime_hashes', {}), ('optimizer_manifest_sha256', '0'*64),
                             ('optimizer_archive_sha256', '0'*64), ('optimizer_profile', {})]:
            broken = dict(self.receipt, **{field:value}); self.mod(self.cache, broken)
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'effective optimizer'):
                A.bundle(self.cache, self.selection)
        broken = dict(self.receipt);broken.pop('optimizer_manifest_sha256');self.mod(self.cache, broken)
        with self.assertRaisesRegex(ValueError, 'effective optimizer'):
            A.bundle(self.cache, self.selection)

    def test_token_stage_requires_actual_lua_owner_and_preserves_default_population_seed(self):
        runtime=dict(roles={'client1':{'cache':str(self.cache)}},fixture={'mods':[]})
        self.write(self.cache/'smoke-user.txt','client1\n')
        with self.assertRaisesRegex(ValueError,'actual owned'):A.stage(ROOT,self.root,self.root/'game',self.root/'jdk',self.selection,{},runtime)
        self.assertFalse((self.cache/A.TOKEN).exists())
        self.write(self.cache/'Lua/smoke-user.txt','foreign\n')
        with self.assertRaises(ValueError):A.stage(ROOT,self.root,self.root/'game',self.root/'jdk',self.selection,{},runtime)
        self.write(self.cache/'Lua/smoke-user.txt','client1\n')
        with patch.object(A.optimizer_profile,'stage') as optimizer:A.stage(ROOT,self.root,self.root/'game',self.root/'jdk',self.selection,{},runtime)
        optimizer.assert_called_once()
        self.assertEqual((self.cache/A.TOKEN).read_text(),'a'*32+'\n')
        self.assertFalse((self.cache/A.HOST_AUTHORITY).exists())
        starter=(self.cache/'mods/ActionQueueTest/42/media/lua/client/ZZStartup.lua').read_text()
        self.assertIn('HOST_REQUEST',starter);self.assertIn(A.SEED,starter)
        self.assertIn("getWorld():setWorld('" + A.WORLD + "')",starter)
        self.assertNotIn("getWorld():setWorld('QueueStartup')",starter)
        self.assertRegex(A.WORLD, r'^PZDrivingBench-OptimizerTrial-[A-Za-z0-9-]+$')
        self.assertIn("getOptionByName('Zombies'):setValue(3)",starter)
        self.assertNotIn("getOptionByName('Zombies'):setValue(6)",starter)
        self.assertEqual(runtime['fixture']['sandbox'],A.SANDBOX)
        with self.assertRaisesRegex(ValueError,'fresh'):A.stage(ROOT,self.root,self.root/'game',self.root/'jdk',self.selection,{},runtime)

    def test_host_authority_stage_requires_fresh_owned_caches_and_never_arms_sp(self):
        runtime=dict(roles={'client1':{'cache':str(self.cache)}},fixture={'mods':[]})
        self.write(self.cache/'Lua/smoke-user.txt','client1\n')
        self.write(self.cache/A.HOST_AUTHORITY,'foreign\n')
        with self.assertRaisesRegex(ValueError,'fresh'):
            A.stage(ROOT,self.root,self.root/'game',self.root/'jdk',self.selection,{},runtime)
        self.assertFalse((self.cache/A.TOKEN).exists())
        (self.cache/A.HOST_AUTHORITY).unlink()
        self.selection['kind']='mp';self.selection['options']['mp_host']=True
        server=self.root/'server';self.mod(server)
        self.write(server/'Lua/smoke-user.txt','foreign\n')
        self.write(server/'Server/queue-smoke.ini','SpawnPoint=0,0,0\n')
        runtime['roles']['server']={'cache':str(server)}
        with self.assertRaisesRegex(ValueError,'actual owned'):
            A.stage(ROOT,self.root,self.root/'game',self.root/'jdk',self.selection,{},runtime)
        self.assertFalse((self.cache/A.TOKEN).exists());self.assertFalse((self.cache/A.HOST_AUTHORITY).exists())
        self.write(server/'Lua/smoke-user.txt','server\n')
        (server/A.HOST_AUTHORITY).symlink_to(server/'absent')
        with self.assertRaisesRegex(ValueError,'fresh'):
            A.stage(ROOT,self.root,self.root/'game',self.root/'jdk',self.selection,{},runtime)
        self.assertFalse((self.cache/A.TOKEN).exists());self.assertFalse((self.cache/A.HOST_AUTHORITY).exists())
        (server/A.HOST_AUTHORITY).unlink()
        with patch.object(A.optimizer_profile,'stage'):
            A.stage(ROOT,self.root,self.root/'game',self.root/'jdk',self.selection,{},runtime)
        for cache in (self.cache,server):
            self.assertEqual((cache/A.HOST_AUTHORITY).read_text(),(cache/A.TOKEN).read_text())

    def test_activation_resource_profiles_are_bound_to_owned_process_roles(self):
        self.optimizer()
        for host in (False, True):
            self.run_files(host)
            profile='multiplayer client=true' if host else 'singleplayer client=false'
            log=self.root/'client1-launch.log'
            log.write_text('[OptimizerTrial] bridge ready mode='+profile+' server=false session=1\n'+log.read_text())
            if host:
                log=self.root/'server-launch.log'
                log.write_text('[OptimizerTrialProbe] native server resources=1 overlayAbsent=true\n'+log.read_text())
            self.assertEqual(A.verify(self.root,self.selection,{})['issues'],[])
            for pid,wrong in [(100,'native-host')] + ([(200,'optimized-client')] if host else []):
                path=self.cache/f'loot-resolved-runtime-activation-{pid}.txt';text=path.read_text()
                path.write_text(text.replace('resource_profile='+('optimized-client' if pid==100 else 'native-host'), 'resource_profile='+wrong))
                with self.subTest(host=host,pid=pid):
                    self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
                path.write_text(text)
            status=self.cache/'loot-resolved-runtime-status.txt';text=status.read_text()
            for key,wrong in [('resource_profile','foreign'),('optimizer_manifest_sha256','none'),('runtime_profile_checked','false')]:
                status.write_text('\n'.join(key+'='+wrong if line.startswith(key+'=') else line for line in text.split('\n')))
                with self.subTest(host=host,status_key=key):
                    self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
                status.write_text(text)
            marker=self.cache/A.HOST_AUTHORITY
            if host:
                marker.write_text('wrong-token\n')
                self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
                marker.unlink()
                self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
            else:
                marker.write_text('a'*32+'\n')
                self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
            self.selection['kind']='sp';self.selection['options'].pop('mp_host',None)

    def test_startup_loaded_and_completion_alone_never_finish_suite(self):
        self.assertFalse(A.complete(self.selection,'client1','[STARTUP_TEST] COMPLETE case=loaded\n'))
        self.assertFalse(A.complete(self.selection,'client1',self.completed()))
        self.assertFalse(A.complete(self.selection,'client1',self.authority('sp-main-tick')+self.completed()))
        good=self.finish()+self.authority('sp-main-tick')+self.completed()
        self.assertTrue(A.complete(self.selection,'client1',good))
        self.assertFalse(A.complete(self.selection,'client1',good+self.completed()))
        self.assertFalse(A.complete(self.selection,'client1',good.replace('status=complete cases=8','status=failed cases=8')))

    def test_capture_requires_real_bank_receipts_and_matching_execution_pids(self):
        for host in (False,True):
            with self.subTest(host=host):
                self.run_files(host)
                result=A.verify(self.root,self.selection,{})
                self.assertEqual(result['issues'],[]);self.assertEqual(result['outcomes'][0]['status'],'captured')
                path=self.cache/'loot-resolved-runtime-status.txt';old=path.read_text()
                path.write_text(old.replace('pid=200' if host else 'pid=100','pid=999'))
                self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
                path.write_text(old);path.unlink()
                self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
                self.selection['kind']='sp';self.selection['options'].pop('mp_host',None)

    def test_rng_scope_must_close_without_poison_and_all_definitions(self):
        self.run_files()
        self.assertEqual(A.verify(self.root,self.selection,{})['issues'],[])
        mutations={
            'loot-resolved-runtime-status.txt': [('rng_scope_complete=true','rng_scope_complete=false')],
            'loot-resolved-runtime-activation-100.txt': [(key+'=1',key+'=0') for key in
                ('rng_abstract_definitions','rng_standard_definitions','rng_interface_definitions')],
            'loot-resolved-runtime-rng-100.txt': [('owner_bypass_rejections=0','owner_bypass_rejections=1'),
                ('owner_unseeded_float_bool_rejections=0','owner_unseeded_float_bool_rejections=1'),
                ('foreign_private_receiver_rejections=0','foreign_private_receiver_rejections=1'),
                ('reason=null','reason=swallowed-error'),('owner_wrapper_selections=123','owner_wrapper_selections=0'),
                ('foreign_wrapper_selections=0','foreign_wrapper_selections=1')],
        }
        for filename, pairs in mutations.items():
            path=self.cache/filename;original=path.read_text()
            for old,new in pairs:
                with self.subTest(filename=filename,new=new):
                    path.write_text(original.replace(old,new))
                    self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
            path.write_text(original)
        path=self.cache/'loot-resolved-runtime-rng-100.txt';original=path.read_text()
        for old,new in [('foreign_wrapper_selections=0','foreign_wrapper_selections=1'),
                        ('foreign_first_thread=none','foreign_first_thread=background'),
                        ('foreign_first_thread_id=0','foreign_first_thread_id=456'),
                        ('foreign_first_caller=none','foreign_first_caller=Native.call'),
                        ('foreign_first_entry=none','foreign_first_entry=Rand.INSTANCE')]:
            original=original.replace(old,new)
        path.write_text(original)
        self.assertEqual(A.verify(self.root,self.selection,{})['issues'],[])
        path.unlink()
        self.assertTrue(A.verify(self.root,self.selection,{})['issues'])

    def test_food_age_compares_exact_native_clock_formula_with_raw_evidence(self):
        a=['kind\tcase\tdetail\n',*self.apple_rows(2.0)]
        b=['kind\tcase\tdetail\n',*self.apple_rows(4.0)]
        self.assertNotEqual(a,b)
        na,pa=COMPARE.clock_rows(a);nb,pb=COMPARE.clock_rows(b)
        self.assertEqual(na,nb)
        self.assertNotEqual(pa[0]['actual_age'],pb[0]['actual_age'])
        # A different stable sandbox setting remains semantically different, even with valid aging.
        nc,_=COMPARE.clock_rows(['kind\tcase\tdetail\n',*self.apple_rows(2.0,2,4)])
        self.assertNotEqual(na,nc)
        b[1]=b[1].replace('condition=10','condition=9')
        self.assertNotEqual(na,COMPARE.clock_rows(b)[0])

    def test_food_clock_rejects_changed_inputs_wrong_formula_and_missing_binding(self):
        original=['kind\tcase\tdetail\n',*self.apple_rows(2.0)]
        bad=[]
        for old,new in [('days_after=3fb5555555555555','days_after=3fc5555555555555'),
                        ('hours_before=4000000000000000','hours_before=4010000000000000'),
                        ('rot_option_after=3','rot_option_after=4'),
                        ('rot_factor=3f800000','rot_factor=3f333333'),
                        ('expected_age=3daaaaab','expected_age=3daaaaaa'),
                        ('actual_age=3daaaaab','actual_age=3daaaaaa'),
                        ('id=42','id=43'),('is_fridge=false','is_fridge=true'),
                        ('days_before=3fb5555555555555','days_before=7ff8000000000000')]:
            rows=list(original);self.assertIn(old,rows[2]);rows[2]=rows[2].replace(old,new);bad.append(rows)
        bad.extend([original[:2],original+[original[2]],original+[original[1]]])
        for rows in bad:
            with self.subTest(rows=rows), self.assertRaises(ValueError):COMPARE.clock_rows(rows)
        rows=list(original);rows[1]=rows[1].replace(':age=3daaaaab:',':age=3daaaaaa:')
        with self.assertRaises(ValueError):COMPARE.clock_rows(rows)
        self.run_files()
        path=self.cache/'loot-resolved-runtime.tsv';path.write_text(path.read_text().replace('CLOCK\t','UNPROVEN\t'))
        self.assertTrue(A.verify(self.root,self.selection,{})['issues'])

    def test_failed_activation_and_diagnostic_duplicates_remain_visible(self):
        self.run_files()
        activation=self.cache/'loot-resolved-runtime-activation-100.txt';old=activation.read_text()
        activation.write_text(old.replace('state=active','state=disabled'))
        self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
        activation.write_text(old)
        log=self.root/'client1-launch.log';log.write_text(log.read_text()+A.DIAGNOSTIC+'\n')
        self.assertTrue(A.verify(self.root,self.selection,{})['issues'])

    def test_optimizer_ready_marker_matches_actual_sp_and_host_contract(self):
        self.optimizer()
        for host in (False,True):
            self.run_files(host)
            path=self.root/'client1-launch.log';original=path.read_text()
            path.write_text('[OptimizerTrial] bridge ready mode=Optimized\n'+original)
            self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
            profile='multiplayer client=true' if host else 'singleplayer client=false'
            path.write_text('[OptimizerTrial] bridge ready mode='+profile+' server=false session=1\n'+original)
            if host:
                path=self.root/'server-launch.log';path.write_text('[OptimizerTrialProbe] native server resources=1 overlayAbsent=true\n'+path.read_text())
            self.assertEqual(A.verify(self.root,self.selection,{})['issues'],[])
            self.selection['kind']='sp';self.selection['options'].pop('mp_host',None)

    def test_host_completion_without_server_request_or_response_is_rejected(self):
        self.run_files(True)
        log=self.root/'server-launch.log';text=log.read_text()
        log.write_text(text.replace(A.MARKER+'REQUEST ', '[IGNORED] REQUEST '))
        self.assertTrue(A.verify(self.root,self.selection,{})['issues'])
        log.write_text(text.replace('"onlineID": 3','"onlineID": 4'))
        self.assertTrue(A.verify(self.root,self.selection,{})['issues'])


@unittest.skipUnless(LUAJIT, 'LuaJIT is unavailable')
class LootLuaHandshake(unittest.TestCase):
    def run_lua(self, body):
        harness = r"""
local root=arg[1]
local JSON=assert(loadfile(root..'/tests/native_queue/health/shared/QueueHealthEvents.lua'))()
local function state(host,server)
 local e=setmetatable({outputs={},handlers={},sent={},bankRuns=0,bankStatus='not-run'},{__index=_G})
 e.selection={suite='loot-resolved',kind=host and 'mp' or 'sp',options={loot_runtime_mode='control'}}
 e.Events=setmetatable({}, {__index=function(t,k)local v={Add=function(f)e.handlers[k]=e.handlers[k]or{};table.insert(e.handlers[k],f)end};rawset(t,k,v);return v end})
 e.fire=function(name,...)for _,f in ipairs(e.handlers[name]or{})do f(...)end end
 e.print=function(v)table.insert(e.outputs,v)end
 e.require=function(n)return n=='QueueTestSelection'and e.selection or JSON end
 e.isClient=function()return host and not server end;e.isServer=function()return server end
 e.isIngameState=function()return true end;e.getTimestampMs=function()return 1000 end
 e.player={isDead=function()return false end,getSquare=function()return{}end,getOnlineID=function()return 3 end,getUsername=function()return 'client1'end}
 e.getPlayer=function()return e.player end
 e.getFileReader=function()return{readLine=function()return 'client1'end,close=function()end}end
 e.lootResolvedRuntimeStatus=function()return e.bankStatus end
 e.lootResolvedRuntimeRun=function()e.bankRuns=e.bankRuns+1;e.bankStatus='complete';e.print('[LOOT_RESOLVED_RUNTIME] FINISH status=complete cases=8 reason=');return true end
 e.sendClientCommand=function(m,c,a)e.sent={module=m,command=c,args=a}end
 e.sendServerCommand=function(p,m,c,a)e.sent={module=m,command=c,args=a}end
 local side=server and 'server/ZZLootResolvedServer.lua'or'client/ZZLootResolved.lua'
 local code=assert(loadfile(root..'/tests/native_queue/loot-resolved/'..side));setfenv(code,e);code()
 return e
end
local function log(e)return table.concat(e.outputs,'\n')end
"""
        result=subprocess.run([LUAJIT,'-',str(ROOT)],input=harness+body+"\nprint('LOOT_HANDSHAKE_PASS')\n",
                              text=True,capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('LOOT_HANDSHAKE_PASS',result.stdout)

    def test_sp_waits_for_valid_game_tick_and_runs_once(self):
        self.run_lua("""
local e=state(false,false);e.fire('OnTick');assert(e.bankRuns==0)
e.fire('OnGameStart');e.fire('OnTick');e.fire('OnTick');assert(e.bankRuns==1)
assert(log(e):find('AUTHORITY',1,true)<log(e):find('COMPLETE',1,true))
""")

    def test_host_requires_request_server_tick_and_response_before_complete(self):
        self.run_lua("""
local c,s=state(true,false),state(true,true)
c.fire('OnGameStart');c.fire('OnTick');assert(c.bankRuns==0 and c.sent.command=='RunBank')
assert(not log(c):find('COMPLETE',1,true))
s.fire('OnClientCommand',c.sent.module,c.sent.command,s.player,c.sent.args);assert(s.bankRuns==0)
s.fire('OnTick');assert(s.bankRuns==1 and s.sent.command=='BankStatus')
c.fire('OnServerCommand',s.sent.module,s.sent.command,s.sent.args)
assert(c.bankRuns==0 and log(c):find('COMPLETE',1,true))
c.fire('OnServerCommand',s.sent.module,s.sent.command,s.sent.args);assert(log(c):find('FAIL',1,true))
""")

    def test_foreign_actor_or_missing_api_never_completes(self):
        self.run_lua("""
local s=state(true,true);s.player.getUsername=function()return 'client2'end
s.fire('OnClientCommand','LootResolvedNativeTest','RunBank',s.player,{role='client1',case='bank',runtimeMode='control'})
s.fire('OnTick');assert(s.bankRuns==0 and log(s):find('FAIL',1,true))
local c=state(false,false);c.lootResolvedRuntimeRun=false;c.fire('OnGameStart');c.fire('OnTick')
assert(log(c):find('FAIL',1,true)and not log(c):find('COMPLETE',1,true))
""")


if __name__=='__main__':unittest.main()
