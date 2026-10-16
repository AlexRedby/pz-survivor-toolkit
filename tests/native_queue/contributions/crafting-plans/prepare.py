"""Stage this fixture only; the common runner owns game/mod snapshots and launch."""
import argparse
import json
import os
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent


def prepare(cache, user, scenario, host, port, password):
    scenarios = json.loads((HERE / 'manifest.json').read_text())['scenarios']
    selected = [scenario] if isinstance(scenario, str) else list(scenario)
    if (user not in ('server', 'client1', 'client2') or not selected or len(selected) != len(set(selected))
            or any(case not in scenarios for case in selected)):
        raise ValueError('Unknown fixture actor or scenario')
    if type(port) is not int or not 1024 <= port <= 65534:
        raise ValueError('Use an unprivileged port with room for UDP port+1')
    selected = [case for case in ('ui', 'crafting', 'alternatives') if case in selected]
    values = [user, ','.join(selected), host, str(port), password]
    if any(not value or any(c in value for c in '\r\n\0') for value in values):
        raise ValueError('Runtime parameters must be nonempty single lines')
    helper, config = cache / 'mods/CraftPlanTest', cache / 'Lua/craft-fixture.txt'
    if helper.exists() or config.exists():
        raise ValueError('Fixture exists; use another disposable cache')
    (helper / 'common').mkdir(parents=True)
    for side in ('client', 'server'):
        target = helper / '42/media/lua' / side
        target.mkdir(parents=True)
        if len(selected) == 1:
            shutil.copy2(HERE / scenarios[selected[0]][side], target / 'ZZCraftFixture.lua')
        else:
            (target / 'ZZCraftFixture.lua').write_text(session_source(selected, scenarios, side), encoding='utf-8')
    (helper / '42/mod.info').write_text('name=Isolated crafting fixture\nid=CraftPlanTest\nversionMin=42.21\n', encoding='utf-8')
    config.parent.mkdir(parents=True, exist_ok=True)
    with open(config, 'x', encoding='utf-8', opener=lambda path, flags: os.open(path, flags, 0o600)) as stream:
        stream.write('\n'.join(values) + '\n')
    return config


def session_source(selected, scenarios, side):
    support = HERE.parents[1] / 'support'
    lifecycle = (support / 'QueueFixtureSession.lua').read_text()
    ownership = (support / 'QueueCraftSession.lua').read_text()
    parts = ["local createSession=(function()\n" + lifecycle + "\nend)()\n",
             "local configure=(function()\n" + ownership + "\nend)()\nlocal factories={}\n"]
    for case in selected:
        parts.append("factories['" + case + "']=function(QueueCraftSession)\n" +
                     (HERE / scenarios[case][side]).read_text() + "\nend\n")
    parts.append("""
local reader=assert(getFileReader('craft-fixture.txt',false))
local config={};for _,key in ipairs({'user','scenario','host','port','password'}) do config[key]=assert(reader:readLine()) end;reader:close()
config.cases={};for case in config.scenario:gmatch('[^,]+') do config.cases[#config.cases+1]=case end
""")
    parts.append("local session=createSession(config,factories," + ('true' if side == 'server' else 'false') + ")\n")
    parts.append("configure(session," + ('true' if side == 'server' else 'false') + ")\n")
    if side == 'server':
        parts.append("""
require 'Entity/TimedActions/ISHandcraftAction'
local nativePerform=ISHandcraftAction.performRecipe
ISHandcraftAction.performRecipe=function(action,...)
 local result=nativePerform(action,...);session.performed(action);return result
end
Events.OnServerStarted.Add(function() session.prepare();print('[QUEUE_TEST] SERVER_READY') end)
Events.OnClientCommand.Add(function(module,command,player,args) session.command(module,command,player,args) end)
Events.OnTick.Add(session.tick)
""")
    else:
        parts.append("""
local connecting,advanced=false,false
Events.OnConnected.Add(function() connecting=true end)
Events.OnMainMenuEnter.Add(function()
 if connecting or isClient() then return end;connecting=true
 ConnectToServer.instance:connect(MainScreen.instance,'Native crafting session',config.user,config.password,config.host,'',config.port,'',false,true,1)
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
    parser.add_argument('cache', type=Path)
    parser.add_argument('--user', choices=('server', 'client1', 'client2'), required=True)
    parser.add_argument('--scenario', choices=('crafting', 'ui', 'alternatives'), required=True)
    parser.add_argument('--host', required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--password-env', required=True, help='Environment variable name; no password in argv')
    args = parser.parse_args()
    if args.password_env not in os.environ:
        parser.error('Password environment variable is missing')
    try:
        prepare(args.cache, args.user, args.scenario, args.host, args.port, os.environ[args.password_env])
    except ValueError as error:
        parser.error(str(error))
    print('Prepared fixture only; no game, mod download, server or client was launched.')


if __name__ == '__main__':
    main()
