-- Explicit fixture boundaries; failures never classify themselves from message text.
local JSON=require 'QueueHealthEvents'
local config=require 'QueuePreflightConfig'
local M={}
function M.new(suite,role)
 assert(type(suite)=='string'and suite~=''and type(config.token)=='string'and config.token~='',
  'case stage suite/token missing')
 local allowed=false
 for _,actor in ipairs(config.roles)do if actor==role then allowed=true end end
 assert(allowed,'case stage role is not required')
 local self={}
 local current,stage,terminal
 local function emit(status,reason)
  local row={token=config.token,suite=suite,role=role,case=current,stage=stage,status=status}
  if reason then row.reason=reason end
  print('[QUEUE_CASE_STAGE] '..JSON.encode(row))
 end
 function self:setup(identifier)
  assert(not current or terminal=='passed','previous case stage is not complete')
  assert(type(identifier)=='string'and identifier~='','case stage ID missing')
  current,stage,terminal=identifier,'setup',nil;emit('started')
 end
 function self:gameplay()
  assert(current and stage=='setup'and not terminal,'case gameplay requires active setup')
  stage='gameplay';emit('started')
 end
 function self:cleanup()
  assert(current and stage=='gameplay'and not terminal,'case cleanup requires active gameplay')
  stage='cleanup';emit('started')
 end
 function self:complete()
  assert(current and stage=='cleanup'and not terminal,'case completion requires active cleanup')
  terminal='passed';emit('passed')
 end
 function self:fail(reason)
  if not current or terminal then return end
  local message=tostring(reason)
  assert(message:match('%S'),'case stage failure reason missing')
  terminal='failed';emit('failed',message)
 end
 return self
end
return M
