local source=ProjectRoot..'/tests/native_queue/contributions/wooden_cart_motion/scene-selection.lua'
CartMotionConfig=nil
CartLabSelectScenes=nil
assert(not pcall(dofile,source) and CartLabSelectScenes==nil,'scene selector loaded without config')
for _,disposable in ipairs({false,1,'true'}) do
 CartMotionConfig={disposable=disposable}
 assert(not pcall(dofile,source) and CartLabSelectScenes==nil,'scene selector accepted unsafe disposable flag')
end
CartMotionConfig={disposable=true}
dofile(source)
local cases={{name='alpha',steps={1}},{name='beta',steps={2}},{name='gamma',steps={3}}}
assert(CartLabSelectScenes(cases)==cases,'full default must preserve the exact original cases table')
CartMotionConfig.scenes={'gamma','alpha'}
local selected=CartLabSelectScenes(cases)
assert(selected~=cases and #selected==2 and selected[1]==cases[1] and selected[2]==cases[3],
 'selection must preserve original bank order and exact case references')
assert(selected[1].steps==cases[1].steps and #cases==3,'selection copied or mutated original records')
CartMotionConfig.scenes={'gamma','beta','alpha'}
selected=CartLabSelectScenes(cases)
assert(#selected==3 and selected[1]==cases[1] and selected[2]==cases[2] and selected[3]==cases[3],
 'explicit full selection must preserve bank order and record references')
CartMotionConfig.scenes={'gamma'}
assert(CartLabSelectScenes(cases)[1]==cases[3],'single exact scene selection failed')
local oldNext=next
next=nil
for _,invalid in ipairs({false,true,1,'alpha',{}, {'alpha','alpha'}, {'missing'}, {'alpha','missing'},
 {1}, {false}, {''}, {'ALPHA'}, {' alpha'}, {[1]='alpha',[3]='gamma'}, {[2]='beta'},
 {[0]='alpha',[1]='beta'}, {[1]='alpha',[1.5]='gamma'}, {[1]='alpha',extra='gamma'}}) do
 CartMotionConfig.scenes=invalid
 assert(not pcall(CartLabSelectScenes,cases),'invalid scene filter was accepted')
end
CartMotionConfig.scenes={'beta','alpha'}
selected=CartLabSelectScenes(cases)
assert(#selected==2 and selected[1]==cases[1] and selected[2]==cases[2],
 'selector requires next even though stock Kahlua exposes pairs')
next=oldNext
CartMotionConfig.scenes=nil
assert(CartLabSelectScenes(cases)==cases,'clearing debug selection did not restore full bank identity')
print('PASS cart scene selection: config guards, exact references/order/full identity and strict dense unique filters')
