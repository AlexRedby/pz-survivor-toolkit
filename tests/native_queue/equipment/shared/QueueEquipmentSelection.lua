local config=require 'QueueTestSelection'
assert((config.kind=='sp' or config.kind=='mp') and config.clients==1,'equipment requires one actual client')
assert(config.mode=='native' or config.mode=='toolkit','invalid equipment mode')
assert(type(config.languages)=='table' and #config.languages==1
 and (config.languages[1]=='EN' or config.languages[1]=='RU'),'equipment language must be EN or RU')
if type(config.cases)=='table' and config.cases[1]=='cart-pickup' then
 assert(config.kind=='mp' and #config.cases==1,'cart-pickup requires standalone MP equipment selection')
 return {cases=config.cases,mode=config.mode,kind=config.kind,language=config.languages[1]}
end
local canonical={'hands-chain','waiting-cancel','bag-capacity','clothing-chain','hotbar-chain','floor-pickup','bulk-pickup','bulk-waiting-cancel','bulk-mixed','tidy-hands','tidy-floor','tidy-empty-hands'}
local known,selected,seen={},{},{}
for _,id in ipairs(canonical) do known[id]=true end
assert(type(config.cases)=='table' and #config.cases>0,'equipment cases missing')
for _,id in ipairs(config.cases) do
 assert(known[id] and not seen[id],'unknown/duplicate equipment case '..tostring(id));seen[id]=true
end
for _,id in ipairs(canonical) do if seen[id] then selected[#selected+1]=id end end
return {cases=selected,mode=config.mode,kind=config.kind,language=config.languages[1]}
