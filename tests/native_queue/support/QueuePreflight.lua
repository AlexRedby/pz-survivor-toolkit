-- Explicit fixture lifecycle registration. Native Events and product APIs remain owned by the game.
local P={}
if isServer and isServer() then
 function P.onGameStart(events,fn) events.OnGameStart.Add(fn) end
 function P.onTick(events,fn) events.OnTick.Add(fn) end
 function P.removeTick(events,fn) events.OnTick.Remove(fn) end
 return P
end
local config=require 'QueuePreflightConfig'
local reader=assert(getFileReader('smoke-user.txt',false),'preflight role missing')
local role=reader:readLine();reader:close()
local allowed=false
for _,actor in ipairs(config.roles) do if actor==role then allowed=true end end
assert(allowed,'preflight role is not required')
local ready,failed,setup,running=false,false,false,false
local setupStarted=false
local starts={}
local ticks={}
local function quote(value)
 return '"'..tostring(value):gsub('[%z\1-\31\\"]',function(c)
  local escapes={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
  return escapes[c] or string.format('\\u%04x',string.byte(c))
 end)..'"'
end
local function emit(event,phase,reason,paused)
 local fields='"event":'..quote(event)..',"token":'..quote(config.token)..',"role":'..quote(role)
 if phase then fields=fields..',"phase":'..quote(phase)..',"reason":'..quote(reason) end
 if event=='setup-started' then fields=fields..',"paused":'..(type(paused)=='boolean'and tostring(paused)or'null') end
 print('[QUEUE_PREFLIGHT] {'..fields..'}')
end
function P.fail(phase,reason)
 if failed then return end
 failed=true;running=false;emit('failed',phase,tostring(reason))
end
function P.complete()
 if failed or ready then return end
 ready=true;emit('ready')
end
local function grant(name)
 local file=getFileReader(name,false)
 if not file then return false end
 local value=file:readLine();file:close()
 if value~=config.token then P.fail('preflight','fixture release token differs from prepared run');return false end
 return true
end
function P.onGameStart(events,fn)
 assert(type(fn)=='function','fixture start callback missing')
 -- Session-owned event buses already run below the admitted native callbacks.
 if events~=Events then events.OnGameStart.Add(fn);return end
 Events.OnGameStart.Add(function(...)
  if failed then return end
  -- A later owned reconnect reuses the already admitted fixture lifecycle.
  if running then fn(...);return end
  starts[#starts+1]={fn=fn,args={...}}
 end)
end
function P.onTick(events,fn)
 assert(type(fn)=='function','fixture tick callback missing')
 if events~=Events then events.OnTick.Add(fn);return end
 if ticks[fn] then return end
 local wrapped=function(...) if running and not failed then fn(...) end end
 ticks[fn]=wrapped;Events.OnTick.Add(wrapped)
end
function P.removeTick(events,fn)
 if events~=Events then events.OnTick.Remove(fn);return end
 if ticks[fn] then Events.OnTick.Remove(ticks[fn]);ticks[fn]=nil end
end
-- The coordinator must admit startup callbacks even when native SP starts
-- paused. Gameplay callbacks above still require a genuine native OnTick.
Events.OnTickEvenPaused.Add(function()
 if failed or not ready then return end
 if not setupStarted and grant('queue-preflight-setup.txt') then
  setupStarted=true
  local paused=nil
  if type(isGamePaused)=='function' then
   local ok,value=pcall(isGamePaused)
   if ok and type(value)=='boolean' then paused=value end
  end
  emit('setup-started',nil,nil,paused)
  for _,start in ipairs(starts) do
   local ok,reason=pcall(start.fn,unpack(start.args))
   if not ok then P.fail('fixture-setup',reason);return end
  end
  setup=true;emit('setup-ready')
 end
 if setup and not running and grant('queue-preflight-release.txt') then running=true end
end)
return P
