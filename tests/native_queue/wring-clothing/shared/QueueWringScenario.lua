-- Test-only recipe shared by live observations and source-backed models.
-- It describes expected producers; it never creates or executes game actions.
local S={}
function S.producer(mode,role)
 assert(mode=='native'or mode=='toolkit','unknown wring scenario mode')
 assert(role=='front'or role=='cancelled'or role=='target'or role=='tail','unknown wring scenario role')
 local result={}
 if role=='target'or role=='cancelled'then
  if mode=='toolkit'then result[#result+1]='ISQueueActionsAction'end
  result[#result+1]='ISInventoryTransferAction'
 end
 result[#result+1]='ISWringClothing'
 return result
end
function S.plan(mode)
 local result={}
 for _,role in ipairs({'front','cancelled','target','tail'})do
  for _,kind in ipairs(S.producer(mode,role))do result[#result+1]={name=role,type=kind}end
 end
 return result
end
function S.checkProducer(actions,mode,role)
 local expected=S.producer(mode,role)
 assert(#actions==#expected,'carried wring producer length differs for '..role)
 for index,kind in ipairs(expected)do
  assert(actions[index].Type==kind,'carried wring producer differs for '..role..' at '..index)
 end
end
function S.check(commands,mode)
 local expected=S.plan(mode)
 assert(#commands==#expected,'carried wring scenario length differs')
 for index,wanted in ipairs(expected)do local actual=commands[index]
  assert(actual.name==wanted.name and actual.type==wanted.type,'carried wring scenario differs at '..index)
 end
end
return S
