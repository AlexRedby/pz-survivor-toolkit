local config=require 'QueueTestSelection'
assert(config.kind=='sp' and config.clients==1,'equipment requires one actual SP client')
assert(config.mode=='native' or config.mode=='toolkit','invalid equipment mode')
assert(type(config.languages)=='table' and #config.languages==1
 and (config.languages[1]=='EN' or config.languages[1]=='RU'),'equipment language must be EN or RU')
local canonical={'hands-chain','waiting-cancel','bag-capacity'}
local known,selected,seen={},{},{}
for _,id in ipairs(canonical) do known[id]=true end
assert(type(config.cases)=='table' and #config.cases>0,'equipment cases missing')
for _,id in ipairs(config.cases) do
 assert(known[id] and not seen[id],'unknown/duplicate equipment case '..tostring(id));seen[id]=true
end
for _,id in ipairs(canonical) do if seen[id] then selected[#selected+1]=id end end
return {cases=selected,mode=config.mode,language=config.languages[1]}
