local selection=require 'QueueTestSelection'
local Cases=require 'QueueHealthCases'
assert(selection.kind=='sp' or selection.kind=='mp','invalid medical execution kind')
assert(selection.mode=='toolkit' or selection.mode=='native','invalid medical execution mode')
assert(type(selection.cases)=='table' and #selection.cases>0,'medical selection must name cases')
local byID,seen,selected={},{},{}
for _,spec in ipairs(Cases) do byID[spec.id]=spec end
for _,id in ipairs(selection.cases) do
 assert(type(id)=='string' and byID[id] and not seen[id],'unknown/duplicate medical case '..tostring(id))
 selected[#selected+1]=byID[id];seen[id]=true
end
local function skipReason(spec,username)
 if spec.mini and selection.kind~='sp' then return 'MiniHealthPlus treats the local player; this fixture uses a remote MP patient' end
 if spec.mini and not (getActivatedMods and getActivatedMods():contains('MiniHealthPlus')) then return 'requires MiniHealthPlus' end
 if selection.kind=='sp' and spec.remote then return 'requires two actual online players' end
 if selection.mode=='native' and (spec.cancel or spec.move or spec.guard or spec.bag or spec.remote and spec.remote~='removed') then
  return 'requires toolkit queue operation or guard API'
 end
 if spec.id=='remoteRemoved' and username=='client1' then
  return 'EN doctor keeps actual patient connected; RU doctor exercises real disconnect'
 end
end
return {kind=selection.kind,mode=selection.mode,cases=selected,skipReason=skipReason}
