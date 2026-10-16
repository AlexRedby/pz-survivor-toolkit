"""Install only this helper and its runtime parameters; never launch or copy PZ."""
import argparse
import os
from pathlib import Path
import re
import shutil

HERE = Path(__file__).resolve().parent


def prepare(cache, user, mode, host, port, password, mods):
    selected = [mode] if isinstance(mode, str) else list(mode)
    if (user not in ("client1", "client2", "server") or not selected or len(selected) != len(set(selected))
            or any(case not in ("full", "standalone", "reload", "visual") for case in selected)
            or (len(selected) > 1 and set(selected) != {"visual", "standalone"})):
        raise ValueError("Unsupported fixture actor or mode")
    if not 1 <= port <= 65534:
        raise ValueError("Port must leave room for the server's adjacent UDP port")
    if not mods or len(mods) != len(set(mods)) or "PZSurvivorWishlist" not in mods:
        raise ValueError("Supply unique product mod IDs including PZSurvivorWishlist")
    if any(not re.fullmatch(r"[A-Za-z0-9_.-]+", mod) for mod in mods):
        raise ValueError("Invalid mod ID")
    if any(case in ("standalone", "visual") for case in selected) and mods != ["PZSurvivorWishlist"]:
        raise ValueError("Standalone/visual modes require only PZSurvivorWishlist")
    if "full" in selected and "PZSurvivorToolkit" not in mods:
        raise ValueError("Full mode requires PZSurvivorToolkit plus the declared integrations")
    selected = [case for case in ("visual", "standalone", "full", "reload") if case in selected]
    values = [user, ",".join(selected), host, str(port), password, ";".join(mods)]
    if any(not value or any(c in value for c in "\r\n\0") for value in values):
        raise ValueError("Runtime parameters must be nonempty single lines")
    helper = cache / "mods/WishlistTest"
    config = cache / "Lua/wishlist-fixture.txt"
    if helper.exists() or config.exists():
        raise ValueError("Fixture already exists; do not overwrite a prepared cache")
    helper.mkdir(parents=True)
    (helper / "common").mkdir()
    lua = helper / "42/media/lua"
    for side in ("client", "server"):
        if len(selected) == 1:
            shutil.copytree(HERE / side, lua / side)
        else:
            (lua / side).mkdir(parents=True)
            (lua / side / ('ZZWishlist.lua' if side == 'client' else 'ZZWishlist_Server.lua')).write_text(
                session_source(selected, side), encoding='utf-8')
    (helper / "42/mod.info").write_text("name=Isolated wishlist fixture\nid=WishlistTest\nversionMin=42.21\n", encoding="utf-8")
    config.parent.mkdir(parents=True, exist_ok=True)
    # This disposable runtime file contains the supplied test password.
    with open(config, "x", encoding="utf-8", opener=lambda path, flags: os.open(path, flags, 0o600)) as output:
        output.write("\n".join(values) + "\n")
    return config


def session_source(selected, side):
    support = HERE.parents[1] / "support"
    parts = ["local createSession=(function()\n" + (support / "QueueFixtureSession.lua").read_text() + "\nend)()\n",
             "local configure=(function()\n" + (support / "QueueCraftSession.lua").read_text() + "\nend)()\nlocal factories={}\n"]
    source = HERE / side / ("ZZWishlist.lua" if side == "client" else "ZZWishlist_Server.lua")
    for case in selected:
        parts.append("factories['" + case + "']=function(QueueWishlistSession)\n" + source.read_text() + "\nend\n")
    parts.append("""
local reader=assert(getFileReader('wishlist-fixture.txt',false))
local config={};for _,key in ipairs({'user','scenario','host','port','password','mods'}) do config[key]=assert(reader:readLine()) end;reader:close()
config.module='WishlistTest';config.cases={};for case in config.scenario:gmatch('[^,]+') do config.cases[#config.cases+1]=case end
""")
    parts.append("local session=createSession(config,factories," + ('true' if side == 'server' else 'false') + ")\n")
    parts.append("configure(session," + ('true' if side == 'server' else 'false') + ")\n")
    if side == 'server':
        parts.append("""
Events.OnServerStarted.Add(function() session.prepare();print('[WISHLIST_TEST] SERVER_READY') end)
Events.OnClientCommand.Add(function(module,command,player,args) session.command(module,command,player,args) end)
Events.OnTick.Add(session.tick)
""")
    else:
        parts.append("""
local connecting,advanced=false,false
Events.OnConnected.Add(function() connecting=true end)
Events.OnMainMenuEnter.Add(function()
 if connecting or isClient() then return end;connecting=true
 ConnectToServer.instance:connect(MainScreen.instance,'Native wishlist session',config.user,config.password,config.host,'',config.port,'',false,true,1)
end)
Events.OnPreUIDraw.Add(function()
 if (not connecting and not isClient()) or advanced or isIngameState() then return end
 if not MainScreen.instance or not MainScreen.instance.charCreationProfession or not MapSpawnSelect.instance then return end
 if MainScreen.instance.charCreationProfession:getIsVisible() or MapSpawnSelect.instance:getIsVisible() then
  advanced=true;MapSpawnSelect.instance:useDefaultSpawnRegion();MapSpawnSelect.instance:setVisible(false)
  MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
  MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
 end
end)
Events.OnConnectFailed.Add(function(a,b) session.quarantine('connect '..tostring(a)..' '..tostring(b)) end)
Events.OnDisconnect.Add(function() session.quarantine('disconnect with unknown effects') end)
Events.OnGameStart.Add(function()
 if config.user=='client2' then local p=getPlayer();p:teleportTo(math.floor(p:getX())+8,math.floor(p:getY())+8,0) end
 session.prepare()
end)
Events.OnServerCommand.Add(function(module,command,args) session.command(module,command,nil,args) end)
Events.OnTick.Add(session.tick)
""")
    return ''.join(parts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cache", type=Path)
    parser.add_argument("--user", choices=("server", "client1", "client2"), required=True)
    parser.add_argument("--mode", choices=("full", "standalone", "reload", "visual"), required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--password-env", required=True, help="Name of an environment variable; never pass the password in argv")
    parser.add_argument("--mods", nargs="+", default=["PZSurvivorWishlist"])
    args = parser.parse_args()
    if args.password_env not in os.environ:
        parser.error("Password environment variable is missing")
    try:
        prepare(args.cache, args.user, args.mode, args.host, args.port, os.environ[args.password_env], args.mods)
    except ValueError as error:
        parser.error(str(error))
    print("Prepared helper only; no game, launcher, mods, world or server was started.")


if __name__ == "__main__":
    main()
