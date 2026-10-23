local config=require 'QueueTestSelection'
assert((config.kind=='sp' or config.kind=='mp') and config.clients==1,'equipment requires one actual client')
assert(config.mode=='native' or config.mode=='toolkit','invalid equipment mode')
assert(type(config.languages)=='table' and #config.languages==1
 and (config.languages[1]=='EN' or config.languages[1]=='RU'),'equipment language must be EN or RU')
if type(config.cases)=='table' and config.cases[1]=='cart-pickup' then
 assert(config.kind=='mp' and #config.cases==1,'cart-pickup requires standalone MP equipment selection')
 return {cases=config.cases,mode=config.mode,kind=config.kind,language=config.languages[1]}
end
local canonical={'hands-chain','waiting-cancel','bag-capacity','clothing-chain','hotbar-chain','belt-knife','belt-hammer','floor-pickup','bulk-pickup','bulk-waiting-cancel','bulk-mixed','tidy-hands','tidy-floor','tidy-empty-hands','tidy-group','tidy-multigroup','tidy-clothing','tidy-clothing-replace','tidy-headwear-hat-exclusive','tidy-headwear-full-hat-exclusive','tidy-clothing-remove','tidy-clothing-overlap','tidy-clothing-overlap-primary','tidy-clothing-overlap-both','tidy-clothing-held-primary','tidy-clothing-held-secondary','tidy-clothing-held-both','tidy-headwear-hat-remove','tidy-headwear-full-hat-remove','tidy-headwear-hat-restore','tidy-headwear-full-hat-restore','tidy-headwear-mohawk-hat-restore','tidy-headwear-mohawk-hat-remove','tidy-headwear-mohawk-full-hat-restore','tidy-headwear-mohawk-full-hat-remove','tidy-watch-digital-restore','tidy-watch-digital-remove','tidy-watch-classic-restore','tidy-watch-classic-remove','tidy-watch-overlap-primary','tidy-watch-overlap-secondary','tidy-watch-overlap-both','tidy-watch-held-primary','tidy-watch-held-secondary','tidy-watch-held-both','tidy-watch-ringing-restore','tidy-watch-ringing-remove','tidy-watch-ringing-overlap-both','tidy-watch-ringing-held-both','tidy-hotbar','tidy-hotbar-holster-left','tidy-hotbar-holster-right','tidy-hotbar-normal-left','tidy-hotbar-normal-right'}
local known,selected,seen={},{},{}
for _,id in ipairs(canonical) do known[id]=true end
assert(type(config.cases)=='table' and #config.cases>0,'equipment cases missing')
for _,id in ipairs(config.cases) do
 assert(known[id] and not seen[id],'unknown/duplicate equipment case '..tostring(id));seen[id]=true
end
for _,id in ipairs(canonical) do if seen[id] then selected[#selected+1]=id end end
return {cases=selected,mode=config.mode,kind=config.kind,language=config.languages[1],options=config.options or {}}
