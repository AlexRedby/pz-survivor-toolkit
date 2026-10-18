"""Parser/staging tests use synthetic logs; they never claim native game coverage."""
import json
import os
from pathlib import Path
import shutil
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from queue_checks import adapters
from queue_checks.adapters import craft_wishlist as adapter


def selection(suite, case):
    mods = adapter.definitions()[suite]["default_mods"]
    return {"suite": suite, "cases": [case], "kind": "mp", "mode": "toolkit", "mods": mods,
            "ports": [18061, 18062], "languages": ["EN", "RU"]}


def client_log(value, role):
    suite, case = value["suite"], value["cases"][0]
    prefix = "[" + adapter.marker(value) + "] "
    names = json.loads((ROOT / "tests/native_queue/contributions" / suite / "stage-names.json").read_text())[case]
    lines = [prefix + "CONNECTED " + role + " language=" + ("EN" if role == "client1" else "RU")]
    if suite == "crafting-plans":
        lines.append(prefix + "EXPECTED checks=" + str(len(names)) + " scenario=" + case)
    if case == "ui":
        lines += [prefix + marker + " " + role for marker in ("PREVIEW_RENDERED", "FALLBACK_RENDERED", "WINDOW_GUARDS", "START_CALLBACK")]
        lines += [prefix + "SCROLLBAR_BOUNDS " + role + " label=" + label for label in ("constrained", "scrolled", "short", "wide")]
    lines += [prefix + "PASS " + name + " nil" for name in names]
    lines.append(prefix + "COMPLETE checks=" + str(len(names)) + " failures=0")
    return "\n".join(lines) + "\n"


def server_log(value):
    suite, case = value["suite"], value["cases"][0]
    lines = [adapter.server_ready(value)]
    if suite == "crafting-plans" and case == "crafting":
        lines += ["[CRAFT_TEST] SERVER_" + phase + "_VERIFY " + role + " ok=true error=nil"
                  for phase in ("CANCEL", "CHAIN") for role in ("client1", "client2")]
        lines.append("[CRAFT_TEST] SERVER_RACE_VERIFY ok=true completed=1 error=nil")
    elif suite == "crafting-plans" and case == "alternatives":
        lines += ["[CRAFT_TEST] SERVER_ALTERNATIVES_VERIFY " + role + " phase=" + phase + " ok=true error=nil"
                  for role in ("client1", "client2") for phase in ("chain", "repeat", "logs")]
    elif suite == "shared-wishlist" and case in ("full", "standalone"):
        lines += ["[WISHLIST_TEST] SERVER_VERIFY " + role + " ok=true" for role in ("client1", "client2")]
    if suite == "shared-wishlist" and case == "reload":
        lines[0:0] = ["[WISHLIST_TEST] RESTORE slot=a chars=12", "[WISHLIST_TEST] RESTORE_COMPLETE slots=1"]
    return "\n".join(lines) + "\n"


def session_log(value, role):
    cases = adapter.ordered_cases(value)
    blocks = [adapter.server_ready(value)] if role == "server" else []
    for epoch, case in enumerate(cases, 1):
        receipt = "case=" + case + " epoch=" + str(epoch) + " actor="
        event = lambda name, actor, suffix="": "[QUEUE_SESSION] " + name + " " + receipt + actor + suffix
        one = dict(value, cases=[case])
        blocks.append(event("BEGIN", role))
        if role == "server":
            blocks.extend(event("PREPARE", actor) for actor in ("client1", "client2"))
            blocks += [event("START", role), server_log(one).replace(adapter.server_ready(value), "")]
            blocks.extend(event("FINISH", actor, " ok=true") for actor in ("client1", "client2"))
            blocks.append(event("CLEANUP", role, " ok=true"))
            blocks.extend(event("CLEANUP", actor, " ok=true") for actor in ("client1", "client2"))
        else:
            blocks += [event("PREPARE", role), event("START", role), client_log(one, role),
                       event("FINISH", role, " ok=true"), event("LOCAL_CLEAN", role, " ok=true"),
                       event("CLEANUP", role, " ok=true")]
        blocks.append(event("JOINT_CLEAN", role, " ok=true"))
    blocks.append("[QUEUE_SESSION] COMPLETE case=" + cases[-1] + " epoch=" + str(len(cases)) + " actor=" + role + " cases=" + str(len(cases)))
    return "\n".join(blocks)


