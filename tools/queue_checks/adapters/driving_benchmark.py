"""Exercise the portable starter in isolated SP or two-client menu Host."""
from pathlib import Path
import re

MARKER = "[DRIVING_BENCH_TEST] "
COMPLETE = MARKER + "COMPLETE driver-key-fuel-engine-idempotency"


def definitions():
    return {"driving-benchmark": {"status": "ready", "clients": 2,
        "default_mods": ["PZDrivingBench"],
        "cases": [{"id": "ready", "producer": "fixture", "capability": "effect",
                   "kinds": ["sp", "mp"], "languages": ["EN", "RU"], "modes": ["native"]}]}}


def validate(selection):
    mp = selection["kind"] == "mp"
    options = selection.get("options", {})
    if (selection["kind"] not in ("sp", "mp") or selection["cases"] != ["ready"]
            or type(selection["clients"]) is not int or selection["clients"] != (2 if mp else 1)
            or selection["mode"] != "native"
            or selection["languages"] != (["EN", "RU"] if mp else ["EN"])
            or options.get("world_template") or options.get("startup_connection")
            or mp and options.get("mp_host") is not True
            or not mp and options.get("mp_host")
            or "PZDrivingBench" not in selection["mods"]):
        raise ValueError("Driving benchmark requires fresh EN SP or EN/RU two-client menu Host/native with PZDrivingBench")


def sources(project, selection):
    root = Path(project)
    paths = sorted((root / "tests/driving_benchmark/mods").rglob("*.lua")) + sorted(
        (root / "tests/native_queue/driving-benchmark").rglob("*.lua"))
    if selection["kind"] == "mp":
        paths += sorted((root / "tests/native_queue/startup").rglob("*.lua"))
    return paths


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    output, project = Path(output), Path(project)
    if selection["kind"] == "sp":
        (output / "client1/Lua/DrivingBench-run.txt").write_text("PZDrivingBench-native-SP\n")
    else:
        runtime["server_name"] = "PZDrivingBench"
        server = output / "server/Server"
        # Keep queue-smoke originals: common post-staging still updates their Mods/settings.
        for path in sorted(server.glob("queue-smoke*")):
            text = path.read_text().replace("queue-smoke", "PZDrivingBench")
            if path.suffix == ".ini":
                text = re.sub(r"^SpawnPoint=.*$", "SpawnPoint=10818,10118,0", text, flags=re.M)
            (server / path.name.replace("queue-smoke", "PZDrivingBench")).write_text(text)
        (server / "PZDrivingBench_spawnregions.lua").write_text(
            'function SpawnRegions() return {{name="Driving benchmark", '
            'serverfile="PZDrivingBench_spawnpoints.lua"}} end\n')
        (server / "PZDrivingBench_spawnpoints.lua").write_text(
            'function SpawnPoints() return {unemployed={{posX=10818,posY=10118,posZ=0}}} end\n')
        for settings in runtime["roles"].values():
            target = Path(settings["cache"]) / "mods/ActionQueueTest/42/media/lua"
            for side, name in (("client", "ZZStartup.lua"), ("server", "ZZStartupServer.lua")):
                text = (project / "tests/native_queue/startup" / side / name).read_text()
                text = text.replace("queue-smoke", "PZDrivingBench")
                (target / side).mkdir(parents=True, exist_ok=True)
                (target / side / name).write_text(text)
        runtime.setdefault("fixture", {})["server_ready"] = "[STARTUP_TEST] SERVER_READY"
    runtime.setdefault("fixture", {}).update(failure_markers=[
        "[PZDrivingBench] FAIL ", MARKER + "FAIL "])


def complete(selection, role, text):
    actors = ["client1", "client2"] if selection["kind"] == "mp" else ["client1"]
    return role in actors and text.count(COMPLETE) == 1


def verify(root, selection, catalog):
    root = Path(root)
    mp = selection["kind"] == "mp"
    actors = ["client1", "client2"] if mp else ["client1"]
    issues, identities, outcomes = [], {}, []
    for actor in actors:
        actor_issues = []
        text = (root / (actor + "-launch.log")).read_text(errors="replace")
        rows = re.findall(re.escape(COMPLETE) + r" actor=(client[12]) id=(-?\d+) sql=(\d+) authority=(sp|server)(?:\s|$)", text)
        if (not complete(selection, actor, text) or len(rows) != 1
                or rows[0][0] != actor or rows[0][3] != ("server" if mp else "sp")
                or "[PZDrivingBench] READY driver=true engine=true" not in text):
            actor_issues.append("Missing actual starter driver/key/fuel/battery/engine/idempotency checks")
        else:
            identities[actor] = rows[0][1:3]
        if "[PZDrivingBench] FAIL " in text or MARKER + "FAIL " in text:
            actor_issues.append("Starter failed")
        if not (root / actor / "Screenshots/driving-benchmark-ready.png").is_file():
            actor_issues.append("Missing starter screenshot")
        if mp:
            acks = re.findall(re.escape(MARKER) + r"AUTHORITY_ACK actor=(client[12]) id=(\d+) sql=(\d+)(?:\s|$)", text)
            if len(acks) != 1 or acks[0] != (actor, *identities.get(actor, ())):
                actor_issues.append("Missing matching server validation acknowledgement")
        issues += [actor + ": " + issue for issue in actor_issues]
        outcomes.append({"actor": actor, "case": "ready", "status": "failed" if actor_issues else "passed",
                         "reason": "; ".join(actor_issues)})
    if mp:
        server = (root / "server-launch.log").read_text(errors="replace")
        authority = re.findall(re.escape(MARKER) + r"AUTHORITY actor=(client[12]) id=(\d+) sql=(\d+) driver=(\d+) reused=true(?:\s|$)", server)
        if (len(authority) != 2 or {row[0] for row in authority} != set(actors)
                or any(identities.get(row[0]) != row[1:3] for row in authority)
                or any(len({row[index] for row in authority}) != 2 for index in (1, 2, 3))):
            issues.append("Missing two distinct authoritative occupied cars matching both clients")
        if len(re.findall(re.escape(MARKER) + r"PAIR count=2 separated=true(?:\s|$)", server)) != 1:
            issues.append("Missing authoritative two-car count and separation proof")
        if MARKER + "FAIL " in server or "[PZDrivingBench] FAIL " in server:
            issues.append("Host authority failed")
        if issues:
            for row in outcomes:
                row.update(status="failed", reason="; ".join(issues))
    limit = ("macOS menu Host, owner EN and guest RU; stationary native driver/key/fuel/engine and server reuse/separation checks."
             if mp else "macOS EN SP native starter readiness only.")
    return {"issues": issues, "outcomes": outcomes, "evidence": {"identities": identities,
        "limits": [limit, "Windows launcher, manual driving, full pack and WAN stutters require separate checks."]}}