class CraftWishlistAdapterTests(unittest.TestCase):
    def test_every_preserved_scenario_and_exact_stage_guards(self):
        catalog = {"suites": adapter.definitions()}
        for suite, counts in adapter.COUNTS.items():
            for case, expected in counts.items():
                value = selection(suite, case)
                with self.subTest(suite=suite, case=case), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    for role in ("client1", "client2"):
                        text = client_log(value, role)
                        (root / (role + "-launch.log")).write_text(text)
                        self.assertTrue(adapter.complete(value, role, text))
                        self.assertEqual([], adapter._client_issues(text, value, role, case))
                        for broken in (text.replace("PASS ", "PASS unknown ", 1),
                                       text + "[" + adapter.marker(value) + "] COMPLETE checks=" + str(expected) + " failures=0\n",
                                       text.replace("language=EN" if role == "client1" else "language=RU", "language=wrong")):
                            self.assertTrue(adapter._client_issues(broken, value, role, case))
                        lines = text.splitlines()
                        first = next(i for i, line in enumerate(lines) if "] PASS " in line)
                        lines[first], lines[first + 1] = lines[first + 1], lines[first]
                        self.assertTrue(adapter._client_issues("\n".join(lines), value, role, case))
                    (root / "server-launch.log").write_text(server_log(value))
                    if case == "reload":
                        (root / "report.json").write_text(json.dumps({"status": "passed", "runtime": {"status": "clean"}}))
                        with patch.object(adapter, "_seed", return_value=(root, [])):
                            result = adapter.verify(root, value, catalog)
                    else:
                        result = adapter.verify(root, value, catalog)
                    self.assertEqual([], result["issues"])
                    self.assertEqual([expected, expected], [row["outcome"]["preserved_stages"] for row in result["outcomes"]])


    def test_grouped_crafting_stages_only_selected_factories_and_one_bootstrap(self):
        value = dict(selection("crafting-plans", "ui"), cases=["alternatives", "ui", "crafting"])
        adapter.validate(value)
        self.assertEqual(["ui", "crafting", "alternatives"], adapter.ordered_cases(value))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime = {"roles": {role: {} for role in ("server", "client1", "client2")}}
            adapter.stage(ROOT, root, None, None, value, {}, runtime)
            helper = "mods/CraftPlanTest/42/media/lua"
            paths = [root / "client1" / helper / "client/ZZCraftFixture.lua",
                     root / "server" / helper / "server/ZZCraftFixture.lua"]
            lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
            code = r'''local paths={arg[1],arg[2]}
for _,path in ipairs(paths) do
 assert(loadfile(path))
 local hooks={};Events=setmetatable({},{__index=function(t,k)
  local e={Add=function(fn) hooks[k]=hooks[k] or {};table.insert(hooks[k],fn) end};t[k]=e;return e
 end})
 require=function()end
 ISHandcraftAction={performRecipe=function()end}
 local lines={'client1','ui,crafting,alternatives','host','12345','password'}
 getFileReader=function() local i=0;return {readLine=function()i=i+1;return lines[i]end,close=function()end}end
 dofile(path)
 assert(#hooks.OnTick==1)
 if path:find('/client/',1,true)then
  assert(#hooks.OnGameStart==1 and #hooks.OnMainMenuEnter==1 and #hooks.OnServerCommand==1)
 else assert(#hooks.OnServerStarted==1 and #hooks.OnClientCommand==1)end
end
print('PASS staged selected factories and single event dispatchers')
'''
            result = subprocess.run([lua, "-", *map(str, paths)], input=code, text=True, capture_output=True)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            text = paths[0].read_text()
            self.assertEqual(3, text.count("']=function(QueueCraftSession)"))
            self.assertEqual(["client1", "ui,crafting,alternatives"], (root / "client1/Lua/craft-fixture.txt").read_text().splitlines()[:2])
            self.assertIn(ROOT / "tests/native_queue/support/QueueFixtureSession.lua", adapter.sources(ROOT, value))

    def test_real_lua_session_joint_cleanup_stale_duplicate_and_reset_failure(self):
        lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
        code = r'''local create=dofile(arg[1]);local now=0
getTimestampMs=function()return now end
local messages={};sendServerCommand=function(player,module,command,args)messages[#messages+1]={player,module,command,args}end
local players={client1={getUsername=function()return 'client1'end},client2={getUsername=function()return 'client2'end}}
local cleanupCount,ran,failReset=0,{},false
local factories={}
for _,case in ipairs({'ui','crafting','alternatives'})do
 factories[case]=function(ctx)
  ran[#ran+1]=ctx.case
  ctx.cleanup=function()cleanupCount=cleanupCount+1;assert(not failReset,'reset failed');return true end
  ctx.events.OnClientCommand.Add(function()ran[#ran+1]='command'end)
 end
end
local function session()
 local s=create({user='server',cases={'ui','crafting','alternatives'}},factories,true);s.prepare();return s
end
local function args(s,actor) return {fixtureCase=s.cases[s.index],fixtureEpoch=s.epoch,fixtureActor=actor,ok=true}end
local function both(s,command)
 for _,actor in ipairs({'client1','client2'})do s.receive(command,players[actor],args(s,actor))end
end
local s=session();both(s,'Prepare');assert(s.phase=='running')
local stale=args(s,'client1');both(s,'Finish');assert(s.phase=='clean'and cleanupCount==1)
s.receive('Cleaned',players.client1,args(s,'client1'));assert(s.index==1)
s.receive('Cleaned',players.client2,args(s,'client2'));assert(s.index==2 and s.phase=='prepare')
s.receive('Finish',players.client1,stale);assert(s.phase=='prepare'and s.index==2)
both(s,'Prepare');both(s,'Finish');both(s,'Cleaned');assert(s.index==3)
both(s,'Prepare');both(s,'Finish');both(s,'Cleaned');assert(s.phase=='done'and cleanupCount==3)
s=session();s.receive('Prepare',players.client1,args(s,'client1'));s.receive('Prepare',players.client1,args(s,'client1'));assert(s.phase=='quarantined'and s.index==1)
s=session();both(s,'Prepare');failReset=true;both(s,'Finish');assert(s.phase=='quarantined'and s.index==1);failReset=false
s=session();both(s,'Prepare');s.current().cleanup=function()return false,'reset refused'end;both(s,'Finish');assert(s.phase=='quarantined'and s.index==1)
s=session();both(s,'Prepare');s.quarantine('timeout');both(s,'Finish');assert(s.index==1 and s.phase=='quarantined')
s=session();now=720001;s.tick();assert(s.phase=='quarantined')
print('PASS lifecycle barriers, stale receipts, duplicates, reset failure and quarantine')
'''
        result = subprocess.run([lua, "-", str(ROOT / "tests/native_queue/support/QueueFixtureSession.lua")],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_grouped_verifier_preserves_each_case_stages_and_joint_clean_receipts(self):
        value = dict(selection("crafting-plans", "ui"), cases=["ui", "crafting", "alternatives"])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for role in ("server", "client1", "client2"):
                (root / (role + "-launch.log")).write_text(session_log(value, role))
            result = adapter.verify(root, value, {"suites": adapter.definitions()})
            self.assertEqual([], result["issues"])
            self.assertEqual(6, len(result["outcomes"]))
            self.assertEqual(71, result["evidence"]["preserved_stages_per_client"])
            self.assertTrue(adapter.complete(value, "client1", (root / "client1-launch.log").read_text()))
            path = root / "server-launch.log"
            original = path.read_text()
            receipt = "[QUEUE_SESSION] JOINT_CLEAN case=ui epoch=1 actor=server ok=true"
            for broken in (original.replace(receipt, ""), original + "\n" + receipt, original.replace("epoch=1", "epoch=2")):
                path.write_text(broken)
                self.assertTrue(adapter.verify(root, value, {"suites": adapter.definitions()})["issues"])

            path.write_text(original)
            client = root / "client1-launch.log"
            clean = client.read_text()
            start = "[QUEUE_SESSION] START case=ui epoch=1 actor=client1"
            end = "[QUEUE_SESSION] JOINT_CLEAN case=ui epoch=1 actor=client1 ok=true"
            client.write_text(clean.replace(start, "PLACEHOLDER").replace(end, start).replace("PLACEHOLDER", end))
            self.assertTrue(adapter.verify(root, value, {"suites": adapter.definitions()})["issues"])
            client.write_text(clean.replace("COMPLETE checks=28 failures=0", "COMPLETE checks=27 failures=1").replace(
                "FINISH case=ui epoch=1 actor=client1 ok=true", "FINISH case=ui epoch=1 actor=client1 ok=false"))
            outcomes = adapter.verify(root, value, {"suites": adapter.definitions()})["outcomes"]
            self.assertEqual("failed", outcomes[0]["status"])
            self.assertTrue(all(row["status"] == "passed" for row in outcomes if row["case"] != "ui"), "proved cleanup permits independent following cases")
            client.write_text(clean)
            partial = clean[:clean.index("[QUEUE_SESSION] BEGIN case=crafting")]
            client.write_text(partial + "[QUEUE_SESSION] QUARANTINE case=crafting epoch=2 actor=client1 reason=prepare\n")
            outcomes = adapter.verify(root, value, {"suites": adapter.definitions()})["outcomes"]
            self.assertEqual("passed", outcomes[0]["status"], "next prepare quarantine must preserve an already joint-clean case")
            self.assertEqual("failed", outcomes[2]["status"])


    def test_real_lua_prepare_waits_for_native_tick_and_online_player_once_per_case(self):
        lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
        code = r'''local create=dofile(arg[1]);local now,online,inTick=0,-1,false
local sent,dropped,instantiated={},0,0
getTimestampMs=function()return now end
local player={getOnlineID=function()return online end}
getPlayer=function()return player end
sendClientCommand=function(module,command,args)
 if not inTick then dropped=dropped+1;return end
 sent[#sent+1]={command=command,case=args.fixtureCase,epoch=args.fixtureEpoch}
end
local factories={}
for _,case in ipairs({'ui','crafting'})do factories[case]=function(ctx)
 instantiated=instantiated+1;ctx.cleanup=function()return true end;ctx.clean=function()return true end
end end
local s=create({user='client1',cases={'ui','crafting'}},factories,false)
s.prepare();assert(instantiated==1 and #sent==0 and dropped==0,'OnGameStart must only instantiate')
inTick=true;s.tick();assert(#sent==0,'offline player must wait')
player=nil;s.tick();assert(#sent==0,'missing player must wait')
player={getOnlineID=function()return online end};online=4;s.tick()
assert(#sent==1 and sent[1].command=='Prepare' and sent[1].case=='ui'and sent[1].epoch==1)
for i=1,20 do s.tick()end;assert(#sent==1 and instantiated==1,'actual Prepare must never retry')
local first={fixtureCase='ui',fixtureEpoch=1,fixtureActor='client1'}
s.receive('Start',nil,first);s.current().finish(true,false);s.receive('Clean',nil,first);s.tick();s.receive('JointClean',nil,first)
inTick=false;s.command('QueueFixtureSession','Next',nil,{fixtureCase='crafting',fixtureEpoch=2,fixtureActor='client1'})
assert(instantiated==2 and #sent==3 and dropped==0,'Next must also defer transport')
inTick=true;s.tick();assert(#sent==4 and sent[4].command=='Prepare'and sent[4].case=='crafting'and sent[4].epoch==2)
for i=1,20 do s.tick()end;assert(#sent==4 and dropped==0)
getPlayer=function()error('server must never use client readiness')end
sendClientCommand=function()error('server must never use client transport')end
local server=create({user='server',cases={'ui'}},factories,true);server.prepare();server.tick()
assert(server.phase=='prepare')
print('PASS deferred initial/next Prepare, missing/offline player, no resend and server role isolation')
'''
        result = subprocess.run([lua, "-", str(ROOT / "tests/native_queue/support/QueueFixtureSession.lua")],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_grouped_outcomes_pass_common_functional_gate_in_actor_then_selection_order(self):
        for suite, cases in (("crafting-plans", ["alternatives", "ui", "crafting"]),
                             ("shared-wishlist", ["standalone", "visual"])):
            with self.subTest(suite=suite), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                value = dict(selection(suite, cases[0]), cases=cases)
                for role in ("server", "client1", "client2"):
                    readiness = "" if role == "server" else "".join("[QUEUE_TEST] " + marker + "\n" for marker in (
                        "VOICE_DISABLED", "DISPLAY_READY", "PREFLIGHT_COMPLETE", "NATIVE_CONNECTED"))
                    (root / (role + "-launch.log")).write_text(readiness + session_log(value, role))
                functional, coverage = adapters.functional(root, value, {"suites": adapter.definitions()})
                self.assertEqual("passed", functional["status"], functional["issues"])
                self.assertEqual([(role, case) for role in ("client1", "client2") for case in cases],
                                 [(row["actor"], row["case"]) for row in coverage])

    def test_real_lua_owned_surface_removal_targets_single_native_object_and_confirms_absence(self):
        lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
        code = r'''local configure=dofile(arg[1]);local session={};configure(session,true)
local ctx={};session.configure(ctx)
local owned,neighbor={},{};local present={[owned]=true,[neighbor]=true}
local network,ignoreRemoval={},false
local square={getX=function()return 1 end,getY=function()return 2 end,getZ=function()return 0 end,
 getObjects=function()return{contains=function(_,object)return present[object]==true end}end}
local empty={getItems=function()return{size=function()return 0 end}end}
owned.getSquare=function()return square end;owned.getContainer=function()return empty end
square.transmitRemoveItemFromSquare=function(_,object,includeMulti)
 -- B42's default multi-square path rejects this incomplete stock table before network/server mutation.
 if includeMulti~=false then return -1 end
 network[#network+1]=object
 if not ignoreRemoval then present[object]=nil end
 return 0
end
ctx.ownObject(owned);ctx.cleanOwned()
assert(#network==1 and network[1]==owned,'single-object network removal must be sent')
assert(not present[owned]and present[neighbor],'authoritative owned object must disappear without touching its neighbor')
ctx.cleanOwned();assert(#network==1,'already removed object must not be transmitted again')
present[owned]=true;ignoreRemoval=true
assert(not pcall(ctx.cleanOwned),'broadcast without authoritative removal must fail cleanup')
assert(present[owned]and present[neighbor],'failed cleanup must preserve server ground truth')
print('PASS exact native single-object removal, authoritative absence and untouched neighbor')
'''
        result = subprocess.run([lua, "-", str(ROOT / "tests/native_queue/support/QueueCraftSession.lua")],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_real_lua_skill_restore_uses_remote_safe_api_and_only_owned_changed_perks(self):
        lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
        code = r'''local configure=dofile(arg[1]);local session={};configure(session,true)
Perks={Carving='Carving',Woodwork='Woodwork'}
local amounts={Carving=12.25,Woodwork=7.75,Fitness=0};local levels={Carving=1,Woodwork=2,Fitness=5}
local writes,total={},123.75
local xp={getXP=function(_,perk)return amounts[perk]end,getTotalXp=function()return total end,
 setTotalXP=function(_,value)total=value end,
 setXPToLevel=function(_,perk,level)assert(perk~='Fitness'and level==0);amounts[perk]=0 end,
 AddXP=function(_,perk,value,a,b,c,d)
  assert(a==false and b==false and c==false and d==false,'native admin overload flags differ')
  writes[perk]=(writes[perk]or 0)+1;amounts[perk]=amounts[perk]+value
 end,
 AddXPNoMultiplier=function()error('local-only wrapper must never restore server remote XP')end}
local player={getUsername=function()return 'client1'end,getXp=function()return xp end,
 getMaxWeight=function()return 16 end,getMaxWeightBase=function()return 16 end,
 setMaxWeight=function()end,setMaxWeightBase=function()end,
 getPrimaryHandItem=function()end,getSecondaryHandItem=function()end,setPrimaryHandItem=function()end,setSecondaryHandItem=function()end,
 getPerkLevel=function(_,perk)return levels[perk]end,setPerkLevelDebug=function(_,perk,level)levels[perk]=level end}
local ctx={};session.configure(ctx);ctx.player(player)
amounts.Carving=99.75;levels.Carving=3;total=999
ctx.cleanOwned()
assert(amounts.Carving==12.25 and levels.Carving==1 and writes.Carving==1)
assert(amounts.Woodwork==7.75 and levels.Woodwork==2 and not writes.Woodwork,'unchanged skill must not be rewritten')
assert(amounts.Fitness==0 and levels.Fitness==5 and total==123.75,'unrelated passive skill/total XP differs')
amounts.Carving=99.75;xp.AddXP=function()end
local ok,err=pcall(ctx.cleanOwned)
assert(not ok and err:find('actor=client1',1,true)and err:find('perk=Carving',1,true)and err:find('expectedXP=12.25',1,true)and err:find('actualXP=0',1,true))
print('PASS actual fixture remote-safe flags, exact fractions, unchanged/unrelated skills and failed-reset diagnostics')
'''
        result = subprocess.run([lua, "-", str(ROOT / "tests/native_queue/support/QueueCraftSession.lua")],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_installed_engine_skill_reset_harness(self):
        game, jdk = os.environ.get("PZ_NATIVE_GAME"), os.environ.get("PZ_NATIVE_JDK")
        if not game or not jdk:
            self.skipTest("Set PZ_NATIVE_GAME and PZ_NATIVE_JDK to run real engine XP methods headlessly")
        jar = Path(game) / "projectzomboid.jar"
        with tempfile.TemporaryDirectory() as directory:
            source = ROOT / "tests/native_queue/support/CraftSkillResetChecks.java"
            compile = subprocess.run([str(Path(jdk) / "bin/javac"), "-d", directory, "-cp", str(jar), str(source)],
                                     text=True, capture_output=True, timeout=60)
            self.assertEqual(0, compile.returncode, compile.stdout + compile.stderr)
            result = subprocess.run([str(Path(jdk) / "bin/java"), "-Djava.awt.headless=true", "-cp", directory + os.pathsep + str(jar),
                                     "zombie.characters.CraftSkillResetChecks"], text=True, capture_output=True, timeout=60)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertIn("CRAFT_SKILL_RESET_CHECKS_PASS realNative=true localAndRemote=true passiveLevel5Xp0Untouched=true", result.stdout)

    def test_real_lua_cleanup_polling_and_product_pending_receipts(self):
        lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
        code = r'''next=nil
local create=dofile(arg[1]);local configure=dofile(arg[2]);local now=0
getTimestampMs=function()return now end
local failedAsserts=0;local nativeAssert=assert
assert=function(value,...)if not value then failedAsserts=failedAsserts+1 end;return nativeAssert(value,...)end
local entries={{getID=function()return 7 end}}
local inventory={getItems=function()return{size=function()return #entries end,get=function(_,i)return entries[i+1]end}end}
getPlayer=function()return{getInventory=function()return inventory end,getOnlineID=function()return 1 end}end
local setup={};configure(setup,true);local ownership={};setup.configure(ownership)
for i=1,20 do local ready=ownership.verifyOwned({items={7},squares={}});nativeAssert(ready==false)end
nativeAssert(failedAsserts==0,'replication lag must not trigger Kahlua logged assertions')
entries={};nativeAssert(ownership.verifyOwned({items={7},squares={}})==true)
local output={};sendClientCommand=function(module,command,args)output[#output+1]=command end
local pending,cleanReady=true,false
local s=create({user='client1',cases={'visual'},module='WishlistTest'},{visual=function(ctx)
 ctx.readyToClean=function()return not pending end;ctx.cleanup=function()return true end;ctx.clean=function()return cleanReady,'replicating'end
 ctx.events.OnGameStart.Add(function()end)
end},false)
s.prepare();nativeAssert(#output==0,'OnGameStart must not use the MP transport');s.tick();nativeAssert(output[1]=='Prepare')
local envelope={fixtureCase='visual',fixtureEpoch=1,fixtureActor='client1'}
s.receive('Start',nil,envelope);s.current().finish(true,false);nativeAssert(s.phase=='drain')
for i=1,20 do s.tick()end;nativeAssert(#output==1 and failedAsserts==0)
pending=false;s.tick();nativeAssert(s.phase=='finish' and output[#output]=='Finish')
s.receive('Clean',nil,envelope)
for i=1,20 do s.tick()end;nativeAssert(s.phase=='clean'and failedAsserts==0)
cleanReady=true;s.tick();nativeAssert(s.phase=='cleaned'and output[#output]=='Cleaned')
-- Execute the actual Wishlist fixture's pending/raw-reply guards, without stage bodies.
local state={queue={},lists={}}
local option={getValue=function()return true end}
local page={pin=false,inventoryPane={getYScroll=function()return 0 end},getIsVisible=function()return false end}
getPlayerInventory=function()return page end;getPlayerLoot=function()return page end
getActivatedMods=function()return{contains=function()return false end}end
PZSurvivorWishlist={Client={state=function()return state end},UI={windows={}}}
PZAPI={ModOptions={getOptions=function()return{getOption=function()return option end}end}}
local lines={'client1','visual,standalone','host','12345','password','PZSurvivorToolkit'}
getFileReader=function()local i=0;return{readLine=function()i=i+1;return lines[i]end,close=function()end}end
local events=setmetatable({},{__index=function(t,k)local e={Add=function()end};t[k]=e;return e end})
QueueWishlistSession={case='visual',events=events};dofile(arg[3]);local ctx=QueueWishlistSession
nativeAssert(WishlistTestFixture.stageCount==11 and ctx.readyToClean())
state.pending={requestId='8'};nativeAssert(not ctx.readyToClean());state.pending=nil
state.queue={{action='set'}};nativeAssert(not ctx.readyToClean());state.queue={}
ctx.trackRequest('forged');nativeAssert(not ctx.readyToClean())
nativeAssert(not pcall(ctx.trackRequest,'forged'),'duplicate raw request must remain rejected')
ctx.observeProduct('Other','snapshot',{requestId='forged'});nativeAssert(not ctx.readyToClean())
ctx.observeProduct('PZSurvivorWishlist','snapshot',{requestId='late'});nativeAssert(not ctx.readyToClean())
ctx.observeProduct('PZSurvivorWishlist','snapshot',{requestId='forged'});nativeAssert(ctx.readyToClean())
state.error='timeout';nativeAssert(not pcall(ctx.readyToClean),'unknown product effects must fail closed')
local removed=false
local square={getX=function()return 0 end,getY=function()return 0 end,getZ=function()return 0 end,
 transmitRemoveItemFromSquare=function()removed=true end}
local foreign={getSquare=function()return square end,getContainer=function()return{getItems=function()return{size=function()return 1 end}end}end}
ownership.ownObject(foreign);nativeAssert(not pcall(ownership.cleanOwned)and not removed,'foreign contents must retain their fixture surface')
print('PASS quiet replication polling, RPC drain, real Wishlist pending/forged receipt guards')
'''
        result = subprocess.run([lua, "-", str(ROOT / "tests/native_queue/support/QueueFixtureSession.lua"),
                                 str(ROOT / "tests/native_queue/support/QueueCraftSession.lua"),
                                 str(ROOT / "tests/native_queue/contributions/shared-wishlist/client/ZZWishlist.lua")],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_real_lua_wishlist_server_visual_cleanup_guards_without_next(self):
        lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
        code = r'''next=nil
local source=arg[1]
local function fixture(preexisting)
 local model={cleaned=0,removed=0,items=0,faction=preexisting}
 local payloads={client1={lists={{owner='client1',entries={},members={}}}},client2={lists={{owner='client2',entries={},members={}}}}}
 local command
 local ctx={case='visual',events={OnServerStarted={Add=function()end},OnClientCommand={Add=function(fn)command=fn end}},
  player=function()end,ownItem=function()model.items=model.items+1 end,ownObject=function()end,
  reply=function()end,cleanOwned=function()model.cleaned=model.cleaned+1 end}
 QueueWishlistSession=ctx
 Faction={getFaction=function()return model.faction end,getFactions=function()return{remove=function(_,value)
  assert(value==model.faction,'cleanup must target the exact owned faction')
  if not model.keepFaction then model.faction=nil;model.removed=model.removed+1 end
 end}end}
 PZSurvivorWishlist={Service={snapshot=function(player)return payloads[player:getUsername()]end}}
 getCell=function()return{}end;sendAddItemToContainer=function()end
 local id=0
 local function addItem()id=id+1;return{getID=function()return id end}end
 local crate={setType=function()end,setCapacity=function()end,setExplored=function()end,AddItem=addItem}
 IsoThumpable={new=function()
  local data={};return{setCanPassThrough=function()end,setIsContainer=function()end,getContainer=function()return crate end,
   getModData=function()return data end,transmitCompleteItemToClients=function()end,transmitModData=function()end}
 end}
 dofile(source)
 for _,name in ipairs({'client1','client2'})do
  local user=name
  local player={getUsername=function()return user end,getInventory=function()return{AddItem=addItem}end,
   getCurrentSquare=function()return{AddSpecialObject=function()end}end}
  command('WishlistTest','Ready',player,{})
 end
 assert(model.items==16,'exercise real Ready ownership and peer registration')
 return ctx,payloads,model
end
local ctx,payloads,model=fixture();assert(ctx.cleanup()==true and model.cleaned==1)
local function reject(change)
 local ctx,payloads,model=fixture();change(ctx,payloads,model)
 assert(not pcall(ctx.cleanup),'unsafe visual reset must fail closed')
 assert(model.cleaned==0 and model.removed==0,'guard failure must not clean world state or delete factions')
end
reject(function(_,p)p.client1.lists[1].entries['Base.Hammer']={amount=1}end)
reject(function(_,p)p.client1.lists[1].entries[2]=true end)
reject(function(_,p)p.client1.lists[1].members.client2=true end)
reject(function(_,p)p.client1.lists[1].owner='client2'end)
reject(function(_,p)p.client1.lists[1].faction='WishlistTest'end)
reject(function(_,p)p.client2.error='storage_invalid'end)
reject(function(ctx,_,m)ctx.faction={};m.faction={}end)
reject(function(ctx,_,m)ctx.faction={};m.faction=ctx.faction;m.keepFaction=true end)
ctx,payloads,model=fixture();ctx.faction={};model.faction=ctx.faction
assert(ctx.cleanup()==true and model.faction==nil and model.removed==1 and model.cleaned==1,'remove only the exact owned faction')
assert(not pcall(fixture,{}),'preexisting unrelated fixture-named faction must be retained')
print('PASS real server visual empty-list/owner/storage/faction reset guards with next unavailable')
'''
        result = subprocess.run([lua, "-", str(ROOT / "tests/native_queue/contributions/shared-wishlist/server/ZZWishlist_Server.lua")],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_grouped_wishlist_only_visual_then_standalone(self):
        value = dict(selection("shared-wishlist", "visual"), cases=["standalone", "visual"])
        adapter.validate(value)
        self.assertEqual(["visual", "standalone"], adapter.ordered_cases(value))
        for cases in (["full", "standalone"], ["reload", "visual"], ["full", "visual", "standalone"]):
            with self.assertRaisesRegex(ValueError, "separate isolated"):
                adapter.validate(dict(value, cases=cases))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            runtime = {"roles": {role: {} for role in ("server", "client1", "client2")}}
            adapter.stage(ROOT, root, None, None, value, {}, runtime)
            lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
            code = r'''local hooks={};Events=setmetatable({},{__index=function(t,k)
 local e={Add=function(fn)hooks[k]=hooks[k]or{};table.insert(hooks[k],fn)end};t[k]=e;return e end})
local lines={'client1','visual,standalone','host','12345','password','PZSurvivorToolkit'}
getFileReader=function()local i=0;return{readLine=function()i=i+1;return lines[i]end,close=function()end}end
assert(loadfile(arg[1]))();assert(#hooks.OnGameStart==1 and #hooks.OnTick==1 and #hooks.OnServerCommand==1)
assert(loadfile(arg[2]))
print('PASS grouped Wishlist generated Lua and single bootstrap')
'''
            base = root / "client1/mods/WishlistTest/42/media/lua"
            result = subprocess.run([lua, "-", str(base / "client/ZZWishlist.lua"), str(base / "server/ZZWishlist_Server.lua")],
                                    input=code, text=True, capture_output=True)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            for role in ("server", "client1", "client2"):
                (root / (role + "-launch.log")).write_text(session_log(value, role))
            result = adapter.verify(root, value, {"suites": adapter.definitions()})
            self.assertEqual([], result["issues"])
            self.assertEqual(37, result["evidence"]["preserved_stages_per_client"])
            self.assertEqual(4, len(result["outcomes"]))
            self.assertEqual([(role, case) for role in ("client1", "client2") for case in value["cases"]],
                             [(row["actor"], row["case"]) for row in result["outcomes"]])
            runtime = {"server_name": "queue-smoke", "roles": {role: {"cache": str((root / role).resolve())} for role in ("server", "client1", "client2")}}
            evidence = {"selection.json": value, "runtime.json": runtime,
                        "execution.json": {"status": "completed", "processes": {role: {"exit_code": 0} for role in runtime["roles"]}},
                        "report.json": {"status": "passed", "functional": {"status": "passed"}, "provenance": {"verified": True},
                                        "runtime": {"status": "clean", "microphone": False, "roles": {role: {"available": True} for role in runtime["roles"]}}}}
            for name, data in evidence.items():
                (root / name).write_text(json.dumps(data))
            world = root / "server/Saves/Multiplayer/queue-smoke/global_mod_data.bin"
            world.parent.mkdir(parents=True);world.write_bytes(b"clean-world")
            slot = adapter._store_prefix(root / "server", "queue-smoke") / "a.txt"
            slot.parent.mkdir(parents=True);slot.write_text("PZSW\t1\t19\nEND\tfixture\n")
            reload = dict(selection("shared-wishlist", "reload"), options={"seed_run": str(root)})
            with patch("queue_checks.report.verify_manifest", return_value=[]):
                self.assertEqual([world, slot], adapter._seed(reload)[1])
                log = root / "client1-launch.log"
                log.write_text(log.read_text().replace("JOINT_CLEAN case=visual", "MISSING case=visual"))
                with self.assertRaisesRegex(ValueError, "native assertions are incomplete"):
                    adapter._seed(reload)

    def test_identical_reload_headers_are_allowed_but_conflicting_headers_fail(self):
        value = selection("crafting-plans", "crafting")
        text = client_log(value, "client1")
        header = "[CRAFT_TEST] EXPECTED checks=20 scenario=crafting\n"
        self.assertEqual([], adapter._client_issues(header + text, value, "client1", "crafting"))
        self.assertTrue(adapter._client_issues(header.replace("checks=20", "checks=19") + text, value, "client1", "crafting"))
        self.assertTrue(adapter._client_issues(text.replace(header, ""), value, "client1", "crafting"))

    def test_failed_or_partial_completion_ends_lifecycle_but_fails_verification(self):
        for suite, case in (("crafting-plans", "crafting"), ("shared-wishlist", "full")):
            value = selection(suite, case)
            for count in (0, adapter.COUNTS[suite][case]):
                text = "[" + adapter.marker(value) + "] COMPLETE checks=" + str(count) + " failures=1\n"
                self.assertTrue(adapter.complete(value, "client1", text))
                self.assertTrue(adapter._client_issues(text, value, "client1", case))

    def test_authority_receipts_cannot_be_missing_or_duplicate(self):
        for suite, case in (("crafting-plans", "crafting"), ("crafting-plans", "alternatives"), ("shared-wishlist", "full")):
            value = selection(suite, case)
            text = server_log(value)
            self.assertEqual([], adapter._server_issues(text, value, case))
            receipt = text.splitlines()[1]
            for broken in (text.replace(receipt, ""), text + receipt + "\n", text.replace("ok=true", "ok=false", 1)):
                self.assertTrue(adapter._server_issues(broken, value, case))

    def test_native_ui_requires_all_render_and_scroll_markers(self):
        value = selection("crafting-plans", "ui")
        text = client_log(value, "client1")
        for marker in ("PREVIEW_RENDERED", "FALLBACK_RENDERED", "WINDOW_GUARDS", "START_CALLBACK", "label=wide"):
            self.assertTrue(adapter._client_issues(text.replace(marker, "MISSING"), value, "client1", "ui"))

    def test_staging_reuses_preserved_fixture_and_refuses_collisions(self):
        for suite, case in (("crafting-plans", "alternatives"), ("shared-wishlist", "standalone")):
            value = selection(suite, case)
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                runtime = {"server_name": "queue-smoke", "roles": {role: {"cache": str(root / role)} for role in ("server", "client1", "client2")}}
                adapter.stage(ROOT, root, None, None, value, {}, runtime)
                expected = adapter.HELPERS[suite]
                self.assertEqual([expected], runtime["fixture"]["mods"])
                snapshots = []
                for role in runtime["roles"]:
                    helper = root / role / "mods" / expected
                    snapshots.append({str(path.relative_to(helper)): path.read_bytes() for path in helper.rglob("*") if path.is_file()})
                    config = root / role / "Lua" / ("craft-fixture.txt" if suite == "crafting-plans" else "wishlist-fixture.txt")
                    self.assertEqual([role, case], config.read_text().splitlines()[:2])
                    self.assertEqual(0, config.stat().st_mode & 0o077)
                self.assertEqual(snapshots[0], snapshots[1])
                self.assertEqual(snapshots[1], snapshots[2])
                with self.assertRaises(ValueError):
                    adapter.stage(ROOT, root, None, None, value, {}, runtime)

    def test_selection_rejects_invalid_controls_and_missing_dependencies(self):
        value = selection("crafting-plans", "crafting")
        for changes in ({"mode": "native"}, {"kind": "sp"}, {"clients": 1}, {"cases": ["crafting", "crafting"]},
                        {"ports": [18061, 18063]}, {"mods": ["PZSurvivorToolkit"]}):
            with self.assertRaises(ValueError):
                adapter.validate(dict(value, **changes))
        with self.assertRaisesRegex(ValueError, "seed_run"):
            adapter.validate(selection("shared-wishlist", "reload"))
        with self.assertRaisesRegex(ValueError, "integration missing"):
            adapter.validate(dict(selection("shared-wishlist", "full"), mods=["PZSurvivorToolkit"]))
        for case in ("standalone", "visual", "reload"):
            spec = next(row for row in adapter.definitions()["shared-wishlist"]["cases"] if row["id"] == case)
            self.assertEqual(["toolkit", "native"], spec["modes"])
            if case != "reload":
                adapter.validate(dict(selection("shared-wishlist", case), mode="native"))

    def test_staging_does_not_write_bytecode_into_preserved_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project, output = root / "project", root / "run"
            relative = Path("tests/native_queue/contributions/shared-wishlist")
            source = project / relative
            source.mkdir(parents=True)
            shutil.copy2(ROOT / relative / "prepare.py", source)
            for side in ("client", "server"):
                shutil.copytree(ROOT / relative / side, source / side)
            runtime = {"server_name": "queue-smoke", "roles": {role: {"cache": str(output / role)} for role in ("server", "client1", "client2")}}
            with patch.object(sys, "dont_write_bytecode", False):
                adapter.stage(project, output, None, None, selection("shared-wishlist", "standalone"), {}, runtime)
            self.assertFalse((source / "__pycache__").exists())

    def test_reload_requires_exact_restore_receipts_before_ready(self):
        value = selection("shared-wishlist", "reload")
        text = server_log(value)
        self.assertEqual([], adapter._server_issues(text, value, "reload"))
        for broken in (text.replace("RESTORE_COMPLETE slots=1", "RESTORE_COMPLETE slots=2"),
                       text.replace("RESTORE slot=a chars=12", "RESTORE slot=a chars=0"),
                       text + "[WISHLIST_TEST] RESTORE slot=a chars=12\n",
                       text.replace("[WISHLIST_TEST] RESTORE_COMPLETE slots=1\n", ""),
                       adapter.server_ready(value) + "\n" + text.replace(adapter.server_ready(value), "")):
            self.assertTrue(adapter._server_issues(broken, value, "reload"))

    def test_native_restore_roundtrip_and_fail_closed_guards(self):
        lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
        self.assertIsNotNone(lua, "Lua interpreter required for the retained native restore helper")
        code = r'''local restore = dofile(arg[1])
local files, current, server, client = {}, '/fixture/world', true, false
isServer=function() return server end
isClient=function() return client end
getCurrentSaveName=function() return current end
getFileWriter=function(path)
  return {write=function(_, text) files[path]=text end, close=function() end}
end
getFileReader=function(path)
  if not files[path] then return end
  local pos=1
  return {close=function() end, readLine=function()
    local a,b=files[path]:find('\n',pos,true)
    if not a then return end
    local line=files[path]:sub(pos,a-1); pos=b+1; return line
  end}
end
local text='PZSW\t1\t19\nEND\tfixture\n'
restore(current,{a=text,b=text})
local n=0; for path,value in pairs(files) do n=n+1; assert(value==text) end; assert(n==2)
assert(not pcall(restore,current,{a=text}))
files={}; assert(not pcall(restore,'other',{a=text}))
assert(not pcall(restore,current,{}))
assert(not pcall(restore,current,{foreign=text}))
server=false; assert(not pcall(restore,current,{a=text})); server=true
client=true; assert(not pcall(restore,current,{a=text})); client=false
getFileWriter=function() return nil end
assert(not pcall(restore,current,{a=text}))
print('PASS native restore roundtrip and guards')
'''
        result = subprocess.run([lua, "-", str(ROOT / "tests/native_queue/support/QueueWishlistRestore.lua")],
                                input=code, text=True, capture_output=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_store_prefix_matches_kahlua_utf16_units_and_path_chunks(self):
        cache = Path("/fixture/мир-😀/server")
        prefix = adapter._store_prefix(cache, "queue-smoke")
        chunks = prefix.relative_to(cache / "Lua/PZSurvivorWishlist").parts
        self.assertTrue(all(len(part) == 80 for part in chunks[:-1]))
        raw = bytes.fromhex("".join(chunks))
        self.assertEqual(str(cache / "Saves/Multiplayer/queue-smoke"), raw.decode("utf-16-be"))
        for name in ("..", "bad/name", None):
            with self.assertRaises(ValueError):
                adapter._store_prefix(cache, name)

    def test_generated_restore_preserves_unicode_world_and_slot_as_utf8_bytes(self):
        lua = shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")
        self.assertIsNotNone(lua, "Lua interpreter required for generated restore string roundtrip")
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            seed, output = base / "seed", base / "мир-😀"
            prefix = adapter._store_prefix(seed / "server", "queue-smoke")
            prefix.mkdir(parents=True)
            slot = prefix / "a.txt"
            text = 'PZSW\t1\t19\nL\tигрок-😀\t14\t\nE\tBase.Hammer\t7\t0\nEND\t19\t123\n'
            slot.write_text(text, encoding="utf-8")
            (seed / "runtime.json").write_text(json.dumps({"server_name": "queue-smoke"}))
            value = dict(selection("shared-wishlist", "reload"), options={"seed_run": str(seed)})
            runtime = {"server_name": "queue-smoke", "roles": {role: {"cache": str(output / role)} for role in ("server", "client1", "client2")}}
            with patch.object(adapter, "_seed", return_value=(seed, [slot])):
                adapter.stage(ROOT, output, None, None, value, {}, runtime)
            modules = [output / role / "mods/WishlistTest/42/media/lua/server/WishlistSeedRestore.lua" for role in runtime["roles"]]
            contents = [path.read_bytes() for path in modules]
            self.assertEqual(contents, [contents[0]] * 3)
            self.assertTrue(contents[0].isascii(), "Kahlua's source lexer must only receive ASCII string literals")
            code = r'''local world, slots
require=function() return function(a,b) world,slots=a,b end end
dofile(arg[1]); WishlistSeedRestore()
io.write(world, '\0', slots.a)
'''
            result = subprocess.run([lua, "-", str(modules[0])], input=code.encode("ascii"), capture_output=True)
            self.assertEqual(0, result.returncode, result.stderr.decode("utf-8", errors="replace"))
            world = str(output / "server/Saves/Multiplayer/queue-smoke")
            self.assertEqual(world.encode("utf-8") + b"\0" + text.encode("utf-8"), result.stdout)
            self.assertEqual(text.encode("utf-8"), slot.read_bytes(), "Seed bytes must remain unchanged")

    def test_reload_copies_only_owned_persisted_state_and_checks_seed(self):
        initial = selection("shared-wishlist", "standalone")
        with tempfile.TemporaryDirectory() as directory:
            seed, target = Path(directory).resolve() / "seed", Path(directory).resolve() / "target"
            seed.mkdir()
            runtime = {"server_name": "queue-smoke", "roles": {role: {"cache": str(seed / role)} for role in ("server", "client1", "client2")}}
            evidence = {"selection.json": initial, "runtime.json": runtime,
                        "execution.json": {"status": "completed", "processes": {role: {"exit_code": 0} for role in runtime["roles"]}},
                        "report.json": {"status": "passed", "functional": {"status": "passed"}, "provenance": {"verified": True},
                                        "runtime": {"status": "clean", "microphone": False,
                                                    "roles": {role: {"available": True} for role in runtime["roles"]}}}}
            for name, data in evidence.items():
                (seed / name).write_text(json.dumps(data))
            for role in runtime["roles"]:
                (seed / (role + "-launch.log")).write_text(server_log(initial) if role == "server" else client_log(initial, role))
            state = seed / "server/Saves/Multiplayer/queue-smoke/global_mod_data.bin"
            state.parent.mkdir(parents=True)
            state.write_bytes(b"persisted-list-fixture")
            forbidden = seed / "server/Lua/unrelated.txt"
            forbidden.parent.mkdir(parents=True)
            forbidden.write_text("do not copy")
            prefix = adapter._store_prefix(seed / "server", "queue-smoke")
            prefix.mkdir(parents=True)
            slots = [prefix / (name + ".txt") for name in ("a", "b")]
            for index, slot in enumerate(slots):
                slot.write_text("PZSW\t1\t" + str(index + 19) + "\nEND\tfixture\n")
            foreign = adapter._store_prefix(seed / "server", "unrelated-world") / "a.txt"
            foreign.parent.mkdir(parents=True)
            foreign.write_text("do not restore another world")
            value = dict(selection("shared-wishlist", "reload"), options={"seed_run": str(seed)})
            with patch("queue_checks.report.verify_manifest", return_value=[]):
                self.assertEqual([state, *slots], adapter._seed(value)[1])
                output_runtime = {"server_name": "queue-smoke", "roles": {role: {"cache": str(target / role)} for role in runtime["roles"]}}
                adapter.stage(ROOT, target, None, None, value, {}, output_runtime)
                self.assertEqual(state.read_bytes(), (target / state.relative_to(seed)).read_bytes())
                self.assertFalse((target / forbidden.relative_to(seed)).exists())
                self.assertFalse(adapter._store_prefix(target / "server", "queue-smoke").exists(), "Live userdata must be restored only after native launch")
                helpers = []
                for role in runtime["roles"]:
                    helper = target / role / "mods/WishlistTest/42/media/lua/server"
                    text = (helper / "WishlistSeedRestore.lua").read_text()
                    self.assertIn(str(target / "server/Saves/Multiplayer/queue-smoke"), text)
                    self.assertIn('PZSW\\t1\\t19', text)
                    self.assertNotIn("unrelated-world", text)
                    helpers.append(text)
                self.assertEqual(helpers, [helpers[0]] * 3)
                self.assertTrue(all(slot.read_text().startswith("PZSW") for slot in slots))
                self.assertEqual("reload", (target / "client1/Lua/wishlist-fixture.txt").read_text().splitlines()[1])
                with self.assertRaisesRegex(ValueError, "endpoint"):
                    adapter._seed(dict(value, ports=[19061, 19062]))
                evidence["report.json"]["status"] = "failed"
                (seed / "report.json").write_text(json.dumps(evidence["report.json"]))
                with self.assertRaisesRegex(ValueError, "verified successful"):
                    adapter._seed(value)
                clean = json.loads(json.dumps(evidence["report.json"]))
                clean["status"] = "passed"
                for status, runtime_status, microphone, available in (
                    ("unknown", "clean", False, True),
                    ("needs-review", "unknown", False, True),
                    ("needs-review", "new-errors", False, True),
                    ("needs-review", "unclassified-errors", True, True),
                    ("needs-review", "unclassified-errors", False, False),
                    ("passed", "new-errors", False, True),
                    ("passed", "reproduced-without-queue", False, True),
                    ("passed", "failed", False, True),
                ):
                    bad = json.loads(json.dumps(clean))
                    bad["status"] = status
                    bad["runtime"].update(status=runtime_status, microphone=microphone)
                    bad["runtime"]["roles"]["server"]["available"] = available
                    (seed / "report.json").write_text(json.dumps(bad))
                    with self.assertRaisesRegex(ValueError, "verified successful"):
                        adapter._seed(value)
                background = json.loads(json.dumps(clean))
                background["runtime"]["status"] = "background-only"
                (seed / "report.json").write_text(json.dumps(background))
                self.assertEqual([state, *slots], adapter._seed(value)[1])
                for message in ("ERROR: General > java.lang.OutOfMemoryError: late failure\n",
                                "ERROR: General > unknown late failure\n",
                                "LOG: General > initialisedRecDev=true\n"):
                    mirror = seed / "server/console.txt"
                    mirror.write_text(message)
                    with self.assertRaisesRegex(ValueError, "runtime audit"):
                        adapter._seed(value)
                    mirror.unlink()
                pending = json.loads(json.dumps(clean))
                pending["status"] = "needs-review"
                pending["runtime"]["status"] = "unclassified-errors"
                (seed / "report.json").write_text(json.dumps(pending))
                self.assertEqual([state, *slots], adapter._seed(value)[1])
                for role in runtime["roles"]:
                    (target / (role + "-launch.log")).write_text(server_log(value) if role == "server" else client_log(value, role))
                result = adapter.verify(target, value, {"suites": adapter.definitions()})
                self.assertEqual([], result["issues"])
                self.assertTrue(result["evidence"]["requires_review"])
                self.assertTrue(result["evidence"]["seed_native_audit"]["pending"])
                with (seed / "server-launch.log").open("a") as stream:
                    stream.write("ERROR: General > java.lang.OutOfMemoryError: pending cannot waive this\n")
                with self.assertRaisesRegex(ValueError, "runtime audit"):
                    adapter._seed(value)
                (seed / "server-launch.log").write_text(server_log(initial))
                evidence["execution.json"]["processes"]["server"].pop("exit_code")
                (seed / "execution.json").write_text(json.dumps(evidence["execution.json"]))
                with self.assertRaisesRegex(ValueError, "not stopped"):
                    adapter._seed(value)
                evidence["execution.json"]["processes"]["server"]["exit_code"] = 0
                (seed / "execution.json").write_text(json.dumps(evidence["execution.json"]))
            evidence["report.json"]["status"] = "passed"
            (seed / "report.json").write_text(json.dumps(evidence["report.json"]))
            with patch("queue_checks.report.verify_manifest", return_value=["Changed input"]):
                with self.assertRaisesRegex(ValueError, "evidence has changed"):
                    adapter._seed(value)


if __name__ == "__main__":
    unittest.main()
